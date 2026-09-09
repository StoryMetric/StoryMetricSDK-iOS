extension SM {

    /// A declared event: a snake_case name and its params.
    public struct Event: Sendable, Hashable {
        public let name: String
        public let params: [Param]

        public init(
            _ name: String,
            params: [Param] = []
        ) {
            self.name = name
            self.params = params
        }
    }
}
