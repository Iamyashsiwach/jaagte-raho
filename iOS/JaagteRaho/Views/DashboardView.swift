import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: DriveModel
    @State private var sheet: DashboardSheet?
    @State private var confirmParked = false

    private enum DashboardSheet: String, Identifiable {
        case settings, history, companion, journey
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            RahoTheme.midnight.ignoresSafeArea()
            if model.snapshot.state == .critical, model.phase == .driving {
                CriticalAlertView(model: model, endSession: { confirmParked = true })
            } else {
                switch model.phase {
                case .ready:
                    ReadyView(model: model, store: model.store,
                              showHistory: { sheet = .history }, showSettings: { sheet = .settings },
                              showCompanion: { sheet = .companion }, showJourney: { sheet = .journey })
                case .calibration:
                    CalibrationView(model: model, camera: model.camera,
                                    endSession: { confirmParked = true })
                case .driving:
                    DriveView(model: model, camera: model.camera, voice: model.voice,
                              endSession: { confirmParked = true },
                              showCompanion: { sheet = .companion }, showJourney: { sheet = .journey })
                }
            }
        }
        .foregroundStyle(RahoTheme.text)
        .sheet(item: $sheet) { selected in
            switch selected {
            case .settings: SettingsView(model: model, voice: model.voice)
            case .history: HistoryView(store: model.store)
            case .companion: CompanionView(model: model, companion: model.companion, voice: model.voice, music: model.music)
            case .journey: JourneyView(journey: model.journey)
            }
        }
        .onChange(of: model.snapshot.state) { state in
            if state == .critical || state == .checkIn { sheet = nil }
        }
        .alert("Are you safely parked?", isPresented: $confirmParked) {
            Button("I'm safely parked · end session", role: .destructive) { model.endSession() }
            Button("Keep monitoring", role: .cancel) {}
        } message: {
            Text("Confirm only after stopping in a safe place. Ending this session stops the camera and alarm.")
        }
    }
}

private struct ReadyView: View {
    @ObservedObject var model: DriveModel
    @ObservedObject var store: EventStore
    let showHistory: () -> Void
    let showSettings: () -> Void
    let showCompanion: () -> Void
    let showJourney: () -> Void
    @State private var confirmEnrollment = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                VStack(alignment: .leading, spacing: 16) {
                    StatusPill(title: "START WITH YOUR EYE SETUP", symbol: "eye.fill")
                    HStack(spacing: 4) {
                        Text("Your watchful\nco-pilot.")
                            .font(.system(size: 37, weight: .bold, design: .rounded))
                            .tracking(-1.2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        SaarthiMascot(size: 125)
                    }
                    Text("Ollie learns your eyes, watches for drowsiness and checks in with you by voice.")
                        .font(.body).foregroundStyle(RahoTheme.muted).lineSpacing(5)
                    Button { confirmEnrollment = true } label: {
                        Label("Set up my eyes with Ollie", systemImage: "viewfinder")
                    }.buttonStyle(RahoPrimaryButton())
                    Text("Park first · Eyes open 3 s · Eyes closed 2 s")
                        .font(.caption.weight(.medium)).foregroundStyle(RahoTheme.amber)
                    HStack(spacing: 18) {
                        Label("On-device camera", systemImage: "iphone")
                        Label("Offline alerts", systemImage: "wifi.slash")
                    }
                    .font(.caption.weight(.medium)).foregroundStyle(RahoTheme.mint)
                }

                RahoCard(accent: RahoTheme.mint.opacity(0.25)) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            SaarthiMascot(size: 58)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Your co-pilot is here.").font(.headline)
                                Text("Talk · Stories · Quizzes · Music").font(.caption).foregroundStyle(RahoTheme.muted)
                            }
                        }
                        Button(action: showCompanion) { Label("Spend a moment with Ollie", systemImage: "waveform") }.buttonStyle(RahoPrimaryButton(color: RahoTheme.mint))
                        Text(model.serverStatus).font(.caption).foregroundStyle(RahoTheme.muted)
                    }
                }
                Button(action: showJourney) {
                    RahoCard {
                        HStack(spacing: 14) {
                            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").font(.title2).foregroundStyle(RahoTheme.amber)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Your journey").font(.headline)
                                Text("Record your route · Share your location").font(.caption).foregroundStyle(RahoTheme.muted)
                            }
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(RahoTheme.muted)
                        }
                    }
                }.buttonStyle(.plain)

                RahoCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            SectionLabel(title: "Your co-pilot's voice")
                            Spacer()
                            Button { model.testVoice() } label: {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.headline).foregroundStyle(RahoTheme.amber)
                                    .frame(width: 40, height: 40)
                            }
                            .accessibilityLabel("Play voice sample")
                        }
                        LanguageSelector(language: $model.language)
                        Text(model.language.text(for: "acknowledged"))
                            .font(.subheadline).foregroundStyle(RahoTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                RahoCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "play.rectangle.fill").foregroundStyle(RahoTheme.amber)
                            SectionLabel(title: "Try a parked demo")
                        }
                        Text("See the check-in and alarm sequence using simulated eye signals.")
                            .font(.subheadline).foregroundStyle(RahoTheme.muted)
                        Button(action: model.startDemo) {
                            Label("Start synthetic demo", systemImage: "play.fill")
                        }
                        .buttonStyle(RahoSecondaryButton())
                    }
                }

                if let error = store.errorMessage { NoticeView(message: error, color: RahoTheme.red) }
                footer
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 32)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .alert("Are you safely parked?", isPresented: $confirmEnrollment) {
            Button("I'm parked · open camera", action: model.startLive)
            Button("Not yet", role: .cancel) {}
        } message: {
            Text("Mount the phone facing you. Ollie will ask you to open your eyes for 3 seconds and close them for 2 seconds while parked.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(RahoTheme.amber)
                .frame(width: 48, height: 48)
                .background(RahoTheme.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 3) {
                Text("SAARTHI").font(.system(.subheadline, design: .rounded).weight(.heavy)).tracking(1.5)
                Text("STAY AWAKE. ARRIVE SAFE.")
                    .font(.system(size: 8, weight: .bold)).tracking(1.2).foregroundStyle(RahoTheme.muted)
            }
            Spacer(minLength: 8)
            Button(action: showHistory) {
                Image(systemName: "clock.arrow.circlepath").frame(width: 40, height: 44)
            }
            .accessibilityLabel("Alert history")
            Button(action: showSettings) {
                Image(systemName: "slider.horizontal.3").frame(width: 36, height: 44)
            }
            .accessibilityLabel("Settings")
        }
        .foregroundStyle(RahoTheme.muted)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: showHistory) {
                HStack {
                    Label("Alert history", systemImage: "clock.arrow.circlepath")
                    Spacer()
                    Text("\(store.events.count)").monospacedDigit()
                    Image(systemName: "chevron.right").font(.caption)
                }
                .font(.subheadline.weight(.medium)).foregroundStyle(RahoTheme.muted)
            }
            .frame(minHeight: 44)
            Text("Research prototype. If you feel sleepy, stop safely and rest. A voice reply is not a measure of fitness to drive.")
                .font(.caption).foregroundStyle(RahoTheme.muted).lineSpacing(3)
        }
    }
}
