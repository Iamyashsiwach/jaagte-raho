import Foundation

public struct CalibrationCollector {
    public enum Phase: String { case openEyes, closedEyes, complete }
    public private(set) var phase: Phase = .openEyes
    public private(set) var progress: Double = 0
    public private(set) var result: DriverCalibration?
    private var open: [FaceMetrics] = []
    private var closed: [FaceMetrics] = []
    private var last: TimeInterval?
    private var validDuration: TimeInterval = 0

    public init() {}
    public func eyesClosed(_ sample: FaceMetrics?) -> Bool {
        guard let sample, sample.usable, phase != .openEyes else { return false }
        if let result { return result.eyesClosed(sample) }
        return sample.leftEAR < median(open.map(\.leftEAR)) * 0.65 &&
            sample.rightEAR < median(open.map(\.rightEAR)) * 0.65
    }
    public mutating func ingest(_ sample: FaceMetrics) {
        guard phase != .complete else { return }
        guard sample.usable else { resetCurrentPhase(); return }
        let dt = last.map { sample.timestamp - $0 } ?? 0
        if dt < 0 || dt > 0.4 { resetCurrentPhase() }
        last = sample.timestamp
        if phase == .openEyes {
            guard sample.leftEAR > 0.12, sample.rightEAR > 0.12 else {
                resetCurrentPhase(); return
            }
            open.append(sample)
            validDuration += max(0, min(dt, 0.2))
            progress = min(1, validDuration / 3)
            if validDuration >= 3 && open.count >= 25 {
                phase = .closedEyes; validDuration = 0; last = nil; progress = 0
            }
        } else {
            let lo = median(open.map(\.leftEAR)), ro = median(open.map(\.rightEAR))
            guard eyesClosed(sample) else {
                resetCurrentPhase(); return
            }
            closed.append(sample)
            validDuration += max(0, min(dt, 0.2))
            progress = min(1, validDuration / 2)
            if validDuration >= 2 && closed.count >= 15 {
                let calibration = DriverCalibration(
                    leftOpen: lo, rightOpen: ro,
                    leftClosed: median(closed.map(\.leftEAR)),
                    rightClosed: median(closed.map(\.rightEAR)),
                    neutralPitch: median(open.map(\.pitch)))
                if calibration.valid { result = calibration; phase = .complete }
                else { self = Self() }
            }
        }
    }
    private mutating func resetCurrentPhase() {
        validDuration = 0; last = nil; progress = 0
        if phase == .openEyes { open.removeAll(keepingCapacity: true) }
        else { closed.removeAll(keepingCapacity: true) }
    }
    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }
}
