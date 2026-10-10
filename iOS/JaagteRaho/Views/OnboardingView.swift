import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: DriveModel
    @ObservedObject var journey: JourneyService
    let finish: () -> Void
    @State private var step = 0
    var body: some View {
        ZStack {
            RahoTheme.midnight.ignoresSafeArea()
            RadialGradient(colors: [RahoTheme.mint.opacity(0.10), .clear], center: .top, startRadius: 20, endRadius: 400).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("SAARTHI").font(.system(.subheadline, design: .rounded).weight(.heavy)).tracking(2)
                    Spacer()
                    Button("Skip") { model.companion.stop(); finish() }.foregroundStyle(RahoTheme.muted)
                }.padding(24)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        SaarthiMascot(size: step == 0 ? 260 : 180).frame(maxWidth: .infinity)
                        Text(title).font(.system(size: 39, weight: .bold, design: .rounded)).tracking(-1.2)
                        Text(detail).font(.body).foregroundStyle(RahoTheme.muted).lineSpacing(5)
                        if step == 0 {
                            feature("eye.fill", "A watchful co-pilot", "On-device face tracking and immediate alerts.")
                            feature("waveform", "A familiar voice", "Conversation, stories and quizzes in your language.")
                            feature("map.fill", "Your journey, together", "Record your route and share your location.")
                        } else if step == 1 {
                            RahoCard {
                                VStack(alignment: .leading, spacing: 18) {
                                    LanguageSelector(language: $model.language)
                                    Button { model.companion.greet() } label: { Label("Hear Ollie · online voice", systemImage: "speaker.wave.2.fill") }
                                        .buttonStyle(RahoSecondaryButton())
                                    Text(model.serverStatus).font(.caption).foregroundStyle(RahoTheme.mint)
                                    Text("Smallest.ai creates the online voice. If connectivity drops, device speech and bundled alarms remain available.")
                                        .font(.caption).foregroundStyle(RahoTheme.muted)
                                }
                            }
                        } else {
                            RahoCard {
                                VStack(alignment: .leading, spacing: 16) {
                                    Toggle("Record my journey", isOn: $journey.enabled).tint(RahoTheme.mint)
                                    Text("Optional GPS route recording while Saarthi is open. Routes save on this phone; share a location only when you choose.")
                                        .font(.subheadline).foregroundStyle(RahoTheme.muted)
                                    if journey.enabled {
                                        Button { journey.requestSnapshot() } label: { Label("Allow location", systemImage: "location.fill") }
                                            .buttonStyle(RahoSecondaryButton())
                                        Text(journey.status).font(.caption).foregroundStyle(RahoTheme.mint)
                                    }
                                }
                            }
                            feature("parkingsign.circle.fill", "Set up while parked", "Mount your phone, test the voice, then calibrate your eyes before monitoring.")
                            feature("lock.fill", "Your camera stays local", "Face frames are processed on your iPhone.")
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 24).frame(maxWidth: 600).frame(maxWidth: .infinity)
                }
                VStack(spacing: 18) {
                    HStack(spacing: 7) {
                        ForEach(0..<3) { index in Capsule().fill(index == step ? RahoTheme.amber : RahoTheme.raised).frame(width: index == step ? 26 : 7, height: 7) }
                    }.accessibilityLabel("Onboarding step \(step + 1) of 3")
                    Button {
                        model.companion.stop()
                        if step < 2 { withAnimation { step += 1 } } else { finish() }
                    } label: { HStack { Text(step == 2 ? "Meet Ollie" : step == 0 ? "Let's get started" : "Continue"); Image(systemName: "arrow.right") } }
                    .buttonStyle(RahoPrimaryButton())
                }.padding(24)
            }
        }.foregroundStyle(RahoTheme.text)
    }
    private var title: String {
        switch step { case 0: return "Every mile.\nA little company."; case 1: return "A voice that\nfeels like home."; default: return "Your journey.\nYour choice." }
    }
    private var detail: String {
        switch step {
        case 0: return "Meet Ollie. A friendly companion for the long road, with a watchful eye and a voice to talk to."
        case 1: return "Choose Hindi, Punjabi or English. Listen to your co-pilot before the journey begins."
        default: return "Choose what to record. You'll always know when tracking is running, paused or unavailable."
        }
    }
    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(RahoTheme.mint).frame(width: 40, height: 40).background(RahoTheme.mint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(RahoTheme.muted) }
        }
    }
}
