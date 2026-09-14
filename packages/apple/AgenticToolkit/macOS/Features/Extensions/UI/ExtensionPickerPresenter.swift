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

    public init() {}

    /// Finish any in-flight session as dismissed and close its window. Safe
    /// to call with nothing on screen.
    private func dismissCurrent() {
        guard let current else { return }
        self.current = nil
        current.dismiss()
        current.window.onDismiss = {}
        current.window.close()
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
            viewController.onValueChanged = { [weak viewController] value in
                Task { @MainActor in
                    let validation = await validate(value)
                    // Drop a late answer for a superseded value rather than
                    // painting it — the extension's validator is async and
                    // answers can arrive out of order. Compared against the
                    // model's current value at the moment the answer lands.
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
