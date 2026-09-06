//
//  MCPClient.swift
//  AgenticToolkit
//
//  Created by Mike Fullerton on 4/30/26.
//

import Foundation
import MCP
import OSLog

public enum MCPClientError: Swift.Error, Sendable, Equatable {
    /// `connect()` was called on a client whose `disconnect()` has already
    /// run. See `MCPClient.disconnect()`: disconnection is terminal, and a
    /// reconnect is a new client.
    case clientHasBeenDisconnected
}

public enum MCPClientState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

/// Surface that the registry, chat view-model, and settings UI consume. Backed
/// by `MCPClient` in production; tests substitute a fake conforming type via
/// `MCPServerRegistry.ClientFactory`.
public protocol MCPClientProtocol: Actor {
    nonisolated var id: UUID { get }
    nonisolated var name: String { get }
    var state: MCPClientState { get }
    var cachedTools: [MCP.Tool] { get }

    func connect() async throws
    func disconnect() async
    func refreshTools() async throws
    func callTool(
        name: String,
        arguments: [String: Value]?
    ) async throws -> (content: [MCP.Tool.Content], isError: Bool)
}

/// Per-server connection: owns the SDK client, its transport, and the cached
/// tool list. The registry creates one of these per enabled
/// `MCPServerConfiguration` and disposes it when the configuration changes,
/// is disabled, or removed.
public actor MCPClient: MCPClientProtocol {

    public typealias State = MCPClientState

    public nonisolated let id: UUID
    public nonisolated let name: String

    private let configuration: MCPServerConfiguration
    private let secrets: [String: String]
    private let client: MCP.Client
    private var transport: (any Transport)?
    private(set) public var state: State = .disconnected
    private(set) public var cachedTools: [MCP.Tool] = []

    /// The in-flight `connect()`, held so `teardown()` can wait for it.
    ///
    /// Without this the transport's own connect/disconnect guard is not
    /// enough, because the losing ordering happens *above* the transport: a
    /// `teardown()` that runs to completion before `connect()` has spawned
    /// anything correctly finds nothing to stop, and the connect then spawns a
    /// child no one owns. Both suspensions in `connect()` — the actor hop into
    /// this task, and `MCP.Client`'s own work before it reaches
    /// `transport.connect()` — are inside that window.
    private var connectTask: Task<Void, Error>?

    /// Set by `disconnect()` and never cleared.
    ///
    /// `connectTask` covers a `disconnect()` that arrives while a connect is in
    /// flight. This covers the wider ordering it cannot: a `disconnect()` that
    /// runs to completion *before* `connect()` has entered this actor at all,
    /// where there is no in-flight task to hold and `teardown()` correctly
    /// finds nothing. That ordering is reachable in production — the registry
    /// starts both in unstructured `Task`s and drops its reference to the
    /// client as soon as the disconnect is queued (`MCPServerRegistry`
    /// `reconcile`), so a server toggled off just after it was enabled can have
    /// its connect scheduled after its disconnect finished. Without this flag
    /// that connect spawns a server process no one holds a reference to, and it
    /// runs until the app exits.
    private var isShutDown = false

    public init(
        configuration: MCPServerConfiguration,
        secrets: [String: String] = [:],
        clientName: String = "AgenticToolkit",
        clientVersion: String = "1.0.0"
    ) {
        self.id = configuration.id
        self.name = configuration.name
        self.configuration = configuration
        self.secrets = secrets
        self.client = MCP.Client(name: clientName, version: clientVersion)
    }

    /// Open the transport, perform initialization, and fetch the tool list.
    /// Caller is responsible for not connecting twice; calling on an already-
    /// connected client will throw from the underlying transport.
    ///
    /// The work runs in a held `Task` rather than inline so that a concurrent
    /// `disconnect()` has something to wait for. Everything this method does
    /// afterwards is bookkeeping on state, and both writes are conditional on
    /// still being `.connecting`, so a `disconnect()` that overtook the
    /// connect keeps the last word. That means a connect overtaken by a
    /// disconnect can return *successfully* while the client reads
    /// `.disconnected` and owns no transport; the caller asked for both, and
    /// the outcome it gets is the one it asked for second.
    ///
    /// Throws `MCPClientError.clientHasBeenDisconnected` if `disconnect()` has
    /// already run — see `isShutDown`. The guard is the *first* statement, so
    /// it is decided before any suspension and cannot be overtaken.
    public func connect() async throws {
        guard !isShutDown else { throw MCPClientError.clientHasBeenDisconnected }
        state = .connecting
        let task = Task { try await self.establishConnection() }
        connectTask = task
        do {
            try await task.value
            if connectTask == task { connectTask = nil }
            if case .connecting = state { state = .connected }
        } catch {
            if connectTask == task { connectTask = nil }
            if case .connecting = state { state = .failed("\(error)") }
            await teardown()
            throw error
        }
    }

    /// The body of `connect()`. Runs on this actor, so `self.transport` is
    /// assigned before any suspension that could let a `teardown()` in — and
    /// `teardown()` waits for this task, so by the time it reads that property
    /// the spawn has either happened or been ruled out.
    private func establishConnection() async throws {
        // A `teardown()` that cancelled this task before it was first
        // scheduled gets its wish here: no transport is built, so no child is
        // spawned. Cancellation arriving later is caught by `teardown()`'s
        // `transport?.disconnect()` instead, which is why this is an
        // optimisation rather than the guarantee.
        try Task.checkCancellation()
        let transport = makeTransport()
        self.transport = transport
        _ = try await client.connect(transport: transport)
        await registerToolListChangedHandler()
        try await refreshTools()
    }

    /// Stops the server and retires this client permanently.
    ///
    /// Disconnection is **terminal**: a later `connect()` throws
    /// `MCPClientError.clientHasBeenDisconnected` rather than starting a second
    /// server, and reconnecting means building a new `MCPClient`. That matches
    /// the lifecycle this type already documents — the registry disposes a
    /// client when its configuration changes, is disabled, or is removed, and
    /// builds a fresh one when it comes back — and it is what makes a connect
    /// that was *requested* before this call but *scheduled* after it safe.
    ///
    /// The flag is set before the first suspension, so it is visible to every
    /// `connect()` that has not already entered this actor.
    public func disconnect() async {
        isShutDown = true
        await teardown()
        state = .disconnected
    }

    /// Re-fetch the tool list from the server. Called automatically on connect
    /// and whenever the server emits `notifications/tools/list_changed`.
    public func refreshTools() async throws {
        let (tools, _) = try await client.listTools()
        cachedTools = tools
    }

    public func callTool(
        name: String,
        arguments: [String: Value]?
    ) async throws -> (content: [MCP.Tool.Content], isError: Bool) {
        let result = try await client.callTool(name: name, arguments: arguments)
        return (result.content, result.isError ?? false)
    }

    /// Stops the server and releases the transport.
    ///
    /// The transport is the *only* owner of the child process — a
    /// `SubprocessTransport` spawns it in `connect()` and reaps it in
    /// `disconnect()`. This client keeps no `Process` of its own beside it any
    /// more; a second owner would double-terminate, and no owner at all would
    /// leak the server for the life of the app.
    ///
    /// `disconnect()` is therefore called *before* the reference is dropped,
    /// and unconditionally: `MCP.Client.disconnect()` already disconnects the
    /// transport it holds, but it only holds one once `connect(transport:)`
    /// has been reached, so a failure between spawning and connecting would
    /// otherwise leave the child running. A second `disconnect()` awaits the
    /// first rather than returning early, so calling both is safe.
    ///
    /// The ownership fix is the four statements below, and their order is the
    /// whole argument. Both transport disconnects are needed, and each closes
    /// a hazard the other opens:
    ///
    /// 1. `connectTask?.cancel()` is *synchronous* and therefore lands before
    ///    this method's first suspension. That matters: a connect task that
    ///    has not been scheduled yet sees the cancellation at its own
    ///    `Task.checkCancellation()` and never builds a transport at all.
    /// 2. `await transport?.disconnect()` is what bounds step 4, and it is the
    ///    only thing here that does. `MCP.Client.send` reads `connection`
    ///    synchronously, then registers its continuation from an *unstructured
    ///    task* it spawns — so a `Client.disconnect()` that drains
    ///    `pendingRequests` in between drains a dictionary the request has not
    ///    joined yet, and the request is then registered with nothing left to
    ///    answer it. Nothing can resume it afterwards: the continuation is
    ///    bare, with no cancellation handler, so `cancel()` cannot reach it
    ///    either, and an `initialize` that parks that way parks for the life
    ///    of the process — taking step 4, and therefore `disconnect()`, with
    ///    it. Killing the transport *first* removes the way in: after this
    ///    line `SubprocessTransport.send` throws `ENOTCONN`, and the SDK's own
    ///    `catch` around the send resumes the continuation with that error. A
    ///    request that got out before this line is instead in
    ///    `pendingRequests`, where step 3 finds it. Between them there is no
    ///    third case.
    ///
    ///    That window has not been observed to open — 200 sweeps of the
    ///    disconnect across the spawn/`initialize` boundary produced no hang.
    ///    It stays shut today for two reasons that are not ours: the SDK's
    ///    `logger` is a computed property reading the `connection` it has just
    ///    nil'd, so its disconnect path has no real suspension before it
    ///    reaches the transport, and `SubprocessTransport.disconnect()` sets
    ///    `.idle` before *its* first suspension. This line is what makes the
    ///    guarantee ours rather than theirs; it costs one call that is a no-op
    ///    in every ordering where the window was already shut.
    /// 3. `await client.disconnect()` resumes every request that *did* get
    ///    registered, with `Client disconnected`, and nils the client's
    ///    `connection`. Steps 2 and 3 between them leave no request unresumed.
    ///    It also disconnects the same transport a second time, which is a
    ///    no-op — the transport returns immediately when it is already idle.
    /// 4. `await connectTask?.value` is the guarantee itself — after it, the
    ///    spawn has either happened or been ruled out, and no code path can
    ///    still be about to spawn. A connect that *fails* here is not this
    ///    method's business: the error is swallowed with `try?`, because
    ///    teardown releases resources and the party that wanted the outcome is
    ///    the `connect()` awaiting the same task. Skipping the release below
    ///    to propagate an error would leak the very child this exists to reap.
    /// 5. The second `await transport?.disconnect()` reaps what step 2 could
    ///    not have. A connect task suspended between `self.transport = …` and
    ///    `MCP.Client.connect(transport:)`'s call to `transport.connect()`
    ///    sees an idle transport when it resumes, and an idle transport
    ///    spawns. Step 4 waits for exactly that to play out; this line stops
    ///    the child it produced. It is a no-op in every other ordering.
    ///
    /// Awaiting the task *before* touching the transport — the obvious
    /// ordering, and the one this method used first — is the version that
    /// hangs: it is step 4 with none of step 2's protection, waiting on a
    /// connect that can no longer be resumed by anything.
    private func teardown() async {
        connectTask?.cancel()
        await transport?.disconnect()
        await client.disconnect()
        if let connectTask { _ = try? await connectTask.value }
        connectTask = nil
        await transport?.disconnect()
        transport = nil
    }

    private func registerToolListChangedHandler() async {
        await client.onNotification(ToolListChangedNotification.self) { [weak self] _ in
            guard let self else { return }
            try? await self.refreshTools()
        }
    }

    private func makeTransport() -> any Transport {
        switch configuration.transport {
        case let .stdio(command, arguments, environment):
            // Secrets override configured environment values, and that
            // precedence is load-bearing: a server's stored configuration is
            // edited by hand, its secrets come from the keychain.
            return makeStdioTransport(
                command: command,
                arguments: arguments,
                environment: environment.merging(secrets) { _, secret in secret }
            )
        case let .http(endpoint, streaming):
            return HTTPClientTransport(endpoint: endpoint, streaming: streaming)
        }
    }

    /// The child is spawned by the transport's own `connect()`, which
    /// `MCP.Client.connect(transport:)` calls — so a command that cannot be
    /// launched still surfaces as a thrown error out of `connect()` and lands
    /// the client in `.failed`, exactly as it did when this method ran the
    /// process itself.
    private func makeStdioTransport(
        command: String,
        arguments: [String],
        environment: [String: String]
    ) -> SubprocessTransport {
        SubprocessTransport(
            configuration: SubprocessChannel.Configuration(
                executableURL: URL(fileURLWithPath: command),
                arguments: arguments,
                environment: environment,
                // An MCP server needs `PATH` and `HOME` to launch at all, and
                // its configuration only ever carries overrides.
                environmentPolicy: .mergeOverParent,
                framing: .newlineDelimited
            )
        )
    }
}

extension MCPClient: Loggable {
    public static nonisolated let logger = makeLogger()
}
