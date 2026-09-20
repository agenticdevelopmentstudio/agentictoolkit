import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreUI
import AgenticToolkitCoreMacOS

/// The Conversations window's contents: the session shelf on the left, the
/// merged feed on the right, and the toolbar that discloses the one over the
/// other.
///
/// The System Settings look — an inset rounded panel with the window's material
/// running behind it, full height under the traffic lights — is *not* what an
/// `NSSplitViewItem(sidebarWithViewController:)` draws here: that fills its rect
/// with square, edge-to-edge sidebar material, in this window and in the
/// Settings window alike. So the shape is drawn by hand in the shelf, out of
/// the system's own material, and this type uses a plain split item
/// (`native-controls` honoured as far as AppKit will take it).
///
/// This type owns the wiring between the two halves — the shelf's ticks become
/// the feed's filter, the feed's roster becomes the shelf's rows — and nothing
/// about either half's contents.
@MainActor
public final class ConversationsSplitViewController: NSSplitViewController {

    private enum ItemID {
        static let toggleShelf = NSToolbarItem.Identifier("conversations.toggle-shelf")
    }

    public let shelf: ConversationsShelfViewController
    public let feed: ConversationsViewController

    /// Held because `NSToolbar.delegate` is weak: a delegate with no other owner
    /// dies the instant `configureWindowChrome` returns, and the titlebar comes
    /// up empty with no error to explain it.
    private var toolbarDelegate: WindowToolbarBuilder.Delegate?

    public init(feed: ConversationsViewController) {
        self.feed = feed
        self.shelf = ConversationsShelfViewController()
        super.init(nibName: nil, bundle: nil)

        shelf.onHiddenChanged = { [weak self] hidden in
            self?.feed.setHiddenSessions(hidden)
        }
        feed.onRosterChanged = { [weak self] sessions in
            self?.shelf.sessions = sessions
        }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    public override func viewDidLoad() {
        super.viewDidLoad()

        // A plain item, not `sidebarWithViewController:`. A sidebar item fills
        // its whole rect with the system's sidebar material, edge to edge and
        // square-cornered, and that backdrop is drawn behind everything the
        // shelf adds — so an inset panel on top of it still has full-bleed
        // material showing in the margin. The shelf draws its own inset panel
        // instead (see `ConversationsShelfViewController`), which is the only
        // way to get the System Settings outline in a window this app paints.
        let shelfItem = NSSplitViewItem(viewController: shelf)
        shelfItem.minimumThickness = 180
        shelfItem.maximumThickness = 340
        shelfItem.canCollapse = true
        // Collapsed to begin with: the window's job is the conversation, and a
        // reader who has never needed to hide a session should not have to
        // dismiss a list to get at it.
        shelfItem.isCollapsed = true
        shelfItem.holdingPriority = .defaultLow + 1

        let feedItem = NSSplitViewItem(viewController: feed)
        feedItem.minimumThickness = 320

        addSplitViewItem(shelfItem)
        addSplitViewItem(feedItem)

        // A plain `NSSplitView`, not the themed one and not a subclass of our
        // own: overriding `dividerColor` makes AppKit fall back to view-backed
        // dividers, and it then asks `shouldHideDivider(at:)` from inside
        // `_setupSplitView` while `splitViewItems` is still empty — an
        // NSRangeException that trapped the app on launch, three times, before
        // the subclass came back out. The shelf's panel is inset from its
        // trailing edge anyway, so there is no divider to hide.
        splitView.autosaveName = NSSplitView.AutosaveName("conversations-split")
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        // The toolbar builds its items lazily, so the button usually does not
        // exist yet when `configureWindowChrome` runs. By the time the window is
        // on screen it does.
        updateToggleAppearance()
    }

    /// Whether the shelf is showing.
    public var isShelfVisible: Bool {
        guard let item = splitViewItems.first else { return false }
        return !item.isCollapsed
    }

    /// Shows the shelf if it is hidden, hides it if it is showing.
    @objc public func toggleShelf() {
        guard let item = splitViewItems.first else { return }
        item.animator().isCollapsed = !item.isCollapsed
        updateToggleAppearance()
    }

    // MARK: - Window chrome

    /// Installs the toolbar and the clear titlebar on the window hosting this
    /// controller. Called from the window controller's `configureWindow`,
    /// because a view controller does not own a window and should not go
    /// looking for one.
    public func configureWindowChrome(_ window: NSWindow) {
        let delegate = WindowToolbarBuilder.Delegate(
            items: [
                .button(
                    identifier: ItemID.toggleShelf,
                    symbol: "sidebar.left",
                    label: "Sessions",
                    action: #selector(toggleShelf)),
                .flexibleSpace
            ],
            target: self)
        toolbarDelegate = delegate

        let toolbar = delegate.makeToolbar(identifier: "conversations.toolbar")
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        // The three lines that make the titlebar clear: the content runs the
        // full height of the window, the titlebar draws no material of its own,
        // and no hairline is stamped across the join. Without the third, the
        // sidebar's inset panel is cut off by a line at the top.
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.titleVisibility = .hidden

        updateToggleAppearance()
    }

    /// Keeps the toggle reading as the state it toggles — filled and accented
    /// while the shelf is out, outlined and quiet while it is away.
    private func updateToggleAppearance() {
        guard let button = toolbarDelegate?.button(for: ItemID.toggleShelf) else { return }
        WindowToolbarBuilder.applyDisclosureAppearance(
            to: button,
            disclosed: isShelfVisible,
            outlineSymbol: "sidebar.left",
            filledSymbol: "sidebar.left",
            showTooltip: "Show Sessions",
            hideTooltip: "Hide Sessions")
    }
}
