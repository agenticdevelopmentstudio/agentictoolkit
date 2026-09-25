import AgenticToolkitHub
import Foundation

public enum WorkspaceState: Equatable, Sendable {
    case idle
    case loading
    case loaded(HubWorkspace)
    case notMember(String)
    case failed(String)
}

/// Loads the caller's workspaces, resolves the current one (spec §5.3) and
/// keeps the recents list the account menu and picker show.
@MainActor
public final class WorkspaceController {
    /// The single authoritative definition of the recents `UserDefaults` key —
    /// `SessionController.signOut()` also clears it, so it refers to this
    /// constant rather than keeping its own copy of the literal.
    public static let recentsKey = "hub.recents"
    public static let maxRecents = 5
    public static let noWorkspacesMessage = "No workspaces are available for this account."

    public private(set) var state: WorkspaceState = .idle {
        didSet { if state != oldValue { onChange(state) } }
    }
    public private(set) var workspaces: [HubWorkspace] = []
    public private(set) var recents: [String]
    public var onChange: @MainActor (WorkspaceState) -> Void = { _ in }

    public var current: HubWorkspace? {
        if case .loaded(let workspace) = state { return workspace }
        return nil
    }

    private let provider: any WorkspacesProviding
    private let defaults: UserDefaults
    private var lastRequestedSlug: String?
    private var loadInFlight: Task<Void, Never>?

    public init(provider: any WorkspacesProviding, defaults: UserDefaults = .standard) {
        self.provider = provider
        self.defaults = defaults
        self.recents = defaults.stringArray(forKey: Self.recentsKey) ?? []
    }

    /// `GET /workspaces` then the server preference (best-effort: a failed
    /// preference read only means "no preference"), then resolve. Overlapping
    /// calls (e.g. a retry racing a picker-driven reload) share one in-flight
    /// load instead of each running its own fetch and resolve — two such
    /// resolves interleaving could otherwise land `state`/`workspaces` from
    /// different responses, leaving `current` outside `workspaces`. Mirrors
    /// `HubEnvironment.refreshTransport()`'s `refreshInFlight` pattern.
    public func load(requestedSlug: String? = nil) async {
        if let loadInFlight {
            return await loadInFlight.value
        }
        let task = Task { @MainActor in
            self.lastRequestedSlug = requestedSlug
            self.state = .loading
            let list: [HubWorkspace]
            do {
                list = try await self.provider.listWorkspaces()
            } catch {
                self.state = .failed(HubError.from(error).message)
                return
            }
            self.workspaces = list
            let pref = (try? await self.provider.preferredSlug()) ?? nil
            self.apply(WorkspaceResolver.resolve(workspaces: list, requestedSlug: requestedSlug, serverPrefSlug: pref))
        }
        loadInFlight = task
        defer { loadInFlight = nil }
        await task.value
    }

    /// An explicit pick from the picker or the recents list.
    public func select(slug: String) async {
        lastRequestedSlug = slug
        let resolution = WorkspaceResolver.resolve(workspaces: workspaces, requestedSlug: slug, serverPrefSlug: nil)
        apply(resolution)
        if case .workspace(let workspace) = resolution, WorkspaceResolver.shouldPersist(workspace) {
            try? await provider.setPreferredSlug(workspace.slug)
        }
    }

    public func retry() async {
        await load(requestedSlug: lastRequestedSlug)
    }

    /// Sign-out: forget everything but leave `hub.recents` to `SessionController.signOut()`,
    /// which clears it before the session goes away.
    public func reset() {
        workspaces = []
        recents = []
        lastRequestedSlug = nil
        state = .idle
    }

    private func apply(_ resolution: WorkspaceResolution) {
        switch resolution {
        case .workspace(let workspace):
            pushRecent(workspace.slug)
            state = .loaded(workspace)
        case .notFound(let slug):
            state = .notMember(slug)
        case .none:
            state = .failed(Self.noWorkspacesMessage)
        }
    }

    private func pushRecent(_ slug: String) {
        var updated = recents.filter { $0 != slug }
        updated.insert(slug, at: 0)
        if updated.count > Self.maxRecents {
            updated = Array(updated.prefix(Self.maxRecents))
        }
        recents = updated
        defaults.set(updated, forKey: Self.recentsKey)
    }
}
