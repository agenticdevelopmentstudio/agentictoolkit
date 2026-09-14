import XCTest
@testable import AgenticToolkitHTDV

@MainActor
final class FormStateTests: XCTestCase {
    private final class SaveRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [[String: FormValue]] = []
        var shouldFail = false
        /// When true, `pauseInFlight()` is awaited from inside the save action before recording.
        var shouldPauseInFlight = false
        /// The `FormState` under test, wired up after construction so the save action's closure
        /// never has to capture a non-`Sendable` `FormState` directly.
        weak var observedState: FormState?
        /// Snapshot of `observedState?.isSaving`, taken from inside the save action while paused.
        private(set) var isSavingObservedDuringPause: Bool?
        private var hasEntered = false
        private var enteredWaiter: CheckedContinuation<Void, Never>?
        private var canRelease = false
        private var releaseWaiter: CheckedContinuation<Void, Never>?

        func record(_ values: [String: FormValue]) { lock.withLock { stored.append(values) } }
        var saved: [[String: FormValue]] { lock.withLock { stored } }

        /// Called from inside the save action when `shouldPauseInFlight` is set: records whether
        /// `observedState.isSaving` reads true mid-flight, wakes any test awaiting
        /// `waitUntilEntered()`, then suspends until the test calls `release()`.
        func pauseInFlight() async {
            let observedIsSaving = await MainActor.run { observedState?.isSaving }
            lock.withLock {
                isSavingObservedDuringPause = observedIsSaving
                hasEntered = true
                if let waiter = enteredWaiter {
                    enteredWaiter = nil
                    waiter.resume()
                }
            }
            await withCheckedContinuation { continuation in
                lock.withLock {
                    if canRelease {
                        canRelease = false
                        continuation.resume()
                    } else {
                        releaseWaiter = continuation
                    }
                }
            }
        }

        /// Called from the test: suspends until a paused `pauseInFlight()` has recorded its
        /// observation.
        func waitUntilEntered() async {
            await withCheckedContinuation { continuation in
                lock.withLock {
                    if hasEntered {
                        hasEntered = false
                        continuation.resume()
                    } else {
                        enteredWaiter = continuation
                    }
                }
            }
        }

        /// Called from the test: lets a paused `pauseInFlight()` continue.
        func release() {
            lock.withLock {
                if let waiter = releaseWaiter {
                    releaseWaiter = nil
                    waiter.resume()
                } else {
                    canRelease = true
                }
            }
        }
    }

    private struct SaveFailure: Error, LocalizedError {
        var errorDescription: String? { "server said no" }
    }

    private func makeSpec(recorder: SaveRecorder) -> FormSpec {
        FormSpec(
            sections: [
                FormSection(fields: [
                    .text(FormTextField(key: "name", label: "Name", isRequired: true)),
                    .toggle(FormToggleField(key: "enabled", label: "Enabled")),
                    .number(FormNumberField(key: "limit", label: "Limit", minimum: 0))
                ])
            ],
            actions: FormActions(save: FormAction(id: "save", title: "Save") { values in
                if recorder.shouldFail { throw SaveFailure() }
                if recorder.shouldPauseInFlight { await recorder.pauseInFlight() }
                recorder.record(values)
            })
        )
    }

    func testInitialValuesUseDefaultsForMissingKeys() {
        let state = FormState(spec: makeSpec(recorder: SaveRecorder()), values: ["name": .string("x")])
        XCTAssertEqual(state.value(for: "name"), .string("x"))
        XCTAssertEqual(state.value(for: "enabled"), .bool(false))
        XCTAssertEqual(state.value(for: "limit"), .null)
        XCTAssertFalse(state.isDirty)
        XCTAssertFalse(state.canSave)
    }

    func testSetMarksDirtyAndValidatesField() {
        let state = FormState(spec: makeSpec(recorder: SaveRecorder()), values: ["name": .string("x")])
        state.set(.string(""), for: "name")
        XCTAssertTrue(state.isDirty)
        XCTAssertEqual(state.errors["name"], "Name is required")
        XCTAssertTrue(state.canSave, "dirty and unblocked → the button is enabled; save() itself re-validates")
        state.set(.string("x"), for: "name")
        XCTAssertFalse(state.isDirty)
        XCTAssertNil(state.errors["name"])
    }

    func testBlockedReasonDisablesSave() {
        let state = FormState(spec: makeSpec(recorder: SaveRecorder()))
        state.set(.string("a"), for: "name")
        XCTAssertTrue(state.canSave)
        state.blockedReason = "Read-only member"
        XCTAssertFalse(state.canSave)
    }

    func testSaveWithInvalidValuesDoesNotPerform() async {
        let recorder = SaveRecorder()
        let state = FormState(spec: makeSpec(recorder: recorder))
        state.set(.number(-1), for: "limit")
        let didSave = await state.save()
        XCTAssertFalse(didSave)
        XCTAssertEqual(state.errors["name"], "Name is required")
        XCTAssertEqual(state.errors["limit"], "Limit must be at least 0")
        XCTAssertTrue(recorder.saved.isEmpty)
    }

    func testSuccessfulSavePerformsAndRebaselines() async {
        let recorder = SaveRecorder()
        let state = FormState(spec: makeSpec(recorder: recorder))
        state.set(.string("Persona"), for: "name")
        state.set(.bool(true), for: "enabled")
        let didSave = await state.save()
        XCTAssertTrue(didSave)
        XCTAssertEqual(recorder.saved.count, 1)
        XCTAssertEqual(recorder.saved.first?["name"], .string("Persona"))
        XCTAssertEqual(recorder.saved.first?["enabled"], .bool(true))
        XCTAssertFalse(state.isDirty)
        XCTAssertFalse(state.isSaving)
        XCTAssertNil(state.saveError)
    }

    func testFailedSaveKeepsDirtyAndReportsError() async {
        let recorder = SaveRecorder()
        recorder.shouldFail = true
        let state = FormState(spec: makeSpec(recorder: recorder))
        state.set(.string("Persona"), for: "name")
        let didSave = await state.save()
        XCTAssertFalse(didSave)
        XCTAssertTrue(state.isDirty)
        XCTAssertEqual(state.saveError, "server said no")
        XCTAssertFalse(state.isSaving, "a thrown save must not leave the form stuck mid-save forever")
    }

    func testRevertRestoresBaselineAndClearsErrors() {
        let state = FormState(spec: makeSpec(recorder: SaveRecorder()), values: ["name": .string("orig")])
        state.set(.string(""), for: "name")
        state.revert()
        XCTAssertEqual(state.value(for: "name"), .string("orig"))
        XCTAssertFalse(state.isDirty)
        XCTAssertTrue(state.errors.isEmpty)
    }

    func testSetUnknownKeyIsIgnored() {
        let state = FormState(spec: makeSpec(recorder: SaveRecorder()))
        state.set(.string("?"), for: "nope")
        XCTAssertFalse(state.isDirty)
        XCTAssertEqual(state.value(for: "nope"), .null)
    }

    func testOnChangeFiresOnSetAndSave() async {
        let state = FormState(spec: makeSpec(recorder: SaveRecorder()))
        var count = 0
        state.onChange = { _ in count += 1 }
        state.set(.string("a"), for: "name")
        XCTAssertEqual(count, 1)
        _ = await state.save()
        XCTAssertGreaterThanOrEqual(count, 3, "saving → saved transitions each notify")
    }

    func testMarkSavedRebaselinesWithoutPerforming() {
        let recorder = SaveRecorder()
        let state = FormState(spec: makeSpec(recorder: recorder), values: ["name": .string("orig")])
        state.set(.string("Changed"), for: "name")
        XCTAssertTrue(state.isDirty)
        state.markSaved()
        XCTAssertFalse(state.isDirty)
        XCTAssertEqual(state.value(for: "name"), .string("Changed"))
        XCTAssertTrue(recorder.saved.isEmpty, "markSaved must not invoke the save action")
    }

    func testOnChangeFiresOnRevert() {
        let state = FormState(spec: makeSpec(recorder: SaveRecorder()), values: ["name": .string("orig")])
        state.set(.string("edited"), for: "name")
        var fired = false
        state.onChange = { _ in fired = true }
        state.revert()
        XCTAssertTrue(fired)
    }

    func testOnChangeFiresOnMarkSaved() {
        let state = FormState(spec: makeSpec(recorder: SaveRecorder()), values: ["name": .string("orig")])
        state.set(.string("edited"), for: "name")
        var fired = false
        state.onChange = { _ in fired = true }
        state.markSaved()
        XCTAssertTrue(fired)
    }

    func testOnChangeFiresOnBlockedReasonChange() {
        let state = FormState(spec: makeSpec(recorder: SaveRecorder()))
        var fired = false
        state.onChange = { _ in fired = true }
        state.blockedReason = "Read-only member"
        XCTAssertTrue(fired)
    }

    func testCanSaveFalseAndSaveReturnsFalseWithNoSaveAction() async {
        let spec = FormSpec(sections: [
            FormSection(fields: [.text(FormTextField(key: "name", label: "Name"))])
        ])
        let state = FormState(spec: spec)
        state.set(.string("x"), for: "name")
        XCTAssertFalse(state.canSave)
        let didSave = await state.save()
        XCTAssertFalse(didSave)
    }

    func testIsSavingObservedTrueDuringInFlightSave() async {
        let recorder = SaveRecorder()
        recorder.shouldPauseInFlight = true
        let state = FormState(spec: makeSpec(recorder: recorder))
        recorder.observedState = state
        state.set(.string("Persona"), for: "name")
        let saveTask = Task { await state.save() }
        await recorder.waitUntilEntered()
        XCTAssertEqual(recorder.isSavingObservedDuringPause, true, "observed from inside the save action")
        XCTAssertTrue(state.isSaving)
        recorder.release()
        let didSave = await saveTask.value
        XCTAssertTrue(didSave)
    }

    // MARK: Duplicate field keys (M8)

    /// `FormSpec.fields` flattens every section and `FormState` builds its maps last-write-wins, so
    /// two sections each declaring "name" collapse to one entry. `init` turns that into an
    /// `assertionFailure` (debug only), which a test bundle cannot catch — so the pure detection it
    /// calls is what is asserted here.
    func testDuplicateFieldKeysAcrossSectionsAreDetected() {
        let spec = FormSpec(sections: [
            FormSection(title: "A", fields: [
                .text(FormTextField(key: "name", label: "Name")),
                .text(FormTextField(key: "email", label: "Email"))
            ]),
            FormSection(title: "B", fields: [.text(FormTextField(key: "name", label: "Display name"))])
        ])
        XCTAssertEqual(FormState.duplicateFieldKeys(in: spec), ["name"])
    }

    func testDuplicateFieldKeysReportsEachKeyOnceInFirstSeenOrder() {
        let spec = FormSpec(sections: [
            FormSection(fields: [
                .text(FormTextField(key: "b", label: "B")),
                .text(FormTextField(key: "a", label: "A")),
                .text(FormTextField(key: "b", label: "B again")),
                .text(FormTextField(key: "a", label: "A again")),
                .text(FormTextField(key: "b", label: "B a third time"))
            ])
        ])
        XCTAssertEqual(FormState.duplicateFieldKeys(in: spec), ["b", "a"])
    }

    func testUniqueFieldKeysReportNoDuplicates() {
        let spec = FormSpec(sections: [
            FormSection(fields: [
                .text(FormTextField(key: "name", label: "Name")),
                .toggle(FormToggleField(key: "enabled", label: "Enabled"))
            ])
        ])
        XCTAssertTrue(FormState.duplicateFieldKeys(in: spec).isEmpty)
    }

    // MARK: requiresChanges (create dialogs opt out of the dirty requirement)

    func testPrefilledCreateFormWithRequiresChangesFalseCanSaveBeforeAnyEdit() {
        let state = FormState(spec: makeSpec(recorder: SaveRecorder()), values: ["name": .string("Ada")])
        state.requiresChanges = false
        XCTAssertFalse(state.isDirty)
        XCTAssertTrue(state.canSave, "a create dialog has nothing to change against, so Save is enabled")
    }

    func testEditFormKeepsRequiringAChangeByDefault() {
        let state = FormState(spec: makeSpec(recorder: SaveRecorder()), values: ["name": .string("Ada")])
        XCTAssertFalse(state.isDirty)
        XCTAssertFalse(state.canSave, "requiresChanges defaults to true, so an unedited edit form cannot save")
        state.set(.string("Grace"), for: "name")
        XCTAssertTrue(state.isDirty)
        XCTAssertTrue(state.canSave)
    }

    func testConcurrentEditDuringSaveSurvivesAndStaysDirty() async {
        let recorder = SaveRecorder()
        recorder.shouldPauseInFlight = true
        let state = FormState(spec: makeSpec(recorder: recorder))
        state.set(.string("Persona"), for: "name")
        let saveTask = Task { await state.save() }
        await recorder.waitUntilEntered()
        state.set(.string("Concurrent Edit"), for: "name")
        recorder.release()
        let didSave = await saveTask.value
        XCTAssertTrue(didSave)
        XCTAssertTrue(state.isDirty, "the concurrent edit must still read dirty against the pre-save baseline")
        XCTAssertEqual(state.value(for: "name"), .string("Concurrent Edit"))
    }
}
