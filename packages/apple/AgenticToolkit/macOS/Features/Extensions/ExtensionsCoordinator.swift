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

    /// Where an extension's reach for an unimplemented API member is
    /// recorded, held here rather than on any one `ExtensionHost` so the
    /// settings panel can read it long after the host that wrote a row was
    /// torn down. The panel reads it back through `accesses(for:)`, so a
    /// row outlives the host that wrote it.
    ///
    /// **Both `ExtensionHost.init` and `ExtensionHostInstaller.init` require
    /// the ledger by name** — neither defaults to one of its own any more,
    /// because a default is exactly how a host ends up recording into a
    /// ledger nothing reads, with nothing to say the rows were written at
    /// all. Passing this one is therefore something the compiler asks for
    /// rather than something a wiring site has to remember.
    ///
    /// The only writers are the `vscode` adaptors, which exist only inside an
    /// `ExtensionHostInstaller` — so nothing writes here until
    /// `installExtensionHosts(...)` builds one. A host that never makes that
    /// call (headless, or a test that wants the registry and the panel without
    /// running any JavaScript) sees an empty "not implemented" list, which is
    /// the truthful answer rather than a missing writer.
    public let notImplementedLedger: NotImplementedLedger

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
        self.notImplementedLedger = NotImplementedLedger()

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
        // as "it is gone" and deleting the user's themes.
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
        subscribeToContributions()
        refreshDocumentLayout()
    }

    // MARK: - The one contributions subscription

    /// Whatever was handling `registry.contributionsDidChange` before this
    /// coordinator took it over, called first on every change.
    ///
    /// The registry has room for exactly one handler, and this coordinator now
    /// has two things to do on a change — rebuild the document layout, and
    /// reconcile the extension hosts. Assigning from each of the two public
    /// entry points meant whichever ran second silently un-wired the first: the
    /// wiring site calls `maintainDocumentLayout(basedOn:)` and then
    /// `installExtensionHosts(...)`, so enabling an extension after launch
    /// brought its host up and left its view unplaceable.
    private var priorContributionsDidChange: (() -> Void)?

    /// Whether `subscribeToContributions()` has already taken the registry's
    /// handler. Guards against capturing this coordinator's *own* handler as
    /// the prior one — which a second `maintainDocumentLayout(basedOn:)` call
    /// would otherwise do, building a chain one link longer on every call.
    private var hasSubscribedToContributions = false

    /// Takes over `registry.contributionsDidChange` once, chaining whatever
    /// was there.
    private func subscribeToContributions() {
        guard !hasSubscribedToContributions else { return }
        hasSubscribedToContributions = true
        priorContributionsDidChange = registry.contributionsDidChange
        // `[weak self]`: the registry is this coordinator's own property, so a
        // strong capture is a cycle that outlives `unregister()`.
        registry.contributionsDidChange = { [weak self] in
            self?.contributionsDidChange()
        }
    }

    /// The layout first, then the hosts: a view has to be placeable before the
    /// extension that contributes it starts running, or its first render lands
    /// in a layout with no room for it. Both are no-ops for the half that is
    /// not wired, so the order costs nothing when only one is.
    private func contributionsDidChange() {
        priorContributionsDidChange?()
        refreshDocumentLayout()
        hostInstaller?.reconcile()
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

    // MARK: - Extension hosts

    /// The running extensions, or `nil` until the app calls
    /// `installExtensionHosts(...)`.
    ///
    /// Optional rather than built in `init` because a host needs five things
    /// this coordinator is constructed too early to have — the command
    /// registry, the chat model provider, and three window-shaped seams — and
    /// because a headless host (the settings panel under test, a scripting
    /// process) legitimately wants the registry, the contribution points and
    /// the panel with no JavaScript running anywhere.
    private var hostInstaller: ExtensionHostInstaller?

    /// Starts one `ExtensionHost` per enabled extension, and keeps that set in
    /// step with the registry from here on.
    ///
    /// **This is the call that first runs extension JavaScript in production.**
    /// Everything before it — loading manifests, registering contributions,
    /// widening the layout — reads what an extension *declares*. This is where
    /// its code starts executing, which is why a hardened-runtime host needs
    /// `com.apple.security.cs.allow-jit` from the same commit that adds this
    /// call. The entitlement is the app's to declare, not this framework's;
    /// see the comment on it in the app's `App.entitlements`.
    ///
    /// Idempotent in the only sense that matters: a second call is a
    /// programmer error — it would bring up a second host, a second JavaScript
    /// context and a second set of adaptors for every extension already
    /// running — so it is refused and logged rather than honoured.
    ///
    /// - Parameters:
    ///   - commandRegistry: where `vscode.commands` registers into and executes
    ///     from. The app's own registry, so a contributed command is reachable
    ///     from the palette and the menus.
    ///   - languageModelProvider: what `vscode.lm` offers. One for every host.
    ///   - frontWindow: where an alert sheet attaches, or `nil` for an app
    ///     modal alert. Read at presentation time, never captured.
    ///   - footers: every footer a status bar item renders into.
    ///   - workspaceRoots: the workspace extensions see right now, or `nil`
    ///     when no project is open. Also read through, for the same reason.
    ///   - placeWebviewPanel: where a webview panel an extension creates goes
    ///     in a window's pane tree, or `nil` when there is nowhere to put one.
    ///     Placement only — the panel arrives built.
    ///   - openDocumentLanguageIDs: the language id of every document open in
    ///     an editor right now. Read once per extension installed, to give an
    ///     extension enabled mid-session the `onLanguage:` activation whose
    ///     `.opened` event was delivered before it existed.
    public func installExtensionHosts(
        commandRegistry: CommandRegistry,
        languageModelProvider: ExtensionLanguageModelProviding,
        frontWindow: @escaping () -> NSWindow?,
        footers: @escaping () -> [WindowFooterBar],
        workspaceRoots: @escaping () -> ExtensionWorkspaceRoots?,
        placeWebviewPanel: @escaping PaneWebviewPresenter.Place,
        openDocumentLanguageIDs: @escaping () -> [String]
    ) {
        guard hostInstaller == nil else {
            logger.error("Extension hosts are already installed — ignoring a second install.")
            return
        }
        let installer = ExtensionHostInstaller(
            registry: registry,
            notImplementedLedger: notImplementedLedger,
            languagePoint: languagePoint,
            seams: ExtensionHostSeams(
                commandRegistry: commandRegistry,
                languageModelProvider: languageModelProvider,
                frontWindow: frontWindow,
                footers: footers,
                workspaceRoots: workspaceRoots,
                placeWebviewPanel: placeWebviewPanel,
                openDocumentLanguageIDs: openDocumentLanguageIDs))
        hostInstaller = installer
        subscribeToContributions()
        installer.reconcile()
    }

    /// Tells the hosts that a document of `languageID` was opened, which is
    /// what `onLanguage:<id>` activates on.
    ///
    /// Driven from the app because the store is the app's: there is exactly
    /// one `TextDocumentStore` for the process and it lives in
    /// `TextDocumentCoordinator`, a feature this coordinator knows nothing
    /// about.
    ///
    /// A no-op before `installExtensionHosts(...)`.
    public func extensionDocumentOpened(languageID: String) {
        hostInstaller?.documentDidOpen(languageID: languageID)
    }

    /// Tells every running extension that the configured chat models moved, so
    /// `vscode.lm.onDidChangeChatModels` fires.
    ///
    /// Driven from the app because the provider is the app's: it observes the
    /// user's AI provider settings, and this coordinator must not reach for
    /// them.
    public func extensionChatModelsDidChange() {
        hostInstaller?.availableChatModelsDidChange()
    }

    /// Tells the hosts that the set of open project windows moved.
    ///
    /// Two different things want this one fact, and both are behind the
    /// installer:
    ///
    ///  - the workspace scan, because the front window is where
    ///    `workspaceContains:` looks and hosts come up at launch with no
    ///    project open at all;
    ///  - the status bar presenter, because a window that opened after the
    ///    last item changed has a footer nothing has rendered into.
    ///
    /// A no-op before `installExtensionHosts(...)`, which is the state a
    /// headless host stays in.
    public func projectWindowsDidChange() {
        hostInstaller?.workspaceDidChange()
        hostInstaller?.windowsDidChange()
    }
}

extension ExtensionsCoordinator: Loggable {
    public static nonisolated let logger = makeLogger()
}
