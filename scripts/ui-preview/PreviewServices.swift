// Preview-only replacements for hardware, storage and remote services.
// The actual DriveModel, fatigue engine and SwiftUI views are compiled unchanged.
import Foundation
import SwiftUI
import Combine
import AVFoundation

final class CameraService: ObservableObject {
    let session = AVCaptureSession()
    @Published var running = false
    @Published var errorMessage: String? = "Live camera is disabled in this Mac UI preview. Use the iPhone build for real calibration."
    var onMetrics: ((FaceMetrics) -> Void)?
    var onInterruption: (() -> Void)?
    func start() { running = false }
    func stop() { running = false }
    func reduceForThermals() {}
}

struct CameraPreview: View {
    let session: AVCaptureSession
    var body: some View {
        VStack {
            Spacer()
            Text("PREVIEW PLACEHOLDER · CAMERA DISABLED")
                .font(.system(size: 9, weight: .bold)).tracking(1)
                .foregroundStyle(RahoTheme.amber)
                .padding(.bottom, 52)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RahoTheme.surface)
    }
}

@MainActor
final class VoiceService: ObservableObject {
    @Published var status = "UI preview · voice playback disabled"
    @Published var listening = false
    @Published var transcript = ""
    @Published var offlineRecognitionAvailable = false
    @Published var audioWarning: String?
    var onAcknowledgment: ((String) -> Void)?
    func requestPermissions(language: VoiceLanguage) async {}
    func playPrompt(_ name: String, language: VoiceLanguage, completion: (() -> Void)? = nil) {
        status = "UI preview · \(language.name) prompt, audio disabled"
        if let completion {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                completion()
            }
        }
    }
    func listen(language: VoiceLanguage) { status = "UI preview · microphone disabled" }
    func playCloudAudio(_ data: Data) {}
    func stopListening() { listening = false }
    func startAlarm() { status = "UI preview · alarm screen, audio disabled" }
    func stopAll() { status = "UI preview · voice playback disabled" }
}

struct TripEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let trigger: FatigueTrigger
    let simulated: Bool
    var delivery: String
    init(trigger: FatigueTrigger, simulated: Bool) {
        id = UUID(); timestamp = Date(); self.trigger = trigger
        self.simulated = simulated; delivery = "demo"
    }
    var deliveryLabel: String { "Preview · in memory only" }
}

@MainActor
final class EventStore: ObservableObject {
    @Published var events: [TripEvent] = []
    @Published var errorMessage: String?
    func record(_ event: TripEvent) { events.insert(event, at: 0) }
    func flush(using client: BackendClient?) async {}
}

struct BackendClient {
    init(baseURL: URL, token: String) {}
    func status() async throws -> ServerStatus { throw PreviewError.disabled }
    func conversation(_ transcript: String, language: VoiceLanguage) async throws -> String { throw PreviewError.disabled }
    func speech(_ text: String, language: VoiceLanguage) async throws -> Data { throw PreviewError.disabled }
    enum PreviewError: Error { case disabled }
}

struct ServerStatus {
    let conversationConfigured: Bool
    let speechConfigured: Bool
    let fleetConfigured: Bool
}

enum KeychainToken {
    static func read() -> String { "" }
    static func save(_ token: String) -> Bool { false }
}
