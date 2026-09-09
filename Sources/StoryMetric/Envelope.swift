import Foundation

extension SM {

    /// An event as it leaves the logging core, headed for a sink.
    struct Envelope: Sendable, Equatable {
        /// Idempotency key; ingest dedupes on it.
        let eventID: String
        /// snake_case event type id.
        let name: String
        let params: [String: ParamValue]
        let clientTS: Date
        /// Monotonic per device; the ordering authority.
        let eventSequence: Int
        let declarationHash: String
        let sdkVersion: String

        var sessionID: String?
        var isSandbox: Bool
        var osVersion: String?
        var appVersion: String?
        var platform: String?
        var device: String?
        var locale: String?
        var country: String?

        /// Validation issues found at record time. Events are flagged, never dropped.
        var flags: [ValidationIssue]

        init(
            eventID: String,
            name: String,
            params: [String: ParamValue],
            clientTS: Date,
            eventSequence: Int,
            declarationHash: String,
            sdkVersion: String,
            sessionID: String? = nil,
            isSandbox: Bool = false,
            osVersion: String? = nil,
            appVersion: String? = nil,
            platform: String? = nil,
            device: String? = nil,
            locale: String? = nil,
            country: String? = nil,
            flags: [ValidationIssue] = []
        ) {
            self.eventID = eventID
            self.name = name
            self.params = params
            self.clientTS = clientTS
            self.eventSequence = eventSequence
            self.declarationHash = declarationHash
            self.sdkVersion = sdkVersion
            self.sessionID = sessionID
            self.isSandbox = isSandbox
            self.osVersion = osVersion
            self.appVersion = appVersion
            self.platform = platform
            self.device = device
            self.locale = locale
            self.country = country
            self.flags = flags
        }
    }
}
