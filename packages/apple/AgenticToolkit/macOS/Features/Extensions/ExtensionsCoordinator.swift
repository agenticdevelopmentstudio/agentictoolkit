//
//  ExtensionsCoordinator.swift
//  AgenticToolkit
//

import AppKit
import Foundation
import OSLog

import AgenticToolkitCore
import AgenticToolkitLanguage

/// Brings the VS Code extension subsystem up: one `ExtensionRegistry`, the five
/// contribution points that consume what it loads, and the settings panel that
/// shows the result.
///
/// The order in `init` is the whole contract — every point is registered, then
/// `loadAll()` runs, then orphaned themes are pruned. `ExtensionRegistry` does
/// not replay past extensions against a point registered afterwards, so a point
/// registered late silently receives nothing.
///
/// The load is synchronous on the main actor by design (Ruling FN): `apply` is
/// synchronous, `loadAll()` is `@MainActor` and already reads a manifest per
/// extension there, and the whole thing runs once during feature construction,
/// before any window is on screen. Making it async would also break the layout
/// widening at the wiring site, which reads what the views point registered.
@MainActor
public final class ExtensionsCoordinator: AppFeature {

    public let registry: ExtensionRegistry

    /// Where extensions were looked for. `ExtensionRegistry` keeps its own copy
    /// private, and the panel's empty state has to name these paths — telling a
    /// user with no extensions where to put one is the whole of that state.
    public let searchPaths: [URL]

    /// The points, held by identity because that is how the registry keeps them
    /// — and because the settings panel reaches through them for the per
    /// extension settings panel, view list and diagnostics.
    public let themePoint: ThemeContributionPoint
    public let snippetStore: SnippetStore
    public let languagePoint: LanguageContributionPoint
    public let configurationPoint: ConfigurationContributionPoint
    /// `nil` when the host has no tabs registry to register panes into — a
    /// headless host, or a wiring site that runs before the layout is
    /// installed. The other four points do not depend on the window layout.
    public let viewsPoint: ViewsContributionPoint?

    public init(
        searchPaths: [URL],
        themeStore: ThemeStore,
        viewRegistry: ComposableTabsViewRegistry?
    ) {
        self.searchPaths = searchPaths
        self.registry = ExtensionRegistry(
            searchPaths: searchPaths,
            hostVersion: ExtensionRegistry.declaredVSCodeVersion
        )
        self.themePoint = ThemeContributionPoint(themeStore: themeStore)
        self.snippetStore = SnippetStore()
        self.languagePoint = LanguageContributionPoint()
        self.configurationPoint = ConfigurationContributionPoint()
        self.viewsPoint = viewRegistry.map { ViewsContributionPoint(registry: $0) }

        super.init()

        registry.register(themePoint)
        registry.register(snippetStore)
        registry.register(languagePoint)
        registry.register(configurationPoint)
        if let viewsPoint {
            registry.register(viewsPoint)
        }

        // Registering the languages point makes it *receive* contributions;
        // nothing *reads* them until it publishes its table into the static
        // `CustomFileTypeMappings` provider, which is what `install()` does.
        // Miss it and every language contribution is parsed, stored and shown
        // in the panel while not one file in the tree changes its icon — no
        // error, no log line. Before `loadAll()` so that all wiring precedes
        // the load, with no exception to remember.
        languagePoint.install()

        registry.loadAll()

        // An extension deleted while the app was closed never gets a
        // `withdraw`, so its themes would outlive it forever. Reconciling once
        // against what actually loaded is the only mechanism that can see a
        // change made while the process was dead.
        themePoint.pruneOrphans(
            installedIdentifiers: Set(registry.extensions.map(\.identifier))
        )
    }

    public func settingsPanel() -> ExtensionsSettingsPanelViewController {
        ExtensionsSettingsPanelViewController(coordinator: self)
    }

    /// Every view the extensions registered, across every loaded extension.
    ///
    /// Registration alone puts nothing in front of the user: a spec's `allows`
    /// has to name the view too. This is what the wiring site widens the spec
    /// with.
    public var contributedViews: [ContributedView] {
        guard let viewsPoint else { return [] }
        return registry.extensions.flatMap { viewsPoint.views(for: $0.identifier) }
    }
}

extension ExtensionsCoordinator: Loggable {
    public static nonisolated let logger = makeLogger()
}
