#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit

/// Sheet container for a create dialog: title row with Cancel, then the form (whose own footer holds Save).
@MainActor
public final class FormSheetController: NSViewController {
    public let form: FormViewController
    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private var onFinish: (@MainActor (Bool) -> Void)?
    private let sheetTitle: String
    /// Guards against a second `cancel()` opening a second discard prompt while the first
    /// `confirmDiscard()` is still awaiting the user.
    @MainActor private var isConfirmingDiscard = false

    public init(title: String, form: FormViewController, onFinish: @escaping @MainActor (Bool) -> Void) {
        self.form = form
        self.onFinish = onFinish
        self.sheetTitle = title
        super.init(nibName: nil, bundle: nil)
        self.title = title
        let existingSaved = form.onSaved
        form.onSaved = { [weak self] in
            existingSaved()
            self?.finish(true)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override public func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: sheetTitle)
        titleLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize + 2, weight: .semibold)
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        cancelButton.keyEquivalent = "\u{1B}"
        cancelButton.setAccessibilityIdentifier("htdv.form.cancel")
        let header = NSStackView(views: [titleLabel, NSView(), cancelButton])
        header.orientation = .horizontal
        header.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 0, right: 20)
        header.translatesAutoresizingMaskIntoConstraints = false

        addChild(form)
        form.view.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(header)
        root.addSubview(form.view)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            form.view.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            form.view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            form.view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            form.view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            root.widthAnchor.constraint(equalToConstant: 540),
            root.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
            root.heightAnchor.constraint(lessThanOrEqualToConstant: 720)
        ])
        view = root
    }

    @objc private func cancelTapped() { cancel() }

    public func cancel() {
        guard !isConfirmingDiscard else { return }
        isConfirmingDiscard = true
        Task { [weak self] in
            guard let self else { return }
            var proceed = true
            if form.hasUnsavedChanges { proceed = await form.confirmDiscard() }
            self.isConfirmingDiscard = false
            guard proceed else { return }
            finish(false)
        }
    }

    /// Nils `onFinish` before calling it, so a second save (or a cancel racing a save) resolves the
    /// continuation in `FormSheet.present` exactly once.
    private func finish(_ saved: Bool) {
        guard let onFinish else { return }
        self.onFinish = nil
        if presentingViewController != nil { presentingViewController?.dismiss(self) }
        onFinish(saved)
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
        markdownEditing: any MarkdownEditing = PlainTextMarkdownEditing(), from presenter: NSViewController
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let state = FormState(spec: spec, values: values)
            state.requiresChanges = false
            let form = FormViewController(state: state, markdownEditing: markdownEditing)
            let sheet = FormSheetController(title: title, form: form) { saved in
                continuation.resume(returning: saved)
            }
            presenter.presentAsSheet(sheet)
        }
    }
}
#endif
