import AgenticToolkitCore
import AgenticToolkitCoreUI
import AgenticToolkitCoreMacOS
import AgenticToolkitMacOS
import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    var features: Features?

    /// Owns the one reply this delegate owes AppKit once a quit defers, and
    /// the budget that sends it if the flush wedges.
    private let shutdown = ApplicationShutdownCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            logger.info("Agentic Toolkit launching under XCTest — skipping app bootstrap")
            return
        }
        NSApp.setActivationPolicy(.regular)
        let features = Features()
        features.start()
        self.features = features
    }

    /// Shutdown runs here rather than in `applicationWillTerminate(_:)`
    /// because that method is synchronous: it returns straight into process
    /// exit, so the features' async `terminate()` hooks never ran at all.
    /// The coordinator holds the quit open until they finish, and quits anyway
    /// if they wedge.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !shutdown.isTerminating else { return .terminateLater }
        guard let features else { return .terminateNow }
        features.stop()
        return shutdown.begin {
            await features.terminate()
        } then: { [weak self] in
            self?.features = nil
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { false }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
}

extension AppDelegate: Loggable {
    public static nonisolated let logger = makeLogger()
}
