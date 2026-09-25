import Foundation

/// Values computed once per key and reused until they are `ttl` old.
///
/// For a derived figure that is expensive to compute and barely moves — a walk
/// over weeks of history that prints tenths of an hour — where a few minutes of
/// staleness changes nothing a reader acts on. ``LRUCache`` bounds by count and
/// never expires; this expires, and is bounded too, so a stream of new keys
/// cannot grow it.
///
/// A clock that went backwards expires an entry at once: an entry stored "in
/// the future" is not trusted to still be fresh. A compute that throws caches
/// nothing. Lock-guarded; the compute runs outside the lock, so two callers
/// that miss together both compute (callers that must be single-flight
/// already are).
public final class ExpiringMemo<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {

    /// How long an entry is served after it was stored.
    public let ttl: TimeInterval
    /// Keys held at once; storing past it drops the oldest.
    public let capacity: Int

    private let lock = NSLock()
    private var entries: [Key: (storedAt: Date, value: Value)] = [:]

    public init(ttl: TimeInterval, capacity: Int) {
        precondition(capacity > 0, "An ExpiringMemo must be able to hold something.")
        self.ttl = ttl
        self.capacity = capacity
    }

    /// Keys held now, fresh or not yet swept.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    /// The value for `key` if it was stored less than ``ttl`` before `now`;
    /// otherwise `compute()`'s, stored at `now`.
    public func value(
        for key: Key,
        now: Date = Date(),
        compute: () throws -> Value
    ) rethrows -> Value {
        lock.lock()
        if let entry = entries[key], isFresh(entry.storedAt, now: now) {
            lock.unlock()
            return entry.value
        }
        lock.unlock()

        let fresh = try compute()
        lock.lock()
        entries = entries.filter { isFresh($0.value.storedAt, now: now) }
        if entries[key] == nil, entries.count >= capacity,
           let oldest = entries.min(by: { $0.value.storedAt < $1.value.storedAt })?.key {
            entries[oldest] = nil
        }
        entries[key] = (now, fresh)
        lock.unlock()
        return fresh
    }

    /// Forgets every entry.
    public func removeAll() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    private func isFresh(_ storedAt: Date, now: Date) -> Bool {
        now >= storedAt && now.timeIntervalSince(storedAt) < ttl
    }
}
