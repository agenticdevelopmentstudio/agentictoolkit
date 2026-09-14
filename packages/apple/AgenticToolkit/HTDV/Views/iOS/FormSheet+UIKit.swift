#if canImport(UIKit)
import UIKit

/// Modal container for a create dialog: navigation bar with the title and Cancel, the form as root.
@MainActor
public final class FormSheetController: UINavigationController {
    public let form: FormViewController
    private var onFinish: (@MainActor (Bool) -> Void)?

    public init(title: String, form: FormViewController, onFinish: @escaping @MainActor (Bool) -> Void) {
        self.form = form
        self.onFinish = onFinish
        super.init(rootViewController: form)
        self.title = title
        form.title = title
        form.navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.cancel() }
        )
        form.onSaved = { [weak self] in self?.finish(true) }
        modalPresentationStyle = .formSheet
        isModalInPresentation = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    public func cancel() {
        Task { [weak self] in
            guard let self else { return }
            if form.hasUnsavedChanges, !(await form.confirmDiscard()) { return }
            finish(false)
        }
    }

    /// Nils `onFinish` before calling it, so a second save (or a cancel racing a save) resolves the
    /// continuation in `FormSheet.present` exactly once.
    private func finish(_ saved: Bool) {
        guard let onFinish else { return }
        self.onFinish = nil
        if presentingViewController != nil {
            dismiss(animated: true) { onFinish(saved) }
        } else {
            onFinish(saved)
        }
    }
}

/// `HubModules` lives in `AgenticToolkitHub`, one tier above this one, so the editor arrives as a
/// parameter; feature modules pass `markdownEditing: HubModules.markdownEditing`.
@MainActor
public enum FormSheet {
    /// Presents `spec` as a modal create dialog. Resolves `true` after the form's save action succeeded,
    /// `false` on cancel.
    public static func present(
        title: String, spec: FormSpec, values: [String: FormValue] = [:],
        markdownEditing: any MarkdownEditing = PlainTextMarkdownEditing(), from presenter: UIViewController
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let state = FormState(spec: spec, values: values)
            let form = FormViewController(state: state, markdownEditing: markdownEditing)
            let sheet = FormSheetController(title: title, form: form) { saved in
                continuation.resume(returning: saved)
            }
            presenter.present(sheet, animated: true)
        }
    }
}
#endif
