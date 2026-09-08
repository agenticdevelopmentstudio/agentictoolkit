//
//  LanguageServerStatusModel.swift
//  AgenticToolkit
//

import Combine
import Foundation
import AgenticToolkitCore
import AgenticToolkitLanguage

/// One (project, language server) pair, flattened into something a list can
/// draw and a diff can compare.
///
/// **The row is where `LanguageServerSessionState` stops being a state and
/// becomes text.** That enum is deliberately not `Equatable` — its `.failed`
/// case carries a `LanguageServerFailure`, which holds `any Error` — so it can
/// neither sit in a `@Published` value SwiftUI diffs nor be compared to decide
/// whether a redraw is needed. Projecting it here, once, gives every consumer
/// an `Equatable` value and keeps the error-to-string decision in one place
/// instead of in each view that shows it.
public struct LanguageServerStatusRow: Identifiable, Equatable, Sendable {

    /// What a session is doing, with the failure's payload lifted out beside it
    /// rather than carried in the case.
    public enum Kind: Equatable, Sendable {
        case idle
        case starting
        case running
        case stopped
        case failed
    }

    /// Composed from the project id and the configuration id, because neither
    /// alone is unique in this list: one project runs several servers, and one
    /// server configuration runs in every open project.
    public struct RowID: Hashable, Sendable {
        public let projectID: UUID
        public let configurationID: UUID
    }

    public let id: RowID
    public let projectName: String
    public let configurationName: String
    public let kind: Kind

    /// One line explaining a failure; empty for every other kind.
    public let failureReason: String

    /// What the server wrote on stderr before it died, trimmed. Empty for every
    /// other kind, and for a failure that produced no output.
    public let standardErrorText: String

    public var projectID: UUID { id.projectID }
    public var configurationID: UUID { id.configurationID }

    public init(
        projectID: UUID,
        configurationID: UUID,
        projectName: String,
        configurationName: String,
        state: LanguageServerSessionState
    ) {
        self.id = RowID(projectID: projectID, configurationID: configurationID)
        self.projectName = projectName
        self.configurationName = configurationName
        switch state {
        case .idle:
            self.kind = .idle
            self.failureReason = ""
            self.standardErrorText = ""
        case .starting:
            self.kind = .starting
            self.failureReason = ""
            self.standardErrorText = ""
        case .running:
            self.kind = .running
            self.failureReason = ""
            self.standardErrorText = ""
        case .stopped:
            self.kind = .stopped
            self.failureReason = ""
            self.standardErrorText = ""
        case .failed(let failure):
            self.kind = .failed
            self.failureReason = failure.error.localizedDescription
            self.standardErrorText = failure.standardErrorText
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

/// Every open project's language servers and what each one is doing, as one
/// flat sorted list.
///
/// This is the testable half of the language server settings panel: it owns no
/// view, so its behaviour is driven from a `CurrentValueSubject` rather than
/// from a window.
///
/// **The project list arrives as a publisher and is never fetched.** The
/// obvious alternative — reaching for `ProjectWindowManager.shared` in here —
/// would weld a settings model to a window manager and to that singleton's
/// lifetime, and would make every test need an open window
/// (`dependency-injection`). `Features` supplies the real publisher.
@MainActor
public final class LanguageServerStatusModel: ObservableObject {

    /// The slice of an open project this model needs: what identifies it, what
    /// to call it, and where its servers live.
    ///
    /// Deliberately not `ProjectWorkspace`: that type carries a database
    /// handle, a `GitRepo` and the whole editor stack, none of which a status
    /// list has any business holding.
    public struct Project {
        public let id: UUID
        public let name: String
        public let registry: LanguageServerRegistry

        public init(id: UUID, name: String, registry: LanguageServerRegistry) {
            self.id = id
            self.name = name
            self.registry = registry
        }
    }

    @Published public private(set) var rows: [LanguageServerStatusRow] = []

    /// False when no project window is open, which is not the same as "no
    /// server is running": a language server exists only inside a project, so a
    /// panel with no open project has nothing to report rather than bad news.
    @Published public private(set) var hasOpenProject: Bool = false

    /// The last values *delivered* for one project, and the only thing `rows`
    /// is ever recomputed from.
    ///
    /// **Not a convenience — a correctness requirement.** `@Published` fires
    /// from `willSet`, so inside a sink on `registry.$sessionStates` the
    /// registry's own `sessionStates` property still holds the *previous*
    /// dictionary. A recompute that read the registry back would build every
    /// row from the value the emission replaced, and the panel would sit
    /// exactly one transition behind the server it describes. So the sink
    /// stores what it was handed, and the recompute reads only this.
    private struct Snapshot {
        var name: String
        var states: [UUID: LanguageServerSessionState]
        var configurations: [LanguageServerConfiguration]
    }

    private var snapshots: [UUID: Snapshot] = [:]

    /// Project order as delivered, so `recomputeRows` iterates something
    /// deterministic rather than a dictionary. The rows themselves sort by
    /// name; this only bounds which projects are considered.
    private var projectIDs: [UUID] = []

    /// One subscription set per project, dropped when the project closes.
    ///
    /// Keyed rather than pooled in a single `Set<AnyCancellable>`, because a
    /// closed project's sink has to be cancelled individually: a sink on a
    /// registry's publisher holds that registry, and holding it keeps a closed
    /// project's servers in the list — and its subprocesses alive — for as long
    /// as the settings window exists.
    private var registryObservations: [UUID: Set<AnyCancellable>] = [:]

    private var projectsCancellable: AnyCancellable?

    public init(projects: some Publisher<[Project], Never>) {
        projectsCancellable = projects.sink { [weak self] projects in
            self?.observe(projects)
        }
    }

    /// Rebuilds the per-registry subscriptions for exactly the projects given.
    ///
    /// Rebuilt wholesale rather than diffed: a project's registry is created
    /// with its window and never swapped, so re-subscribing to one that is
    /// still open costs a single immediate re-emission of values this model
    /// already holds. Diffing would buy nothing and would add the one bug this
    /// method cannot have — a subscription that outlived its project.
    private func observe(_ projects: [Project]) {
        let ids = projects.map(\.id)
        projectIDs = ids
        let surviving = Set(ids)
        // Removed, not merely cancelled: `AnyCancellable` cancels on
        // deallocation, so dropping the set is the cancel — but leaving the
        // empty entry behind would grow both dictionaries for the lifetime of
        // the settings window.
        for id in registryObservations.keys where !surviving.contains(id) {
            registryObservations.removeValue(forKey: id)
        }
        for id in snapshots.keys where !surviving.contains(id) {
            snapshots.removeValue(forKey: id)
        }

        for project in projects {
            var cancellables: Set<AnyCancellable> = []
            let id = project.id
            let name = project.name
            // `combineLatest` rather than two sinks, because a row needs both
            // halves: the state says what to draw, the configuration list says
            // what to call it. Two independent sinks would each recompute from
            // one fresh value and one stale one — the `willSet` hazard again,
            // one publisher removed.
            project.registry.$sessionStates
                .combineLatest(project.registry.$configurations)
                .sink { [weak self] states, configurations in
                    guard let self else { return }
                    self.snapshots[id] = Snapshot(
                        name: name,
                        states: states,
                        configurations: configurations
                    )
                    self.recomputeRows()
                }
                .store(in: &cancellables)
            registryObservations[id] = cancellables
        }

        hasOpenProject = !projects.isEmpty
        // Called unconditionally. A list that shrank to nothing produces no
        // registry emission at all, and the closed project's rows would
        // otherwise stay on screen.
        recomputeRows()
    }

    /// Rebuilds `rows` from `snapshots` alone.
    ///
    /// One row per *session*: a configuration the registry has no session for —
    /// disabled, or removed — has no `sessionStates` entry and contributes
    /// nothing. The panel is what turns that absence into "Not running";
    /// inventing a row here would mean inventing a state.
    private func recomputeRows() {
        var next: [LanguageServerStatusRow] = []
        for projectID in projectIDs {
            guard let snapshot = snapshots[projectID] else { continue }
            let namesByID = Dictionary(
                snapshot.configurations.map { ($0.id, $0.name) },
                uniquingKeysWith: { first, _ in first }
            )
            for (configurationID, state) in snapshot.states {
                next.append(LanguageServerStatusRow(
                    projectID: projectID,
                    configurationID: configurationID,
                    projectName: snapshot.name,
                    // A session whose configuration has already left the list
                    // is a window of one reconcile. Naming it after its id
                    // would read worse than saying nothing.
                    configurationName: namesByID[configurationID] ?? "",
                    state: state
                ))
            }
        }
        // Sorted by project, then server name, so the list holds still. Rows
        // are built out of dictionaries, whose iteration order is not stable
        // between reads, and a handshake tick is frequent enough that an
        // unsorted list would visibly reshuffle while the user is reading it.
        // The id is the final tiebreak so two servers sharing a name still
        // order deterministically.
        next.sort { lhs, rhs in
            if lhs.projectName != rhs.projectName { return lhs.projectName < rhs.projectName }
            if lhs.configurationName != rhs.configurationName {
                return lhs.configurationName < rhs.configurationName
            }
            return lhs.configurationID.uuidString < rhs.configurationID.uuidString
        }
        // Compared before assigning: `rows` drives a SwiftUI list, and the
        // registries emit on every handshake tick, most of which change nothing
        // this list shows.
        guard next != rows else { return }
        rows = next
    }
}
