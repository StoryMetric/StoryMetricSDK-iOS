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
}
