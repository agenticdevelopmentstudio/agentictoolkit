import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// Edge-aligned tab bar header for `MultiTabbedViewController`. Renders one
/// pill-style button per tab inside an `NSStackView` whose orientation
/// follows the bar's `Edge`. Calls back to its owner via closures so it
/// stays decoupled from the controller's public API.
@MainActor
final class TabBarView: NSView {

    /// The bar's narrow dimension — height for top/bottom, width for
    /// left/right — when nothing hosted in it asks for more.
    static func preferredThickness(for edge: Edge) -> CGFloat {
        switch edge {
        case .top, .bottom: return 28
        case .left, .right: return 140
        }
    }

    /// The gap between an item and the *outer* side of the bar — the window
    /// side. The workspace side gets none: an item is flush against it, which
    /// is what lets a tab read as attached to the workspace rather than as a
    /// chip floating in a bar of its own.
    static let outerPadding: CGFloat = 6

    /// The gap at each end of the bar, along the direction it lays items out.
    private static let endPadding: CGFloat = 8

    let edge: Edge

    // MARK: - Tab metadata

    struct ItemModel {
        let id: UUID
        var item: TabItem
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

        // Padding on the outer side only, so items meet the workspace side of
        // the bar — see `outerPadding`. The cross-axis alignment is set to
        // that same workspace side rather than to the centre, so the
        // alignment constraints NSStackView installs agree with the explicit
        // cross-axis pins in `rebuildButtons()` instead of fighting them.
        let outer = Self.outerPadding
        let ends = Self.endPadding
        switch edge {
        case .top:
            stack.orientation = .horizontal
            stack.alignment = .bottom
            stack.edgeInsets = NSEdgeInsets(top: outer, left: ends, bottom: 0, right: ends)
        case .bottom:
            stack.orientation = .horizontal
            stack.alignment = .top
            stack.edgeInsets = NSEdgeInsets(top: 0, left: ends, bottom: outer, right: ends)
        case .left:
            stack.orientation = .vertical
            stack.alignment = .trailing
            stack.edgeInsets = NSEdgeInsets(top: ends, left: outer, bottom: ends, right: 0)
        case .right:
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.edgeInsets = NSEdgeInsets(top: ends, left: 0, bottom: ends, right: outer)
        }
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        wantsLayer = true
        observeTheme { bar, palette in
            // The backdrop a tab sits on, a plane below the `.surface` an
            // inactive tab paints — otherwise a tab is the same colour as its
            // bar and only its border has any shape. There is no divider
            // along the workspace side: the workspace draws its own outline,
            // and the tabs break through it, which is what makes them read as
            // part of it.
            bar.layer?.backgroundColor = palette.nsColor(.windowBackground).cgColor
        }

        addSubview(stack)

        let thickness = Self.preferredThickness(for: edge)

        switch edge {
        case .top, .bottom:
            NSLayoutConstraint.activate([
                makeThicknessConstraint(thickness),
                stack.topAnchor.constraint(equalTo: topAnchor),
                stack.leadingAnchor.constraint(equalTo: leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        case .left, .right:
            NSLayoutConstraint.activate([
                makeThicknessConstraint(thickness),
                stack.topAnchor.constraint(equalTo: topAnchor),
                // Pack buttons from the top; the leftover column height
                // stays empty instead of stretching the buttons.
                stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
                stack.leadingAnchor.constraint(equalTo: leadingAnchor),
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

    /// The caller (`MultiTabbedViewController.renameTab`) already refuses to
    /// call this for a `.viewController` item, so there is nothing left to
    /// guard against here.
    func renameItem(id: UUID, title: String) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].item = .title(title)
            buttons[id]?.title = title
        }
    }

    // MARK: - Building

    private func rebuildButtons() {
        // Captured before the stack is torn down below, so the reconciliation
        // loop can tell whether a hosted controller's view is still sitting
        // in the wrapper *this bar* gave it, as opposed to one another bar
        // handed it in the meantime (see the loop's comment).
        let previousHostViews = hostViews

        for view in stack.arrangedSubviews { view.removeFromSuperview() }
        buttons.removeAll()
        hostViews.removeAll()

        // Reconcile hosted children against the new items on both id *and*
        // payload: an id that is gone, or whose `.viewController` payload
        // changed identity (or reverted to `.title`), gets its old
        // controller torn down here — otherwise it stays parented forever
        // and keeps inflating `updateThickness()`.
        var currentControllers: [UUID: NSViewController] = [:]
        for item in items {
            guard case let .viewController(controller) = item.item else { continue }
            currentControllers[item.id] = controller
        }
        for (id, oldController) in hostedControllers where currentControllers[id] !== oldController {
            // A cross-edge move (insert on the new edge before removing from
            // the old one, since there is no edge-to-edge `moveTab`) already
            // reparents this controller's view onto the *new* bar's wrapper
            // when that bar rebuilds first — so by the time this bar notices
            // the id is gone, `oldController.view`'s superview is the other
            // bar's wrapper, not the one this bar itself handed it a moment
            // ago. Tearing it down here as well would rip the view out of
            // the new bar's display and cut the controller's
            // `preferredContentSizeDidChange` routing, so only tear down a
            // controller this bar's own (now-detached) wrapper still held.
            if oldController.view.superview === previousHostViews[id] {
                oldController.view.removeFromSuperview()
                oldController.removeFromParent()
            }
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
                stack.addArrangedSubview(view)
                // Vertical bars: each button fills the bar's interior width
                // so labels and close buttons line up flush.
                if stack.orientation == .vertical {
                    pinCrossAxis(view)
                }
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
                stack.addArrangedSubview(view)
                // A hosted item's content view reports no intrinsic size. Its
                // length along the stack's main axis is already handled —
                // AppKit constrains a view controller's view from
                // `preferredContentSize` (see `updateThickness()`) — but the
                // cross axis is not: the item has to be told to fill the
                // bar's interior, or it sits at whatever width that same
                // `preferredContentSize` asked for while the bar is as wide
                // as the widest item. These pins are required priority and
                // so win over that 501 constraint, which is the point.
                pinCrossAxis(host)
            }
        }
        updateThickness()
    }

    /// Stretches one arranged item across the bar's thickness, from the outer
    /// side to the workspace side.
    ///
    /// The constants restate `stack.edgeInsets` on this axis rather than
    /// pinning to the stack's raw bounds: NSStackView's own alignment
    /// constraints are required priority and already honour the insets, so a
    /// pin that disagreed with them by even a point would make the layout
    /// unsatisfiable.
    private func pinCrossAxis(_ view: NSView) {
        let outer = Self.outerPadding
        switch edge {
        case .top:
            view.topAnchor.constraint(equalTo: stack.topAnchor, constant: outer).isActive = true
            view.bottomAnchor.constraint(equalTo: stack.bottomAnchor).isActive = true
        case .bottom:
            view.topAnchor.constraint(equalTo: stack.topAnchor).isActive = true
            view.bottomAnchor.constraint(equalTo: stack.bottomAnchor, constant: -outer).isActive = true
        case .left:
            view.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: outer).isActive = true
            view.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        case .right:
            view.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
            view.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -outer).isActive = true
        }
    }

    /// The bar is as thick as its thickest hosted item needs, never thinner
    /// than the button default.
    ///
    /// Only the thickness axis is this method's business. The length axis —
    /// the stack's main axis — needs nothing from here: a hosted item is
    /// always an `NSViewController`, and AppKit installs
    /// `NSViewController.preferredContentSize.width`/`.height` constraints
    /// on that controller's view at priority 501, updating them whenever
    /// `preferredContentSize` changes. Pinning the length here as well would
    /// restate those at required priority, which is strictly worse: 501 is
    /// deliberately overridable, and a required duplicate takes that escape
    /// hatch away while adding nothing.
    func updateThickness() {
        let sizes = hostedControllers.values.map(\.preferredContentSize)
        // `outerPadding` is the one thing standing between an item and the
        // bar's own edge on this axis — the workspace side is flush — so the
        // bar is exactly that much thicker than its thickest item.
        let thickest: CGFloat
        switch edge {
        case .top, .bottom: thickest = sizes.map(\.height).max() ?? 0
        case .left, .right: thickest = sizes.map(\.width).max() ?? 0
        }
        thicknessConstraint?.constant = max(
            Self.preferredThickness(for: edge),
            thickest + Self.outerPadding
        )
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
