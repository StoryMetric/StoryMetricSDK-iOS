import XCTest
@testable import StoryMetric

final class LoggingCoreTests: XCTestCase {

    private let fixedDate = Date(timeIntervalSince1970: 1_000)

    private func makeCore(sink: CollectingSink, store: InMemoryStore = InMemoryStore()) -> SM.Core {
        SM.Core(store: store, clock: ManualClock(date: fixedDate), sink: sink, uuid: CountingUUID().next)
    }

    func testValidEventFlowsToSink() {
        let sink = CollectingSink()
        let core = makeCore(sink: sink)
        core.start(apiKey: "k", events: LoggingSampleEvents.allEvents)

        core.record(name: "used_search", params: ["query": .string("cats"), "results": .int(2)])

        XCTAssertEqual(sink.received.count, 1)
        let e = sink.received[0]
        XCTAssertEqual(e.name, "used_search")
        XCTAssertEqual(e.params, ["query": .string("cats"), "results": .int(2)])
        XCTAssertEqual(e.eventID, "id-2") // id-1 was the install id
        XCTAssertEqual(e.eventSequence, 1)
        XCTAssertEqual(e.clientTS, fixedDate)
        XCTAssertEqual(e.sdkVersion, SM.sdkVersion)
        XCTAssertEqual(
            e.declarationHash,
            SM.DeclarationManifest(events: LoggingSampleEvents.allEvents).declarationHash
        )
        XCTAssertTrue(e.flags.isEmpty)
        XCTAssertNil(e.sessionID) // deferred
    }

    func testInvalidParamsAcceptedAndFlagged() {
        let sink = CollectingSink()
        let core = makeCore(sink: sink)
        core.start(apiKey: "k", events: LoggingSampleEvents.allEvents)

        core.record(name: "used_search", params: ["query": .string("cats"), "results": .string("two")])

        XCTAssertEqual(sink.received.count, 1, "flagged, not dropped")
        XCTAssertEqual(
            sink.received[0].flags,
            [.typeMismatch(event: "used_search", param: "results", expected: .int, actual: .string)]
        )
    }

    func testUndeclaredEventAcceptedAndFlagged() {
        let sink = CollectingSink()
        let core = makeCore(sink: sink)
        core.start(apiKey: "k", events: LoggingSampleEvents.allEvents)

        core.record(name: "mystery", params: [:])

        XCTAssertEqual(sink.received.count, 1, "accepted, never dropped")
        XCTAssertEqual(sink.received[0].flags, [.undeclaredEvent(name: "mystery")])
    }
}
