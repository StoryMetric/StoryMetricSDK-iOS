import XCTest
@testable import StoryMetric

final class ConfigTests: XCTestCase {

    func testDefaultWhenNoOverride() {
        let url = SM.Config.resolveBaseURL(environment: nil, infoPlist: nil)
        XCTAssertEqual(url, SM.Config.defaultBaseURL)
    }

    func testDefaultHostIsPinned() {
        // Baked into every consumer binary and unchangeable for builds already
        // shipped — changing it should be deliberate, not incidental.
        XCTAssertEqual(SM.Config.defaultBaseURL.absoluteString, "https://ingest.storymetric.app")
    }

    func testEnvironmentWins() {
        let url = SM.Config.resolveBaseURL(
            environment: "http://localhost:8787",
            infoPlist: "https://plist.example"
        )
        XCTAssertEqual(url.absoluteString, "http://localhost:8787")
    }

    func testInfoPlistUsedWhenNoEnvironment() {
        let url = SM.Config.resolveBaseURL(
            environment: nil,
            infoPlist: "https://staging.storymetric.eu"
        )
        XCTAssertEqual(url.absoluteString, "https://staging.storymetric.eu")
    }

    func testEmptyOrWhitespaceIgnored() {
        let url = SM.Config.resolveBaseURL(environment: "   ", infoPlist: "")
        XCTAssertEqual(url, SM.Config.defaultBaseURL)
    }

    func testSchemelessOverrideIgnored() {
        // A bare host with no scheme would build a relative URL — reject it and
        // fall through rather than ship a broken endpoint.
        let url = SM.Config.resolveBaseURL(environment: "localhost:8787", infoPlist: nil)
        XCTAssertEqual(url, SM.Config.defaultBaseURL)
    }

    func testEnvironmentTrimmedBeforeUse() {
        let url = SM.Config.resolveBaseURL(environment: "  http://localhost:8787\n", infoPlist: nil)
        XCTAssertEqual(url.absoluteString, "http://localhost:8787")
    }
}
