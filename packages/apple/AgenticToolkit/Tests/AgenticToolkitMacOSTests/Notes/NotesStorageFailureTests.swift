import AppKit
import XCTest
@testable import AgenticToolkitMacOS

/// A `NoteStorage` whose operations fail on demand.
///
/// Nothing in the suite had one before, so every branch that reports a storage
/// failure to the user was written and never exercised — which is how a
/// failure at launch, and a failure arriving at a pane with no window yet,
/// both went unnoticed.
struct ThrowingNoteStorage: NoteStorage {

    enum Operation: Hashable {
        case fetch, insert, update, delete
    }

    /// A `localizedDescription` distinct enough to assert on: the alert shows
    /// it verbatim, and that it survives the trip is part of the contract.
    struct Failure: LocalizedError {
        var errorDescription: String? { "the database is locked" }
    }

    /// Operations that throw. Anything not listed succeeds.
    let failing: Set<Operation>

    /// What `fetchAllNotes` returns when reading is not the failing operation.
    let stored: [Note]

    init(failing: Set<Operation>, stored: [Note] = []) {
        self.failing = failing
        self.stored = stored
    }

    func fetchAllNotes() throws -> [Note] {
        if failing.contains(.fetch) { throw Failure() }
        return stored
    }

    func insertNote(_ note: Note) throws {
        if failing.contains(.insert) { throw Failure() }
    }

    func updateNote(_ note: Note) throws {
        if failing.contains(.update) { throw Failure() }
    }

    func deleteNote(id: UUID) throws {
        if failing.contains(.delete) { throw Failure() }
    }
}

/// All four failing operations, and the two paths on which a failure used to
/// be swallowed: a load at launch, and a failure that arrives at a pane which
/// has no window yet.
@MainActor
final class NotesStorageFailureTests: XCTestCase {

    private func note() -> Note {
        Note(id: UUID(), content: "Milk",
             createdDate: Date(), modifiedDate: Date(), isPinned: false)
    }

    // MARK: - The four operations

    func testAFailedLoadIsRecorded() async {
        let manager = NotesManager(storage: ThrowingNoteStorage(failing: [.fetch]))

        await manager.loadNotes()

        XCTAssertEqual(manager.storageFailure?.operation, .load)
        XCTAssertEqual(manager.storageFailure?.message, "the database is locked")
        XCTAssertTrue(manager.notes.isEmpty)
    }

    func testAFailedCreateIsRecordedAndTheNoteIsNotListed() async {
        let manager = NotesManager(storage: ThrowingNoteStorage(failing: [.insert]))
        await manager.loadNotes()

        let id = await manager.createNote(content: "Milk")

        XCTAssertNil(id, "a note that could not be persisted is not a note")
        XCTAssertEqual(manager.storageFailure?.operation, .create)
        XCTAssertTrue(manager.notes.isEmpty)
    }

    func testAFailedSaveIsRecorded() async {
        let existing = note()
        let manager = NotesManager(
            storage: ThrowingNoteStorage(failing: [.update], stored: [existing]))
        await manager.loadNotes()
        XCTAssertNil(manager.storageFailure)

        // `togglePin` writes through immediately, so it reaches the save path
        // without the editor's one-second debounce.
        await manager.togglePin(note: existing)

        XCTAssertEqual(manager.storageFailure?.operation, .save)
    }

    func testAFailedDeleteIsRecorded() async {
        let existing = note()
        let manager = NotesManager(
            storage: ThrowingNoteStorage(failing: [.delete], stored: [existing]))
        await manager.loadNotes()
        XCTAssertNil(manager.storageFailure)

        await manager.deleteNote(id: existing.id)

        XCTAssertEqual(manager.storageFailure?.operation, .delete)
    }

    // MARK: - Reaching a user

    /// What the pane's alert would have said, in order. A test host must never
    /// let the real sheet open: `beginSheetModal(for:completionHandler: nil)`
    /// puts a sheet on screen that nothing ever answers, and an application
    /// with an unanswered sheet beeps at every later `performClick(_:)` in the
    /// process instead of clicking.
    private final class PresentedAlerts {
        private(set) var shown: [(failure: NotesStorageFailure, window: NSWindow)] = []
        func record(_ failure: NotesStorageFailure, _ window: NSWindow) {
            shown.append((failure, window))
        }
    }

    /// Builds the pane with its alert routed to `alerts` rather than to a real
    /// sheet, so what reaches the user is something the test can read.
    private func makeSplit(
        _ manager: NotesManager, recordingInto alerts: PresentedAlerts? = nil
    ) -> NotesSplitViewController {
        let name = "notes-failure-tests-\(UUID().uuidString)"
        addTeardownBlock {
            UserDefaults.standard.removeObject(forKey: "NSSplitView Subview Frames \(name)")
        }
        let split = NotesSplitViewController(notesManager: manager, autosaveName: name)
        let recorder = alerts ?? PresentedAlerts()
        split.storageFailurePresenter = { failure, window in recorder.record(failure, window) }
        return split
    }

    private func window(hosting controller: NSViewController) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled], backing: .buffered, defer: true)
        window.contentViewController = controller
        // Nothing here orders this window in, but anything that attaches a
        // sheet to it would — so it is born below the desktop picture.
        window.sinkBehindDesktop()
        addTeardownBlock { @MainActor in window.close() }
        return window
    }

    /// The launch path. `NotesCoordinator.start()` loads before any window
    /// exists, so the notification reaches a pane that cannot show anything.
    /// The failure must still be there afterwards — dropping it is how one
    /// corrupt row turned the notes list silently empty.
    func testAFailureWithNoWindowYetIsLeftPendingRatherThanDropped() async {
        let manager = NotesManager(storage: ThrowingNoteStorage(failing: [.fetch]))
        let split = makeSplit(manager)
        split.loadViewIfNeeded()
        XCTAssertNil(split.view.window)

        await manager.loadNotes()

        XCTAssertNotNil(
            manager.storageFailure,
            "a pane with no window must not claim a failure it cannot show")
    }

    /// And the pane must ask again when it becomes visible, rather than only
    /// when a notification arrives while it already is. Claiming the failure —
    /// clearing it — is what shows it: `clearStorageFailure()` is called by
    /// whichever host put the alert on screen.
    func testAPaneAsksForAPendingFailureWhenItAppears() async {
        let manager = NotesManager(storage: ThrowingNoteStorage(failing: [.fetch]))
        let alerts = PresentedAlerts()
        let split = makeSplit(manager, recordingInto: alerts)
        split.loadViewIfNeeded()
        await manager.loadNotes()
        XCTAssertNotNil(manager.storageFailure)

        let hostWindow = window(hosting: split)
        split.viewDidAppear()

        XCTAssertNil(
            manager.storageFailure,
            "the first pane that can show a pending failure claims it")
        // Claiming it is only half the contract: claiming without showing is
        // exactly the silent drop these tests exist to catch.
        XCTAssertEqual(alerts.shown.count, 1)
        XCTAssertEqual(alerts.shown.first?.failure.operation, .load)
        XCTAssertEqual(alerts.shown.first?.failure.message, "the database is locked")
        XCTAssertTrue(alerts.shown.first?.window === hostWindow,
                      "the sheet belongs to the pane's own window")
    }

    /// The path that already worked, kept honest: a failure arriving at a pane
    /// that is already on screen is claimed by the notification, not left for
    /// the next appearance.
    func testAFailureArrivingAtAVisiblePaneIsClaimedImmediately() async {
        let existing = note()
        let manager = NotesManager(
            storage: ThrowingNoteStorage(failing: [.delete], stored: [existing]))
        let alerts = PresentedAlerts()
        let split = makeSplit(manager, recordingInto: alerts)
        split.loadViewIfNeeded()
        _ = window(hosting: split)
        split.viewDidAppear()
        await manager.loadNotes()
        XCTAssertTrue(alerts.shown.isEmpty, "nothing has failed yet")

        await manager.deleteNote(id: existing.id)

        XCTAssertNil(manager.storageFailure)
        XCTAssertEqual(alerts.shown.count, 1)
        XCTAssertEqual(alerts.shown.first?.failure.operation, .delete)
    }
}
