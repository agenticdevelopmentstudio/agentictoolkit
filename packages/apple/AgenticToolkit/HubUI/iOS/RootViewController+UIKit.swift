#if canImport(UIKit)
import AgenticToolkitHubService
import AgenticDeveloperToolkitUI
import AgenticToolkitHTDV
import AgenticToolkitHub
import UIKit

/// Phase-driven container: launch spinner, sign-in, root HTDV or
/// Not-a-member pane, plus the status strip (spec §5.4–§5.6).
public final class RootViewController: UIViewController {
    public private(set) var htdvViewController: HTDVViewController?

    private let composition: HubAppComposition
    private var coordinator: AppCoordinator { composition.coordinator }

    private let launch = LaunchViewController()
    private var signIn: SignInViewController?
    private var contentChild: UIViewController?
    private var renderedWorkspaceSlug: String?
    private let contentContainer = UIView()
    private let statusStrip = ThemedLabel(role: .secondaryText, textRole: .caption)
    private var stripHeight: NSLayoutConstraint!

    public init(composition: HubAppComposition) {
        self.composition = composition
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.observeTheme { view, palette in view.backgroundColor = palette.windowBackgroundColor }
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        statusStrip.translatesAutoresizingMaskIntoConstraints = false
        statusStrip.textAlignment = .center
        // The strip sits *on* the window rather than in it, so it takes the
        // `surface` plane — the one step of separation the palette draws
        // between the two.
        statusStrip.observeTheme { strip, palette in strip.backgroundColor = palette.surfaceColor }
        view.addSubview(contentContainer)
        view.addSubview(statusStrip)
        stripHeight = statusStrip.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: statusStrip.topAnchor),
            statusStrip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusStrip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusStrip.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stripHeight
        ])

        coordinator.onChange = { [weak self] phase in self?.render(phase) }
        coordinator.environment.onChange = { [weak self] environment in self?.renderStatusStrip(environment) }
        coordinator.appearance.onChange = { _ in
            // Not written straight to the window's `overrideUserInterfaceStyle`:
            // the theme owns that, and this preference is only what an `.auto`
            // theme defers to (see `AppearanceController`). Re-driving the theme
            // is what makes the new answer take effect without overruling a
            // theme that has one of its own.
            ThemeManager.shared?.refreshApplicationAppearance()
        }
        coordinator.confirmDiscard = { [weak self] in
            await self?.htdvViewController?.confirmDiscard() ?? true
        }
        renderStatusStrip(coordinator.environment)
        render(coordinator.phase)
    }

    /// Called once by `SceneDelegate` after the view controller is installed.
    public func start() {
        loadViewIfNeeded()
        Task { await coordinator.start() }
    }

    // MARK: Rendering

    private func render(_ phase: AppCoordinator.Phase) {
        switch phase {
        case .launching, .loadingWorkspace:
            navigationItem.title = nil
            clearBarItems()
            launch.showLoading()
            setContent(launch)
        case .error(let message):
            clearBarItems()
            launch.showError(message) { [weak self] in
                Task { await self?.coordinator.retry() }
            }
            setContent(launch)
        case .signIn:
            navigationItem.title = "Sign In"
            clearBarItems()
            htdvViewController = nil
            renderedWorkspaceSlug = nil
            let controller = signIn ?? SignInViewController(viewModel: composition.makeSignInViewModel())
            signIn = controller
            setContent(controller)
        case .ready(let workspace):
            signIn = nil
            navigationItem.title = workspace.listLabel
            renderBarItems()
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
            signIn = nil
            navigationItem.title = NotMemberCopy.title
            renderBarItems()
            htdvViewController = nil
            renderedWorkspaceSlug = nil
            setContent(NotMemberViewController(slug: slug))
        }
        navigationController?.popToRootViewController(animated: false)
    }

    private func setContent(_ child: UIViewController) {
        guard contentChild !== child else { return }
        if let old = contentChild {
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            child.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor)
        ])
        child.didMove(toParent: self)
        contentChild = child
    }

    private func clearBarItems() {
        navigationItem.leftBarButtonItem = nil
        navigationItem.rightBarButtonItem = nil
    }

    private func renderBarItems() {
        let workspaces = coordinator.workspaces.workspaces
        let current = coordinator.workspaces.current
        let workspaceActions = workspaces.map { workspace in
            UIAction(title: workspace.listLabel, state: workspace == current ? .on : .off) { [weak self] _ in
                Task { await self?.coordinator.selectWorkspace(slug: workspace.slug) }
            }
        }
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.grid.2x2"),
            menu: UIMenu(title: "Workspace", children: workspaceActions)
        )

        guard let user = coordinator.user else {
            navigationItem.rightBarButtonItem = nil
            return
        }
        let model = AccountMenuModel(user: user)
        let accountActions = model.items.map { item in
            UIAction(title: item.label, attributes: item == .logOut ? .destructive : []) { [weak self] _ in
                self?.perform(item)
            }
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: model.initials,
            menu: UIMenu(title: model.avatarLabel, children: accountActions)
        )
    }

    private func renderStatusStrip(_ environment: HubEnvironment) {
        let state = StatusStripState.resolve(
            transportKind: environment.transportKind,
            servedFromCache: environment.servedFromCache,
            expectsDaemon: composition.expectsDaemon
        )
        statusStrip.text = state.message
        stripHeight.constant = state.message == nil ? 0 : 24
        statusStrip.isHidden = state.message == nil
    }

    private func perform(_ item: AccountMenuModel.Item) {
        switch item {
        case .home:
            guard let htdv = htdvViewController else { return }
            navigationController?.popToRootViewController(animated: true)
            Task { await htdv.controller.load() }
        case .profile, .settings:
            guard let htdv = htdvViewController else { return }
            Task { await htdv.controller.select(itemID: RootDataSource.featurePrefix + "settings", atLevel: 0) }
        case .logOut:
            Task { await coordinator.logOut() }
        }
    }
}

public extension HubColorMode {
    /// The style this mode asks for, or `.unspecified` for "whatever the system
    /// says" — the shape `ThemeAppearanceDriver.autoAppearance` returns, which
    /// is the app delegate's one use for it.
    var uiStyle: UIUserInterfaceStyle {
        switch self {
        case .auto: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}
#endif
