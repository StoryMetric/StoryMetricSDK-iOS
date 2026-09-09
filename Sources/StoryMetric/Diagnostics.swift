import Foundation
import os

extension SM {

    /// How much the SDK reports about what it's doing. Off by default; set it before
    /// `start` to trace an integration. Output goes to the unified log (and Xcode's
    /// console) under the `com.storymetric` subsystem.
    public enum LogLevel: Int, Sendable, Comparable {
        /// Silence, including integration mistakes. Rarely what you want.
        case off
        /// The default. Integration problems only — an undeclared event, a param of
        /// the wrong type, a rejected API key. Silent for a correct integration.
        case error
        /// Everything above plus lifecycle and upload activity.
        case debug

        public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public static var logLevel: LogLevel {
        get { Diag.level }
        set { Diag.level = newValue }
    }
}

enum Diag {
    private static let lock = NSLock()
    private static var stored: SM.LogLevel = .error
    private static let logger = Logger(subsystem: "com.storymetric", category: "sdk")

    static var level: SM.LogLevel {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }

    static func error(_ message: @autoclosure () -> String) {
        guard level >= .error else { return }
        let text = message()
        logger.error("[StoryMetric] \(text, privacy: .public)")
    }

    static func debug(_ message: @autoclosure () -> String) {
        guard level >= .debug else { return }
        let text = message()
        logger.notice("[StoryMetric] \(text, privacy: .public)")
    }
}

extension SM.ValidationIssue: CustomStringConvertible {
    var description: String {
        switch self {
        case .emptyEventName:
            return "an event was declared with an empty name"
        case .reservedEventName(let name):
            return "`\(name)` is reserved by StoryMetric and can't be declared"
        case .duplicateEvent(let name):
            return "`\(name)` is declared more than once"
        case .emptyParamId(let event):
            return "`\(event)` has a param with an empty id"
        case .duplicateParam(let event, let param):
            return "`\(event)` declares param `\(param)` more than once"
        case .undeclaredEvent(let name):
            return "`\(name)` isn't declared — add it to your @SMEvents extension"
        case .missingRequiredParam(let event, let param):
            return "`\(event)` is missing required param `\(param)`"
        case .undeclaredParam(let event, let param):
            return "`\(event)` was sent undeclared param `\(param)`"
        case .typeMismatch(let event, let param, let expected, let actual):
            return "`\(event)`.`\(param)` expects \(expected.rawValue), got \(actual.rawValue)"
        }
    }
}
