import AVFoundation
import Speech
import UIKit
import Combine

@MainActor
final class VoiceService: NSObject, ObservableObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    @Published private(set) var status = "Voice ready"
    @Published private(set) var listening = false
    @Published private(set) var transcript = ""
    @Published private(set) var offlineRecognitionAvailable = false
    @Published private(set) var audioWarning: String?
    private let synthesizer = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private var player: AVAudioPlayer?
    private var alarm: AVAudioPlayer?
    private var recognition: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var completion: (() -> Void)?
    private var tapInstalled = false
    private var haptics: Timer?
    private var listenGeneration = 0
    private var alarmActive = false
    private var interruptionObserver: NSObjectProtocol?
    private var conversationReply: ((String) -> Void)?
    private var conversationTimeout: Task<Void, Never>?
    private var currentUtterance: AVSpeechUtterance?
    var onAcknowledgment: ((String) -> Void)?
    var onWillSpeak: (() -> Void)?

    override init() {
        super.init(); synthesizer.delegate = self
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
                guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                Task { @MainActor in
                    guard let self else { return }
                    if type == .began {
                        self.stopListening(); self.alarm?.pause()
                        self.audioWarning = "Audio interrupted · monitoring status remains visible."
                    } else if self.alarmActive { self.startAlarm() }
                }
            }
    }
    func requestPermissions(language: VoiceLanguage) async {
        let auth = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        let mic = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.locale))
        offlineRecognitionAvailable = auth == .authorized && mic && recognizer?.supportsOnDeviceRecognition == true
        status = offlineRecognitionAvailable ? "Offline voice replies ready" : "Voice alerts ready · offline replies unavailable"
    }
    private func configureAudio() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .duckOthers])
        try session.setActive(true)
        audioWarning = session.outputVolume < 0.25 ? "Raise the phone volume before driving." : nil
    }
    func playPrompt(_ name: String, language: VoiceLanguage, completion: (() -> Void)? = nil) {
        guard !alarmActive else { completion?(); return }
        onWillSpeak?()
        stopListening(); cancelSpeech()
        self.completion = completion
        status = name == "checkin" ? "Checking in with you…" : "Speaking…"
        do {
            try configureAudio()
            if let url = Bundle.main.url(forResource: "\(language.rawValue)_\(name)", withExtension: "wav", subdirectory: "Audio") {
                let next = try AVAudioPlayer(contentsOf: url)
                next.delegate = self; player = next
                guard next.play() else { throw VoiceError.playback }
            } else {
                let utterance = AVSpeechUtterance(string: language.text(for: name))
                currentUtterance = utterance
                utterance.voice = AVSpeechSynthesisVoice(language: language.locale)
                utterance.rate = 0.47; synthesizer.speak(utterance)
            }
        } catch {
            audioWarning = "Audio unavailable. Check the speaker and volume."
            finishPlayback()
        }
    }
    func playCloudAudio(_ data: Data, completion: (() -> Void)? = nil) {
        guard !alarmActive else { return }
        onWillSpeak?()
        stopListening(); cancelSpeech()
        self.completion = completion
        do {
            try configureAudio()
            let next = try AVAudioPlayer(data: data); next.delegate = self; player = next
            if !next.play() { audioWarning = "Voice playback unavailable."; finishPlayback() }
            else { status = "Your co-pilot is speaking…" }
        } catch { audioWarning = "Voice playback unavailable."; finishPlayback() }
    }
    func listen(language: VoiceLanguage) {
        startListening(language: language, conversation: nil)
    }
    func listenForConversation(language: VoiceLanguage, reply: @escaping (String) -> Void) {
        startListening(language: language, conversation: reply)
    }
    private func startListening(language: VoiceLanguage, conversation: ((String) -> Void)?) {
        guard !alarmActive else { return }
        stopListening()
        guard offlineRecognitionAvailable,
              let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.locale)),
              recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else {
            status = "Offline replies unavailable · alarm still active"
            conversation?("")
            return
        }
        conversationReply = conversation
        let generation = listenGeneration
        let audioRequest = SFSpeechAudioBufferRecognitionRequest()
        audioRequest.requiresOnDeviceRecognition = true
        audioRequest.shouldReportPartialResults = true
        audioRequest.contextualStrings = ["हाँ", "ठीक है", "ਹਾਂ", "ਠੀਕ ਹੈ", "yes", "okay"]
        request = audioRequest; transcript = ""
        do {
            try configureAudio()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw VoiceError.microphone }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                audioRequest.append(buffer)
            }
            tapInstalled = true
            engine.prepare(); try engine.start()
            listening = true; status = conversation == nil ? "Listening for your acknowledgment" : "Listening · speak to Ollie"
            if conversation != nil {
                conversationTimeout = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 12_000_000_000)
                    guard !Task.isCancelled else { return }
                    self?.finishConversation()
                }
            }
            recognition = recognizer.recognitionTask(with: audioRequest) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, generation == self.listenGeneration else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        if self.conversationReply != nil {
                            if result.isFinal { self.finishConversation() }
                        } else if language.acknowledges(self.transcript) {
                            let text = self.transcript; self.stopListening(); self.onAcknowledgment?(text)
                        } else if result.isFinal { self.stopListening() }
                    }
                    if error != nil {
                        if self.conversationReply != nil { self.finishConversation(); return }
                        self.stopListening(); self.status = "Could not hear a reply · checking your response"
                    }
                }
            }
        } catch {
            if conversationReply != nil { finishConversation(); return }
            stopListening(); status = "Microphone unavailable · alarm still active"
        }
    }
    func finishConversation() {
        let reply = conversationReply
        let text = String(transcript.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        stopListening(); reply?(text)
    }
    func speak(_ text: String, language: VoiceLanguage, completion: (() -> Void)? = nil) {
        guard !alarmActive else { return }
        onWillSpeak?(); stopListening(); cancelSpeech()
        self.completion = completion
        do {
            try configureAudio()
            let utterance = AVSpeechUtterance(string: text)
            currentUtterance = utterance
            utterance.voice = AVSpeechSynthesisVoice(language: language.locale)
            utterance.rate = 0.47; status = "Ollie is speaking…"
            synthesizer.speak(utterance)
        } catch { audioWarning = "Voice playback unavailable."; finishPlayback() }
    }
    func stopListening() {
        conversationTimeout?.cancel(); conversationTimeout = nil; conversationReply = nil
        listenGeneration += 1
        recognition?.cancel(); recognition = nil
        request?.endAudio(); request = nil
        if engine.isRunning { engine.stop() }
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        listening = false
    }
    func startAlarm() {
        guard !alarmActive || alarm?.isPlaying != true else { return }
        onWillSpeak?()
        alarmActive = true; stopListening(); cancelSpeech()
        status = "Stop somewhere safe and rest"
        do {
            try configureAudio()
            guard let url = Bundle.main.url(forResource: "alarm", withExtension: "wav", subdirectory: "Audio") else { throw VoiceError.playback }
            let next = try AVAudioPlayer(contentsOf: url)
            next.numberOfLoops = -1; next.volume = 1; alarm = next
            guard next.play() else { throw VoiceError.playback }
        } catch { audioWarning = "Alarm audio unavailable. Stop safely and check the speaker." }
        let generator = UINotificationFeedbackGenerator(); generator.notificationOccurred(.error)
        if haptics == nil {
            haptics = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { _ in
                Task { @MainActor in UINotificationFeedbackGenerator().notificationOccurred(.error) }
            }
        }
    }
    func stopAll() {
        alarmActive = false; alarm?.stop(); alarm = nil; haptics?.invalidate(); haptics = nil
        stopListening(); cancelSpeech(); status = "Voice ready"
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    private func cancelSpeech() {
        currentUtterance = nil
        completion = nil; player?.delegate = nil; player?.stop(); player = nil
        synthesizer.stopSpeaking(at: .immediate)
    }
    private func finishPlayback() {
        player = nil
        let callback = completion; completion = nil
        status = "Voice ready"; callback?()
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.finishPlayback()
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.currentUtterance === utterance else { return }
            self.currentUtterance = nil; self.finishPlayback()
        }
    }
    private enum VoiceError: Error { case playback, microphone }
}
