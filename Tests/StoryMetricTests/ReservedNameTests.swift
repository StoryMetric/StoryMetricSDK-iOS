import XCTest
@testable import StoryMetric

/// Reserved names used to be a COMPILE error, caught by @SMEvents when a developer
/// declared one. Events are designed in Studio now, so the rule moved with them:
/// Studio refuses a name whose id is already taken, and upsert_event_definition
/// (migration 0028) refuses a $-prefixed one.
///
/// What remains here is the SDK's own knowledge of which names are its: the
/// automatic events it emits, and the built-in purchase it captures itself.
final class ReservedNameTests: XCTestCase {

    func testAutomaticEventsAreRecognizedByPrefix() {
        XCTAssertTrue(AutoEvent.isAutomatic("$first_launch"))
        XCTAssertTrue(AutoEvent.isAutomatic("$session_start"))
        XCTAssertFalse(AutoEvent.isAutomatic("used_search"))
    }

    func testPurchaseIsReservedWithoutThePrefix() {
        XCTAssertTrue(ReservedEvent.isReserved("purchase"))
        XCTAssertTrue(ReservedEvent.isReserved("$session_end"))
        XCTAssertFalse(ReservedEvent.isReserved("opened_paywall"))
    }
}
