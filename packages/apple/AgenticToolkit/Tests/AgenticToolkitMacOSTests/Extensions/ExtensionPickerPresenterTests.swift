import AppKit
import Testing
@testable import AgenticToolkitMacOS

/// Pins `ExtensionPickerPresenter` itself — the real conformer to
/// `ExtensionQuickPickPresenting` and `ExtensionInputBoxPresenting`. Every
/// other suite that reaches a picker (`MainThreadWindowQuickPickTests`,
/// `MainThreadWindowInputBoxTests`, `ExtensionsCoordinatorTests`) substitutes
/// a hand-written fake of those two protocols, so the replacement rule, the
/// once-only resume and the two stale-validation guards this class actually
/// implements had never been run.
///
/// Real objects throughout: a real presenter, the real window controller it
/// builds, the real content controllers inside it. The only double is the
/// `validate` closure, which is a protocol parameter and stands in for an
/// extension's async JavaScript — the seam is already there.
///
/// Two things the suite reads by reflection, because the class exposes no
/// seam for either and the alternatives are worse: the presenter's `private
/// var current` (the alternative is scanning `NSApp.windows`, a process-wide
/// list the rest of this bundle also writes to) and the input box controller's
/// `private let model` (the alternative is not testing the value comparison at
/// all — see `validationForASupersededValueIsNotPainted`).
///
/// `.serialized` and `ignoreFocusOut: true` for the same reason: these tests
/// put several real panels on screen in one process, and a panel that
/// dismissed itself the moment another took the keyboard would answer its
/// caller before the test had asked it anything.
@Suite("ExtensionPickerPresenter", .serialized)
@MainActor
struct ExtensionPickerPresenterTests {

    // MARK: - Requests

    private func item(_ label: String) -> ExtensionQuickPickItem {
        ExtensionQuickPickItem(
            label: label,
            description: nil,
            detail: nil,
            isSeparator: false,
            isPicked: false,
            alwaysShow: false
        )
    }

    private func quickPickRequest(items: [ExtensionQuickPickItem]) -> ExtensionQuickPickRequest {
        ExtensionQuickPickRequest(
            title: nil,
            placeHolder: nil,
            prompt: nil,
            items: items,
            canPickMany: false,
            matchOnDescription: false,
            matchOnDetail: false,
            ignoreFocusOut: true
        )
    }

    private func inputBoxRequest(value: String) -> ExtensionInputBoxRequest {
        ExtensionInputBoxRequest(
            title: nil,
            prompt: nil,
            placeHolder: nil,
            value: value,
            valueSelection: nil,
            isPassword: false,
            ignoreFocusOut: true,
            isValidating: false
        )
    }

    // MARK: - Driving one presentation

    /// One `presentQuickPick` call in flight, and its answer once it lands.
    /// The tests never `await` the call itself: a presentation the presenter
    /// fails to resume is the bug several of these tests are looking for, and
    /// awaiting it would hang the run instead of failing it.
    @MainActor
    private final class QuickPickRun {
        private(set) var isFinished = false
        private(set) var indices: [Int]?

        func record(_ indices: [Int]?) {
            self.indices = indices
            isFinished = true
        }
    }

    /// The input box's half of `QuickPickRun`.
    @MainActor
    private final class InputBoxRun {
        private(set) var isFinished = false
        private(set) var value: String?

        func record(_ value: String?) {
            self.value = value
            isFinished = true
        }
    }

    /// The extension's `validateInput`, with its answers held until a test
    /// hands one back. Keyed by nothing: calls are matched by value in arrival
    /// order, so a value validated twice is answered oldest first.
    @MainActor
    private final class ScriptedValidator {
        private typealias Answer = CheckedContinuation<ExtensionInputValidation?, Never>

        private var pending: [(value: String, continuation: Answer)] = []

        func validate(_ value: String) async -> ExtensionInputValidation? {
            await withCheckedContinuation { continuation in
                pending.append((value, continuation))
            }
        }

        func isPending(_ value: String) -> Bool {
            pending.contains { $0.value == value }
        }

        /// Answer the oldest in-flight call for `value`.
        func answer(_ value: String, with validation: ExtensionInputValidation?) {
            guard let index = pending.firstIndex(where: { $0.value == value }) else { return }
            let entry = pending.remove(at: index)
            entry.continuation.resume(returning: validation)
        }

        /// Answer everything still outstanding, so no checked continuation is
        /// left to leak when the test ends.
        func drain() {
            let outstanding = pending
            pending = []
            for entry in outstanding { entry.continuation.resume(returning: nil) }
        }
    }

    private func startQuickPick(
        on presenter: ExtensionPickerPresenter,
        items: [ExtensionQuickPickItem],
        onHighlight: @escaping (Int) -> Void = { _ in }
    ) -> QuickPickRun {
        let run = QuickPickRun()
        let request = quickPickRequest(items: items)
        Task { @MainActor in
            run.record(await presenter.presentQuickPick(request, onHighlight: onHighlight))
        }
        return run
    }

    private func startInputBox(
        on presenter: ExtensionPickerPresenter,
        value: String = "",
        validator: ScriptedValidator
    ) -> InputBoxRun {
        let run = InputBoxRun()
        let request = inputBoxRequest(value: value)
        Task { @MainActor in
            run.record(await presenter.presentInputBox(request, validate: { await validator.validate($0) }))
        }
        return run
    }

    /// Let every main-actor job the last call woke run to its next suspension.
    /// The presenter, the presentations and the validations are all on this
    /// actor, so yielding is what lets them proceed; the count covers a chain
    /// of them (a validator answering resumes a task, which paints, which can
    /// accept, which resumes a presentation).
    private func settle() async {
        for _ in 0..<8 { await Task.yield() }
    }

    // MARK: - Reading the presenter's state back

    /// The panel the presenter is holding, out of its `private var current`.
    /// `current` is `(window:dismiss:)?`, so this is one mirror for the
    /// Optional and one for the tuple inside it.
    private func currentPanel(of presenter: ExtensionPickerPresenter) -> ExtensionPickerWindowController? {
        guard let current = Mirror(reflecting: presenter).children.first(where: { $0.label == "current" }),
              let wrapped = Mirror(reflecting: current.value).children.first else { return nil }
        return Mirror(reflecting: wrapped.value).children
            .first { $0.label == "window" }?
            .value as? ExtensionPickerWindowController
    }

    /// The model the presenter built for this input box, out of the content
    /// controller's `private let model`.
    private func inputModel(of controller: ExtensionInputBoxViewController) -> ExtensionInputBoxModel? {
        Mirror(reflecting: controller).children
            .first { $0.label == "model" }?
            .value as? ExtensionInputBoxModel
    }

    /// The field `ExtensionInputBoxViewController.loadView()` stamps with an
    /// accessibility identifier.
    private func field(of controller: ExtensionInputBoxViewController) -> NSTextField? {
        controller.view.subviews
            .compactMap { $0 as? NSTextField }
            .first { $0.accessibilityIdentifier() == "extension-input-box.field" }
    }

    /// The validation message label — the other `NSTextField` in a panel built
    /// from a request with no title and no prompt.
    private func validationLabel(of controller: ExtensionInputBoxViewController) -> NSTextField? {
        controller.view.subviews
            .compactMap { $0 as? NSTextField }
            .first { $0.accessibilityIdentifier() != "extension-input-box.field" }
    }

    /// Type into the real field and tell the real delegate, which is the path
    /// a keystroke takes: it sets `model.value`, opens the validating window,
    /// and calls the presenter's `onValueChanged`.
    private func type(_ text: String, into controller: ExtensionInputBoxViewController) throws {
        let field = try #require(self.field(of: controller))
        field.stringValue = text
        controller.controlTextDidChange(
            Notification(name: NSControl.textDidChangeNotification, object: field))
    }

    /// Close whatever is still on screen and answer whatever validations are
    /// still in flight, so a test leaves neither a suspended presentation nor
    /// a leaked checked continuation behind it.
    private func tearDown(_ presenter: ExtensionPickerPresenter, _ validators: ScriptedValidator...) async {
        currentPanel(of: presenter)?.close()
        for validator in validators { validator.drain() }
        await settle()
    }

    // MARK: - The replacement rule

    @Test("a second quick pick finishes the first as nil and closes the first window")
    func secondQuickPickDismissesTheFirst() async throws {
        let presenter = ExtensionPickerPresenter()
        let first = startQuickPick(on: presenter, items: [item("a"), item("b")])
        await settle()

        let firstPanel = try #require(currentPanel(of: presenter))
        let firstWindow = try #require(firstPanel.window)
        #expect(firstWindow.isVisible, "the first panel is on screen before the second request arrives")

        let second = startQuickPick(on: presenter, items: [item("c")])
        await settle()

        #expect(first.isFinished, "the replaced request must not be left waiting on a panel nobody can see")
        #expect(first.indices == nil, "a replaced request is dismissed, which is nil")
        #expect(firstWindow.isVisible == false, "the replaced panel's window must be closed")
        #expect(currentPanel(of: presenter) !== firstPanel, "the second panel is the one held now")
        #expect(second.isFinished == false, "the second request is still waiting for an answer")

        await tearDown(presenter)
    }

    @Test("a second input box finishes the first as nil and closes the first window")
    func secondInputBoxDismissesTheFirst() async throws {
        let presenter = ExtensionPickerPresenter()
        let firstValidator = ScriptedValidator()
        let secondValidator = ScriptedValidator()
        let first = startInputBox(on: presenter, validator: firstValidator)
        await settle()

        let firstPanel = try #require(currentPanel(of: presenter))
        let firstWindow = try #require(firstPanel.window)
        #expect(firstWindow.isVisible)

        let second = startInputBox(on: presenter, validator: secondValidator)
        await settle()

        #expect(first.isFinished)
        #expect(first.value == nil, "a replaced input box is dismissed, which is nil")
        #expect(firstWindow.isVisible == false)
        #expect(currentPanel(of: presenter) !== firstPanel)
        #expect(second.isFinished == false)

        await tearDown(presenter, firstValidator, secondValidator)
    }

    @Test("an input box arriving over a quick pick finishes the quick pick as nil")
    func inputBoxReplacesAQuickPick() async throws {
        let presenter = ExtensionPickerPresenter()
        let validator = ScriptedValidator()
        let quickPick = startQuickPick(on: presenter, items: [item("a")])
        await settle()
        let quickPickWindow = try #require(currentPanel(of: presenter)?.window)

        let inputBox = startInputBox(on: presenter, validator: validator)
        await settle()

        #expect(quickPick.isFinished)
        #expect(quickPick.indices == nil)
        #expect(quickPickWindow.isVisible == false)
        #expect(inputBox.isFinished == false)
        let panel = try #require(currentPanel(of: presenter))
        #expect(panel.contentController is ExtensionInputBoxViewController, "the input box is what is on screen")

        await tearDown(presenter, validator)
    }

    @Test("a quick pick arriving over an input box finishes the input box as nil")
    func quickPickReplacesAnInputBox() async throws {
        let presenter = ExtensionPickerPresenter()
        let validator = ScriptedValidator()
        let inputBox = startInputBox(on: presenter, validator: validator)
        await settle()
        let inputBoxWindow = try #require(currentPanel(of: presenter)?.window)

        let quickPick = startQuickPick(on: presenter, items: [item("a")])
        await settle()

        #expect(inputBox.isFinished)
        #expect(inputBox.value == nil)
        #expect(inputBoxWindow.isVisible == false)
        #expect(quickPick.isFinished == false)
        let panel = try #require(currentPanel(of: presenter))
        #expect(panel.contentController is ExtensionQuickPickViewController, "the quick pick is what is on screen")

        await tearDown(presenter, validator)
    }

    // MARK: - Resuming exactly once

    @Test("a window the user closed resumes its caller with nil rather than leaking the continuation")
    func closingTheWindowResumesWithNil() async throws {
        let presenter = ExtensionPickerPresenter()
        let run = startQuickPick(on: presenter, items: [item("a")])
        await settle()

        let panel = try #require(currentPanel(of: presenter))
        panel.close()
        await settle()

        #expect(run.isFinished, "a panel closed without a choice must still answer its caller")
        #expect(run.indices == nil)
    }

    /// The double-resume this class can actually produce. A window the user
    /// closed answers through `onDismiss`, and nothing on that path clears
    /// `current` — so the *next* request's `dismissCurrent()` calls the stale
    /// session's `dismiss` closure and finishes the same continuation a second
    /// time. `OnceOnlyContinuation` is what absorbs it; a bare
    /// `CheckedContinuation` traps the process on the second resume, so the
    /// assertion below is reached only if the second resume never happened.
    @Test("replacing a panel the user already closed resumes its caller exactly once")
    func replacingAnAlreadyDismissedPanelResumesOnce() async throws {
        let presenter = ExtensionPickerPresenter()
        let first = startQuickPick(on: presenter, items: [item("a")])
        await settle()

        let firstPanel = try #require(currentPanel(of: presenter))
        firstPanel.close()
        await settle()
        #expect(first.isFinished)
        #expect(first.indices == nil)

        // `current` still holds the closed panel's session here: this second
        // request is what asks it to finish again.
        let second = startQuickPick(on: presenter, items: [item("b")])
        await settle()

        #expect(first.indices == nil, "the second finish must not have changed the answer already delivered")
        #expect(second.isFinished == false, "the replacement itself is still waiting")

        await tearDown(presenter)
    }

    // MARK: - Teardown ordering

    @Test("accepting a quick pick closes its window, then lets go of the window controller")
    func acceptingQuickPickClosesThenReleasesThePanel() async throws {
        let presenter = ExtensionPickerPresenter()
        let run = startQuickPick(on: presenter, items: [item("a"), item("b")])
        await settle()

        weak var weakPanel: ExtensionPickerWindowController?
        let window: NSWindow = try autoreleasepool {
            let panel = try #require(currentPanel(of: presenter))
            weakPanel = panel
            let window = try #require(panel.window)
            let content = try #require(panel.contentController as? ExtensionQuickPickViewController)
            content.handleRowClick(1)
            return window
        }
        await settle()

        #expect(run.indices == [1])
        #expect(window.isVisible == false, "the window controller must still be alive to close its window")
        #expect(weakPanel == nil, "and released afterwards — nothing may keep the answered panel alive")
    }

    @Test("cancelling a quick pick closes its window, then lets go of the window controller")
    func cancellingQuickPickClosesThenReleasesThePanel() async throws {
        let presenter = ExtensionPickerPresenter()
        let run = startQuickPick(on: presenter, items: [item("a")])
        await settle()

        weak var weakPanel: ExtensionPickerWindowController?
        let window: NSWindow = try autoreleasepool {
            let panel = try #require(currentPanel(of: presenter))
            weakPanel = panel
            let window = try #require(panel.window)
            let content = try #require(panel.contentController as? ExtensionQuickPickViewController)
            content.onCancel()
            return window
        }
        await settle()

        #expect(run.isFinished)
        #expect(run.indices == nil)
        #expect(window.isVisible == false, "the window controller must still be alive to close its window")
        #expect(weakPanel == nil)
    }

    @Test("accepting an input box answers with the value and closes its window")
    func acceptingInputBoxAnswersWithTheValue() async throws {
        let presenter = ExtensionPickerPresenter()
        let validator = ScriptedValidator()
        let run = startInputBox(on: presenter, validator: validator)
        await settle()

        let panel = try #require(currentPanel(of: presenter))
        let window = try #require(panel.window)
        let content = try #require(panel.contentController as? ExtensionInputBoxViewController)
        content.onAccept("chosen")
        await settle()

        #expect(run.isFinished)
        #expect(run.value == "chosen")
        #expect(window.isVisible == false)
        #expect(currentPanel(of: presenter) == nil, "an answered panel is no longer the current one")

        validator.drain()
        await settle()
    }

    // MARK: - Stale validations

    /// The positive control the two drop tests are measured against: without
    /// it, a guard that dropped *everything* would leave them both green.
    @Test("a validation for the value still in the field is painted")
    func validationForTheCurrentValueIsPainted() async throws {
        let presenter = ExtensionPickerPresenter()
        let validator = ScriptedValidator()
        _ = startInputBox(on: presenter, validator: validator)
        await settle()

        let panel = try #require(currentPanel(of: presenter))
        let content = try #require(panel.contentController as? ExtensionInputBoxViewController)
        try type("draft", into: content)
        await settle()
        #expect(validator.isPending("draft"), "a keystroke asks the extension about the new value")

        validator.answer("draft", with: ExtensionInputValidation(message: "too short", severity: .error))
        await settle()

        let label = try #require(validationLabel(of: content))
        #expect(label.isHidden == false)
        #expect(label.stringValue == "too short")

        await tearDown(presenter, validator)
    }

    /// The `Task.isCancelled` guard, alone. The panel is replaced while the
    /// validation is in flight, which cancels it — but the model it belongs to
    /// still reads `draft`, so the value comparison would wave the late answer
    /// through, and this test holds the content controller so the `weak
    /// viewController` capture does not drop it either. Cancellation is the
    /// only guard left standing.
    @Test("a validation the replacement cancelled is not painted, though its value is still the model's")
    func validationCancelledByAReplacementIsNotPainted() async throws {
        let presenter = ExtensionPickerPresenter()
        let validator = ScriptedValidator()
        let secondValidator = ScriptedValidator()
        _ = startInputBox(on: presenter, validator: validator)
        await settle()

        let panel = try #require(currentPanel(of: presenter))
        let content = try #require(panel.contentController as? ExtensionInputBoxViewController)
        try type("draft", into: content)
        await settle()
        #expect(validator.isPending("draft"))

        _ = startInputBox(on: presenter, validator: secondValidator)
        await settle()

        let model = try #require(inputModel(of: content))
        #expect(model.value == "draft", "the replaced panel's model still holds the value being validated")

        validator.answer("draft", with: ExtensionInputValidation(message: "too short", severity: .error))
        await settle()

        let label = try #require(validationLabel(of: content))
        #expect(label.isHidden, "a cancelled validation must not paint over a panel that is gone")
        #expect(label.stringValue.isEmpty)

        await tearDown(presenter, validator, secondValidator)
    }

    /// The `model.value == value` comparison, alone. The task is never
    /// cancelled here: the value moves out from under it directly on the
    /// model, which is what "an answer that raced past" means and the only way
    /// to reach this guard — every keystroke path into the presenter
    /// (`controlTextDidChange`) cancels the previous validation as well as
    /// superseding its value, so a stale answer arriving through the UI is
    /// always a *cancelled* one and is caught by the test above instead.
    @Test("a validation whose value the model has moved past is not painted, though it was never cancelled")
    func validationForASupersededValueIsNotPainted() async throws {
        let presenter = ExtensionPickerPresenter()
        let validator = ScriptedValidator()
        _ = startInputBox(on: presenter, validator: validator)
        await settle()

        let panel = try #require(currentPanel(of: presenter))
        let content = try #require(panel.contentController as? ExtensionInputBoxViewController)
        try type("draft", into: content)
        await settle()
        #expect(validator.isPending("draft"))

        let model = try #require(inputModel(of: content))
        model.value = "redraft"

        validator.answer("draft", with: ExtensionInputValidation(message: "too short", severity: .error))
        await settle()

        let label = try #require(validationLabel(of: content))
        #expect(label.isHidden, "an answer about a value the field has moved past must not paint")
        #expect(label.stringValue.isEmpty)
        #expect(model.validation == nil, "nor may it be recorded on the model")

        await tearDown(presenter, validator)
    }

    @Test("accepting an input box drops the validation still in flight for it")
    func acceptingAnInputBoxDropsItsInFlightValidation() async throws {
        let presenter = ExtensionPickerPresenter()
        let validator = ScriptedValidator()
        let run = startInputBox(on: presenter, validator: validator)
        await settle()

        let panel = try #require(currentPanel(of: presenter))
        let content = try #require(panel.contentController as? ExtensionInputBoxViewController)
        try type("draft", into: content)
        await settle()

        content.onAccept("draft")
        await settle()
        #expect(run.value == "draft")

        validator.answer("draft", with: ExtensionInputValidation(message: "too short", severity: .error))
        await settle()

        let label = try #require(validationLabel(of: content))
        #expect(label.isHidden, "an accepted panel's validation must not answer into it afterwards")

        validator.drain()
        await settle()
    }
}
