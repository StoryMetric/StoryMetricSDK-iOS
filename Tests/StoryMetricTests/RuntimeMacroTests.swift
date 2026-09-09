import XCTest
@testable import StoryMetric

/// A real `@SMEvents extension SM`, expanded by the actual compiler (not the
/// syntax-only test harness). Its compilation proves the generated `SM.log` methods,
/// `SM.allEvents`, and the slim `SM.start(apiKey:)` all hold in a real build — and
/// that the macro attaches to `extension SM` at all (the crux of option B).
@SMEvents
extension SM {
    static let opened = SM.Event("opened")
    static let usedSearch = SM.Event("used_search", params: [
        .string("query"), .int("results"), .bool("from_history", optional: true),
    ])
    static let tagged = SM.Event("tagged", params: [.stringArray("tags", optional: true)])
}

final class RuntimeMacroTests: XCTestCase {

    func testAllEvents() {
        XCTAssertEqual(SM.allEvents.map(\.name), ["opened", "used_search", "tagged"])

        let search = SM.allEvents.first { $0.name == "used_search" }
        XCTAssertEqual(search?.params.map(\.id), ["query", "results", "from_history"])
        XCTAssertEqual(search?.params.last?.optional, true)
    }

    func testGeneratedMethodsCompileAndNoOpBeforeStart() {
        // Core.shared is never started by the test suite (other tests use isolated
        // SM.Core instances), so these route through an inactive core → safe no-ops,
        // no network. This exercises the generated `SM.log.*` call sites end to end.
        SM.log.opened()
        SM.log.usedSearch(query: "cats", results: 3)
        SM.log.usedSearch(query: "cats", results: 3, fromHistory: true)
        SM.log.tagged()
        SM.log.tagged(tags: ["a", "b"])
    }

    func testSlimStartExists() {
        // Reference the generated zero-events start without invoking it (calling would
        // activate the production core). Its existence — as SM.start(apiKey:) — is the point.
        let slimStart: (String) -> Void = SM.start(apiKey:)
        _ = slimStart
    }

    #if canImport(StoreKit)
    /// The crux of the reserved-purchase wiring: the built-in `purchase` capture is
    /// reachable through the macro-generated `SM.log` (via `SMLogSurface`), even though
    /// this `@SMEvents` file never imports StoreKit and declares no `purchase` event.
    /// Referenced as an unapplied method value so nothing is recorded.
    @available(iOS 16.0, macOS 13.0, *)
    func testPurchaseIsReachableThroughGeneratedLog() {
        let capture: (StoreKitTransaction) -> Void = SM.log.purchase(_:)
        _ = capture
    }
    #endif
}

#if canImport(StoreKit)
import StoreKit
private typealias StoreKitTransaction = StoreKit.Transaction
#endif
