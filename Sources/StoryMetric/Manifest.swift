extension SM {

    /// The declared events plus the stable `declaration_hash` derived from them.
    ///
    /// The hash is order-independent: reordering declarations never moves it, while
    /// changing an event name, param id, param type, or `optional` does.
    struct DeclarationManifest: Sendable, Equatable {
        let events: [Event]

        init(events: [Event]) {
            self.events = events
        }

        init<Source: SMEventSource>(_ source: Source.Type) {
            self.init(events: source.allEvents)
        }

        /// A deterministic, order-independent serialization of the declarations.
        var canonicalString: String {
            events
                .sorted { $0.name < $1.name }
                .map { event in
                    let params = event.params
                        .sorted { $0.id < $1.id }
                        .map { "\($0.id):\($0.type.rawValue)\($0.optional ? "?" : "")" }
                        .joined(separator: ",")
                    return "\(event.name)|params:\(params)"
                }
                .joined(separator: ";")
        }

        /// SHA-256 hex of `canonicalString`.
        var declarationHash: String {
            Hashing.hexDigest(of: canonicalString)
        }
    }
}
