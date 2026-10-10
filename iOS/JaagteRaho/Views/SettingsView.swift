import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: DriveModel
    @ObservedObject var voice: VoiceService
    @Environment(\.dismiss) private var dismiss
    @State private var draftURL: String
    @State private var token = ""
    @State private var connecting = false
    @FocusState private var focusedField: Field?

    private enum Field { case url, token }

    init(model: DriveModel, voice: VoiceService) {
        self.model = model; self.voice = voice
        _draftURL = State(initialValue: model.serverURL)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    RahoCard {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionLabel(title: "Voice language")
                            LanguageSelector(language: $model.language)
                            Button(action: model.testVoice) { Label("Play voice sample", systemImage: "speaker.wave.2.fill") }
                                .buttonStyle(RahoSecondaryButton())
                            Text("Camera monitoring, bundled voice alerts and alarms work offline. Voice replies depend on on-device speech recognition support for your selected language.")
                                .font(.footnote).foregroundStyle(RahoTheme.muted)
                            if let warning = voice.audioWarning { NoticeView(message: warning) }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("An optional\nvoice connection.")
                            .font(.system(size: 32, weight: .bold, design: .rounded)).tracking(-0.7)
                        Text("Pair with your backend for extra conversation and fleet delivery. Local detection and alarms keep working without a connection.")
                            .font(.subheadline).foregroundStyle(RahoTheme.muted).lineSpacing(3)
                    }
                    RahoCard {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionLabel(title: "Backend pairing")
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Backend URL").font(.caption.weight(.semibold)).foregroundStyle(RahoTheme.muted)
                                TextField("https://your-backend.example", text: $draftURL)
                                    .keyboardType(.URL)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .submitLabel(.next)
                                    .focused($focusedField, equals: .url)
                                    .onSubmit { focusedField = .token }
                                    .padding(14)
                                    .background(RahoTheme.midnight, in: RoundedRectangle(cornerRadius: 12))
                                    .accessibilityLabel("Backend URL")
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Backend pairing token").font(.caption.weight(.semibold)).foregroundStyle(RahoTheme.muted)
                                SecureField("Pairing token from your backend", text: $token)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .submitLabel(.done)
                                    .focused($focusedField, equals: .token)
                                    .onSubmit { focusedField = nil }
                                    .padding(14)
                                    .background(RahoTheme.midnight, in: RoundedRectangle(cornerRadius: 12))
                                    .accessibilityLabel("Backend pairing token")
                            }
                            Text("Use HTTPS, or your Mac's .local address for a local demo. The pairing token is stored in the iPhone Keychain. Provider API keys belong on the backend.")
                                .font(.caption).foregroundStyle(RahoTheme.muted)
                            Button {
                                focusedField = nil
                                connecting = true
                                let url = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
                                let pairingToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
                                Task {
                                    await model.connect(url: url, token: pairingToken)
                                    token = ""
                                    connecting = false
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    if connecting { ProgressView().tint(RahoTheme.midnight) }
                                    else { Image(systemName: "link") }
                                    Text(connecting ? "Connecting…" : "Connect backend")
                                }
                            }
                            .buttonStyle(RahoPrimaryButton())
                            .disabled(connecting || draftURL.isEmpty || token.isEmpty)
                            .opacity(connecting || draftURL.isEmpty || token.isEmpty ? 0.55 : 1)
                            Text(model.serverStatus).font(.footnote).foregroundStyle(RahoTheme.muted)
                                .accessibilityLabel("Connection status: \(model.serverStatus)")
                            if model.backend != nil {
                                Label(model.fleetConfigured ? "Fleet webhook configured" : "Fleet delivery not confirmed",
                                      systemImage: model.fleetConfigured ? "checkmark.shield.fill" : "antenna.radiowaves.left.and.right.slash")
                                    .font(.caption).foregroundStyle(model.fleetConfigured ? RahoTheme.mint : RahoTheme.amber)
                            }
                        }
                    }
                    RahoCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Toggle(isOn: $model.cloudEnabled) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Online conversation").font(.headline)
                                    Text("Optional · needs a connection").font(.caption).foregroundStyle(RahoTheme.muted)
                                }
                            }
                            .tint(RahoTheme.mint)
                            Text("When enabled, a short recognized reply is sent to your backend and OpenAI to create a response. The response text is sent to Smallest for speech. Camera frames stay on this phone.")
                                .font(.footnote).foregroundStyle(RahoTheme.muted).lineSpacing(3)
                            if model.cloudEnabled && model.backend == nil {
                                NoticeView(message: "Pair a backend above to use online conversation. Offline alerts remain available.", symbol: "wifi.slash")
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: "Before each drive")
                        Text("Mount the phone securely, keep your face well lit, test the voice and raise the volume. Keep the app open while monitoring. Set up only while safely parked.")
                            .font(.footnote).foregroundStyle(RahoTheme.muted).lineSpacing(3)
                        Text("Jaagte Raho · research prototype")
                            .font(.caption).foregroundStyle(RahoTheme.muted.opacity(0.8))
                    }
                }
                .padding(24)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(RahoTheme.midnight)
            .foregroundStyle(RahoTheme.text)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
