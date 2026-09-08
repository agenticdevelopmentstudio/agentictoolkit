//
//  LanguageServerRegistry.swift
//  AgenticToolkit
//

import AgenticToolkitCore
import Combine
import Foundation
import OSLog

/// Reconciles a set of live language-server sessions against the configurations
/// stored in `SettingsStore`, and answers the one question every consumer asks:
/// which server serves this language, rooted where.
///
/// Hosts (the file editor, a settings panel) observe the registry; the registry
/// owns the lifecycle of each session. This mirrors `MCPServerRegistry`
/// structurally — `@MainActor`, `ObservableObject`, a `@Published` dictionary
/// keyed by configuration id, an injected factory with a production default,
/// and a Combine `combineLatest` of the two settings publishers driving
/// `reconcile`.
///
/// It differs from `MCPServerRegistry` in one deliberate way: that registry
/// creates a client only when there is no entry for the id, so editing a
/// server's command leaves the old client running. This one records what
/// produced each session and **replaces** a session whose configuration,
/// secrets, or resolved root have changed. Editing a command that does not
/// restart the server is the shape of bug that reads as "my settings do
/// nothing".
///
/// Tests inject a `sessionFactory` (and usually `builtInConfigurations: []`) to
/// avoid spawning real language servers.
@MainActor
public final class LanguageServerRegistry: ObservableObject {

    public typealias SessionFactory = @MainActor (
        _ configuration: LanguageServerConfiguration,
        _ secrets: [String: String],
        _ rootURL: URL
    ) -> any LanguageServerSessionProtocol

    /// Live sessions keyed by configuration id. Only enabled configurations
    /// have an entry.
    @Published public private(set) var sessions: [UUID: any LanguageServerSessionProtocol] = [:]

    /// The configurations currently in force: the built-ins, minus any the user
    /// has overridden, plus the user's own. Republished on every reconcile so a
    /// settings UI can list exactly what is running.
    @Published public private(set) var configurations: [LanguageServerConfiguration] = []

    /// Each live session's last reported state, keyed by configuration id.
    ///
    /// This is the answer to "is that server actually running?", and before it
    /// existed nobody could ask: a session whose `start()` threw stays in
    /// `sessions` looking exactly like one that started, and `$sessions` never
    /// emits again — the failure lived only in the log.
    ///
    /// **A second published map rather than richer values in `sessions`.**
    /// `sessions` is the *identity* map every consumer looks a session up in —
    /// `LanguageServerDocumentSync`, `DiagnosticStore`, the completion and
    /// definition delegates all subscribe to it to learn which object serves a
    /// language. Putting mutable state in it would republish every one of those
    /// subscriptions on every handshake tick, for a change none of them care
    /// about. The two questions are genuinely different: `sessions` answers
    /// *which* session, this answers *whether it can answer yet*
    /// (`separation-of-concerns`).
    ///
    /// An entry is added when the session is created and removed by whoever
    /// removes the session — never by the session's stream ending. A stream
    /// that finished while its session was still in `sessions` would simply
    /// stop updating, which is the honest behaviour; it cannot happen today,
    /// because `stop()` is the only finisher and this registry removes a
    /// session before it stops it.
    @Published public private(set) var sessionStates: [UUID: LanguageServerSessionState] = [:]

    /// The directory sessions are rooted at when a configuration's root markers
    /// find nothing above it — normally the open project directory.
    public let workspaceURL: URL

    private let store: SettingsStore
    private let builtInConfigurations: [LanguageServerConfiguration]
    private let sessionFactory: SessionFactory
    private let fileManager: FileManager
    private var descriptors: [UUID: SessionDescriptor] = [:]

    /// One `stateChanges` reader per live session, keyed by configuration id —
    /// the same key `sessions` uses, because these are created and retired in
    /// lockstep with it.
    private var stateObservations: [UUID: Task<Void, Never>] = [:]

    private var cancellables: Set<AnyCancellable> = []

    public init(
        store: SettingsStore,
        workspaceURL: URL,
        builtInConfigurations: [LanguageServerConfiguration] = LanguageServerRegistry.builtInConfigurations,
        fileManager: FileManager = .default,
        sessionFactory: @escaping SessionFactory = { configuration, secrets, rootURL in
            LanguageServerSession(configuration: .init(
                id: configuration.id,
                name: configuration.name,
                languageIds: configuration.languageIds,
                executableURL: URL(fileURLWithPath: configuration.command),
                arguments: configuration.arguments,
                environment: configuration.environment.merging(secrets) { _, secret in secret },
                rootURL: rootURL
            ))
        }
    ) {
        self.store = store
        self.workspaceURL = workspaceURL
        self.builtInConfigurations = builtInConfigurations
        self.fileManager = fileManager
        self.sessionFactory = sessionFactory

        store.publisher(for: UserSettings.languageServerConfigurations)
            .combineLatest(store.publisher(for: UserSettings.languageServerSecrets))
            .sink { [weak self] configurations, secrets in
                guard let self else { return }
                self.reconcile(userConfigurations: configurations, secrets: secrets)
            }
            .store(in: &cancellables)
    }

    // MARK: - Lookup

    public func session(for id: UUID) -> (any LanguageServerSessionProtocol)? {
        sessions[id]
    }

    /// The session serving `languageId`, or `nil` if no enabled configuration
    /// claims it. Language ids are matched case-insensitively because LSP ids
    /// are conventionally lowercase but a hand-edited settings file need not be.
    public func session(forLanguageId languageId: String) -> (any LanguageServerSessionProtocol)? {
        guard let configuration = configuration(forLanguageId: languageId) else { return nil }
        return sessions[configuration.id]
    }

    /// The enabled configuration claiming `languageId`. When more than one does
    /// — which the merge rule makes possible only among the user's own entries —
    /// the first in configuration order wins, so the list is the tiebreak the
    /// user can see and reorder.
    public func configuration(forLanguageId languageId: String) -> LanguageServerConfiguration? {
        let wanted = languageId.lowercased()
        return configurations.first { configuration in
            configuration.isEnabled && configuration.languageIds.contains { $0.lowercased() == wanted }
        }
    }

    // MARK: - Built-ins and the override rule

    /// The servers shipped with the toolkit.
    ///
    /// `sourcekit-lsp` is at an absolute path rather than a bare name because
    /// the app's `PATH` when launched from Finder is not the user's shell
    /// `PATH`, and a bare name would resolve in a terminal build and not in the
    /// shipped app.
    public static let builtInConfigurations: [LanguageServerConfiguration] = [
        LanguageServerConfiguration(
            // A stable id, not a fresh `UUID()`: it is the key secrets are
            // stored under and the key `sessions` is keyed by, so it has to
            // survive a relaunch.
            id: UUID(uuidString: "1CE31A0E-0000-4000-A000-5357494654FF") ?? UUID(),
            name: "SourceKit-LSP",
            languageIds: ["swift", "objective-c", "objective-cpp", "c", "cpp"],
            command: "/usr/bin/sourcekit-lsp",
            arguments: [],
            environment: [:],
            rootMarkers: ["Package.swift", "*.xcodeproj", "*.xcworkspace", ".git"]
        )
    ]

    /// The configurations in force: every user configuration, plus each
    /// built-in that no user configuration has taken over.
    ///
    /// **A user configuration for a languageId replaces the built-in for that
    /// languageId; it does not merge with it.** A built-in is dropped as soon
    /// as any user configuration claims *any* of its language ids. Merging
    /// field-by-field would mean a user who removes an argument still gets it,
    /// and a user who cannot express "not that one" cannot fix a broken
    /// built-in — which is exactly what an override is for. The cost is that
    /// overriding Swift with a user entry that also claims C removes the
    /// built-in's C support too; that is visible in the settings list, and the
    /// alternative is a partial identity nobody can reason about.
    public static func effectiveConfigurations(
        builtIn: [LanguageServerConfiguration],
        user: [LanguageServerConfiguration]
    ) -> [LanguageServerConfiguration] {
        let overridden = Set(user.flatMap { $0.languageIds.map { $0.lowercased() } })
        let survivors = builtIn.filter { configuration in
            !configuration.languageIds.contains { overridden.contains($0.lowercased()) }
        }
        return survivors + user
    }

    // MARK: - Root markers

    /// Walks up from `startingURL` looking for the first directory containing
    /// any of `markers`, and returns it.
    ///
    /// This is the **only** implementation of the root-marker walk. A second one
    /// would inevitably disagree about a case (a bare name versus a glob, a file
    /// start versus a directory start) and two servers rooted at different
    /// directories for the same file index different things and answer
    /// differently.
    ///
    /// A marker may be a plain name (`"Package.swift"`, `".git"`) or a `*.ext`
    /// suffix pattern (`"*.xcodeproj"`) — the latter because an Xcode project
    /// root is identified by a file whose name nobody can predict. Markers are
    /// tried in order at each level, and levels are tried innermost-first, so
    /// the *nearest* root wins over the most specific marker.
    ///
    /// Returns `nil` when no marker is found anywhere up to the filesystem root.
    /// That is not an error: it means the caller should fall back to whatever
    /// directory it already considers the workspace.
    public static func workspaceRoot(
        startingAt startingURL: URL,
        markers: [String],
        fileManager: FileManager = .default
    ) -> URL? {
        guard !markers.isEmpty else { return nil }

        var directory = startingURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            directory = directory.deletingLastPathComponent()
        }

        while true {
            if directoryContainsMarker(directory, markers: markers, fileManager: fileManager) {
                return directory
            }
            let parent = directory.deletingLastPathComponent().standardizedFileURL
            // `deletingLastPathComponent()` on "/" yields "/" again, so this is
            // the loop's only exit for a path with no marker anywhere.
            guard parent.path != directory.path else { return nil }
            directory = parent
        }
    }

    private static func directoryContainsMarker(
        _ directory: URL,
        markers: [String],
        fileManager: FileManager
    ) -> Bool {
        var contents: [String]?
        for marker in markers {
            if let suffix = globSuffix(of: marker) {
                // Listing is only paid for when a glob marker is present, and
                // then only once per directory.
                if contents == nil {
                    contents = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
                }
                if contents?.contains(where: { $0.hasSuffix(suffix) }) == true { return true }
            } else {
                let candidate = directory.appendingPathComponent(marker).path
                if fileManager.fileExists(atPath: candidate) { return true }
            }
        }
        return false
    }

    /// `"*.xcodeproj"` -> `".xcodeproj"`; anything else -> `nil`.
    private static func globSuffix(of marker: String) -> String? {
        guard marker.hasPrefix("*"), marker.count > 1 else { return nil }
        return String(marker.dropFirst())
    }

    // MARK: - Reconcile

    /// Stops every session and clears the registry. The one place an app-level
    /// teardown should call.
    ///
    /// Sessions are stopped **concurrently**. `SubprocessChannel.terminate()`
    /// costs up to 2.5 s flat per channel, is not cancellable, and the budgets
    /// do not share, so a `for` loop over five servers is a twelve-second quit.
    public func shutdown() async {
        let running = Array(sessions.values)
        sessions = [:]
        descriptors = [:]
        for observation in stateObservations.values {
            observation.cancel()
        }
        stateObservations = [:]
        sessionStates = [:]
        await Self.stopAll(running)
    }

    /// How many sessions are having their state read right now.
    ///
    /// Internal, for tests. Cancelling an observation has no other externally
    /// visible consequence — a cancelled reader simply stops writing — so
    /// without this the difference between "cancelled" and "leaked and parked
    /// forever" is not assertable.
    var stateObservationCount: Int { stateObservations.count }

    private func reconcile(
        userConfigurations: [LanguageServerConfiguration],
        secrets: LanguageServerSecrets
    ) {
        let effective = Self.effectiveConfigurations(builtIn: builtInConfigurations, user: userConfigurations)
        configurations = effective

        let enabled = effective.filter(\.isEnabled)
        let desired: [UUID: SessionDescriptor] = enabled.reduce(into: [:]) { result, configuration in
            let serverSecrets = secrets[configuration.id.uuidString] ?? [:]
            let root = Self.workspaceRoot(
                startingAt: workspaceURL,
                markers: configuration.rootMarkers,
                fileManager: fileManager
            ) ?? workspaceURL
            result[configuration.id] = SessionDescriptor(
                configuration: configuration,
                secrets: serverSecrets,
                rootURL: root
            )
        }

        // Removed outright, or superseded by a changed descriptor. Both are
        // collected first so the stop happens once, concurrently, below.
        var retired: [any LanguageServerSessionProtocol] = []
        for (id, session) in sessions where desired[id] != descriptors[id] {
            retired.append(session)
            sessions.removeValue(forKey: id)
            descriptors.removeValue(forKey: id)
            sessionStates.removeValue(forKey: id)
            stateObservations.removeValue(forKey: id)?.cancel()
        }
        if !retired.isEmpty {
            Task { await Self.stopAll(retired) }
        }

        for (id, descriptor) in desired where sessions[id] == nil {
            let session = sessionFactory(descriptor.configuration, descriptor.secrets, descriptor.rootURL)
            sessions[id] = session
            descriptors[id] = descriptor
            // Seeded synchronously, here, and before the start below. A
            // `sessions` entry with no `sessionStates` entry is a window in
            // which a panel has to invent an answer for a server it can see;
            // `.idle` is the session's real state at this instant, and the
            // session itself does not publish it (nobody is listening yet when
            // its initialiser runs).
            sessionStates[id] = .idle
            observeState(of: session, id: id)
            let name = descriptor.configuration.name
            Task {
                do {
                    try await session.start()
                } catch {
                    let message = error.localizedDescription
                    Self.logger.error(
                        "Failed to start language server \(name, privacy: .public): \(message, privacy: .public)"
                    )
                }
            }
        }
    }

    /// Reads one session's transitions into `sessionStates` until the session's
    /// stream finishes or the observation is cancelled.
    ///
    /// `Task {}` inside a `@MainActor` method inherits main-actor isolation, so
    /// the identity check and the write below are one synchronous step with no
    /// window between them — the same argument `DiagnosticStore.observe(_:)`
    /// makes about `apply(_:)`.
    ///
    /// **The identity check is the whole point, and it is re-evaluated after
    /// every suspension rather than once at subscribe time.** `reconcile`
    /// retires superseded sessions and then installs their replacements under
    /// the *same* configuration id, while the outgoing session is still
    /// draining in `stopAll`'s detached task. A retired session's reader can
    /// therefore be resumed with a value it was handed before it was cancelled,
    /// and an unguarded write would put that session's `.stopped` on top of its
    /// replacement's state — a panel showing a stopped server that is in fact
    /// running, with no further emission to correct it.
    ///
    /// The invariant that makes it sound: **nothing is read before an await and
    /// used after it.** `id` and `session` are constants captured at creation,
    /// `state` is delivered by the await itself, and `sessions[id]` is read
    /// fresh on every iteration.
    ///
    /// `[weak self]` so an abandoned registry — one released without
    /// `shutdown()` — is not kept alive by a task parked on a live server's
    /// stream.
    ///
    /// **At most one live observation per id, and a second call is refused.**
    /// `stateChanges` is single-consumer exactly as `publishedDiagnostics` is:
    /// two `for await` loops over one `AsyncStream` split its values between
    /// them rather than each seeing all of them, and the second `Task {}` would
    /// overwrite the first's handle and leave a writer nothing holds. This is
    /// the guard `DiagnosticStore.observe(_:)` makes, for the same reason.
    ///
    /// Refused rather than cancel-and-replace, because `reconcile` is the sole
    /// owner of an id's lifetime. Its retire loop drops `sessions`,
    /// `descriptors`, `sessionStates` and this entry together and cancels the
    /// observation in the same statement, all of it *before* the create loop
    /// installs a replacement under the same `UUID` — so the slot is already
    /// empty and this guard can never block that replacement. Cancel-and-replace
    /// would instead make a caller that swaps the observation without going
    /// through that loop look supported, when it is not: `sessions[id]` would
    /// still hold the outgoing session, the identity check below would fail on
    /// the replacement's very first value, and a working reader would have been
    /// cancelled to install one that dies immediately.
    ///
    /// **This all rests on a precondition this method does not check: `id` is
    /// never passed unless it is already a key in `sessions`.** The refusal
    /// above keys on `id` alone, while the retire loop this paragraph leans on
    /// keys on `sessions`; the two agree only because the sole call site sits a
    /// few statements after `sessions[id] = session`, in the same iteration of
    /// `reconcile`'s create loop. If that ever stopped holding — a caller
    /// passing an `id` `sessions` does not have — the refusal above would
    /// install an entry for it that nothing but `shutdown()` ever removes,
    /// permanently refusing every later legitimate call for that `id` and
    /// freezing `sessionStates[id]` at whatever it last was. Documented rather
    /// than guarded: a check nothing can reach is a branch that will never be
    /// exercised and will be trusted anyway.
    ///
    /// Internal rather than private, and returning whether it installed a
    /// reader, because that return value is the only thing a second call
    /// changes *for the caller*. It is not the only observable effect of a
    /// second call: the guard below also logs a fault, so a second call is
    /// visible in the log even though its `Bool` is easy to discard.
    /// A second reader is invisible from outside for a different reason — the
    /// entry is keyed by id, so overwriting it leaves the count at one, and the
    /// identity check below means both readers write the same key with the
    /// same values. That invisibility is the finding the fault log exists to
    /// surface — the next caller's return value goes unchecked, but the log
    /// does not.
    ///
    /// - Returns: `false` when `id` already has a live observation, which the
    ///   only call site — `reconcile`'s create loop, gated
    ///   `where sessions[id] == nil` — cannot produce.
    @discardableResult
    func observeState(of session: any LanguageServerSessionProtocol, id: UUID) -> Bool {
        guard stateObservations[id] == nil else {
            Self.logger.fault(
                "Refused a second state observation for language server \(id, privacy: .public)"
            )
            return false
        }
        stateObservations[id] = Task { [weak self] in
            for await state in session.stateChanges {
                guard let self else { return }
                guard self.sessions[id] === session else { return }
                self.sessionStates[id] = state
            }
        }
        return true
    }

    /// The `withTaskGroup` every multi-session teardown must go through.
    private static func stopAll(_ sessions: [any LanguageServerSessionProtocol]) async {
        await withTaskGroup(of: Void.self) { group in
            for session in sessions {
                group.addTask { await session.stop() }
            }
        }
    }

    /// What produced a session. A session is replaced when this changes, which
    /// is what makes editing a command restart the server.
    private struct SessionDescriptor: Equatable {
        let configuration: LanguageServerConfiguration
        let secrets: [String: String]
        let rootURL: URL
    }
}

extension LanguageServerRegistry: Loggable {
    public static nonisolated let logger = makeLogger()
}
