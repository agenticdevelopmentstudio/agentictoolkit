import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreUI
import AgenticDeveloperToolkitUI

/// A two-part `[✓ | ✗]` control: confirm on the left, cancel on the right, with
/// a hairline between them so the pair reads as one control rather than as two
/// loose buttons that happen to sit side by side.
///
/// It exists because "commit or back out of this edit" is a shape that recurs
/// wherever a control edits in place — a key-command recorder, a rename field,
/// an inline filter — and each of those was otherwise going to grow its own
/// pair of tiny buttons with its own idea of how a disabled checkmark looks.
///
/// **Cancel is never disabled.** Only confirming is gated, by
/// ``isConfirmEnabled``; a control you cannot back out of is a trap, and the
/// one moment you most want out is when confirming is refused.
///
/// Return confirms and Escape cancels, as in any other edit — but only while
/// the pair is on screen: a hidden pair (every other row's, in a list of
/// editors) must not answer the keys meant for the visible one.
@MainActor
public final class ConfirmCancelControl: NSView {

    public var onConfirm: (() -> Void)?
    public var onCancel: (() -> Void)?

    /// Whether the checkmark is live. The caller sets this from whatever makes
    /// the pending value acceptable — for the key-command recorder, whether the
    /// captured chord is available.
    public var isConfirmEnabled: Bool = true {
        didSet {
            confirmButton.isEnabled = isConfirmEnabled
            applyTint()
        }
    }

    private static let buttonWidth: CGFloat = 24
    private static let height: CGFloat = 20

    private let confirmButton = PointingHandButton()
    private let cancelButton = PointingHandButton()
    private let divider = NSView()

    /// The last palette seen, kept so ``isConfirmEnabled`` can repaint without
    /// waiting for the next theme change.
    private var palette: SemanticPalette?

    public init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1

        configure(confirmButton, symbol: "checkmark", title: "Save", action: #selector(confirmClicked))
        configure(cancelButton, symbol: "xmark", title: "Cancel", action: #selector(cancelClicked))
        confirmButton.keyEquivalent = "\r"
        cancelButton.keyEquivalent = "\u{1b}"

        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.wantsLayer = true

        addSubview(confirmButton)
        addSubview(divider)
        addSubview(cancelButton)

        NSLayoutConstraint.activate([
            confirmButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            confirmButton.topAnchor.constraint(equalTo: topAnchor),
            confirmButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            confirmButton.widthAnchor.constraint(equalToConstant: Self.buttonWidth),

            divider.leadingAnchor.constraint(equalTo: confirmButton.trailingAnchor),
            divider.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            divider.widthAnchor.constraint(equalToConstant: 1),

            cancelButton.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            cancelButton.topAnchor.constraint(equalTo: topAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: Self.buttonWidth),

            heightAnchor.constraint(equalToConstant: Self.height)
        ])

        observeTheme { control, palette in
            control.palette = palette
            control.applyTint()
        }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard !isHiddenOrHasHiddenAncestor else { return false }
        return super.performKeyEquivalent(with: event)
    }

    private func configure(
        _ button: PointingHandButton,
        symbol: String,
        title: String,
        action: Selector
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.bezelStyle = .shadowlessSquare
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.target = self
        button.action = action
        button.toolTip = title
        button.setAccessibilityLabel(title)
    }

    private func applyTint() {
        guard let palette else { return }
        layer?.borderColor = palette.borderColor.cgColor
        layer?.backgroundColor = palette.controlBackgroundColor.cgColor
        divider.layer?.backgroundColor = palette.borderColor.cgColor
        // A disabled checkmark fades rather than greying, because the button is
        // borderless: `isEnabled` alone leaves a tinted template image looking
        // exactly as live as an enabled one.
        confirmButton.contentTintColor = palette.successColor
        confirmButton.alphaValue = isConfirmEnabled ? 1 : 0.35
        cancelButton.contentTintColor = palette.dangerColor
    }

    @objc private func confirmClicked() { onConfirm?() }

    @objc private func cancelClicked() { onCancel?() }
}
