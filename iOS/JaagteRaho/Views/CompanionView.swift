import SwiftUI

struct SaarthiMascot: View {
    var size: CGFloat = 160
    var speaking = false
    var body: some View {
        Image("SaarthiCompanion")
            .resizable().scaledToFit().frame(width: size, height: size)
            .shadow(color: RahoTheme.mint.opacity(speaking ? 0.3 : 0.12), radius: speaking ? 24 : 12)
            .accessibilityLabel("Ollie, your friendly owl road companion")
    }
}

struct CompanionView: View {
    @ObservedObject var model: DriveModel
    @ObservedObject var companion: CompanionService
    @ObservedObject var voice: VoiceService
    @ObservedObject var music: MusicService
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var musicPicker = false
    @FocusState private var typing: Bool
    private var interrupted: Bool { model.snapshot.state == .critical || model.snapshot.state == .checkIn || model.paused }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(spacing: 8) {
                            SaarthiMascot(size: 170, speaking: companion.busy)
                            Text("A friend for every mile.").font(.system(.title2, design: .rounded).weight(.bold))
                            Text(companion.source).font(.caption).foregroundStyle(RahoTheme.mint)
                            Text(companion.conversationSource).font(.caption2).foregroundStyle(RahoTheme.muted).multilineTextAlignment(.center)
                            Text("Talk, hear a short story, or answer a quick voice quiz.")
                                .font(.subheadline).foregroundStyle(RahoTheme.muted).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity)
                        if interrupted {
                            NoticeView(message: "Conversation is paused for monitoring. Return to the session to respond to the alert.")
                            Button("Return to monitoring") { dismiss() }.buttonStyle(RahoPrimaryButton())
                        }
                        RahoCard {
                            VStack(spacing: 14) {
                                Picker("Voice agent", selection: $companion.assistant) {
                                    Text("OLLIE").tag("saarthi")
                                    Text("My assistant").tag("custom")
                                }.pickerStyle(.segmented)
                                if companion.assistant == "custom" {
                                    Text("Connect your assistant's HTTPS endpoint in the Mac backend. Voice playback uses Smallest.ai.")
                                        .font(.caption).foregroundStyle(RahoTheme.muted)
                                }
                                Toggle("Online voice · Smallest.ai", isOn: $model.cloudEnabled).tint(RahoTheme.mint)
                                Toggle("Hands-free turns", isOn: $companion.handsFree).tint(RahoTheme.mint)
                                Text("After each response, Ollie listens for your next turn. Say ‘stop’ to finish. Check-ins and alarms interrupt conversation.")
                                    .font(.caption).foregroundStyle(RahoTheme.muted)
                            }
                        }
                        HStack(spacing: 12) {
                            Button { typing = false; companion.story() } label: { Label("Story", systemImage: "book.closed.fill") }
                            Button { typing = false; companion.quiz() } label: { Label("Quiz", systemImage: "sparkles") }
                        }.buttonStyle(RahoSecondaryButton()).disabled(interrupted)
                        RahoCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "music.note").foregroundStyle(RahoTheme.amber)
                                    Text(music.title).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    if music.hasSelection {
                                        Button { music.toggle() } label: { Image(systemName: music.playing ? "pause.fill" : "play.fill").frame(width: 44, height: 44) }
                                            .accessibilityLabel(music.playing ? "Pause music" : "Play music")
                                    }
                                }
                                Button {
                                    Task { if await music.requestAccess() { musicPicker = true } }
                                } label: { Label("Choose music", systemImage: "music.note.list") }
                                .buttonStyle(RahoSecondaryButton())
                                Text("Use music from your library. Playback pauses when Ollie speaks or an alarm starts.")
                                    .font(.caption).foregroundStyle(RahoTheme.muted)
                            }
                        }.disabled(interrupted)
                        ForEach(companion.messages) { message in
                            HStack(alignment: .top, spacing: 10) {
                                if !message.driver { SaarthiMascot(size: 38) }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(message.driver ? "YOU" : "OLLIE").font(.caption2.weight(.bold)).foregroundStyle(RahoTheme.muted)
                                    Text(message.text).font(.subheadline).lineSpacing(3)
                                }
                                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(message.driver ? RahoTheme.raised : RahoTheme.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                            }.id(message.id)
                        }
                        if voice.listening {
                            NoticeView(message: voice.transcript.isEmpty ? "Listening… say ‘tell me a story’, ‘quiz’, or speak your reply." : voice.transcript, symbol: "waveform")
                        }
                        if let warning = voice.audioWarning { NoticeView(message: warning) }
                    }
                    .padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
                }
                .onChange(of: companion.messages.count) { _ in
                    if let id = companion.messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
                .safeAreaInset(edge: .bottom) { composer }
            }
            .background(RahoTheme.midnight).foregroundStyle(RahoTheme.text)
            .navigationTitle("Your co-pilot").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $musicPicker) {
            MusicLibraryPicker(selected: { music.select($0) }, dismissed: { musicPicker = false })
        }
        .onDisappear { companion.stop() }
    }
    private var composer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField("Say hello to Ollie…", text: $input).focused($typing)
                    .submitLabel(.send).onSubmit(send)
                    .padding(14).background(RahoTheme.raised, in: RoundedRectangle(cornerRadius: 14))
                Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 32)).foregroundStyle(RahoTheme.amber) }
                    .accessibilityLabel("Send message").disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || companion.busy || interrupted)
            }
            HStack(spacing: 12) {
                Button {
                    typing = false
                    if voice.listening { voice.finishConversation() } else { companion.listen() }
                } label: { Label(voice.listening ? "Finish reply" : "Talk to Ollie", systemImage: voice.listening ? "checkmark" : "mic.fill") }
                .buttonStyle(RahoPrimaryButton()).disabled(companion.busy || interrupted)
                Button { companion.stop() } label: { Image(systemName: "stop.fill").frame(width: 48, height: 56) }
                    .buttonStyle(.plain).foregroundStyle(RahoTheme.muted).accessibilityLabel("Stop conversation")
            }
        }.padding(16).background(RahoTheme.midnight).disabled(interrupted)
    }
    private func send() { typing = false; companion.send(input); input = "" }
}
