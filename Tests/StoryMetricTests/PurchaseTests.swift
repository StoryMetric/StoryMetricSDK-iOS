import XCTest
@testable import StoryMetric

/// The built-in `purchase` capture path, the deterministic dedup id, and the
/// `original_download_ts` origin riding `$first_launch`.
final class PurchaseTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1000)

    // MARK: PurchaseFacts → params

    func testParamsCarryRequiredFields() {
        let facts = PurchaseFacts(
            productID: "pro_annual",
            transactionID: "2000000123",
            originalTransactionID: "2000000123",
            isRenewal: false,
            price: 34.99,
            currencyCode: "USD",
            period: "annual",
            isTrial: true,
            isSandbox: false
        )
        XCTAssertEqual(facts.params(), [
            "product_id": .string("pro_annual"),
            "transaction_id": .string("2000000123"),
            "original_transaction_id": .string("2000000123"),
            "is_renewal": .bool(false),
            "price": .double(34.99),
            "currency": .string("USD"),
            "period": .string("annual"),
            "is_trial": .bool(true),
        ])
    }

    func testOneTimePurchaseOmitsPeriodAndTrial() {
        // period/is_trial are nil for a one-time (or transaction-only) capture — absent,
        // not empty, in the payload.
        let facts = PurchaseFacts(
            productID: "credits_100",
            transactionID: "42",
            originalTransactionID: "42",
            isRenewal: false,
            price: 4.99,
            currencyCode: "USD",
            period: nil,
            isTrial: nil,
            isSandbox: true
        )
        let params = facts.params()
        XCTAssertNil(params["period"])
        XCTAssertNil(params["is_trial"])
        XCTAssertEqual(params["product_id"], .string("credits_100"))
    }

    // MARK: Custom params

    private func facts(period: String? = "annual", isTrial: Bool? = false) -> PurchaseFacts {
        PurchaseFacts(
            productID: "pro_annual",
            transactionID: "2000000123",
            originalTransactionID: "2000000123",
            isRenewal: false,
            price: 34.99,
            currencyCode: "USD",
            period: period,
            isTrial: isTrial,
            isSandbox: false
        )
    }

    func testCustomParamsRideAlongsideTheTransaction() {
        let params = facts().params(custom: [
            "paywall_source": .string("onboarding"),
            "experiment": .string("price_b"),
            "days_since_install": .int(3),
        ])

        XCTAssertEqual(params["paywall_source"], .string("onboarding"))
        XCTAssertEqual(params["experiment"], .string("price_b"))
        XCTAssertEqual(params["days_since_install"], .int(3))
        XCTAssertEqual(params["product_id"], .string("pro_annual"), "the built-ins still ride")
    }

    func testCustomParamsCantOverrideTheTransaction() {
        let params = facts().params(custom: [
            "price": .double(0),
            "product_id": .string("free"),
            "is_renewal": .bool(true),
        ])

        XCTAssertEqual(params["price"], .double(34.99))
        XCTAssertEqual(params["product_id"], .string("pro_annual"))
        XCTAssertEqual(params["is_renewal"], .bool(false))
    }

    func testReservedIDsAreDroppedEvenWhenTheTransactionHasNoValue() {
        // A one-time purchase has no period and no trial. Their absence is a fact
        // about the purchase, not a gap a caller may fill.
        let params = facts(period: nil, isTrial: nil).params(custom: [
            "period": .string("annual"),
            "is_trial": .bool(true),
        ])

        XCTAssertNil(params["period"])
        XCTAssertNil(params["is_trial"])
    }

    func testEveryBuiltInIDIsReserved() {
        let custom = Dictionary(
            uniqueKeysWithValues: SM.purchaseParamIDs.map { ($0, SM.ParamValue.string("injected")) }
        )
        let params = facts().params(custom: custom)

        XCTAssertFalse(
            params.values.contains(.string("injected")),
            "purchaseParamIDs is the full built-in vocabulary — none of it is writable"
        )
    }

    func testEmptyParamIDIsDropped() {
        let params = facts().params(custom: ["": .string("nameless"), "kept": .int(1)])

        XCTAssertNil(params[""])
        XCTAssertEqual(params["kept"], .int(1))
    }

    func testNoCustomParamsLeavesThePayloadUnchanged() {
        XCTAssertEqual(facts().params(custom: [:]), facts().params())
    }

    // MARK: Core.recordPurchase

    private func startedCore(store: InMemoryStore = InMemoryStore(), sink: EventSink) -> SM.Core {
        let core = SM.Core(
            store: store, clock: ManualClock(date: t0), sink: sink, uuid: CountingUUID().next
        )
        core.start(apiKey: "k", vocabularyVersion: sampleVocabularyVersion)
        return core
    }

    func testRecordPurchaseEmitsReservedEventUnflagged() {
        let sink = CollectingSink()
        let core = startedCore(sink: sink)

        core.recordPurchase(
            params: ["product_id": .string("pro"), "transaction_id": .string("99")],
            transactionID: "99", isSandbox: false
        )

        let e = sink.received.last
        XCTAssertEqual(e?.name, "purchase")
    }

    func testPurchaseSandboxIsTransactionLevel() {
        // The build is DEBUG (Environment.isSandbox == true), but a production
        // transaction must ride as non-sandbox regardless.
        let sink = CollectingSink()
        let core = startedCore(sink: sink)

        core.recordPurchase(params: [:], transactionID: "1", isSandbox: false)

        XCTAssertEqual(sink.received.last?.isSandbox, false)
    }

    func testSameTransactionYieldsSameEventID() {
        let sink = CollectingSink()
        let core = startedCore(sink: sink)

        core.recordPurchase(params: [:], transactionID: "2000000123", isSandbox: false)
        core.recordPurchase(params: [:], transactionID: "2000000123", isSandbox: false)

        let ids = sink.received.map(\.eventID)
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(ids[0], ids[1], "the same transaction dedupes to one id across routes")
    }

    func testDifferentTransactionsYieldDifferentEventIDs() {
        let sink = CollectingSink()
        let core = startedCore(sink: sink)

        core.recordPurchase(params: [:], transactionID: "1", isSandbox: false)
        core.recordPurchase(params: [:], transactionID: "2", isSandbox: false)

        XCTAssertNotEqual(sink.received[0].eventID, sink.received[1].eventID)
    }

    func testPurchaseEventIDIsUUIDShaped() {
        let sink = CollectingSink()
        let core = startedCore(sink: sink)

        core.recordPurchase(params: [:], transactionID: "abc", isSandbox: false)

        let id = sink.received.last?.eventID
        XCTAssertNotNil(id.flatMap(UUID.init(uuidString:)), "event_id is a valid UUID string")
    }

    func testPurchaseBeforeStartNoOps() {
        let sink = CollectingSink()
        let core = SM.Core(store: InMemoryStore(), clock: ManualClock(date: t0), sink: sink)

        core.recordPurchase(params: [:], transactionID: "1", isSandbox: false)

        XCTAssertTrue(sink.received.isEmpty, "no consent → no purchase")
    }

    // MARK: original_download_ts origin

    private func makeSessionCore(
        store: InMemoryStore,
        sink: EventSink,
        appOrigin: AppOriginSource?
    ) -> SM.Core {
        let clock = ManualClock(date: t0)
        let sessions = SessionManager(clock: clock, store: store, uuid: { UUID().uuidString })
        return SM.Core(
            store: store, clock: clock, sink: sink,
            sessions: sessions, appOrigin: appOrigin, uuid: CountingUUID().next
        )
    }

    func testFirstLaunchCarriesOriginWhenKnown() {
        let origin = Date(timeIntervalSince1970: 500)
        let firstLaunch = expectation(description: "first_launch recorded")
        let sink = ClosureSink { if $0.name == "$first_launch" { firstLaunch.fulfill() } }

        let core = makeSessionCore(store: InMemoryStore(), sink: sink, appOrigin: StubAppOrigin(date: origin))
        core.start(apiKey: "k", vocabularyVersion: sampleVocabularyVersion)

        wait(for: [firstLaunch], timeout: 2)
        let fl = sink.received.first { $0.name == "$first_launch" }
        let iso = ISO8601DateFormatter().string(from: origin)
        XCTAssertEqual(fl?.params["original_download_ts"], .string(iso))
    }

    func testFirstLaunchOmitsOriginWhenUnknown() {
        let firstLaunch = expectation(description: "first_launch recorded")
        let sink = ClosureSink { if $0.name == "$first_launch" { firstLaunch.fulfill() } }

        let core = makeSessionCore(store: InMemoryStore(), sink: sink, appOrigin: StubAppOrigin(date: nil))
        core.start(apiKey: "k", vocabularyVersion: sampleVocabularyVersion)

        wait(for: [firstLaunch], timeout: 2)
        let fl = sink.received.first { $0.name == "$first_launch" }
        XCTAssertNil(fl?.params["original_download_ts"], "unknown origin is absent, never zero")
    }

#if canImport(StoreKit)
    // SystemAppOrigin sanitizes StoreKit's originalPurchaseDate: the Simulator /
    // StoreKit-testing epoch placeholder (1970) is a non-date and must map to unknown,
    // not ship as a decades-old origin. A genuine date passes through untouched.
    func testSystemOriginRejectsPreAppStorePlaceholders() {
        XCTAssertNil(SystemAppOrigin.sanitize(Date(timeIntervalSince1970: 0)), "epoch is a placeholder")
        XCTAssertNil(SystemAppOrigin.sanitize(Date(timeIntervalSince1970: 500)), "1970 is a placeholder")
        XCTAssertNil(SystemAppOrigin.sanitize(nil), "missing stays missing")
        XCTAssertNil(
            SystemAppOrigin.sanitize(SystemAppOrigin.appStoreEpoch.addingTimeInterval(-86_400)),
            "the day before the App Store opened is not a real download"
        )
    }

    func testSystemOriginKeepsRealDates() {
        let real = Date(timeIntervalSince1970: 1_700_000_000) // 2023
        XCTAssertEqual(SystemAppOrigin.sanitize(real), real)
        XCTAssertEqual(
            SystemAppOrigin.sanitize(SystemAppOrigin.appStoreEpoch), SystemAppOrigin.appStoreEpoch,
            "the boundary itself is a valid date"
        )
    }
#endif

    func testOriginOnlyOnFreshInstall() {
        // A relaunch (existing install id) records no first_launch, origin or not.
        let store = InMemoryStore()
        makeSessionCore(store: store, sink: CollectingSink(),
                        appOrigin: StubAppOrigin(date: t0)).start(apiKey: "k", vocabularyVersion: sampleVocabularyVersion)

        let sink2 = CollectingSink()
        makeSessionCore(store: store, sink: sink2,
                        appOrigin: StubAppOrigin(date: t0)).start(apiKey: "k", vocabularyVersion: sampleVocabularyVersion)

        XCTAssertFalse(sink2.received.contains { $0.name == "$first_launch" })
    }
}
