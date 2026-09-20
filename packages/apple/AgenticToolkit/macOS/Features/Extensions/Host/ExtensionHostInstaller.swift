//
//  ExtensionHostInstaller.swift
//  AgenticToolkit
//

import AppKit
import Foundation
import OSLog

import AgenticDeveloperToolkitUI
import AgenticToolkitCore

/// An `ExtensionWorkspaceRoots` that forwards to a closure.
///
/// Every host is built once, at launch, before any project window exists, and
/// `ExtensionHost.workspaceRoots` is a stored `let` — so a host handed the
/// front window's `ProjectWorkspace` at construction would be handed `nil`
/// forever, and a host handed the first window that opened would keep
/// answering for that window after the user moved to another project.
///
/// The same idiom `NSAlertMessagePresenter.window` and
/// `WindowFooterStatusBarPresenter.footers` already use, for the same reason:
/// the answer has to be whatever is open when an extension actually asks.
/// Both members below are read-through, so nothing is cached here either.
@MainActor
public final class ClosureWorkspaceRoots: ExtensionWorkspaceRoots {

    private let current: () -> ExtensionWorkspaceRoots?

    public init(current: @escaping () -> ExtensionWorkspaceRoots?) {
        self.current = current
    }

    public var workspaceDisplayName: String? { current()?.workspaceDisplayName }

    public var workspaceRootURLs: [URL] { current()?.workspaceRootURLs ?? [] }
}

/// Everything the extension host needs from the app around it, in one value.
///
/// Closures rather than references for the four read-through seams: the app
/// owns `ProjectWindowManager` and `TextDocumentCoordinator`, this framework
/// does not reach for a shared instance from inside a feature, and every one
/// of the four changes underneath a host that outlives it.
@MainActor
public struct ExtensionHostSeams {

    /// Where `vscode.commands` registers into and executes from. The app's
    /// own registry, deliberately — an extension's command has to be
    /// reachable from the command palette and a menu, which is the whole
    /// point of contributing one.
    public let commandRegistry: CommandRegistry

    /// What `vscode.lm` offers. One provider for every host: the models are a
    /// property of the user's settings, not of an extension.
    public let languageModelProvider: ExtensionLanguageModelProviding

    /// What `vscode.workspace.fs` reaches the disk through. One service for
    /// every host — a file read is a file read whichever extension asked —
    /// and a seam rather than a hardcoded `FileSystemService()` so that
    /// sharing is a claim a test can actually make: hand two extensions one
    /// double, and the double is what answers both.
    public let fileSystemService: FileSystemServicing

    /// Where an alert sheet attaches, or `nil` for an app-modal alert.
    public let frontWindow: () -> NSWindow?

    /// Every footer a status bar item renders into.
    public let footers: () -> [WindowFooterBar]

    /// The workspace extensions see right now, or `nil` when no project is
    /// open.
    public let workspaceRoots: () -> ExtensionWorkspaceRoots?

    /// Where a webview panel an extension creates goes on screen, or `nil`
    /// when there is nowhere to put one.
    ///
    /// A closure for `frontWindow`'s reason, one layer further in: the pane
    /// tree belongs to the app, and this framework holds only what a webview
    /// panel *is*. `PaneWebviewPresenter` is what turns this into the
    /// `ExtensionWebviewPresenting` the adaptor takes.
    public let placeWebviewPanel: PaneWebviewPresenter.Place

    /// The language id of every document open in an editor right now, for
    /// `onLanguage:` activation.
    ///
    /// Read-through, and read only when an extension is installed: the live
    /// event is `ExtensionHostInstaller.documentDidOpen(languageID:)`, and
    /// this answers the other half of the same question — what was already
    /// open when an extension the user just enabled came up. Duplicates are
    /// not filtered here; `activateIfTriggered(by:)` is idempotent per
    /// installation, so the second `swift` costs a matcher call.
    public let openDocumentLanguageIDs: () -> [String]

    public init(
        commandRegistry: CommandRegistry,
        languageModelProvider: ExtensionLanguageModelProviding,
        frontWindow: @escaping () -> NSWindow?,
        footers: @escaping () -> [WindowFooterBar],
        workspaceRoots: @escaping () -> ExtensionWorkspaceRoots?,
        placeWebviewPanel: @escaping PaneWebviewPresenter.Place,
        openDocumentLanguageIDs: @escaping () -> [String],
        // Defaulted, because the real answer is the only answer every caller
        // outside a test wants: the app has no second file system to choose
        // between, and making every call site spell it would be ceremony.
        fileSystemService: FileSystemServicing = FileSystemService()
    ) {
        self.commandRegistry = commandRegistry
        self.languageModelProvider = languageModelProvider
        self.fileSystemService = fileSystemService
        self.frontWindow = frontWindow
        self.footers = footers
        self.workspaceRoots = workspaceRoots
        self.placeWebviewPanel = placeWebviewPanel
        self.openDocumentLanguageIDs = openDocumentLanguageIDs
    }
}

/// One extension's `ExtensionHost`, its eight `vscode` namespace adaptors, and
/// the activation that decides when its code runs.
///
/// ### Why the adaptors are held
///
/// `ExtensionHost.defineVSCodeMember` takes `implementation: Any` — the
/// `lazy var` block an adaptor exposes — and the host keeps only that block.
/// Nothing in the host keeps the adaptor that vended it alive, and every one
/// of the eight owns state the block reads (a registry handle, a disposable
/// table, a pending continuation). Dropping an adaptor after installing its
/// members is the shape where an extension's first call reaches a
/// deallocated owner, so all eight are stored here for as long as the host is.
///
/// ### One host per extension, one set of adaptors per host
///
/// The adaptors are per extension because seven of the eight take
/// `extensionIdentifier` and record against it. Their *collaborators* — the
/// stores, the diagnostic emitter, the presenters — are shared across every
/// host by `ExtensionHostInstaller`; see its own doc for which and why.
@MainActor
public final class ExtensionHostInstallation {

    public let host: ExtensionHost

    public var identifier: String { host.identifier }

    /// What this extension declared it activates on. Held rather than
    /// recomputed because `ExtensionHostInstaller` asks it a second question
    /// once the workspace scan lands, long after installation.
    public let activationMatcher: ActivationEventMatcher

    private let commands: MainThreadCommands
    private let languages: MainThreadLanguages
    private let workspace: MainThreadWorkspace
    private let languageModels: MainThreadLanguageModels
    private let window: MainThreadWindow
    private let webviews: MainThreadWebviews
    private let treeViews: MainThreadTreeViews
    private let diagnostics: MainThreadDiagnostics

    private let commandRegistry: CommandRegistry

    /// The registration token for each stub command still standing, keyed by
    /// command id. An id leaves this table the first time the stub fires;
    /// see `dispatchAfterActivation(commandID:arguments:)` for what the token
    /// is actually for.
    private var stubCommands: [String: CommandRegistration] = [:]

    private var isDisposed = false

    // MARK: - Construction

    /// Builds the host and all eight adaptors over the shared collaborators
    /// `installer` owns, and installs every `vscode` member and enum table.
    ///
    /// - Throws: whatever `ExtensionHost.defineVSCodeMember` throws — which,
    ///   before `activate()`, is only `hostDisposed` on a host torn down
    ///   between construction and here. A namespace the shim does not know is
    ///   raised later, from the activation that first installs a runtime.
    fileprivate init(
        loadedExtension: LoadedExtension,
        notImplementedLedger: NotImplementedLedger,
        collaborators: ExtensionHostInstaller.Collaborators,
        seams: ExtensionHostSeams
    ) throws {
        let identifier = loadedExtension.identifier
        self.activationMatcher = ActivationEventMatcher(manifest: loadedExtension.manifest)
        self.commandRegistry = seams.commandRegistry
        self.host = ExtensionHost(
            loadedExtension: loadedExtension,
            notImplementedLedger: notImplementedLedger,
            workspaceRoots: collaborators.workspaceRoots)

        self.commands = MainThreadCommands(registry: seams.commandRegistry)
        self.languages = MainThreadLanguages(
            store: collaborators.languageConfigurationStore,
            vocabulary: collaborators.vocabulary)
        self.workspace = MainThreadWorkspace(
            workspaceRoots: collaborators.workspaceRoots,
            notImplementedLedger: notImplementedLedger,
            extensionIdentifier: identifier,
            fileSystemService: collaborators.fileSystemService)
        self.languageModels = MainThreadLanguageModels(
            provider: seams.languageModelProvider,
            notImplementedLedger: notImplementedLedger,
            extensionIdentifier: identifier)
        self.window = MainThreadWindow(
            presenter: collaborators.messagePresenter,
            quickPickPresenter: collaborators.pickerPresenter,
            inputBoxPresenter: collaborators.pickerPresenter,
            statusBarPresenter: collaborators.statusBarPresenter,
            notImplementedLedger: notImplementedLedger,
            extensionIdentifier: identifier)
        self.webviews = MainThreadWebviews(
            presenter: collaborators.webviewPresenter,
            notImplementedLedger: notImplementedLedger,
            extensionIdentifier: identifier,
            extensionDirectory: loadedExtension.directory,
            workspaceRoots: collaborators.workspaceRoots)
        self.treeViews = MainThreadTreeViews(
            notImplementedLedger: notImplementedLedger,
            extensionIdentifier: identifier,
            commands: seams.commandRegistry)
        self.diagnostics = MainThreadDiagnostics(
            store: collaborators.diagnosticStore,
            sink: collaborators.diagnosticSink,
            events: collaborators.diagnosticEvents)

        try installVSCodeMembers()
    }

    /// Installs all twenty-four members and all three enum tables.
    ///
    /// **Nothing here installs `Uri`, the text-geometry classes, the
    /// diagnostic classes, the language-model vocabulary or the trampoline.**
    /// `ExtensionHost.installRuntime` installs all five itself on every
    /// activation, and a second installation from out here would overwrite
    /// the class objects the already-installed members close over.
    private func installVSCodeMembers() throws {
        try host.defineVSCodeMember(
            namespacePath: "vscode.commands", name: "registerCommand",
            implementation: commands.registerCommand)
        try host.defineVSCodeMember(
            namespacePath: "vscode.commands", name: "executeCommand",
            implementation: commands.executeCommand)
        try host.defineVSCodeMember(
            namespacePath: "vscode.commands", name: "getCommands",
            implementation: commands.getCommands)

        try host.defineVSCodeMember(
            namespacePath: "vscode.languages", name: "getLanguages",
            implementation: languages.getLanguages)
        try host.defineVSCodeMember(
            namespacePath: "vscode.languages", name: "setLanguageConfiguration",
            implementation: languages.setLanguageConfiguration)
        try host.defineVSCodeMember(
            namespacePath: "vscode.languages", name: "createDiagnosticCollection",
            implementation: diagnostics.createDiagnosticCollection)
        try host.defineVSCodeMember(
            namespacePath: "vscode.languages", name: "getDiagnostics",
            implementation: diagnostics.getDiagnostics)
        try host.defineVSCodeMember(
            namespacePath: "vscode.languages", name: "onDidChangeDiagnostics",
            implementation: diagnostics.onDidChangeDiagnostics)

        try host.defineVSCodeMember(
            namespacePath: "vscode.workspace", name: "name",
            implementation: workspace.name)
        try host.defineVSCodeMember(
            namespacePath: "vscode.workspace", name: "workspaceFolders",
            implementation: workspace.workspaceFolders)
        try host.defineVSCodeMember(
            namespacePath: "vscode.workspace", name: "getWorkspaceFolder",
            implementation: workspace.getWorkspaceFolder)
        try host.defineVSCodeMember(
            namespacePath: "vscode.workspace", name: "fs",
            implementation: workspace.fs)

        try host.defineVSCodeMember(
            namespacePath: "vscode.lm", name: "selectChatModels",
            implementation: languageModels.selectChatModels)
        try host.defineVSCodeMember(
            namespacePath: "vscode.lm", name: "onDidChangeChatModels",
            implementation: languageModels.onDidChangeChatModels)

        try host.defineVSCodeMember(
            namespacePath: "vscode.window", name: "showInformationMessage",
            implementation: window.showInformationMessage)
        try host.defineVSCodeMember(
            namespacePath: "vscode.window", name: "showWarningMessage",
            implementation: window.showWarningMessage)
        try host.defineVSCodeMember(
            namespacePath: "vscode.window", name: "showErrorMessage",
            implementation: window.showErrorMessage)
        try host.defineVSCodeMember(
            namespacePath: "vscode.window", name: "showQuickPick",
            implementation: window.showQuickPick)
        try host.defineVSCodeMember(
            namespacePath: "vscode.window", name: "showInputBox",
            implementation: window.showInputBox)
        try host.defineVSCodeMember(
            namespacePath: "vscode.window", name: "createStatusBarItem",
            implementation: window.createStatusBarItem)
        // Installed under `vscode.window`, implemented by a different adaptor.
        // `MainThreadDiagnostics` under `vscode.languages` is the precedent,
        // and `MainThreadWebviews`' own doc says why the class is separate.
        try host.defineVSCodeMember(
            namespacePath: "vscode.window", name: "createWebviewPanel",
            implementation: webviews.createWebviewPanel)
        try host.defineVSCodeMember(
            namespacePath: "vscode.window", name: "registerWebviewPanelSerializer",
            implementation: webviews.registerWebviewPanelSerializer)
        try host.defineVSCodeMember(
            namespacePath: "vscode.window", name: "registerWebviewViewProvider",
            implementation: webviews.registerWebviewViewProvider)
        // `MainThreadTreeViews` is the second adaptor installed under
        // `vscode.window`, for `MainThreadWebviews`' reason: the two tree
        // members are one feature with one lifetime, and the window adaptor
        // has no business owning it.
        //
        // **The four value types the tree API needs — `TreeItem`,
        // `TreeItemCollapsibleState`, `ThemeIcon` and `EventEmitter` — are not
        // installed here.** They are built in JavaScript by
        // `extension-runtime.js`, where `new` and `instanceof` answer the way
        // an extension expects, and a second installation from out here would
        // replace the constructors an already-built item was made with.
        try host.defineVSCodeMember(
            namespacePath: "vscode.window", name: "registerTreeDataProvider",
            implementation: treeViews.registerTreeDataProvider)
        try host.defineVSCodeMember(
            namespacePath: "vscode.window", name: "createTreeView",
            implementation: treeViews.createTreeView)

        // The three enum tables go on **`vscode`**, the top-level namespace,
        // never on `vscode.window` — each adaptor's own table doc gives the
        // measured citation for why that is where the declaration puts them.
        try host.defineVSCodeMember(
            namespacePath: "vscode", name: "QuickPickItemKind",
            implementation: MainThreadWindow.quickPickItemKindMembers)
        try host.defineVSCodeMember(
            namespacePath: "vscode", name: "InputBoxValidationSeverity",
            implementation: MainThreadWindow.inputBoxValidationSeverityMembers)
        try host.defineVSCodeMember(
            namespacePath: "vscode", name: "StatusBarAlignment",
            implementation: MainThreadWindow.statusBarAlignmentMembers)
    }

    // MARK: - Activation

    /// Activates this extension if `trigger` is one it declared, and does
    /// nothing at all otherwise.
    ///
    /// Safe to call repeatedly and safe to call on an already-running host:
    /// `ExtensionHost.activate()` is idempotent and shares one outcome across
    /// every caller, so a second trigger costs an `await` on a finished task
    /// rather than a second evaluation of the extension's code.
    public func activateIfTriggered(by trigger: ActivationTrigger) {
        guard !isDisposed, activationMatcher.matches(trigger) else { return }
        activate(then: nil)
    }

    /// Whether this extension is the one a restored panel of `viewType`
    /// belongs to.
    ///
    /// Two ways to be that extension, and the order matters. An extension
    /// already awake *with a serializer registered* has said so at runtime,
    /// which is the strongest claim there is. An extension not yet awake can
    /// only have said so in its manifest, as `onWebviewPanel:<viewType>` —
    /// and that declaration is read directly rather than through
    /// `ActivationEventMatcher.matches(_:)`, which `"*"` answers yes to for
    /// every trigger. See `declaresWebviewPanel(viewType:)`.
    fileprivate func claimsWebviewPanel(viewType: String) -> Bool {
        guard !isDisposed else { return false }
        return webviews.hasSerializer(for: viewType)
            || activationMatcher.declaresWebviewPanel(viewType: viewType)
    }

    /// Where a panel of this extension's may read files from, given what it
    /// was created with. See `MainThreadWebviews.resourceRoots(for:)` — the
    /// extension directory it resolves against is this installation's.
    fileprivate func resourceRoots(for options: WebviewPanelOptions) -> [URL] {
        webviews.resourceRoots(for: options)
    }

    /// Activates this extension if it is not awake yet, then hands it the
    /// restored panel.
    ///
    /// The panel is on screen and blank throughout: `activate(then:)` runs the
    /// extension's `activate` on a detached task and calls back on the main
    /// actor, so a restore of a not-yet-awake extension completes a turn or
    /// two later. That is the whole reason this is a closure rather than a
    /// return value — there is nothing to hand back synchronously, and the
    /// pane is already where it belongs.
    fileprivate func restoreWebviewPanel(_ panel: any ExtensionWebviewPanel, state: WebviewPanelState) {
        guard !isDisposed else { return }
        if webviews.hasSerializer(for: state.viewType) {
            handOver(panel, state: state)
            return
        }
        activate { [weak self] in
            self?.handOver(panel, state: state)
        }
    }

    /// Activates this extension if it is not awake yet, then hands it the
    /// empty webview of a contributed view it declared.
    ///
    /// `restoreWebviewPanel(_:state:)`'s twin, down to the shape: resolve now
    /// if the provider is already registered, otherwise activate and resolve on
    /// the way back. The pane is on screen and empty throughout, which is what
    /// makes the asynchronous case merely late rather than wrong.
    fileprivate func resolveWebviewView(
        _ panel: any ExtensionWebviewPanel,
        viewID: String,
        then didResolve: @escaping () -> Void
    ) {
        guard !isDisposed else { return }
        if webviews.hasViewProvider(for: viewID) {
            handOver(panel, viewID: viewID, then: didResolve)
            return
        }
        activate { [weak self] in
            self?.handOver(panel, viewID: viewID, then: didResolve)
        }
    }

    /// Activates this extension if it is not awake yet, then hands the pane the
    /// tree data provider it registered for the contributed view `viewID`.
    ///
    /// `resolveWebviewView(_:viewID:then:)`'s twin, with the one difference the
    /// two APIs force: there is no object to hand over, because the provider is
    /// the extension's and this is the pane finding it. The pane shows its
    /// explanation throughout, which is what makes the asynchronous case merely
    /// late rather than wrong.
    fileprivate func resolveTreeView(
        viewID: String,
        then didResolve: @escaping (any ExtensionTreeDataSource) -> Void
    ) {
        guard !isDisposed else { return }
        if let source = treeViews.treeDataSource(for: viewID) {
            didResolve(source)
            return
        }
        activate { [weak self] in
            self?.handOverTree(viewID: viewID, then: didResolve)
        }
    }

    private func handOverTree(
        viewID: String,
        then didResolve: @escaping (any ExtensionTreeDataSource) -> Void
    ) {
        guard !isDisposed else { return }
        guard let source = treeViews.treeDataSource(for: viewID) else {
            // The pane stays, showing its explanation. An extension that
            // contributes a tree view and registers no provider for it is the
            // same ordinary state its webview twin describes — a `when` clause
            // nothing satisfied, a provider registered on a later activation
            // event — and the pane belongs to the manifest, not the provider.
            Self.logger.error(
                """
                Extension '\(self.identifier, privacy: .public)' contributes the tree view \
                '\(viewID, privacy: .public)' but registered no tree data provider for it
                """)
            return
        }
        didResolve(source)
    }

    private func handOver(
        _ panel: any ExtensionWebviewPanel,
        viewID: String,
        then didResolve: @escaping () -> Void
    ) {
        guard !isDisposed else { return }
        guard webviews.resolveWebviewView(panel, viewID: viewID) else {
            // The pane stays, showing the explanation its placeholder carries,
            // rather than an empty white rectangle. An extension that declares
            // a webview view in its manifest and never registers a provider for
            // it is a real and common state — a `when` clause the view is
            // behind, a provider registered only on a later activation event —
            // and the pane is the manifest's, not the provider's.
            Self.logger.error(
                """
                Extension '\(self.identifier, privacy: .public)' contributes the webview view \
                '\(viewID, privacy: .public)' but registered no provider that resolved it
                """)
            return
        }
        didResolve()
    }

    private func handOver(_ panel: any ExtensionWebviewPanel, state: WebviewPanelState) {
        guard !isDisposed else { return }
        guard webviews.restore(panel, viewType: state.viewType, state: state.state) else {
            // The pane stays, holding a blank panel, rather than being taken
            // out from under the user: the layout is theirs, and a webview
            // whose extension failed to deserialize it is a page that did not
            // render, not a tab they asked to close.
            Self.logger.error(
                """
                Extension '\(self.identifier, privacy: .public)' claimed the restored webview panel \
                of type '\(state.viewType, privacy: .public)' but did not deserialize it
                """)
            return
        }
    }

    /// Registers one stub `AppCommand` per command this extension contributes
    /// that it has not already registered for itself.
    ///
    /// **This is how `onCommand:` activation works without a pre-execute hook
    /// on `CommandRegistry`.** The registry has none, so nothing can sit in
    /// front of `execute(id:)` and activate the extension that owns the id.
    /// What it does have is a documented replace-in-place on a duplicate
    /// registration — written, in its own words, because "Stage 5 registers
    /// commands from extensions that can be reloaded". So the stub is
    /// registered *now*, the extension's own `registerCommand` replaces it
    /// the moment it activates, and no new mechanism is needed on either
    /// side.
    ///
    /// **The activating invocation resolves `undefined`.** `AppCommand.run`
    /// is synchronous and `activate()` is not, so the first press of a
    /// command that activates its extension returns before the extension's
    /// own handler has run; the handler then runs, and its result is
    /// discarded. Every later invocation goes straight to the extension's own
    /// registration and resolves normally. The alternative — an `AppCommand`
    /// that could answer with a promise — is a change to the app's command
    /// vocabulary for a case that happens once per extension per launch.
    ///
    /// **An id already in the registry is left alone, and said so.** The
    /// registry replaces in place, so registering a stub over someone else's
    /// command would silently take that command away from whoever owns it —
    /// and `unregister(id:token:)` would hand it back only if the stub were
    /// still the registration at that moment. But an id that is taken is also
    /// an id whose `onCommand:` activation will never fire, so the extension
    /// is quietly inert on that trigger: that is a fact about the
    /// installation that is invisible from inside the extension, and it is
    /// logged rather than skipped in silence.
    fileprivate func registerActivationCommands(_ contributed: [ExtensionManifest.Command]) {
        for command in contributed where activationMatcher.matches(.commandInvoked(command.command)) {
            let id = command.command
            guard commandRegistry.command(id: id) == nil else {
                Self.logger.notice(
                    """
                    Extension '\(self.identifier, privacy: .public)' declares \
                    'onCommand:\(id, privacy: .public)', but '\(id, privacy: .public)' is already \
                    registered: that trigger will not activate it
                    """)
                continue
            }
            // `isExtensionContributed: true` for two reasons, and the second
            // is the one that would break if it were left off. It is true —
            // the id comes from a manifest's `contributes.commands` — and
            // `CommandRegistry.register(_:isExtensionContributed:)` refuses
            // exactly one combination: extension over built-in. A stub filed
            // as built-in would therefore refuse the extension's own
            // `registerCommand` when it arrives moments later to replace it,
            // leaving the extension permanently talking to its own activation
            // stub. Extension over extension is the replace-and-warn the
            // handoff has always relied on.
            let token = commandRegistry.register(
                AppCommand(
                    id: id,
                    title: command.title,
                    category: command.category ?? "",
                    run: { [weak self] arguments in
                        self?.runActivationStub(commandID: id, arguments: arguments)
                        return nil
                    }),
                isExtensionContributed: true)
            stubCommands[id] = token
        }
    }

    private func runActivationStub(commandID: String, arguments: [Any]) {
        activate { [weak self] in
            self?.dispatchAfterActivation(commandID: commandID, arguments: arguments)
        }
    }

    /// Hands the invocation the stub swallowed to whoever owns the id now.
    ///
    /// `unregister(id:token:)` is the whole mechanism: it removes the
    /// registration only if the token still names it, so it is a no-op
    /// exactly when the extension's `registerCommand` already replaced the
    /// stub, and removes the stub exactly when it did not. What is in the
    /// registry afterwards therefore answers the question nothing else can —
    /// a command means the extension registered one, and no command means it
    /// activated without honouring a `contributes.commands` entry it
    /// declared, which is the extension's bug and is logged as one rather
    /// than re-entering the stub forever.
    ///
    /// **Retiring the stub and forwarding the invocation are two steps, not
    /// one.** Activation is asynchronous, so a user who presses the command
    /// twice before the extension finishes activating queues *two* of these,
    /// each carrying its own arguments. Only the first finds the token, and a
    /// `guard` that took the token as its admission ticket dropped the second
    /// press on the floor — not deferred, not logged, gone. So the token is
    /// retired if it is still there (`if`, not `guard`), and every
    /// invocation then forwards on its own merits.
    private func dispatchAfterActivation(commandID: String, arguments: [Any]) {
        guard !isDisposed else { return }
        if let token = stubCommands.removeValue(forKey: commandID) {
            commandRegistry.unregister(id: commandID, token: token)
        }
        guard commandRegistry.command(id: commandID) != nil else {
            Self.logger.error(
                """
                Extension '\(self.identifier, privacy: .public)' activated without registering \
                '\(commandID, privacy: .public)', a command its manifest contributes
                """)
            return
        }
        do {
            _ = try commandRegistry.execute(id: commandID, arguments: arguments)
        } catch {
            Self.logger.error(
                """
                Extension '\(self.identifier, privacy: .public)' command \
                '\(commandID, privacy: .public)' failed: \
                \(error.localizedDescription, privacy: .public)
                """)
        }
    }

    /// Runs `activate()` and then `completion`, on the main actor.
    ///
    /// The task is deliberately not retained and deliberately not cancelled
    /// by `dispose()`: `ExtensionHost.activate()` shares one outcome across
    /// every caller, so cancelling one caller's task would decide the shared
    /// outcome for all of them. `dispose()` finishes the activation itself,
    /// with `.hostDisposed`, and the `isDisposed` guards here are what stop a
    /// completion running afterwards.
    private func activate(then completion: (() -> Void)?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.host.activate()
            } catch {
                Self.logger.error(
                    """
                    Extension '\(self.identifier, privacy: .public)' failed to activate: \
                    \(error.localizedDescription, privacy: .public)
                    """)
                return
            }
            guard !self.isDisposed else { return }
            completion?()
        }
    }

    // MARK: - Teardown

    /// Tells this extension's `vscode.lm` that the configured model list
    /// moved, so `onDidChangeChatModels` publishes.
    public func availableChatModelsDidChange() {
        guard !isDisposed else { return }
        languageModels.availableChatModelsDidChange()
    }

    /// Tears the host and every adaptor down, in the one order that works.
    ///
    /// **The extension's own teardown first.** `context.subscriptions` is where
    /// an extension is asked to put the things that reach back into the app,
    /// and disposing them is the extension's last chance to do anything — flush
    /// state, close a panel, run its own cleanup command. Every one of those
    /// goes through an adaptor, so it only means something while the adaptors
    /// are still standing. This used to run last, inside `host.dispose()`,
    /// after all eight had been swept: a `dispose` block that called a command
    /// the extension itself registered found it already withdrawn, and since
    /// `executeCommand` answers a rejected promise and a `dispose` block does
    /// not await, nothing anywhere reported that the work had been dropped.
    ///
    /// Then stubs — a stub left in the registry outlives everything it can
    /// reach and would activate a disposed host on the next press. Then the
    /// eight adaptors, each of which withdraws what it registered elsewhere
    /// (commands, language configurations, status bar items, diagnostic
    /// collections).
    ///
    /// The host last, and still last: those withdrawals call into JavaScript —
    /// a panel's `onDidDispose`, a tree view's — so disposing the runtime ahead
    /// of them would leave them running against a dead context. That is what
    /// makes this three phases rather than a swap; `host.dispose()` runs the
    /// subscriptions too, and is a no-op on that count by the time it gets here.
    ///
    /// One thing this ordering does *not* buy: teardown is synchronous, so
    /// anything a `dispose` block starts asynchronously — `workspace.fs`
    /// writes, a quick pick — is still enqueued behind the adaptor sweeps and
    /// finds its adaptor disposed when it lands. Making that work means making
    /// teardown async, which `reconcile()` depends on not being: it disposes
    /// the outgoing host before building its replacement, and the two must not
    /// overlap.
    public func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        host.disposeSubscriptions()
        for (id, token) in stubCommands {
            commandRegistry.unregister(id: id, token: token)
        }
        stubCommands = [:]
        commands.dispose()
        languages.dispose()
        workspace.dispose()
        languageModels.dispose()
        window.dispose()
        webviews.dispose()
        treeViews.dispose()
        diagnostics.dispose()
        host.dispose()
    }
}

extension ExtensionHostInstallation: Loggable {
    public static nonisolated let logger = makeLogger()
}

/// Brings up one `ExtensionHost` per enabled extension, and keeps that set in
/// step with what the registry holds.
///
/// ### What is shared, and what is not
///
/// Per extension: one `ExtensionHost` and one of each adaptor, because seven
/// of the eight record against an `extensionIdentifier`.
///
/// Shared across every host, each for a reason its own type states:
///
/// - `LanguageConfigurationStore` — one table of language configurations is
///   what the editor reads; per-adaptor teardown is safe because the adaptor
///   tracks its own handles.
/// - `ExtensionDiagnosticStore` — `allDiagnostics()` answers across every
///   collection of every extension, which a per-extension store cannot.
/// - The `ExtensionEventEmitter<[URL]>` and the `HostDiagnosticSink` over it
///   — the emitter's own doc: a privately constructed one "would silently
///   give each extension its own island".
/// - `ExtensionEventTimerWindow` — one timer, not one per extension.
/// - `HostLanguageVocabulary` — it reads the coordinator's language
///   contribution point, which is already one per app.
/// - The three presenters — they render into windows, and there is one set of
///   windows.
/// - `FileSystemService` — its serial queue is what orders two extensions'
///   writes to the same file, and an instance each is two queues and no
///   ordering at all.
@MainActor
public final class ExtensionHostInstaller {

    /// The shared collaborators, in one value so the per-extension
    /// initialiser takes one parameter rather than nine.
    struct Collaborators {
        let languageConfigurationStore: LanguageConfigurationStore
        let diagnosticStore: ExtensionDiagnosticStore
        let diagnosticEvents: ExtensionEventEmitter<[URL]>
        let diagnosticSink: HostDiagnosticSink
        let vocabulary: HostLanguageVocabulary
        let messagePresenter: NSAlertMessagePresenter
        let pickerPresenter: ExtensionPickerPresenter
        let statusBarPresenter: WindowFooterStatusBarPresenter

        /// Shared like the other presenters: a webview panel is a webview
        /// panel whichever extension asked for one, and the per-extension
        /// facts reach it on the request instead.
        let webviewPresenter: PaneWebviewPresenter

        let workspaceRoots: ClosureWorkspaceRoots

        /// The one service every extension's `vscode.workspace.fs` runs
        /// through. Shared for the reason in this type's list above, and
        /// typed as the protocol so a test can substitute a double for all of
        /// them at once.
        let fileSystemService: FileSystemServicing
    }

    private let registry: ExtensionRegistry
    private let notImplementedLedger: NotImplementedLedger
    private let seams: ExtensionHostSeams

    /// **`internal`, not `private`, deliberately**, on the same grounds as
    /// `NSAlertMessagePresenter.buttonPlan(for:)`: which collaborator each
    /// seam ends up wired into is a claim about this initialiser, and the
    /// only way to check it without a running window server is to read the
    /// built collaborator back out. `ExtensionHostInstallerTests` does.
    let collaborators: Collaborators

    /// One installation per running extension, keyed by identifier, each
    /// stored beside the identity it was built from so `reconcile()` can tell
    /// "already running" from "already running *this*".
    private var installed: [String: Installed] = [:]

    /// The running installations, keyed by identifier. Computed from
    /// `installed` rather than stored alongside it: two dictionaries that must
    /// agree is a drift waiting to happen, and every reader here wants one or
    /// the other, never both.
    public var installations: [String: ExtensionHostInstallation] {
        installed.mapValues(\.installation)
    }

    /// A running installation and the on-disk state it was built from.
    private struct Installed {
        let installation: ExtensionHostInstallation
        let identity: InstalledIdentity
    }

    /// Everything about an extension that a running host has already baked in:
    /// its manifest, the directory it came from, and a signature of the code
    /// that was evaluated. Two equal identities mean the host on screen is
    /// still the host this extension would get if it were installed now.
    ///
    /// `LoadedExtension` alone would not do. It is the manifest plus the
    /// directory, so it catches an edited `package.json` — a changed
    /// `activationEvents`, a new contribution, a moved entry point — but an
    /// extension author's ordinary edit is to the *code*, which leaves the
    /// manifest byte-identical.
    private struct InstalledIdentity: Equatable {
        let loaded: LoadedExtension
        let entryPoint: EntryPointSignature?
    }

    /// A cheap stand-in for "the code on disk is the code that is running":
    /// the entry point's size and modification date.
    ///
    /// Not a content hash, deliberately. The entry point of a bundled web
    /// extension is one concatenated file and routinely megabytes, and this is
    /// computed on the main actor inside `reconcile()`, which runs on every
    /// contribution change. Two fields of a `stat` cost nothing and catch every
    /// edit an ordinary save produces.
    ///
    /// What it does not catch, plainly: a rewrite that lands on the same byte
    /// count *and* the same timestamp, and an edit to a file the entry point
    /// pulls in at runtime rather than to the entry point itself. The first
    /// takes deliberate effort; the second is invisible to any signature short
    /// of walking the extension's whole directory, which is the walk this is
    /// deliberately not.
    ///
    /// **`nil` means "did not resolve or did not stat", and two `nil`s compare
    /// equal.** That is the safe direction: an entry point that cannot be read
    /// keeps the host that is already running, rather than tearing it down for
    /// a `bringUp` that would fail on the same unreadable path and leave the
    /// extension with nothing.
    private struct EntryPointSignature: Equatable {
        let size: Int
        let modified: Date
    }

    /// Stats `loaded`'s entry point, or answers `nil` if there is nothing to
    /// stat — no `browser` entry point declared, a path that escapes the
    /// extension's directory, or a file that is not there.
    private static func entryPointSignature(for loaded: LoadedExtension) -> EntryPointSignature? {
        guard let browser = loaded.manifest.browser,
              let url = try? ExtensionResourcePath.resolve(browser, inside: loaded.directory),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize,
              let modified = values.contentModificationDate
        else { return nil }
        return EntryPointSignature(size: size, modified: modified)
    }

    /// The last completed scan, replayed at every extension that comes up
    /// afterwards so a scan is not re-run per extension. `nil` until the first
    /// scan lands.
    ///
    /// It carries the roots it was taken from, and that is the whole point of
    /// the type: a bare `[String]?` conflated "no scan yet" with "a scan that
    /// found nothing", and a bare non-`nil` conflated "the paths of the
    /// project that is open" with "the paths of a project that was open".
    private var completedScan: CompletedScan?

    /// The roots a scan is running against right now, or `nil` when none is.
    ///
    /// Without it, two `reconcile()` calls before the first scan returned —
    /// which is ordinary, since the registry's contributions settle in more
    /// than one step at launch — each started a full recursive walk of the
    /// same tree.
    private var scanningRoots: [URL]?

    /// One finished scan: what it found, and what it was looking at.
    private struct CompletedScan {
        let roots: [URL]

        /// Held as a prepared `WorkspaceScan` rather than as the raw paths,
        /// so the replay below hands every extension the same decomposed
        /// copy instead of each matcher decomposing the workspace again —
        /// see `WorkspaceScan`'s own doc.
        let scan: WorkspaceScan
    }

    public init(
        registry: ExtensionRegistry,
        notImplementedLedger: NotImplementedLedger,
        languagePoint: LanguageContributionPoint,
        seams: ExtensionHostSeams
    ) {
        self.registry = registry
        self.notImplementedLedger = notImplementedLedger
        self.seams = seams

        let eventWindow = ExtensionEventTimerWindow()
        let events = MainThreadDiagnostics.makeOnDidChangeDiagnosticsEmitter(window: eventWindow)
        let workspaceRoots = ClosureWorkspaceRoots(current: seams.workspaceRoots)
        self.collaborators = Collaborators(
            languageConfigurationStore: LanguageConfigurationStore(),
            diagnosticStore: ExtensionDiagnosticStore(),
            diagnosticEvents: events,
            diagnosticSink: HostDiagnosticSink(emitter: events),
            vocabulary: HostLanguageVocabulary(contributionPoint: languagePoint),
            messagePresenter: NSAlertMessagePresenter(window: seams.frontWindow),
            pickerPresenter: ExtensionPickerPresenter(),
            statusBarPresenter: WindowFooterStatusBarPresenter(
                footers: seams.footers,
                // `try?` would be exactly the silent no-op
                // `CommandRegistryError`'s own doc says this registry must
                // never produce: "a discarded `Bool` is a silent no-op the
                // compiler will not complain about, and 'nothing happened' is
                // the exact failure this registry must never produce quietly"
                // (`AppCommand.swift`). A status bar item whose command is a
                // typo, or belongs to an extension that failed to load, is a
                // click that does nothing forever — and this is the one path
                // with no extension JavaScript on the stack to receive a
                // rejection, so the log is where it has to land.
                onCommand: { [weak registry = seams.commandRegistry] command in
                    guard let registry else { return }
                    do {
                        try registry.execute(id: command)
                    } catch {
                        ExtensionHostInstaller.logger.error(
                            """
                            A status bar item's command '\(command, privacy: .public)' did not run: \
                            \(String(describing: error), privacy: .public)
                            """)
                    }
                }),
            webviewPresenter: PaneWebviewPresenter(place: seams.placeWebviewPanel),
            workspaceRoots: workspaceRoots,
            fileSystemService: seams.fileSystemService)
    }

    // MARK: - Bringing hosts up

    /// Brings up a host for every enabled extension, activates the ones that
    /// asked for startup, and starts the workspace scan the rest may be
    /// waiting on.
    ///
    /// Idempotent in the sense that matters: an extension whose identity has
    /// not moved keeps the host it has, so this is also the reconcile called
    /// when the registry's contributions change.
    ///
    /// **Identity, not identifier.** Keying on the identifier alone made
    /// "already installed" mean "never install again": `ExtensionRegistry
    /// .loadAll()` re-reads every manifest from disk and fires
    /// `contributionsDidChange`, so an extension edited and rescanned arrived
    /// here with a new `LoadedExtension` and was skipped — the running host
    /// went on executing the previous code, with the registry, the
    /// contribution points and the settings UI all showing the new manifest.
    /// An author editing an extension saw their changes appear everywhere
    /// except in the extension. Comparing `InstalledIdentity` disposes that
    /// host and brings up a fresh one instead.
    public func reconcile() {
        let enabled = registry.extensions.filter { registry.isEnabled($0.identifier) }
        let enabledIdentifiers = Set(enabled.map(\.identifier))

        for (identifier, entry) in installed where !enabledIdentifiers.contains(identifier) {
            entry.installation.dispose()
            installed[identifier] = nil
        }

        for loaded in enabled {
            let identity = InstalledIdentity(
                loaded: loaded, entryPoint: Self.entryPointSignature(for: loaded))
            if let current = installed[loaded.identifier] {
                guard current.identity != identity else { continue }
                // Disposed before the replacement is built, not after: the two
                // hosts would otherwise both be live across the `bringUp`,
                // each holding this extension's identifier in five adaptors
                // that record against it, and the teardown of the old one
                // would then withdraw the new one's registrations.
                current.installation.dispose()
                installed[loaded.identifier] = nil
            }
            bringUp(loaded, identity: identity)
        }

        startWorkspaceScanIfNeeded()
    }

    private func bringUp(_ loaded: LoadedExtension, identity: InstalledIdentity) {
        let installation: ExtensionHostInstallation
        do {
            installation = try ExtensionHostInstallation(
                loadedExtension: loaded,
                notImplementedLedger: notImplementedLedger,
                collaborators: collaborators,
                seams: seams)
        } catch {
            Self.logger.error(
                """
                Extension '\(loaded.identifier, privacy: .public)' could not be installed: \
                \(error.localizedDescription, privacy: .public)
                """)
            return
        }
        installed[loaded.identifier] = Installed(installation: installation, identity: identity)
        installation.registerActivationCommands(loaded.manifest.contributes?.commands ?? [])
        installation.activateIfTriggered(by: .startupFinished)
        // Replayed only while it still describes the open workspace. A scan
        // taken from a project the user has since closed is not a weaker
        // answer than none — it activates an extension on a file that is not
        // there, and `workspaceContains:` is the one trigger whose whole
        // meaning is "this project looks like mine".
        if let completedScan,
           completedScan.roots == (seams.workspaceRoots()?.workspaceRootURLs ?? []) {
            installation.activateIfTriggered(by: .workspaceScanned(completedScan.scan))
        }
        // The same replay, for `onLanguage:`. An extension enabled while a
        // Swift file is already on screen never sees the `.opened` event that
        // has already been delivered, and `onLanguage:swift` means "a
        // document of this language is open", not "one opened after you were
        // installed". Read live rather than from a remembered set, so a
        // document since closed cannot activate anything.
        for languageID in seams.openDocumentLanguageIDs() {
            installation.activateIfTriggered(by: .documentOpened(languageID: languageID))
        }
    }

    /// Tells every installed extension that a document of `languageID` was
    /// opened, which is what `onLanguage:<id>` activates on.
    ///
    /// The app forwards this from the one shared `TextDocumentStore`; there
    /// is no equivalent on close, because `onLanguage:` has no un-activation
    /// — an extension that has run cannot be made not to have run.
    public func documentDidOpen(languageID: String) {
        for entry in installed.values {
            entry.installation.activateIfTriggered(by: .documentOpened(languageID: languageID))
        }
    }

    /// Rebuilds the webview panel a pane restored from a persisted layout is
    /// supposed to hold, and hands it to the extension that owns its view type.
    ///
    /// **The panel cannot be built by its caller, which is why this builds it.**
    /// A webview's `enableScripts` is baked into its `WKWebViewConfiguration`
    /// at first load, and its `localResourceRoots` resolve against the *owning
    /// extension's* directory — so a panel has to know which extension it
    /// belongs to before it exists, and that is precisely what is being decided
    /// here. `makePanel` receives the resolved roots and answers with the
    /// panel; it is not called at all when nobody claims the view type, so
    /// nothing is built for a panel that has nowhere to go.
    ///
    /// Exactly one extension is asked, and it is asked by *claim* rather than
    /// by broadcast — every other signal here (a document opened, a command
    /// invoked) is news that any number of extensions may care about, but a
    /// restored panel belongs to one of them and delivering it twice would
    /// give two extensions a handle on the same page.
    ///
    /// **A view type nobody claims leaves the pane blank, and says so.** That
    /// is a real state with real causes — the extension was uninstalled or
    /// disabled since the layout was saved — and it is not this installer's
    /// place to close a pane the user arranged.
    ///
    /// Generic over the panel rather than returning `any ExtensionWebviewPanel`
    /// so the caller gets back exactly what it built — this type has no
    /// business naming `WebviewPanelViewController`, and the caller has no
    /// business downcasting to it.
    ///
    /// - Returns: The panel `makePanel` built, or `nil` when no installed
    ///   extension claims the view type. A returned panel is claimed, not yet
    ///   deserialized: an extension that has to be activated first fills it a
    ///   turn or two later, or logs why it could not.
    public func restoreWebviewPanel<Panel: ExtensionWebviewPanel>(
        state: WebviewPanelState,
        makePanel: (_ localResourceRoots: [URL]) -> Panel
    ) -> Panel? {
        // Sorted, so which extension wins a contested view type is the same
        // on every launch. Two extensions claiming one view type is their
        // authors' bug; answering it differently each time would make it look
        // like this app's.
        let claimants = installed.values
            .map(\.installation)
            .filter { $0.claimsWebviewPanel(viewType: state.viewType) }
            .sorted { $0.identifier < $1.identifier }
        guard let owner = claimants.first else {
            Self.logger.notice(
                """
                A restored webview panel of type '\(state.viewType, privacy: .public)' has no \
                installed extension claiming it; its pane stays blank
                """)
            return nil
        }
        if claimants.count > 1 {
            Self.logger.error(
                """
                \(claimants.count, privacy: .public) installed extensions claim webview panel type \
                '\(state.viewType, privacy: .public)'; \
                '\(owner.identifier, privacy: .public)' gets it
                """)
        }
        let panel = makePanel(owner.resourceRoots(for: state.options))
        owner.restoreWebviewPanel(panel, state: state)
        return panel
    }

    /// Builds the webview a contributed view of `view` is supposed to hold,
    /// and hands it to the extension whose manifest contributed it.
    ///
    /// `restoreWebviewPanel(state:makePanel:)`'s twin, and different in exactly
    /// one way that matters: **there is no claim contest here.** A restored
    /// panel is a view type with no owner written down anywhere, so ownership
    /// has to be inferred from who claims it; a contributed view was *declared*
    /// by a named extension, and `ContributedView.extensionIdentifier` is that
    /// name. Asking every installation whether it claims the id would invite
    /// exactly the ambiguity the manifest already settled.
    ///
    /// `makePanel` receives the resolved roots and builds the panel, for the
    /// sibling's reason — the roots resolve against the owning extension's
    /// directory, which only this type knows. It is not called when the
    /// extension is not installed, so nothing is built for a view with nobody
    /// to draw it.
    ///
    /// The broadcast half of the same moment is
    /// `contributedViewWillAppear(viewID:)`, which is separate on purpose: this
    /// resolves *the owner's* view, while `onView:` is an activation event any
    /// extension may declare against any view id, including someone else's.
    ///
    /// - Returns: The panel `makePanel` built, or `nil` when the contributing
    ///   extension is not installed — a real state (disabled since the layout
    ///   was last read) whose pane keeps its placeholder.
    /// - Parameter didResolve: Called once the extension's provider has taken
    ///   the panel — synchronously when it is already awake, a turn or two
    ///   later when it had to be activated first, and never when it registers
    ///   no provider. It is what tells the pane to stop explaining itself and
    ///   show the page, so a provider that never runs leaves the explanation
    ///   up, which is the truthful outcome.
    public func resolveWebviewView<Panel: ExtensionWebviewPanel>(
        view: ContributedView,
        makePanel: (_ localResourceRoots: [URL]) -> Panel,
        didResolve: @escaping () -> Void
    ) -> Panel? {
        guard let owner = installed[view.extensionIdentifier]?.installation else {
            Self.logger.notice(
                """
                The contributed webview view '\(view.viewID, privacy: .public)' names extension \
                '\(view.extensionIdentifier, privacy: .public)', which is not installed; its pane \
                keeps its placeholder
                """)
            return nil
        }
        // No declared options to resolve against: a contributed view's manifest
        // entry carries no `webviewOptions`, and the provider sets them from
        // inside `resolveWebviewView`. So the roots start at the defaults —
        // the extension's own directory and the open workspace — which is what
        // `WebviewPanelOptions` yields for a panel that declared none either.
        let panel = makePanel(owner.resourceRoots(
            for: WebviewPanelOptions(
                enableScripts: nil, enableForms: nil, localResourceRoots: nil)))
        owner.resolveWebviewView(panel, viewID: view.viewID, then: didResolve)
        return panel
    }

    /// Finds the tree data provider the contributed view `view` should draw,
    /// waking its extension first if that is what it takes.
    ///
    /// `resolveWebviewView(view:makePanel:didResolve:)`'s twin, and addressed
    /// the same way: to the one extension that declared the view, because the
    /// provider for a view id is that extension's to register. The broadcast
    /// an extension *adding* to someone else's view is woken by is
    /// `contributedViewWillAppear(viewID:)` below, which runs for this pane too.
    ///
    /// - Parameter didResolve: Called with the data source once the extension
    ///   has registered one — synchronously when it is already awake, a turn or
    ///   two later when it had to be activated first, and never when it
    ///   registers none, which leaves the pane showing its explanation.
    public func resolveTreeView(
        view: ContributedView,
        didResolve: @escaping (any ExtensionTreeDataSource) -> Void
    ) {
        guard let owner = installed[view.extensionIdentifier]?.installation else {
            Self.logger.notice(
                """
                The contributed tree view '\(view.viewID, privacy: .public)' names extension \
                '\(view.extensionIdentifier, privacy: .public)', which is not installed; its pane \
                keeps its placeholder
                """)
            return
        }
        owner.resolveTreeView(viewID: view.viewID, then: didResolve)
    }

    /// Tells every installed extension that a pane showing the contributed view
    /// `viewID` has just been built, which is what `onView:<id>` activates on.
    ///
    /// A broadcast, unlike `resolveWebviewView(view:makePanel:)` directly
    /// above, and the pairing is the point. Upstream lets any extension declare
    /// `onView:` against any view id — including one another extension
    /// contributed, which is how an extension that *adds* to someone else's
    /// tree gets woken — so an ownership lookup would never find it. Both run
    /// for a webview view; only this one runs for a tree view, which has no
    /// provider to resolve.
    public func contributedViewWillAppear(viewID: String) {
        for entry in installed.values {
            entry.installation.activateIfTriggered(by: .viewShown(viewID: viewID))
        }
    }

    /// Tells every running extension that the configured chat models moved.
    public func availableChatModelsDidChange() {
        for entry in installed.values {
            entry.installation.availableChatModelsDidChange()
        }
    }

    public func disposeAll() {
        for entry in installed.values {
            entry.installation.dispose()
        }
        installed = [:]
    }

    // MARK: - workspaceContains:

    /// How deep the scan walks, and how many entries it will collect.
    ///
    /// All three constants in this section are `nonisolated`: `scan(roots:)`
    /// reads them from inside a detached task, which is the whole point of
    /// that task — the walk is the expensive part and it must not run on the
    /// main actor. They are immutable values of `Sendable` type, so leaving
    /// the actor is exactly as safe as reading a global `let`.
    ///
    /// `workspaceContains:` patterns are overwhelmingly shallow — a
    /// `package.json`, a `.csproj`, a `Cargo.toml` — and the cost of being
    /// wrong in the other direction is a full recursive walk of a source tree
    /// at every launch. A pattern that genuinely needs more than six levels
    /// goes unmatched, and the extension stays dormant until its command is
    /// invoked, which is a worse outcome than a launch that stalls.
    private nonisolated static let scanDepthLimit = 6

    /// The entry cap. Reached on a large tree, at which point the scan stops
    /// and matches against what it has.
    private nonisolated static let scanEntryLimit = 20_000

    /// Directories the scan never descends into. Every one of them is either
    /// machine-generated or a checkout of somebody else's source, and a
    /// `workspaceContains:` pattern matching inside one is matching a fact
    /// about a dependency rather than about this project.
    private nonisolated static let skippedDirectoryNames: Set<String> = [
        ".build", ".git", ".svn", ".venv", "DerivedData", "Pods",
        "__pycache__", "build", "dist", "node_modules", "target", "vendor"
    ]

    /// Tells the installer the workspace may have changed — a project opened,
    /// closed, or replaced the one before it — so a `workspaceContains:`
    /// extension that could not match the old workspace gets its chance at
    /// the new one.
    ///
    /// Separate from `reconcile()` because the two answer different questions:
    /// `reconcile()` is about which extensions are enabled, this is about what
    /// is on disk, and the events that move them are unrelated.
    public func workspaceDidChange() {
        startWorkspaceScanIfNeeded()
    }

    /// Tells the status bar presenter that the set of windows moved, so a
    /// footer that did not exist at the last render picks up the items already
    /// up.
    ///
    /// The presenter drives itself off `NSWindow.didBecomeKeyNotification`
    /// too, and that is deliberately kept: it is the generic AppKit fact, and
    /// it covers a host that has no better signal. This is the better signal —
    /// it fires on the window *set* changing, which is the event that actually
    /// matters, and it fires for the case the key-window notification cannot
    /// see at all: a window opened without taking key.
    ///
    /// Forwarded from here rather than by handing the presenter out, because
    /// the presenter is one of this installer's shared collaborators and
    /// nothing outside should be able to put items on it.
    public func windowsDidChange() {
        collaborators.statusBarPresenter.windowsDidChange()
    }

    /// Runs the scan, off the main actor, and replays the result at every host
    /// — including the ones that come up later.
    ///
    /// Once *per workspace*, not once per reconcile and not once per
    /// installer:
    ///
    ///  - Re-walking the tree whenever the registry's contributions change
    ///    would make a settings panel expensive to use, since toggling an
    ///    extension says nothing about the files on disk. So a scan whose
    ///    roots match the current ones is reused.
    ///  - But keying on "has a scan ever run" was wrong in the case that
    ///    actually happens: extensions are brought up at app launch, ahead of
    ///    any project window, so the first call routinely finds no roots. It
    ///    returned having recorded nothing, nothing ever called it again, and
    ///    every `workspaceContains:` extension stayed dormant for the life of
    ///    the process. An empty-roots call now records nothing *and* leaves
    ///    the next call free to scan, which is what `workspaceDidChange()` is
    ///    for.
    ///  - And a project switch must not replay the old project's paths at a
    ///    newly installed extension, which is why `completedScan` carries the
    ///    roots it was taken from — nor record them, which is why the
    ///    completion below compares against the *live* roots and not only
    ///    against `scanningRoots`.
    private func startWorkspaceScanIfNeeded() {
        let roots = seams.workspaceRoots()?.workspaceRootURLs ?? []
        // No workspace to scan. Deliberately records nothing: this is the
        // launch-time state, not an answer.
        guard !roots.isEmpty else { return }
        guard completedScan?.roots != roots, scanningRoots != roots else { return }
        scanningRoots = roots
        Task { @MainActor [weak self] in
            let paths = await Self.scan(roots: roots)
            // A scan superseded by a *newer* scan is discarded and nothing
            // else: `scanningRoots` already names the walk that replaced it,
            // and clearing it here would cancel that one's own completion.
            guard let self, self.scanningRoots == roots else { return }
            self.scanningRoots = nil

            // And a scan superseded by the workspace *moving back* is
            // discarded too — the case `scanningRoots` alone cannot see.
            // Roots A, then B, then A again: the return to A is refused a
            // scan by the guard above, correctly, because `completedScan`
            // still holds A's paths. But the walk of B is still running, and
            // recording it here would file B's paths as the answer for a
            // workspace showing A, replay them at every extension, and then
            // *stay* wrong — the next `workspaceDidChange()` for A would find
            // `completedScan.roots` reading B and start a walk, while every
            // extension already activated on files from a project that is not
            // open. So the live roots are re-read and compared, and a
            // mismatch records nothing and replays nothing.
            let liveRoots = self.seams.workspaceRoots()?.workspaceRootURLs ?? []
            guard liveRoots == roots else {
                // Whatever is open now may never have been walked — A had an
                // answer in this example, C in an A→B→C→B ordering would not
                // — and nothing else is going to ask. The re-entry is cheap
                // and idempotent: it returns immediately when `completedScan`
                // already describes the live roots.
                self.startWorkspaceScanIfNeeded()
                return
            }

            let scan = WorkspaceScan(relativePaths: paths)
            self.completedScan = CompletedScan(roots: roots, scan: scan)
            for entry in self.installed.values {
                entry.installation.activateIfTriggered(by: .workspaceScanned(scan))
            }
        }
    }

    /// Every file under `roots`, as a path relative to the root it was found
    /// under — which is the vocabulary `workspaceContains:` globs are written
    /// in.
    private static func scan(roots: [URL]) async -> [String] {
        await Task.detached(priority: .utility) {
            var found: [String] = []
            let manager = FileManager.default
            for root in roots {
                let prefix = root.standardizedFileURL.path + "/"
                // Deliberately **not** `.skipsHiddenFiles`. The most common
                // `workspaceContains:` patterns in the wild name dotfiles —
                // `.vscode/launch.json`, `.eslintrc*`, `.editorconfig`,
                // `.devcontainer/devcontainer.json` — and skipping hidden
                // entries made every one of them unmatchable, silently: the
                // extension simply never activated, with nothing anywhere
                // saying why. The cost of dropping the option is bounded by
                // `skippedDirectoryNames`, which already excludes the hidden
                // directories that are actually large (`.git`, `.build`,
                // `.venv`).
                let enumerator = manager.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsPackageDescendants])
                guard let enumerator else { continue }
                while let url = enumerator.nextObject() as? URL {
                    if found.count >= scanEntryLimit { break }
                    let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?
                        .isDirectory ?? false
                    if isDirectory {
                        if skippedDirectoryNames.contains(url.lastPathComponent)
                            || enumerator.level >= scanDepthLimit {
                            enumerator.skipDescendants()
                        }
                        continue
                    }
                    let path = url.standardizedFileURL.path
                    guard path.hasPrefix(prefix) else { continue }
                    found.append(String(path.dropFirst(prefix.count)))
                }
            }
            return found
        }.value
    }
}

extension ExtensionHostInstaller: Loggable {
    public static nonisolated let logger = makeLogger()
}
