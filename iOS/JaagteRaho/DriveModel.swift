import Foundation
import SwiftUI
import Combine
import UIKit

@MainActor
final class DriveModel: ObservableObject {
    enum Phase { case ready, calibration, driving }
    @Published var phase: Phase = .ready
    @Published private(set) var snapshot = FatigueSnapshot()
    @Published private(set) var calibration = CalibrationCollector()
    @Published private(set) var metrics: FaceMetrics?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var demo = false
    @Published var demoEyesClosed = false
    @Published var language: VoiceLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "voiceLanguage") }
    }
    @Published var cloudEnabled: Bool {
        didSet { UserDefaults.standard.set(cloudEnabled, forKey: "cloudEnabled") }
    }
    @Published var serverURL: String
    @Published private(set) var serverStatus: String = "Online voice not connected"
    @Published private(set) var fleetConfigured = false
    @Published private(set) var paused = false
    let camera = CameraService()
    let voice = VoiceService()
    let store = EventStore()
    let journey = JourneyService()
    let music = MusicService()
    lazy var companion = CompanionService(voice: voice, backend: { [weak self] in self?.backend },
        online: { [weak self] in self?.cloudEnabled ?? true },
        language: { [weak self] in self?.language ?? .hindi },
        available: { [weak self] in
            guard let self else { return false }
            return !self.paused && self.phase != .calibration &&
                self.snapshot.state != .critical && self.snapshot.state != .checkIn
        })
    private var engine: FatigueEngine?
    private var timer: Timer?
    private var demoTimer: Timer?
    private var tripStarted: Double?
    private var criticalRecorded = false
    private var cloudTask: Task<Void, Never>?
    private var flushAt: Double = 0
    private var pairingToken = KeychainToken.read()

    var backend: BackendClient? {
        guard let url = URL(string: serverURL), ["http", "https"].contains(url.scheme), url.host != nil,
              !pairingToken.isEmpty else { return nil }
        return BackendClient(baseURL: url, token: pairingToken)
    }
    init() {
        language = VoiceLanguage(rawValue: UserDefaults.standard.string(forKey: "voiceLanguage") ?? "hi") ?? .hindi
        cloudEnabled = UserDefaults.standard.object(forKey: "cloudEnabled") as? Bool ?? true
        serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        camera.onMetrics = { [weak self] metrics in self?.receive(metrics) }
        camera.onInterruption = { [weak self] in self?.markUnavailable() }
        voice.onAcknowledgment = { [weak self] text in self?.acknowledge(text) }
        voice.onWillSpeak = { [weak self] in self?.music.pauseForVoice() }
        #if DEBUG
        if let url = ProcessInfo.processInfo.environment["SAARTHI_BACKEND_URL"],
           let token = ProcessInfo.processInfo.environment["SAARTHI_BACKEND_TOKEN"], token.count >= 24 {
            serverURL = url; pairingToken = token
            Task { await connect(url: url, token: token) }
        }
        #endif
    }
    func startLive() {
        guard phase == .ready else { return }
        prepare(demo: false); phase = .calibration
        camera.start(); startWatchdog()
        Task { await voice.requestPermissions(language: language) }
    }
    func startDemo() {
        guard phase == .ready else { return }
        prepare(demo: true); phase = .driving
        engine = FatigueEngine(calibration: .demo)
        tripStarted = ProcessInfo.processInfo.systemUptime
        startWatchdog(); startDemoFrames()
        Task { await voice.requestPermissions(language: language) }
    }
    private func prepare(demo: Bool) {
        companion.stop()
        journey.startSession(simulated: demo)
        self.demo = demo; demoEyesClosed = false; paused = false; metrics = nil
        snapshot = FatigueSnapshot(); calibration = CalibrationCollector()
        criticalRecorded = false; tripStarted = nil; elapsed = 0; flushAt = 0
        UIApplication.shared.isIdleTimerDisabled = true
    }
    private func receive(_ sample: FaceMetrics) {
        guard !paused, phase != .ready else { return }
        metrics = sample
        if phase == .calibration {
            calibration.ingest(sample)
            if let result = calibration.result {
                engine = FatigueEngine(calibration: result)
                phase = .driving; tripStarted = sample.timestamp
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        } else if var engine {
            let before = snapshot.state
            snapshot = engine.ingest(sample); self.engine = engine
            handleTransition(from: before)
        }
    }
    private func handleTransition(from before: MonitoringState) {
        if snapshot.state == .critical && before != .critical {
            companion.interrupt(); journey.record(alarm: true)
            cloudTask?.cancel(); cloudTask = nil
            voice.startAlarm()
            if !criticalRecorded {
                store.record(TripEvent(trigger: snapshot.trigger ?? .prolongedClosure, simulated: demo))
                criticalRecorded = true
                Task { await store.flush(using: backend) }
            }
        } else if snapshot.state == .checkIn && before != .checkIn && before != .trackingUnavailable {
            companion.interrupt(); journey.record(checkIn: true)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            voice.playPrompt("checkin", language: language) { [weak self] in
                guard let self, self.phase == .driving, !self.paused,
                      self.snapshot.state != .critical else { return }
                self.engine?.promptFinished(at: ProcessInfo.processInfo.systemUptime)
                self.voice.listen(language: self.language)
            }
        }
    }
    func acknowledgeDemo() {
        guard demo else { return }
        acknowledge(language == .english ? "yes" : "हाँ")
    }
    private func acknowledge(_ transcript: String) {
        let now = ProcessInfo.processInfo.systemUptime
        guard engine?.acknowledge(at: now) == true, let engine else { return }
        snapshot = engine.snapshot
        voice.playPrompt("acknowledged", language: language)
        // Only the selected, short transcript is sent after an acknowledged check-in.
        guard cloudEnabled, let backend else { return }
        cloudTask?.cancel()
        let selectedLanguage = language
        cloudTask = Task { [weak self] in
            do {
                let text = try await backend.conversation(transcript, language: selectedLanguage)
                guard !Task.isCancelled, let self, self.snapshot.state == .monitoring,
                      self.phase == .driving, !self.paused else { return }
                let data = try await backend.speech(text, language: selectedLanguage)
                guard !Task.isCancelled, self.snapshot.state == .monitoring, !self.paused else { return }
                self.voice.playCloudAudio(data)
            } catch { /* Bundled acknowledgment already played. */ }
        }
    }
    private func startWatchdog() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    private func tick() {
        guard phase != .ready else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let tripStarted { elapsed = now - tripStarted }
        if var engine {
            let before = snapshot.state
            snapshot = engine.tick(at: now); self.engine = engine
            handleTransition(from: before)
        }
        if now - flushAt > 15 {
            flushAt = now
            Task { await store.flush(using: backend) }
            camera.reduceForThermals()
        }
    }
    private func startDemoFrames() {
        demoTimer?.invalidate()
        demoTimer = Timer.scheduledTimer(withTimeInterval: 1 / 12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.paused else { return }
                self.receive(FaceMetrics(timestamp: ProcessInfo.processInfo.systemUptime,
                    leftEAR: self.demoEyesClosed ? 0.05 : 0.3,
                    rightEAR: self.demoEyesClosed ? 0.05 : 0.3, inferenceMilliseconds: 0))
            }
        }
    }
    private func markUnavailable() {
        guard phase != .ready else { return }
        let time = ProcessInfo.processInfo.systemUptime
        if var engine { snapshot = engine.ingest(.missing(at: time)); self.engine = engine }
    }
    func suspend() {
        journey.suspend(); companion.interrupt(); music.pauseForVoice()
        guard phase != .ready else { return }
        paused = true; markUnavailable(); camera.stop(); voice.stopListening()
        cloudTask?.cancel(); cloudTask = nil
        // Keep a critical event latched. Camera monitoring is explicitly unavailable in background.
    }
    func resume() {
        journey.resume()
        guard phase != .ready, paused else { return }
        paused = false
        if !demo { camera.start() }
        if snapshot.state == .critical { voice.startAlarm() }
    }
    /// Called only from the parked/end-session confirmation.
    func endSession() {
        companion.stop(); journey.endSession(); music.pauseForVoice()
        timer?.invalidate(); timer = nil; demoTimer?.invalidate(); demoTimer = nil
        cloudTask?.cancel(); cloudTask = nil
        camera.stop(); voice.stopAll(); engine = nil; metrics = nil
        phase = .ready; snapshot = FatigueSnapshot(); paused = false; demoEyesClosed = false
        UIApplication.shared.isIdleTimerDisabled = false
    }
    func connect(url: String, token: String) async {
        guard let parsed = URL(string: url), let host = parsed.host,
              parsed.user == nil, parsed.password == nil,
              parsed.scheme == "https" || (parsed.scheme == "http" && (host == "localhost" || host.hasSuffix(".local") || host == "127.0.0.1"))
        else { serverStatus = "Use HTTPS, or a local Mac .local address for the demo."; return }
        guard token.count >= 24 else { serverStatus = "Enter the backend pairing token."; return }
        let candidate = BackendClient(baseURL: parsed, token: token)
        do {
            let status = try await candidate.status()
            guard KeychainToken.save(token) else { serverStatus = "Pairing token could not be saved securely."; return }
            pairingToken = token
            serverURL = url; UserDefaults.standard.set(url, forKey: "serverURL")
            fleetConfigured = status.fleetConfigured
            serverStatus = status.speechConfigured ? "Smallest.ai online voice connected" : "Connected · speech provider not configured"
            await store.flush(using: candidate)
        } catch { serverStatus = "Could not connect. Check the Mac backend and Wi-Fi." }
    }
    func testVoice() { voice.playPrompt("checkin", language: language) }
    var elapsedLabel: String {
        let seconds = Int(elapsed)
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
}
