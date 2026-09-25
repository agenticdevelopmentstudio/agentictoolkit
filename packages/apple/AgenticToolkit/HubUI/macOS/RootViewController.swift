#if canImport(AppKit)
import AgenticToolkitHubService
import AgenticDeveloperToolkitUI
import AgenticToolkitHTDV
import AgenticToolkitHub
import AppKit

/// The signed-in window content (spec §5.4–§5.6): a header with the
/// workspace popup and the account menu, the root HTDV (or the Not-a-member
/// pane), and the status strip along the bottom.
public final class RootViewController: NSViewController {
    public private(set) var htdvViewController: HTDVViewController?

    private let composition: HubAppComposition
    private var coordinator: AppCoordinator { composition.coordinator }

    private let workspacePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let accountButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let contentContainer = ThemedBackgroundView(role: .surface)
    /// The shared window footer (AgenticDeveloperToolkitUI). Its status label is
    /// `root.footer.status`; the bar is hidden while there is no message.
    private let footer = WindowFooterBar(accessibilityPrefix: "root.footer")
    private var contentChild: NSViewController?
    private var renderedWorkspaceSlug: String?

    public init(composition: HubAppComposition) {
        self.composition = composition
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func loadView() {
        workspacePopup.setAccessibilityIdentifier("root.workspace")
        accountButton.setAccessibilityIdentifier("root.account")
        workspacePopup.target = self
        workspacePopup.action = #selector(workspaceChosen)
        accountButton.target = self
        accountButton.action = #selector(accountItemChosen)
        let header = NSStackView(views: [workspacePopup, NSView(), accountButton])
        header.orientation = .horizontal
        header.spacing = 12
        header.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        header.setHuggingPriority(.defaultLow, for: .horizontal)

        footer.isHidden = true

        // Explicit constraints rather than a vertical NSStackView. The stack
        // has to be told twice which view absorbs the window's slack — once
        // through `distribution`, once through per-view hugging priorities —
        // and it reads as three equal rows either way. Three anchors say the
        // same thing once, and say it in the order the window is actually
        // divided: the header sits at the top at its own height, the footer at
        // the bottom at its fixed height, and the content takes what is left.
        for subview in [header, contentContainer] {
            subview.translatesAutoresizingMaskIntoConstraints = false
        }
        // The header is exactly as tall as what it holds; the content area is
        // the one view here that should take whatever the window has left.
        // `WindowFooterBar` sets its own `translatesAutoresizingMaskIntoConstraints`
        // and its own height.
        header.setHuggingPriority(.required, for: .vertical)
        contentContainer.setContentHuggingPriority(.defaultLow, for: .vertical)
        let container = ThemedBackgroundView(role: .windowBackground)
        container.addSubview(header)
        container.addSubview(contentContainer)
        container.addSubview(footer)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            contentContainer.topAnchor.constraint(equalTo: header.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: footer.topAnchor),
            contentContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),

            footer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        view = container

        coordinator.environment.onChange = { [weak self] environment in
            self?.renderStatusStrip(environment)
        }
        coordinator.confirmDiscard = { [weak self] in
            await self?.htdvViewController?.confirmDiscard() ?? true
        }
        renderStatusStrip(coordinator.environment)
    }

    /// Called by `MainWindowController` for `.ready` and `.notMember`.
    public func render(_ phase: AppCoordinator.Phase) {
        _ = view
        renderHeader()
        switch phase {
        case .ready(let workspace):
            if renderedWorkspaceSlug != workspace.slug || htdvViewController == nil {
                let dataSource = RootDataSource(workspace: workspace, registry: coordinator.registry)
                let controller = HTDVController(dataSource: dataSource)
                let htdv = HTDVViewController(controller: controller)
                htdvViewController = htdv
                renderedWorkspaceSlug = workspace.slug
                setContent(htdv)
                Task { await controller.load() }
            } else if let htdv = htdvViewController, contentChild !== htdv {
                setContent(htdv)
            }
        case .notMember(let slug):
            htdvViewController = nil
            renderedWorkspaceSlug = nil
            setContent(NotMemberViewController(slug: slug))
        case .launching, .signIn, .loadingWorkspace, .error:
            break
        }
    }

    // MARK: Private

    private func setContent(_ child: NSViewController) {
        contentChild?.view.removeFromSuperview()
        contentChild?.removeFromParent()
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            child.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor)
        ])
        contentChild = child
    }

    private func renderHeader() {
        let workspaces = coordinator.workspaces.workspaces
        workspacePopup.removeAllItems()
        for workspace in workspaces {
            workspacePopup.addItem(withTitle: workspace.listLabel)
            workspacePopup.lastItem?.representedObject = workspace.slug
        }
        if let current = coordinator.workspaces.current, let index = workspaces.firstIndex(of: current) {
            workspacePopup.selectItem(at: index)
        }

        accountButton.removeAllItems()
        guard let user = coordinator.user else { return }
        let model = AccountMenuModel(user: user)
        accountButton.addItem(withTitle: model.avatarLabel)   // pull-down title item
        for item in model.items {
            accountButton.addItem(withTitle: item.label)
            accountButton.lastItem?.representedObject = item.rawValue
        }
    }

    private func renderStatusStrip(_ environment: HubEnvironment) {
        let state = StatusStripState.resolve(
            transportKind: environment.transportKind,
            servedFromCache: environment.servedFromCache,
            expectsDaemon: composition.expectsDaemon
        )
        footer.status = state.message ?? ""
        footer.isHidden = state.message == nil
    }

    @objc private func workspaceChosen() {
        guard let slug = workspacePopup.selectedItem?.representedObject as? String else { return }
        Task { await coordinator.selectWorkspace(slug: slug) }
    }

    @objc private func accountItemChosen() {
        guard let raw = accountButton.selectedItem?.representedObject as? String,
              let item = AccountMenuModel.Item(rawValue: raw) else { return }
        perform(item)
    }

    // MARK: Scripting

    /// What the footer's status shows, or `nil` when the footer is hidden.
    public var scriptStatusStripMessage: String? {
        _ = view
        return footer.isHidden ? nil : footer.status
    }

    /// Picks an account-menu item, as choosing it in the pull-down does.
    ///
    /// It routes through the same `perform(_:)` the menu action does rather
    /// than reimplementing what each item means — a scripted path with its own
    /// copy of that switch is a second implementation free to drift from the
    /// one the user gets.
    ///
    /// - Returns: whether there was anything to act on. `home`, `profile` and
    ///   `settings` need the HTDV on screen; in `.notMember` there is none, and
    ///   saying so is more use to a script than a silent no-op.
    @discardableResult
    public func scriptChooseAccountItem(_ item: AccountMenuModel.Item) -> Bool {
        _ = view
        switch item {
        case .home, .profile, .settings:
            guard htdvViewController != nil else { return false }
        case .logOut:
            break
        }
        perform(item)
        return true
    }

    private func perform(_ item: AccountMenuModel.Item) {
        switch item {
        case .home:
            guard let htdv = htdvViewController else { return }
            Task { await htdv.controller.load() }
        case .profile, .settings:
            guard let htdv = htdvViewController else { return }
            Task { await htdv.controller.select(itemID: RootDataSource.featurePrefix + "settings", atLevel: 0) }
        case .logOut:
            Task { await coordinator.logOut() }
        }
    }
}
#endif
