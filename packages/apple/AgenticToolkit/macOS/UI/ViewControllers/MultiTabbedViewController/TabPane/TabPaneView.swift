import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import AppKit

/// The card drawn in the edge bar. Two arrangements: a stacked card for the
/// left and right edges, a single row for the top and bottom edges.
@MainActor
final class TabPaneView: NSView {
    static let sideWidth: CGFloat = 220
    static let rowHeight: CGFloat = 28
    static let rowMaxWidth: CGFloat = 320

    let agentLabel = ThemedLabel(role: .primaryText, textRole: .body)
    let sessionLabel = ThemedLabel(role: .primaryText, textRole: .body)
    let directoryLabel = ThemedLabel(role: .tertiaryText, textRole: .caption)
    let branchLabel = ThemedLabel(role: .secondaryText, textRole: .caption)
    let summaryLabel = ThemedLabel(role: .secondaryText, textRole: .caption)
    let closeButton = NSButton()
    let statusStack = NSStackView()

    var onClose: (() -> Void)?
    var contextMenuProvider: ((NSEvent) -> NSMenu?)?
    var isHighlighted = false { didSet { applyHighlight() } }

    private let edge: Edge
    private let background = NSView()
    private var statusViews: [NSImageView] = []

    init(edge: Edge, tabID: UUID) {
        self.edge = edge
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityID("tab-pane.\(tabID.uuidString)")
        agentLabel.accessibilityID("tab-pane.agent.\(tabID.uuidString)")
        sessionLabel.accessibilityID("tab-pane.session.\(tabID.uuidString)")
        directoryLabel.accessibilityID("tab-pane.directory.\(tabID.uuidString)")
        branchLabel.accessibilityID("tab-pane.branch.\(tabID.uuidString)")
        summaryLabel.accessibilityID("tab-pane.summary.\(tabID.uuidString)")
        closeButton.accessibilityID("tab-pane.close.\(tabID.uuidString)")
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: Content

    func setStatusSymbols(_ symbols: [TabPaneStatusSymbol]) {
        for view in statusViews { statusStack.removeView(view) }
        statusViews = symbols.map { symbol in
            let symbolImage = NSImage(
                systemSymbolName: symbol.symbolName,
                accessibilityDescription: symbol.accessibilityLabel
            ) ?? NSImage()
            let image = NSImageView(image: symbolImage)
            image.symbolConfiguration = .init(pointSize: 11, weight: .regular)
            image.setAccessibilityLabel(symbol.accessibilityLabel)
            image.widthAnchor.constraint(equalToConstant: 14).isActive = true
            image.heightAnchor.constraint(equalToConstant: 14).isActive = true
            statusStack.addArrangedSubview(image)
            return image
        }
    }

    /// The size the pane wants for its current content in its arrangement.
    var contentSize: NSSize {
        layoutSubtreeIfNeeded()
        switch edge {
        case .left, .right:
            return NSSize(width: Self.sideWidth, height: max(Self.rowHeight, fittingSize.height))
        case .top, .bottom:
            return NSSize(width: min(Self.rowMaxWidth, fittingSize.width), height: Self.rowHeight)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenuProvider?(event) ?? super.menu(for: event)
    }

    // MARK: Layout

    private func setUp() {
        for label in [agentLabel, sessionLabel, directoryLabel, branchLabel, summaryLabel] {
            label.lineBreakMode = .byTruncatingMiddle
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        directoryLabel.lineBreakMode = .byTruncatingHead
        summaryLabel.isHidden = true

        statusStack.orientation = .horizontal
        statusStack.spacing = 2

        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeButton.isBordered = false
        closeButton.bezelStyle = .inline
        closeButton.imagePosition = .imageOnly
        closeButton.target = self
        closeButton.action = #selector(closePressed)
        closeButton.widthAnchor.constraint(equalToConstant: 14).isActive = true
        closeButton.heightAnchor.constraint(equalToConstant: 14).isActive = true

        background.wantsLayer = true
        background.layer?.cornerRadius = 6
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)
        observeTheme { view, _ in view.applyHighlight() }

        let content: NSStackView
        switch edge {
        case .left, .right:
            let header = NSStackView(views: [agentLabel, statusStack, NSView(), closeButton])
            header.orientation = .horizontal
            header.spacing = 4
            header.alignment = .centerY
            content = NSStackView(views: [header, sessionLabel, directoryLabel, branchLabel, summaryLabel])
            content.orientation = .vertical
            content.alignment = .leading
            content.spacing = 2
        case .top, .bottom:
            summaryLabel.lineBreakMode = .byTruncatingTail
            // The lowest priorities in the row, so a narrow bar squeezes the
            // summary before it touches the agent name, branch, or path.
            summaryLabel.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
            summaryLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
            content = NSStackView(
                views: [agentLabel, statusStack, sessionLabel, branchLabel, summaryLabel, directoryLabel, closeButton]
            )
            content.orientation = .horizontal
            content.alignment = .centerY
            content.spacing = 6
        }
        content.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        // No self-pin on either axis: the cross axis is the hosting bar's
        // job at required priority (`TabBarView.rebuildButtons()`), and the
        // length axis is AppKit's own priority-501
        // `NSViewController.preferredContentSize` constraint, driven by
        // `contentSize` below. A required pin here would restate one of
        // those two numbers at required priority and risk an unsatisfiable
        // conflict with whichever one wins.
        applyHighlight()
    }

    /// Selection is a fill and a role swap, exactly as `TabButton` does it.
    private func applyHighlight() {
        let palette = resolvedThemeScope.palette
        background.layer?.backgroundColor = isHighlighted
            ? palette.nsColor(.selection).cgColor
            : palette.nsColor(.surface).cgColor
        agentLabel.role = isHighlighted ? .selectionText : .primaryText
        sessionLabel.role = isHighlighted ? .selectionText : .primaryText
        closeButton.contentTintColor = palette.nsColor(isHighlighted ? .selectionText : .tertiaryText)
    }

    @objc private func closePressed() {
        onClose?()
    }
}
