import XCTest
@testable import StoryMetric

final class ValidationTests: XCTestCase {

    // MARK: Manifest structure

    func testCleanManifestHasNoIssues() {
        let manifest = SM.DeclarationManifest(SampleEvents.self)
        XCTAssertTrue(SM.Validate.manifest(manifest).isEmpty)
    }

    func testDuplicateEventDetected() {
        let manifest = SM.DeclarationManifest(events: [SM.Event("e"), SM.Event("e")])
        XCTAssertEqual(SM.Validate.manifest(manifest), [.duplicateEvent(name: "e")])
    }

    func testDuplicateParamDetected() {
        let manifest = SM.DeclarationManifest(events: [
            SM.Event("e", params: [.string("x"), .int("x")]),
        ])
        XCTAssertEqual(SM.Validate.manifest(manifest), [.duplicateParam(event: "e", param: "x")])
    }

    func testEmptyNamesDetected() {
        let manifest = SM.DeclarationManifest(events: [
            SM.Event("", params: [.string("")]),
        ])
        let issues = SM.Validate.manifest(manifest)
        XCTAssertTrue(issues.contains(.emptyEventName))
        XCTAssertTrue(issues.contains(.emptyParamId(event: "")))
    }

    // MARK: Payload

    private let search = SM.Event("used_search", params: [
        .string("query"),
        .int("results"),
        .bool("from_history", optional: true),
    ])

    func testValidPayload() {
        let issues = SM.Validate.payload(
            ["query": .string("cats"), "results": .int(3)],
            against: search
        )
        XCTAssertTrue(issues.isEmpty)
    }

    func testMissingRequiredParam() {
        let issues = SM.Validate.payload(["query": .string("cats")], against: search)
        XCTAssertEqual(issues, [.missingRequiredParam(event: "used_search", param: "results")])
    }

    func testOptionalParamMayBeOmitted() {
        let issues = SM.Validate.payload(
            ["query": .string("cats"), "results": .int(3)],
            against: search
        )
        XCTAssertTrue(issues.isEmpty)
    }

    func testTypeMismatch() {
        let issues = SM.Validate.payload(
            ["query": .string("cats"), "results": .string("three")],
            against: search
        )
        XCTAssertEqual(
            issues,
            [.typeMismatch(event: "used_search", param: "results", expected: .int, actual: .string)]
        )
    }

    func testUndeclaredParam() {
        let issues = SM.Validate.payload(
            ["query": .string("cats"), "results": .int(3), "extra": .bool(true)],
            against: search
        )
        XCTAssertEqual(issues, [.undeclaredParam(event: "used_search", param: "extra")])
    }
}
