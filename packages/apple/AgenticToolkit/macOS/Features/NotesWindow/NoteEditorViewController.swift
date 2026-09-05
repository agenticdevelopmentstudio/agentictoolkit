import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import AgenticDeveloperToolkitUI

@MainActor public protocol NoteEditorViewControllerDelegate: AnyObject {
    func noteEditorDidChangeTitle(_ title: String, for noteID: UUID)
    func noteEditorDidChangeContent(_ content: String, for noteID: UUID)
    func noteEditorDidRequestPin(for noteID: UUID)
    func noteEditorDidRequestDelete(for noteID: UUID)
}

public final class NoteEditorViewController: NSViewController {

    // MARK: - Public API

    public weak var delegate: NoteEditorViewControllerDelegate?

    /// Call to display a note in the editor, or nil to show the empty state.
    public func show(note: Note?) {
        currentNoteID = note?.id
        let hasNote = note != nil
        titleField.isHidden = !hasNote
        editorController.view.isHidden = !hasNote
        pinButton.isHidden = !hasNote
        deleteButton.isHidden = !hasNote
        emptyLabel.isHidden = hasNote
        guard let note else {
            editorController.content = ""
            return
        }
        titleField.stringValue = note.title
        editorController.content = note.content
        updatePinButtonAppearance(isPinned: note.isPinned)
    }

    // MARK: - Properties

    private var currentNoteID: UUID?

    /// The markdown editor this controller wraps. `public` because the Notes
    /// window's own tests drive it, and because a host that wants to change
    /// mode has nowhere else to reach.
    ///
    /// `MarkdownEditorController` takes its palette rather than pulling one, so
    /// the app's current palette is handed over at construction and kept in
    /// step by `observeTheme` below — the same way every other view in this
    /// window gets repainted.
    public let editorController = MarkdownEditorController(palette: ThemeScope.app.palette)

    private lazy var titleField: NSTextField = {
        let field = NSTextField()
        field.placeholderString = "Note title"
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        field.observeTheme { field, palette in
            field.font = palette.font(.heading)
            field.textColor = palette.primaryTextColor
            if let placeholder = field.placeholderString {
                field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
                    .foregroundColor: palette.placeholderTextColor,
                    .font: palette.font(.heading)
                ])
            }
        }
        return field
    }()

    private lazy var pinButton: NSButton = {
        let btn = NSButton()
        btn.isBordered = false
        btn.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "Pin")
        btn.image?.isTemplate = true
        btn.toolTip = "Pin note"
        btn.target = self
        btn.action = #selector(pinTapped)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private lazy var deleteButton: NSButton = {
        let btn = NSButton()
        btn.isBordered = false
        btn.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
        btn.image?.isTemplate = true
        btn.toolTip = "Delete note"
        btn.target = self
        btn.action = #selector(deleteTapped)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private lazy var emptyLabel: NSTextField = {
        let label = ThemedLabel(string: "Select or create a note", role: .secondaryText, textRole: .body)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - View Lifecycle

    override public func loadView() {
        // The editor is the split view's main content pane, so it sits directly
        // on the window backdrop rather than a `surface` plane.
        view = ThemedBackgroundView(role: .windowBackground)
        view.translatesAutoresizingMaskIntoConstraints = false
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        addChild(editorController)
        editorController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pinButton)
        view.addSubview(deleteButton)
        view.addSubview(titleField)
        view.addSubview(editorController.view)
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            pinButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            pinButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -8),
            pinButton.widthAnchor.constraint(equalToConstant: 24),
            pinButton.heightAnchor.constraint(equalToConstant: 24),

            deleteButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            deleteButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            deleteButton.widthAnchor.constraint(equalToConstant: 24),
            deleteButton.heightAnchor.constraint(equalToConstant: 24),

            titleField.topAnchor.constraint(equalTo: pinButton.bottomAnchor, constant: 8),
            titleField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            titleField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            editorController.view.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 8),
            editorController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            editorController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            editorController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        editorController.onContentChange = { [weak self] content in
            guard let self, let id = self.currentNoteID else { return }
            self.delegate?.noteEditorDidChangeContent(content, for: id)
        }
        editorController.view.observeTheme { [weak editorController] _, palette in
            editorController?.palette = palette
        }

        show(note: nil)
    }

    // MARK: - Actions

    @objc private func pinTapped() {
        guard let id = currentNoteID else { return }
        delegate?.noteEditorDidRequestPin(for: id)
    }

    @objc private func deleteTapped() {
        guard let id = currentNoteID else { return }
        let alert = NSAlert()
        alert.messageText = "Delete Note"
        alert.informativeText = "Are you sure you want to delete this note? This cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                self?.delegate?.noteEditorDidRequestDelete(for: id)
            }
        }
    }

    // MARK: - Helpers

    private func updatePinButtonAppearance(isPinned: Bool) {
        let symbolName = isPinned ? "pin.fill" : "pin"
        pinButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: isPinned ? "Unpin" : "Pin")
        pinButton.image?.isTemplate = true
        pinButton.toolTip = isPinned ? "Unpin note" : "Pin note"
    }
}

// MARK: - NSTextFieldDelegate

extension NoteEditorViewController: NSTextFieldDelegate {
    public func controlTextDidChange(_ obj: Notification) {
        guard let id = currentNoteID else { return }
        delegate?.noteEditorDidChangeTitle(titleField.stringValue, for: id)
    }
}
