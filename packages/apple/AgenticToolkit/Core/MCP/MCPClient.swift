//
//  MCPClient.swift
//  AgenticToolkit
//
//  Created by Mike Fullerton on 4/30/26.
//

import Foundation
import MCP
import OSLog

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
    public func connect() async throws {
        state = .connecting
        do {
            let transport = makeTransport()
            self.transport = transport
            _ = try await client.connect(transport: transport)
            await registerToolListChangedHandler()
            try await refreshTools()
            state = .connected
        } catch {
            state = .failed("\(error)")
            await teardown()
            throw error
        }
    }

    public func disconnect() async {
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
    private func teardown() async {
        await client.disconnect()
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
