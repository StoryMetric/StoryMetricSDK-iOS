import XCTest
import Foundation
@testable import StoryMetric

final class UploaderTests: XCTestCase {

    private let manifest = SM.DeclarationManifest(events: LoggingSampleEvents.allEvents)

    private func makeUploader(
        http: MockHTTPClient,
        buffer: InMemoryEventBuffer = InMemoryEventBuffer(),
        store: InMemoryStore = InMemoryStore()
    ) -> Uploader {
        Uploader(buffer: buffer, http: http, store: store, baseURL: URL(string: "https://x.test")!)
    }

    // MARK: Events

    func testSuccessRemovesBatch() async {
        let buffer = InMemoryEventBuffer()
        buffer.append(makeBufferedEvent(id: "a"))
        buffer.append(makeBufferedEvent(id: "b"))
        let http = MockHTTPClient(status: 200)
        let uploader = makeUploader(http: http, buffer: buffer)
        await uploader.configure(apiKey: "k", installID: "i", manifest: manifest)

        let outcome = await uploader.flush()

        XCTAssertEqual(outcome, .sent(2))
        XCTAssertEqual(buffer.count, 0)
        XCTAssertEqual(http.requests(matching: "v1/events").count, 1)
    }

    func testServerErrorRetains() async {
        let buffer = InMemoryEventBuffer()
        buffer.append(makeBufferedEvent(id: "a"))
        let uploader = makeUploader(http: MockHTTPClient(status: 503), buffer: buffer)
        await uploader.configure(apiKey: "k", installID: "i", manifest: manifest)

        let outcome = await uploader.flush()
        XCTAssertEqual(outcome, .retained)
        XCTAssertEqual(buffer.count, 1, "kept for retry")
        let delay = await uploader.pendingDelay
        XCTAssertEqual(delay, 1, "one transient failure → base backoff")
    }

    func testRateLimitRetains() async {
        let buffer = InMemoryEventBuffer()
        buffer.append(makeBufferedEvent(id: "a"))
        let uploader = makeUploader(http: MockHTTPClient(status: 429), buffer: buffer)
        await uploader.configure(apiKey: "k", installID: "i", manifest: manifest)
        let outcome = await uploader.flush()
        XCTAssertEqual(outcome, .retained)
        XCTAssertEqual(buffer.count, 1)
    }

    func testNetworkErrorRetains() async {
        let buffer = InMemoryEventBuffer()
        buffer.append(makeBufferedEvent(id: "a"))
        let http = MockHTTPClient(responder: { _ in .failure(MockNetworkError()) })
        let uploader = makeUploader(http: http, buffer: buffer)
        await uploader.configure(apiKey: "k", installID: "i", manifest: manifest)
        let outcome = await uploader.flush()
        XCTAssertEqual(outcome, .retained)
        XCTAssertEqual(buffer.count, 1)
    }

    func testAuthFailureHoldsUntilRestart() async {
        let buffer = InMemoryEventBuffer()
        buffer.append(makeBufferedEvent(id: "a"))
        let uploader = makeUploader(http: MockHTTPClient(status: 401), buffer: buffer)
        await uploader.configure(apiKey: "k", installID: "i", manifest: manifest)

        let held = await uploader.flush()
        XCTAssertEqual(held, .held)
        XCTAssertEqual(buffer.count, 1, "not dropped")
        let next = await uploader.flush()
        XCTAssertEqual(next, .notConfigured, "stops flushing until reconfigure")
    }

    func testPermanentRejectionDrops() async {
        let buffer = InMemoryEventBuffer()
        buffer.append(makeBufferedEvent(id: "a"))
        let uploader = makeUploader(http: MockHTTPClient(status: 400), buffer: buffer)
        await uploader.configure(apiKey: "k", installID: "i", manifest: manifest)

        let outcome = await uploader.flush()
        XCTAssertEqual(outcome, .dropped(1))
        XCTAssertEqual(buffer.count, 0, "removed so it can't poison the queue")
    }

    func testNoOpWhenNotConfigured() async {
        let buffer = InMemoryEventBuffer()
        buffer.append(makeBufferedEvent(id: "a"))
        let uploader = makeUploader(http: MockHTTPClient(status: 200), buffer: buffer)
        let outcome = await uploader.flush()
        XCTAssertEqual(outcome, .notConfigured)
    }

    func testEmptyBuffer() async {
        let uploader = makeUploader(http: MockHTTPClient(status: 200))
        await uploader.configure(apiKey: "k", installID: "i", manifest: manifest)
        let outcome = await uploader.flush()
        XCTAssertEqual(outcome, .empty)
    }

    // MARK: manifest_unknown handshake

    func testManifestUnknownReuploadsDeclarations() async {
        let buffer = InMemoryEventBuffer()
        buffer.append(makeBufferedEvent(id: "a"))
        let http = MockHTTPClient(responder: { url in
            if url.path.contains("v1/events") {
                return .success(HTTPResponse(status: 200, body: Data(#"{"manifest_unknown":true}"#.utf8)))
            }
            return .success(HTTPResponse(status: 200, body: Data()))
        })
        let store = InMemoryStore()
        let uploader = makeUploader(http: http, buffer: buffer, store: store)
        await uploader.configure(apiKey: "k", installID: "i", manifest: manifest)

        let outcome = await uploader.flush()

        XCTAssertEqual(outcome, .sent(1), "events still accepted")
        XCTAssertEqual(buffer.count, 0)
        XCTAssertEqual(http.requests(matching: "v1/declarations").count, 1, "manifest re-uploaded")
        XCTAssertEqual(store.string(forKey: Keys.lastUploadedHash), manifest.declarationHash)
    }

    // MARK: Declarations

    func testDeclarationsUploadedFirstTime() async {
        let http = MockHTTPClient(status: 200)
        let store = InMemoryStore()
        let uploader = makeUploader(http: http, store: store)
        await uploader.configure(apiKey: "k", installID: "i", manifest: manifest)

        await uploader.uploadDeclarationsIfNeeded(now: Date(timeIntervalSince1970: 1000))

        XCTAssertEqual(http.requests(matching: "v1/declarations").count, 1)
        XCTAssertEqual(store.string(forKey: Keys.lastUploadedHash), manifest.declarationHash)
        XCTAssertEqual(store.integer(forKey: Keys.lastUploadedAt), 1000)
    }

    func testDeclarationsSkippedWhenUnchangedAndFresh() async {
        let http = MockHTTPClient(status: 200)
        let store = InMemoryStore()
        store.set(manifest.declarationHash, forKey: Keys.lastUploadedHash)
        store.setInteger(1000, forKey: Keys.lastUploadedAt)
        let uploader = makeUploader(http: http, store: store)
        await uploader.configure(apiKey: "k", installID: "i", manifest: manifest)

        await uploader.uploadDeclarationsIfNeeded(now: Date(timeIntervalSince1970: 1000 + 3600))

        XCTAssertTrue(http.requests(matching: "v1/declarations").isEmpty, "unchanged + fresh → skip")
    }

    func testDeclarationsForcedAfterSevenDays() async {
        let http = MockHTTPClient(status: 200)
        let store = InMemoryStore()
        store.set(manifest.declarationHash, forKey: Keys.lastUploadedHash)
        store.setInteger(1000, forKey: Keys.lastUploadedAt)
        let uploader = makeUploader(http: http, store: store)
        await uploader.configure(apiKey: "k", installID: "i", manifest: manifest)

        let eightDaysLater = Date(timeIntervalSince1970: 1000 + 8 * 24 * 3600)
        await uploader.uploadDeclarationsIfNeeded(now: eightDaysLater)

        XCTAssertEqual(http.requests(matching: "v1/declarations").count, 1, "re-uploaded after 7d")
    }

    // MARK: Erasure

    func testErasureDrainsAndClears() async {
        let http = MockHTTPClient(status: 200)
        let store = InMemoryStore()
        store.set("inst-erase", forKey: Keys.pendingErasureID)
        let uploader = makeUploader(http: http, store: store)
        await uploader.configure(apiKey: "k", installID: "i", manifest: manifest)

        await uploader.drainErasure()

        XCTAssertEqual(http.requests(matching: "v1/erasure").count, 1)
        XCTAssertNil(store.string(forKey: Keys.pendingErasureID), "cleared on success")
    }

    func testErasureKeptOnFailure() async {
        let http = MockHTTPClient(status: 503)
        let store = InMemoryStore()
        store.set("inst-erase", forKey: Keys.pendingErasureID)
        let uploader = makeUploader(http: http, store: store)
        await uploader.configure(apiKey: "k", installID: "i", manifest: manifest)

        await uploader.drainErasure()

        XCTAssertEqual(store.string(forKey: Keys.pendingErasureID), "inst-erase", "retried later")
    }
}
