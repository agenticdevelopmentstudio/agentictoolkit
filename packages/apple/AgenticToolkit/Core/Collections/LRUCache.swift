// Core/Collections/LRUCache.swift
import Foundation

/// A bounded key-value store that forgets whatever was used longest ago.
///
/// For state that is cheap to hold a few of and expensive to fetch again — the
/// transcripts a reader is flicking between, say — where keeping every one ever
/// seen would grow without limit and keeping none would refetch on every visit.
///
/// Reads and writes are O(1). Eviction is a scan for the stalest entry, O(n) in
/// the capacity, and only runs when an insert overflows; at the capacities this
/// is meant for (tens) that scan is cheaper than the linked list that would
/// avoid it.
///
/// `@unchecked Sendable` and lock-guarded, so a background fetch can fill it
/// while the main actor reads it.
public final class LRUCache<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {

    private struct Entry {
        var value: Value
        var lastUsed: UInt64
    }

    /// How many entries are kept before the least recently used one goes.
    public let capacity: Int

    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]
    private var clock: UInt64 = 0

    public init(capacity: Int) {
        precondition(capacity > 0, "An LRUCache must be able to hold something.")
        self.capacity = capacity
    }

    /// The value for `key`, marking it as just used; nil when absent.
    public func value(for key: Key) -> Value? {
        withLock {
            guard var entry = entries[key] else { return nil }
            entry.lastUsed = tick()
            entries[key] = entry
            return entry.value
        }
    }

    /// Stores `value` under `key` as the most recently used entry, evicting the
    /// least recently used one if that takes the cache over ``capacity``.
    public func set(_ value: Value, for key: Key) {
        withLock {
            entries[key] = Entry(value: value, lastUsed: tick())
            guard entries.count > capacity,
                  let stalest = entries.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key
            else { return }
            entries.removeValue(forKey: stalest)
        }
    }

    /// Whether `key` is held, without counting as a use.
    public func contains(_ key: Key) -> Bool {
        withLock { entries[key] != nil }
    }

    /// The value for `key` without counting as a use — for a caller deciding
    /// whether to refetch, which is not the reader looking at it.
    public func peek(_ key: Key) -> Value? {
        withLock { entries[key]?.value }
    }

    public func removeValue(for key: Key) {
        withLock { _ = entries.removeValue(forKey: key) }
    }

    public func removeAll() {
        withLock { entries.removeAll() }
    }

    public var count: Int { withLock { entries.count } }

    /// Called with the lock held.
    private func tick() -> UInt64 {
        clock &+= 1
        return clock
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }; return body()
    }
}
