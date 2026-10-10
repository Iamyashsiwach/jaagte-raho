import Foundation
import Combine

struct CompanionMessage: Identifiable {
    let id = UUID()
    let text: String
    let driver: Bool
}

@MainActor
final class CompanionService: ObservableObject {
    @Published private(set) var messages: [CompanionMessage] = []
    @Published private(set) var busy = false
    @Published private(set) var source = "Ready to talk · online voice preferred"
    @Published private(set) var conversationSource = "Ollie online agent · Smallest.ai Electron when paired"
    @Published var handsFree = false
    @Published var assistant = "saarthi" {
        didSet { UserDefaults.standard.set(assistant, forKey: "companionAssistant") }
    }
    private let voice: VoiceService
    private let backend: () -> BackendClient?
    private let online: () -> Bool
    private let language: () -> VoiceLanguage
    private let available: () -> Bool
    private var task: Task<Void, Never>?
    private var quizPending = false
    private var generation = 0
    init(voice: VoiceService, backend: @escaping () -> BackendClient?, online: @escaping () -> Bool,
         language: @escaping () -> VoiceLanguage, available: @escaping () -> Bool) {
        self.voice = voice; self.backend = backend; self.online = online
        self.language = language; self.available = available
        assistant = UserDefaults.standard.string(forKey: "companionAssistant") ?? "saarthi"
    }
    func greet() { say(CompanionContent.greeting(language())) }
    func story() { quizPending = false; say(CompanionContent.story(language())) }
    func quiz() { quizPending = true; handsFree = true; say(CompanionContent.quiz(language())) }
    func listen() {
        guard available(), !busy else { return }
        generation += 1
        let current = generation
        task?.cancel(); busy = true
        task = Task { [weak self] in
            guard let self else { return }
            let selectedLanguage = self.language()
            if self.online(), let backend = self.backend(), selectedLanguage != .punjabi {
                self.source = "Preparing microphone · Smallest.ai Pulse"
                let allowed = await self.voice.requestMicrophonePermission()
                guard !Task.isCancelled, current == self.generation, self.available() else { return }
                self.busy = false
                guard allowed else {
                    self.handsFree = false; self.source = "Allow Microphone in iPhone Settings to talk to Ollie"; return
                }
                self.source = "Listening · speak now · Smallest.ai Pulse"
                self.voice.recordForConversation { [weak self] audio in
                    guard let self, current == self.generation, self.available() else { return }
                    guard let audio else {
                        self.handsFree = false; self.source = "Could not record your voice · check microphone and try again"; return
                    }
                    self.transcribe(audio, backend: backend, language: selectedLanguage, generation: current)
                }
                return
            }
            await self.voice.requestPermissions(language: self.language())
            guard !Task.isCancelled, current == self.generation, self.available() else { return }
            self.busy = false
            self.source = selectedLanguage == .punjabi && self.online() ? "Listening · Apple Punjabi recognition" : "Listening · device speech"
            self.voice.listenForConversation(language: selectedLanguage, allowNetwork: self.online()) { [weak self] text in
                guard let self, current == self.generation, self.available() else { return }
                if text.isEmpty { self.handsFree = false; self.source = "Could not hear you · choose Hindi or English for Smallest listening" }
                else { self.send(text) }
            }
        }
    }
    private func transcribe(_ audio: Data, backend: BackendClient, language: VoiceLanguage, generation current: Int) {
        busy = true; source = "Transcribing your reply · Smallest.ai Pulse"
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await backend.transcribe(audio, language: language)
                guard !Task.isCancelled, current == self.generation, self.available() else { return }
                self.busy = false
                if text.isEmpty { self.handsFree = false; self.source = "No speech heard · speak closer to the phone and try again" }
                else { self.send(text) }
            } catch {
                guard !Task.isCancelled, current == self.generation, self.available() else { return }
                self.busy = false; self.handsFree = false
                self.source = "Online listening failed · restart the updated backend and check the voice connection"
            }
        }
    }
    func send(_ input: String) {
        guard available(), !busy else { return }
        let text = String(input.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !text.isEmpty else { return }
        messages.append(.init(text: text, driver: true))
        let lower = text.lowercased()
        let command = lower.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if ["stop", "stop talking", "quiet", "be quiet", "चुप", "रुको", "ਰੁਕੋ"].contains(command) { stop(); return }
        if quizPending {
            quizPending = false; say(CompanionContent.quizReply(text, language: language())); return
        }
        if ["story", "कहानी", "ਕਹਾਣੀ"].contains(where: { lower.contains($0) }) { story(); return }
        if ["quiz", "क्विज", "ਕੁਇਜ਼"].contains(where: { lower.contains($0) }) { quiz(); return }
        generation += 1; let current = generation
        task?.cancel(); busy = true
        let selectedLanguage = language()
        task = Task { [weak self] in
            guard let self else { return }
            var reply = CompanionContent.reply(text, language: selectedLanguage)
            if self.online(), let backend = self.backend() {
                do {
                    let history = self.messages.dropLast().suffix(6).map { ["role": $0.driver ? "user" : "assistant", "content": $0.text] }
                    let response = try await backend.companion(text, language: selectedLanguage, assistant: self.assistant, history: history)
                    reply = response.text
                    self.conversationSource = response.provider == "smallest-electron" ? "Ollie agent · Smallest.ai Electron"
                        : self.assistant == "custom" ? "Connected assistant" : "Ollie online agent"
                }
                catch { self.conversationSource = "Scripted reply · conversation agent not available" }
            }
            guard !Task.isCancelled, current == self.generation, self.available() else { return }
            self.busy = false; self.say(reply)
        }
    }
    private func say(_ text: String) {
        guard available() else { return }
        generation += 1; let current = generation
        task?.cancel(); voice.stopAll(); busy = true
        messages.append(.init(text: text, driver: false))
        if messages.count > 40 { messages.removeFirst(messages.count - 40) }
        let selectedLanguage = language()
        let finished: () -> Void = { [weak self] in
            guard let self, current == self.generation else { return }
            self.busy = false
            if self.handsFree && self.available() { self.listen() }
        }
        task = Task { [weak self] in
            guard let self else { return }
            if self.online(), let backend = self.backend() {
                self.source = "Generating online voice · Smallest.ai"
                do {
                    let audio = try await backend.speech(text, language: selectedLanguage)
                    guard !Task.isCancelled, current == self.generation, self.available() else { return }
                    self.source = "Online voice · Smallest.ai Lightning"
                    self.voice.playCloudAudio(audio, completion: finished)
                    return
                } catch { self.source = "Online voice unavailable · device voice fallback" }
            } else { self.source = self.online() ? "Pair the voice backend · device voice fallback" : "Device voice · online mode is off" }
            guard !Task.isCancelled, current == self.generation, self.available() else { return }
            self.voice.speak(text, language: selectedLanguage, completion: finished)
        }
    }
    func stop() {
        generation += 1; task?.cancel(); task = nil
        handsFree = false; quizPending = false; busy = false
        source = "Ready to talk · online voice preferred"
        if available() { voice.stopAll() } else { voice.stopListening() }
    }
    /// Detection prompts and the alarm always interrupt entertainment.
    func interrupt() { stop(); source = "Paused for a driver check-in" }
}
