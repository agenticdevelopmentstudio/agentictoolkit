import AppKit
@preconcurrency import Sparkle

/// Sparkle's standard updater, for any bundle with a feed and a signing key.
/// A dev-channel build checks only when asked — see `AppUpdaterConfiguration`.
@MainActor
public final class AppUpdater {
    public let configuration: AppUpdaterConfiguration
    private let controller: SPUStandardUpdaterController
    /// Held here: Sparkle keeps its delegate weakly.
    private let policy: AppUpdaterPolicy

    public init?(bundle: Bundle = .main) {
        guard let configuration = AppUpdaterConfiguration(infoDictionary: bundle.infoDictionary ?? [:])
        else { return nil }
        self.configuration = configuration
        policy = AppUpdaterPolicy(checksInBackground: configuration.checksInBackground)
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: policy, userDriverDelegate: nil)
    }

    public func checkForUpdates() { controller.checkForUpdates(nil) }
    public var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
}

/// Refuses Sparkle's background work when the channel doesn't allow it.
/// Asked per check rather than by turning `automaticallyChecksForUpdates` off:
/// that setting is saved in the bundle id's defaults, which a dev build shares
/// with a release build of the same app.
final class AppUpdaterPolicy: NSObject, SPUUpdaterDelegate {
    private let checksInBackground: Bool

    init(checksInBackground: Bool) {
        self.checksInBackground = checksInBackground
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard !checksInBackground, updateCheck == .updatesInBackground else { return }
        throw NSError(domain: "AppUpdater", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "A dev-channel build checks for updates only when asked."
        ])
    }

    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool {
        checksInBackground
    }
}
