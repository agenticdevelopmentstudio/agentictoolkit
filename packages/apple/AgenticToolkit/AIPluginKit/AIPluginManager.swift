import AgenticToolkitCore
import Foundation
import os
import OSLog

/// Discovers, loads, and manages LLM plugin bundles.
///
/// Plugins are macOS `.aiplugin` bundles whose `NSPrincipalClass` conforms to
/// `AIPluginKit.AIPlugin`. The manager reads each bundle's `descriptor.json` at
/// discovery time (cheap, no binary load) and only `dlopen`s the binary on
/// demand. Discovery never loads code, so the settings UI can list and configure
/// a plugin from its descriptor alone.
@MainActor
public final class AIPluginManager {

    // MARK: - Properties

    /// Descriptors for every discovered plugin. Binaries are not yet loaded.
    public var descriptors: [AIPluginDescriptor] { records.map(\.descriptor) }

    /// A provider template paired with the plugin that serves it. The picker's
    /// data source: every template every discovered plugin advertises.
    public struct AvailableProviderTemplate: Sendable, Equatable {
        public let pluginIdentifier: String
        public let template: AIPluginDescriptor.ProviderTemplate
    }

    /// Every advertised template across all discovered plugins, in descriptor
    /// order then template order.
    public var availableTemplates: [AvailableProviderTemplate] {
        records.flatMap { record in
            record.descriptor.resolvedTemplates.map {
                AvailableProviderTemplate(pluginIdentifier: record.descriptor.identifier, template: $0)
            }
        }
    }

    /// The template with `templateId` advertised by `pluginIdentifier`, if any.
    public func template(pluginIdentifier: String, templateId: String) -> AIPluginDescriptor.ProviderTemplate? {
        descriptor(for: pluginIdentifier)?.resolvedTemplates.first { $0.id == templateId }
    }

    /// The fields to render/seed for a configuration: the plugin descriptor's
    /// per-template fields, else the template's own, else none. One source of truth
    /// for the editor, the list view model, and first-run seeding.
    public func fields(
        pluginIdentifier: String, template: AIPluginDescriptor.ProviderTemplate
    ) -> [AIPluginDescriptor.Field] {
        descriptor(for: pluginIdentifier)?.fields(for: template) ?? (template.fields ?? [])
    }

    /// Internal storage pairing each descriptor with the bundle it came from.
    private var records: [Record] = []

    /// Loaded plugin instances, keyed by identifier.
    private var loadedPlugins: [String: any AIPlugin] = [:]

    /// Loaded bundles, keyed by identifier (kept alive so the binary stays mapped).
    private var loadedBundles: [String: Bundle] = [:]

    /// Directories to scan for `.aiplugin` bundles.
    private let searchPaths: [URL]

    /// App name used for the user plugins directory under Application Support.
    private let appName: String

    // MARK: - Errors

    public enum AIPluginError: Error, LocalizedError {
        case notFound(String)
        case loadFailed(String)
        case noPrincipalClass(String)
        case principalClassNotPlugin(String)

        public var errorDescription: String? {
            switch self {
            case .notFound(let id):
                return "Plugin not found: \(id)"
            case .loadFailed(let id):
                return "Failed to load plugin bundle: \(id)"
            case .noPrincipalClass(let id):
                return "Plugin '\(id)' has no NSPrincipalClass"
            case .principalClassNotPlugin(let id):
                return "Plugin '\(id)' principal class does not conform to AIPlugin"
            }
        }
    }

    // MARK: - Initialization

    /// Creates a plugin manager.
    ///
    /// Default search paths:
    /// - `Contents/PlugIns/` inside the app bundle
    /// - `~/.agenticplugins/`
    /// - `~/Library/Application Support/<appName>/Plugins/`
    public init(appName: String, additionalSearchPaths: [URL] = []) {
        self.appName = appName

        var paths: [URL] = []

        if let builtInPath = Bundle.main.builtInPlugInsURL {
            paths.append(builtInPath)
        }

        // The two locations, and the order, are the host's: `InstalledContentLocation`
        // derives where user-installed content lives, and this init says that for
        // plugins the bundle's own copy wins, then the hand-filled dotfolder, then
        // what an installer wrote.
        paths.append(InstalledContentLocation.homeDotDirectory(named: "agenticplugins"))

        if let userPlugins = InstalledContentLocation.applicationSupport(
            appName: appName, subdirectory: "Plugins") {
            paths.append(userPlugins)
        }

        paths.append(contentsOf: additionalSearchPaths)
        self.searchPaths = paths
    }

    /// Creates a plugin manager with explicit search paths only (no defaults).
    /// Useful for testing.
    public init(searchPaths: [URL], appName: String = "AgenticPlugins") {
        self.appName = appName
        self.searchPaths = searchPaths
    }

    // MARK: - Discovery

    /// Scans all search paths for `.aiplugin` bundles and reads their
    /// `descriptor.json`. Does not load any plugin binaries. Bundles without a
    /// descriptor, or whose `schemaVersion` the host does not understand, are
    /// skipped (this is how old v1 plugins are ignored).
    public func discoverPlugins() {
        let fileManager = FileManager.default

        for searchPath in searchPaths {
            guard fileManager.fileExists(atPath: searchPath.path) else { continue }

            guard let contents = try? fileManager.contentsOfDirectory(
                at: searchPath,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents where url.pathExtension == "aiplugin" {
                guard let bundle = Bundle(url: url),
                      let descriptor = Self.readDescriptor(from: bundle) else {
                    // swiftlint:disable:next line_length
                    logger.warning("Skipping plugin without a readable descriptor: \(url.lastPathComponent, privacy: .public)")
                    continue
                }

                guard (2...AIPluginDescriptor.currentSchemaVersion).contains(descriptor.schemaVersion) else {
                    // swiftlint:disable:next line_length
                    logger.warning("Skipping incompatible plugin '\(descriptor.displayName, privacy: .public)': schema \(descriptor.schemaVersion) not in 2...\(AIPluginDescriptor.currentSchemaVersion)")
                    continue
                }

                guard !records.contains(where: { $0.descriptor.identifier == descriptor.identifier }) else { continue }

                records.append(Record(descriptor: descriptor, bundleURL: url))
                // swiftlint:disable:next line_length
                logger.info("Discovered plugin: \(descriptor.displayName, privacy: .public) (\(descriptor.identifier, privacy: .public))")
            }
        }
    }

    /// Reads and decodes `descriptor.json` from a bundle's resources.
    private static func readDescriptor(from bundle: Bundle) -> AIPluginDescriptor? {
        guard let url = bundle.url(forResource: "descriptor", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(AIPluginDescriptor.self, from: data)
    }

    // MARK: - Loading

    /// Loads every discovered plugin. Resilient: a failure loading one plugin is
    /// logged and recorded in `failures` without aborting the others.
    public func loadAllPlugins() -> PluginLoadResult {
        var loaded: [any AIPlugin] = []
        var failures: [PluginLoadFailure] = []
        for descriptor in descriptors {
            do {
                loaded.append(try loadPlugin(identifier: descriptor.identifier))
            } catch {
                let message = error.localizedDescription
                // swiftlint:disable:next line_length
                logger.error("Failed to load plugin '\(descriptor.displayName, privacy: .public)' (\(descriptor.identifier, privacy: .public)): \(message, privacy: .public)")
                failures.append(
                    PluginLoadFailure(
                        identifier: descriptor.identifier,
                        displayName: descriptor.displayName,
                        message: message
                    )
                )
            }
        }
        return PluginLoadResult(loaded: loaded, failures: failures)
    }

    /// Loads a plugin's binary and instantiates it. Returns a cached instance if
    /// already loaded.
    public func loadPlugin(identifier: String) throws -> any AIPlugin {
        if let existing = loadedPlugins[identifier] {
            return existing
        }

        guard let record = records.first(where: { $0.descriptor.identifier == identifier }) else {
            throw AIPluginError.notFound(identifier)
        }

        guard let bundle = Bundle(url: record.bundleURL) else {
            throw AIPluginError.loadFailed(identifier)
        }

        if !bundle.isLoaded {
            guard bundle.load() else {
                throw AIPluginError.loadFailed(identifier)
            }
        }

        guard let principalClass = bundle.principalClass else {
            throw AIPluginError.noPrincipalClass(identifier)
        }

        guard let pluginClass = principalClass as? any AIPlugin.Type else {
            throw AIPluginError.principalClassNotPlugin(identifier)
        }

        let instance = pluginClass.init()

        loadedPlugins[identifier] = instance
        loadedBundles[identifier] = bundle
        logger.info("Loaded plugin: \(record.descriptor.displayName, privacy: .public)")

        return instance
    }

    /// Unloads a plugin instance (releases the reference).
    /// The bundle remains loaded in memory (macOS does not support unloading bundles).
    public func unloadPlugin(identifier: String) {
        loadedPlugins.removeValue(forKey: identifier)
        logger.info("Unloaded plugin: \(identifier, privacy: .public)")
    }

    // MARK: - Query

    /// Returns the descriptor for a plugin without loading it.
    public func descriptor(for identifier: String) -> AIPluginDescriptor? {
        records.first { $0.descriptor.identifier == identifier }?.descriptor
    }

    /// Returns a loaded plugin instance, or nil if not loaded.
    public func plugin(for identifier: String) -> (any AIPlugin)? {
        loadedPlugins[identifier]
    }

    #if DEBUG
    /// Test-only: inject a descriptor without an on-disk bundle so store/resolver
    /// tests need no `.aiplugin` fixtures. `loadPlugin` still fails for it (no
    /// binary), which resolver/store tests don't exercise.
    public func registerForTesting(_ descriptor: AIPluginDescriptor) {
        records.append(Record(descriptor: descriptor, bundleURL: URL(fileURLWithPath: "/dev/null")))
    }
    #endif

    // MARK: - Internal record

    /// Pairs a discovered descriptor with the bundle URL the manager needs for
    /// lazy loading.
    private struct Record {
        let descriptor: AIPluginDescriptor
        let bundleURL: URL
    }
}

// MARK: - Load result

/// One plugin's load failure: identity + a human-readable reason.
public struct PluginLoadFailure: Sendable {
    public let identifier: String
    public let displayName: String
    public let message: String
}

/// Outcome of loading every discovered plugin: what loaded, and what didn't.
public struct PluginLoadResult {
    public let loaded: [any AIPlugin]
    public let failures: [PluginLoadFailure]
}

extension AIPluginManager: Loggable {
    public static nonisolated let logger = makeLogger()
}
