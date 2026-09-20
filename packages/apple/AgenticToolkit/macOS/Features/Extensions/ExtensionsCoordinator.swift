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
/// The load in `init` is synchronous on the main actor by design (Ruling FN):
/// `apply` is synchronous, `loadAll()` is `@MainActor` and already reads a
/// manifest per extension there, and the whole thing runs once during feature
/// construction, before any window is on screen. Making it async would also
/// break the layout widening at the wiring site, which reads what the views
/// point registered.
///
/// **That rationale is startup's alone.** Every later rescan — installing from
/// the registry, and anything else that follows — goes through
/// `registry.reload()`, which reads the disk off this actor. A load is not a
/// cheap thing done twice: it is an enumeration, a read and a JSONC decode per
/// installed extension, followed by every contribution withdrawn and
/// re-applied and every contributions observer rebuilding the document layout
/// and reconciling every host. In a settings window the user is looking at, all of
/// that on this actor is a stopped run loop.
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

    /// The registry `viewsPoint` registers contributed panes into, kept
    /// alongside it because webview panels need the same registry and are not
    /// a contribution — a panel is created at runtime by an extension that is
    /// already running, never declared in a manifest.
    private let viewRegistry: ComposableTabsViewRegistry?

    /// Owns the one registered pane identifier every extension webview panel
    /// is laid out under, and puts panels back after a quit.
    ///
    /// Built by `installExtensionHosts(...)` rather than in `init`, and `nil`
    /// until then, because restoring a panel means handing it to the extension
    /// that claims its view type — which is a question only an
    /// `ExtensionHostInstaller` can answer. A host that never installs one has
    /// no extensions running and therefore no panels to put back.
    public private(set) var webviewPanelSerializer: WebviewPanelSerializer?

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
        self.viewRegistry = viewRegistry
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

    // MARK: - Installing from a registry

    /// Where an extension installed from inside the app lands.
    ///
    /// The **first** search path, not a path of its own. The registry scans
    /// the search paths in order and an installer writing somewhere else would
    /// produce an extension that installs and never loads. `nil` only for a
    /// host constructed with no search paths at all — headless, or a test —
    /// and the browse UI reads it as "installing is not available here"
    /// rather than inventing a directory.
    public var installDirectory: URL? { searchPaths.first }

    /// Downloads, verifies and installs `detail`, then rescans so the new
    /// extension is live without a relaunch.
    ///
    /// The rescan is a full `loadAll()`: every contribution is withdrawn and
    /// re-applied from what is on disk now. That is heavier than applying the
    /// one new extension, and it is the only version that is *correct* — an
    /// install can supersede a directory (a newer version replacing an older
    /// one), and applying the new contributions without withdrawing the old
    /// ones would leave the superseded version's themes and snippets in place
    /// with nothing left on disk to withdraw them later *(idempotency)*.
    ///
    /// The download and the archive work happen off the main actor: every
    /// method they go through is `nonisolated async`, so `await` here does not
    /// pin a multi-megabyte download and an Ed25519 verification to the actor
    /// drawing the window. The rescan that follows is the same bargain —
    /// `reload()` rather than `loadAll()`, so the manifest pass over every
    /// installed extension does not land on the actor drawing the settings
    /// window the user clicked Install in.
    public func installFromRegistry(
        _ detail: OpenVSXExtensionDetail,
        using client: OpenVSXClient
    ) async throws -> VSIXInstallation {
        guard let installDirectory else {
            throw ExtensionInstallUnavailable.noSearchPath
        }
        let installer = VSIXInstaller(
            installDirectory: installDirectory,
            hostVersion: ExtensionRegistry.declaredVSCodeVersion)
        let installation = try await installer.install(detail, using: client)
        await registry.reload()
        return installation
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

    /// Whether the installed layout carries the allowance every extension
    /// webview pane is laid out under, so a rebuild that moves no contributed
    /// view still notices that the serializer has since appeared.
    private var installedWebviewPaneAllowance = false

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
        // views are contributed, so neither record can short-circuit it.
        installedContributedViewIDs = []
        installedWebviewPaneAllowance = false
        subscribeToContributions()
        refreshDocumentLayout()
    }

    // MARK: - The one contributions subscription

    /// This coordinator's registration with the registry, if it has one.
    ///
    /// **One subscription, not one per entry point.** Both public entry points
    /// call `subscribeToContributions()` and this coordinator has two things
    /// to do on a change — rebuild the document layout, and reconcile the
    /// extension hosts — but they are ordered with respect to each other, so
    /// they belong in one handler rather than two independent observers whose
    /// order would be whichever entry point the host happened to call first.
    /// Holding the token is what keeps a second call from adding a second
    /// registration that does the same work twice.
    private var contributionsObserver: UUID?

    /// Subscribes to the registry's contribution changes, once.
    private func subscribeToContributions() {
        guard contributionsObserver == nil else { return }
        // `[weak self]`: the registry is this coordinator's own property, so a
        // strong capture is a cycle that outlives `unregister()`.
        contributionsObserver = registry.addContributionsObserver { [weak self] in
            self?.contributionsDidChange()
        }
    }

    /// The layout first, then the hosts: a view has to be placeable before the
    /// extension that contributes it starts running, or its first render lands
    /// in a layout with no room for it. Both are no-ops for the half that is
    /// not wired, so the order costs nothing when only one is.
    private func contributionsDidChange() {
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
        // The serializer registers the webview pane identifier in its `init`,
        // so its existence is exactly the question "may a pane hold a webview
        // panel yet" — before it there is nothing registered to allow, and an
        // allowance naming an unregistered view fails validation.
        let allowsWebviewPanes = webviewPanelSerializer != nil
        guard viewIDs != installedContributedViewIDs
                || allowsWebviewPanes != installedWebviewPaneAllowance else { return }
        do {
            var spec = baseDocumentLayout.spec.widened(for: views)
            if allowsWebviewPanes {
                // Unbounded and horizontal for a contributed view's reasons: a
                // panel is auxiliary, and an extension may open a second one
                // while the first is on screen.
                spec = spec.widened(
                    allowing: [.unbounded(WebviewPanelSerializer.viewID, preferredAxis: .horizontal)])
            }
            let widened = try ComposableTabsLayout(
                registry: baseDocumentLayout.registry,
                spec: spec
            )
            ComposableTabsLayout.install(widened)
            installedContributedViewIDs = viewIDs
            installedWebviewPaneAllowance = allowsWebviewPanes
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
    ///   - openDocumentLanguageIDs: the language id of every document open in
    ///     an editor right now. Read once per extension installed, to give an
    ///     extension enabled mid-session the `onLanguage:` activation whose
    ///     `.opened` event was delivered before it existed.
    ///
    /// Webview panels are **not** a parameter: where one goes is this
    /// framework's own `ExtensionWebviewPanePlacer`, and putting one back after
    /// a quit needs both the view registry this coordinator was built with and
    /// the installer this method builds. A caller that supplied the placement
    /// would be handing us back something assembled out of two things we
    /// already hold (`dry`).
    public func installExtensionHosts(
        commandRegistry: CommandRegistry,
        languageModelProvider: ExtensionLanguageModelProviding,
        frontWindow: @escaping () -> NSWindow?,
        footers: @escaping () -> [WindowFooterBar],
        workspaceRoots: @escaping () -> ExtensionWorkspaceRoots?,
        openDocumentLanguageIDs: @escaping () -> [String]
    ) {
        guard hostInstaller == nil else {
            logger.error("Extension hosts are already installed — ignoring a second install.")
            return
        }
        // Before the installer, because the installer's seams place panels
        // through it. Its own `restore` reaches back for `hostInstaller`
        // through `self` at call time, which is a turn or more later — by then
        // the assignment below has happened.
        let serializer = viewRegistry.map { registry in
            WebviewPanelSerializer(registry: registry) { [weak self] state in
                self?.hostInstaller?.restoreWebviewPanel(state: state) { roots in
                    WebviewPanelViewController(restoring: state, localResourceRoots: roots)
                }
            }
        }
        webviewPanelSerializer = serializer
        // The serializer has just registered the identifier webview panes are
        // laid out under; the spec the app installed names every pane type it
        // knew about, which cannot include this one. Widening here — before any
        // host runs, and before the first project window is restored — is what
        // keeps `ComposableTabLayoutSpec.reconcile(_:)` from demoting a stored
        // webview pane to a placeholder as the window loads.
        refreshDocumentLayout()
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
                // `nil` for a coordinator built without a view registry: a host
                // with nowhere to lay out a pane has nowhere to put a panel,
                // and `MainThreadWebviews` turns that into a JavaScript
                // exception naming the reason rather than a silent no-op.
                placeWebviewPanel: { panel in
                    guard let serializer else { return nil }
                    return ExtensionWebviewPanePlacer.place(panel, using: serializer)
                },
                openDocumentLanguageIDs: openDocumentLanguageIDs))
        hostInstaller = installer
        // The three contributed-view seams, wired here rather than at
        // construction for the serializer's reason directly above: `viewsPoint`
        // is built in `init`, and all three need the installer. Each reads
        // `hostInstaller` back through `self` at call time, which is a pane
        // build later.
        viewsPoint?.onViewWillAppear = { [weak self] view in
            self?.hostInstaller?.contributedViewWillAppear(viewID: view.viewID)
        }
        viewsPoint?.resolveWebview = { [weak self] view, didResolve in
            self?.hostInstaller?.resolveWebviewView(
                view: view,
                makePanel: { roots in
                    // `registryID` as the view type, not `viewID`: this panel
                    // is never restored through `WebviewPanelSerializer` — its
                    // pane is the manifest's, rebuilt from the manifest — so
                    // the string is read only by people, in logs, where the
                    // namespaced form is the one that says which extension it
                    // belongs to.
                    WebviewPanelViewController(
                        viewType: view.registryID,
                        title: view.name,
                        // What the provider will overwrite from inside its
                        // `resolveWebviewView`, and the only safe starting
                        // point: scripts off until an extension says its page
                        // runs code.
                        options: WebviewPanelOptions(
                            enableScripts: nil, enableForms: nil, localResourceRoots: nil),
                        localResourceRoots: roots)
                },
                didResolve: didResolve)
        }
        viewsPoint?.resolveTree = { [weak self] view, didResolve in
            self?.hostInstaller?.resolveTreeView(view: view, didResolve: didResolve)
        }
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

/// Why installing from a registry is not possible at all, as distinct from an
/// install that was tried and failed.
///
/// Separate from `VSIXInstallError` on purpose: every case there describes a
/// particular extension that could not be installed, and a UI showing one
/// beside a Retry button is right to. This is the other kind — nothing about
/// the extension is wrong and retrying it changes nothing.
public enum ExtensionInstallUnavailable: Error, Sendable, Equatable {
    /// This host was built with no extension search paths, so there is nowhere
    /// an installed extension could be found again.
    case noSearchPath
}
