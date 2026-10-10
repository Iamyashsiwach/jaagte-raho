import MediaPlayer
import Combine
import SwiftUI

@MainActor
final class MusicService: ObservableObject {
    @Published private(set) var title = "Choose music from your library"
    @Published private(set) var playing = false
    @Published private(set) var authorized = false
    @Published private(set) var hasSelection = false
    private let player = MPMusicPlayerController.applicationMusicPlayer
    func requestAccess() async -> Bool {
        let status = await withCheckedContinuation { continuation in
            MPMediaLibrary.requestAuthorization { continuation.resume(returning: $0) }
        }
        authorized = status == .authorized
        if !authorized { title = "Music library permission is off" }
        return authorized
    }
    func select(_ collection: MPMediaItemCollection) {
        guard !collection.items.isEmpty else { return }
        player.setQueue(with: collection); hasSelection = true
        title = collection.items.first?.title ?? "Your music"
        player.play(); playing = true
    }
    func toggle() {
        guard hasSelection else { return }
        playing ? player.pause() : player.play(); playing.toggle()
    }
    func pauseForVoice() { player.pause(); playing = false }
}

struct MusicLibraryPicker: UIViewControllerRepresentable {
    let selected: (MPMediaItemCollection) -> Void
    let dismissed: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(selected: selected, dismissed: dismissed) }
    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let picker = MPMediaPickerController(mediaTypes: .music)
        picker.allowsPickingMultipleItems = true
        picker.prompt = "Choose your journey's soundtrack"
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: MPMediaPickerController, context: Context) {}
    final class Coordinator: NSObject, MPMediaPickerControllerDelegate {
        let selected: (MPMediaItemCollection) -> Void
        let dismissed: () -> Void
        init(selected: @escaping (MPMediaItemCollection) -> Void, dismissed: @escaping () -> Void) {
            self.selected = selected; self.dismissed = dismissed
        }
        func mediaPicker(_ mediaPicker: MPMediaPickerController, didPickMediaItems collection: MPMediaItemCollection) { selected(collection); dismissed() }
        func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) { dismissed() }
    }
}
