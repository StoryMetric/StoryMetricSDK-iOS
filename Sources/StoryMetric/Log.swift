extension SM {

    /// Stops collection and erases the subject, locally and server-side.
    public static func deleteData() {
        Core.shared.deleteData()
    }

    // MARK: SPI for Studio-generated code

    /// Not for direct use — backs the generated `SM.start(apiKey:)`.
    ///
    /// The vocabulary version is the one the generated file was cut from. The SDK
    /// reports it and holds no opinion about it: what a build knows how to log is
    /// settled by the file it was compiled with.
    public static func _start(apiKey: String, vocabularyVersion: Int) {
        Core.shared.start(apiKey: apiKey, vocabularyVersion: vocabularyVersion)
    }

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
