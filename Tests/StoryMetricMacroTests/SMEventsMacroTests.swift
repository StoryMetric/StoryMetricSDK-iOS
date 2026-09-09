import XCTest
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import StoryMetricMacros

private let testMacros: [String: Macro.Type] = ["SMEvents": SMEventsMacro.self]

final class SMEventsMacroTests: XCTestCase {

    func testFullExpansion() {
        assertMacroExpansion(
            """
            @SMEvents
            extension SM {
                static let openedPaywall = SM.Event("opened_paywall")
                static let usedSearch = SM.Event("used_search", params: [
                    .string("query"), .int("results"), .bool("from_history", optional: true),
                ])
            }
            """,
            expandedSource: """
            extension SM {
                static let openedPaywall = SM.Event("opened_paywall")
                static let usedSearch = SM.Event("used_search", params: [
                    .string("query"), .int("results"), .bool("from_history", optional: true),
                ])

                public enum Log: SMLogSurface {
                    public static func openedPaywall() {
                        SM._record("opened_paywall", params: [:])
                    }

                    public static func usedSearch(query: String, results: Int, fromHistory: Bool? = nil) {
                        var params: [String: SM.ParamValue] = ["query": .string(query), "results": .int(results)]
                        if let fromHistory {
                            params["from_history"] = .bool(fromHistory)
                        }
                        SM._record("used_search", params: params)
                    }
                }

                public static var log: Log.Type {
                    Log.self
                }

                public static var allEvents: [SM.Event] {
                    [openedPaywall, usedSearch]
                }

                public static func start(apiKey: String) {
                    SM._start(apiKey: apiKey, events: allEvents)
                }
            }
            """,
            macros: testMacros
        )
    }

    func testReservedNameIsRejected() {
        assertMacroExpansion(
            """
            @SMEvents
            extension SM {
                static let bad = SM.Event("$first_launch")
            }
            """,
            expandedSource: """
            extension SM {
                static let bad = SM.Event("$first_launch")

                public enum Log: SMLogSurface {

                }

                public static var log: Log.Type {
                    Log.self
                }

                public static var allEvents: [SM.Event] {
                    []
                }

                public static func start(apiKey: String) {
                    SM._start(apiKey: apiKey, events: allEvents)
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: #"event names starting with "$" are reserved for StoryMetric's automatic events"#,
                    line: 3, column: 22
                )
            ],
            macros: testMacros
        )
    }

    func testPurchaseNameIsRejected() {
        assertMacroExpansion(
            """
            @SMEvents
            extension SM {
                static let bad = SM.Event("purchase")
            }
            """,
            expandedSource: """
            extension SM {
                static let bad = SM.Event("purchase")

                public enum Log: SMLogSurface {

                }

                public static var log: Log.Type {
                    Log.self
                }

                public static var allEvents: [SM.Event] {
                    []
                }

                public static func start(apiKey: String) {
                    SM._start(apiKey: apiKey, events: allEvents)
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: #""purchase" is reserved for StoryMetric's built-in StoreKit capture path; call SM.log.purchase(_:) instead"#,
                    line: 3, column: 22
                )
            ],
            macros: testMacros
        )
    }

    func testSkipsNonEventMembers() {
        assertMacroExpansion(
            """
            @SMEvents
            extension SM {
                static let helper = 42
                static let opened = SM.Event("opened")
            }
            """,
            expandedSource: """
            extension SM {
                static let helper = 42
                static let opened = SM.Event("opened")

                public enum Log: SMLogSurface {
                    public static func opened() {
                        SM._record("opened", params: [:])
                    }
                }

                public static var log: Log.Type {
                    Log.self
                }

                public static var allEvents: [SM.Event] {
                    [opened]
                }

                public static func start(apiKey: String) {
                    SM._start(apiKey: apiKey, events: allEvents)
                }
            }
            """,
            macros: testMacros
        )
    }
}
