#if canImport(AppKit)
import AppKit
import XCTest
@testable import AgenticToolkitHTDV

@MainActor
final class FormViewControllerTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func bump() { lock.withLock { count += 1 } }
        var saves: Int { lock.withLock { count } }
    }

    /// Records the ids of calls made to it, for the delete/extra-action tests below.
    private final class CallRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [String] = []
        func record(_ id: String) { lock.withLock { calls.append(id) } }
        var recorded: [String] { lock.withLock { calls } }
    }

    /// Lets a delete/extra action pause mid-flight so a test can exercise "second tap while the first
    /// is in flight" deterministically, mirroring `FormStateTests`' `SaveRecorder.pauseInFlight()`.
    /// Only the FIRST call to `pause()` actually suspends; every later call returns immediately. That
    /// way, if the guard under test fails to block a second concurrent call, that second call is
    /// observed as an immediate extra invocation rather than deadlocking against this single-slot gate.
    private final class PauseGate: @unchecked Sendable {
        private let lock = NSLock()
        private var hasPausedOnce = false
        private var hasEntered = false
        private var enteredWaiter: CheckedContinuation<Void, Never>?
        private var canRelease = false
        private var releaseWaiter: CheckedContinuation<Void, Never>?

        /// Called from inside the action under test: on the first call, signals `waitUntilEntered()`
        /// then suspends until the test calls `release()`. Later calls are no-ops.
        func pause() async {
            let shouldPause = lock.withLock { () -> Bool in
                guard !hasPausedOnce else { return false }
                hasPausedOnce = true
                hasEntered = true
                if let waiter = enteredWaiter {
                    enteredWaiter = nil
                    waiter.resume()
                }
                return true
            }
            guard shouldPause else { return }
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

        /// Called from the test: suspends until a paused `pause()` has recorded its entry.
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

        /// Called from the test: lets a paused `pause()` continue.
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

    private enum FormTestError: Error, LocalizedError {
        case boom
        var errorDescription: String? { "boom" }
    }

    // MARK: Brief's spec/VC builders (Step 1)

    private func makeSpec(recorder: Recorder) -> FormSpec {
        FormSpec(
            sections: [
                FormSection(title: "General", fields: [
                    .text(FormTextField(key: "name", label: "Name", isRequired: true)),
                    .toggle(FormToggleField(key: "enabled", label: "Enabled")),
                    .select(FormSelectField(key: "kind", label: "Kind", options: [
                        FormSelectOption(value: "a", title: "A"), FormSelectOption(value: "b", title: "B")
                    ])),
                    .stringSet(FormStringSetField(key: "tags", label: "Tags")),
                    .readOnly(FormReadOnlyField(key: "id", label: "ID", isMonospaced: true)),
                    .markdown(FormMarkdownField(key: "notes", label: "Notes"))
                ])
            ],
            actions: FormActions(save: FormAction(id: "save", title: "Save") { _ in recorder.bump() })
        )
    }

    private func makeVC(recorder: Recorder = Recorder(), values: [String: FormValue] = [:]) -> FormViewController {
        let state = FormState(spec: makeSpec(recorder: recorder), values: values)
        let formViewController = FormViewController(state: state, markdownEditing: PlainTextMarkdownEditing())
        formViewController.view.frame = NSRect(x: 0, y: 0, width: 600, height: 800)
        formViewController.loadViewIfNeeded()
        return formViewController
    }

    // MARK: Brief's 7 tests (Step 1), verbatim behaviour

    func testBuildsOneControlPerField() {
        let formViewController = makeVC(
            values: ["id": .string("abc"), "kind": .string("b"), "tags": .stringSet(["x", "y"])]
        )
        XCTAssertTrue(formViewController.control(for: "name") is NSTextField)
        XCTAssertTrue(formViewController.control(for: "enabled") is NSSwitch)
        XCTAssertEqual((formViewController.control(for: "kind") as? NSPopUpButton)?.titleOfSelectedItem, "B")
        XCTAssertEqual((formViewController.control(for: "tags") as? NSTextField)?.stringValue, "x, y")
        XCTAssertEqual((formViewController.control(for: "id") as? NSTextField)?.stringValue, "abc")
        XCTAssertNotNil(formViewController.control(for: "notes"))
        XCTAssertFalse(formViewController.saveButton.isEnabled)
        XCTAssertFalse(formViewController.revertButton.isEnabled)
        XCTAssertTrue(formViewController.deleteButton.isHidden)
    }

    func testEditingTextUpdatesStateAndButtons() {
        let formViewController = makeVC()
        guard let field = formViewController.control(for: "name") as? NSTextField else {
            return XCTFail("no text field")
        }
        field.stringValue = "Ada"
        formViewController.textFieldChanged(field)
        XCTAssertEqual(formViewController.state.value(for: "name"), .string("Ada"))
        XCTAssertTrue(formViewController.saveButton.isEnabled)
        XCTAssertTrue(formViewController.revertButton.isEnabled)
        XCTAssertTrue(formViewController.hasUnsavedChanges)
    }

    func testStringSetSplitsOnCommas() {
        let formViewController = makeVC()
        guard let field = formViewController.control(for: "tags") as? NSTextField else {
            return XCTFail("no text field")
        }
        field.stringValue = " a, b ,, c "
        formViewController.textFieldChanged(field)
        XCTAssertEqual(formViewController.state.value(for: "tags"), .stringSet(["a", "b", "c"]))
    }

    func testValidationErrorShownUnderField() {
        let formViewController = makeVC(values: ["name": .string("x")])
        guard let field = formViewController.control(for: "name") as? NSTextField else {
            return XCTFail("no text field")
        }
        field.stringValue = ""
        formViewController.textFieldChanged(field)
        XCTAssertEqual(formViewController.errorLabel(for: "name"), "Name is required")
    }

    func testBlockedReasonShowsLabelAndDisablesSave() {
        let formViewController = makeVC()
        formViewController.state.set(.string("Ada"), for: "name")
        formViewController.state.blockedReason = "Read-only member"
        XCTAssertFalse(formViewController.saveButton.isEnabled)
        XCTAssertEqual(formViewController.blockedLabel.stringValue, "Read-only member")
        XCTAssertFalse(formViewController.blockedLabel.isHidden)
    }

    func testSaveRunsActionAndClearsDirty() async {
        let recorder = Recorder()
        let formViewController = makeVC(recorder: recorder)
        formViewController.state.set(.string("Ada"), for: "name")
        await formViewController.performSave()
        XCTAssertEqual(recorder.saves, 1)
        XCTAssertFalse(formViewController.hasUnsavedChanges)
        XCTAssertFalse(formViewController.saveButton.isEnabled)
    }

    func testRevertRestoresControls() {
        let formViewController = makeVC(values: ["name": .string("orig")])
        formViewController.state.set(.string("changed"), for: "name")
        formViewController.revertButton.performClick(nil)
        XCTAssertEqual((formViewController.control(for: "name") as? NSTextField)?.stringValue, "orig")
        XCTAssertFalse(formViewController.hasUnsavedChanges)
    }

    // MARK: Extended spec/VC builders — surface the brief specifies but its 7 tests never touch

    private func makeConfigurableSpec(
        recorder: Recorder,
        saveShouldFail: Bool = false,
        extra: [FormAction] = [],
        delete: FormDeleteAction? = nil
    ) -> FormSpec {
        FormSpec(
            sections: [
                FormSection(title: "General", fields: [
                    .text(FormTextField(key: "name", label: "Name", isRequired: true)),
                    .text(FormTextField(key: "password", label: "Password", isSecure: true)),
                    .number(FormNumberField(key: "limit", label: "Limit")),
                    .date(FormDateField(key: "due", label: "Due")),
                    .textArea(FormTextAreaField(key: "summary", label: "Summary")),
                    .json(FormJSONField(key: "config", label: "Config")),
                    .markdown(FormMarkdownField(key: "notes", label: "Notes"))
                ])
            ],
            actions: FormActions(
                save: FormAction(id: "save", title: "Save") { _ in
                    recorder.bump()
                    if saveShouldFail { throw FormTestError.boom }
                },
                delete: delete,
                extra: extra
            )
        )
    }

    private func makeConfigurableVC(
        recorder: Recorder = Recorder(),
        values: [String: FormValue] = [:],
        saveShouldFail: Bool = false,
        extra: [FormAction] = [],
        delete: FormDeleteAction? = nil
    ) -> FormViewController {
        let spec = makeConfigurableSpec(
            recorder: recorder, saveShouldFail: saveShouldFail, extra: extra, delete: delete
        )
        let state = FormState(spec: spec, values: values)
        let formViewController = FormViewController(state: state, markdownEditing: PlainTextMarkdownEditing())
        formViewController.view.frame = NSRect(x: 0, y: 0, width: 600, height: 800)
        formViewController.loadViewIfNeeded()
        return formViewController
    }

    // MARK: Delete flow

    func testDeleteButtonVisibleWhenDeleteActionPresent() {
        let formViewController = makeConfigurableVC(delete: FormDeleteAction(title: "Delete Item") {})
        XCTAssertFalse(formViewController.deleteButton.isHidden)
        XCTAssertEqual(formViewController.deleteButton.title, "Delete Item")
    }

    func testDeleteConfirmedInvokesPerformAndOnDeleted() async {
        let performed = CallRecorder()
        let formViewController = makeConfigurableVC(
            delete: FormDeleteAction(title: "Delete") { performed.record("delete") }
        )
        var deletedCalled = false
        formViewController.onDeleted = { deletedCalled = true }
        formViewController.confirmDeleteHandler = { _ in true }
        await formViewController.performDelete()
        XCTAssertEqual(performed.recorded, ["delete"])
        XCTAssertTrue(deletedCalled)
    }

    func testDeleteCancelledDoesNotInvokePerform() async {
        let performed = CallRecorder()
        let formViewController = makeConfigurableVC(
            delete: FormDeleteAction(title: "Delete") { performed.record("delete") }
        )
        var deletedCalled = false
        formViewController.onDeleted = { deletedCalled = true }
        formViewController.confirmDeleteHandler = { _ in false }
        await formViewController.performDelete()
        XCTAssertTrue(performed.recorded.isEmpty)
        XCTAssertFalse(deletedCalled)
    }

    func testDeleteFailureShowsErrorLabel() async {
        let formViewController = makeConfigurableVC(
            delete: FormDeleteAction(title: "Delete") { throw FormTestError.boom }
        )
        formViewController.confirmDeleteHandler = { _ in true }
        await formViewController.performDelete()
        // The ACTION error label, not the save error label: `syncFromState()` owns `errorLabel` and
        // rewrites it on every state change, so a delete failure written there was erased by the
        // user's next keystroke. See `testActionErrorSurvivesASubsequentEdit`.
        XCTAssertEqual(formViewController.actionErrorLabel.stringValue, "boom")
        XCTAssertFalse(formViewController.actionErrorLabel.isHidden)
        XCTAssertTrue(formViewController.errorLabel.isHidden)
    }

    // MARK: confirmDiscard() / hasUnsavedChanges

    func testConfirmDiscardHandlerTrue() async {
        let formViewController = makeConfigurableVC()
        formViewController.confirmDiscardHandler = { true }
        let result = await formViewController.confirmDiscard()
        XCTAssertTrue(result)
    }

    func testConfirmDiscardHandlerFalse() async {
        let formViewController = makeConfigurableVC()
        formViewController.confirmDiscardHandler = { false }
        let result = await formViewController.confirmDiscard()
        XCTAssertFalse(result)
    }

    func testHasUnsavedChangesTracksStateDirty() {
        let formViewController = makeConfigurableVC(values: ["name": .string("orig")])
        XCTAssertFalse(formViewController.hasUnsavedChanges)
        formViewController.state.set(.string("changed"), for: "name")
        XCTAssertTrue(formViewController.hasUnsavedChanges)
        formViewController.state.revert()
        XCTAssertFalse(formViewController.hasUnsavedChanges)
    }

    // MARK: onSaved / save failure

    func testOnSavedFiresOnSuccessfulSave() async {
        let formViewController = makeConfigurableVC(values: ["name": .string("Ada")])
        formViewController.state.set(.string("Ada Two"), for: "name")
        var saved = false
        formViewController.onSaved = { saved = true }
        await formViewController.performSave()
        XCTAssertTrue(saved)
    }

    func testOnSavedNotCalledWhenSaveReturnsFalse() async {
        // "name" is required and stays empty here, so validateAll() fails and state.save() returns false
        // before the save action (and therefore onSaved) ever runs.
        let formViewController = makeConfigurableVC()
        formViewController.state.set(.string("secret"), for: "password")
        var saved = false
        formViewController.onSaved = { saved = true }
        await formViewController.performSave()
        XCTAssertFalse(saved)
    }

    func testSaveFailureSurfacesErrorInErrorLabel() async {
        let formViewController = makeConfigurableVC(values: ["name": .string("Ada")], saveShouldFail: true)
        formViewController.state.set(.string("Ada Two"), for: "name")
        await formViewController.performSave()
        XCTAssertEqual(formViewController.errorLabel.stringValue, "boom")
        XCTAssertFalse(formViewController.errorLabel.isHidden)
    }

    // MARK: actions.extra

    func testExtraActionButtonsInvokeCorrectActionByIdentifier() async {
        let recorderA = CallRecorder()
        let recorderB = CallRecorder()
        let formViewController = makeConfigurableVC(extra: [
            FormAction(id: "actionA", title: "Action A") { _ in recorderA.record("actionA") },
            FormAction(id: "actionB", title: "Action B") { _ in recorderB.record("actionB") }
        ])
        XCTAssertEqual(formViewController.extraButton(for: "actionA")?.title, "Action A")
        XCTAssertEqual(formViewController.extraButton(for: "actionB")?.title, "Action B")
        await formViewController.performExtra(id: "actionA")
        XCTAssertEqual(recorderA.recorded, ["actionA"])
        XCTAssertTrue(recorderB.recorded.isEmpty)
    }

    func testExtraActionFailureShowsErrorLabel() async {
        let formViewController = makeConfigurableVC(extra: [
            FormAction(id: "boom", title: "Boom") { _ in throw FormTestError.boom }
        ])
        await formViewController.performExtra(id: "boom")
        XCTAssertEqual(formViewController.actionErrorLabel.stringValue, "boom")
        XCTAssertFalse(formViewController.actionErrorLabel.isHidden)
        XCTAssertTrue(formViewController.errorLabel.isHidden)
    }

    // MARK: In-flight edits are not reformatted (C3)

    /// `syncFromState()` runs synchronously inside `state.set(...)`, so it used to rewrite the very
    /// field the keystroke came from: "1." parses to 1.0 and formats back to "1", deleting the point
    /// the user just typed and making "1.5" unreachable. Compare-before-assign does not help — "1."
    /// and "1" genuinely differ. The originating control is skipped by identity instead.
    func testTypingATrailingDecimalPointIsNotReformattedAway() {
        let formViewController = makeConfigurableVC()
        guard let field = formViewController.control(for: "limit") as? NSTextField else {
            return XCTFail("no number field")
        }
        field.stringValue = "1."
        formViewController.textFieldChanged(field)
        XCTAssertEqual(field.stringValue, "1.")
        XCTAssertEqual(formViewController.state.value(for: "limit"), .number(1))
    }

    /// The same bug at the start of a negative number: "-" parses to nothing, so the field was
    /// emptied and a negative value could never be typed.
    func testTypingALoneMinusSignIsNotReformattedAway() {
        let formViewController = makeConfigurableVC()
        guard let field = formViewController.control(for: "limit") as? NSTextField else {
            return XCTFail("no number field")
        }
        field.stringValue = "-"
        formViewController.textFieldChanged(field)
        XCTAssertEqual(field.stringValue, "-")
    }

    /// The `.stringSet` shape of the same bug: the trailing comma that starts the next tag was
    /// dropped on every keystroke, so a second tag could never be typed.
    func testTypingATrailingCommaInAStringSetIsNotReformattedAway() {
        let formViewController = makeVC()
        guard let field = formViewController.control(for: "tags") as? NSTextField else {
            return XCTFail("no string set field")
        }
        field.stringValue = "alpha,"
        formViewController.textFieldChanged(field)
        XCTAssertEqual(field.stringValue, "alpha,")
        XCTAssertEqual(formViewController.state.value(for: "tags"), .stringSet(["alpha"]))
    }

    /// The skip lasts only for the duration of the edit — `textFieldChanged` clears
    /// `controlBeingEdited` in a `defer`. Without that, the first field the user ever touched would be
    /// frozen for the lifetime of the form: a later programmatic `state.set` (a revert, a server
    /// round-trip, a computed default) would never reach it.
    func testFieldStillSyncsOnceTheEditIsOver() {
        let formViewController = makeConfigurableVC()
        guard let field = formViewController.control(for: "limit") as? NSTextField else {
            return XCTFail("no number field")
        }
        field.stringValue = "1."
        formViewController.textFieldChanged(field)
        XCTAssertEqual(field.stringValue, "1.")
        formViewController.state.set(.number(2), for: "limit")
        XCTAssertEqual(field.stringValue, "2", "the skip must not outlive the keystroke that caused it")
    }

    // MARK: Null dates (I4)

    private func makeDateVC(isRequired: Bool = false, values: [String: FormValue] = [:]) -> FormViewController {
        let spec = FormSpec(sections: [
            FormSection(fields: [.date(FormDateField(key: "due", label: "Due", isRequired: isRequired))])
        ])
        let formViewController = FormViewController(
            state: FormState(spec: spec, values: values), markdownEditing: PlainTextMarkdownEditing()
        )
        formViewController.loadViewIfNeeded()
        return formViewController
    }

    /// `NSDatePicker` has no empty state, so a null value used to render TODAY — a date the model did
    /// not hold and a save would not store. The row offers "Set date" instead.
    func testDateFieldWithNoValueOffersSetDateInsteadOfShowingToday() {
        let formViewController = makeDateVC()
        XCTAssertEqual(formViewController.state.value(for: "due"), .null)
        XCTAssertEqual(formViewController.datePicker(for: "due")?.isHidden, true)
        XCTAssertEqual(formViewController.dateSetButton(for: "due")?.isHidden, false)
        XCTAssertEqual(formViewController.dateClearButton(for: "due")?.isHidden, true)
    }

    /// "Set date" commits immediately, so the picker never displays a date the model does not hold.
    func testSetDateCommitsTheDisplayedDateImmediately() {
        let formViewController = makeDateVC()
        guard let setButton = formViewController.dateSetButton(for: "due") else { return XCTFail("no button") }
        setButton.sendAction(setButton.action, to: setButton.target)
        guard case .date(let stored) = formViewController.state.value(for: "due") else {
            return XCTFail("date not committed")
        }
        XCTAssertEqual(formViewController.datePicker(for: "due")?.isHidden, false)
        XCTAssertEqual(formViewController.datePicker(for: "due")?.dateValue, stored)
        XCTAssertEqual(formViewController.dateSetButton(for: "due")?.isHidden, true)
    }

    func testClearDateReturnsTheRowToItsEmptyState() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let formViewController = makeDateVC(values: ["due": .date(date)])
        XCTAssertEqual(formViewController.datePicker(for: "due")?.isHidden, false)
        XCTAssertEqual(formViewController.dateClearButton(for: "due")?.isHidden, false)
        guard let clear = formViewController.dateClearButton(for: "due") else { return XCTFail("no button") }
        clear.sendAction(clear.action, to: clear.target)
        XCTAssertEqual(formViewController.state.value(for: "due"), .null)
        XCTAssertEqual(formViewController.datePicker(for: "due")?.isHidden, true)
        XCTAssertEqual(formViewController.dateSetButton(for: "due")?.isHidden, false)
    }

    /// Clearing a required field could only produce a validation error, so it is not offered.
    func testRequiredDateFieldWithAValueOffersNoClearButton() {
        let formViewController = makeDateVC(
            isRequired: true, values: ["due": .date(Date(timeIntervalSince1970: 1_700_000_000))]
        )
        XCTAssertEqual(formViewController.datePicker(for: "due")?.isHidden, false)
        XCTAssertEqual(formViewController.dateClearButton(for: "due")?.isHidden, true)
    }

    // MARK: Action errors outlive the next edit (I5)

    /// `syncFromState()` rewrites `errorLabel` from `state.saveError` on EVERY state change, so a
    /// delete/extra-action failure written there vanished on the user's next keystroke — the report of
    /// the failure disappeared while the failure itself stood.
    func testActionErrorSurvivesASubsequentEdit() async {
        let formViewController = makeConfigurableVC(extra: [
            FormAction(id: "boom", title: "Boom") { _ in throw FormTestError.boom }
        ])
        await formViewController.performExtra(id: "boom")
        formViewController.state.set(.string("Ada"), for: "name")
        XCTAssertEqual(formViewController.actionErrorLabel.stringValue, "boom")
        XCTAssertFalse(formViewController.actionErrorLabel.isHidden)
    }

    /// Re-running an action clears the previous attempt's error, so a success never leaves a stale
    /// failure on screen.
    func testRunningAnActionClearsThePreviousActionError() async {
        let formViewController = makeConfigurableVC(extra: [
            FormAction(id: "boom", title: "Boom") { _ in throw FormTestError.boom },
            FormAction(id: "fine", title: "Fine") { _ in }
        ])
        await formViewController.performExtra(id: "boom")
        XCTAssertEqual(formViewController.actionErrorLabel.stringValue, "boom")
        await formViewController.performExtra(id: "fine")
        XCTAssertEqual(formViewController.actionErrorLabel.stringValue, "")
        XCTAssertTrue(formViewController.actionErrorLabel.isHidden)
    }

    // MARK: Field kinds the brief renders but never tests

    func testNumberFieldStoresNumericValue() {
        let formViewController = makeConfigurableVC()
        guard let field = formViewController.control(for: "limit") as? NSTextField else {
            return XCTFail("no number field")
        }
        field.stringValue = "42"
        formViewController.textFieldChanged(field)
        XCTAssertEqual(formViewController.state.value(for: "limit"), .number(42))
    }

    func testNumberFieldStoresStringForNonNumericInput() {
        let formViewController = makeConfigurableVC()
        guard let field = formViewController.control(for: "limit") as? NSTextField else {
            return XCTFail("no number field")
        }
        field.stringValue = "not-a-number"
        formViewController.textFieldChanged(field)
        XCTAssertEqual(formViewController.state.value(for: "limit"), .string("not-a-number"))
    }

    func testDateFieldUpdatesStateOnChange() {
        let formViewController = makeConfigurableVC()
        // `control(for:)` is the date ROW now (picker + Set date + Clear), so the picker comes from
        // `datePicker(for:)`. See `testDateFieldWithNoValueOffersSetDateInsteadOfShowingToday`.
        guard let picker = formViewController.datePicker(for: "due") else {
            return XCTFail("no date picker")
        }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        picker.dateValue = date
        picker.sendAction(picker.action, to: picker.target)
        XCTAssertEqual(formViewController.state.value(for: "due"), .date(date))
    }

    func testTextAreaFieldUpdatesStateOnEdit() {
        let formViewController = makeConfigurableVC()
        guard let scroll = formViewController.control(for: "summary") as? NSScrollView,
              let textView = scroll.documentView as? NSTextView else { return XCTFail("no text view") }
        let end = NSRange(location: (textView.string as NSString).length, length: 0)
        textView.insertText("hello", replacementRange: end)
        XCTAssertEqual(formViewController.state.value(for: "summary"), .string("hello"))
    }

    func testJSONFieldIsMonospacedAndValidatesContent() {
        let formViewController = makeConfigurableVC()
        guard let scroll = formViewController.control(for: "config") as? NSScrollView,
              let textView = scroll.documentView as? NSTextView else { return XCTFail("no text view") }
        XCTAssertEqual(textView.font, .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular))
        let end = NSRange(location: (textView.string as NSString).length, length: 0)
        textView.insertText("{not json", replacementRange: end)
        XCTAssertEqual(formViewController.errorLabel(for: "config"), "Config must be valid JSON")
    }

    func testSecureTextFieldProducesNSSecureTextField() {
        let formViewController = makeConfigurableVC()
        XCTAssertTrue(formViewController.control(for: "password") is NSSecureTextField)
    }

    // MARK: Markdown revert (Ruling 2)

    func testMarkdownRevertPushesRestoredTextIntoEditor() {
        let formViewController = makeConfigurableVC(values: ["notes": .string("original notes")])
        guard let controlView = formViewController.control(for: "notes"),
              let editor = formViewController.children.first(where: { $0.view === controlView })
                  as? PlainTextEditorViewController
        else { return XCTFail("expected markdown editor child") }
        editor.textView.string = "scratch text"
        formViewController.state.set(.string("scratch text"), for: "notes")
        formViewController.revertButton.performClick(nil)
        XCTAssertEqual(editor.text, "original notes")
        XCTAssertFalse(formViewController.hasUnsavedChanges)
    }

    // MARK: In-flight guards on Delete / extra actions (Fix round 1, Fix 2)

    func testSecondDeleteTapWhileFirstInFlightDoesNotInvokePerformTwice() async {
        let performed = CallRecorder()
        let gate = PauseGate()
        let formViewController = makeConfigurableVC(
            delete: FormDeleteAction(title: "Delete") { performed.record("delete") }
        )
        formViewController.confirmDeleteHandler = { _ in
            await gate.pause()
            return true
        }
        let firstTask = Task { await formViewController.performDelete() }
        await gate.waitUntilEntered()
        XCTAssertFalse(formViewController.deleteButton.isEnabled)
        await formViewController.performDelete()
        XCTAssertTrue(performed.recorded.isEmpty, "the second tap must not reach delete.perform() at all")
        gate.release()
        await firstTask.value
        XCTAssertEqual(performed.recorded, ["delete"])
    }

    func testDeleteButtonReenabledAfterActionCompletes() async {
        let performed = CallRecorder()
        let formViewController = makeConfigurableVC(
            delete: FormDeleteAction(title: "Delete") { performed.record("delete") }
        )
        formViewController.confirmDeleteHandler = { _ in true }
        XCTAssertTrue(formViewController.deleteButton.isEnabled)
        await formViewController.performDelete()
        XCTAssertEqual(performed.recorded, ["delete"])
        XCTAssertTrue(formViewController.deleteButton.isEnabled)
    }

    func testSecondExtraActionTapWhileFirstInFlightDoesNotInvokePerformTwice() async {
        let recorder = CallRecorder()
        let gate = PauseGate()
        let formViewController = makeConfigurableVC(extra: [
            FormAction(id: "longRunning", title: "Long Running") { _ in
                await gate.pause()
                recorder.record("longRunning")
            }
        ])
        let firstTask = Task { await formViewController.performExtra(id: "longRunning") }
        await gate.waitUntilEntered()
        XCTAssertEqual(formViewController.extraButton(for: "longRunning")?.isEnabled, false)
        await formViewController.performExtra(id: "longRunning")
        XCTAssertTrue(recorder.recorded.isEmpty, "the second tap must not reach the action's perform at all")
        gate.release()
        await firstTask.value
        XCTAssertEqual(recorder.recorded, ["longRunning"])
    }

    func testExtraActionButtonReenabledAfterActionCompletes() async {
        let recorder = CallRecorder()
        let formViewController = makeConfigurableVC(extra: [
            FormAction(id: "actionA", title: "Action A") { _ in recorder.record("actionA") }
        ])
        XCTAssertEqual(formViewController.extraButton(for: "actionA")?.isEnabled, true)
        await formViewController.performExtra(id: "actionA")
        XCTAssertEqual(recorder.recorded, ["actionA"])
        XCTAssertEqual(formViewController.extraButton(for: "actionA")?.isEnabled, true)
    }
}
#endif
