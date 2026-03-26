import CoreGraphics
import Foundation

struct CaptureState {
    var streak: Int = 0
    var totalCaptured: Int = 0
    var isRare: Bool = false
    private(set) var lastCaptureTime: Date = .distantPast

    /// Linear scale from 1.0 (0 words) to 1.3 (100+ words)
    var pouchScale: CGFloat {
        1.0 + CGFloat(min(totalCaptured, 100)) / 100.0 * 0.3
    }

    /// Update state for a newly captured word. `timestamp` is injectable for tests.
    mutating func update(word: String, timestamp: Date = Date()) {
        isRare = word.count >= 8
        if timestamp.timeIntervalSince(lastCaptureTime) <= 60 {
            streak += 1
        } else {
            streak = 1
        }
        lastCaptureTime = timestamp
        totalCaptured += 1
        AppSettings.shared.captureCount = totalCaptured
    }
}
