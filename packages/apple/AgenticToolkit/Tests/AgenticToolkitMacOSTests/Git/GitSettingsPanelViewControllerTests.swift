import AgenticToolkitCore
import AppKit
import XCTest
@testable import AgenticToolkitMacOS

@MainActor
final class GitSettingsPanelViewControllerTests: XCTestCase {
    /// Discriminates only the descriptor title literal `"Git"` passed to
    /// `super.init(with:)`. Nothing about the view, the queue, or help
    /// content is exercised here.
    func testPanelDescribesItselfAsGit() {
        let panel = GitSettingsPanelViewController(client: GitClient(configuration: .default))
        XCTAssertEqual(panel.descriptor.title, "Git")
    }

    /// Discriminates the six `accessibilityID` calls made synchronously
    /// inside `viewDidLoad`'s three `settingsView.addGroup` calls -- one per
    /// interactive control, plus the executable-status label itself (the
    /// brief requires this id; it was previously set but never asserted
    /// here).
    func testLoadingTheViewInstallsTheThreeGroups() {
        let panel = GitSettingsPanelViewController(client: GitClient(configuration: .default))
        panel.loadViewIfNeeded()
        let identifiers = Self.accessibilityIdentifiers(in: panel.view)
        let expectedIdentifiers = [
            "settings.git.executable-field",
            "settings.git.choose-executable",
            "settings.git.executable-status",
            "settings.git.timeout-field",
            "settings.git.include-submodules",
            "settings.git.config-table"
        ]
        for expected in expectedIdentifiers {
            XCTAssertTrue(identifiers.contains(expected), "missing \(expected)")
        }
    }

    /// The **second** assertion in each pair is what actually discriminates:
    /// it fails if `UserSettingObserver` (the executable group's live
    /// re-subscription) or the "Found: " branch of `refreshExecutableStatus`
    /// is reverted. The **first** assertion in each pair is non-discriminating
    /// on its own -- the synchronous priming call in `makeExecutableGroup`
    /// already renders "not found" before the observer ever fires -- so both
    /// pairs are kept together rather than relying on either alone.
    ///
    /// Uses `Self.freshGitDefaults()` (F6): the previous version wrote
    /// straight to `UserDefaults.standard` under the developer's real
    /// `git.executable_path` key and relied on `defer` alone to restore it --
    /// a crash or a killed test run between the write and the `defer` left
    /// the developer's real setting corrupted. Pointing `UserSettings.shared`
    /// at an isolated, suite-named `UserDefaults` domain for the duration of
    /// this test removes that risk instead of merely bounding it.
    func testExecutableStatusReflectsTheSetting() async {
        let (_, restore) = Self.freshGitDefaults()
        defer { restore() }
        let panel = GitSettingsPanelViewController(client: GitClient(configuration: .default))
        panel.loadViewIfNeeded()
        UserSettings.gitExecutablePath.value = "/nonexistent/git"
        await Self.drain()
        XCTAssertTrue(panel.executableStatusLabel.stringValue.contains("not found"))
        UserSettings.gitExecutablePath.value = "/usr/bin/git"
        await Self.drain()
        XCTAssertTrue(panel.executableStatusLabel.stringValue.contains("Found"))
    }

    /// Discriminates `enqueueWrite`/`processNextWriteIfNeeded`'s FIFO
    /// ordering (`GitSettingsPanelViewController.pendingWrites`): a rename's
    /// single queued operation runs its own steps in order (see
    /// `testRenameRestoresOldKeyValueWhenSetFails` below), but two
    /// independently-enqueued writes must also run in arrival order.
    /// Reverting `removeFirst()` to anything that does not preserve arrival
    /// order, or starting a second operation before the first's `Task`
    /// completes, fails this test without needing to touch git at all --
    /// the queue takes an opaque `@Sendable () async throws -> Void`
    /// (see `pendingWrites`' doc comment for why this seam, not a `GitClient`
    /// stub, is what makes the queue testable).
    func testEnqueuedWritesRunInFIFOOrder() async {
        let panel = GitSettingsPanelViewController(client: GitClient(configuration: .default))
        let recorder = Recorder()

        panel.enqueueWrite { recorder.record("unset old key") }
        panel.enqueueWrite { recorder.record("set new key") }

        await Self.drainQueue(panel)

        XCTAssertEqual(recorder.entries, ["unset old key", "set new key"])
        // Pins the `reloadGlobalConfig()` call at the end of the drain --
        // deletable while every assertion above still passes, since neither
        // recorded entry depends on it running.
        XCTAssertEqual(panel.reloadCount, 1)
    }

    /// Discriminates the `guard !isProcessingWrites` in
    /// `processNextWriteIfNeeded`: a write enqueued *while another is still
    /// running* (the "third edit arriving mid-drain" scenario the review
    /// flagged) must land after every write that was already queued ahead of
    /// it, not jump the line. `A` suspends on `gate` so the test can observe
    /// -- deterministically, via `pendingWrites`/`isProcessingWrites`, not a
    /// fixed sleep -- the exact moment `A` is running and `B` is queued but
    /// not yet started, enqueue `C` at that moment, then let `A` finish.
    ///
    /// `A`'s own closure cannot call `panel.enqueueWrite` directly: it is
    /// `@Sendable`, and capturing the non-`Sendable`, `@MainActor` panel
    /// inside it does not type-check under Swift 6 strict concurrency (which
    /// is exactly why the write queue takes an opaque operation closure in
    /// the first place -- see `pendingWrites`' doc comment). `gate` is an
    /// `actor`, so it is `Sendable` on its own.
    func testAWriteEnqueuedWhileAnotherIsRunningIsAppendedAfterAlreadyQueuedWrites() async {
        let panel = GitSettingsPanelViewController(client: GitClient(configuration: .default))
        let recorder = Recorder()
        let gate = Gate()

        panel.enqueueWrite {
            recorder.record("A")
            await gate.waitUntilSignaled()
        }
        panel.enqueueWrite { recorder.record("B") }

        // Poll for the moment `A` is running and `B` is the sole queued
        // write -- i.e. mid-drain -- rather than assuming a fixed number of
        // yields gets there.
        for _ in 0..<10_000 {
            if panel.isProcessingWrites, panel.pendingWrites.count == 1 { break }
            await Task.yield()
        }
        XCTAssertTrue(panel.isProcessingWrites, "expected A to still be running")
        XCTAssertEqual(panel.pendingWrites.count, 1, "expected exactly B to be queued behind A")

        panel.enqueueWrite { recorder.record("C") }
        await gate.signal()

        await Self.drainQueue(panel)

        XCTAssertEqual(recorder.entries, ["A", "B", "C"])
        // Pins the `reloadGlobalConfig()` call at the end of the drain, same
        // as `testEnqueuedWritesRunInFIFOOrder`.
        XCTAssertEqual(panel.reloadCount, 1)
    }

    /// Discriminates the `do`/`catch` around `try await operation()` in
    /// `processNextWriteIfNeeded`: one write throwing must not stop the queue
    /// or reorder what follows it (this is the mechanism F3's fix relies on
    /// -- a rejected rename shows an error but does not wedge later,
    /// unrelated edits).
    func testAFailingWriteDoesNotHaltOrReorderTheQueue() async {
        let panel = GitSettingsPanelViewController(client: GitClient(configuration: .default))
        let recorder = Recorder()
        struct Boom: Error {}

        panel.enqueueWrite {
            recorder.record("failing write")
            throw Boom()
        }
        panel.enqueueWrite { recorder.record("later write") }

        await Self.drainQueue(panel)

        XCTAssertEqual(recorder.entries, ["failing write", "later write"])
        // Pins the `reloadGlobalConfig()` call at the end of the drain, same
        // as the other two queue-ordering tests, and -- since this is the
        // one test of the three whose queued operation actually throws --
        // pins the catch block's `showError` call too: deleting either line
        // leaves every assertion above still green.
        XCTAssertEqual(panel.reloadCount, 1)
        XCTAssertNotNil(panel.lastWriteErrorMessage)
    }

    /// Fix round 3: calls `performRename` -- the exact method
    /// `makeGlobalConfigGroup`'s `onRename` closure calls in production --
    /// rather than hand-rolling a copy of its unset/set/restore sequence.
    /// Round 2's version of this test drove a duplicate inline sequence
    /// through `enqueueWrite` directly; the review confirmed that let the
    /// real restore line be deleted from production with both rename tests
    /// still green. `unset`/`set` are the injected throwing stand-ins --
    /// `GitClient` is a concrete `actor` with no protocol seam, so reaching
    /// it from a test is still a hard no -- but the control flow between
    /// them, including the restore, is now the one production runs: a
    /// dropped restore, a swapped `oldKey`/`newKey`, or a wrong value here
    /// fails this test directly. A later, unrelated write still running
    /// afterward is what proves the restore's own throw does not wedge the
    /// queue (mirrors `testAFailingWriteDoesNotHaltOrReorderTheQueue`).
    func testRenameRestoresOldKeyValueWhenSetFails() async {
        let panel = GitSettingsPanelViewController(client: GitClient(configuration: .default))
        let recorder = Recorder()
        struct SetFailed: Error {}

        panel.performRename(
            oldKey: "old.key",
            oldValue: "old.value",
            newKey: "new.key",
            newValue: "new.value",
            unset: { key in recorder.record("unset:\(key)") },
            set: { key, value in
                recorder.record("set:\(key)=\(value)")
                if key == "new.key" { throw SetFailed() }
            }
        )
        panel.enqueueWrite { recorder.record("later write") }

        await Self.drainQueue(panel)

        // "set:old.key=old.value" is the restore call: its presence, in this
        // order and with these exact arguments, is what a swapped argument
        // or a deleted restore would break.
        XCTAssertEqual(
            recorder.entries,
            ["unset:old.key", "set:new.key=new.value", "set:old.key=old.value", "later write"]
        )
    }

    /// Fix round 3, same rationale as the test above: calls `performRename`
    /// directly instead of hand-rolling its control flow. The restore can
    /// itself fail -- a locked config file or a second permissions error,
    /// say -- and that must not be swallowed by only reporting whichever
    /// failure happened last. `performRename` returns `Void`, so the
    /// combined error is observed the way production observes it too: via
    /// `processNextWriteIfNeeded`'s catch block, which stores
    /// `lastWriteErrorMessage`. `SetFailed`/`RestoreFailed` carry distinct
    /// marker text so the assertion can confirm both underlying failures
    /// -- not just one -- reached the final message, plus the "lost"
    /// wording `GitConfigRestoreFailedError.errorDescription` uses only
    /// when both failed.
    func testRenameReportsBothFailuresWhenSetAndRestoreBothFail() async throws {
        let panel = GitSettingsPanelViewController(client: GitClient(configuration: .default))
        let recorder = Recorder()
        struct SetFailed: LocalizedError {
            var errorDescription: String? { "SetFailedMarker" }
        }
        struct RestoreFailed: LocalizedError {
            var errorDescription: String? { "RestoreFailedMarker" }
        }

        panel.performRename(
            oldKey: "old.key",
            oldValue: "old.value",
            newKey: "new.key",
            newValue: "new.value",
            unset: { key in recorder.record("unset:\(key)") },
            set: { key, value in
                recorder.record("set:\(key)=\(value)")
                if key == "new.key" {
                    throw SetFailed()
                } else {
                    throw RestoreFailed()
                }
            }
        )
        panel.enqueueWrite { recorder.record("later write") }

        await Self.drainQueue(panel)

        XCTAssertEqual(
            recorder.entries,
            ["unset:old.key", "set:new.key=new.value", "set:old.key=old.value", "later write"]
        )
        let message = try XCTUnwrap(panel.lastWriteErrorMessage)
        XCTAssertTrue(message.contains("SetFailedMarker"))
        XCTAssertTrue(message.contains("RestoreFailedMarker"))
        XCTAssertTrue(message.contains("lost"))
    }

    private static func accessibilityIdentifiers(in view: NSView) -> Set<String> {
        var found: Set<String> = []
        let id = view.accessibilityIdentifier()
        if !id.isEmpty { found.insert(id) }
        for subview in view.subviews { found.formUnion(accessibilityIdentifiers(in: subview)) }
        return found
    }

    /// Waits for `UserSettingObserver`'s delivery, which lands on the next
    /// turn of the main queue rather than synchronously with the write (see
    /// the dispatch comment on `UserSettingObserver.init` in `UserSetting.swift`).
    /// Same technique `ExternalThemeChangeObservationTests.drain()` uses.
    private static func drain() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    /// Polls until the panel's write queue has fully drained (no operation
    /// running, nothing left queued) rather than guessing how many
    /// `DispatchQueue.main` turns a chain of queued `Task`s needs. Bounded so
    /// a genuinely broken queue fails the test instead of hanging it.
    private static func drainQueue(_ panel: GitSettingsPanelViewController) async {
        for _ in 0..<10_000 {
            if !panel.isProcessingWrites, panel.pendingWrites.isEmpty { return }
            await Task.yield()
        }
        XCTFail("write queue never drained")
    }

    /// Points `UserSettings.shared` at a fresh, isolated `UserDefaults`
    /// domain and re-creates the `gitExecutablePath` static bound to it,
    /// following `ExternalThemeChangeObservationTests.freshDefaults()`. Both
    /// halves matter for the same reason that file documents: `UserSetting`
    /// captures whichever `UserSettings.shared` is live when the static is
    /// first touched, so rebinding only `shared` would leave
    /// `gitExecutablePath` observing a store this test never writes to.
    private static func freshGitDefaults() -> (defaults: UserDefaults, restore: () -> Void) {
        let suiteName = "AgenticToolkitMacOSTests.GitSettingsPanelViewControllerTests"
        let previousShared = UserSettings.shared
        let previousExecutablePath = UserSettings.gitExecutablePath

        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        UserSettings.shared = UserSettings(with: UserDefaultsSettingsStorageProvider(defaults: defaults))
        UserSettings.gitExecutablePath = UserSetting<String>("git.executable_path", default: "/usr/bin/git")

        return (defaults, {
            UserSettings.gitExecutablePath = previousExecutablePath
            UserSettings.shared = previousShared
            defaults.removePersistentDomain(forName: suiteName)
        })
    }
}

/// Records the order operations run in, from inside a `@Sendable` closure
/// running on whatever executor the write queue's `Task`s use. `unchecked`
/// because every write in these tests is enqueued and drained on the main
/// actor, one at a time -- `processNextWriteIfNeeded`'s own
/// `!isProcessingWrites` guard is the thing under test, so nothing here runs
/// two operations concurrently against this recorder.
private final class Recorder: @unchecked Sendable {
    private(set) var entries: [String] = []

    func record(_ entry: String) {
        entries.append(entry)
    }
}

/// A one-shot async gate, used to hold a queued write operation suspended at
/// a known point so a test can observe the write queue mid-drain instead of
/// guessing at timing. Actor-isolated (rather than a lock or a `Task.sleep`)
/// so it is safely `Sendable` on its own without an `@unchecked` escape
/// hatch, and so a signal that arrives before anyone is waiting is not lost.
private actor Gate {
    private var isSignaled = false
    private var continuation: CheckedContinuation<Void, Never>?

    func waitUntilSignaled() async {
        if isSignaled { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func signal() {
        isSignaled = true
        continuation?.resume()
        continuation = nil
    }
}
