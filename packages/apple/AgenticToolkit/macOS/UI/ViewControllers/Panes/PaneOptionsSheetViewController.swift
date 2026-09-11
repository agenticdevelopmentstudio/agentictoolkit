import AgenticDeveloperToolkitUI
import AppKit

/// A pane's options, as a dialog: the pane's name, the rows it handed over, and
/// the one button that ends it.
///
/// The rows are `PaneViewController.makeOptionRows()` — the same views the gear
/// used to show inside a popover. Only the container changed; the controls, and
/// the knowledge of what they are, stayed where they were (`dry`).
///
/// Every row applies its change as it is made — the spacing moves behind the
/// sheet as the steppers tick — so there is nothing to commit and nothing to
/// cancel. `Done` is the way out, not an acceptance. That is the same shape,
/// and the same reason, as the project settings sheet.
@MainActor
public final class PaneOptionsSheetViewController: NSViewController {

    /// Fires once the dialog is off screen.
    ///
    /// The spacing steppers coalesce their writes, so the last tick of a
    /// gesture is still waiting when the dialog goes away — the dialog closing
    /// *is* the end of the gesture, and the pane listens here to finish it.
    public var onDidClose: (() -> Void)?

    /// The name at the head of the dialog. Settable, because a pane named by
    /// its content can be renamed while the dialog is up, and a heading frozen
    /// at the moment it was built would then be naming the wrong pane.
    public var heading: String {
        didSet { headingLabel.stringValue = heading }
    }

    /// Wide enough for the spacing control's diagram, which is the widest thing
    /// any pane puts in here.
    private static let width: CGFloat = 340

    private let headingLabel: ThemedLabel
    private let rows: [NSView]

    public init(heading: String, rows: [NSView]) {
        self.heading = heading
        self.headingLabel = ThemedLabel(string: heading, role: .secondaryText, textRole: .button)
        self.rows = rows
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("PaneOptionsSheetViewController is code-built, never decoded")
    }

    public override func loadView() {
        let container = ThemedBackgroundView(role: .windowBackground)
        container.accessibilityID("pane.options.dialog")

        let stack = NSStackView(views: [headingLabel] + rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 8, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        let done = NSButton(title: "Done", target: self, action: #selector(close(_:)))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        done.translatesAutoresizingMaskIntoConstraints = false
        done.accessibilityID("pane.options.dialog.done")
        container.addSubview(done)

        var constraints = [
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            done.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 12),
            container.trailingAnchor.constraint(equalTo: done.trailingAnchor, constant: 20),
            container.bottomAnchor.constraint(equalTo: done.bottomAnchor, constant: 16),

            container.widthAnchor.constraint(equalToConstant: Self.width)
        ]
        // Every row spans the dialog minus the stack's insets, so a slider gets
        // the room and its caption right-aligns to one edge. Leading-aligned
        // content such as a checkbox is unaffected by the extra trailing space.
        for row in rows {
            constraints.append(row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40))
        }
        NSLayoutConstraint.activate(constraints)

        self.view = container
    }

    public override func viewDidDisappear() {
        super.viewDidDisappear()
        onDidClose?()
    }

    @objc private func close(_ sender: Any?) {
        dismiss(self)
    }
}
