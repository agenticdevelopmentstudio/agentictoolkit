import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// Edge-aligned tab bar header for `MultiTabbedViewController`. Renders one
/// pill-style button per tab inside an `NSStackView` whose orientation
/// follows the bar's `Edge`. Calls back to its owner via closures so it
/// stays decoupled from the controller's public API.
@MainActor
final class TabBarView: NSView {

    /// The bar's narrow dimension — height for top/bottom, width for left/right.
    static func preferredThickness(for edge: Edge) -> CGFloat {
        switch edge {
        case .top, .bottom: return 28
        case .left, .right: return 140
        }
    }

    let edge: Edge

    // MARK: - Tab metadata

    struct ItemModel {
        let id: UUID
        var item: TabItem
        @MainActor
        var title: String { item.title }
    }

    // MARK: - Callbacks (set by MultiTabbedViewController)

    var onSelect: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?
    /// Fires after the user finishes dragging a tab to a new index. The
    /// stack view's underlying order is the source of truth before this
    /// call.
    var onReorder: ((UUID, Int) -> Void)?

    // MARK: - State

    private(set) var items: [ItemModel] = []
    private(set) var selectedID: UUID?

    // MARK: - Subviews

    private let stack = NSStackView()
    private let edgeDivider = NSView()
    private var buttons: [UUID: TabButton] = [:]

    /// The controller `rebuildButtons()` parents hosted view controllers to
    /// — set by `MultiTabbedViewController` right after it creates the bar.
    weak var hostController: NSViewController?
    private(set) var thicknessConstraint: NSLayoutConstraint?
    private var hostedControllers: [UUID: NSViewController] = [:]
    private var hostViews: [UUID: TabItemHostView] = [:]

    // MARK: - Init

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false

        switch edge {
        case .top, .bottom:
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        case .left, .right:
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        }
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        edgeDivider.wantsLayer = true
        edgeDivider.translatesAutoresizingMaskIntoConstraints = false

        wantsLayer = true
        observeTheme { bar, palette in
            bar.layer?.backgroundColor = palette.nsColor(.surface).cgColor
            bar.edgeDivider.layer?.backgroundColor = palette.nsColor(.divider).cgColor
        }

        addSubview(stack)
        addSubview(edgeDivider)

        let thickness = Self.preferredThickness(for: edge)

        switch edge {
        case .top:
            NSLayoutConstraint.activate([
                makeThicknessConstraint(thickness),
                stack.topAnchor.constraint(equalTo: topAnchor),
                stack.leadingAnchor.constraint(equalTo: leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor),
                stack.bottomAnchor.constraint(equalTo: edgeDivider.topAnchor),

                edgeDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
                edgeDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
                edgeDivider.bottomAnchor.constraint(equalTo: bottomAnchor),
                edgeDivider.heightAnchor.constraint(equalToConstant: 1)
            ])
        case .bottom:
            NSLayoutConstraint.activate([
                makeThicknessConstraint(thickness),
                edgeDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
                edgeDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
                edgeDivider.topAnchor.constraint(equalTo: topAnchor),
                edgeDivider.heightAnchor.constraint(equalToConstant: 1),

                stack.topAnchor.constraint(equalTo: edgeDivider.bottomAnchor),
                stack.leadingAnchor.constraint(equalTo: leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        case .left:
            NSLayoutConstraint.activate([
                makeThicknessConstraint(thickness),
                stack.topAnchor.constraint(equalTo: topAnchor),
                // Pack buttons from the top; the leftover column height
                // stays empty instead of stretching the buttons.
                stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
                stack.leadingAnchor.constraint(equalTo: leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: edgeDivider.leadingAnchor),

                edgeDivider.topAnchor.constraint(equalTo: topAnchor),
                edgeDivider.bottomAnchor.constraint(equalTo: bottomAnchor),
                edgeDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
                edgeDivider.widthAnchor.constraint(equalToConstant: 1)
            ])
        case .right:
            NSLayoutConstraint.activate([
                makeThicknessConstraint(thickness),
                edgeDivider.topAnchor.constraint(equalTo: topAnchor),
                edgeDivider.bottomAnchor.constraint(equalTo: bottomAnchor),
                edgeDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
                edgeDivider.widthAnchor.constraint(equalToConstant: 1),

                stack.topAnchor.constraint(equalTo: topAnchor),
                // Pack buttons from the top; the leftover column height
                // stays empty instead of stretching the buttons.
                stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
                stack.leadingAnchor.constraint(equalTo: edgeDivider.trailingAnchor),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
        }
    }

    /// Builds this edge's height/width constraint and keeps it, so later
    /// hosted-item growth (`updateThickness()`) is a constant update rather
    /// than a teardown.
    private func makeThicknessConstraint(_ constant: CGFloat) -> NSLayoutConstraint {
        let constraint = edge == .top || edge == .bottom
            ? heightAnchor.constraint(equalToConstant: constant)
            : widthAnchor.constraint(equalToConstant: constant)
        thicknessConstraint = constraint
        return constraint
    }

    // MARK: - Public mutation

    func setItems(_ items: [ItemModel], selectedID: UUID?) {
        self.items = items
        self.selectedID = selectedID
        rebuildButtons()
    }

    func setSelected(_ id: UUID?) {
        selectedID = id
        for (buttonID, button) in buttons {
            button.isHighlighted = (buttonID == id)
        }
        for (itemID, controller) in hostedControllers {
            (controller as? TabBarHostedItem)?.isHighlighted = (itemID == id)
        }
    }

    func renameItem(id: UUID, title: String) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            guard case .title = items[idx].item else { return }
            items[idx].item = .title(title)
            buttons[id]?.title = title
        }
    }

    // MARK: - Building

    private func rebuildButtons() {
        for view in stack.arrangedSubviews { view.removeFromSuperview() }
        buttons.removeAll()
        hostViews.removeAll()
        let liveIDs = Set(items.map(\.id))
        for (id, controller) in hostedControllers where !liveIDs.contains(id) {
            controller.removeFromParent()
            hostedControllers[id] = nil
        }
        for item in items {
            let view: NSView
            switch item.item {
            case let .title(title):
                let button = TabButton(id: item.id, title: title)
                button.isHighlighted = (item.id == selectedID)
                button.onSelect = { [weak self] id in self?.onSelect?(id) }
                button.onClose = { [weak self] id in self?.onClose?(id) }
                buttons[item.id] = button
                view = button
            case let .viewController(controller):
                if controller.parent !== hostController { hostController?.addChild(controller) }
                hostedControllers[item.id] = controller
                if let hosted = controller as? TabBarHostedItem {
                    hosted.isHighlighted = (item.id == selectedID)
                    hosted.onClose = { [weak self, id = item.id] in self?.onClose?(id) }
                }
                let host = TabItemHostView(id: item.id, content: controller.view)
                host.onSelect = { [weak self] id in self?.onSelect?(id) }
                hostViews[item.id] = host
                view = host
            }
            stack.addArrangedSubview(view)

            // Vertical bars: each button fills the bar's interior width so
            // labels and close buttons line up flush.
            if stack.orientation == .vertical {
                view.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 8).isActive = true
                view.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -8).isActive = true
            }
        }
        updateThickness()
    }

    /// The bar is as thick as its thickest hosted item needs, never thinner than the button default.
    func updateThickness() {
        let sizes = hostedControllers.values.map(\.preferredContentSize)
        let constant: CGFloat
        switch edge {
        case .top, .bottom:
            constant = max(Self.preferredThickness(for: edge), (sizes.map(\.height).max() ?? 0) + 4)
        case .left, .right:
            constant = max(Self.preferredThickness(for: edge), (sizes.map(\.width).max() ?? 0) + 16)
        }
        thicknessConstraint?.constant = constant
    }
}

// MARK: - TabItemHostView

/// Wraps a hosted item's view so a click anywhere on it selects the tab.
/// The close button inside a hosted item receives its own `mouseDown` first
/// (it is a subview), so a close click does not also select.
@MainActor
private final class TabItemHostView: NSView {
    let id: UUID
    var onSelect: ((UUID) -> Void)?

    init(id: UUID, content: NSView) {
        self.id = id
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        onSelect?(id)
    }
}

// MARK: - TabButton

@MainActor
private final class TabButton: NSView {

    let id: UUID

    var title: String {
        didSet { titleLabel.stringValue = title }
    }

    var isHighlighted: Bool = false {
        didSet { updateAppearance() }
    }

    var onSelect: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?

    private let titleLabel = ThemedLabel(role: .secondaryText, textRole: .caption)
    private let closeButton = NSButton()
    private let backgroundView = NSView()

    init(id: UUID, title: String) {
        self.id = id
        self.title = title
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 4
        backgroundView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close Tab")
        // Per tab: several bars can be on screen at once, so "the close button"
        // is only an address if it names which tab it closes.
        closeButton.accessibilityID("tab-bar.close.\(id.uuidString)")
        closeButton.imagePosition = .imageOnly
        closeButton.symbolConfiguration = .init(pointSize: 10, weight: .regular)
        closeButton.target = self
        closeButton.action = #selector(closeAction(_:))
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(backgroundView)
        backgroundView.addSubview(titleLabel)
        backgroundView.addSubview(closeButton)

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),

            // The label's top/bottom pins give the button an unambiguous
            // fitting height — without them, stack views stretch or
            // collapse buttons on the vertical bars.
            titleLabel.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 4),
            titleLabel.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -4),

            closeButton.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            closeButton.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 14),
            closeButton.heightAnchor.constraint(equalToConstant: 14)
        ])

        observeTheme { tab, _ in tab.updateAppearance() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if closeButton.frame.contains(convert(point, to: backgroundView)) {
            super.mouseDown(with: event)
            return
        }
        onSelect?(id)
    }

    @objc private func closeAction(_ sender: NSButton) {
        onClose?(id)
    }

    private func updateAppearance() {
        let palette = resolvedThemeScope.palette
        backgroundView.layer?.backgroundColor = isHighlighted
            ? palette.nsColor(.selection).cgColor
            : NSColor.clear.cgColor
        // `ThemedLabel` recolors itself from whichever role it holds, so the
        // selected/unselected distinction is a role swap, not a color.
        titleLabel.role = isHighlighted ? .selectionText : .secondaryText
        closeButton.contentTintColor = palette.nsColor(
            isHighlighted ? .selectionText : .tertiaryText
        )
    }
}
