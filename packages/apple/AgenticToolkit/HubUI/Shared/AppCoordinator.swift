import AgenticToolkitHubService
import AgenticToolkitHub
import Foundation

/// The launch/sign-in/workspace state machine (spec §5.1). Platform code
/// renders `phase`; everything that decides *which* phase comes next is here
/// and unit-tested.
@MainActor
public final class AppCoordinator {
    public enum Phase: Equatable, Sendable {
        case launching
        case signIn
        case loadingWorkspace
        case ready(HubWorkspace)
        case notMember(String)
        case error(String)
    }

    public private(set) var phase: Phase = .launching {
        didSet { if phase != oldValue { onChange(phase) } }
    }

    public var onChange: @MainActor (Phase) -> Void = { _ in }
    public var confirmDiscard: @MainActor () async -> Bool = { true }
    public var onResume: @MainActor () async -> Void = {}

    public let environment: HubEnvironment
    public let session: SessionController
    public let workspaces: WorkspaceController
    public let registry: FeatureModuleRegistry
    public let appearance: AppearanceController

    public var user: HubUser? { session.user }

    private var workspaceLoad: Task<Void, Never>?

    public init(
        environment: HubEnvironment,
        session: SessionController,
        workspaces: WorkspaceController,
        registry: FeatureModuleRegistry,
        appearance: AppearanceController
    ) {
        self.environment = environment
        self.session = session
        self.workspaces = workspaces
        self.registry = registry
        self.appearance = appearance
        session.onChange = { [weak self] state in self?.sessionChanged(state) }
        workspaces.onChange = { [weak self] state in self?.workspaceChanged(state) }
    }

    public func start() async {
        phase = .launching
        await session.restore()
    }

    public func selectWorkspace(slug: String) async {
        guard await confirmDiscard() else { return }
        await workspaces.select(slug: slug)
    }

    public func logOut() async {
        guard await confirmDiscard() else { return }
        await session.signOut()
    }

    public func retry() async {
        switch session.state {
        case .error, .restoring:
            await session.restore()
        case .signedIn:
            await workspaces.retry()
        case .signedOut:
            phase = .signIn
        }
    }

    public func applicationDidBecomeActive() async {
        await onResume()
    }

    // MARK: Private

    private func sessionChanged(_ state: SessionState) {
        switch state {
        case .restoring:
            phase = .launching
        case .signedOut:
            workspaceLoad?.cancel()
            workspaces.reset()
            registry.reset()
            appearance.reset()
            phase = .signIn
        case .signedIn:
            phase = .loadingWorkspace
            workspaceLoad?.cancel()
            workspaceLoad = Task { [appearance, workspaces] in
                Task { await appearance.refresh() }
                await workspaces.load()
            }
        case .error(let message):
            phase = .error(message)
        }
    }

    private func workspaceChanged(_ state: WorkspaceState) {
        guard case .signedIn = session.state else { return }
        switch state {
        case .idle:
            break
        case .loading:
            phase = .loadingWorkspace
        case .loaded(let workspace):
            phase = .ready(workspace)
        case .notMember(let slug):
            phase = .notMember(slug)
        case .failed(let message):
            phase = .error(message)
        }
    }
}
