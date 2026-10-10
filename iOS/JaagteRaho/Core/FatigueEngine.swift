import Foundation

public enum MonitoringState: String, Codable, Sendable {
    case idle, monitoring, checkIn, critical, trackingUnavailable
}
public enum FatigueTrigger: String, Codable, Sendable {
    case prolongedClosure, closureTrend, repeatedYawns, repeatedNods, noResponse
    public var title: String {
        switch self {
        case .prolongedClosure: return "Prolonged eye closure"
        case .closureTrend: return "Frequent eye closure"
        case .repeatedYawns: return "Repeated yawn signals"
        case .repeatedNods: return "Repeated head nods"
        case .noResponse: return "No driver response"
        }
    }
}
public struct FatigueSnapshot: Sendable {
    public var state: MonitoringState = .idle
    public var closureSeconds: Double = 0
    public var closureFraction: Double = 0
    public var trackingCoverage: Double = 0
    public var trendReady = false
    public var yawns = 0
    public var nods = 0
    public var eyesClosed = false
    public var trigger: FatigueTrigger?
    public init() {}
}
public struct FatigueConfiguration: Sendable {
    public var checkInAfter: Double = 1.5
    public var criticalAfter: Double = 3
    public var responseWindow: Double = 8
    public var frameGapLimit: Double = 0.4
    public var staleAfter: Double = 0.8
    public var trendWindow: Double = 60
    public var trendThreshold: Double = 0.30
    public var cooldown: Double = 30
    public init() {}
}

/// Temporal heuristics for a prototype. All times use the same monotonic clock.
/// An alarm remains latched until a parked driver ends the session.
public struct FatigueEngine {
    public private(set) var snapshot = FatigueSnapshot()
    public let configuration: FatigueConfiguration
    private let calibration: DriverCalibration
    private var previous: FaceMetrics?
    private var closedSince: Double?
    private var eyesOpenSince: Double?
    private var lastValidAt: Double?
    private var checkInAt: Double?
    private var responseDeadline: Double?
    private var lastCheckIn: Double = -.infinity
    private var yawnSince: Double?
    private var yawnRecorded = false
    private var yawnTimes: [Double] = []
    private var nodSince: Double?
    private var nodRecorded = false
    private var nodTimes: [Double] = []
    private var startedAt: Double?
    private struct Segment { var end: Double; var duration: Double; var closed: Bool }
    private var segments: [Segment] = []

    public init(calibration: DriverCalibration, configuration: FatigueConfiguration = .init()) {
        self.calibration = calibration; self.configuration = configuration
        snapshot.state = calibration.valid ? .trackingUnavailable : .idle
    }

    @discardableResult public mutating func ingest(_ sample: FaceMetrics) -> FatigueSnapshot {
        guard calibration.valid, sample.timestamp.isFinite else { return snapshot }
        // Reject out-of-order results; they must not move deadlines backwards.
        if let previous, sample.timestamp <= previous.timestamp { return snapshot }
        startedAt = startedAt ?? sample.timestamp
        let gap = previous.map { sample.timestamp - $0.timestamp } ?? 0
        let continuous = gap > 0 && gap <= configuration.frameGapLimit && previous?.usable == true
        guard sample.usable else {
            resetContinuousSignals()
            previous = sample
            if snapshot.state != .critical { snapshot.state = .trackingUnavailable }
            updateTrend(at: sample.timestamp)
            return tick(at: sample.timestamp)
        }
        lastValidAt = sample.timestamp
        if !continuous { resetContinuousSignals() }
        if snapshot.state == .trackingUnavailable {
            snapshot.state = checkInAt == nil ? .monitoring : .checkIn
        }
        let closed = calibration.eyesClosed(sample)
        snapshot.eyesClosed = closed
        if continuous, let previous {
            segments.append(Segment(end: sample.timestamp, duration: gap,
                                    closed: closed && calibration.eyesClosed(previous)))
        }
        if closed {
            closedSince = closedSince ?? sample.timestamp
            eyesOpenSince = nil
            snapshot.closureSeconds = sample.timestamp - (closedSince ?? sample.timestamp)
        } else {
            closedSince = nil; snapshot.closureSeconds = 0
            eyesOpenSince = eyesOpenSince ?? sample.timestamp
        }
        collectAuxiliarySignals(sample)
        updateTrend(at: sample.timestamp)
        previous = sample
        if snapshot.state != .critical {
            if snapshot.closureSeconds >= configuration.criticalAfter {
                escalate(.prolongedClosure)
            } else if snapshot.closureSeconds >= configuration.checkInAfter {
                checkIn(.prolongedClosure, at: sample.timestamp)
            } else if snapshot.trendReady && snapshot.closureFraction >= configuration.trendThreshold {
                checkIn(.closureTrend, at: sample.timestamp)
            } else if yawnTimes.count >= 3 {
                checkIn(.repeatedYawns, at: sample.timestamp)
            } else if nodTimes.count >= 3 {
                checkIn(.repeatedNods, at: sample.timestamp)
            }
        }
        return tick(at: sample.timestamp)
    }

    /// Call on a watchdog even when no new camera result arrives.
    @discardableResult public mutating func tick(at time: Double) -> FatigueSnapshot {
        guard time.isFinite, time >= (previous?.timestamp ?? 0) else { return snapshot }
        if snapshot.state != .critical {
            if let responseDeadline, time >= responseDeadline { escalate(.noResponse) }
            // A failed prompt/audio callback cannot suppress escalation forever.
            else if let checkInAt, time - checkInAt >= 20 { escalate(.noResponse) }
        }
        if lastValidAt == nil || time - (lastValidAt ?? time) > configuration.staleAfter {
            resetContinuousSignals()
            if snapshot.state != .critical { snapshot.state = .trackingUnavailable }
        }
        updateTrend(at: time)
        return snapshot
    }

    public mutating func promptFinished(at time: Double) {
        guard checkInAt != nil, snapshot.state != .critical, responseDeadline == nil else { return }
        responseDeadline = time + configuration.responseWindow
    }

    @discardableResult public mutating func acknowledge(at time: Double) -> Bool {
        guard snapshot.state == .checkIn, !snapshot.eyesClosed,
              let lastValidAt, time - lastValidAt < configuration.staleAfter,
              let eyesOpenSince, time - eyesOpenSince >= 0.5,
              !(snapshot.trendReady && snapshot.closureFraction >= configuration.trendThreshold)
        else { return false }
        snapshot.state = .monitoring; snapshot.trigger = nil
        checkInAt = nil; responseDeadline = nil
        // Keep observed yawns/nods for the trip display; re-check only after cooldown.
        return true
    }

    private mutating func checkIn(_ trigger: FatigueTrigger, at time: Double) {
        guard checkInAt == nil else { return }
        // Sustained closure bypasses cooldown; auxiliary cues do not.
        guard trigger == .prolongedClosure || time - lastCheckIn >= configuration.cooldown else { return }
        checkInAt = time; lastCheckIn = time
        snapshot.state = .checkIn; snapshot.trigger = trigger
    }
    private mutating func escalate(_ trigger: FatigueTrigger) {
        snapshot.state = .critical; snapshot.trigger = trigger
        responseDeadline = nil
    }
    private mutating func resetContinuousSignals() {
        closedSince = nil; eyesOpenSince = nil; yawnSince = nil; nodSince = nil
        yawnRecorded = false; nodRecorded = false
        snapshot.closureSeconds = 0; snapshot.eyesClosed = false
    }
    private mutating func collectAuxiliarySignals(_ sample: FaceMetrics) {
        if sample.jawOpen > 0.65 {
            yawnSince = yawnSince ?? sample.timestamp
            if sample.timestamp - (yawnSince ?? sample.timestamp) >= 1.5 && !yawnRecorded {
                yawnTimes.append(sample.timestamp); yawnRecorded = true
            }
        } else { yawnSince = nil; yawnRecorded = false }
        if abs(sample.pitch - calibration.neutralPitch) > 18 {
            nodSince = nodSince ?? sample.timestamp
            if sample.timestamp - (nodSince ?? sample.timestamp) >= 0.6 && !nodRecorded {
                nodRecorded = true
            }
        } else {
            if nodRecorded { nodTimes.append(sample.timestamp) }
            nodSince = nil; nodRecorded = false
        }
        yawnTimes.removeAll { sample.timestamp - $0 > 120 }
        nodTimes.removeAll { sample.timestamp - $0 > 60 }
        snapshot.yawns = yawnTimes.count; snapshot.nods = nodTimes.count
    }
    private mutating func updateTrend(at time: Double) {
        let cutoff = time - configuration.trendWindow
        segments.removeAll { $0.end <= cutoff }
        let clipped = segments.map { (min($0.duration, max(0, $0.end - cutoff)), $0.closed) }
        let tracked = clipped.reduce(0) { $0 + $1.0 }
        let elapsed = min(configuration.trendWindow, max(0, time - (startedAt ?? time)))
        snapshot.trackingCoverage = elapsed > 0 ? min(1, tracked / elapsed) : 0
        snapshot.trendReady = elapsed >= 20 && tracked >= 15 && snapshot.trackingCoverage >= 0.7
        snapshot.closureFraction = tracked > 0 ? clipped.filter(\.1).reduce(0) { $0 + $1.0 } / tracked : 0
    }
}
