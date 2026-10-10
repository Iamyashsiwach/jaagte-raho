import SwiftUI
import UIKit

struct CalibrationView: View {
    @ObservedObject var model: DriveModel
    @ObservedObject var camera: CameraService
    let endSession: () -> Void

    private var closingEyes: Bool { model.calibration.phase == .closedEyes }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SessionHeader(title: "Before you drive", trailing: "End setup", action: endSession)
                StatusPill(title: "STAY SAFELY PARKED", symbol: "parkingsign.circle.fill", color: RahoTheme.amber)
                VStack(alignment: .leading, spacing: 10) {
                    Text(closingEyes ? "Now, close\nyour eyes." : "Let's get\nto know you.")
                        .font(.system(size: 38, weight: .bold, design: .rounded)).tracking(-1)
                    Text(closingEyes
                         ? "While parked, gently close both eyes for 2 seconds. Keep your head facing the phone."
                         : "Mount the phone facing you. Look forward with both eyes open for 3 seconds.")
                        .font(.body).foregroundStyle(RahoTheme.muted).lineSpacing(4)
                }

                CameraPanel(camera: camera, metrics: model.metrics,
                            label: closingEyes ? "Gently close both eyes" : "Look forward · eyes open")
                Button { camera.start() } label: {
                    Label("Restart camera", systemImage: "arrow.clockwise")
                }
                .buttonStyle(RahoSecondaryButton())

                if model.paused { NoticeView(message: "Monitoring is paused. Keep Saarthi open in the foreground.") }
                if let error = camera.errorMessage {
                    NoticeView(message: error, color: RahoTheme.red)
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: { Label("Open iPhone settings", systemImage: "gearshape") }
                    .buttonStyle(RahoSecondaryButton())
                }

                RahoCard(accent: RahoTheme.amber.opacity(0.3)) {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            SectionLabel(title: closingEyes ? "Step 2 of 2" : "Step 1 of 2")
                            Spacer()
                            Text("\(Int(model.calibration.progress * 100))%")
                                .font(.headline.monospacedDigit()).foregroundStyle(RahoTheme.amber)
                        }
                        ProgressView(value: model.calibration.progress)
                            .tint(RahoTheme.amber)
                            .accessibilityLabel("Calibration progress")
                        CalibrationStep(number: "1", title: "Eyes open", detail: "3 seconds", complete: closingEyes, active: !closingEyes)
                        CalibrationStep(number: "2", title: "Eyes closed", detail: "2 seconds · parked only", complete: false, active: closingEyes)
                        Text("Progress follows the camera. Keep your face clearly lit and in frame; tracking gaps restart the current step.")
                            .font(.footnote).foregroundStyle(RahoTheme.muted)
                    }
                }
                Text("Monitoring starts automatically when both steps complete. Camera frames are processed on this phone.")
                    .font(.footnote).foregroundStyle(RahoTheme.muted)
            }
            .padding(24)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct CalibrationStep: View {
    let number: String
    let title: String
    let detail: String
    let complete: Bool
    let active: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill((active || complete ? RahoTheme.mint : RahoTheme.muted).opacity(0.12))
                if complete { Image(systemName: "checkmark").font(.headline).foregroundStyle(RahoTheme.mint) }
                else { Text(number).font(.headline).foregroundStyle(active ? RahoTheme.amber : RahoTheme.muted) }
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(active || complete ? RahoTheme.text : RahoTheme.muted)
                Text(detail).font(.caption).foregroundStyle(RahoTheme.muted)
            }
            Spacer()
            if active { Text("NOW").font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(RahoTheme.amber) }
        }
        .accessibilityElement(children: .combine)
    }
}

struct DriveView: View {
    @ObservedObject var model: DriveModel
    @ObservedObject var camera: CameraService
    @ObservedObject var voice: VoiceService
    let endSession: () -> Void

    private var unavailable: Bool { model.paused || model.snapshot.state == .trackingUnavailable }
    private var checkingIn: Bool { model.snapshot.state == .checkIn }
    private var stateColor: Color { unavailable || checkingIn ? RahoTheme.amber : RahoTheme.mint }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SessionHeader(title: model.demo ? "Parked demo" : "On the road", trailing: "End trip", action: endSession)
                if model.demo {
                    NoticeView(message: "SYNTHETIC DEMO · Simulated eye signals. The camera is off and fleet alerts are not sent.", symbol: "play.rectangle.fill")
                }
                HStack {
                    StatusPill(title: unavailable ? "TRACKING UNAVAILABLE" : (checkingIn ? "VOICE CHECK-IN" : "MONITORING"),
                               symbol: unavailable ? "eye.slash.fill" : (checkingIn ? "waveform" : "eye.fill"), color: stateColor)
                    Spacer()
                    Text(model.elapsedLabel).font(.system(.caption, design: .monospaced)).foregroundStyle(RahoTheme.muted)
                }
                RahoCard(accent: stateColor.opacity(0.25)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(unavailable ? "Bring your face\nback into view." : (checkingIn ? "Can you\nhear me?" : "We're watching\nwith you."))
                            .font(.system(size: 34, weight: .bold, design: .rounded)).tracking(-0.8)
                        Text(unavailable ? "Fatigue detection needs a clear face and good light. Keep the app open."
                             : checkingIn ? "\(model.snapshot.trigger?.title ?? "Drowsiness signal"). If sleepy, pull over somewhere safe and rest."
                             : "Eye closure, yawn signals and head nods are monitored on your phone.")
                            .font(.subheadline).foregroundStyle(RahoTheme.muted).lineSpacing(3)
                        if checkingIn {
                            Label("Answer out loud", systemImage: "mic.fill")
                                .font(.headline).foregroundStyle(RahoTheme.amber)
                        }
                    }
                }

                if model.demo { demoControls }
                else {
                    CameraPanel(camera: camera, metrics: unavailable ? nil : model.metrics,
                                label: unavailable ? "Tracking unavailable" : (model.snapshot.eyesClosed ? "Eyes closed" : "Face in view"))
                }

                if let error = camera.errorMessage, !model.demo { NoticeView(message: error, color: RahoTheme.red) }
                if model.paused { NoticeView(message: "Monitoring is paused. Keep this app open in the foreground.") }
                if let warning = voice.audioWarning { NoticeView(message: warning, color: RahoTheme.red) }
                voiceCard
                metricGrid
                RahoCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            SectionLabel(title: "Eye closure trend")
                            Spacer()
                            Text(model.snapshot.trendReady ? "\(Int(model.snapshot.closureFraction * 100))%" : "Building trend")
                                .font(.caption.weight(.semibold)).foregroundStyle(RahoTheme.mint)
                        }
                        ProgressView(value: model.snapshot.trendReady ? model.snapshot.closureFraction : 0)
                            .tint(RahoTheme.mint)
                        Text(model.snapshot.trendReady
                             ? "Share of tracked time with eyes closed in the rolling 60-second window."
                             : "Collecting enough continuous face tracking to show a meaningful trend.")
                            .font(.caption).foregroundStyle(RahoTheme.muted)
                    }
                }
                Text("If you feel sleepy, stop safely and rest. Keep your attention on driving; use your voice for check-ins.")
                    .font(.caption).foregroundStyle(RahoTheme.muted).lineSpacing(3)
            }
            .padding(24)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
    }

    private var demoControls: some View {
        RahoCard(accent: RahoTheme.amber.opacity(0.3)) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: model.demoEyesClosed ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 32)).foregroundStyle(RahoTheme.amber)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.demoEyesClosed ? "Simulating closed eyes" : "Simulating open eyes").font(.headline)
                        Text("Check-in at 1.5 s · alarm at 3 s").font(.caption).foregroundStyle(RahoTheme.muted)
                    }
                }
                HStack(spacing: 12) {
                    Button { model.demoEyesClosed = true } label: { Label("Close eyes", systemImage: "eye.slash") }
                        .buttonStyle(RahoSecondaryButton())
                    Button { model.demoEyesClosed = false } label: { Label("Open eyes", systemImage: "eye") }
                        .buttonStyle(RahoSecondaryButton())
                }
                if checkingIn {
                    Button(action: model.acknowledgeDemo) { Label("Simulate voice reply", systemImage: "mic.badge.plus") }
                        .buttonStyle(RahoPrimaryButton())
                        .disabled(model.demoEyesClosed)
                        .opacity(model.demoEyesClosed ? 0.45 : 1)
                    Text("Open the simulated eyes for at least half a second, then reply. A reply cannot dismiss a critical alarm.")
                        .font(.caption).foregroundStyle(RahoTheme.muted)
                }
            }
        }
    }

    private var voiceCard: some View {
        RahoCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: voice.listening ? "mic.fill" : "waveform")
                    .font(.title2).foregroundStyle(voice.listening ? RahoTheme.amber : RahoTheme.mint)
                    .frame(width: 40, height: 40)
                    .background(RahoTheme.raised, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(model.language.name) co-pilot").font(.subheadline.weight(.semibold))
                    Text(voice.status).font(.caption).foregroundStyle(RahoTheme.muted)
                    if !voice.transcript.isEmpty {
                        Text("Heard: “\(voice.transcript)”").font(.caption).foregroundStyle(RahoTheme.text)
                    }
                    if checkingIn && !voice.offlineRecognitionAvailable {
                        Text("Offline reply recognition is unavailable on this phone. The alarm still escalates if no response is recognized.")
                            .font(.caption).foregroundStyle(RahoTheme.amber)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricTile(title: "Eye closure", value: unavailable ? "—" : String(format: "%.1f", model.snapshot.closureSeconds),
                       suffix: unavailable ? "" : "s", symbol: "eye", detail: "Current duration", color: stateColor)
            MetricTile(title: "Face tracking", value: unavailable ? "Lost" : "Active", suffix: "", symbol: "viewfinder",
                       detail: model.demo ? "Simulated" : "On this phone", color: stateColor)
            MetricTile(title: "Yawn signals", value: "\(model.snapshot.yawns)", suffix: "", symbol: "mouth", detail: "Past 2 minutes")
            MetricTile(title: "Head nods", value: "\(model.snapshot.nods)", suffix: "", symbol: "person.crop.circle", detail: "Past minute")
        }
    }
}

struct CriticalAlertView: View {
    @ObservedObject var model: DriveModel
    @ObservedObject private var voice: VoiceService
    @ObservedObject private var store: EventStore
    let endSession: () -> Void

    init(model: DriveModel, endSession: @escaping () -> Void) {
        self.model = model; self.endSession = endSession
        _voice = ObservedObject(wrappedValue: model.voice)
        _store = ObservedObject(wrappedValue: model.store)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    SectionLabel(title: "Saarthi")
                    Spacer()
                    Text(model.elapsedLabel).font(.caption.monospacedDigit()).foregroundStyle(RahoTheme.muted)
                }
                if model.demo { StatusPill(title: "SYNTHETIC DEMO ALARM", symbol: "play.rectangle.fill", color: RahoTheme.amber) }
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 70, weight: .medium)).foregroundStyle(RahoTheme.red)
                    .padding(24).background(RahoTheme.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 28))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 18) {
                    StatusPill(title: "STOP SAFELY & REST", symbol: "exclamationmark.triangle.fill", color: RahoTheme.red)
                    Text("Pull over safely.\nTake a break.")
                        .font(.system(size: 43, weight: .bold, design: .rounded)).tracking(-1.5)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(model.language.text(for: "critical"))
                        .font(.title3.weight(.medium)).foregroundStyle(RahoTheme.amber).lineSpacing(5)
                    Text("\(model.snapshot.trigger?.title ?? "Drowsiness alert") detected. The alarm remains active until you confirm you're safely parked.")
                        .font(.body).foregroundStyle(RahoTheme.muted).lineSpacing(4)
                }
                RahoCard(accent: RahoTheme.red.opacity(0.3)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(model.demo ? "Demo event" : "Fleet alert", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.headline).foregroundStyle(RahoTheme.text)
                        Text(deliveryMessage).font(.subheadline).foregroundStyle(RahoTheme.muted)
                        if let error = store.errorMessage { Text(error).font(.caption).foregroundStyle(RahoTheme.red) }
                    }
                }
                if let warning = voice.audioWarning { NoticeView(message: warning, color: RahoTheme.red) }
                Button(action: endSession) { Label("I'm parked · end session", systemImage: "parkingsign.circle.fill") }
                    .buttonStyle(RahoPrimaryButton(color: RahoTheme.amber))
                Text("Stop in a safe place before touching the phone. A voice reply or opening your eyes will not clear this alarm.")
                    .font(.footnote).foregroundStyle(RahoTheme.muted)
            }
            .padding(28)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .background(RahoTheme.red.opacity(0.025))
    }

    private var deliveryMessage: String {
        if model.demo { return "Saved locally for the demo. No fleet notification is sent." }
        if store.errorMessage != nil { return "Event storage needs attention. The alarm remains active on this phone." }
        if let event = store.events.first(where: { !$0.simulated }) {
            return event.deliveryLabel + (model.backend == nil ? ". Connect the optional backend after parking to send it." : ".")
        }
        return "The local alert is active. Check event history after stopping."
    }
}

private struct SessionHeader: View {
    let title: String
    let trailing: String
    let action: () -> Void
    var body: some View {
        HStack {
            Text(title).font(.system(.headline, design: .rounded).weight(.bold))
            Spacer()
            Button(action: action) {
                HStack(spacing: 6) {
                    Text(trailing)
                    Image(systemName: "stop.circle")
                }
                .font(.subheadline.weight(.medium)).foregroundStyle(RahoTheme.muted).frame(minHeight: 44)
            }
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let suffix: String
    let symbol: String
    let detail: String
    var color: Color = RahoTheme.mint

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol).foregroundStyle(color)
                Text(title).font(.caption.weight(.medium)).foregroundStyle(RahoTheme.muted)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(suffix).font(.caption).foregroundStyle(RahoTheme.muted)
            }
            Text(detail).font(.caption2).foregroundStyle(RahoTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RahoTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

private struct CameraPanel: View {
    @ObservedObject var camera: CameraService
    let metrics: FaceMetrics?
    let label: String
    private var faceVisible: Bool { metrics?.usable == true && camera.running }

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
            LinearGradient(colors: [.black.opacity(0.55), .clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
            VStack {
                HStack {
                    StatusPill(title: "ON-DEVICE CAMERA", symbol: "iphone", color: .white)
                    Spacer()
                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                HStack(spacing: 8) {
                    Circle().fill(faceVisible ? RahoTheme.mint : RahoTheme.amber).frame(width: 7, height: 7)
                    Text(camera.running ? label : (camera.errorMessage == nil ? "Starting camera…" : "Camera unavailable"))
                        .font(.caption.weight(.semibold)).foregroundStyle(.white)
                    Spacer()
                    if faceVisible, let metrics {
                        Text("\(Int(metrics.inferenceMilliseconds)) ms").font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .padding(16)
            RoundedRectangle(cornerRadius: 55)
                .stroke(faceVisible ? RahoTheme.mint.opacity(0.8) : Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [9, 7]))
                .frame(width: 150, height: 185)
                .accessibilityHidden(true)
            if !camera.running {
                VStack(spacing: 12) {
                    Image(systemName: camera.errorMessage == nil ? "camera" : "camera.fill")
                        .font(.largeTitle).foregroundStyle(RahoTheme.muted)
                    Text(camera.errorMessage == nil ? "Preparing face tracking" : "Camera unavailable")
                        .font(.subheadline.weight(.medium)).foregroundStyle(RahoTheme.text)
                }
                .padding(20).background(RahoTheme.midnight.opacity(0.9), in: RoundedRectangle(cornerRadius: 18))
            }
        }
        .frame(height: 255)
        .background(RahoTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(RahoTheme.border))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(camera.running ? "Camera preview. \(label)." : "Camera unavailable or starting.")
    }
}
