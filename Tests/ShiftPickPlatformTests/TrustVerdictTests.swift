import ApplicationServices
import XCTest
import ShiftPickCore
@testable import ShiftPickPlatform

/// What one Accessibility call's result says about the grant. Two mistakes are possible and both cost
/// something: reading a busy Dock as a grant that is gone sends the user back to the onboarding wizard for
/// nothing, and reading a refusal as anything else leaves a click tap armed over a grant that is not there.
final class TrustVerdictTests: XCTestCase {
    func testARefusalByNameIsTheGrantGone() {
        XCTAssertEqual(Permissions.verdict(for: .apiDisabled), .revoked)
    }

    /// The other side answered, even if only to say it has nothing: the request was let through.
    func testAnyAnswerFromTheOtherSideIsAGrantInPlace() {
        for error in [AXError.success, .noValue, .attributeUnsupported] {
            XCTAssertEqual(Permissions.verdict(for: error), .trusted, "\(error.rawValue)")
        }
    }

    /// A timeout above all. Nobody answered, which says nothing about whether they would have been allowed to.
    func testEverythingElseSaysNothingEitherWay() {
        for error in [AXError.cannotComplete, .invalidUIElement, .failure, .notImplemented, .illegalArgument,
                      .invalidUIElementObserver, .actionUnsupported, .notEnoughPrecision] {
            XCTAssertEqual(Permissions.verdict(for: error), .unknown, "\(error.rawValue)")
        }
    }
}
