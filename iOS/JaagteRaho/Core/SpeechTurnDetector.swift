import Foundation

/// Ends a bounded microphone turn after speech followed by a quiet pause.
public struct SpeechTurnDetector {
    private let started: TimeInterval
    private var lastSpeech: TimeInterval?
    public init(startedAt: TimeInterval) { started = startedAt }
    public mutating func shouldFinish(decibels: Float, at now: TimeInterval) -> Bool {
        guard now.isFinite, now >= started else { return false }
        if now - started >= 12 { return true }
        if decibels.isFinite && decibels > -38 { lastSpeech = now }
        return lastSpeech.map { now - $0 >= 1.2 && now - started >= 1 } ?? false
    }
}
