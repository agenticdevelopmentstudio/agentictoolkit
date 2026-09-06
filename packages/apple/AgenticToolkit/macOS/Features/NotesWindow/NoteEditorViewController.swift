import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import AgenticDeveloperToolkitUI

@MainActor public protocol NoteEditorViewControllerDelegate: AnyObject {
    func noteEditorDidChangeContent(_ content: String, for noteID: UUID)
}

public final class NoteEditorViewController: NSViewController {

    // MARK: - Public API

    public weak var delegate: NoteEditorViewControllerDelegate?

    /// Call to display a note in the editor, or nil to show the empty state.
    public func show(note: Note?) {
        currentNoteID = note?.id
        let hasNote = note != nil
        editorController.view.isHidden = !hasNote
        emptyLabel.isHidden = hasNote
        guard let note else {
            editorController.content = ""
            return
        }
        editorController.content = note.content
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

        // Task 7 puts help in the window toolbar and Task 10 puts import in
        // the File menu — this pane is the editor alone, with no controls of
        // its own left to compete with either.
        editorController.showsHelpButton = false
        editorController.showsImportButton = false

        addChild(editorController)
        editorController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(editorController.view)
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            editorController.view.topAnchor.constraint(equalTo: view.topAnchor),
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
}
