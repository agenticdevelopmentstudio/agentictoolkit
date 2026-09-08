import AgenticToolkitCore
import Combine
import Foundation
import LanguageServerProtocol
import Testing
@testable import AgenticToolkitLanguage

/// Reconciliation and root-marker resolution. Every registry here is built
/// with `builtInConfigurations: []` and, with one deliberate exception, an
/// injected `sessionFactory` that hands back `FakeLanguageServerSession`. That
/// is what the injected factory is for — a registry test that spawned
/// `sourcekit-lsp` would be a language-server test.
///
/// The exception is section 7, which is about the *default* factory and so
/// cannot inject one. It launches a `/bin/sh` scripted server — the same kind
/// of double `LanguageServerSessionTests` uses — never a real language
/// server.
@Suite("LanguageServerRegistry")
@MainActor
struct LanguageServerRegistryTests {

    /// Ceiling on any poll here. The registry starts and stops sessions from
    /// unstructured `Task`s, so those effects land after the synchronous
    /// reconcile has already returned.
    private static let pollSeconds: TimeInterval = 5

    // MARK: - Doubles

    // `SessionLog` and `FakeLanguageServerSession` moved to
    // `FakeLanguageServerSession.swift` when Task 3.2 needed them too.
    // There is one fake for this protocol in this bundle, on purpose: a
    // second one would be free to disagree about the lifecycle — whether a
    // second `start()` is a no-op, most of all — and two doubles that
    // disagree about the thing under test are worse than none.

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
        workspaceURL: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
        // Applied to every fake the factory hands back, because the reconcile
        // rule is not selective and neither is this. Section 8's tests set
        // `holdsStart` so a session parks at `.idle` and stays there for as
        // long as the assertions need it to.
        behavior: FakeSessionBehavior = FakeSessionBehavior()
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
                    log: log,
                    behavior: behavior
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

    /// The same ceiling, for a condition that has to cross an actor boundary.
    /// Section 7's session is a real `LanguageServerSession`, so reading its
    /// state is an `await` and the synchronous `poll` above cannot express it.
    private func pollAsync(
        seconds: TimeInterval = LanguageServerRegistryTests.pollSeconds,
        until condition: () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return await condition()
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

    // MARK: - 7. The production session factory

    /// The one server this suite actually launches, and only because the
    /// factory under test is the one that builds real sessions.
    ///
    /// It reports the two environment variables it was given before doing
    /// anything else, answers `initialize` from the first header line — enough
    /// to know `JSONRPCSession` has registered the responder for id 1 — and
    /// then copies the rest of what the client wrote to **stderr** rather than
    /// discarding it. That copy is the initialize *body*, which is where
    /// `rootUri` is. Between them, stderr carries the evidence for three of the
    /// factory's mappings; reaching `.running` at all is the evidence for the
    /// other two.
    private static let productionFactoryProbeScript = #"""
    printf 'ENV %s %s\n' "$LSP_TEST_PLAIN" "$LSP_TEST_OVERRIDDEN" >&2
    CAPS='{"hoverProvider":true}'
    BODY='{"jsonrpc":"2.0","id":1,"result":{"capabilities":'"$CAPS"'}}'
    IFS= read -r HEADER_LINE
    printf 'Content-Length: %s\r\n\r\n%s' "${#BODY}" "$BODY"
    cat >&2
    """#

    /// `LanguageServerRegistry.init`'s **default** `sessionFactory` — the one
    /// the app uses and the only code path in this file that no other test
    /// covers, because every other test replaces it.
    ///
    /// The registry is constructed without a `sessionFactory:` argument on
    /// purpose. Passing one, even a faithful copy, would test the copy.
    ///
    /// What it catches: every mapping the closure performs, each of which is
    /// silent when wrong. A `command` not carried into `executableURL` gives a
    /// session that never starts; `arguments` dropped turns `/bin/sh -c script`
    /// into an interactive shell that answers nothing; the environment merged
    /// the other way round makes a secret lose to the placeholder a settings
    /// file holds, which is how a token-authenticated server fails to
    /// authenticate with the settings UI showing the right value; a `rootURL`
    /// not forwarded roots every server at whatever the session defaults to,
    /// so cross-file navigation silently resolves nothing; and an `id` not
    /// carried through makes `session(for:)` miss.
    ///
    /// It also pins that the session the default factory builds is one the
    /// registry can drive: `stopAll` reaches a real `LanguageServerSession`,
    /// not just a fake whose `stop()` is a flag.
    @Test("the default session factory maps a configuration onto a session that starts")
    func defaultSessionFactoryBuildsAWorkingSession() async throws {
        let workspace = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("LSPFactoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let store = makeStore()
        let registry = LanguageServerRegistry(
            store: store,
            workspaceURL: workspace,
            builtInConfigurations: []
        )

        var configuration = LanguageServerConfiguration(
            name: "Scripted",
            languageIds: ["swift"],
            command: "/bin/sh",
            arguments: ["-c", Self.productionFactoryProbeScript],
            environment: [
                "LSP_TEST_PLAIN": "from-configuration",
                // Also present in the secrets below. The registry merges
                // secrets *over* the configuration, so the secret must win.
                "LSP_TEST_OVERRIDDEN": "from-configuration"
            ],
            // Empty, so the resolved root is the workspace itself and the
            // assertion below is about the factory rather than about marker
            // resolution, which section 6 already covers.
            rootMarkers: []
        )
        configuration.isEnabled = true

        // Secrets first: `publisher(for:)` replays its current value, so
        // setting configurations last means the descriptor is complete the
        // first time reconcile builds one, and exactly one session is created.
        store.set(
            [configuration.id.uuidString: ["LSP_TEST_OVERRIDDEN": "from-secrets"]],
            for: UserSettings.languageServerSecrets
        )
        store.set([configuration], for: UserSettings.languageServerConfigurations)

        let session = try #require(registry.session(for: configuration.id))
        #expect(session is LanguageServerSession)

        let running = await pollAsync {
            if case .running = await session.state { return true }
            return false
        }
        #expect(running, "the default factory's session never reached .running")

        // Only the child could have supplied this, so the handshake really
        // completed over the process the factory named.
        let capabilities = await session.capabilities()
        #expect(capabilities?.hoverProvider != nil)

        let wire = await session.standardErrorText()
        // Merge direction: the plain value survives, the secret overrides.
        #expect(wire.contains("ENV from-configuration from-secrets"))
        // The initialize body the child echoed back carries the root the
        // registry resolved and the factory forwarded.
        #expect(wire.contains(#""rootUri""#))
        #expect(wire.contains(workspace.lastPathComponent))

        // And the registry can tear a real session down, not just a fake.
        configuration.isEnabled = false
        store.set([configuration], for: UserSettings.languageServerConfigurations)
        #expect(registry.session(for: configuration.id) == nil)

        let stopped = await pollAsync {
            switch await session.state {
            case .stopped, .failed: return true
            case .idle, .starting, .running: return false
            }
        }
        #expect(stopped, "the retired session was never stopped")
    }

    // MARK: - 8. Session state aggregation

    /// The state the registry currently reports for `id`, as a word, or
    /// `"none"` when it has no entry at all — so one assertion distinguishes
    /// "not tracked" from "tracked as idle".
    private func stateName(_ registry: LanguageServerRegistry, _ id: UUID) -> String {
        registry.sessionStates[id]?.caseName ?? "none"
    }

    /// The session the registry currently holds for `id`, as the fake it is.
    /// Fetched rather than captured, because a reconcile *replaces* the object
    /// under an unchanged id and a captured reference would silently be the old
    /// one.
    private func fake(_ registry: LanguageServerRegistry, _ id: UUID) -> FakeLanguageServerSession? {
        registry.sessions[id] as? FakeLanguageServerSession
    }

    /// What it catches: an entry created only when the session first publishes.
    /// A session publishes nothing at construction — nobody is listening yet
    /// when its initialiser runs — so a registry that waited for the stream
    /// would leave a window in which `sessions` holds a server that
    /// `sessionStates` has no answer for, and a panel would have to invent one.
    @Test("creating a session seeds sessionStates with .idle")
    func sessionStatesGainsAnIdleEntryWhenASessionIsCreated() {
        let store = makeStore()
        let registry = makeRegistry(
            store: store,
            log: SessionLog(),
            behavior: FakeSessionBehavior(holdsStart: true)
        )

        let configuration = makeConfiguration()
        store.set([configuration], for: UserSettings.languageServerConfigurations)

        // Asserted synchronously, in the same step as the `sessions` entry: the
        // two are written by one reconcile, so there is no tick in which one
        // exists without the other.
        #expect(registry.sessions[configuration.id] != nil)
        #expect(stateName(registry, configuration.id) == "idle")
        #expect(registry.stateObservationCount == 1)
    }

    /// What it catches: an observation that reads the first transition and
    /// stops, and one that reports the case but drops the payload. A failed
    /// row's second line — the reason, and the server's own stderr — is read
    /// off this map and nowhere else.
    @Test("sessionStates follows the session's transitions")
    func sessionStatesFollowsASessionsTransitions() async {
        let store = makeStore()
        let registry = makeRegistry(
            store: store,
            log: SessionLog(),
            behavior: FakeSessionBehavior(holdsStart: true)
        )

        let configuration = makeConfiguration()
        store.set([configuration], for: UserSettings.languageServerConfigurations)
        guard let session = fake(registry, configuration.id) else {
            Issue.record("no session was created")
            return
        }

        await session.transition(to: .starting)
        #expect(await poll { stateName(registry, configuration.id) == "starting" })

        await session.transition(to: .running)
        #expect(await poll { stateName(registry, configuration.id) == "running" })

        await session.transition(to: .failed(LanguageServerFailure(
            error: LanguageServerSessionError.serverExited(status: 9),
            standardErrorText: "boom: no toolchain here"
        )))
        #expect(await poll { stateName(registry, configuration.id) == "failed" })
        #expect(
            registry.sessionStates[configuration.id]?.failure?.standardErrorText
                == "boom: no toolchain here"
        )
    }

    /// What it catches: a retire path that drops the session but keeps the
    /// state, which leaves a disabled server permanently listed as running; and
    /// one that forgets to cancel the reader, which is a task parked on a
    /// retired session's stream — and therefore a strong reference to that
    /// session, and to its child, for the lifetime of the registry.
    @Test("disabling a configuration drops its sessionStates entry and its observation")
    func sessionStatesDropsTheEntryWhenAConfigurationIsDisabled() {
        let store = makeStore()
        let registry = makeRegistry(
            store: store,
            log: SessionLog(),
            behavior: FakeSessionBehavior(holdsStart: true)
        )

        var configuration = makeConfiguration()
        store.set([configuration], for: UserSettings.languageServerConfigurations)
        #expect(stateName(registry, configuration.id) == "idle")
        #expect(registry.stateObservationCount == 1)

        configuration.isEnabled = false
        store.set([configuration], for: UserSettings.languageServerConfigurations)

        #expect(registry.sessionStates.isEmpty)
        #expect(stateName(registry, configuration.id) == "none")
        #expect(registry.stateObservationCount == 0)
    }

    /// ★ Ruling BB, stated as a test.
    ///
    /// A superseded session is retired and its replacement installed under the
    /// *same* configuration id, while the outgoing one is still draining in
    /// `stopAll`'s detached task. So the retired session's reader can be
    /// resumed with a value it was handed *before* it was cancelled — a cancel
    /// cannot take back a value already delivered — and an unguarded write puts
    /// that session's `.stopped` on top of its replacement's state. The panel
    /// then shows a stopped server that is in fact running, permanently,
    /// because nothing emits again to correct it.
    ///
    /// Deterministic by construction, not by scheduling. The yield and the
    /// reconcile happen in **one synchronous main-actor step** with no
    /// suspension between them, which is the only ordering in which the guard
    /// is load-bearing: `yieldState` resumes the parked reader with `.stopped`
    /// before the reconcile cancels it. (A yield issued *after* the cancel is
    /// unobservable — the reader is resumed with `nil` and returns — so a test
    /// written that way would pass against the unguarded code.)
    ///
    /// **Deviation from the brief's wording, deliberate.** The brief says "let
    /// the replacement reach `.starting`". This fake publishes no `.starting` —
    /// its `start()` has no suspension point — and its start is held anyway, so
    /// the replacement's observable state is the `.idle` the reconcile seeded.
    /// That serves the same purpose: it is a state that is not the outgoing
    /// session's `.stopped`, and the final two assertions go further than the
    /// brief asked by driving the replacement's own transition through
    /// afterwards, proving the guard rejects the retired *session* and not the
    /// id.
    @Test("a retired session's late transition cannot overwrite its replacement")
    func aRetiredSessionsLateTransitionCannotOverwriteItsReplacement() async {
        let store = makeStore()
        let registry = makeRegistry(
            store: store,
            log: SessionLog(),
            behavior: FakeSessionBehavior(holdsStart: true)
        )

        var configuration = makeConfiguration()
        store.set([configuration], for: UserSettings.languageServerConfigurations)
        guard let outgoing = fake(registry, configuration.id) else {
            Issue.record("no session was created")
            return
        }

        // Driven somewhere observable and waited for, so the reader is parked
        // in `for await` — not mid-iteration — at the instant the race is set
        // up below.
        await outgoing.transition(to: .running)
        #expect(await poll { stateName(registry, configuration.id) == "running" })

        // The race. No `await` between these two statements.
        outgoing.yieldState(.stopped)
        configuration.command = "/nonexistent/second-server"
        store.set([configuration], for: UserSettings.languageServerConfigurations)

        guard let replacement = fake(registry, configuration.id) else {
            Issue.record("no replacement was created")
            return
        }
        #expect(replacement.instanceID != outgoing.instanceID)
        #expect(stateName(registry, configuration.id) == "idle")

        // Now let the retired reader run. Unguarded, this is where it writes
        // `.stopped` over the seeded `.idle`.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(stateName(registry, configuration.id) == "idle")

        await replacement.transition(to: .running)
        #expect(await poll { stateName(registry, configuration.id) == "running" })
    }

    /// What it catches: a quit path that stops every child but leaves the
    /// readers parked, so the registry cannot be released; and one that leaves
    /// the last known states behind, so a settings panel reopened after a quit
    /// lists servers that no longer exist.
    @Test("shutdown clears sessionStates and cancels every observation")
    func shutdownClearsSessionStatesAndCancelsTheObservations() async {
        let store = makeStore()
        let registry = makeRegistry(
            store: store,
            log: SessionLog(),
            behavior: FakeSessionBehavior(holdsStart: true)
        )

        let first = makeConfiguration(languageIds: ["swift"])
        let second = makeConfiguration(languageIds: ["python"], command: "/nonexistent/second-server")
        store.set([first, second], for: UserSettings.languageServerConfigurations)
        #expect(registry.sessionStates.count == 2)
        #expect(registry.stateObservationCount == 2)

        await registry.shutdown()

        #expect(registry.sessionStates.isEmpty)
        #expect(registry.stateObservationCount == 0)
    }

    /// ★ The gap Ruling AQ named, stated as a test — and the reason a second
    /// published map exists at all.
    ///
    /// A `start()` that throws changes nothing about `sessions`: the object is
    /// still there, still resolvable by language id, and `$sessions` does not
    /// emit again. Every consumer watching only that publisher — which, before
    /// this task, was every consumer there was — has no way to learn the server
    /// is dead. `sessionStates` is where the failure shows up.
    @Test("sessionStates reports a failed start that `sessions` cannot see")
    func sessionStatesReportsAFailedStartThatSessionsCannotSee() async {
        let store = makeStore()
        let registry = makeRegistry(
            store: store,
            log: SessionLog(),
            behavior: FakeSessionBehavior(startError: .serverExited(status: 3))
        )

        var sessionEmissions = 0
        let token = registry.$sessions.sink { _ in sessionEmissions += 1 }
        defer { token.cancel() }

        let configuration = makeConfiguration()
        store.set([configuration], for: UserSettings.languageServerConfigurations)
        let emissionsAfterCreation = sessionEmissions

        #expect(await poll { stateName(registry, configuration.id) == "failed" })

        #expect(registry.sessions[configuration.id] != nil)
        #expect(registry.session(forLanguageId: "swift") != nil)
        #expect(sessionEmissions == emissionsAfterCreation, "the failure must not move `sessions`")
        #expect(registry.sessionStates[configuration.id]?.failure != nil)
    }
}
