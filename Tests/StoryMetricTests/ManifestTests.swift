import XCTest
@testable import StoryMetric

/// A hand-written declaration source — proving the manifest works without the macro.
enum SampleEvents: SMEventSource {
    static let allEvents: [SM.Event] = [
        SM.Event("opened_paywall"),
        SM.Event("used_search", params: [
            .string("query"),
            .int("results"),
            .bool("from_history", optional: true),
        ]),
        SM.Event("added_ten_friends"),
    ]
}

final class ManifestTests: XCTestCase {

    func testInitFromEventSource() {
        let manifest = SM.DeclarationManifest(SampleEvents.self)
        XCTAssertEqual(manifest.events.count, 3)
        XCTAssertFalse(manifest.declarationHash.isEmpty)
    }

    func testHashIsOrderIndependent() {
        let a = SM.DeclarationManifest(events: [
            SM.Event("b_event", params: [.string("x"), .int("y")]),
            SM.Event("a_event"),
        ])
        let b = SM.DeclarationManifest(events: [
            SM.Event("a_event"),
            SM.Event("b_event", params: [.int("y"), .string("x")]), // params reordered too
        ])
        XCTAssertEqual(a.declarationHash, b.declarationHash)
    }

    func testHashChangesOnParamType() {
        let a = SM.DeclarationManifest(events: [SM.Event("e", params: [.int("n")])])
        let b = SM.DeclarationManifest(events: [SM.Event("e", params: [.double("n")])])
        XCTAssertNotEqual(a.declarationHash, b.declarationHash)
    }

    func testHashChangesOnOptionality() {
        let a = SM.DeclarationManifest(events: [SM.Event("e", params: [.string("s")])])
        let b = SM.DeclarationManifest(events: [SM.Event("e", params: [.string("s", optional: true)])])
        XCTAssertNotEqual(a.declarationHash, b.declarationHash)
    }

    func testHashChangesOnAddedEvent() {
        let a = SM.DeclarationManifest(events: [SM.Event("e")])
        let b = SM.DeclarationManifest(events: [SM.Event("e"), SM.Event("f")])
        XCTAssertNotEqual(a.declarationHash, b.declarationHash)
    }

    func testCanonicalStringShape() {
        let manifest = SM.DeclarationManifest(events: [
            SM.Event("used_search", params: [.int("results"), .string("query")]),
        ])
        XCTAssertEqual(
            manifest.canonicalString,
            "used_search|params:query:string,results:int"
        )
    }
}
