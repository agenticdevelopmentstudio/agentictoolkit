import AgenticToolkitCore
import Foundation
import LanguageServerProtocol
import Testing
@testable import AgenticToolkitLanguage

/// A `Bool` a background task can set and a main-actor test can read.
///
/// Lock-guarded rather than isolated: the writer is the last statement of a
/// `for await` loop that has just ended, and the reader is a poll on the main
/// actor. An actor here would make the read a suspension and the poll a
/// different shape for no gain.
private final class TerminationFlag: @unchecked Sendable {

    private let lock = NSLock()
    private var finished = false

    func markFinished() {
        lock.lock()
        defer { lock.unlock() }
        finished = true
    }

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }
}

/// `DiagnosticStore` against the fake session — no editor, no window, no run
/// loop, which is the whole reason the store lives in this framework rather
/// than beside `ProjectLanguageServices` in `macOS/`.
@Suite("DiagnosticStore")
@MainActor
struct DiagnosticStoreTests {

    /// Ceiling on any poll here. Every effect under test lands from an
    /// unstructured `Task` draining an `AsyncStream`, so none of them is
    /// visible on the statement after the push.
    private static let pollSeconds: TimeInterval = 5

    private static let firstURI: DocumentUri = "file:///Workspace/First.swift"
    private static let secondURI: DocumentUri = "file:///Workspace/Second.swift"

    // MARK: - Fixtures

    private func makeSession(
        languageIds: [String] = ["swift"],
        log: SessionLog = SessionLog()
    ) -> FakeLanguageServerSession {
        FakeLanguageServerSession(
            configuration: LanguageServerConfiguration(
                name: "Fake",
                languageIds: languageIds,
                command: "/nonexistent/server",
                rootMarkers: [".git"]
            ),
            environment: [:],
            rootURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            log: log
        )
    }

    private func makeDiagnostic(
        _ message: String,
        line: Int = 0,
        severity: DiagnosticSeverity = .error
    ) -> Diagnostic {
        Diagnostic(
            range: LSPRange(
                start: Position(line: line, character: 0),
                end: Position(line: line, character: 4)
            ),
            severity: severity,
            message: message
        )
    }

    private func poll(
        seconds: TimeInterval = DiagnosticStoreTests.pollSeconds,
        until condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    // MARK: - 1. Order and replacement

    /// Two publishes for one URI: the second replaces the first, and neither is
    /// merged into the other.
    ///
    /// What it catches: a store that appends rather than replaces, which leaves
    /// every fixed error on screen forever; and a store whose task never starts,
    /// which looks identical to a server that said nothing.
    @Test("two publishes for one URI leave the second set, in send order")
    func secondPublishReplacesTheFirst() async {
        let store = DiagnosticStore()
        let session = makeSession()
        store.observe(session)

        session.publish(PublishDiagnosticsParams(
            uri: Self.firstURI,
            version: 1,
            diagnostics: [makeDiagnostic("first")]
        ))
        session.publish(PublishDiagnosticsParams(
            uri: Self.firstURI,
            version: 2,
            diagnostics: [makeDiagnostic("second"), makeDiagnostic("third", line: 1)]
        ))

        let arrived = await poll { store.diagnostics(for: Self.firstURI).count == 2 }
        #expect(arrived)
        #expect(store.diagnostics(for: Self.firstURI).map(\.message) == ["second", "third"])
        #expect(store.version(for: Self.firstURI) == 2)

        store.shutdown()
    }

    // MARK: - 2. The empty array is a clear, not a no-op

    /// LSP has no "clear" notification: an empty `diagnostics` array *is* the
    /// clear. A store that ignored it would leave the last error on screen for
    /// the rest of the session, which is the exact bug this asserts against.
    @Test("an empty diagnostics array clears the URI rather than being ignored")
    func emptyArrayClearsTheURI() async {
        let store = DiagnosticStore()
        let session = makeSession()
        store.observe(session)

        session.publish(PublishDiagnosticsParams(
            uri: Self.firstURI,
            version: nil,
            diagnostics: [makeDiagnostic("boom")]
        ))
        let arrived = await poll { store.diagnostics(for: Self.firstURI).count == 1 }
        #expect(arrived)

        session.publish(PublishDiagnosticsParams(uri: Self.firstURI, version: nil, diagnostics: []))
        let cleared = await poll { store.diagnostics(for: Self.firstURI).isEmpty }
        #expect(cleared)
        // Cleared, but still *known*: the server said this file is clean, which
        // is not the same as never having spoken about it. `clear(uri:)` is the
        // other one, and it is what a document close calls.
        #expect(store.documents[Self.firstURI] != nil)

        store.clear(uri: Self.firstURI)
        #expect(store.documents[Self.firstURI] == nil)

        store.shutdown()
    }

    // MARK: - 3. Two URIs from one session

    @Test("diagnostics for two URIs from one session land under their own keys")
    func twoURIsFromOneSession() async {
        let store = DiagnosticStore()
        let session = makeSession()
        store.observe(session)

        session.publish(PublishDiagnosticsParams(
            uri: Self.firstURI,
            version: nil,
            diagnostics: [makeDiagnostic("in first")]
        ))
        session.publish(PublishDiagnosticsParams(
            uri: Self.secondURI,
            version: nil,
            diagnostics: [makeDiagnostic("in second"), makeDiagnostic("also second", line: 3)]
        ))

        let arrived = await poll {
            store.diagnostics(for: Self.firstURI).count == 1
                && store.diagnostics(for: Self.secondURI).count == 2
        }
        #expect(arrived)
        #expect(store.diagnostics(for: Self.firstURI).first?.message == "in first")
        #expect(store.diagnostics(for: Self.secondURI).first?.message == "in second")

        store.shutdown()
    }

    // MARK: - 4. Two sessions, one store

    /// A project with a Swift server and a Python server has two sessions and
    /// one overlay layer. Both streams have to reach the same map.
    @Test("two sessions both reach one store")
    func twoSessionsOneStore() async {
        let store = DiagnosticStore()
        let swift = makeSession(languageIds: ["swift"])
        let python = makeSession(languageIds: ["python"])
        store.observe(swift)
        store.observe(python)

        swift.publish(PublishDiagnosticsParams(
            uri: Self.firstURI,
            version: nil,
            diagnostics: [makeDiagnostic("swift said so")]
        ))
        python.publish(PublishDiagnosticsParams(
            uri: Self.secondURI,
            version: nil,
            diagnostics: [makeDiagnostic("python said so")]
        ))

        let arrived = await poll {
            !store.diagnostics(for: Self.firstURI).isEmpty
                && !store.diagnostics(for: Self.secondURI).isEmpty
        }
        #expect(arrived)
        #expect(store.diagnostics(for: Self.firstURI).first?.message == "swift said so")
        #expect(store.diagnostics(for: Self.secondURI).first?.message == "python said so")

        store.shutdown()
    }

    // MARK: - 5. The session that appears later

    /// The already-open-file defect, asserted rather than assumed: the store is
    /// wired to a registry that has **no** sessions, the configuration arrives
    /// afterwards, and the session it produces must still be observed.
    ///
    /// This is the same shape as Task 3.3's fix round 2 on the trigger-character
    /// path. A store that read `registry.sessions` once at construction passes
    /// every other test in this suite and shows nothing in the app.
    @Test("a session the registry publishes after construction is observed")
    func lateSessionIsObserved() async throws {
        let log = SessionLog()
        let settings = SettingsStore(
            with: InMemorySettingsStorageProvider(),
            secureSettingsProvider: InMemorySecureSettingsStorageProvider()
        )
        let registry = LanguageServerRegistry(
            store: settings,
            workspaceURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
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

        let store = DiagnosticStore()
        store.observeSessions(from: registry)
        #expect(registry.sessions.isEmpty)

        settings.set(
            [LanguageServerConfiguration(
                name: "Late",
                languageIds: ["swift"],
                command: "/nonexistent/server",
                rootMarkers: []
            )],
            for: UserSettings.languageServerConfigurations
        )

        let appeared = await poll { registry.session(forLanguageId: "swift") != nil }
        #expect(appeared)
        let session = try #require(registry.session(forLanguageId: "swift") as? FakeLanguageServerSession)

        session.publish(PublishDiagnosticsParams(
            uri: Self.firstURI,
            version: nil,
            diagnostics: [makeDiagnostic("from a server that started late")]
        ))
        let arrived = await poll { !store.diagnostics(for: Self.firstURI).isEmpty }
        #expect(arrived)

        store.shutdown()
        await registry.shutdown()
    }

    // MARK: - 6. Shutdown

    /// After `shutdown()` nothing further is stored, and calling it twice is a
    /// no-op rather than a crash.
    ///
    /// The assertion is deterministic because `shutdown()` sets its flag before
    /// cancelling anything: a notification already sitting in the stream's
    /// buffer is dropped by the write path, not raced by the cancellation.
    @Test("shutdown stops observation and is idempotent")
    func shutdownStopsObservation() async {
        let store = DiagnosticStore()
        let session = makeSession()
        store.observe(session)

        session.publish(PublishDiagnosticsParams(
            uri: Self.firstURI,
            version: nil,
            diagnostics: [makeDiagnostic("before")]
        ))
        let arrived = await poll { !store.diagnostics(for: Self.firstURI).isEmpty }
        #expect(arrived)

        store.shutdown()
        store.shutdown()

        session.publish(PublishDiagnosticsParams(
            uri: Self.secondURI,
            version: nil,
            diagnostics: [makeDiagnostic("after")]
        ))
        // Nothing to wait *for*, so the wait is the other way up: give the
        // observation task every chance to run and assert it did not write.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(store.diagnostics(for: Self.secondURI).isEmpty)
        // And what it already knew is left alone — teardown is not a clear.
        #expect(store.diagnostics(for: Self.firstURI).count == 1)

        // A late `observe` after shutdown is refused rather than starting a
        // task nothing will ever cancel.
        store.observe(session)
        session.publish(PublishDiagnosticsParams(
            uri: Self.secondURI,
            version: nil,
            diagnostics: [makeDiagnostic("later still")]
        ))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(store.diagnostics(for: Self.secondURI).isEmpty)
    }

    // MARK: - 8. Ordering

    /// The stream's ordering guarantee, asserted on the stream itself rather
    /// than through the store — a map cannot show order, only its last write.
    ///
    /// One task drains one stream and yields into an unbounded stream in receipt
    /// order, so N publishes arrive as N events in that order.
    @Test("N publishes arrive in the order they were sent")
    func publishesArriveInOrder() async {
        let session = makeSession()
        let expected = (0..<20).map { "file:///Workspace/File\($0).swift" }

        for (index, uri) in expected.enumerated() {
            session.publish(PublishDiagnosticsParams(
                uri: uri,
                version: index,
                diagnostics: [makeDiagnostic("message \(index)")]
            ))
        }
        session.finishDiagnostics()

        var received: [String] = []
        for await params in session.publishedDiagnostics {
            received.append(params.uri)
        }
        #expect(received == expected)
    }
}

/// Test 7 — the stream's *lifetime*, which only the real session can answer.
///
/// `.serialized` and scripted `/bin/sh` children, the same doubles
/// `LanguageServerSessionTests` uses: nothing here needs a language server
/// installed, and every wait is bounded so a stream that never finishes fails
/// the test instead of wedging the suite.
@Suite("LanguageServerSession published diagnostics", .serialized)
struct PublishedDiagnosticsStreamTests {

    private static let initializeBudget: TimeInterval = 2
    private static let shutdownBudget: TimeInterval = 0.5
    private static let pollSeconds: TimeInterval = 10

    /// Answers one `initialize` and then stays alive swallowing everything else.
    private static let respondingServerScript = #"""
    CAPS='{"hoverProvider":true}'
    BODY='{"jsonrpc":"2.0","id":1,"result":{"capabilities":'"$CAPS"'}}'
    IFS= read -r HEADER_LINE
    printf 'Content-Length: %s\r\n\r\n%s' "${#BODY}" "$BODY"
    cat >/dev/null
    """#

    /// Explains itself on stderr and dies — a server with a broken toolchain.
    private static let failingServerScript = #"""
    echo 'boom: no toolchain here' >&2
    exit 3
    """#

    private func makeSession(script: String) -> LanguageServerSession {
        LanguageServerSession(configuration: .init(
            name: "Scripted",
            languageIds: ["swift"],
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            rootURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            initializeBudgetSeconds: Self.initializeBudget,
            shutdownBudgetSeconds: Self.shutdownBudget
        ))
    }

    private func poll(
        seconds: TimeInterval = PublishedDiagnosticsStreamTests.pollSeconds,
        until condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    /// A consumer's `for await` must terminate when the session stops.
    ///
    /// What it catches: a `finish()` that is missing, or placed on a path
    /// `stop()` does not take. The failure mode is not a wrong answer — it is a
    /// task parked forever, holding its session and, through it, a
    /// language-server subprocess that never goes away.
    @Test("the published-diagnostics stream finishes when the session stops")
    func streamFinishesOnStop() async throws {
        let session = makeSession(script: Self.respondingServerScript)
        let flag = TerminationFlag()
        let stream = session.publishedDiagnostics
        let reader = Task {
            for await _ in stream {}
            flag.markFinished()
        }

        try await session.start()
        #expect(!flag.isFinished)

        await session.stop()

        let ended = await poll { flag.isFinished }
        #expect(ended)
        reader.cancel()
    }

    /// The same, for a server that never gets as far as running.
    ///
    /// The `.failed` path is the one a consumer is most likely to be parked on:
    /// the store attaches when the registry publishes the session, which is
    /// before the handshake has had a chance to fail.
    @Test("the published-diagnostics stream finishes when the session fails to start")
    func streamFinishesOnFailedStart() async {
        let session = makeSession(script: Self.failingServerScript)
        let flag = TerminationFlag()
        let stream = session.publishedDiagnostics
        let reader = Task {
            for await _ in stream {}
            flag.markFinished()
        }

        await #expect(throws: (any Error).self) { try await session.start() }

        let ended = await poll { flag.isFinished }
        #expect(ended)
        reader.cancel()
    }
}
