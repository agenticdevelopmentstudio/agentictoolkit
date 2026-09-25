import Foundation

/// Each live session's activity instants, kept between billing passes so a
/// pass reads only the events that arrived since the last one.
///
/// Derivation stays a pure function over a session's *whole* history — that is
/// what makes a crash, a sleep or a reinstall cost nothing — but re-reading
/// that history from the event store every minute is not affordable: a long
/// session has six figures of events, each a random page fetch in a
/// many-gigabyte table, and every live session was re-read every pass. This
/// holds the parsed history (sorted, de-duplicated epoch seconds) plus the
/// event-row cursor it was read up to, so each pass reads the tail and
/// hands the full history to derivation without touching the rest.
///
/// In memory only, deliberately: after a restart the first pass per session
/// reads in full once, which is the old cost paid once instead of every
/// minute, and nothing on disk can drift out of step with the event store.
///
/// Shared by every copy of `BillingTask` (the scheduler may copy the value),
/// hence a class. Bounding and locking are `LRUCache`'s, so a fix
/// to its eviction reaches this cache too.
public final class BillingActivityCache: Sendable {

    /// Sessions held at once. Well above the number of live sessions anyone
    /// runs; past it the least recently used entry goes, and costs only one
    /// full read if that session comes back.
    public static let defaultCapacity = 64

    private struct Entry: Sendable {
        let cursor: Int64
        let seconds: [Int]
    }

    private let entries: LRUCache<String, Entry>
    public var capacity: Int { entries.capacity }

    public init(capacity: Int = BillingActivityCache.defaultCapacity) {
        entries = LRUCache(capacity: capacity)
    }

    /// The session's full activity history as sorted, de-duplicated epoch
    /// seconds, reading from `database` only what is newer than the cached
    /// cursor.
    public func activitySeconds(sessionId: String, database: any BillingPersistence) throws -> [Int] {
        let cached = entries.value(for: sessionId)
        let tail = try database.billingActivitySeconds(sessionId: sessionId, afterId: cached?.cursor ?? 0)
        let merged = Self.merging(tail.seconds, into: cached?.seconds ?? [])
        entries.set(Entry(cursor: tail.lastId, seconds: merged), for: sessionId)
        return merged
    }

    /// Drops a session — called once it has ended, since nothing more will
    /// arrive for it and holding its history would only cost memory.
    public func forget(sessionId: String) {
        entries.removeValue(for: sessionId)
    }

    public var count: Int { entries.count }

    /// `fresh` (any order, may repeat) merged into `sorted` (ascending,
    /// unique), keeping it ascending and unique. The common case — a handful
    /// of new instants all later than everything held — is an append.
    public static func merging(_ fresh: [Int], into sorted: [Int]) -> [Int] {
        guard !fresh.isEmpty else { return sorted }
        let incoming = Array(Set(fresh)).sorted()
        guard let last = sorted.last else { return incoming }
        if incoming[0] > last { return sorted + incoming }

        var result: [Int] = []
        result.reserveCapacity(sorted.count + incoming.count)
        var left = 0, right = 0
        while left < sorted.count || right < incoming.count {
            let next: Int
            if right == incoming.count || (left < sorted.count && sorted[left] <= incoming[right]) {
                next = sorted[left]; left += 1
            } else {
                next = incoming[right]; right += 1
            }
            if result.last != next { result.append(next) }
        }
        return result
    }
}
