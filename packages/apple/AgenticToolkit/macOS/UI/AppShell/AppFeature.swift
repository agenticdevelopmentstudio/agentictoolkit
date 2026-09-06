import Foundation
import AgenticToolkitCore
import os
import OSLog

/// A self-contained feature module the host app composes during launch.
/// Hosts collect their `AppFeature`s into an array and call the lifecycle
/// hooks at the appropriate `NSApplicationDelegate` events.
///
/// All hooks are optional — features only implement what they need.
@MainActor
open class AppFeature {

    public var featureName: String = ""

    public var menuContributions: [MenuContribution] = []

    /// What this feature's "New" means while its window is key. Empty when
    /// the feature has no "New" of its own. See `NewItemProvider`.
    public var newItemProviders: [NewItemProvider] = []

    public var scriptingKeys = Set<String>()

    /// Called once per launch, after the feature has been constructed and
    /// other features in the same launch wave are visible. Bring up
    /// long-running services here (timers, file watchers, ingestion, …).
    ///
    /// `open` so host apps in other modules can override it.
    open func start() throws {
    }

    /// Called from `applicationWillTerminate(_:)`. Stop synchronous services
    /// here. Pair with `terminate()` for async cleanup.
    ///
    /// `open` so host apps in other modules can override it.
    open func stop() {
    }

    /// Called from `applicationWillTerminate(_:)`, after `stop()`. Use for
    /// async shutdown work like flushing pending saves.
    ///
    /// `open` so host apps in other modules can override it.
    open func terminate() async {

    }

    public func register() {
        AppFeatureRegistry.shared.register(self)
    }

    public func unregister() {
        AppFeatureRegistry.shared.unregister(self)
    }

    public var defaultName: String {
        "\(type(of: self))".replacingOccurrences(of: ".Type", with: "")
    }

    public init() {
        self.featureName = defaultName
        register()
    }

    /// Read the value for a key in `scriptingKeys`. Return `nil` if the key
    /// is unknown — the router will move on to the next contributor.
    ///
    /// `open` so host apps in other modules can override it.
    open func value(forScriptingKey key: String) -> Any? {
        nil
    }

    /// Write the value for a key in `scriptingKeys`. Default no-op; override
    /// for read-write keys.
    ///
    /// `open` so host apps in other modules can override it.
    open func setValue(_ value: Any?, forScriptingKey key: String) {

    }

}

@MainActor
open class AppFeatureRegistry {

    public static let shared = AppFeatureRegistry()

    public private(set) var featureMap: [String: AppFeature] = [:]

    /// Registration order. `featureMap.values` is a Swift `Dictionary`'s value
    /// order, which is seeded per process — different on every launch, not
    /// stable within one — and `features` used to return exactly that (W-M1
    /// in the review this fixes). Whippet's `MenuManager` relies on `features`'
    /// order for the order File-menu groups appear in, so `featureMap` stays
    /// for lookup by name but is never again what `features` reads from.
    private var orderedFeatures: [AppFeature] = []

    public var features: [AppFeature] {
        orderedFeatures
    }

    public func register(_ feature: AppFeature) {
        if let index = orderedFeatures.firstIndex(where: { $0.featureName == feature.featureName }) {
            // Re-registering a name already known replaces it in place,
            // keeping its original position — a rename-in-place, not a
            // reordering.
            orderedFeatures[index] = feature
        } else {
            orderedFeatures.append(feature)
        }
        featureMap[feature.featureName] = feature
        logger.info("Registered feature: \(feature.featureName)")
    }

    public func unregister(_ feature: AppFeature) {
        featureMap.removeValue(forKey: feature.featureName)
        orderedFeatures.removeAll { $0.featureName == feature.featureName }
        logger.info("Unegistered feature: \(feature.featureName)")
    }

    public func feature(named name: String) -> AppFeature? {
        featureMap[name]
    }

    public func contains(featureNamed name: String) -> Bool {
        featureMap.keys.contains(name)
    }

    public func startAll() {
        for feature in features {
            do {
                try feature.start()
                logger.info("Started feature: \(feature.featureName)")
            } catch {
                assertionFailure("Failed to start feature \(feature.featureName): \(error)")
            }
        }
    }

    public func stopAll() {
        for feature in features {
            feature.stop()
            logger.info("Stopped feature: \(feature.featureName)")
        }
    }

    /// Look up a registered feature by its concrete type.
    public func feature<F: AnyObject>(_ type: F.Type) -> F? {
        for feature in features {
            if let featureAsT = feature as? F {
                return featureAsT
            }
        }
        return nil
    }
}

extension AppFeatureRegistry: Loggable {
    public static nonisolated let logger = makeLogger()
}
