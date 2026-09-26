import AppKit
@preconcurrency import Sparkle

/// Sparkle's standard updater, started only for release-channel builds.
@MainActor
public final class AppUpdater {
    private let controller: SPUStandardUpdaterController

    public init?(bundle: Bundle = .main) {
        guard AppUpdaterConfiguration(infoDictionary: bundle.infoDictionary ?? [:]) != nil
        else { return nil }
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    public func checkForUpdates() { controller.checkForUpdates(nil) }
    public var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
}
