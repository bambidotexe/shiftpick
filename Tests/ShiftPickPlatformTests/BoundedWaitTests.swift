import XCTest
@testable import ShiftPickPlatform

/// Waiting on something the app does not own, another process or a daemon's reply, for so long and no
/// longer, and without spinning any run loop while it waits: the uninstall is made of such waits, and one
/// that spun the main run loop re-ran the app's own timers in the middle of it and never came back.
final class BoundedWaitTests: XCTestCase {
    private func elapsed(_ body: () -> Void) -> TimeInterval {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return TimeInterval(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
    }

    func testAToolThatEndsInTimeReportsHowItEnded() {
        XCTAssertEqual(BoundedWait.run("/usr/bin/true", [], timeout: 5), .exited(0))
        XCTAssertEqual(BoundedWait.run("/usr/bin/false", [], timeout: 5), .exited(1))
    }

    func testAToolThatOverrunsIsStoppedAndSaidSo() {
        var outcome: BoundedWait.ProcessOutcome?
        let took = elapsed { outcome = BoundedWait.run("/bin/sleep", ["30"], timeout: 0.2) }
        XCTAssertEqual(outcome, .timedOut)
        XCTAssertLessThan(took, 1.5)
    }

    func testAToolThatCannotStartIsSaidSo() {
        XCTAssertEqual(BoundedWait.run("/nonexistent/tool", [], timeout: 5), .couldNotStart)
    }

    /// The whole point: the calling thread's run loop is not run while it waits, so nothing scheduled on it
    /// fires in the middle.
    func testWaitingRunsNothingElseOnTheCallersRunLoop() {
        var fired = 0
        let timer = Timer(timeInterval: 0.001, repeats: true) { _ in fired += 1 }
        RunLoop.current.add(timer, forMode: .default)
        defer { timer.invalidate() }
        _ = BoundedWait.run("/bin/sleep", ["0.2"], timeout: 5)
        _ = BoundedWait.answer(within: 0.2) { (_: @escaping @Sendable (Int) -> Void) in }
        XCTAssertEqual(fired, 0)
    }

    func testAnAnswerInTimeIsTheAnswer() {
        let answer: Int? = BoundedWait.answer(within: 2) { reply in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { reply(42) }
        }
        XCTAssertEqual(answer, 42)
    }

    func testAnAnswerThatNeverComesIsGivenUpOn() {
        var answer: Int? = 0
        let took = elapsed {
            answer = BoundedWait.answer(within: 0.2) { (_: @escaping @Sendable (Int) -> Void) in }
        }
        XCTAssertNil(answer)
        XCTAssertLessThan(took, 1)
    }

    /// A reply of "nothing went wrong" is an answer, and is told apart from no answer at all.
    func testAnAnswerCanBeNothingAndStillBeInTime() {
        let answer = BoundedWait.answer(within: 2) { (reply: @escaping @Sendable (String?) -> Void) in reply(nil) }
        XCTAssertEqual(answer, .some(.none))
    }
}
