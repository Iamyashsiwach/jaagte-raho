import SwiftUI

@main
struct JaagteRahoApp: App {
    @StateObject private var model = DriveModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            DashboardView(model: model)
                .preferredColorScheme(.dark)
                .tint(RahoTheme.amber)
                .onChange(of: scenePhase) { phase in
                    if phase == .active { model.resume() }
                    else { model.suspend() }
                }
        }
    }
}
