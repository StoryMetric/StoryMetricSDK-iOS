import Foundation

extension SM {

    /// The runtime logging core: identity, consent state, and the record path.
    final class Core: @unchecked Sendable {

        static let shared: Core = {
            let store = UserDefaultsStore()
            let clock = SystemClock()
            let buffer = FileEventBuffer.makeDefault()
            let uploader = Uploader(buffer: buffer, http: URLSessionHTTPClient(), store: store)
            let transport = Transport(buffer: buffer, uploader: uploader)
            let sessions = SessionManager(clock: clock, store: store, uuid: { UUID().uuidString })
            return Core(
                store: store, clock: clock, sink: transport, lifecycle: transport,
                sessions: sessions, appLifecycle: SystemLifecycleObserver(),
                appOrigin: SystemAppOrigin()
            )
        }()

        private let lock = NSLock()
        private let store: KeyValueStore
        private let clock: Clock
        private let sink: EventSink
        private let lifecycle: TransportLifecycle?
        private let sessions: SessionManager?
        private let appLifecycle: (any AppLifecycleObserver)?
        private let appOrigin: (any AppOriginSource)?
        private let uuid: () -> String

        private enum State {
            case inactive
            case active(Active)
        }

        private struct Active {
            let apiKey: String
            let installID: String
            let declarations: [String: Event]
            let manifest: DeclarationManifest
        }

        private var state: State = .inactive

        init(
            store: KeyValueStore = UserDefaultsStore(),
            clock: Clock = SystemClock(),
            sink: EventSink = NoopSink(),
            lifecycle: TransportLifecycle? = nil,
            sessions: SessionManager? = nil,
            appLifecycle: (any AppLifecycleObserver)? = nil,
            appOrigin: (any AppOriginSource)? = nil,
            uuid: @escaping () -> String = { UUID().uuidString }
        ) {
            self.store = store
            self.clock = clock
            self.sink = sink
            self.lifecycle = lifecycle
            self.sessions = sessions
            self.appLifecycle = appLifecycle
            self.appOrigin = appOrigin
            self.uuid = uuid
        }

        // MARK: Lifecycle

        /// Activates collection. Idempotent: re-starting keeps the install id.
        func start(apiKey: String, events: [Event]) {
            let manifest = DeclarationManifest(events: events)
            for issue in SM.Validate.manifest(manifest) {
                Diag.error("declaration problem: \(issue)")
            }
            let (installID, isNewInstall): (String, Bool) = {
                lock.lock()
                defer { lock.unlock() }
                let (id, isNew) = ensureInstallID()
                let declarations = Dictionary(
                    events.map { ($0.name, $0) },
                    uniquingKeysWith: { _, latest in latest }
                )
                state = .active(Active(
                    apiKey: apiKey,
                    installID: id,
                    declarations: declarations,
                    manifest: manifest
                ))
                return (id, isNew)
            }()

            Diag.debug("started · \(events.count) declared event(s) · install_id \(installID)")
            lifecycle?.start(apiKey: apiKey, installID: installID, manifest: manifest)

            if let sessions {
                startAppLifecycle()
                for emit in sessions.activated(now: clock.now()) {
                    record(name: emit.name, params: emit.params, sessionIDOverride: emit.sessionID)
                }
                if isNewInstall {
                    recordFirstLaunch()
                }
            }
        }

        private func recordFirstLaunch() {
            guard let appOrigin else {
                record(name: AutoEvent.firstLaunch, params: [:])
                return
            }
            Task { [weak self] in
                let date = await appOrigin.originalDownloadDate()
                var params: [String: ParamValue] = [:]
                if let date {
                    params[AutoEvent.originalDownloadTS] = .string(ISO8601DateFormatter().string(from: date))
                }
                self?.record(name: AutoEvent.firstLaunch, params: params)
            }
        }

        /// Stops collection, erases the local subject, and queues the server
        /// erasure beacon.
        func deleteData() {
            let erasedID: String? = {
                lock.lock()
                defer { lock.unlock() }
                let id = store.string(forKey: Keys.installID)
                if let id { store.set(id, forKey: Keys.pendingErasureID) }
                store.set(nil, forKey: Keys.installID)
                store.setInteger(nil, forKey: Keys.sequence)
                state = .inactive
                return id
            }()
            sessions?.reset()
            if let erasedID { lifecycle?.requestErasure(installID: erasedID) }
        }

#if DEBUG || STORYMETRIC_IDENTITY_TOOLS
        // MARK: Identity control (manual testing seam)

        var debugCurrentInstallID: String? {
            lock.lock(); defer { lock.unlock() }
            return store.string(forKey: Keys.installID)
        }

        func debugResetIdentity() {
            lock.lock()
            store.set(nil, forKey: Keys.installID)
            store.setInteger(nil, forKey: Keys.sequence)
            state = .inactive
            lock.unlock()
            sessions?.reset()
        }

        func debugSetInstallID(_ id: String) {
            lock.lock()
            store.set(id, forKey: Keys.installID)
            store.setInteger(nil, forKey: Keys.sequence)
            state = .inactive
            lock.unlock()
            sessions?.reset()
        }
#endif // DEBUG || STORYMETRIC_IDENTITY_TOOLS

        // MARK: App lifecycle → sessions + background flush

        private func startAppLifecycle() {
            guard let appLifecycle else { return }
            appLifecycle.onForeground = { [weak self] in self?.handleForeground() }
            appLifecycle.onBackground = { [weak self] in self?.handleBackground() }
            appLifecycle.start()
        }

        private func handleForeground() {
            for emit in sessions?.activated(now: clock.now()) ?? [] {
                record(name: emit.name, params: emit.params, sessionIDOverride: emit.sessionID)
            }
        }

        private func handleBackground() {
            sessions?.backgrounded(now: clock.now())
            lifecycle?.flush()
        }

        // MARK: Record

        func record(name: String, params: [String: ParamValue], sessionIDOverride: String? = nil) {
            let envelope: Envelope? = {
                lock.lock()
                defer { lock.unlock() }

                guard case .active(let active) = state else { return nil }

                let flags: [ValidationIssue]
                if ReservedEvent.isReserved(name) {
                    flags = []
                } else if let declaration = active.declarations[name] {
                    flags = SM.Validate.payload(params, against: declaration)
                } else {
                    flags = [.undeclaredEvent(name: name)]
                }

                return Envelope(
                    eventID: uuid(),
                    name: name,
                    params: params,
                    clientTS: clock.now(),
                    eventSequence: nextSequence(),
                    declarationHash: active.manifest.declarationHash,
                    sdkVersion: SM.sdkVersion,
                    sessionID: sessionIDOverride ?? sessions?.currentSessionID,
                    isSandbox: Environment.isSandbox,
                    osVersion: Environment.osVersion,
                    appVersion: Environment.appVersion,
                    platform: Environment.platform,
                    device: Environment.device,
                    locale: Environment.locale,
                    country: Environment.country,
                    flags: flags
                )
            }()

            guard let envelope else {
                Diag.debug("`\(name)` not recorded — SM.start(apiKey:) hasn't been called")
                return
            }
            for issue in envelope.flags {
                Diag.error("\(issue)")
            }
            sink.receive(envelope)
        }

        /// Records the built-in `purchase` event. Its `event_id` is derived from the
        /// transaction, so the same purchase logged twice collapses at ingest.
        func recordPurchase(params: [String: ParamValue], transactionID: String, isSandbox: Bool) {
            let envelope: Envelope? = {
                lock.lock()
                defer { lock.unlock() }

                guard case .active(let active) = state else { return nil }

                return Envelope(
                    eventID: Hashing.deterministicUUID("\(active.apiKey):\(transactionID)"),
                    name: ReservedEvent.purchase,
                    params: params,
                    clientTS: clock.now(),
                    eventSequence: nextSequence(),
                    declarationHash: active.manifest.declarationHash,
                    sdkVersion: SM.sdkVersion,
                    sessionID: sessions?.currentSessionID,
                    isSandbox: isSandbox,
                    osVersion: Environment.osVersion,
                    appVersion: Environment.appVersion,
                    platform: Environment.platform,
                    device: Environment.device,
                    locale: Environment.locale,
                    country: Environment.country,
                    flags: []
                )
            }()

            guard let envelope else {
                Diag.debug("purchase not recorded — SM.start(apiKey:) hasn't been called")
                return
            }
            sink.receive(envelope)
        }

        // MARK: Helpers (lock held)

        private func ensureInstallID() -> (id: String, isNew: Bool) {
            if let existing = store.string(forKey: Keys.installID) {
                return (existing, false)
            }
            let fresh = uuid()
            store.set(fresh, forKey: Keys.installID)
            return (fresh, true)
        }

        private func nextSequence() -> Int {
            let next = (store.integer(forKey: Keys.sequence) ?? 0) + 1
            store.setInteger(next, forKey: Keys.sequence)
            return next
        }
    }
}
