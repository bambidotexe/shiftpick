import XCTest
@testable import ShiftPickPlatform

/// The thread the event taps are served on. Everything that touches a tap is handed to it, and the one
/// caller that cannot wait for ever, the teardown, is told plainly whether its block ran or never will.
final class TapThreadTests: XCTestCase {
    private var thread: TapThread!

    override func setUp() {
        super.setUp()
        thread = TapThread(name: "TapThreadTests")
    }

    override func tearDown() {
        thread.stop()
        thread = nil
        super.tearDown()
    }

    func testABlockRunsOnTheThreadAndNotOnTheCaller() {
        let ran = expectation(description: "ran")
        XCTAssertFalse(thread.isCurrent)
        thread.perform { [thread] in
            XCTAssertTrue(thread!.isCurrent)
            XCTAssertFalse(Thread.isMainThread)
            ran.fulfill()
        }
        wait(for: [ran], timeout: 2)
    }

    func testBlocksRunInTheOrderTheyWereHandedOver() {
        let done = expectation(description: "done")
        var order: [Int] = []
        for index in 0..<50 { thread.perform { order.append(index) } }
        thread.perform { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(order, Array(0..<50))
    }

    func testWaitingForABlockThatRan() {
        var ran = false
        XCTAssertTrue(thread.performAndWait(timeout: 2) { ran = true })
        XCTAssertTrue(ran)
    }

    func testCalledFromTheThreadItselfItRunsInline() {
        let done = expectation(description: "done")
        thread.perform { [thread] in
            var ran = false
            XCTAssertTrue(thread!.performAndWait(timeout: 0.01) { ran = true })
            XCTAssertTrue(ran)
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }

    /// The caller is about to do the work itself, so a block it gave up on must never run afterwards.
    func testABlockTheThreadNeverGotToNeverRuns() {
        let freed = expectation(description: "the thread is free again")
        thread.perform {
            Thread.sleep(forTimeInterval: 0.3)
            freed.fulfill()
        }
        var ran = false
        XCTAssertFalse(thread.performAndWait(timeout: 0.05) { ran = true })
        wait(for: [freed], timeout: 2)
        // Anything still queued behind the sleeper has had its turn by the time this one has.
        XCTAssertTrue(thread.performAndWait(timeout: 2) {})
        XCTAssertFalse(ran)
    }
}
