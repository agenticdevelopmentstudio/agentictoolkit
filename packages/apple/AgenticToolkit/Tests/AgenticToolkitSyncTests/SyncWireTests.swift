import XCTest
@testable import AgenticToolkitSync

final class SyncWireTests: XCTestCase {

    /// A missing fixture is a broken test environment, not a reason to skip
    /// silently (sync fix-wave item p2b): XCTSkip would report these tests
    /// as passing in CI even though nothing was actually verified. Fail
    /// loudly instead so the missing vendor step gets noticed.
    private func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            XCTFail("missing fixture \(name).json — vendor it from the backend repo first")
            throw SyncWireTestsFixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    func testDecodesPullResponseFixture() throws {
        let response = try JSONDecoder().decode(SyncPullResponse.self, from: fixture("pull-response"))
        // Three, not the six this asserted until 2026-09: the manifest advertised
        // chat.chats/chat_messages/chat_participants for a release after the backend's
        // sync registry stopped carrying them. The count is vendored from the backend
        // fixture, which its own sync-fixture-reality.int.test.ts now checks against the
        // live /sync/pull route — so a number that drifts here fails there first.
        XCTAssertEqual(response.manifest.count, 3)
        XCTAssertEqual(response.changes.count, 2)
        XCTAssertEqual(response.changes[0].op, .upsert)
        XCTAssertEqual(response.changes[1].op, .delete)
        XCTAssertNil(response.changes[1].data)
        XCTAssertEqual(response.changes[0].data?["full_name"]?.stringValue, "Groceries")
        XCTAssertFalse(response.hasMore)
    }

    func testPushRequestRoundTripsThroughItsOwnCoding() throws {
        let request = try JSONDecoder().decode(SyncPushRequest.self, from: fixture("push-request"))
        XCTAssertEqual(request.ops.count, 3)
        let roundTripped = try JSONDecoder().decode(SyncPushRequest.self, from: JSONEncoder().encode(request))
        XCTAssertEqual(roundTripped, request)
    }

    func testDecodesPushResponseFixtureIncludingConflictRow() throws {
        let response = try JSONDecoder().decode(SyncPushResponse.self, from: fixture("push-response"))
        XCTAssertEqual(response.results.map(\.status), [.applied, .conflict, .applied])
        XCTAssertNotNil(response.results[1].current)
        XCTAssertEqual(response.watermark, "1058")
        // newVersion is populated on the two `applied` results that actually wrote a
        // row, and absent (nil) on the `conflict` — decode asserts the wire shape both
        // ways (adh sync.md §3).
        XCTAssertEqual(response.results[0].newVersion, "1056")
        XCTAssertNil(response.results[1].newVersion)
        XCTAssertEqual(response.results[2].newVersion, "1058")
    }

    func testUUIDv7IsSortableAndWellFormed() throws {
        let first = SyncID.uuidV7()
        let second = SyncID.uuidV7(now: Date().addingTimeInterval(1))
        XCTAssertNotEqual(first, second)
        XCTAssertLessThan(first, second) // time-ordered prefix ⇒ lexically sortable
        XCTAssertEqual(first.count, 36)
        XCTAssertEqual(first[first.index(first.startIndex, offsetBy: 14)], "7") // version nibble
    }

    /// item (m): RFC 9562 Method 3's whole point is that same-millisecond
    /// ids don't rely on random bits happening to sort correctly — 1000
    /// back-to-back calls (almost certainly landing in the same
    /// millisecond, or a handful) must come out strictly increasing.
    func testUUIDv7RapidCallsAreStrictlyIncreasing() throws {
        let ids = (0..<1000).map { _ in SyncID.uuidV7() }
        for (previous, next) in zip(ids, ids.dropFirst()) {
            XCTAssertLessThan(previous, next)
        }
        XCTAssertEqual(Set(ids).count, ids.count) // no duplicates as a side effect of strict ordering
    }
}

/// Thrown after `XCTFail` so `fixture(_:)` still returns Never on the
/// missing-file path without force-unwrapping.
private enum SyncWireTestsFixtureError: Error {
    case missing(String)
}
