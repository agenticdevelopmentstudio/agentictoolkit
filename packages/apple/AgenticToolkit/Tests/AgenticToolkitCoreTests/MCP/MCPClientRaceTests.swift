import Foundation
import MCP
import Testing
@testable import AgenticToolkitCore

/// `MCPClient` owns the MCP server process transitively — `SubprocessTransport`
/// spawns and reaps it, and this client is the only thing holding the
/// transport. That makes the client, not the transport, where a
/// connect/disconnect race can strand a process: the transport's own tri-state
/// guard covers the window *inside* `SubprocessTransport.connect()`, and
/// `MCPClient.connect()` opens a wider one above it.
///
/// The probes drive a real child (a shell loop that never answers `initialize`,
/// so a connect stays in flight for as long as the race needs) and find it with
/// `pgrep -f` on a UUID in its `argv`, because in the failing case nothing ever
/// reads its stdout and a pid it printed would never be collected.
///
/// `.serialized` because these count processes by name across the whole
/// machine, and because the failure they look for is timing-shaped.
@Suite("MCPClient connect/disconnect race", .serialized)
struct MCPClientRaceTests {

    private static let markerCommand = "while :; do sleep 0.05; done"

    private func makeClient(marker: String) -> MCPClient {
        MCPClient(
            configuration: MCPServerConfiguration(
                name: "race-probe",
                transport: .stdio(
                    command: "/bin/sh",
                    arguments: ["-c", Self.markerCommand, marker],
                    environment: [:]
                )
            )
        )
    }

    /// The production shape, from `MCPServerRegistry.reconcile`: connect and
    /// disconnect are each started in their own unstructured `Task`, and the
    /// registry drops its reference to the client the moment the disconnect is
    /// queued. Nothing here awaits the connect, for the same reason the
    /// registry does not — which is exactly what makes a stranded child
    /// permanent rather than merely late.
    ///
    /// Two orderings have to come out the same way, and they are closed by
    /// different halves of the fix:
    ///
    /// - The connect is in flight when the disconnect lands. `connectTask` is
    ///   what covers this: `teardown()` cancels it, unwedges it through
    ///   `MCP.Client.disconnect()`, waits for it, and only then reads
    ///   `self.transport` — so the spawn has either happened and is reaped, or
    ///   been ruled out.
    /// - The disconnect runs to completion before `connect()` enters the actor
    ///   at all. There is no task to hold, and `teardown()` correctly finds
    ///   nothing; `isShutDown` is what covers this, by making the connect that
    ///   arrives afterwards throw instead of spawning.
    ///
    /// Iterated because which of the two happens is a scheduling accident, and
    /// the assertion has to hold for both. If this ever flakes, raise the
    /// iteration count — the failure mode is missing an ordering, never
    /// inventing one.
    @Test("a disconnect racing a connect never strands the server process")
    func disconnectRacingConnectStopsTheChild() async throws {
        let batch = "MCPClientRaceProbe-\(UUID().uuidString)"
        var pending: [Task<Void, Never>] = []
        defer { for task in pending { task.cancel() } }

        for iteration in 0..<20 {
            let client = makeClient(marker: "\(batch)-\(iteration)")
            // Deliberately not awaited: see the doc comment. A connect that
            // loses this race is left parked exactly as the registry would
            // leave it.
            pending.append(Task { try? await client.connect() })
            await client.disconnect()
        }

        var survivors = try Self.processesMatching(batch)
        for _ in 0..<50 where !survivors.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
            survivors = try Self.processesMatching(batch)
        }
        // Kill before asserting: a failure here means real orphans, and leaving
        // them running would outlive the whole test run.
        for pid in survivors { kill(pid, SIGKILL) }
        #expect(
            survivors.isEmpty,
            "a disconnect racing connect() left MCP servers running (pids \(survivors))"
        )
    }

    /// The sequential half of the same guarantee, and the one that proves the
    /// probe can see a child at all: here the spawn is waited for before the
    /// disconnect, so a surviving process is unambiguous.
    ///
    /// It also pins that `teardown()` can reap a connect that is *parked* —
    /// this server never answers `initialize`, and `MCP.Client.send` waits on a
    /// continuation with no cancellation handler, so cancelling the connect
    /// task cannot free it. Only `MCP.Client.disconnect()` can, which is why
    /// `teardown()` calls it before it waits.
    @Test("a connect that never finishes initializing is still reaped by disconnect")
    func parkedConnectIsStillReapedByDisconnect() async throws {
        let marker = "MCPClientTeardownProbe-\(UUID().uuidString)"
        let client = makeClient(marker: marker)

        let connecting = Task { try? await client.connect() }
        // Wait for the spawn rather than for the connect: the connect cannot
        // finish, because the child never answers `initialize`.
        var spawned = try Self.processesMatching(marker)
        for _ in 0..<50 where spawned.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
            spawned = try Self.processesMatching(marker)
        }
        try #require(!spawned.isEmpty, "the probe server never started")

        await client.disconnect()
        // Bounded by the disconnect above having already unwedged it.
        await connecting.value

        var survivors = try Self.processesMatching(marker)
        for _ in 0..<50 where !survivors.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
            survivors = try Self.processesMatching(marker)
        }
        for pid in survivors { kill(pid, SIGKILL) }
        #expect(
            survivors.isEmpty,
            "disconnect() left an unresponsive MCP server running (pids \(survivors))"
        )
    }

    /// Disconnection is terminal, and the sequential case is the readable
    /// statement of what the racing case relies on: a `connect()` that arrives
    /// after a completed `disconnect()` must not spawn a server, because the
    /// owner that would reap it has already been let go.
    @Test("connect after disconnect throws instead of starting a second server")
    func connectAfterDisconnectThrows() async throws {
        let marker = "MCPClientTerminalProbe-\(UUID().uuidString)"
        let client = makeClient(marker: marker)

        await client.disconnect()
        await #expect(throws: MCPClientError.clientHasBeenDisconnected) {
            try await client.connect()
        }

        let survivors = try Self.processesMatching(marker)
        for pid in survivors { kill(pid, SIGKILL) }
        #expect(
            survivors.isEmpty,
            "connect() after disconnect() started a server anyway (pids \(survivors))"
        )
        let state = await client.state
        #expect(state == .disconnected)
    }

    /// The pids whose full command line contains `marker`. `pgrep` never
    /// matches itself, so the marker in its own `argv` is not a false hit.
    private static func processesMatching(_ marker: String) throws -> [pid_t] {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-f", marker]
        let output = Pipe()
        pgrep.standardOutput = output
        pgrep.standardError = Pipe()
        try pgrep.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        pgrep.waitUntilExit()
        return (String(bytes: data, encoding: .utf8) ?? "")
            .split(separator: "\n")
            .compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
    }
}
