import AgenticToolkitHTDV
import Foundation
import XCTest
@testable import AgenticToolkitHub

final class SupportTests: XCTestCase {
    // MARK: HubError.wrap
    func testWrapPassesHubErrorThrough() {
        XCTAssertEqual(HubError.wrap(HubError.notFound), .notFound)
    }
    func testWrapMapsOtherErrorsToUnexpected() {
        struct Boom: Error {}
        XCTAssertEqual(HubError.wrap(Boom()), .unexpected("Boom()"))
    }
    func testWrapClosureRethrowsAsHubError() async {
        struct Boom: Error {}
        do {
            _ = try await HubError.wrap { () async throws -> Int in throw Boom() }
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? HubError, .unexpected("Boom()"))
        }
        let value = try? await HubError.wrap { () async throws -> Int in 7 }
        XCTAssertEqual(value, 7)
    }

    /// Compile-time regression for the Swift 6 shape every one of tasks 3-18 uses: a `@MainActor` caller
    /// whose closure both reads and writes main-actor state must compile without `sending`, which would
    /// force the closure `nonisolated` and break exactly this access. The assertions are incidental; the
    /// value of this test is that it fails to BUILD if `wrap`'s isolation parameter regresses.
    @MainActor
    final class MainActorCounter {
        private(set) var count = 0
        func increment() { count += 1 }
    }
    @MainActor
    func testWrapCompilesForMainActorCallerReadingAndWritingState() async throws {
        let counter = MainActorCounter()
        let value = try await HubError.wrap { () async throws -> Int in
            counter.increment()
            return counter.count
        }
        XCTAssertEqual(value, 1)
        XCTAssertEqual(counter.count, 1)
    }

    /// Same shape from an `actor` caller.
    actor ActorCounter {
        private(set) var count = 0
        func increment() { count += 1 }
        func run() async throws -> Int {
            try await HubError.wrap { () async throws -> Int in
                self.increment()
                return self.count
            }
        }
    }
    func testWrapCompilesForActorCaller() async throws {
        let counter = ActorCounter()
        let value = try await counter.run()
        XCTAssertEqual(value, 1)
    }

    /// Same shape from a `nonisolated` caller.
    func testWrapCompilesForNonisolatedCaller() async throws {
        let value = try await HubError.wrap { () async throws -> Int in 42 }
        XCTAssertEqual(value, 42)
    }

    // MARK: HubDates
    func testParseAcceptsFractionalAndWholeSeconds() {
        XCTAssertNotNil(HubDates.parse("2026-09-04T10:00:00.000Z"))
        XCTAssertNotNil(HubDates.parse("2026-09-04T10:00:00Z"))
        XCTAssertNil(HubDates.parse("yesterday"))
        XCTAssertNil(HubDates.parse(nil))
    }
    func testDisplayFallsBackWhenMissing() {
        XCTAssertEqual(HubDates.display(nil, fallback: "never"), "never")
        XCTAssertEqual(HubDates.display("", fallback: "never"), "never")
        XCTAssertFalse(HubDates.display("2026-09-04T10:00:00.000Z").isEmpty)
    }
    func testIsoRoundTrips() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(HubDates.iso(date), "2027-01-15T08:00:00.000Z")
        XCTAssertEqual(HubDates.parse(HubDates.iso(date)), date)
    }
    func testValueMapsToFormValue() {
        XCTAssertEqual(HubDates.value(nil), .null)
        XCTAssertEqual(HubDates.value("2027-01-15T08:00:00.000Z"), .date(Date(timeIntervalSince1970: 1_800_000_000)))
    }

    // MARK: Slug
    func testSlugMake() {
        XCTAssertEqual(Slug.make(from: "  Research Agent  "), "research-agent")
        XCTAssertEqual(Slug.make(from: "Hello, World!"), "hello-world")
        XCTAssertEqual(Slug.make(from: "--a--b--"), "a-b")
        XCTAssertEqual(Slug.make(from: ""), "")
    }
    func testSlugPattern() {
        XCTAssertTrue(Slug.isValid("ci-sync"))
        XCTAssertTrue(Slug.isValid("a"))
        XCTAssertFalse(Slug.isValid("-lead"))
        XCTAssertFalse(Slug.isValid("Trail-"))
        XCTAssertFalse(Slug.isValid("has space"))
    }

    // MARK: JSONValue
    func testJSONValueParseAndPretty() throws {
        let value = try JSONValue.parse(#"{"b":1,"a":[true,null,"x"]}"#)
        XCTAssertEqual(value, .object(["b": .int(1), "a": .array([.bool(true), .null, .string("x")])]))
        XCTAssertEqual(value.prettyText, "{\n  \"a\" : [\n    true,\n    null,\n    \"x\"\n  ],\n  \"b\" : 1\n}")
    }
    func testJSONValueParseFailureIsValidation() {
        XCTAssertThrowsError(try JSONValue.parse("{nope")) { error in
            guard case .validation(let message)? = error as? HubError else { return XCTFail("\(error)") }
            XCTAssertTrue(message.hasPrefix("Invalid JSON"), message)
        }
    }
    func testJSONValueCodableRoundTrip() throws {
        let value = JSONValue.object(["n": .number(2.5), "s": .string("hi"), "z": .null])
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: data), value)
    }
    /// 2^53 + 1: the smallest integer a `Double` cannot represent exactly (it rounds to 2^53 + 2, one
    /// even). `case number(Double)` alone would silently corrupt this on the way back out; `case int(Int64)`
    /// is tried first in `init(from:)` specifically so this round-trips unchanged.
    func testJSONValueLargeIntegerRoundTripsExactly() throws {
        let value = JSONValue.int(9_007_199_254_740_993)
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(String(data: data, encoding: .utf8), "9007199254740993")
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: data), value)
    }
    func testStringDictionary() {
        XCTAssertEqual(JSONValue.object(["a": .string("1")]).stringDictionary, ["a": "1"])
        XCTAssertNil(JSONValue.object(["a": .number(1)]).stringDictionary)
        XCTAssertNil(JSONValue.array([]).stringDictionary)
    }

    // MARK: RailPath
    func testRailPath() {
        let path = [HTDVItem(id: "one", label: "One"), HTDVItem(id: "two", label: "Two")]
        XCTAssertEqual(RailPath.id(at: 0, in: path), "one")
        XCTAssertEqual(RailPath.id(at: 1, in: path), "two")
        XCTAssertNil(RailPath.id(at: 2, in: path))
        XCTAssertEqual(RailPath.last(path)?.id, "two")
        XCTAssertNil(RailPath.last([]))
    }

    // MARK: FormDetails
    @MainActor
    func testFormDetailBuildsFormViewControllerWithValuesAndBlockedReason() {
        let spec = FormSpec(sections: [FormSection(fields: [.text(FormTextField(key: "name", label: "Name"))])])
        let detail = FormDetails.form(
            id: "d", title: "Edit", spec: spec, values: ["name": .string("Ada")], blockedReason: "read only"
        )
        XCTAssertEqual(detail.id, "d")
        XCTAssertEqual(detail.title, "Edit")
        let form = detail.make() as? FormViewController
        XCTAssertNotNil(form)
        XCTAssertEqual(form?.state.value(for: "name"), .string("Ada"))
        XCTAssertEqual(form?.state.blockedReason, "read only")
    }
    @MainActor
    func testNoticeIsReadOnlySingleField() {
        let detail = FormDetails.notice(id: "n", title: "Memory", message: FormDetails.unavailableMessage)
        let form = detail.make() as? FormViewController
        XCTAssertEqual(form?.state.spec.fields.count, 1)
        XCTAssertEqual(form?.state.spec.fields.first?.isEditable, false)
        XCTAssertEqual(form?.state.value(for: "notice"), .string("Not available in this version"))
        XCTAssertNil(form?.state.spec.actions.save)
    }
}
