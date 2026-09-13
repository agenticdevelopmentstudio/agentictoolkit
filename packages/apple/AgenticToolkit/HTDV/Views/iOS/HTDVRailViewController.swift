#if canImport(UIKit)
import UIKit

/// One level as a grouped table. Used as a column in regular width and as a pushed screen in compact width.
public final class HTDVRailViewController: UITableViewController {
    public let levelIndex: Int
    public var onSelect: (String) -> Void = { _ in }
    public var onCreate: () -> Void = {}

    private var items: [HTDVItem] = []
    private var selectedID: String?
    private var emptyMessage = ""
    private let emptyLabel = UILabel()
    private let errorView = HTDVErrorView(frame: .zero)
    private let loadingView = HTDVLoadingView(frame: .zero)
    private static let cellID = "HTDVCell"
    /// The fixed-width constraint applied while this rail is laid out as a column. Held so it can
    /// be deactivated when the rail leaves columns layout (e.g. pushed full-screen after a
    /// regular-to-compact transition) instead of pinning the view at a stale width forever.
    private var columnWidthConstraint: NSLayoutConstraint?

    public init(levelIndex: Int) {
        self.levelIndex = levelIndex
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override public func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellID)
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.numberOfLines = 0
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .add, primaryAction: UIAction { [weak self] _ in self?.onCreate() }
        )
        navigationItem.rightBarButtonItem?.isHidden = true
        tableView.backgroundView = emptyLabel
        errorView.isHidden = true
        loadingView.isHidden = true
        // Opaque so a shown overlay fully occludes stale rows underneath it — `view` here IS the
        // table view (UITableViewController), so there is no separate scroll view to hide.
        errorView.backgroundColor = .systemGroupedBackground
        loadingView.backgroundColor = .systemGroupedBackground
        for overlay in [errorView, loadingView] {
            overlay.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(overlay)
            // `view` here IS the table view, so its own edge anchors are the SCROLLABLE content's
            // edges: an overlay pinned to them is sized and positioned by the content, and scrolls
            // away with it. `frameLayoutGuide` is the visible viewport, which is what an overlay
            // that must occlude the list actually wants. All four edges, deliberately — the overlay
            // is opaque and should cover the area under the navigation bar too.
            NSLayoutConstraint.activate([
                overlay.leadingAnchor.constraint(equalTo: tableView.frameLayoutGuide.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: tableView.frameLayoutGuide.trailingAnchor),
                overlay.topAnchor.constraint(equalTo: tableView.frameLayoutGuide.topAnchor),
                overlay.bottomAnchor.constraint(equalTo: tableView.frameLayoutGuide.bottomAnchor)
            ])
        }
    }

    public func apply(level: HTDVLevel, selectedID: String?) {
        loadViewIfNeeded()
        title = level.title
        items = level.items
        self.selectedID = selectedID
        emptyMessage = level.emptyMessage
        navigationItem.rightBarButtonItem?.isHidden = level.createAction == nil
        errorView.isHidden = true
        loadingView.isHidden = true
        emptyLabel.text = items.isEmpty ? emptyMessage : nil
        tableView.reloadData()
        if let selectedID, let row = items.firstIndex(where: { $0.id == selectedID }) {
            tableView.selectRow(at: IndexPath(row: row, section: 0), animated: false, scrollPosition: .none)
        } else {
            // `reloadData()` does not clear the table's tracked selection, so a rail that survives
            // a level change (only the excess rails are trimmed) would otherwise keep highlighting
            // whatever row was selected under the previous content.
            for indexPath in tableView.indexPathsForSelectedRows ?? [] {
                tableView.deselectRow(at: indexPath, animated: false)
            }
        }
    }

    /// Activates a fixed-width constraint for columns layout, idempotently: a rail re-rendered
    /// while already in columns layout must not accumulate duplicate width constraints, and a
    /// layout-engine width change must actually take effect rather than being masked by the
    /// original constraint still being active.
    public func activateColumnWidth(_ width: CGFloat) {
        if let columnWidthConstraint, columnWidthConstraint.constant == width, columnWidthConstraint.isActive {
            return
        }
        columnWidthConstraint?.isActive = false
        let constraint = view.widthAnchor.constraint(equalToConstant: width)
        constraint.isActive = true
        columnWidthConstraint = constraint
    }

    /// Deactivates the column-width constraint, if any. Must be called whenever this rail leaves
    /// columns layout (compact stack push, or removal), otherwise it stays pinned at whatever
    /// width it last had as a column.
    public func deactivateColumnWidth() {
        columnWidthConstraint?.isActive = false
        columnWidthConstraint = nil
    }

    public func showLoading() {
        loadViewIfNeeded()
        loadingView.isHidden = false
        errorView.isHidden = true
        // Both overlays are opaque siblings added to `view` (the table view) in `viewDidLoad`, so
        // bringing the visible one to front is what "hides the list" behind an opaque overlay.
        view.bringSubviewToFront(loadingView)
    }

    public func showError(_ message: String, retry: @escaping () -> Void) {
        loadViewIfNeeded()
        errorView.messageLabel.text = message
        errorView.onRetry = retry
        errorView.isHidden = false
        loadingView.isHidden = true
        view.bringSubviewToFront(errorView)
    }

    // MARK: Table

    override public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    override public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellID, for: indexPath)
        let content = HTDVCellContent(item: items[indexPath.row])
        var config = cell.defaultContentConfiguration()
        config.text = content.label
        config.secondaryText = content.sublabel
        // Assigned on every path (not just when non-nil) so a recycled cell never keeps a
        // previous row's icon.
        if let name = content.systemImage {
            config.image = UIImage(systemName: name)
        } else {
            config.image = nil
        }
        cell.contentConfiguration = config
        applyAccessory(content, to: cell)
        return cell
    }

    /// Composes the trailing accessory. `accessoryType = .disclosureIndicator` and `accessoryView`
    /// occupy the same slot and the view wins, so the previous code had to choose — and chose the
    /// chevron, silently dropping the badge on every disclosing row. A disclosing row with a badge
    /// gets both, composed into one accessory view, the way `HTDVRailCellView` does on macOS.
    private func applyAccessory(_ content: HTDVCellContent, to cell: UITableViewCell) {
        switch (makeBadgeView(content.badge), content.isDisclosing) {
        case (nil, false):
            cell.accessoryType = .none
            cell.accessoryView = nil
        case (nil, true):
            cell.accessoryType = .disclosureIndicator
            cell.accessoryView = nil
        case (let badge?, false):
            cell.accessoryType = .none
            cell.accessoryView = badge
        case (let badge?, true):
            cell.accessoryType = .none
            cell.accessoryView = makeBadgeAndChevron(badge)
        }
    }

    private func makeBadgeView(_ badge: HTDVBadge?) -> UIView? {
        switch badge {
        case .count(let badgeCount):
            let label = UILabel()
            label.text = String(badgeCount)
            label.font = .monospacedDigitSystemFont(ofSize: UIFont.smallSystemFontSize, weight: .medium)
            label.textColor = .secondaryLabel
            label.sizeToFit()
            return label
        case .dot(let badgeColor):
            let dot = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
            dot.backgroundColor = HTDVBadgeColorMapping.uiColor(badgeColor)
            dot.layer.cornerRadius = 5
            // Both a frame and a size: the frame sizes it when it is the bare accessory view (which
            // UIKit positions by frame), the constraints size it inside the stack below (which sizes
            // its arranged subviews by Auto Layout, and a plain `UIView` has no intrinsic size).
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 10),
                dot.heightAnchor.constraint(equalToConstant: 10)
            ])
            return dot
        case nil:
            return nil
        }
    }

    /// `accessoryView` is laid out by its frame, not by Auto Layout, so the composed stack is given
    /// an explicit frame from its own fitting size rather than left at zero.
    private func makeBadgeAndChevron(_ badge: UIView) -> UIView {
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit
        let stack = UIStackView(arrangedSubviews: [badge, chevron])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.frame = CGRect(origin: .zero, size: stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize))
        return stack
    }

    override public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        onSelect(items[indexPath.row].id)
    }
}
#endif
