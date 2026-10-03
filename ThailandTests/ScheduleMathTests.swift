import XCTest
@testable import Thailand

final class ScheduleMathTests: XCTestCase {
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000) // a fixed instant

    func testOnTimeWhenThereIsEnoughGap() {
        // Finish at base, 10 min walk + 5 min buffer, next starts 20 min later.
        let late = ScheduleMath.minutesLate(previousEnd: base, travelSeconds: 600, nextStart: base.addingTimeInterval(20 * 60))
        XCTAssertEqual(late, 0)
    }

    func testRunningLate() {
        // 30 min travel + 5 buffer, next start only 20 min later → 15 min late.
        let late = ScheduleMath.minutesLate(previousEnd: base, travelSeconds: 1_800, nextStart: base.addingTimeInterval(20 * 60))
        XCTAssertEqual(late, 15)
    }

    func testPartialMinutesRoundUp() {
        let late = ScheduleMath.minutesLate(previousEnd: base, travelSeconds: 61, bufferMinutes: 0, nextStart: base)
        XCTAssertEqual(late, 2)
    }

    func testRetimeKeepsDurationsAndTravel() {
        let start = ScheduleMath.roundedUpToFiveMinutes(base)
        let starts = ScheduleMath.retimedStarts(
            firstStart: start,
            durationsMinutes: [60, 30, 45],
            travelSeconds: [600, 300],
            bufferMinutes: 5
        )
        XCTAssertEqual(starts.count, 3)
        XCTAssertEqual(starts[0], start)
        // 60 min visit + 10 min travel + 5 buffer = 75 min later.
        XCTAssertEqual(starts[1].timeIntervalSince(start), 75 * 60)
        // +30 min visit + 5 min travel + 5 buffer = 40 min after stop 2.
        XCTAssertEqual(starts[2].timeIntervalSince(starts[1]), 40 * 60)
    }

    func testRetimeHandlesMissingTravelAndEmpty() {
        XCTAssertTrue(ScheduleMath.retimedStarts(firstStart: base, durationsMinutes: [], travelSeconds: []).isEmpty)
        let starts = ScheduleMath.retimedStarts(firstStart: ScheduleMath.roundedUpToFiveMinutes(base), durationsMinutes: [30, 30], travelSeconds: [], bufferMinutes: 0)
        XCTAssertEqual(starts[1].timeIntervalSince(starts[0]), 30 * 60)
    }

    func testRoundUpToFiveMinutes() {
        let aligned = ScheduleMath.roundedUpToFiveMinutes(base)
        XCTAssertEqual(aligned.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 300), 0)
        XCTAssertEqual(ScheduleMath.roundedUpToFiveMinutes(aligned), aligned)
        XCTAssertEqual(ScheduleMath.roundedUpToFiveMinutes(aligned.addingTimeInterval(1)), aligned.addingTimeInterval(300))
    }

    func testDurationText() {
        XCTAssertEqual(ScheduleMath.durationText(seconds: 600), "10 min")
        XCTAssertEqual(ScheduleMath.durationText(seconds: 3_900), "1 h 5 min")
        XCTAssertEqual(ScheduleMath.durationText(seconds: 5), "1 min")
    }
}
