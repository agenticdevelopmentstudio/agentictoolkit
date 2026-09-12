import AgenticToolkitCore
import AppKit
import os

/// The `.terminateLater` dance an app has to do to flush anything on the way
/// out — written once, for every app built on this toolkit.
///
/// `applicationWillTerminate(_:)` is synchronous and returns straight into
/// process exit, so an async shutdown hook launched from it is a `Task` the
/// process never gets round to running: the debounced save inside its window
/// is lost on every quit, silently, and a test that calls the delegate method
/// directly still passes. Deferring the reply is the only way to hold the quit
/// open long enough, and it carries two obligations that are easy to get wrong
/// and invisible when they are — exactly one `reply(toApplicationShouldTerminate:)`
/// must be sent, and it must be sent *even when the flush never finishes*, or
/// the user is left with an app that cannot be quit and no way out of it.
///
/// Both obligations are met here by construction rather than by each app
/// remembering them: `finish()` is idempotent, and the budget timer replies on
/// the app's behalf when the flush does not (`idempotency`, `fail-fast`).
@MainActor
public final class ApplicationShutdownCoordinator {

    /// How long the flush gets before the app quits anyway.
    ///
    /// A save that misses this window is lost, which is bad. An app that
    /// cannot be quit because one feature's flush wedged is worse.
    public static let defaultFlushBudget: Duration = .seconds(5)

    private let flushBudget: Duration
    private let reply: @MainActor (Bool) -> Void

    /// True from the moment the first quit defers, so a second one — an
    /// impatient ⌘Q, a Dock "Quit", a logout arriving inside the budget —
    /// can be told the quit is already under way instead of starting a
    /// second shutdown alongside the first.
    public private(set) var isTerminating = false

    private var hasReplied = false

    /// - Parameters:
    ///   - flushBudget: How long `begin(flush:then:)` waits before replying
    ///     without the flush.
    ///   - reply: How the reply reaches AppKit. Injected (`dependency-injection`)
    ///     so a test can observe the reply instead of sending a real one:
    ///     `reply(toApplicationShouldTerminate:)` with no termination pending
    ///     is not a defined thing to do to a test runner.
    public init(
        flushBudget: Duration = ApplicationShutdownCoordinator.defaultFlushBudget,
        reply: @escaping @MainActor (Bool) -> Void = { NSApp.reply(toApplicationShouldTerminate: $0) }
    ) {
        self.flushBudget = flushBudget
        self.reply = reply
    }

    /// Starts the deferred shutdown and returns what the delegate should
    /// return from `applicationShouldTerminate(_:)`.
    ///
    /// Safe to call for every quit gesture: the first one runs `flush`, and
    /// every later one is a no-op that still answers `.terminateLater`,
    /// because the reply the first one owes AppKit is the only one coming.
    ///
    /// - Parameters:
    ///   - flush: The asynchronous shutdown work. Cancelled if the budget runs
    ///     out first.
    ///   - then: Run once, immediately before the reply, whichever of the two
    ///     got there. This is where an app drops what it was holding — it has
    ///     to run on the budget path too, which is why it is not simply the
    ///     last line of `flush`.
    @discardableResult
    public func begin(
        flush: @escaping @MainActor () async -> Void,
        then: @escaping @MainActor () -> Void = {}
    ) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateLater }
        isTerminating = true

        let flushTask = Task { @MainActor in
            await flush()
            self.finish(then)
        }
        Task { @MainActor in
            try? await Task.sleep(for: flushBudget)
            guard !self.hasReplied else { return }
            Self.logger.error("Shutdown flush did not finish in time — quitting with writes outstanding")
            flushTask.cancel()
            self.finish(then)
        }
        return .terminateLater
    }

    /// Either the flush or the budget gets here first; the loser is a no-op.
    /// `reply(toApplicationShouldTerminate:)` is not documented as safe to
    /// call twice, so it is called once by construction.
    private func finish(_ then: @MainActor () -> Void) {
        guard !hasReplied else { return }
        hasReplied = true
        then()
        reply(true)
    }
}

extension ApplicationShutdownCoordinator: Loggable {
    public static nonisolated let logger = makeLogger()
}
