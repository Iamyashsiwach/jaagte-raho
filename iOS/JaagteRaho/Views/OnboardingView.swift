import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: DriveModel
    @ObservedObject var journey: JourneyService
    let finish: () -> Void
    @State private var step = 0
    @State private var confirmEnrollment = false
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
                        } else if step == 2 {
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
                        } else {
                            RahoCard(accent: RahoTheme.mint.opacity(0.3)) {
                                VStack(alignment: .leading, spacing: 20) {
                                    feature("eye.fill", "First, eyes open", "Look at the phone for 3 seconds. Ollie learns your normal eye opening.")
                                    feature("eye.slash.fill", "Then, eyes closed", "While parked, gently close both eyes for 2 seconds.")
                                    feature("checkmark.shield.fill", "Ready to monitor", "Open your eyes and confirm when you're ready. Ollie watches for prolonged closure and checks in by voice.")
                                }
                            }
                            Text("Stay parked throughout enrollment. Mount the phone facing you in good light. This eye setup is repeated for each real monitoring session.")
                                .font(.subheadline).foregroundStyle(RahoTheme.muted)
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 24).frame(maxWidth: 600).frame(maxWidth: .infinity)
                }
                VStack(spacing: 18) {
                    HStack(spacing: 7) {
                        ForEach(0..<4) { index in Capsule().fill(index == step ? RahoTheme.amber : RahoTheme.raised).frame(width: index == step ? 26 : 7, height: 7) }
                    }.accessibilityLabel("Onboarding step \(step + 1) of 4")
                    Button {
                        model.companion.stop()
                        if step < 3 { withAnimation { step += 1 } } else { confirmEnrollment = true }
                    } label: { HStack { Text(step == 3 ? "Set up my eyes with Ollie" : step == 0 ? "Let's get started" : "Continue"); Image(systemName: step == 3 ? "viewfinder" : "arrow.right") } }
                    .buttonStyle(RahoPrimaryButton())
                    if step == 3 {
                        Button("Explore the app first") { model.companion.stop(); finish() }
                            .font(.subheadline).foregroundStyle(RahoTheme.muted).frame(minHeight: 32)
                    }
                }.padding(24)
            }
        }.foregroundStyle(RahoTheme.text)
        .alert("Are you safely parked?", isPresented: $confirmEnrollment) {
            Button("I'm parked · open camera") { model.startLive(); finish() }
            Button("Not yet", role: .cancel) {}
        } message: {
            Text("Eye enrollment asks you to close your eyes briefly. Stop safely and mount the phone before opening the camera.")
        }
    }
    private var title: String {
        switch step { case 0: return "Every mile.\nA little company."; case 1: return "A voice that\nfeels like home."; case 2: return "Your journey.\nYour choice."; default: return "Let Ollie learn\nyour eyes." }
    }
    private var detail: String {
        switch step {
        case 0: return "Meet Ollie. A friendly companion for the long road, with a watchful eye and a voice to talk to."
        case 1: return "Choose Hindi, Punjabi or English. Listen to your co-pilot before the journey begins."
        case 2: return "Choose what to record. You'll always know when tracking is running, paused or unavailable."
        default: return "A quick camera setup makes eye monitoring personal to you. Ollie will guide you through each step."
        }
    }
    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(RahoTheme.mint).frame(width: 40, height: 40).background(RahoTheme.mint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(RahoTheme.muted) }
        }
    }
}
