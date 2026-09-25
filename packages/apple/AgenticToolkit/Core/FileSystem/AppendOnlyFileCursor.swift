import Foundation

/// Per-path resume points for files that only ever grow — transcripts, logs —
/// so each scan reads only what was appended since the last one.
///
/// Re-reading a 130 MB file to find what its last few lines added is the cost
/// this removes. A file that was replaced (a different inode), shrank, or no
/// longer holds the bytes the cursor was taken over is not the file the cursor
/// describes, and is scanned again from the start. The last check needs the
/// caller's `fingerprint` of the bytes up to an offset: a file rewritten in
/// place at the same or a greater length keeps its inode and its size, and
/// resuming it would keep a result the rewrite changed.
///
/// What a scan accumulates is the caller's `State` — the last title seen, a
/// running count — carried from one scan to the next. The reader is injected:
/// it reads from a byte offset, folds what it reads into the state, and returns
/// the offset the next scan should start at (the end of the last complete
/// record, not the end of the file, so a half-written line is read again whole).
///
/// In memory and bounded: past `capacity` paths the whole map is dropped, which
/// costs one full scan per path. Lock-guarded; scans run outside the lock.
public final class AppendOnlyFileCursor<State: Sendable>: @unchecked Sendable {

    /// Reads `url` from the byte offset, folding what it reads into the state,
    /// and returns the offset the next scan starts at.
    public typealias Reader = @Sendable (_ url: URL, _ from: Int64, _ state: inout State) throws -> Int64
    /// A digest of the file's bytes up to the offset.
    public typealias Fingerprint = @Sendable (_ url: URL, _ upTo: Int64) throws -> String

    private struct Cursor {
        let fileID: UInt64
        let offset: Int64
        let fingerprint: String
        let state: State
    }

    public let capacity: Int
    private let initial: State
    private let read: Reader
    private let fingerprint: Fingerprint
    private let lock = NSLock()
    private var cursors: [String: Cursor] = [:]

    public init(
        capacity: Int,
        initial: State,
        fingerprint: @escaping Fingerprint,
        read: @escaping Reader
    ) {
        self.capacity = capacity
        self.initial = initial
        self.fingerprint = fingerprint
        self.read = read
    }

    /// The state after reading whatever `path` gained since its last scan, or
    /// nil when the file cannot be stat'ed. A read that fails part-way answers
    /// what it had folded in so far and keeps the old cursor.
    public func scan(path: String) -> State? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attrs[.size] as? NSNumber)?.int64Value,
              let fileID = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value
        else { return nil }

        lock.lock()
        let known = cursors[path]
        lock.unlock()

        let url = URL(fileURLWithPath: path)
        var start: Int64 = 0
        var state = initial
        if let known, known.fileID == fileID, known.offset <= size,
           (try? fingerprint(url, known.offset)) == known.fingerprint {
            start = known.offset
            state = known.state
        }

        let end: Int64
        do {
            end = try read(url, start, &state)
        } catch {
            return state
        }
        // No fingerprint, no cursor: the next scan starts from the beginning.
        guard let print = try? fingerprint(url, end) else { return state }

        lock.lock()
        if cursors[path] == nil, cursors.count >= capacity { cursors.removeAll() }
        cursors[path] = Cursor(fileID: fileID, offset: end, fingerprint: print, state: state)
        lock.unlock()
        return state
    }

    /// Where the next scan of `path` starts; nil when it has no cursor.
    public func resumeOffset(path: String) -> Int64? {
        lock.lock()
        defer { lock.unlock() }
        return cursors[path]?.offset
    }

    /// Forgets `path`'s cursor, so its next scan starts from the beginning.
    public func forget(path: String) {
        lock.lock()
        cursors[path] = nil
        lock.unlock()
    }
}
