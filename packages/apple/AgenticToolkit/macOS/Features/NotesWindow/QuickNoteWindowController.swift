import AppKit
import os
import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import AgenticDeveloperToolkitUI

/// A small floating window for quickly capturing a note.
/// Positions itself near a given screen rect (typically a status bar item).
public final class QuickNoteWindowController: NSWindowController {

    // MARK: - Callback

    /// Called when the user saves. Provides (title, content).
    /// Required at init time — a silently-dropped save is a terrible UX.
    private let onSave: (String, String) -> Void

    // MARK: - Views

    private lazy var titleField: NSTextField = {
        let field = NSTextField()
        field.placeholderString = "Note title..."
        field.bezelStyle = .roundedBezel
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

    /// The window's content view controller, so the editor below is a genuine
    /// child in the view-controller hierarchy rather than an orphan whose
    /// view happens to be a subview. That gives it a working responder chain
    /// and a proper host for `presentSyntaxHelp(from:)`, which the editor's
    /// toolbar uses to present its syntax-help sheet.
    private let containerController = NSViewController()

    public let editorController = MarkdownEditorController(palette: ThemeScope.app.palette)

    private lazy var saveButton: NSButton = {
        let btn = ThemedButton(title: "Save", target: self, action: #selector(saveAction))
        btn.keyEquivalent = "\r"
        btn.keyEquivalentModifierMask = [.command]
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private lazy var cancelButton: NSButton = {
        let btn = NSButton(title: "Cancel", target: self, action: #selector(cancelAction))
        btn.keyEquivalent = "\u{1b}"
        btn.translatesAutoresizingMaskIntoConstraints = false
        // The same explicit Cancel styling used elsewhere in the app, so this
        // dialog agrees with the others — AppKit's stock bezel does not (see
        // `applySecondaryActionTheme`).
        btn.observeTheme { button, palette in
            button.applySecondaryActionTheme(palette)
        }
        return btn
    }()

    // MARK: - Initialization

    public init(onSave: @escaping (String, String) -> Void) {
        self.onSave = onSave

        let contentRect = NSRect(x: 0, y: 0, width: 360, height: 260)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Quick Note"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        super.init(window: window)

        // Framed with the same rect as the window itself: a zero-frame
        // container view collapses the window to Auto Layout's intrinsic
        // minimum the moment it becomes `contentViewController`, discarding
        // the 360x260 set above.
        containerController.view = NSView(frame: contentRect)
        window.contentViewController = containerController
        containerController.addChild(editorController)

        setupContentView()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    private func setupContentView() {
        let contentView = containerController.view

        contentView.addSubview(titleField)
        contentView.addSubview(editorController.view)
        contentView.addSubview(cancelButton)
        contentView.addSubview(saveButton)

        editorController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            titleField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            titleField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            editorController.view.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 8),
            editorController.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            editorController.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            editorController.view.bottomAnchor.constraint(equalTo: cancelButton.topAnchor, constant: -12),

            cancelButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),
            // Cancel is drawn by the theme rather than by a stock bezel (see
            // `applySecondaryActionTheme`), so its size is stated here — matching
            // the default button beside it — instead of coming from the bezel.
            cancelButton.heightAnchor.constraint(equalTo: saveButton.heightAnchor),
            cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),

            saveButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            saveButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            saveButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 60)
        ])

        editorController.view.observeTheme { [weak editorController] _, palette in
            editorController?.palette = palette
        }
        // One small panel for capturing a thought. A three-way mode switcher
        // here would be three controls competing for a window sized for one.
        editorController.isPreviewAvailable = false
        editorController.mode = .edit
    }

    // MARK: - Show

    /// Positions near the menu bar status item button and shows the window.
    public func showNearStatusItem(buttonFrame: NSRect) {
        titleField.stringValue = ""
        editorController.content = ""

        guard let window else { return }
        let wSize = window.frame.size

        // Choose the screen containing the button, falling back to main.
        // If neither is available (headless, screensaver), just center the window.
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(buttonFrame) })
            ?? NSScreen.main
        if let screenFrame = targetScreen?.visibleFrame {
            var origin = NSPoint(
                x: buttonFrame.maxX - wSize.width,
                y: buttonFrame.minY - wSize.height - 4
            )
            origin.x = max(screenFrame.minX + 8, min(origin.x, screenFrame.maxX - wSize.width - 8))
            origin.y = max(screenFrame.minY + 8, origin.y)
            window.setFrameOrigin(origin)
        } else {
            window.center()
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(titleField)
        logger.debug("Quick note window shown")
    }

    // MARK: - Actions

    @objc private func saveAction() {
        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = editorController.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty || !content.isEmpty else {
            close()
            return
        }
        onSave(title.isEmpty ? "Quick Note" : title, content)
        close()
    }

    @objc private func cancelAction() {
        close()
    }
}

extension QuickNoteWindowController: Loggable {
    public static nonisolated let logger = makeLogger()
}
