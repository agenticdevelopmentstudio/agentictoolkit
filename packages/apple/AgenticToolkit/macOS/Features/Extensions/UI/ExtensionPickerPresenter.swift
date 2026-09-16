//
//  ExtensionPickerPresenter.swift
//  AgenticToolkit
//

import AppKit

/// The AppKit conformer for `vscode.window.showQuickPick` and
/// `vscode.window.showInputBox`.
///
/// One class conforming to both protocols because there is one panel: the
/// two requests cannot be on screen at once, and a single owner is what
/// makes that enforceable rather than hoped for.
///
/// **Replacement rule, decided here:** a second request arriving while one
/// is on screen finishes the first as dismissed (`nil`) and shows the
/// second. Not queued, because an extension would then be waiting on a
/// panel the user cannot see, and not refused, because a `nil` return
/// already means "the user did not answer" and that is what happened. This
/// is our rule; this task did not check what VS Code itself does when a
/// second picker is requested mid-presentation.
@MainActor
public final class ExtensionPickerPresenter {

    /// The window controller currently on screen, if any, and the pieces
    /// needed to close it out — held together so `dismissCurrent()` never
    /// has to guess which session belongs to which window.
    private var current: (window: ExtensionPickerWindowController, dismiss: () -> Void)?

    /// The in-flight validation for the input box's current value, if any.
    /// **One at a time:** a new keystroke cancels the previous one before
    /// starting its own, and finishing or replacing the panel cancels
    /// whatever is left. Without it, every keystroke started a `Task` that
    /// nothing ever cancelled, each capturing the view controller and the
    /// extension's validator closure, and each one lived until its validator
    /// answered — so typing twenty characters into a box with a slow
    /// validator left twenty of them alive at once.
    ///
    /// **What cancellation does and does not buy.** `validate` is an
    /// extension's arbitrary async JavaScript; cancellation is cooperative,
    /// so a validator that never answers leaves its task suspended no matter
    /// what is cancelled here. What this does guarantee is that only the
    /// newest keystroke's validation is *reachable* from this presenter, that
    /// superseded work stops at the first suspension point that checks, and
    /// that nothing survives the panel it belongs to.
    private var validationTask: Task<Void, Never>?

    public init() {}

    /// Finish any in-flight session as dismissed and close its window. Safe
    /// to call with nothing on screen.
    private func dismissCurrent() {
        cancelValidation()
        guard let current else { return }
        self.current = nil
        current.dismiss()
        current.window.onDismiss = {}
        current.window.close()
    }

    /// Stop the in-flight validation, if any. Called wherever the input box
    /// stops being on screen — replaced, accepted, or cancelled — so a
    /// validation never outlives the panel that asked for it.
    private func cancelValidation() {
        validationTask?.cancel()
        validationTask = nil
    }
}

// MARK: - Quick pick

extension ExtensionPickerPresenter: ExtensionQuickPickPresenting {

    public func presentQuickPick(
        _ request: ExtensionQuickPickRequest,
        onHighlight: @escaping (Int) -> Void
    ) async -> [Int]? {
        dismissCurrent()

        let model = ExtensionQuickPickModel(request: request)
        let viewController = ExtensionQuickPickViewController(model: model)
        // Set before `ExtensionPickerWindowController` is constructed:
        // constructing it forces `viewController.view` to load, which runs
        // `viewDidLoad()` and publishes the opening highlight through
        // `onHighlight` synchronously — the listener must already be
        // attached before that happens, or the first highlight is published
        // to nobody.
        viewController.onHighlight = onHighlight
        let windowController = ExtensionPickerWindowController(
            content: viewController, ignoreFocusOut: request.ignoreFocusOut)

        let answer: UncheckedSendableBox<[Int]?> = await withCheckedContinuation { continuation in
            let session = OnceOnlyContinuation<[Int]?>(continuation: continuation)
            self.current = (windowController, { session.finish(nil) })

            // `[weak windowController]`, not a strong capture, breaks the
            // retain cycle windowController → contentController(viewController)
            // → this closure → windowController. The `current` assignment
            // runs last in each closure, after `windowController` is used —
            // `self.current` is the panel's other strong owner, so nilling it
            // first could deallocate `windowController` before
            // `windowController?.close()` ever ran.
            //
            // The identity test is what makes each closure clear only its own
            // session: `current` is whatever the most recent request put
            // there, and these closures outlive the request that installed
            // them. With the test, a closure that fires after its window has
            // been replaced leaves the replacement's `current` alone.
            viewController.onAccept = { [weak self, weak windowController] indices in
                session.finish(indices)
                windowController?.onDismiss = {}
                windowController?.close()
                if self?.current?.window === windowController { self?.current = nil }
            }
            viewController.onCancel = { [weak self, weak windowController] in
                session.finish(nil)
                windowController?.onDismiss = {}
                windowController?.close()
                if self?.current?.window === windowController { self?.current = nil }
            }
            windowController.onDismiss = { session.finish(nil) }

            windowController.show()
        }
        return answer.value
    }
}

// MARK: - Input box

extension ExtensionPickerPresenter: ExtensionInputBoxPresenting {

    public func presentInputBox(
        _ request: ExtensionInputBoxRequest,
        validate: @escaping (String) async -> ExtensionInputValidation?
    ) async -> String? {
        dismissCurrent()

        let model = ExtensionInputBoxModel(request: request)
        let viewController = ExtensionInputBoxViewController(model: model)
        let windowController = ExtensionPickerWindowController(
            content: viewController, ignoreFocusOut: request.ignoreFocusOut)

        let answer: UncheckedSendableBox<String?> = await withCheckedContinuation { continuation in
            let session = OnceOnlyContinuation<String?>(continuation: continuation)
            self.current = (windowController, { session.finish(nil) })

            // `[weak windowController]`, not a strong capture, and the same
            // identity test before clearing `current` — see the note on
            // `presentQuickPick` above. The `current` assignment runs
            // last, after `windowController` is used.
            viewController.onAccept = { [weak self, weak windowController] value in
                session.finish(value)
                self?.cancelValidation()
                windowController?.onDismiss = {}
                windowController?.close()
                if self?.current?.window === windowController { self?.current = nil }
            }
            viewController.onCancel = { [weak self, weak windowController] in
                session.finish(nil)
                self?.cancelValidation()
                windowController?.onDismiss = {}
                windowController?.close()
                if self?.current?.window === windowController { self?.current = nil }
            }
            viewController.onValueChanged = { [weak self, weak viewController] value in
                self?.cancelValidation()
                self?.validationTask = Task { @MainActor in
                    let validation = await validate(value)
                    // Drop a late answer for a superseded value rather than
                    // painting it — the extension's validator is async and
                    // answers can arrive out of order. Two tests, because they
                    // catch different things: cancellation covers a keystroke
                    // this presenter has already superseded, and the value
                    // comparison covers an answer that raced past it.
                    guard !Task.isCancelled else { return }
                    guard let viewController, model.value == value else { return }
                    viewController.showValidation(validation)
                }
            }
            windowController.onDismiss = { session.finish(nil) }

            windowController.show()
        }
        return answer.value
    }
}
