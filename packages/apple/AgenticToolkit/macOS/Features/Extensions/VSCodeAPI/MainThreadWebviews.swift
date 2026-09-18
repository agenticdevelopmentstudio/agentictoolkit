//
//  MainThreadWebviews.swift
//  AgenticToolkit
//

import Foundation
import JavaScriptCore
import os
import AgenticToolkitCore

// MARK: - One live panel

/// Everything the host keeps about one panel an extension created.
///
/// The per-object model `MainThreadWindow.ExtensionStatusBarItem` is for a
/// status bar item, and held the same way: `MainThreadWebviews.panels` is the
/// only strong reference, every block the JS panel object carries captures this
/// **weakly**, and dropping it from that dictionary is what makes all of them
/// go inert at once.
///
/// It is not the panel itself. The panel is a view controller in a pane; this
/// is the extension-facing bookkeeping beside it — the two emitters, the view
/// type the panel was created under, and whether it has been disposed.
@MainActor
private final class ExtensionWebviewPanelModel {

    /// The panel on screen.
    let panel: any ExtensionWebviewPanel

    /// What `createWebviewPanel` was called with. Kept here rather than added
    /// to `ExtensionWebviewPanel`, because nothing that *presents* a panel
    /// needs to read its view type back — only this adaptor does, to answer
    /// `panel.viewType`.
    let viewType: String

    /// `webview.onDidReceiveMessage` (`vscode.d.ts:11700`).
    let messages: ExtensionEventEmitter<Any>

    /// `panel.onDidDispose` (`vscode.d.ts:11934`).
    let disposal: ExtensionEventEmitter<Void>

    /// `panel.onDidChangeViewState` (`vscode.d.ts:11929`).
    ///
    /// Real, subscribable, and **never fired**: a pane in this app does not yet
    /// report becoming visible or active, so there is no change to publish.
    /// Present rather than absent because an extension that writes
    /// `panel.onDidChangeViewState(…)` against a missing member gets a
    /// `TypeError` at activation and never renders anything at all — a far
    /// worse answer than an event that stays quiet. `MainThreadWebviews`
    /// records a `NotImplementedLedger` row the first time anyone subscribes,
    /// so the extension report says which extension is waiting on it.
    let viewStateChanges: ExtensionEventEmitter<Void>

    private(set) var isDisposed = false

    init(panel: any ExtensionWebviewPanel, viewType: String) {
        self.panel = panel
        self.viewType = viewType
        self.messages = ExtensionEventEmitter<Any>(
            path: "vscode.Webview.onDidReceiveMessage",
            delay: 0,
            window: ExtensionEventImmediateWindow(),
            // Unreachable in practice: a zero-delay immediate window closes
            // inside the `fire` that opened it, and `fire` queues its payload
            // first, so the queue this merges holds exactly one element. The
            // emitter also never calls `merge` on an empty queue
            // (`event.ts:1568`'s guard, behaviour 4 in its own doc), so the
            // fallback below is the branch that cannot be taken — spelled
            // rather than forced, because a message is the one payload here
            // that carries the extension's data and a trap would take the app
            // down with it.
            merge: { $0.last ?? NSNull() },
            map: { payload, context in JSValue(object: payload, in: context) })
        self.disposal = ExtensionEventEmitter<Void>(
            path: "vscode.WebviewPanel.onDidDispose",
            delay: 0,
            window: ExtensionEventImmediateWindow(),
            merge: { _ in () },
            map: { _, context in JSValue(undefinedIn: context) })
        self.viewStateChanges = ExtensionEventEmitter<Void>(
            path: "vscode.WebviewPanel.onDidChangeViewState",
            delay: 0,
            window: ExtensionEventImmediateWindow(),
            merge: { _ in () },
            map: { _, context in JSValue(undefinedIn: context) })
    }

    func markDisposed() {
        isDisposed = true
    }

    /// Drops every listener this model's emitters hold, which is what releases
    /// the extension's `JSContext` — see `ExtensionEventEmitter`'s own
    /// "Lifetime" section.
    func removeListeners() {
        messages.removeListeners(ownedBy: self)
        disposal.removeListeners(ownedBy: self)
        viewStateChanges.removeListeners(ownedBy: self)
    }
}

// MARK: - vscode.window.createWebviewPanel

/// Installs `vscode.window.createWebviewPanel` (`vscode.d.ts:12525`) and the
/// `vscode.WebviewPanel` objects it hands back (`:11890-11945`), with the
/// `vscode.Webview` inside each (`:11660-11712`).
///
/// **A sixth adaptor rather than more of `MainThreadWindow`.** The member is
/// installed under `vscode.window`, but the precedent for where it *lives* is
/// `MainThreadDiagnostics`, whose members are installed under
/// `vscode.languages`: a namespace is a JavaScript address, not a Swift type
/// boundary. What decides the boundary is the seam — this is the only adaptor
/// that needs somewhere to *put a view*, so it is the only one that takes a
/// presenter that can open a pane, an extension directory, and the workspace
/// roots. Folding those three into `MainThreadWindow` would hand every message
/// box and quick pick a pane tree it has no use for (`srp`), on top of a class
/// that is already two thousand lines.
///
/// `@MainActor`, like every adaptor here: `JSValue` is not `Sendable`, and
/// JavaScriptCore calls these blocks on the thread that made the call.
@MainActor
public final class MainThreadWebviews {

    /// Read back in the torn-down message, and by
    /// `ExtensionHostInstaller.installVSCodeMembers()`.
    public static let createWebviewPanelMemberPath = "vscode.window.createWebviewPanel"

    /// `vscode.window.registerWebviewPanelSerializer` (`vscode.d.ts:12552`).
    public static let registerWebviewPanelSerializerMemberPath =
        "vscode.window.registerWebviewPanelSerializer"

    private let presenter: any ExtensionWebviewPresenting
    private let notImplementedLedger: NotImplementedLedger
    private let extensionIdentifier: String

    /// Where the owning extension is installed — the first of
    /// `WebviewPanelOptions.resourceRoots(extensionDirectory:workspaceRoots:)`'s
    /// two inputs, and the reason this adaptor is built per extension rather
    /// than shared.
    private let extensionDirectory: URL

    /// The open workspace folders, read on **every** `createWebviewPanel` call
    /// rather than snapshotted — `MainThreadWorkspace` holds its own for the
    /// same reason, stated at its `workspaceRoots` property: a project opened
    /// after an extension activated is still a root a panel created afterwards
    /// should be able to read from.
    private let workspaceRoots: (any ExtensionWorkspaceRoots)?

    /// The sole strong reference to every live panel model, keyed by panel id.
    ///
    /// `MainThreadWindow.statusBarItems`' role exactly: the blocks on each JS
    /// panel object capture their model weakly, so removing the entry is what
    /// makes a disposed panel's JavaScript surface go quiet, with no flag for
    /// each block to check.
    private var panels: [String: ExtensionWebviewPanelModel] = [:]

    /// One live `registerWebviewPanelSerializer` registration.
    ///
    /// The token is what makes the returned `Disposable` specific: an
    /// extension that registers, disposes, and registers again for the same
    /// view type must not have its *second* registration torn out by the
    /// first `Disposable` — the same distinction
    /// `MainThreadCommands.makeDisposable(id:token:in:)` draws.
    ///
    /// The serializer object is held whole rather than its
    /// `deserializeWebviewPanel` function: upstream reads the method off the
    /// object at call time (`mainThreadWebviewPanels.ts`), so an extension
    /// that swaps the method afterwards gets the method it is using now, and
    /// `this` is the object it was written to expect.
    private struct SerializerRegistration {
        let token: UUID
        let serializer: JSValue
    }

    /// Serializers by view type. A Swift-side table rather than anything
    /// stored on a `JSValue`, for `ExtensionEvent`'s reason: the adaptor is
    /// what outlives a single call, and a registration that lived in the
    /// context would be a reference cycle through JavaScriptCore.
    private var serializers: [String: SerializerRegistration] = [:]

    private var isDisposed = false

    /// - Parameters:
    ///   - presenter: Where a created panel is actually put on screen.
    ///   - notImplementedLedger: Mirrors `MainThreadWindow.init`'s — the
    ///     shapes this host takes only part of are recorded here, and the
    ///     Stage 5.8 report reads them back.
    ///   - extensionIdentifier: Who is asking, for the ledger rows and the log.
    ///   - extensionDirectory: Where that extension is installed.
    ///   - workspaceRoots: The open workspace, or `nil` when there is none.
    ///     Held strongly, as `MainThreadWorkspace` holds it: the conformer the
    ///     installer builds is a `ClosureWorkspaceRoots` owned by the
    ///     extension's own collaborators, and a weak reference here would
    ///     outlive nothing but would nil itself out if that changed.
    public init(
        presenter: any ExtensionWebviewPresenting,
        notImplementedLedger: NotImplementedLedger,
        extensionIdentifier: String,
        extensionDirectory: URL,
        workspaceRoots: (any ExtensionWorkspaceRoots)?
    ) {
        self.presenter = presenter
        self.notImplementedLedger = notImplementedLedger
        self.extensionIdentifier = extensionIdentifier
        self.extensionDirectory = extensionDirectory
        self.workspaceRoots = workspaceRoots
    }

    /// `.raisedException` rather than `.rejectedPromise`: `createWebviewPanel`
    /// returns a `WebviewPanel` synchronously (`vscode.d.ts:12525`), so a
    /// failure has to be a throw the extension's own `try` can see — a
    /// rejected promise here would be pushed onto `context.subscriptions` as
    /// a thenable nothing awaits.
    public private(set) lazy var createWebviewPanel: Any = VSCodeAPI.member(
        MainThreadWebviews.createWebviewPanelMemberPath,
        of: self,
        whenTornDown: .raisedException
    ) { $0.handleCreateWebviewPanel() }

    /// `.raisedException` for `createWebviewPanel`'s reason: this returns a
    /// `Disposable` synchronously (`vscode.d.ts:12552`), and an extension's
    /// `activate` pushes it onto `context.subscriptions` on the next line.
    public private(set) lazy var registerWebviewPanelSerializer: Any = VSCodeAPI.member(
        MainThreadWebviews.registerWebviewPanelSerializerMemberPath,
        of: self,
        whenTornDown: .raisedException
    ) { $0.handleRegisterWebviewPanelSerializer() }

    // MARK: - Creating a panel

    /// The directories a panel of this extension's may read files from.
    ///
    /// Public because a *restored* panel is built outside this adaptor — by
    /// `ExtensionHostInstaller`, from a `WebviewPanelState` — and resolving the
    /// declared roots needs the extension's own directory and the open
    /// workspace, which is knowledge this object holds and the installer does
    /// not (`dry`: the creation path below calls this same method).
    public func resourceRoots(for options: WebviewPanelOptions) -> [URL] {
        options.resourceRoots(
            extensionDirectory: extensionDirectory,
            workspaceRoots: workspaceRoots?.workspaceRootURLs ?? [])
    }

    private func handleCreateWebviewPanel() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let path = MainThreadWebviews.createWebviewPanelMemberPath
        guard !isDisposed else {
            return VSCodeAPI.raise(
                "\(path) is unavailable: this extension's host has been torn down.", in: context)
        }

        let arguments = VSCodeAPI.currentArguments()
        guard let viewTypeArgument = arguments.first, viewTypeArgument.isString,
              let viewType = viewTypeArgument.toString()
        else {
            return VSCodeAPI.raise("\(path)'s first argument must be a view type string.", in: context)
        }
        guard arguments.count > 1, arguments[1].isString, let title = arguments[1].toString() else {
            return VSCodeAPI.raise("\(path)'s second argument must be a title string.", in: context)
        }

        let preserveFocus = MainThreadWebviews.parsePreserveFocus(
            arguments.count > 2 ? arguments[2] : nil)
        let options = parseOptions(arguments.count > 3 ? arguments[3] : nil, in: context)

        let request = ExtensionWebviewPanelRequest(
            viewType: viewType,
            title: title,
            options: options,
            localResourceRoots: resourceRoots(for: options),
            preserveFocus: preserveFocus,
            extensionIdentifier: extensionIdentifier)

        guard let panel = presenter.presentWebviewPanel(request) else {
            Self.logger.error(
                """
                \(self.extensionIdentifier, privacy: .public) asked for a webview panel of type \
                \(viewType, privacy: .public), but there is no window to put it in
                """)
            return VSCodeAPI.raise(
                """
                \(path) could not open a panel for view type '\(viewType)': this app's windows \
                belong to open projects, and none is open.
                """,
                in: context)
        }

        let model = ExtensionWebviewPanelModel(panel: panel, viewType: viewType)
        panels[panel.panelID] = model
        wire(model)
        return MainThreadWebviews.makePanelObject(for: model, of: self, in: context)
    }

    /// Points the panel's two host-side callbacks at this model's emitters.
    ///
    /// Both closures capture the model weakly and the panel id **by copy**:
    /// `forget(_:)` below drops the dictionary's reference, which is the model's
    /// last one, so reading `model.panel.panelID` after that line would be
    /// reading through a reference that has just gone.
    private func wire(_ model: ExtensionWebviewPanelModel) {
        let panelID = model.panel.panelID
        model.panel.onDidReceiveMessage = { [weak model] body in
            model?.messages.fire(body)
        }
        model.panel.onDidDispose = { [weak self, weak model] in
            model?.markDisposed()
            // Fired *before* the model is forgotten: the emitter's window
            // closes inside this call, so the extension's own `onDidDispose`
            // listeners run while their registrations are still alive.
            model?.disposal.fire(())
            self?.forget(panelID)
        }
    }

    /// Drops the host's last reference to a panel, which is what makes every
    /// block on its JavaScript object inert.
    private func forget(_ panelID: String) {
        guard let model = panels.removeValue(forKey: panelID) else { return }
        model.removeListeners()
    }

    // MARK: - Restoring a panel

    private func handleRegisterWebviewPanelSerializer() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let path = MainThreadWebviews.registerWebviewPanelSerializerMemberPath
        guard !isDisposed else {
            return VSCodeAPI.raise(
                "\(path) is unavailable: this extension's host has been torn down.", in: context)
        }

        let arguments = VSCodeAPI.currentArguments()
        guard let viewTypeArgument = arguments.first, viewTypeArgument.isString,
              let viewType = viewTypeArgument.toString()
        else {
            return VSCodeAPI.raise("\(path)'s first argument must be a view type string.", in: context)
        }
        // The *method* is what gets called, so it is what is checked for —
        // `isObject` is true of `{}`, and an extension that mistyped the name
        // would otherwise register successfully and restore nothing, months
        // later, with no error anywhere (`fail-fast`).
        let serializer: JSValue? = arguments.count > 1 ? arguments[1] : nil
        guard let serializer, serializer.isObject,
              MainThreadWebviews.isFunction(
                serializer.forProperty("deserializeWebviewPanel"), in: context)
        else {
            return VSCodeAPI.raise(
                """
                \(path)'s second argument must be an object with a \
                deserializeWebviewPanel(panel, state) method.
                """,
                in: context)
        }

        // Last registration wins, as upstream's map assignment does, but it is
        // logged: two serializers for one view type is a bug in an extension
        // that nothing else would ever tell its author about.
        if serializers[viewType] != nil {
            Self.logger.error(
                """
                \(self.extensionIdentifier, privacy: .public) registered a second webview panel \
                serializer for view type \(viewType, privacy: .public); the later one wins
                """)
        }
        let token = UUID()
        serializers[viewType] = SerializerRegistration(token: token, serializer: serializer)

        return VSCodeAPI.disposable(in: context) { [weak self] in
            guard let self, self.serializers[viewType]?.token == token else { return }
            self.serializers.removeValue(forKey: viewType)
        }
    }

    /// Whether this extension has claimed `viewType` by registering a
    /// serializer for it.
    ///
    /// Asked by `ExtensionHostInstallation` *after* activating the extension:
    /// a serializer is registered from `activate`, so before that the honest
    /// answer for every awake-on-demand extension is "no."
    public func hasSerializer(for viewType: String) -> Bool {
        !isDisposed && serializers[viewType] != nil
    }

    /// Hands a restored panel to the extension that registered a serializer
    /// for its view type, and adopts it as a live panel of this adaptor's.
    ///
    /// The panel is already on screen and blank when this is called — the pane
    /// tree rebuilt it from what the project stored — so this is the moment its
    /// extension gets to put its page back. Everything after adoption is
    /// indistinguishable from a panel the extension created itself: the same
    /// model, the same wiring, the same JS object.
    ///
    /// - Returns: `false` when there is no serializer for the view type, or
    ///   when the registering context is gone — in which case the caller still
    ///   has a blank pane, and the log says why.
    @discardableResult
    public func restore(
        _ panel: any ExtensionWebviewPanel, viewType: String, state: String?
    ) -> Bool {
        guard !isDisposed, let registration = serializers[viewType] else { return false }
        guard let context = registration.serializer.context,
              let deserialize = registration.serializer.forProperty("deserializeWebviewPanel"),
              MainThreadWebviews.isFunction(deserialize, in: context)
        else {
            Self.logger.error(
                """
                \(self.extensionIdentifier, privacy: .public) has a serializer for view type \
                \(viewType, privacy: .public) but no deserializeWebviewPanel to call
                """)
            return false
        }

        let model = ExtensionWebviewPanelModel(panel: panel, viewType: viewType)
        panels[panel.panelID] = model
        wire(model)
        guard let panelObject = MainThreadWebviews.makePanelObject(for: model, of: self, in: context)
        else {
            Self.logger.error(
                """
                A restored panel of view type \(viewType, privacy: .public) could not be given a \
                JavaScript object; it stays blank
                """)
            return false
        }

        let stateValue = MainThreadWebviews.restoredStateValue(state, in: context)
        switch VSCodeAPI.call(deserialize, thisArg: registration.serializer,
                              arguments: [panelObject, stateValue]) {
        case .returned:
            return true
        case .threw(let error):
            Self.logger.error(
                """
                \(self.extensionIdentifier, privacy: .public)'s deserializeWebviewPanel threw for \
                view type \(viewType, privacy: .public): \
                \(error.toString() ?? "<unprintable>", privacy: .public)
                """)
            return false
        case .unavailable:
            Self.logger.error(
                """
                \(self.extensionIdentifier, privacy: .public)'s deserializeWebviewPanel could not \
                be invoked for view type \(viewType, privacy: .public)
                """)
            return false
        }
    }

    /// The saved state as the value `deserializeWebviewPanel` receives.
    ///
    /// Parsed here rather than by the page's `JSON.parse`, because handing the
    /// context a string it has to parse would set `context.exception` on a
    /// corrupted entry — an exception belonging to no call, which the next
    /// unrelated call would see. `.fragmentsAllowed` for
    /// `WebviewPanelViewController.jsonText(of:)`'s reason: `setState(42)` is
    /// a thing a page may do, so `42` is a thing this may have to read back.
    private static func restoredStateValue(_ state: String?, in context: JSContext) -> Any {
        guard let state,
              let object = try? JSONSerialization.jsonObject(
                with: Data(state.utf8), options: [.fragmentsAllowed])
        else {
            // `undefined`, which is what upstream passes a panel that never
            // called `setState` — and `null` would not be the same answer: an
            // extension's `state ?? defaults` reads both, but `if (state ===
            // undefined)` does not.
            return JSValue(undefinedIn: context) as Any
        }
        return object
    }

    /// `x instanceof Function`, the check `MainThreadCommands` makes of a
    /// callback: `isObject` is true of `{}`, so it cannot stand in.
    private static func isFunction(_ value: JSValue?, in context: JSContext) -> Bool {
        guard let value, let functionConstructor = context.objectForKeyedSubscript("Function") else {
            return false
        }
        return value.isInstance(of: functionConstructor)
    }

    // MARK: - Reading the arguments

    /// `showOptions`, which is `ViewColumn | { viewColumn, preserveFocus }`
    /// (`vscode.d.ts:12529`).
    ///
    /// Only `preserveFocus` is read. A `ViewColumn` numbers an editor group in
    /// a row of them, and this app's panes are a tree the user splits where
    /// they like — there is no column for a number to select, so a full enum
    /// would be a field nothing could ever read (`yagni`). The column is a
    /// *degraded argument*, not an absent member, so it gets this doc comment
    /// and no `NotImplementedLedger` row — see `MainThreadWindow`'s own
    /// statement of that rule, and `ExtensionWebviewPanelRequest.preserveFocus`.
    private static func parsePreserveFocus(_ value: JSValue?) -> Bool {
        guard let value, value.isObject, let field = value.forProperty("preserveFocus") else {
            return false
        }
        return field.isBoolean && field.toBool()
    }

    /// `WebviewPanelOptions & WebviewOptions` (`vscode.d.ts:12531`), reduced to
    /// the three fields this host honours.
    ///
    /// The five it does not are not all the same kind of absence, so they are
    /// not answered the same way. `retainContextWhenHidden` is already true of
    /// every pane here and `enableFindWidget` names a widget that does not
    /// exist, so both are silent — see `WebviewPanelOptions`' own doc for why
    /// each is missing. `enableCommandUris` and `portMapping` are real
    /// capabilities that are simply not built, and an extension that asked for
    /// either gets a ledger row naming the shape, on
    /// `vscode.StatusBarItem.tooltip: MarkdownString`'s precedent: the row says
    /// "this host takes only part of this member", which is what the Stage 5.8
    /// report needs to stay honest.
    ///
    /// A row is recorded only when the option was actually asked *for*.
    /// `enableCommandUris: false` is the state this host is already in, and
    /// reporting it would tell a user their extension wants something it
    /// explicitly declined.
    private func parseOptions(_ value: JSValue?, in context: JSContext) -> WebviewPanelOptions {
        guard let value, value.isObject else {
            return WebviewPanelOptions(enableScripts: nil, enableForms: nil, localResourceRoots: nil)
        }

        if Self.isTruthyFlag(value.forProperty("enableCommandUris")) {
            notImplementedLedger.record(
                memberPath: "vscode.WebviewOptions.enableCommandUris",
                extensionIdentifier: extensionIdentifier)
        }
        if let portMapping = value.forProperty("portMapping"),
           let count = VSCodeAPI.arrayLength(of: portMapping), count > 0 {
            notImplementedLedger.record(
                memberPath: "vscode.WebviewOptions.portMapping",
                extensionIdentifier: extensionIdentifier)
        }

        return WebviewPanelOptions(
            enableScripts: Self.booleanField(value.forProperty("enableScripts")),
            enableForms: Self.booleanField(value.forProperty("enableForms")),
            localResourceRoots: Self.resourceRootsField(
                value.forProperty("localResourceRoots"), in: context))
    }

    /// A `boolean | undefined` option as written, so
    /// `WebviewPanelOptions.init` can tell an absent option from an explicit
    /// `false` — which is the whole reason its parameters are optional.
    /// Anything that is not a boolean is treated as absent rather than coerced
    /// the way JavaScript's own `!!` would: guessing at `enableScripts: "yes"`
    /// would turn a typo into a capability.
    private static func booleanField(_ value: JSValue?) -> Bool? {
        guard let value, value.isBoolean else { return nil }
        return value.toBool()
    }

    /// True only for a boolean `true` — for options this host reads to decide
    /// whether to record a ledger row, where the question is "did the
    /// extension ask for this?" and nothing else.
    private static func isTruthyFlag(_ value: JSValue?) -> Bool {
        guard let value, value.isBoolean else { return false }
        return value.toBool()
    }

    /// `localResourceRoots: readonly Uri[] | undefined` (`vscode.d.ts:11640`).
    ///
    /// `nil` when the option was absent and `[]` when it was written empty:
    /// `WebviewPanelOptions` treats those as different answers on purpose, so
    /// collapsing them here would undo the distinction one layer above.
    ///
    /// An entry that is not a `Uri` this bridge can read is **dropped**, not
    /// substituted. Every root is a grant of file access, and inventing one
    /// from a value the host could not parse is the one mistake in this
    /// function that has a security consequence.
    private static func resourceRootsField(_ value: JSValue?, in context: JSContext) -> [URL]? {
        guard let value, !value.isUndefined, !value.isNull else { return nil }
        guard let count = VSCodeAPI.arrayLength(of: value) else { return nil }
        return (0..<count).compactMap { index in
            guard let element = value.atIndex(index) else { return nil }
            return VSCodeAPI.url(from: element, in: context)
        }
    }

    // MARK: - The WebviewPanel object

    /// Builds the JS-visible `WebviewPanel` for `model`.
    ///
    /// **No-capture evidence, one sentence per block kind installed here** —
    /// `makeStatusBarItemObject`'s own contract, which this follows:
    /// - Every getter, setter and method block captures `model` and `webviews`
    ///   **weakly**, and `viewType`/`panelID` by copy, so nothing a
    ///   `JSContext` can reach retains either object.
    /// - `onDidDispose` and `onDidChangeViewState` hand their listener
    ///   `JSValue`s to an `ExtensionEventEmitter` owned by `model`, which is
    ///   owned by `webviews.panels` — the one direction the reference runs, and
    ///   what `forget(_:)` breaks.
    /// - Nothing here stores a `JSValue` or a `JSContext` on `model`. That is
    ///   why `webview` builds a fresh object on every access (see its own note)
    ///   rather than caching one.
    private static func makePanelObject(
        for model: ExtensionWebviewPanelModel,
        of webviews: MainThreadWebviews,
        in context: JSContext
    ) -> JSValue? {
        guard let object = JSValue(newObjectIn: context) else { return nil }

        installReadonlyGetter(on: object, name: "viewType") { [weak model] in model?.viewType }

        installAccessor(on: object, name: "title",
            get: { [weak model] in model?.panel.panelTitle },
            set: { [weak model] value in
                guard let model, let value, value.isString, let string = value.toString() else {
                    return
                }
                model.panel.panelTitle = string
            })

        // A fresh `Webview` object each access, rather than one cached on the
        // model. Caching would mean storing a `JSValue` — and so its
        // `JSContext` — on an object this adaptor owns, which is the one thing
        // `makeStatusBarItemObject`'s no-capture contract rules out; the
        // extension's context would then live exactly as long as the panel.
        // Every member of the object below reads through to `model`, so two
        // wrappers behave identically; the single observable difference is that
        // `panel.webview !== panel.webview`, and nothing in the `vscode` API
        // asks that question.
        installReadonlyGetter(on: object, name: "webview") { [weak model] in
            guard let model, let context = JSContext.current() else { return nil }
            return makeWebviewObject(for: model, in: context)
        }

        // `vscode.d.ts:11905` — the options the *panel* was created with, as
        // opposed to the webview's. Both of this host's answers are fixed:
        // a pane keeps its view controller whether or not it is the visible
        // tab, and there is no find widget. See `WebviewPanelOptions`.
        installReadonlyGetter(on: object, name: "options") {
            guard let context = JSContext.current(), let options = JSValue(newObjectIn: context) else {
                return nil
            }
            options.setObject(true, forKeyedSubscript: "retainContextWhenHidden" as NSString)
            options.setObject(false, forKeyedSubscript: "enableFindWidget" as NSString)
            return options
        }

        // `vscode.d.ts:11899`. Pane chrome here shows a title, not an icon, so
        // there is nowhere for this to go. An accessor pair rather than
        // nothing at all: a plain JS object accepts `panel.iconPath = …`
        // silently, and a silent drop is the one outcome the ledger exists to
        // prevent.
        installAccessor(on: object, name: "iconPath",
            get: { JSContext.current().map { JSValueBridge.undefinedOrNull(in: $0) } },
            set: { [weak webviews] value in
                guard let webviews, let value, !value.isUndefined, !value.isNull else { return }
                webviews.notImplementedLedger.record(
                    memberPath: "vscode.WebviewPanel.iconPath",
                    extensionIdentifier: webviews.extensionIdentifier)
            })

        // `vscode.d.ts:11911`. There are no view columns here — see
        // `parsePreserveFocus`. `undefined` is a value `vscode.d.ts` already
        // permits for this property, so an extension that reads it finds an
        // answer its own types allow rather than a missing member.
        installReadonlyGetter(on: object, name: "viewColumn") {
            JSContext.current().map { JSValueBridge.undefinedOrNull(in: $0) }
        }

        // `vscode.d.ts:11916`/`:11922`. A pane keeps its panel alive whether or
        // not it is the frontmost tab, and nothing yet reports when that
        // changes — so both answer "yes, until disposed", which is true of
        // `visible` in the sense that matters (the panel is live and rendering)
        // and is the least astonishing answer for `active` given that
        // `onDidChangeViewState` never fires to correct it. The ledger row that
        // event records is where the honest limit is written down.
        installReadonlyGetter(on: object, name: "active") { [weak model] in
            model.map { !$0.isDisposed } ?? false
        }
        installReadonlyGetter(on: object, name: "visible") { [weak model] in
            model.map { !$0.isDisposed } ?? false
        }

        let onDidDispose: @convention(block) () -> JSValue? = { [weak model] in
            MainActor.assumeIsolated {
                guard let model, let context = JSContext.current() else {
                    return UncheckedJSValueBox(value: nil)
                }
                return UncheckedJSValueBox(value: model.disposal.subscribe(
                    arguments: VSCodeAPI.currentArguments(), in: context, owner: model))
            }.value
        }
        object.setObject(onDidDispose, forKeyedSubscript: "onDidDispose" as NSString)

        let onDidChangeViewState: @convention(block) () -> JSValue? = { [weak model, weak webviews] in
            MainActor.assumeIsolated {
                guard let model, let context = JSContext.current() else {
                    return UncheckedJSValueBox(value: nil)
                }
                if let webviews {
                    webviews.notImplementedLedger.record(
                        memberPath: "vscode.WebviewPanel.onDidChangeViewState",
                        extensionIdentifier: webviews.extensionIdentifier)
                }
                return UncheckedJSValueBox(value: model.viewStateChanges.subscribe(
                    arguments: VSCodeAPI.currentArguments(), in: context, owner: model))
            }.value
        }
        object.setObject(onDidChangeViewState, forKeyedSubscript: "onDidChangeViewState" as NSString)

        let reveal: @convention(block) () -> Void = { [weak model] in
            MainActor.assumeIsolated {
                guard let model else { return }
                // `reveal(viewColumn?, preserveFocus?)` (`vscode.d.ts:11941`).
                // The column is dropped for `parsePreserveFocus`' reason; the
                // focus argument is the second one whether or not a column was
                // passed, because a caller that omits the column passes
                // `undefined` in its place rather than shifting the list.
                let arguments = VSCodeAPI.currentArguments()
                let focusArgument = arguments.count > 1 ? arguments[1] : nil
                let preserveFocus = focusArgument.map { $0.isBoolean && $0.toBool() } ?? false
                model.panel.reveal(preserveFocus: preserveFocus)
            }
        }
        object.setObject(reveal, forKeyedSubscript: "reveal" as NSString)

        // `dispose()` closes the pane's panel, which fires the host-side
        // `onDidDispose` this adaptor wired — so the extension's own listeners
        // and the bookkeeping both run through one path, whether the extension
        // or the user started it (`dry`). Idempotent twice over: the panel's
        // own `dispose()` guards on `isDisposed`, and a model already forgotten
        // is weakly `nil` here.
        let dispose: @convention(block) () -> Void = { [weak model] in
            MainActor.assumeIsolated { model?.panel.dispose() }
        }
        object.setObject(dispose, forKeyedSubscript: "dispose" as NSString)

        return object
    }

    // MARK: - The Webview object

    /// Builds the JS-visible `Webview` (`vscode.d.ts:11660-11712`) inside a
    /// panel. Built fresh per access — see the `webview` getter above.
    private static func makeWebviewObject(
        for model: ExtensionWebviewPanelModel,
        in context: JSContext
    ) -> JSValue? {
        guard let object = JSValue(newObjectIn: context) else { return nil }
        let panelID = model.panel.panelID

        installAccessor(on: object, name: "html",
            get: { [weak model] in model?.panel.html },
            set: { [weak model] value in
                guard let model, let value, value.isString, let string = value.toString() else {
                    return
                }
                model.panel.html = string
            })

        // `vscode.d.ts:11712`. The string an extension interpolates into its
        // own `<meta http-equiv="Content-Security-Policy">` to name where its
        // resources come from. Scheme and authority only, with no trailing
        // path, which is what a CSP source expression takes.
        installReadonlyGetter(on: object, name: "cspSource") {
            "\(WebviewResourceURL.scheme)://\(panelID)"
        }

        // `vscode.d.ts:11706`. Naming a file is not permission to read it —
        // `WebviewResourceURL.target(of:panelID:localResourceRoots:)` is the
        // only place that decides, when the page actually asks. So a URI built
        // here for a file outside every declared root is simply refused later,
        // and this function never has to consult the roots.
        let asWebviewUri: @convention(block) () -> JSValue? = {
            MainActor.assumeIsolated {
                guard let context = JSContext.current() else { return UncheckedJSValueBox(value: nil) }
                guard let argument = VSCodeAPI.currentArguments().first,
                      let file = VSCodeAPI.url(from: argument, in: context)
                else {
                    return UncheckedJSValueBox(value: VSCodeAPI.raise(
                        "vscode.Webview.asWebviewUri needs a Uri.", in: context))
                }
                return UncheckedJSValueBox(value: VSCodeAPI.uriValue(
                    for: WebviewResourceURL.url(forFile: file, panelID: panelID), in: context))
            }.value
        }
        object.setObject(asWebviewUri, forKeyedSubscript: "asWebviewUri" as NSString)

        // `vscode.d.ts:11699` — `Thenable<boolean>`. Upstream's boolean is
        // "was the message posted", which for this host is "is there still a
        // page to post it to": a disposed panel answers `false` rather than
        // rejecting, because upstream's own `postMessage` to a disposed
        // webview resolves `false` rather than throwing.
        let postMessage: @convention(block) () -> JSValue? = { [weak model] in
            MainActor.assumeIsolated {
                guard let context = JSContext.current() else { return UncheckedJSValueBox(value: nil) }
                guard let model, !model.isDisposed else {
                    return UncheckedJSValueBox(
                        value: VSCodeAPI.resolvedPromise(with: false, in: context))
                }
                let message = VSCodeAPI.currentArguments().first
                model.panel.post(message: message?.toObject() ?? NSNull())
                return UncheckedJSValueBox(value: VSCodeAPI.resolvedPromise(with: true, in: context))
            }.value
        }
        object.setObject(postMessage, forKeyedSubscript: "postMessage" as NSString)

        let onDidReceiveMessage: @convention(block) () -> JSValue? = { [weak model] in
            MainActor.assumeIsolated {
                guard let model, let context = JSContext.current() else {
                    return UncheckedJSValueBox(value: nil)
                }
                return UncheckedJSValueBox(value: model.messages.subscribe(
                    arguments: VSCodeAPI.currentArguments(), in: context, owner: model))
            }.value
        }
        object.setObject(onDidReceiveMessage, forKeyedSubscript: "onDidReceiveMessage" as NSString)

        // `vscode.d.ts:11667` — the options the webview is *currently* under.
        // Read-only here: `enableScripts` is fixed when `WKWebView`'s
        // configuration is built and cannot be changed afterwards, so a setter
        // that accepted one would be accepting something it could not do. The
        // one field an extension genuinely re-narrows at runtime is
        // `localResourceRoots`, and it is settable on its own below — a
        // narrower member that does exactly what it says, rather than a wide
        // one that silently honours a third of itself.
        installReadonlyGetter(on: object, name: "options") { [weak model] in
            guard let model, let context = JSContext.current(),
                  let options = JSValue(newObjectIn: context)
            else { return nil }
            options.setObject(
                model.panel.localResourceRoots.compactMap {
                    VSCodeAPI.uriValue(for: $0, in: context)
                },
                forKeyedSubscript: "localResourceRoots" as NSString)
            return options
        }

        installAccessor(on: object, name: "localResourceRoots",
            get: { [weak model] in
                guard let model, let context = JSContext.current() else { return nil }
                return model.panel.localResourceRoots.compactMap {
                    VSCodeAPI.uriValue(for: $0, in: context)
                }
            },
            set: { [weak model] value in
                guard let model, let context = JSContext.current() else { return }
                // An assignment this bridge cannot read as a list of Uris is
                // refused outright rather than applied as the empty list: one
                // reading silently revokes the panel's file access, the other
                // silently keeps it, and only the second leaves the page
                // working while the host logs nothing. Dropping *individual*
                // unreadable entries is `resourceRootsField`'s rule and is
                // different — there the extension did give a list.
                guard let value, let roots = resourceRootsField(value, in: context) else { return }
                model.panel.localResourceRoots = roots
            })

        return object
    }

    // MARK: - Object-building helpers

    /// `MainThreadWindow`'s, reused rather than re-declared: the descriptor's
    /// flags are one decision and belong in one place (`dry`). See its own doc
    /// for why each is set as it is.
    private static func installAccessor(
        on object: JSValue,
        name: String,
        get: @escaping @convention(block) () -> Any?,
        set: @escaping @convention(block) (JSValue?) -> Void
    ) {
        MainThreadWindow.installAccessor(on: object, name: name, get: get, set: set)
    }

    private static func installReadonlyGetter(
        on object: JSValue,
        name: String,
        get: @escaping @convention(block) () -> Any?
    ) {
        MainThreadWindow.installReadonlyGetter(on: object, name: name, get: get)
    }

    // MARK: - Teardown

    /// Disposes every panel this extension created and drops every listener.
    ///
    /// Called from `InstalledExtension.dispose()` beside `window.dispose()`.
    /// A webview holds a whole web content process, so a panel left standing
    /// after its extension is gone is not merely untidy — hence disposing the
    /// panels rather than only forgetting them.
    public func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        for model in Array(panels.values) {
            model.panel.onDidDispose = nil
            model.panel.onDidReceiveMessage = nil
            model.panel.dispose()
            model.removeListeners()
        }
        panels.removeAll()
        // The serializers go with them: each is a `JSValue` into a context
        // that is being torn down, and `hasSerializer(for:)` must stop
        // claiming view types this extension can no longer restore.
        serializers.removeAll()
    }
}

extension MainThreadWebviews: Loggable {
    public static nonisolated let logger = makeLogger()
}
