import SwiftUI

@main
struct JaagteRahoApp: App {
    @StateObject private var model = DriveModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    var body: some Scene {
        WindowGroup {
            Group {
                if onboardingComplete { DashboardView(model: model) }
                else { OnboardingView(model: model, journey: model.journey) { onboardingComplete = true } }
            }
                .preferredColorScheme(.dark)
                .tint(RahoTheme.amber)
                #if DEBUG
                .onAppear {
                    if ProcessInfo.processInfo.environment["SAARTHI_START_CAMERA"] == "1",
                       model.phase == .ready { model.startLive() }
                }
                #endif
                .onChange(of: scenePhase) { phase in
                    if phase == .active { model.resume() }
                    else if phase == .background { model.suspend() }
                }
        }
    }
}
