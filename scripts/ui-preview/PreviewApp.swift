import SwiftUI
import UIKit

@main
struct JaagteRahoUIPreviewApp: App {
    @StateObject private var model = DriveModel()

    var body: some Scene {
        WindowGroup {
            DashboardView(model: model)
                .safeAreaInset(edge: .top, spacing: 0) { previewControls }
                .preferredColorScheme(.dark)
                .tint(RahoTheme.amber)
                .onAppear {
                    for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                        scene.sizeRestrictions?.minimumSize = CGSize(width: 420, height: 720)
                        scene.sizeRestrictions?.maximumSize = CGSize(width: 460, height: 950)
                        scene.title = "Jaagte Raho · actual SwiftUI preview"
                    }
                }
        }
    }

    private var previewControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("MAC UI PREVIEW · ACTUAL SWIFTUI VIEWS", systemImage: "macwindow")
                .font(.system(size: 10, weight: .heavy)).tracking(0.7)
            Text("Camera, microphone, audio & network disabled. Demo signals are synthetic.")
                .font(.system(size: 10)).foregroundStyle(RahoTheme.muted)
            HStack(spacing: 12) {
                Button("Home") { model.endSession() }
                Button("Calibration") { model.endSession(); model.startLive() }
                Button("Demo") { model.endSession(); model.startDemo() }
                Button("Alarm") {
                    model.endSession(); model.startDemo(); model.demoEyesClosed = true
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .buttonStyle(.bordered)
        }
        .foregroundStyle(RahoTheme.amber)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RahoTheme.raised)
    }
}
