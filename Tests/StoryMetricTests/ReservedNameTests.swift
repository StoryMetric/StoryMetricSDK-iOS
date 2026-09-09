import XCTest
@testable import StoryMetric

final class ReservedNameTests: XCTestCase {

    func testManifestRejectsReservedEventName() {
        let manifest = SM.DeclarationManifest(events: [SM.Event("$first_launch"), SM.Event("ok")])
        XCTAssertEqual(SM.Validate.manifest(manifest), [.reservedEventName(name: "$first_launch")])
    }

    func testManifestRejectsPurchaseName() {
        // `purchase` is SDK-owned vocabulary (not $-prefixed, but built in), so a
        // developer declaration of it is rejected rather than shadowing the capture path.
        let manifest = SM.DeclarationManifest(events: [SM.Event("purchase"), SM.Event("ok")])
        XCTAssertEqual(SM.Validate.manifest(manifest), [.reservedEventName(name: "purchase")])
    }

    func testNormalNamesUnaffected() {
        let manifest = SM.DeclarationManifest(events: [SM.Event("used_search")])
        XCTAssertTrue(SM.Validate.manifest(manifest).isEmpty)
    }
}
