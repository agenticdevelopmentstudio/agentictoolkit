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
        //
        // `establishedIdentifiers` is Optional and passed straight through: a
        // scan that could not name every directory it looked at prunes
        // nothing at all, rather than reading "its manifest would not parse"
        // as "it is gone" and deleting the user's themes (I1/I2).
        themePoint.pruneOrphans(installedIdentifiers: registry.establishedIdentifiers)
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

    // MARK: - Document layout

    /// The layout the widened one is always derived from — never the installed
    /// layout, which is a *result* of this and would compound.
    private var baseDocumentLayout: ComposableTabsLayout?

    /// The view ids the currently installed layout was widened for, so a change
    /// that moves no view — a disable of an extension contributing only themes,
    /// a `loadAll()` that found the same set — reinstalls nothing.
    private var installedContributedViewIDs: [String] = []

    /// Keeps the installed document layout in step with the views extensions
    /// contribute, for as long as this coordinator lives.
    ///
    /// Registering a view does not make it reachable:
    /// `ComposableTabLayoutSpec.validate(against:)` only checks that the ids a
    /// spec *names* are registered, never the reverse, so a contributed view no
    /// allowance mentions is registered and unplaceable. Widening once at
    /// launch covered only the extensions enabled at launch — enabling one
    /// afterwards registered its view into a layout with no room for it, and
    /// the user saw nothing until the app was restarted.
    ///
    /// `base` is the layout the host installed *before* any extension was
    /// widened in, and every rebuild starts from it again.
    /// `ComposableTabLayoutSpec.widened(for:)` **appends**, so re-widening the
    /// installed layout would add a second allowance for every view on every
    /// change; worse, a disable leaves the withdrawn view's allowance naming an
    /// id no longer in the registry, and the next widening throws
    /// `.unregisteredView` — from then on the catch below keeps the broken
    /// layout installed forever. Deriving from `base` makes every rebuild total
    /// rather than incremental, which is what lets a withdrawal shrink the spec
    /// at all.
    ///
    /// Passing `nil` (a headless host, or a wiring site with no layout yet)
    /// subscribes to nothing: there is no spec to widen and no base to hold.
    public func maintainDocumentLayout(basedOn base: ComposableTabsLayout?) {
        guard let base else { return }
        baseDocumentLayout = base
        // A second call with a different base has to rebuild even if the same
        // views are contributed, so the recorded set cannot short-circuit it.
        installedContributedViewIDs = []
        // `[weak self]`: the registry is this coordinator's own property, so a
        // strong capture is a cycle that outlives `unregister()`.
        registry.contributionsDidChange = { [weak self] in
            self?.refreshDocumentLayout()
        }
        refreshDocumentLayout()
    }

    /// Rebuilds the installed layout from the base one and what is contributed
    /// now. A throw leaves whatever is installed in place — a bad extension
    /// must not cost the user their file browser — and deliberately does not
    /// record the view set, so the next change retries rather than treating the
    /// failed widening as the installed state.
    private func refreshDocumentLayout() {
        guard let baseDocumentLayout else { return }
        let views = contributedViews
        let viewIDs = views.map(\.registryID)
        guard viewIDs != installedContributedViewIDs else { return }
        do {
            let widened = try ComposableTabsLayout(
                registry: baseDocumentLayout.registry,
                spec: baseDocumentLayout.spec.widened(for: views)
            )
            ComposableTabsLayout.install(widened)
            installedContributedViewIDs = viewIDs
        } catch {
            logger.error(
                """
                Extension views left unplaceable — the widened layout did not \
                validate: \(error.localizedDescription, privacy: .public)
                """
            )
        }
    }
}

extension ExtensionsCoordinator: Loggable {
    public static nonisolated let logger = makeLogger()
}
