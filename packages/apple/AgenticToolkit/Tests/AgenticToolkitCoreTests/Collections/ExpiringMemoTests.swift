import XCTest
@testable import AgenticToolkitCore

final class ExpiringMemoTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testServesTheStoredValueUntilItExpires() {
        let memo = ExpiringMemo<String, Int>(ttl: 60, capacity: 4)
        var computed = 0
        func read(at offset: TimeInterval) -> Int {
            memo.value(for: "week", now: start.addingTimeInterval(offset)) {
                computed += 1
                return computed
            }
        }
        XCTAssertEqual(read(at: 0), 1)
        XCTAssertEqual(read(at: 59), 1, "fresh: served from the memo")
        XCTAssertEqual(read(at: 60), 2, "ttl old: computed again")
    }

    /// An entry stored "in the future" is not trusted to still be fresh.
    func testAClockThatWentBackwardsExpiresTheEntry() {
        let memo = ExpiringMemo<String, Int>(ttl: 60, capacity: 4)
        _ = memo.value(for: "k", now: start) { 1 }
        XCTAssertEqual(memo.value(for: "k", now: start.addingTimeInterval(-1)) { 2 }, 2)
    }

    func testAThrowingComputeCachesNothing() {
        struct Failure: Error {}
        let memo = ExpiringMemo<String, Int>(ttl: 60, capacity: 4)
        XCTAssertThrowsError(try memo.value(for: "k", now: start) { throw Failure() })
        XCTAssertEqual(memo.count, 0)
    }

    func testStoringPastCapacityDropsTheOldest() {
        let memo = ExpiringMemo<String, Int>(ttl: 600, capacity: 2)
        _ = memo.value(for: "a", now: start) { 1 }
        _ = memo.value(for: "b", now: start.addingTimeInterval(1)) { 2 }
        _ = memo.value(for: "c", now: start.addingTimeInterval(2)) { 3 }
        XCTAssertEqual(memo.count, 2)
        XCTAssertEqual(memo.value(for: "a", now: start.addingTimeInterval(3)) { 9 }, 9, "a was dropped")
        memo.removeAll()
        XCTAssertEqual(memo.count, 0)
    }
}
