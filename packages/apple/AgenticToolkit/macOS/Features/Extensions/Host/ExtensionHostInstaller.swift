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

    /// Where an alert sheet attaches, or `nil` for an app-modal alert.
    public let frontWindow: () -> NSWindow?

    /// Every footer a status bar item renders into.
    public let footers: () -> [WindowFooterBar]

    /// The workspace extensions see right now, or `nil` when no project is
    /// open.
    public let workspaceRoots: () -> ExtensionWorkspaceRoots?

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
        openDocumentLanguageIDs: @escaping () -> [String]
    ) {
        self.commandRegistry = commandRegistry
        self.languageModelProvider = languageModelProvider
        self.frontWindow = frontWindow
        self.footers = footers
        self.workspaceRoots = workspaceRoots
        self.openDocumentLanguageIDs = openDocumentLanguageIDs
    }
}

/// One extension's `ExtensionHost`, its six `vscode` namespace adaptors, and
/// the activation that decides when its code runs.
///
/// ### Why the adaptors are held
///
/// `ExtensionHost.defineVSCodeMember` takes `implementation: Any` — the
/// `lazy var` block an adaptor exposes — and the host keeps only that block.
/// Nothing in the host keeps the adaptor that vended it alive, and every one
/// of the six owns state the block reads (a registry handle, a disposable
/// table, a pending continuation). Dropping an adaptor after installing its
/// members is the shape where an extension's first call reaches a
/// deallocated owner, so all six are stored here for as long as the host is.
///
/// ### One host per extension, one set of adaptors per host
///
/// The adaptors are per extension because five of the six take
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
    private let diagnostics: MainThreadDiagnostics

    private let commandRegistry: CommandRegistry

    /// The registration token for each stub command still standing, keyed by
    /// command id. An id leaves this table the first time the stub fires;
    /// see `dispatchAfterActivation(commandID:arguments:)` for what the token
    /// is actually for.
    private var stubCommands: [String: CommandRegistration] = [:]

    private var isDisposed = false

    // MARK: - Construction

    /// Builds the host and all six adaptors over the shared collaborators
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
            extensionIdentifier: identifier)
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
        self.diagnostics = MainThreadDiagnostics(
            store: collaborators.diagnosticStore,
            sink: collaborators.diagnosticSink,
            events: collaborators.diagnosticEvents)

        try installVSCodeMembers()
    }

    /// Installs all twenty members and all three enum tables.
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
            let token = commandRegistry.register(AppCommand(
                id: id,
                title: command.title,
                category: command.category ?? "",
                run: { [weak self] arguments in
                    self?.runActivationStub(commandID: id, arguments: arguments)
                    return nil
                }))
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
    /// Stubs first — a stub left in the registry outlives everything it can
    /// reach and would activate a disposed host on the next press. Then the
    /// six adaptors, each of which withdraws what it registered elsewhere
    /// (commands, language configurations, status bar items, diagnostic
    /// collections). The host last, because disposing it first would leave
    /// those withdrawals running against a dead runtime.
    public func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        for (id, token) in stubCommands {
            commandRegistry.unregister(id: id, token: token)
        }
        stubCommands = [:]
        commands.dispose()
        languages.dispose()
        workspace.dispose()
        languageModels.dispose()
        window.dispose()
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
/// Per extension: one `ExtensionHost` and one of each adaptor, because five
/// of the six record against an `extensionIdentifier`.
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
        let workspaceRoots: ClosureWorkspaceRoots
    }

    private let registry: ExtensionRegistry
    private let notImplementedLedger: NotImplementedLedger
    private let seams: ExtensionHostSeams
    private let collaborators: Collaborators

    /// One installation per running extension, keyed by identifier.
    public private(set) var installations: [String: ExtensionHostInstallation] = [:]

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
        let relativePaths: [String]
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
            workspaceRoots: workspaceRoots)
    }

    // MARK: - Bringing hosts up

    /// Brings up a host for every enabled extension, activates the ones that
    /// asked for startup, and starts the workspace scan the rest may be
    /// waiting on.
    ///
    /// Idempotent: an extension that already has a host keeps it, so this is
    /// also the reconcile called when the registry's contributions change.
    public func reconcile() {
        let enabled = registry.extensions.filter { registry.isEnabled($0.identifier) }
        let enabledIdentifiers = Set(enabled.map(\.identifier))

        for (identifier, installation) in installations where !enabledIdentifiers.contains(identifier) {
            installation.dispose()
            installations[identifier] = nil
        }

        for loaded in enabled where installations[loaded.identifier] == nil {
            bringUp(loaded)
        }

        startWorkspaceScanIfNeeded()
    }

    private func bringUp(_ loaded: LoadedExtension) {
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
        installations[loaded.identifier] = installation
        installation.registerActivationCommands(loaded.manifest.contributes?.commands ?? [])
        installation.activateIfTriggered(by: .startupFinished)
        // Replayed only while it still describes the open workspace. A scan
        // taken from a project the user has since closed is not a weaker
        // answer than none — it activates an extension on a file that is not
        // there, and `workspaceContains:` is the one trigger whose whole
        // meaning is "this project looks like mine".
        if let completedScan,
           completedScan.roots == (seams.workspaceRoots()?.workspaceRootURLs ?? []) {
            installation.activateIfTriggered(
                by: .workspaceScanned(relativePaths: completedScan.relativePaths))
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
        for installation in installations.values {
            installation.activateIfTriggered(by: .documentOpened(languageID: languageID))
        }
    }

    /// Tells every running extension that the configured chat models moved.
    public func availableChatModelsDidChange() {
        for installation in installations.values {
            installation.availableChatModelsDidChange()
        }
    }

    public func disposeAll() {
        for installation in installations.values {
            installation.dispose()
        }
        installations = [:]
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
    ///    roots it was taken from.
    private func startWorkspaceScanIfNeeded() {
        let roots = seams.workspaceRoots()?.workspaceRootURLs ?? []
        // No workspace to scan. Deliberately records nothing: this is the
        // launch-time state, not an answer.
        guard !roots.isEmpty else { return }
        guard completedScan?.roots != roots, scanningRoots != roots else { return }
        scanningRoots = roots
        Task { @MainActor [weak self] in
            let paths = await Self.scan(roots: roots)
            // A scan whose roots were superseded while it ran is discarded,
            // not recorded: the tree it walked is no longer the workspace.
            guard let self, self.scanningRoots == roots else { return }
            self.scanningRoots = nil
            self.completedScan = CompletedScan(roots: roots, relativePaths: paths)
            for installation in self.installations.values {
                installation.activateIfTriggered(by: .workspaceScanned(relativePaths: paths))
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
