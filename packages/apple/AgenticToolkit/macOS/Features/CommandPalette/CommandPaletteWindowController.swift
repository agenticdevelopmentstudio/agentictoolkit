import AppKit
import OSLog
import AgenticToolkitCore

/// The floating panel the command palette lives in.
///
/// Everything about the panel itself — the titleless `NSPanel`, the container
/// framing, the show ordering, the pointer-screen positioning, and the single
/// re-entrant dismissal path — is `FloatingChooserPanelController`'s, and is
/// documented there. This type is the three things that are the palette's own:
/// its fixed size, clearing the model around every appearance, and focusing the
/// search field.
@MainActor
public final class CommandPaletteWindowController: FloatingChooserPanelController {

    /// 640x400, spelled rather than asked of the content: the palette's list is
    /// a fixed size whatever it currently holds, so a chooser that shrank to
    /// three commands and grew back would move under the pointer between one
    /// query and the next.
    private static let contentSize = NSSize(width: 640, height: 400)

    private let paletteController: CommandPaletteViewController

    // MARK: - Lifecycle

    public init(model: CommandPaletteModel) {
        let paletteController = CommandPaletteViewController(model: model)
        self.paletteController = paletteController
        super.init(
            content: paletteController,
            contentRect: NSRect(origin: .zero, size: Self.contentSize)
        )

        paletteController.onRun = { [weak self] in self?.close() }
        paletteController.onCancel = { [weak self] in self?.close() }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    // MARK: - Show

    /// Bring the palette up empty, re-read from the registry, and focus it.
    ///
    /// The reset happens before `super.show()` positions and activates, so the
    /// panel is never on screen holding the last visit's typing even for a
    /// frame.
    public override func show() {
        paletteController.reset()
        super.show()
        logger.debug("Command palette shown")
    }

    /// The field keeps first responder for the palette's whole life — the table
    /// is a display surface.
    public override func takeInitialFocus() {
        paletteController.focusSearchField()
    }

    // MARK: - Dismiss

    /// Every dismissal clears the palette.
    ///
    /// Here rather than only in `show()` because a closed palette should not be
    /// sitting on the last visit's query and selection at all: `runSelection`
    /// takes what it needs from the model *before* asking for the dismissal
    /// that clears it.
    public override func panelWillClose() {
        paletteController.reset()
    }
}

extension CommandPaletteWindowController: Loggable {
    public static nonisolated let logger = makeLogger()
}
