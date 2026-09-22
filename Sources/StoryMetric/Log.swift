extension SM {

    /// Activates collection. Call it once, at the app's own launch.
    ///
    /// Everything the SDK does is behind this call: before it, nothing is written,
    /// nothing is uploaded, and every log call is a no-op. Re-starting is harmless
    /// and keeps the install's identity.
    ///
    /// The package alone is enough to call it — sessions and launches are reported
    /// from here on. Milestones need the file Studio generates for the app.
    public static func start(apiKey: String) {
        Core.shared.start(apiKey: apiKey)
    }

    /// Stops collection and erases the subject, locally and server-side.
    public static func deleteData() {
        Core.shared.deleteData()
    }

    // MARK: SPI for Studio-generated code

    /// Not for direct use — backs the generated `SM.log.<event>()` methods.
    public static func _record(_ name: String, params: [String: ParamValue]) {
        Core.shared.record(name: name, params: params)
    }

    /// Not for direct use — backs the generated `SM.mark.<startingPoint>()` methods.
    ///
    /// A starting point is a place in the journey, not an event: nothing is
    /// recorded, nothing is uploaded, and it never appears in anyone's timeline. All
    /// it does is put a stake in this install's foreground time, for a milestone to
    /// measure back to.
    public static func _mark(_ id: String) {
        Core.shared.mark(id)
    }

    /// Not for direct use — backs a generated method whose milestone carries a
    /// screen-time-since property.
    ///
    /// Foreground seconds since that starting point was marked, or nil when it never
    /// was — in which case the generated code leaves the property off the instance
    /// rather than sending a zero.
    public static func _screenTimeSince(_ id: String) -> Double? {
        Core.shared.screenTimeSince(id)
    }
}
