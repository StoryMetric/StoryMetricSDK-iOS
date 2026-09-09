extension SM {

    /// Activates StoryMetric — the consent lever. Nothing is written to disk and
    /// logging no-ops until this is called.
    public static func start<Source: SMEventSource>(apiKey: String, events: Source.Type) {
        Core.shared.start(apiKey: apiKey, events: events.allEvents)
    }

    /// Stops collection and erases the subject, locally and server-side.
    public static func deleteData() {
        Core.shared.deleteData()
    }

    // MARK: SPI for @SMEvents-generated code

    /// Not for direct use — backs the generated `SM.start(apiKey:)`.
    public static func _start(apiKey: String, events: [Event]) {
        Core.shared.start(apiKey: apiKey, events: events)
    }

    /// Not for direct use — backs the generated `SM.log.<event>()` methods.
    public static func _record(_ name: String, params: [String: ParamValue]) {
        Core.shared.record(name: name, params: params)
    }
}
