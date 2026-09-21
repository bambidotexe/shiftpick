import XCTest
@testable import ShiftPickPlatform

/// The click's budget is kept by whoever waits, not by whoever works. The tap's thread hands a click to the
/// worker and waits so long and no longer: a worker that never answers costs a click its range, and never
/// costs the Mac its clicks.
final class DeadlineGateTests: XCTestCase {
    private let queue = DispatchQueue(label: "DeadlineGateTests.worker")

    private func elapsed(_ body: () -> Void) -> TimeInterval {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return TimeInterval(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
    }

    func testAnAnswerInTimeIsTheAnswer() {
        let gate = DeadlineGate(queue: queue)
        let outcome = gate.run(budget: 1, grace: 1) { ticket in
            XCTAssertTrue(ticket.commit())
            ticket.finish(swallow: true)
        }
        XCTAssertEqual(outcome, .answered(swallow: true))
    }

    func testAnAnswerToPassIsTheAnswerToo() {
        let gate = DeadlineGate(queue: queue)
        XCTAssertEqual(gate.run(budget: 1, grace: 1) { $0.finish(swallow: false) }, .answered(swallow: false))
    }

    /// Work that returns without a word has decided nothing, and nothing is swallowed on its behalf.
    func testWorkThatEndsWithoutAnsweringPasses() {
        let gate = DeadlineGate(queue: queue)
        var outcome: DeadlineGate.Outcome?
        let took = elapsed { outcome = gate.run(budget: 1, grace: 1) { _ in } }
        XCTAssertEqual(outcome, .answered(swallow: false))
        XCTAssertLessThan(took, 0.5)
    }

    /// Only a selection that was really set may swallow a click, and `commit` is what says it is being set.
    func testSwallowingWithoutCommittingIsNotHonoured() {
        let gate = DeadlineGate(queue: queue)
        XCTAssertEqual(gate.run(budget: 1, grace: 1) { $0.finish(swallow: true) }, .answered(swallow: false))
    }

    func testWorkThatNeverAnswersCostsTheBudgetAndNoMore() {
        let gate = DeadlineGate(queue: queue)
        let late = expectation(description: "the worker gets there in the end")
        var outcome: DeadlineGate.Outcome?
        let took = elapsed {
            outcome = gate.run(budget: 0.05, grace: 0.05) { ticket in
                Thread.sleep(forTimeInterval: 0.4)
                // Given up on: the worker is told so, and must not set a selection nobody waited for.
                XCTAssertTrue(ticket.isAbandoned)
                XCTAssertFalse(ticket.commit())
                late.fulfill()
            }
        }
        XCTAssertEqual(outcome, .outOfTime)
        XCTAssertLessThan(took, 0.2)
        wait(for: [late], timeout: 2)
    }

    /// Letting the click through while the selection is being set would have Finder toggle the clicked file
    /// on top of the range, so that one call is waited for.
    func testASelectionAlreadyBeingSetIsWaitedFor() {
        let gate = DeadlineGate(queue: queue)
        let outcome = gate.run(budget: 0.05, grace: 0.4) { ticket in
            XCTAssertTrue(ticket.commit())
            Thread.sleep(forTimeInterval: 0.12)
            ticket.finish(swallow: true)
        }
        XCTAssertEqual(outcome, .answered(swallow: true))
    }

    func testASelectionThatTakesTooLongIsGivenUpOnAsWell() {
        let gate = DeadlineGate(queue: queue)
        let done = expectation(description: "the worker ends")
        var outcome: DeadlineGate.Outcome?
        let took = elapsed {
            outcome = gate.run(budget: 0.05, grace: 0.05) { ticket in
                XCTAssertTrue(ticket.commit())
                Thread.sleep(forTimeInterval: 0.4)
                ticket.finish(swallow: true)
                done.fulfill()
            }
        }
        XCTAssertEqual(outcome, .outOfTimeWhileSelecting)
        XCTAssertLessThan(took, 0.25)
        wait(for: [done], timeout: 2)
    }

    /// A click never queues behind a worker that is still busy with the one before: it would wait for an
    /// answer about a click that is no longer the one being held.
    func testAWorkerStillBusyRefusesTheNextClickAtOnce() {
        let gate = DeadlineGate(queue: queue)
        let freed = expectation(description: "the first job ends")
        XCTAssertEqual(gate.run(budget: 0.02, grace: 0.02) { _ in
            Thread.sleep(forTimeInterval: 0.3)
            freed.fulfill()
        }, .outOfTime)

        var second: DeadlineGate.Outcome?
        let took = elapsed { second = gate.run(budget: 1, grace: 1) { $0.finish(swallow: false) } }
        XCTAssertEqual(second, .busy)
        XCTAssertLessThan(took, 0.05)

        wait(for: [freed], timeout: 2)
        // The flag is cleared after the work returns, a moment after the expectation is fulfilled.
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(gate.run(budget: 1, grace: 1) { $0.finish(swallow: false) }, .answered(swallow: false))
    }
}
