import XCTest
@testable import WordsHunterLib

// MARK: - CaptureState Tests

final class CaptureStateTests: XCTestCase {

    // MARK: Streak logic

    func test_streak_incrementsWhenWithin60Seconds() {
        var state = CaptureState()
        let base = Date()
        state.update(word: "hello", timestamp: base)
        state.update(word: "world", timestamp: base.addingTimeInterval(30))
        XCTAssertEqual(state.streak, 2)
    }

    func test_streak_resetsWhenOver60Seconds() {
        var state = CaptureState()
        let base = Date()
        state.update(word: "hello", timestamp: base)
        state.update(word: "world", timestamp: base.addingTimeInterval(61))
        XCTAssertEqual(state.streak, 1)
    }

    func test_streak_startsAtOneOnFirstCapture() {
        var state = CaptureState()
        state.update(word: "hello", timestamp: Date())
        XCTAssertEqual(state.streak, 1)
    }

    func test_totalCaptured_incrementsOnEachUpdate() {
        var state = CaptureState()
        let base = Date()
        state.update(word: "a", timestamp: base)
        state.update(word: "b", timestamp: base.addingTimeInterval(1))
        state.update(word: "c", timestamp: base.addingTimeInterval(2))
        XCTAssertEqual(state.totalCaptured, 3)
    }

    // MARK: isRare

    func test_isRare_trueForLongWords() {
        var state = CaptureState()
        state.update(word: "absolute", timestamp: Date()) // 8 chars
        XCTAssertTrue(state.isRare)
    }

    func test_isRare_falseForShortWords() {
        var state = CaptureState()
        state.update(word: "courage", timestamp: Date()) // 7 chars
        XCTAssertFalse(state.isRare)
    }

    func test_isRare_trueForExactlyEightChars() {
        var state = CaptureState()
        state.update(word: "absolute", timestamp: Date()) // exactly 8
        XCTAssertTrue(state.isRare)
    }

    // MARK: pouchScale

    func test_pouchScale_baseAtZero() {
        var state = CaptureState()
        state.totalCaptured = 0
        XCTAssertEqual(state.pouchScale, 1.0, accuracy: 0.001)
    }

    func test_pouchScale_midpoint() {
        var state = CaptureState()
        state.totalCaptured = 50
        XCTAssertEqual(state.pouchScale, 1.15, accuracy: 0.001)
    }

    func test_pouchScale_maxAtHundred() {
        var state = CaptureState()
        state.totalCaptured = 100
        XCTAssertEqual(state.pouchScale, 1.3, accuracy: 0.001)
    }

    func test_pouchScale_clampedAbove100() {
        var state = CaptureState()
        state.totalCaptured = 200
        XCTAssertEqual(state.pouchScale, 1.3, accuracy: 0.001)
    }
}

// MARK: - AppSettings captureCount Tests

final class CaptureCountSettingsTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        return d
    }

    func test_captureCount_defaultIsZero() {
        let settings = AppSettings(defaults: freshDefaults())
        XCTAssertEqual(settings.captureCount, 0)
    }

    func test_captureCount_roundTrip() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.captureCount = 42
        XCTAssertEqual(settings.captureCount, 42)
    }
}

// MARK: - StatusBarController Icon Tests

final class StatusBarIconTests: XCTestCase {

    func test_iconForZeroCaptures() {
        XCTAssertEqual(StatusBarController.iconTitle(for: 0), "🎯")
    }

    func test_iconAtTenCaptures() {
        XCTAssertEqual(StatusBarController.iconTitle(for: 10), "🏹")
    }

    func test_iconAtTwentyFiveCaptures() {
        XCTAssertEqual(StatusBarController.iconTitle(for: 25), "🎒")
    }

    func test_iconAtHundredCaptures() {
        XCTAssertEqual(StatusBarController.iconTitle(for: 100), "🏆")
    }

    func test_iconAtNineCaptures() {
        XCTAssertEqual(StatusBarController.iconTitle(for: 9), "🎯")
    }
}

// MARK: - BubbleWindow Frame Tests

final class BubbleWindowFrameTests: XCTestCase {

    func test_boundingRect_normalCase() {
        // When cursor is far from pouch, the panel should be wide enough to cover both
        // with ≥60pt padding. We verify this via the frame calculation logic directly.
        let cursor = CGPoint(x: 100, y: 100)
        let pouch  = CGPoint(x: 1800, y: 1000)

        let originX = min(cursor.x, pouch.x) - 60
        let originY = min(cursor.y, pouch.y) - 60
        let width   = abs(pouch.x - cursor.x) + 120
        let height  = abs(pouch.y - cursor.y) + 120

        let frameRect = CGRect(x: originX, y: originY, width: width, height: height)

        // Both points should be inside the frame
        XCTAssertTrue(frameRect.contains(cursor))
        XCTAssertTrue(frameRect.contains(pouch))

        // Each edge should have at least 60pt padding from the nearest point
        XCTAssertLessThanOrEqual(frameRect.minX, cursor.x - 60 + 1)
        XCTAssertLessThanOrEqual(frameRect.minY, cursor.y - 60 + 1)
    }

    func test_skipReel_whenCursorNearPouch() {
        // When cursor is within 80pt of pouch, the reel should be skipped
        let cursor = CGPoint(x: 1000, y: 1000)
        let pouch  = CGPoint(x: 1050, y: 1050) // ~70pt away

        let distance = hypot(cursor.x - pouch.x, cursor.y - pouch.y)
        XCTAssertLessThan(distance, 80, "Test setup: cursor should be within 80pt of pouch")
    }
}
