import Foundation

extension SM {
    /// Result of one events flush.
    enum FlushOutcome: Equatable {
        case notConfigured
        case empty
        case sent(Int)
        case retained
        case held
        case dropped(Int)
    }
}

/// Serializes all network work: event flushes, declaration upload, and the erasure
/// beacon. One flush at a time.
actor Uploader {
    private let buffer: EventBuffer
    private let http: HTTPClient
    private let store: KeyValueStore
    private let baseURL: URL
    private let sdkVersion: String
    private let batchLimit: Int
    private let backoff = Backoff()

    private var apiKey: String?
    private var installID: String?
    private var manifest: SM.DeclarationManifest?
    private var currentHash: String?
    private var holdUntilRestart = false
    private var attempt = 0

    var pendingDelay: TimeInterval { backoff.delay(forAttempt: attempt) }

    init(
        buffer: EventBuffer,
        http: HTTPClient,
        store: KeyValueStore,
        baseURL: URL = SM.Config.baseURL,
        sdkVersion: String = SM.sdkVersion,
        batchLimit: Int = 100
    ) {
        self.buffer = buffer
        self.http = http
        self.store = store
        self.baseURL = baseURL
        self.sdkVersion = sdkVersion
        self.batchLimit = batchLimit
    }

    /// Stops event uploads, keeping the api key so the erasure beacon can still send.
    func deactivate() {
        installID = nil
        currentHash = nil
        manifest = nil
        attempt = 0
    }

    func configure(apiKey: String, installID: String, manifest: SM.DeclarationManifest) {
        self.apiKey = apiKey
        self.installID = installID
        self.manifest = manifest
        self.currentHash = manifest.declarationHash
        self.holdUntilRestart = false
        self.attempt = 0
    }

    // MARK: Events

    @discardableResult
    func flush(now: Date = Date()) async -> SM.FlushOutcome {
        guard let apiKey, let installID, let currentHash, !holdUntilRestart else {
            return .notConfigured
        }
        let events = buffer.peek(limit: batchLimit)
        guard !events.isEmpty else { return .empty }

        let body: Data
        do {
            body = try Wire.eventsBody(
                installID: installID, declarationHash: currentHash,
                sdkVersion: sdkVersion, events: events
            )
        } catch {
            attempt += 1
            return .retained
        }

        do {
            let resp = try await http.send(
                method: "POST", url: url(SM.Config.Path.events),
                headers: Wire.authHeaders(apiKey: apiKey), body: body
            )
            switch HTTPPolicy.classify(resp.status) {
            case .success:
                buffer.remove(ids: events.map(\.eventID))
                attempt = 0
                Diag.debug("uploaded \(events.count) event(s)")
                if Wire.parseManifestUnknown(resp.body), let manifest {
                    store.set(nil, forKey: Keys.lastUploadedHash)
                    _ = await uploadDeclarations(manifest, now: now)
                    self.currentHash = manifest.declarationHash
                }
                return .sent(events.count)
            case .retry:
                attempt += 1
                Diag.debug("ingest returned HTTP \(resp.status) — \(events.count) event(s) retained, retrying in \(Int(pendingDelay))s")
                return .retained
            case .hold:
                holdUntilRestart = true
                Diag.error("ingest rejected the API key (HTTP \(resp.status)) — uploads paused until the next launch")
                return .held
            case .dropPermanent:
                buffer.remove(ids: events.map(\.eventID))
                attempt = 0
                Diag.error("ingest permanently rejected \(events.count) event(s) (HTTP \(resp.status)) — dropped")
                return .dropped(events.count)
            }
        } catch {
            attempt += 1
            Diag.debug("upload failed (\(error.localizedDescription)) — \(events.count) event(s) retained, retrying in \(Int(pendingDelay))s")
            return .retained
        }
    }

    // MARK: Declarations

    /// Uploads when the hash changed or the last successful upload is over 7 days old.
    func uploadDeclarationsIfNeeded(now: Date = Date()) async {
        guard let manifest else { return }
        let hash = manifest.declarationHash
        let last = store.string(forKey: Keys.lastUploadedHash)
        let lastAt = store.integer(forKey: Keys.lastUploadedAt)
        let sevenDays = 7 * 24 * 3600
        let stale = lastAt.map { Int(now.timeIntervalSince1970) - $0 > sevenDays } ?? true
        if last == hash && !stale { return }
        _ = await uploadDeclarations(manifest, now: now)
    }

    @discardableResult
    private func uploadDeclarations(_ manifest: SM.DeclarationManifest, now: Date) async -> Bool {
        guard let apiKey else { return false }
        do {
            let resp = try await http.send(
                method: "POST", url: url(SM.Config.Path.declarations),
                headers: Wire.authHeaders(apiKey: apiKey),
                body: try Wire.declarationsBody(manifest)
            )
            guard (200..<300).contains(resp.status) else {
                Diag.error("declaration upload rejected (HTTP \(resp.status))")
                return false
            }
            Diag.debug("uploaded \(manifest.events.count) declaration(s)")
            store.set(manifest.declarationHash, forKey: Keys.lastUploadedHash)
            store.setInteger(Int(now.timeIntervalSince1970), forKey: Keys.lastUploadedAt)
            return true
        } catch {
            return false
        }
    }

    // MARK: Erasure

    func drainErasure() async {
        guard let apiKey, let id = store.string(forKey: Keys.pendingErasureID) else { return }
        do {
            let resp = try await http.send(
                method: "POST", url: url(SM.Config.Path.erasure),
                headers: Wire.authHeaders(apiKey: apiKey),
                body: try Wire.erasureBody(installID: id)
            )
            if (200..<300).contains(resp.status) {
                store.set(nil, forKey: Keys.pendingErasureID)
            }
        } catch {
            // retried on the next start
        }
    }

    private func url(_ path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }
}
