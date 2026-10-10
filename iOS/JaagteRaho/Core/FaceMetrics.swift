import Foundation

public struct FaceMetrics: Sendable {
    public let timestamp: TimeInterval
    public var leftEAR: Double
    public var rightEAR: Double
    public var jawOpen: Double
    public var pitch: Double
    public var facePresent: Bool
    public var illumination: Double
    public var inferenceMilliseconds: Double

    public init(timestamp: TimeInterval, leftEAR: Double = 0, rightEAR: Double = 0,
                jawOpen: Double = 0, pitch: Double = 0, facePresent: Bool = true,
                illumination: Double = 1, inferenceMilliseconds: Double = 0) {
        self.timestamp = timestamp; self.leftEAR = leftEAR; self.rightEAR = rightEAR
        self.jawOpen = jawOpen; self.pitch = pitch; self.facePresent = facePresent
        self.illumination = illumination; self.inferenceMilliseconds = inferenceMilliseconds
    }

    public var usable: Bool {
        facePresent && illumination > 0.06 && timestamp.isFinite && leftEAR.isFinite &&
        rightEAR.isFinite && jawOpen.isFinite && pitch.isFinite &&
        leftEAR >= 0 && rightEAR >= 0 && leftEAR < 1 && rightEAR < 1
    }
    public static func missing(at time: TimeInterval) -> Self {
        Self(timestamp: time, facePresent: false)
    }
}

public struct DriverCalibration: Codable, Sendable {
    public var leftOpen: Double
    public var rightOpen: Double
    public var leftClosed: Double
    public var rightClosed: Double
    public var neutralPitch: Double

    public init(leftOpen: Double, rightOpen: Double, leftClosed: Double,
                rightClosed: Double, neutralPitch: Double) {
        self.leftOpen = leftOpen; self.rightOpen = rightOpen
        self.leftClosed = leftClosed; self.rightClosed = rightClosed
        self.neutralPitch = neutralPitch
    }
    public var valid: Bool {
        [leftOpen, rightOpen, leftClosed, rightClosed, neutralPitch].allSatisfy(\.isFinite) &&
        leftOpen > 0.12 && rightOpen > 0.12 && leftOpen < 0.8 && rightOpen < 0.8 &&
        leftClosed >= 0 && rightClosed >= 0 &&
        leftClosed < leftOpen * 0.7 && rightClosed < rightOpen * 0.7
    }
    // Both open and closed samples determine the cutoff. Small blinks are handled temporally.
    public var leftThreshold: Double { leftClosed + (leftOpen - leftClosed) * 0.40 }
    public var rightThreshold: Double { rightClosed + (rightOpen - rightClosed) * 0.40 }
    public func eyesClosed(_ metrics: FaceMetrics) -> Bool {
        metrics.leftEAR < leftThreshold && metrics.rightEAR < rightThreshold
    }
    /// Enrollment must finish with a fresh, usable sample of both eyes open.
    public func readyToMonitor(_ metrics: FaceMetrics?, at now: TimeInterval) -> Bool {
        guard valid, now.isFinite, let metrics, metrics.usable else { return false }
        let age = now - metrics.timestamp
        return age >= 0 && age <= 0.75 &&
            metrics.leftEAR >= leftThreshold && metrics.rightEAR >= rightThreshold
    }
    public static let demo = Self(leftOpen: 0.30, rightOpen: 0.30,
                                  leftClosed: 0.05, rightClosed: 0.05, neutralPitch: 0)
}
