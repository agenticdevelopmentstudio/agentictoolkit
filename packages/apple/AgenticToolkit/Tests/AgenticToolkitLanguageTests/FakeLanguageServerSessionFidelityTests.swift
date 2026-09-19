import AgenticToolkitCore
import Foundation
import LanguageServerProtocol
import Testing
@testable import AgenticToolkitLanguage

/// Tests of the *fake*, which is unusual enough to say why.
///
/// `FakeLanguageServerSession` stands in for `LanguageServerSession` in every
/// registry and document-sync suite. Wherever the fake is **looser** than the
/// real session, a defect that the real session would surface passes through
/// the whole test bundle unseen — the tests keep testing, and what they test is
/// the fake. That failure mode is invisible by construction: nothing goes red.
/// So the places where the two are deliberately aligned are pinned here, by
/// name, against the real session's own source.
///
/// The one pinned below is the teardown window. `LanguageServerSession.stop()`
/// sets `isStopped` at the top, **before its first suspension**, and
/// `runningServer()` consults it — so a request arriving after `stop()` has
/// begun is refused even though the state has not been rewritten yet and the
/// child process is still alive. The fake used to decide on `state` alone, and
/// its `stop()` suspends on a held continuation *before* writing `.stopped`,
/// so for the whole of that window it answered traffic the real session
/// refuses. A held stop is exactly the shape a teardown-ordering test sets up,
/// so the looseness sat directly under the tests written to find it.
@Suite("FakeLanguageServerSession fidelity")
struct FakeLanguageServerSessionFidelityTests {

    private func makeFake(log: SessionLog) -> FakeLanguageServerSession {
        let configuration = LanguageServerConfiguration(
            name: "Fake",
            languageIds: ["swift"],
            command: "/nonexistent/server",
            rootMarkers: [".git"]
        )
        return FakeLanguageServerSession(
            configuration: configuration,
            environment: [:],
            rootURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            log: log,
            behavior: FakeSessionBehavior(holdsStop: true)
        )
    }

    /// `LanguageServerSessionState` is deliberately not `Equatable` — `.failed`
    /// carries a failure nobody would want compared — so the state is read by
    /// pattern rather than by `==`.
    private func isRunning(_ fake: FakeLanguageServerSession) async -> Bool {
        if case .running = await fake.state { return true }
        return false
    }

    private func openParams() -> DidOpenTextDocumentParams {
        DidOpenTextDocumentParams(
            textDocument: TextDocumentItem(
                uri: "file:///tmp/Fidelity.swift",
                languageId: "swift",
                version: 1,
                text: "abcdef"
            )
        )
    }

    /// What it catches: `requireRunning()` reverting to `guard case .running`.
    /// The state is asserted to *still be* `.running` here, which is what makes
    /// the refusal attributable to the stop flag and nothing else.
    @Test("a fake refuses notifications from the instant stop() begins")
    func heldStopRefusesNotifications() async throws {
        let log = SessionLog()
        let fake = makeFake(log: log)
        try await fake.start()

        let stopping = Task { await fake.stop() }
        await fake.waitForHeldStop()

        // Mid-teardown, and the state has not been rewritten yet: this is the
        // window, not the aftermath.
        #expect(await isRunning(fake))

        await #expect(throws: LanguageServerSessionError.notRunning) {
            try await fake.didOpen(openParams())
        }

        await fake.releaseHeldStop()
        await stopping.value

        // The refusal is not recorded — nothing reached the server — so the
        // whole call log is the lifecycle, with no open in the middle.
        #expect(log.calls(forInstance: fake.instanceID) == [.start, .stop])
    }

    /// The other gate the real session carries, and the one with a comment in
    /// both fakes asking whoever relaxes one to check the other.
    ///
    /// What it catches: a delegate-side fix looking tested while the real
    /// session would still hand back stale, pre-teardown capabilities.
    @Test("a fake answers no capabilities from the instant stop() begins")
    func heldStopRefusesCapabilities() async throws {
        let log = SessionLog()
        let fake = makeFake(log: log)
        try await fake.start()

        let stopping = Task { await fake.stop() }
        await fake.waitForHeldStop()

        #expect(await isRunning(fake))
        #expect(await fake.capabilities() == nil)

        await fake.releaseHeldStop()
        await stopping.value
    }
}
