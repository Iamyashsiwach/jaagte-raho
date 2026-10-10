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
    @Published private(set) var enrollmentReady = false
    @Published private(set) var enrollmentVoiceStatus = "Ollie will guide your eye setup"
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
    private var enrollmentVoiceTask: Task<Void, Never>?
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
        }
        #endif
        if let pairedBackend = backend {
            Task { await connect(url: pairedBackend.baseURL.absoluteString, token: pairedBackend.token) }
        }
    }
    func startLive() {
        guard phase == .ready else { return }
        prepare(demo: false); phase = .calibration
        camera.start(); startWatchdog()
        speakEnrollmentStep()
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
        enrollmentReady = false
        criticalRecorded = false; tripStarted = nil; elapsed = 0; flushAt = 0
        UIApplication.shared.isIdleTimerDisabled = true
    }
    private func receive(_ sample: FaceMetrics) {
        guard !paused, phase != .ready else { return }
        metrics = sample
        if phase == .calibration {
            let before = calibration.phase
            calibration.ingest(sample)
            refreshEnrollmentReady()
            if calibration.phase != before {
                speakEnrollmentStep()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        } else if var engine {
            let before = snapshot.state
            snapshot = engine.ingest(sample); self.engine = engine
            handleTransition(from: before)
        }
    }
    private func refreshEnrollmentReady() {
        let ready = !paused && camera.running &&
            calibration.result?.readyToMonitor(metrics, at: ProcessInfo.processInfo.systemUptime) == true
        if enrollmentReady != ready { enrollmentReady = ready }
    }
    func beginMonitoring() {
        refreshEnrollmentReady()
        guard phase == .calibration, enrollmentReady, let result = calibration.result,
              let sample = metrics else { return }
        enrollmentVoiceTask?.cancel(); enrollmentVoiceTask = nil
        voice.stopAll()
        var detector = FatigueEngine(calibration: result)
        snapshot = detector.ingest(sample); engine = detector
        tripStarted = ProcessInfo.processInfo.systemUptime; phase = .driving
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    func restartEnrollment() {
        guard phase == .calibration, !paused else { return }
        calibration = CalibrationCollector(); metrics = nil; enrollmentReady = false
        camera.start(); speakEnrollmentStep()
    }
    func speakEnrollmentStep() {
        guard phase == .calibration, !paused else { return }
        enrollmentVoiceTask?.cancel(); voice.stopAll()
        let step = calibration.phase, selectedLanguage = language
        let text = CompanionContent.enrollment(step, language: selectedLanguage)
        let connectedBackend = cloudEnabled ? backend : nil
        enrollmentVoiceTask = Task { [weak self] in
            guard let self else { return }
            if let connectedBackend {
                self.enrollmentVoiceStatus = "Preparing Ollie's online voice…"
                do {
                    let audio = try await connectedBackend.speech(text, language: selectedLanguage)
                    guard !Task.isCancelled, self.phase == .calibration, !self.paused,
                          self.calibration.phase == step else { return }
                    self.enrollmentVoiceStatus = "Ollie's online voice · Smallest.ai"
                    self.voice.playCloudAudio(audio); return
                } catch { /* The step remains available through device speech. */ }
            }
            guard !Task.isCancelled, self.phase == .calibration, !self.paused,
                  self.calibration.phase == step else { return }
            self.enrollmentVoiceStatus = "Ollie's device voice · \(selectedLanguage.name)"
            self.voice.speak(text, language: selectedLanguage)
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
        if phase == .calibration {
            if metrics.map({ now - $0.timestamp > 0.75 }) ?? true {
                calibration.ingest(.missing(at: now))
            }
            refreshEnrollmentReady()
        }
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
        if phase == .calibration {
            metrics = nil; enrollmentReady = false
            calibration.ingest(.missing(at: time))
        }
        if var engine { snapshot = engine.ingest(.missing(at: time)); self.engine = engine }
    }
    func suspend() {
        journey.suspend(); companion.interrupt(); music.pauseForVoice()
        enrollmentVoiceTask?.cancel(); enrollmentVoiceTask = nil
        guard phase != .ready else { return }
        paused = true; markUnavailable(); camera.stop(); voice.stopListening()
        if phase == .calibration { voice.stopAll() }
        cloudTask?.cancel(); cloudTask = nil
        // Keep a critical event latched. Camera monitoring is explicitly unavailable in background.
    }
    func resume() {
        journey.resume()
        guard phase != .ready, paused else { return }
        paused = false
        if !demo { camera.start() }
        if phase == .calibration { speakEnrollmentStep() }
        if snapshot.state == .critical { voice.startAlarm() }
    }
    /// Called only from the parked/end-session confirmation.
    func endSession() {
        companion.stop(); journey.endSession(); music.pauseForVoice()
        timer?.invalidate(); timer = nil; demoTimer?.invalidate(); demoTimer = nil
        cloudTask?.cancel(); cloudTask = nil
        enrollmentVoiceTask?.cancel(); enrollmentVoiceTask = nil
        camera.stop(); voice.stopAll(); engine = nil; metrics = nil
        phase = .ready; snapshot = FatigueSnapshot(); paused = false; demoEyesClosed = false
        enrollmentReady = false
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
