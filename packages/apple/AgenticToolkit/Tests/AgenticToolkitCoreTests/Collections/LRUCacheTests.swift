import XCTest
@testable import AgenticToolkitCore

final class LRUCacheTests: XCTestCase {

    func testStoresAndReturnsValues() {
        let cache = LRUCache<String, Int>(capacity: 2)
        cache.set(1, for: "a")
        XCTAssertEqual(cache.value(for: "a"), 1)
        XCTAssertNil(cache.value(for: "b"))
    }

    func testOverflowEvictsTheLeastRecentlyUsed() {
        let cache = LRUCache<String, Int>(capacity: 2)
        cache.set(1, for: "a")
        cache.set(2, for: "b")
        // Reading "a" makes "b" the stalest.
        _ = cache.value(for: "a")
        cache.set(3, for: "c")

        XCTAssertEqual(cache.count, 2)
        XCTAssertEqual(cache.peek("a"), 1)
        XCTAssertNil(cache.peek("b"))
        XCTAssertEqual(cache.peek("c"), 3)
    }

    /// A peek is a caller deciding whether to refetch, not a use — it must not
    /// keep an entry alive.
    func testPeekDoesNotCountAsAUse() {
        let cache = LRUCache<String, Int>(capacity: 2)
        cache.set(1, for: "a")
        cache.set(2, for: "b")
        _ = cache.peek("a")
        cache.set(3, for: "c")

        XCTAssertNil(cache.peek("a"))
        XCTAssertTrue(cache.contains("b"))
    }

    func testOverwritingAKeyDoesNotEvict() {
        let cache = LRUCache<String, Int>(capacity: 2)
        cache.set(1, for: "a")
        cache.set(2, for: "b")
        cache.set(10, for: "a")

        XCTAssertEqual(cache.count, 2)
        XCTAssertEqual(cache.peek("a"), 10)
        XCTAssertEqual(cache.peek("b"), 2)
    }

    func testRemoval() {
        let cache = LRUCache<String, Int>(capacity: 3)
        cache.set(1, for: "a")
        cache.set(2, for: "b")
        cache.removeValue(for: "a")
        XCTAssertFalse(cache.contains("a"))
        cache.removeAll()
        XCTAssertEqual(cache.count, 0)
    }

    func testConcurrentUseStaysWithinCapacity() {
        let cache = LRUCache<Int, Int>(capacity: 16)
        DispatchQueue.concurrentPerform(iterations: 1_000) { index in
            cache.set(index, for: index % 64)
            _ = cache.value(for: (index + 7) % 64)
        }
        XCTAssertLessThanOrEqual(cache.count, 16)
    }
}
