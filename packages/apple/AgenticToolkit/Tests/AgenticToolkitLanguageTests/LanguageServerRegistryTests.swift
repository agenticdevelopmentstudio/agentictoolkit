import AgenticToolkitCore
import Foundation
import Testing
@testable import AgenticToolkitLanguage

/// Reconciliation and root-marker resolution, with **no process ever
/// launched**: every registry here is built with `builtInConfigurations: []`
/// and an injected `sessionFactory` that hands back `FakeLanguageServerSession`.
/// That is what the injected factory is for — a registry test that spawned
/// `sourcekit-lsp` would be a language-server test.
@Suite("LanguageServerRegistry")
@MainActor
struct LanguageServerRegistryTests {

    /// Ceiling on any poll here. The registry starts and stops sessions from
    /// unstructured `Task`s, so those effects land after the synchronous
    /// reconcile has already returned.
    private static let pollSeconds: TimeInterval = 5

    // MARK: - Doubles

    /// What the fakes did. Lock-guarded rather than isolated: `start()` and
    /// `stop()` run on each session's own actor, off the main one, and the
    /// assertions read from the main one.
    private final class SessionLog: @unchecked Sendable {
        private let lock = NSLock()
        private var startedIDs: [UUID] = []
        private var stoppedIDs: [UUID] = []

        func recordStart(_ id: UUID) {
            lock.lock()
            defer { lock.unlock() }
            startedIDs.append(id)
        }

        func recordStop(_ id: UUID) {
            lock.lock()
            defer { lock.unlock() }
            stoppedIDs.append(id)
        }

        var started: [UUID] {
            lock.lock()
            defer { lock.unlock() }
            return startedIDs
        }

        var stopped: [UUID] {
            lock.lock()
            defer { lock.unlock() }
            return stoppedIDs
        }
    }

    /// Conforms to the protocol the registry consumes and does nothing else.
    /// It keeps the command, environment and root it was built with, so a test
    /// can prove a *replacement* happened rather than a reuse.
    private actor FakeLanguageServerSession: LanguageServerSessionProtocol {
        nonisolated let id: UUID
        nonisolated let name: String
        nonisolated let languageIds: [String]
        nonisolated let command: String
        nonisolated let rootURL: URL
        nonisolated let environment: [String: String]

        private(set) var state: LanguageServerSessionState = .idle
        private let log: SessionLog

        init(
            configuration: LanguageServerConfiguration,
            environment: [String: String],
            rootURL: URL,
            log: SessionLog
        ) {
            self.id = configuration.id
            self.name = configuration.name
            self.languageIds = configuration.languageIds
            self.command = configuration.command
            self.rootURL = rootURL
            self.environment = environment
            self.log = log
        }

        func start() async throws {
            state = .running
            log.recordStart(id)
        }

        func stop() async {
            state = .stopped
            log.recordStop(id)
        }
    }

    // MARK: - Fixtures

    private func makeStore() -> SettingsStore {
        SettingsStore(
            with: InMemorySettingsStorageProvider(),
            secureSettingsProvider: InMemorySecureSettingsStorageProvider()
        )
    }

    private func makeRegistry(
        store: SettingsStore,
        log: SessionLog,
        workspaceURL: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    ) -> LanguageServerRegistry {
        LanguageServerRegistry(
            store: store,
            workspaceURL: workspaceURL,
            // No built-ins: this suite is about the reconcile rule, and the
            // built-in SourceKit-LSP entry would put a second session into
            // every assertion.
            builtInConfigurations: [],
            sessionFactory: { configuration, secrets, rootURL in
                FakeLanguageServerSession(
                    configuration: configuration,
                    environment: configuration.environment.merging(secrets) { _, secret in secret },
                    rootURL: rootURL,
                    log: log
                )
            }
        )
    }

    private func makeConfiguration(
        languageIds: [String] = ["swift"],
        command: String = "/nonexistent/first-server",
        isEnabled: Bool = true
    ) -> LanguageServerConfiguration {
        LanguageServerConfiguration(
            name: "Fake",
            languageIds: languageIds,
            command: command,
            rootMarkers: [".git"],
            isEnabled: isEnabled
        )
    }

    private func poll(
        seconds: TimeInterval = LanguageServerRegistryTests.pollSeconds,
        until condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    /// A unique directory that exists only for the duration of `body`.
    /// Scoped rather than owned by a fixture object, so its lifetime is the
    /// test's and not ARC's.
    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("LSPRegistryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        try body(url)
    }

    private func identical(
        _ lhs: (any LanguageServerSessionProtocol)?,
        _ rhs: (any LanguageServerSessionProtocol)?
    ) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }

    // MARK: - 5. Registry reconcile

    /// What it catches: a registry that publishes configurations but builds
    /// nothing from them, a factory that is called but whose session is never
    /// started, and a language lookup that is case-sensitive (LSP ids are
    /// conventionally lowercase; a hand-edited settings file need not be).
    @Test("adding an enabled configuration creates and starts one session")
    func addingAConfigurationCreatesASession() async {
        let store = makeStore()
        let log = SessionLog()
        let registry = makeRegistry(store: store, log: log)
        #expect(registry.sessions.isEmpty)

        let configuration = makeConfiguration()
        store.set([configuration], for: UserSettings.languageServerConfigurations)

        #expect(registry.sessions.count == 1)
        #expect(registry.session(for: configuration.id) != nil)
        #expect(registry.session(forLanguageId: "Swift") != nil)

        let started = await poll { log.started == [configuration.id] }
        #expect(started)
    }

    /// What it catches: a registry that drops a session from its dictionary
    /// without stopping it. The child process would then outlive every
    /// reference to it — the leak `MCPClient` was reshaped to avoid.
    @Test("disabling a configuration tears its session down")
    func disablingAConfigurationStopsItsSession() async {
        let store = makeStore()
        let log = SessionLog()
        let registry = makeRegistry(store: store, log: log)

        var configuration = makeConfiguration()
        store.set([configuration], for: UserSettings.languageServerConfigurations)
        #expect(registry.sessions.count == 1)

        configuration.isEnabled = false
        store.set([configuration], for: UserSettings.languageServerConfigurations)

        #expect(registry.sessions.isEmpty)
        #expect(registry.session(forLanguageId: "swift") == nil)

        let stopped = await poll { log.stopped == [configuration.id] }
        #expect(stopped)
    }

    /// The one place this registry deliberately differs from
    /// `MCPServerRegistry`, which creates a client only when the id is absent
    /// and so leaves an edited server running on its old command.
    ///
    /// What it catches: exactly that — a reconcile keyed on the id alone. The
    /// id is unchanged here, so an id-keyed reconcile is a no-op and the old
    /// session survives with the old command. "My settings do nothing" is the
    /// shape that reaches the user.
    @Test("changing a configuration's command replaces the running session")
    func changingACommandReplacesTheSession() async {
        let store = makeStore()
        let log = SessionLog()
        let registry = makeRegistry(store: store, log: log)

        var configuration = makeConfiguration()
        store.set([configuration], for: UserSettings.languageServerConfigurations)
        let first = registry.session(for: configuration.id)
        #expect(first != nil)

        configuration.command = "/nonexistent/second-server"
        store.set([configuration], for: UserSettings.languageServerConfigurations)

        let second = registry.session(for: configuration.id)
        #expect(second != nil)
        #expect(!identical(first, second))
        #expect((second as? FakeLanguageServerSession)?.command == "/nonexistent/second-server")

        let stopped = await poll { log.stopped == [configuration.id] }
        #expect(stopped)
        let restarted = await poll { log.started.count == 2 }
        #expect(restarted)
    }

    /// What it catches: a reconcile that replaces on every settings emission.
    /// Every language server would then restart whenever any unrelated
    /// setting changed — here, a secret belonging to a different server.
    @Test("an unrelated settings change reconciles without replacing the session")
    func unrelatedSettingsChangeKeepsTheSession() {
        let store = makeStore()
        let log = SessionLog()
        let registry = makeRegistry(store: store, log: log)

        let configuration = makeConfiguration()
        store.set([configuration], for: UserSettings.languageServerConfigurations)
        let first = registry.session(for: configuration.id)

        let strangerSecrets: LanguageServerSecrets = [UUID().uuidString: ["TOKEN": "not-ours"]]
        store.set(strangerSecrets, for: UserSettings.languageServerSecrets)

        #expect(identical(first, registry.session(for: configuration.id)))
        #expect(log.stopped.isEmpty)
    }

    /// What it catches: secrets that are read but never reach the session, and
    /// secrets that fail to trigger a replacement when they change — a rotated
    /// token would then be ignored until the next relaunch.
    @Test("a secret change replaces the session and reaches its environment")
    func secretsReachTheSessionAndTriggerAReplacement() {
        let store = makeStore()
        let log = SessionLog()
        let registry = makeRegistry(store: store, log: log)

        let configuration = makeConfiguration()
        store.set([configuration], for: UserSettings.languageServerConfigurations)
        let first = registry.session(for: configuration.id)

        let secrets: LanguageServerSecrets = [configuration.id.uuidString: ["TOKEN": "s3cret"]]
        store.set(secrets, for: UserSettings.languageServerSecrets)

        let second = registry.session(for: configuration.id)
        #expect(!identical(first, second))
        #expect((second as? FakeLanguageServerSession)?.environment["TOKEN"] == "s3cret")
    }

    /// What it catches: an override rule that merges instead of replacing. A
    /// user who overrides Swift would keep getting the built-in's arguments,
    /// and a built-in that survived alongside its override would also win
    /// `session(forLanguageId:)`, since it comes first in the list.
    @Test("a user configuration replaces the built-in that claims the same language")
    func userConfigurationReplacesTheBuiltIn() {
        let builtIn = makeConfiguration(languageIds: ["swift", "c"], command: "/built-in")
        let user = makeConfiguration(languageIds: ["swift"], command: "/user")

        let effective = LanguageServerRegistry.effectiveConfigurations(builtIn: [builtIn], user: [user])

        #expect(effective.map(\.command) == ["/user"])
    }

    /// What it catches: an override rule keyed on the configuration id rather
    /// than on the language, which would leave both entries in force and make
    /// which server answers depend on list order.
    @Test("a built-in survives a user configuration for an unrelated language")
    func unrelatedUserConfigurationLeavesTheBuiltInAlone() {
        let builtIn = makeConfiguration(languageIds: ["swift"], command: "/built-in")
        let user = makeConfiguration(languageIds: ["python"], command: "/user")

        let effective = LanguageServerRegistry.effectiveConfigurations(builtIn: [builtIn], user: [user])

        #expect(effective.map(\.command) == ["/built-in", "/user"])
    }

    /// What it catches: an app-level teardown that empties the dictionary
    /// without stopping what was in it.
    @Test("shutdown stops every session and empties the registry")
    func shutdownStopsEverySession() async {
        let store = makeStore()
        let log = SessionLog()
        let registry = makeRegistry(store: store, log: log)

        let swiftServer = makeConfiguration(languageIds: ["swift"], command: "/nonexistent/swift")
        let pythonServer = makeConfiguration(languageIds: ["python"], command: "/nonexistent/python")
        store.set([swiftServer, pythonServer], for: UserSettings.languageServerConfigurations)
        #expect(registry.sessions.count == 2)

        await registry.shutdown()

        #expect(registry.sessions.isEmpty)
        #expect(Set(log.stopped) == Set([swiftServer.id, pythonServer.id]))
    }

    // MARK: - 6. Root-marker resolution

    /// What it catches: a walk that starts at the file rather than its
    /// directory, one that never climbs, and one that returns the *outermost*
    /// match. Two servers rooted at different directories for the same file
    /// index different things and answer differently.
    @Test("the walk climbs from a file to the nearest directory holding a marker")
    func rootMarkerWalkFindsTheNearestMarker() throws {
        try withTemporaryDirectory { fixture in
            let outer = fixture.appendingPathComponent("outer", isDirectory: true)
            let inner = outer.appendingPathComponent("inner", isDirectory: true)
            let sources = inner.appendingPathComponent("Sources", isDirectory: true)
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            try Data().write(to: outer.appendingPathComponent("Package.swift"))
            try Data().write(to: inner.appendingPathComponent("Package.swift"))
            let file = sources.appendingPathComponent("Thing.swift")
            try Data().write(to: file)

            let root = LanguageServerRegistry.workspaceRoot(startingAt: file, markers: ["Package.swift"])

            #expect(root?.standardizedFileURL == inner.standardizedFileURL)
        }
    }

    /// What it catches: a marker matcher that only does exact names. An Xcode
    /// project root is identified by a bundle whose name nobody can predict,
    /// so `*.xcodeproj` has to work or Xcode projects get rooted at `.git` —
    /// or nowhere.
    @Test("a *.ext marker matches by suffix")
    func rootMarkerWalkSupportsGlobSuffixes() throws {
        try withTemporaryDirectory { fixture in
            let project = fixture.appendingPathComponent("Whippet.xcodeproj", isDirectory: true)
            let sources = fixture.appendingPathComponent("Sources", isDirectory: true)
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            let file = sources.appendingPathComponent("Thing.swift")
            try Data().write(to: file)

            let root = LanguageServerRegistry.workspaceRoot(startingAt: file, markers: ["*.xcodeproj"])

            #expect(root?.standardizedFileURL == fixture.standardizedFileURL)
        }
    }

    /// The no-marker-found case. `nil` is not an error — it means "fall back
    /// to the directory you already call the workspace" — but it does have to
    /// terminate.
    ///
    /// What it catches: the walk's only exit condition. `/` is its own parent,
    /// so a loop that climbs without comparing against the previous path spins
    /// forever, and this test times out rather than passing.
    @Test("a marker that exists nowhere resolves to nil rather than looping")
    func rootMarkerWalkReturnsNilWhenNothingMatches() throws {
        try withTemporaryDirectory { fixture in
            let file = fixture.appendingPathComponent("Thing.swift")
            try Data().write(to: file)

            let missing = LanguageServerRegistry.workspaceRoot(
                startingAt: file,
                markers: ["__whippet-no-such-root-marker__"]
            )

            #expect(missing == nil)
            // An empty marker list is the same answer, reached without
            // touching the filesystem at all.
            #expect(LanguageServerRegistry.workspaceRoot(startingAt: file, markers: []) == nil)
        }
    }

    /// What it catches: a reconcile that ignores root markers and roots every
    /// session at the workspace directory — which is what makes a server index
    /// a subdirectory of a package instead of the package.
    @Test("reconcile roots a session at the marker directory, not the workspace directory")
    func reconcileResolvesTheRootFromMarkers() throws {
        try withTemporaryDirectory { fixture in
            let repository = fixture.appendingPathComponent("Repo", isDirectory: true)
            let workspace = repository.appendingPathComponent("Sources/Feature", isDirectory: true)
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: repository.appendingPathComponent(".git", isDirectory: true),
                withIntermediateDirectories: true
            )

            let store = makeStore()
            let log = SessionLog()
            let registry = makeRegistry(store: store, log: log, workspaceURL: workspace)
            let configuration = makeConfiguration()
            store.set([configuration], for: UserSettings.languageServerConfigurations)

            let session = registry.session(for: configuration.id) as? FakeLanguageServerSession
            #expect(session?.rootURL.standardizedFileURL == repository.standardizedFileURL)
        }
    }
}
