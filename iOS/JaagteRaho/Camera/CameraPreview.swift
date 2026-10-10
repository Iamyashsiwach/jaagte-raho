import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.bind(session)
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) { uiView.bind(session) }
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        func bind(_ session: AVCaptureSession) {
            if preview.session !== session { preview.session = session }
            preview.videoGravity = .resizeAspectFill
            configureConnection()
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            configureConnection()
        }
        private func configureConnection() {
            guard let connection = preview.connection else { return }
            if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
    }
}
