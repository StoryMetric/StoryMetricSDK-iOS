extension SM {

    /// The closed set of param types; raw values are the wire tokens.
    public enum ParamType: String, Sendable, Hashable, Codable, CaseIterable {
        case string
        case int
        case double
        case bool
        case stringArray = "string[]"
        case intArray = "int[]"
        case doubleArray = "double[]"
        case boolArray = "bool[]"
    }

    /// A declared param, scoped to its event. Required unless `optional`.
    public struct Param: Sendable, Hashable {
        /// snake_case wire id.
        public let id: String
        public let type: ParamType
        public let optional: Bool

        public init(id: String, type: ParamType, optional: Bool = false) {
            self.id = id
            self.type = type
            self.optional = optional
        }

        public static func string(_ id: String, optional: Bool = false) -> Param {
            Param(id: id, type: .string, optional: optional)
        }
        public static func int(_ id: String, optional: Bool = false) -> Param {
            Param(id: id, type: .int, optional: optional)
        }
        public static func double(_ id: String, optional: Bool = false) -> Param {
            Param(id: id, type: .double, optional: optional)
        }
        public static func bool(_ id: String, optional: Bool = false) -> Param {
            Param(id: id, type: .bool, optional: optional)
        }
        public static func stringArray(_ id: String, optional: Bool = false) -> Param {
            Param(id: id, type: .stringArray, optional: optional)
        }
        public static func intArray(_ id: String, optional: Bool = false) -> Param {
            Param(id: id, type: .intArray, optional: optional)
        }
        public static func doubleArray(_ id: String, optional: Bool = false) -> Param {
            Param(id: id, type: .doubleArray, optional: optional)
        }
        public static func boolArray(_ id: String, optional: Bool = false) -> Param {
            Param(id: id, type: .boolArray, optional: optional)
        }
    }
}
