import XCTest
@testable import AgenticToolkitMacOS

/// `NotesManager` runs its storage calls off the main actor. That is what
/// keeps SQLite I/O from blocking whichever host shares the main actor — and
/// it is also what removed the ordering the manager used to get for free,
/// because a main-actor call with no suspension point inside it ran to
/// completion before the next one could start.
///
/// The ordering is load-bearing: every write hands storage a *whole* `Note`
/// snapshot taken on the main actor, so a pin toggle issued after a content
/// save carries the pre-save content, and landing first would resurrect it.
/// One write in flight at a time is how the manager keeps issue order and
/// execution order the same thing.
@MainActor
final class NotesManagerStorageOrderingTests: XCTestCase {

    /// Reports the highest number of storage calls that were ever inside it
    /// at once. Each call dwells long enough that genuinely parallel callers
    /// overlap rather than merely appearing to.
    private final class OverlapProbeStorage: NoteStorage, @unchecked Sendable {
        private let lock = NSLock()
        private var inFlight = 0
        private var peak = 0

        var peakConcurrency: Int {
            lock.lock()
            defer { lock.unlock() }
            return peak
        }

        private func dwell() {
            lock.lock()
            inFlight += 1
            peak = max(peak, inFlight)
            lock.unlock()

            Thread.sleep(forTimeInterval: 0.05)

            lock.lock()
            inFlight -= 1
            lock.unlock()
        }

        func fetchAllNotes() throws -> [Note] { [] }
        func insertNote(_ note: Note) throws { dwell() }
        func updateNote(_ note: Note) throws { dwell() }
        func deleteNote(id: UUID) throws { dwell() }
    }

    func testStorageWritesNeverOverlap() async {
        let storage = OverlapProbeStorage()
        let manager = NotesManager(storage: storage)

        var seeded: [Note] = []
        for index in 0..<6 {
            let id = await manager.createNote(content: "note-\(index)")
            let note = try? XCTUnwrap(manager.notes.first(where: { $0.id == id }))
            if let note { seeded.append(note) }
        }
        XCTAssertEqual(seeded.count, 6, "the notes to write to must exist first")

        // Six pin toggles issued together. Each detaches its own storage
        // call, so without the manager's write chain all six are in flight at
        // once and the probe sees a peak of six.
        var running: [Task<Void, Never>] = []
        for note in seeded {
            running.append(Task { await manager.togglePin(note: note) })
        }
        for task in running {
            await task.value
        }

        XCTAssertEqual(storage.peakConcurrency, 1,
                       "storage calls overlapped — the manager's writes are no longer ordered")
    }
}
