import AppKit
import KeyboardShortcuts
import AgenticToolkitCore

/// The field the user clicks into and then presses the keys they want.
///
/// It looks like a text field and is not one: a field editor would eat the very
/// chords being recorded, and `NSTextField`'s own key handling turns ⌘-anything
/// into an edit command. So this is a plain focusable view that paints its own
/// bezel and reads key events directly.
///
/// It records and reports; it never saves. Committing is the row's business —
/// see ``KeyCommandRowView`` — because the brief's ✓/✗ pair means a captured
/// chord is *pending* until the user says otherwise, and losing focus must not
/// quietly decide either way.
@MainActor
public final class KeyCommandCaptureField: NSView {

    /// A chord the user just pressed. Fired for every chord while recording,
    /// so the readout can re-evaluate as they try alternatives.
    public var onCapture: ((KeyboardShortcuts.Shortcut) -> Void)?

    /// The user pressed Escape with no modifiers: back out.
    public var onCancel: (() -> Void)?

    /// Recording started or stopped. Starting is a click or Space; stopping is
    /// losing focus.
    public var onRecordingChanged: ((Bool) -> Void)?

    public private(set) var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            refreshText()
            applyTheme()
            onRecordingChanged?(isRecording)
        }
    }

    /// What the command is bound to, shown when nothing is pending.
    public var displayedShortcut: KeyboardShortcuts.Shortcut? {
        didSet { refreshText() }
    }

    /// The chord captured but not yet saved. Takes precedence over
    /// ``displayedShortcut`` while it is set.
    public var pendingShortcut: KeyboardShortcuts.Shortcut? {
        didSet { refreshText() }
    }

    /// Shown when there is nothing to show.
    public var placeholder: String = "Click to record" {
        didSet { refreshText() }
    }

    private let label = NSTextField(labelWithString: "")
    private var palette: SemanticPalette?

    private static let height: CGFloat = 22
    private static let minimumWidth: CGFloat = 132

    public init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.isSelectable = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: Self.height),
            widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumWidth)
        ])

        observeTheme { field, palette in
            field.palette = palette
            field.applyTheme()
        }
        refreshText()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    // MARK: - Focus

    public override var acceptsFirstResponder: Bool { true }

    public override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { isRecording = true }
        return accepted
    }

    public override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { isRecording = false }
        return accepted
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    /// Stop recording without going through the responder chain — what the row
    /// calls once the edit is committed or abandoned.
    public func endRecording() {
        guard isRecording else { return }
        if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
        isRecording = false
    }

    public override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    // MARK: - Reading keys

    /// ⌘-chords never reach `keyDown` — AppKit offers them down the key
    /// equivalent chain first, and something up that chain (a menu item, the
    /// window) would otherwise claim them. Since ⌘ is the modifier most of
    /// these commands want, this override is what makes the recorder work at
    /// all.
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        return capture(event)
    }

    public override func keyDown(with event: NSEvent) {
        guard isRecording, capture(event) else {
            super.keyDown(with: event)
            return
        }
    }

    private func capture(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.function, .numericPad, .capsLock])

        if event.keyCode == UInt16(KeyboardShortcuts.Key.escape.rawValue), modifiers.isEmpty {
            onCancel?()
            return true
        }

        // Bare Tab keeps moving focus. A recorder that swallowed it would trap
        // anyone who arrived here by tabbing through the panel, and ⌥⇥ / ⌃⇥ are
        // still recordable because they carry a modifier.
        if event.keyCode == UInt16(KeyboardShortcuts.Key.tab.rawValue), modifiers.isEmpty {
            return false
        }

        guard let shortcut = KeyboardShortcuts.Shortcut(event: event) else { return false }
        onCapture?(shortcut)
        return true
    }

    // MARK: - Appearance

    private func refreshText() {
        if let shortcut = pendingShortcut ?? displayedShortcut {
            label.stringValue = shortcut.description
        } else {
            label.stringValue = isRecording ? "Press keys…" : placeholder
        }
        applyTheme()
    }

    private func applyTheme() {
        guard let palette else { return }
        layer?.backgroundColor = palette.controlBackgroundColor.cgColor
        layer?.borderColor = (isRecording ? palette.accentColor : palette.borderColor).cgColor
        label.font = palette.font(.button)

        let hasShortcut = (pendingShortcut ?? displayedShortcut) != nil
        label.textColor = hasShortcut ? palette.primaryTextColor : palette.placeholderTextColor
    }
}
