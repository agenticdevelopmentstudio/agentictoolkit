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
/// execution order the same thing — and *both* halves of that sentence are
/// asserted below, because a replacement that serialized without preserving
/// order (a plain lock, a LIFO queue) would re-break exactly this case while
/// looking correct.
@MainActor
final class NotesManagerStorageOrderingTests: XCTestCase {

    /// Records how many storage calls were ever inside it at once, and the
    /// order the notes arrived in. Each call dwells long enough that genuinely
    /// parallel callers overlap rather than merely appearing to.
    private final class OverlapProbeStorage: NoteStorage, @unchecked Sendable {
        private let lock = NSLock()
        private var inFlight = 0
        private var peak = 0
        private var arrivals: [String] = []

        var peakConcurrency: Int {
            lock.lock()
            defer { lock.unlock() }
            return peak
        }

        /// The content of each updated note, in the order storage saw it.
        var updateArrivals: [String] {
            lock.lock()
            defer { lock.unlock() }
            return arrivals
        }

        private func dwell(recording content: String? = nil) {
            lock.lock()
            inFlight += 1
            peak = max(peak, inFlight)
            if let content { arrivals.append(content) }
            lock.unlock()

            Thread.sleep(forTimeInterval: 0.05)

            lock.lock()
            inFlight -= 1
            lock.unlock()
        }

        func fetchAllNotes() throws -> [Note] { [] }
        func insertNote(_ note: Note) throws { dwell() }
        func updateNote(_ note: Note) throws { dwell(recording: note.content) }
        func deleteNote(id: UUID) throws { dwell() }
    }

    /// Issue order, recorded by the test rather than assumed from the order
    /// the six tasks were *created* in — which the runtime does not promise.
    /// The entry is appended immediately before `togglePin`, and `togglePin`
    /// reaches `performStorage` with no suspension point in between, so this
    /// log and the manager's chain are appended to in the same order by the
    /// same actor.
    @MainActor
    private final class IssueLog {
        private(set) var contents: [String] = []
        func record(_ content: String) { contents.append(content) }
    }

    func testStorageWritesRunOneAtATimeInIssueOrder() async throws {
        let storage = OverlapProbeStorage()
        let manager = NotesManager(storage: storage)
        let issued = IssueLog()

        var seeded: [Note] = []
        for index in 0..<24 {
            let id = await manager.createNote(content: "note-\(index)")
            seeded.append(try XCTUnwrap(manager.notes.first(where: { $0.id == id })))
        }

        // Twenty-four pin toggles issued together. Each detaches its own
        // storage call, so without the manager's write chain they are all in
        // flight at once and the probe sees a peak far above one.
        //
        // The count is 24 rather than a handful because the two assertions
        // need different amounts of pressure. Overlap shows at any count;
        // reordering only shows once more callers are queued than the
        // cooperative pool runs at once. A plain `NSLock` in place of the
        // chain was measured granting in arrival order on every one of
        // thirteen runs — so a replacement that reorders has to be given
        // enough contention to actually do it before this assertion can
        // report on it.
        var running: [Task<Void, Never>] = []
        for note in seeded {
            running.append(Task {
                issued.record(note.content)
                await manager.togglePin(note: note)
            })
        }
        for task in running {
            await task.value
        }

        XCTAssertEqual(storage.peakConcurrency, 1,
                       "storage calls overlapped — the manager's writes are no longer ordered")
        XCTAssertEqual(storage.updateArrivals, issued.contents,
                       "storage saw the writes in a different order than they were issued")
    }
}
