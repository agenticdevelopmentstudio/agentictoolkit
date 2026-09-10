//
//  ExtensionsSettingsPanelViewController.swift
//  AgenticToolkit
//

import AppKit
import Foundation

import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// The Extensions settings panel: what is installed, what each one contributes,
/// and everything the app decided on the author's behalf while loading it.
///
/// A topic/detail split on the `AIPanelViewController` model — one detail panel
/// per loaded extension, plus a trailing panel for anything that went wrong.
/// It is the only place the work of Tasks 4.3–4.5 is visible at all.
@MainActor
public final class ExtensionsSettingsPanelViewController: ComposableSettings.SettingsPanelSplitViewController {

    private let coordinator: ExtensionsCoordinator

    private var registry: ExtensionRegistry { coordinator.registry }

    public init(coordinator: ExtensionsCoordinator) {
        self.coordinator = coordinator
        super.init(with: ComposableSettings.SettingsPanelDescriptor(
            title: "Extensions",
            icon: NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: nil)
        ))
        // The sidebar lists extensions, not sub-topics of one extension.
        sidebarTitle = "Installed"
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var helpContent: ComposableSettings.PanelHelp? {
        ComposableSettings.PanelHelp(topics: [
            .init(
                title: "What an Extension Is",
                body: "A VS Code extension folder — a package.json plus the files it names. "
                    + "This app reads the parts of one that need no code to run: colour "
                    + "themes, snippets, file-type mappings, settings and view panes. "
                    + "Anything an extension does by *running* code needs an extension host, "
                    + "which this app does not have yet."
            ),
            .init(
                title: "Installing One",
                body: "Unpack the extension (a .vsix file is a zip) into one of the folders "
                    + "listed under Extensions, then relaunch: extensions are read once at "
                    + "startup. Installing from inside the app, and a marketplace to install "
                    + "from, are not built yet."
            ),
            .init(
                title: "Turning One Off",
                body: "The switch on an extension applies or withdraws everything it "
                    + "contributed, immediately — its themes leave the theme list, its "
                    + "snippets stop completing. Uninstall deletes the folder from disk; "
                    + "reinstalling it is the only way back."
            )
        ])
    }

    /// The detail panels are built lazily and one of them is generated SwiftUI,
    /// so almost nothing here is readable off the view tree. These terms are how
    /// settings search finds the panel at all.
    public override var searchKeywords: [String] {
        [
            "extension", "extensions", "vscode", "vsix", "marketplace",
            "theme", "snippet", "plugin", "contributes", "package.json"
        ]
    }

    /// The per-extension panels, in sidebar order.
    var extensionPanels: [ExtensionDetailPanel] {
        panels.compactMap { $0 as? ExtensionDetailPanel }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        rebuildPanels()
    }

    /// Rebuilds the sidebar and selects `index`, clamped to what is left.
    ///
    /// Every panel is a fresh object after a rebuild, so the split view's own
    /// identity-based restore cannot recognise the survivors — the selection
    /// has to be named positionally from here.
    private func rebuildPanels(selecting index: Int = 0) {
        var built: [any ComposableSettingsPanel] = registry.extensions.map { loaded in
            ExtensionDetailPanel(
                loaded: loaded,
                coordinator: coordinator,
                onUninstalled: { [weak self] in
                    guard let self else { return }
                    // Uninstalling the fourth of five extensions should leave
                    // the reader where they were rather than at the top of the
                    // list: whatever takes the removed row's place is the
                    // nearest thing to "still here".
                    let removed = self.panels.firstIndex {
                        ($0 as? ExtensionDetailPanel)?.extensionIdentifier == loaded.identifier
                    }
                    self.rebuildPanels(selecting: removed ?? 0)
                }
            )
        }

        // No extensions is the normal case today. A blank detail pane reads as a
        // broken panel; saying where extensions are looked for is the one thing
        // a user in that state can act on.
        if built.isEmpty {
            built.append(ExtensionsEmptyStatePanel(searchPaths: coordinator.searchPaths))
        }

        if !registry.failures.isEmpty {
            built.append(ExtensionLoadProblemsPanel(
                failures: registry.failures,
                // The same answer the theme prune was given, so the sentence
                // in the panel and the behaviour it describes cannot drift
                // apart.
                scanIdentifiedEveryExtension: registry.establishedIdentifiers != nil
            ))
        }

        setPanels(built)
        selectPanel(at: min(max(index, 0), built.count - 1))
    }
}

// MARK: - One extension

/// Everything known about one loaded extension: what it is, whether it is on,
/// what it contributed, what this app decided for it, and how to remove it.
@MainActor
final class ExtensionDetailPanel: ComposableSettings.SettingsPanelViewController {

    let loaded: LoadedExtension
    private let coordinator: ExtensionsCoordinator
    /// Internal rather than private so a test can stand where the alert's
    /// Uninstall button stands. Presenting the alert needs a window and a
    /// modal loop; what is worth pinning is the rebuild it asks for.
    let onUninstalled: () -> Void

    /// The enable/disable control. A plain `NSSwitch` rather than the
    /// vocabulary's `CheckboxView`, which is bound to a `UserSetting<Bool>`:
    /// enablement is a `Set<String>` that must be changed through
    /// `ExtensionRegistry.setEnabled(_:for:)` so contributions are applied or
    /// withdrawn in the same call. A shadow per-extension setting would give the
    /// panel and the registry two sources of truth for one fact.
    private(set) var enableSwitch: NSSwitch?

    /// Not `identifier`: `NSViewController` inherits one from
    /// `NSUserInterfaceItemIdentification`, of a different type.
    var extensionIdentifier: String { loaded.identifier }

    init(
        loaded: LoadedExtension,
        coordinator: ExtensionsCoordinator,
        onUninstalled: @escaping () -> Void
    ) {
        self.loaded = loaded
        self.coordinator = coordinator
        self.onUninstalled = onUninstalled
        super.init(with: ComposableSettings.SettingsPanelDescriptor(
            title: loaded.manifest.displayName ?? loaded.manifest.name
        ))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var helpContent: ComposableSettings.PanelHelp? {
        ComposableSettings.PanelHelp(topics: [
            .init(
                title: "What This App Decided",
                body: "An extension declares more than any one editor can honour. Where a "
                    + "declaration could not be used exactly as written — a matcher this app "
                    + "cannot apply, a setting type it cannot draw, an icon it has no symbol "
                    + "for — it says so rather than doing nothing quietly. None of it means "
                    + "the extension is broken."
            )
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        addGroup(makeIdentityGroup())
        addGroup(makeStateGroup())

        if let contributions = loaded.manifest.contributes {
            let lines = Self.contributionSummaryLines(for: contributions)
            if !lines.isEmpty {
                let group = ComposableSettings.GroupView(withTitle: "Contributes")
                for line in lines {
                    group.addSettingSubview(ComposableSettings.ExplanationView(withText: line))
                }
                addGroup(group)
            }
        }

        addContributedSettingsGroup()
        addContributedViewsGroup()
        addDecisionsGroup()
        addGroup(makeUninstallGroup())
    }

    // MARK: - Groups

    private func makeIdentityGroup() -> ComposableSettings.GroupView {
        let manifest = loaded.manifest
        let group = ComposableSettings.GroupView(withTitle: manifest.displayName ?? manifest.name)
        if let description = manifest.description, !description.isEmpty {
            group.addSettingSubview(ComposableSettings.ExplanationView(withText: description))
        }
        group.addSettingSubview(
            ComposableSettings.ExplanationView(withText: "Version \(manifest.version)"))
        group.addSettingSubview(
            ComposableSettings.ExplanationView(
                withText: manifest.publisher.map { "Published by \($0)" }
                    ?? "No publisher declared"),
            style: .continuation)
        group.addSettingSubview(
            ComposableSettings.ExplanationView(withText: "Identifier: \(manifest.identifier)"),
            style: .continuation)
        group.addSettingSubview(
            ComposableSettings.ExplanationView(withText: "Folder: \(loaded.directory.path)"),
            style: .continuation)
        return group
    }

    private func makeStateGroup() -> ComposableSettings.GroupView {
        let group = ComposableSettings.GroupView(withTitle: "Status")
        let label = ComposableSettings.makeRowLabel("Enabled")
        let toggle = NSSwitch()
        toggle.state = coordinator.registry.isEnabled(extensionIdentifier) ? .on : .off
        toggle.target = self
        toggle.action = #selector(enabledDidChange(_:))
        // A bare switch has no name of its own, so VoiceOver would announce it
        // as an unlabelled control.
        toggle.setAccessibilityTitleUIElement(label)
        self.enableSwitch = toggle

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView.makeRow([label, toggle])
        row.addSubview(content)
        NSView.pinToEdges(content, of: row)
        group.addSettingSubview(row)

        group.addSettingSubview(
            ComposableSettings.ExplanationView(
                withText: "Turning this off withdraws everything the extension contributed, "
                    + "without deleting it."),
            style: .continuation)
        return group
    }

    private func addContributedSettingsGroup() {
        guard let panel = coordinator.configurationPoint.panel(for: extensionIdentifier) else { return }
        // A child view controller, not a loose view: the generated panel builds
        // its rows in `viewDidLoad` and owns the controls' targets, both of
        // which need a live controller in the responder chain.
        addChild(panel)
        let group = ComposableSettings.GroupView(withTitle: "Settings")
        group.addSettingSubview(panel.view)
        addGroup(group)
    }

    private func addContributedViewsGroup() {
        let views = coordinator.viewsPoint?.views(for: extensionIdentifier) ?? []
        let notes = coordinator.viewsPoint?.notes.filter { $0.extensionIdentifier == extensionIdentifier } ?? []
        guard !views.isEmpty else { return }

        let group = ComposableSettings.GroupView(withTitle: "Views")
        // Stated unconditionally, as a property of the group rather than a
        // rendering of the notes: a tree view — the overwhelming majority —
        // produces no note at all, so a sentence derived from the notes would
        // say "webviews are unsupported" beside a silent list of tree views and
        // leave the reader concluding those work.
        group.addSettingSubview(ComposableSettings.ExplanationView(
            withText: "These panes are registered and can be opened. What they show is not "
                + "implemented yet: a view's content is drawn by the extension's own code, "
                + "which needs an extension host this app does not run."))
        for view in views {
            group.addSettingSubview(
                ComposableSettings.ExplanationView(withText: "\(view.name) (\(view.viewID))"))
            for note in notes where note.viewID == view.viewID {
                group.addSettingSubview(
                    ComposableSettings.ExplanationView(withText: note.detail),
                    style: .continuation)
            }
        }
        addGroup(group)
    }

    private func addDecisionsGroup() {
        let lines = decisionLines()
        guard !lines.isEmpty else { return }
        // Titled for what these actually are. Most are not failures: a default
        // this app supplied, a section name it invented, a clause it stored
        // without evaluating. Sorting them by severity is a judgment nobody has
        // the data to make — the same note is trivia to one author and the
        // answer to another's whole afternoon.
        let group = ComposableSettings.GroupView(withTitle: "Decisions this app made")
        for line in lines {
            group.addSettingSubview(ComposableSettings.ExplanationView(withText: line))
        }
        addGroup(group)
    }

    private func makeUninstallGroup() -> ComposableSettings.GroupView {
        let group = ComposableSettings.GroupView(withTitle: "Uninstall")
        let button = ComposableSettings.ButtonView(
            viewModel: ComposableSettings.ButtonViewModel(
                title: "Uninstall…",
                explanation: "Deletes the extension's folder from disk.",
                wasPressedCallback: { [weak self] in self?.confirmUninstall() }
            )
        )
        group.addSettingSubview(button)
        return group
    }

    // MARK: - Actions

    @objc private func enabledDidChange(_ sender: NSSwitch) {
        // Through the registry, never through the setting: this is the call that
        // applies or withdraws the contributions, and the stored set is its
        // record rather than the other way round.
        coordinator.registry.setEnabled(sender.state == .on, for: extensionIdentifier)
    }

    private func confirmUninstall() {
        let name = loaded.manifest.displayName ?? loaded.manifest.name
        let alert = NSAlert()
        alert.messageText = "Uninstall “\(name)”?"
        alert.informativeText = "The folder at \(loaded.directory.path) will be deleted. "
            + "Everything this extension contributed is withdrawn. You can install it again later."
        // Cancel first, so Return cancels. Not a `.critical` alert: this is
        // recoverable by reinstalling.
        alert.addButton(withTitle: "Cancel")
        let uninstall = alert.addButton(withTitle: "Uninstall")
        uninstall.hasDestructiveAction = true

        if let window = view.window {
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertSecondButtonReturn { self?.performUninstall() }
            }
        } else if alert.runModal() == .alertSecondButtonReturn {
            performUninstall()
        }
    }

    private func performUninstall() {
        do {
            try coordinator.registry.uninstall(extensionIdentifier)
            onUninstalled()
        } catch {
            // The registry's contract is that a throw leaves the extension fully
            // intact, so the row stays exactly where it is.
            let name = loaded.manifest.displayName ?? loaded.manifest.name
            let alert = NSAlert()
            alert.messageText = "Could not uninstall “\(name)”."
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            if let window = view.window {
                alert.beginSheetModal(for: window) { _ in }
            } else {
                alert.runModal()
            }
        }
    }

    // MARK: - Content, as pure functions

    /// "3 themes", "12 snippets", "1 view" — one line per non-empty
    /// `contributes.*` key.
    ///
    /// Derived by reflection rather than from a list of keys spelled here: a
    /// key added to `Contributions` in a later stage would otherwise be decoded,
    /// applied, and silently missing from the one summary that claims to say
    /// what an extension contributes.
    static func contributionSummaryLines(for contributions: ExtensionManifest.Contributions) -> [String] {
        Mirror(reflecting: contributions).children.compactMap { child in
            guard let label = child.label, label != "decodingFailures" else { return nil }
            let count: Int
            if let array = child.value as? [Any] {
                count = array.count
            } else if let keyed = child.value as? [String: [Any]] {
                count = keyed.values.reduce(0) { $0 + $1.count }
            } else {
                return nil
            }
            guard count > 0 else { return nil }
            return "\(count) \(noun(forKey: label, count: count))"
        }
    }

    /// `viewsContainers` → "views containers" / "views container". Crude
    /// singularisation on purpose: every key in `Contributions` is a plural
    /// noun ending in `s`, and the alternative is a second list of words to
    /// keep in step with the first.
    private static func noun(forKey key: String, count: Int) -> String {
        var words = ""
        for character in key {
            if character.isUppercase {
                words.append(" ")
                words.append(Character(character.lowercased()))
            } else {
                words.append(character)
            }
        }
        guard count == 1, words.hasSuffix("s") else { return words }
        return String(words.dropLast())
    }

    /// Everything the loading of *this* extension decided that its author did
    /// not spell out, gathered from every contribution point.
    ///
    /// Filtered here rather than by a pre-filtered accessor on each point: the
    /// points already key by identifier, and five accessors to save five
    /// `filter`s is surface nobody needs.
    func decisionLines() -> [String] {
        var lines: [String] = []

        for failure in coordinator.themePoint.importFailures
        where failure.extensionIdentifier == extensionIdentifier {
            lines.append("Theme file \(failure.path) could not be read: \(failure.message)")
        }

        for failure in coordinator.snippetStore.failures where failure.extensionIdentifier == extensionIdentifier {
            lines.append("Snippet file \(failure.path) could not be read: \(failure.reason)")
        }

        for dropped in coordinator.languagePoint.dropped where dropped.extensionIdentifier == extensionIdentifier {
            lines.append(Self.line(for: dropped))
        }

        for conflict in coordinator.languagePoint.conflicts
        where conflict.loser == extensionIdentifier || conflict.winner == extensionIdentifier {
            lines.append(Self.line(for: conflict, viewedFrom: extensionIdentifier))
        }

        for note in coordinator.configurationPoint.notes where note.extensionIdentifier == extensionIdentifier {
            // `detail` is already written for a person; `kind` is a
            // discriminator for code and is never rendered.
            lines.append("Setting \(note.key): \(note.detail)")
        }

        // View notes are deliberately *not* repeated here: they are rendered in
        // the Views group, under the view each one is about, which is the more
        // useful of the two places. Ruling FW asks for one line each.

        // A lenient decode that dropped one malformed entry is a decision this
        // app made on the author's behalf, and the manifest is the only source
        // of those. Its failures are excluded from the Contributes summary —
        // an entry that did not decode is not a contribution — so this is the
        // one route they have to a screen.
        for failure in loaded.manifest.contributes?.decodingFailures ?? [] {
            lines.append("\(Self.entry(for: failure)) could not be read: \(failure.reason)")
        }

        return lines
    }

    /// `contributes.themes[1]`, or `contributes.menus.editor/context` for a
    /// keyed container, whose failures carry no index.
    static func entry(for failure: DecodingFailure) -> String {
        guard let index = failure.index else { return failure.key }
        return "\(failure.key)[\(index)]"
    }

    /// One sentence covering both facts a dropped matcher can carry at once.
    ///
    /// `keys` and `declaredNoMatcher` are not alternatives: an entry declaring
    /// only `mimetypes` has both, because `mimetypes` is a key worth recording
    /// and not a matcher this app can act on. The sentence therefore states what
    /// was ignored first and what that leaves second, which reads correctly
    /// whether one of the two is true or both are.
    static func line(for dropped: DroppedLanguageMatcher) -> String {
        var sentence = "Language \(dropped.languageID): "
        // `keys` gains "extensions" when *individual declared values* were
        // unusable, which is a different fact from a key this app cannot match
        // by at all — and it is the clause below that says which values. Left
        // in, the sentence claims the app cannot match files by extension,
        // which is the one thing this point does, and then contradicts itself
        // two clauses later.
        let unsupported = dropped.keys.filter { $0 != "extensions" }
        if !unsupported.isEmpty {
            sentence += "this app cannot match files by \(list(unsupported)), so "
                + "\(unsupported.count == 1 ? "it was" : "they were") ignored"
        }
        if dropped.declaredNoMatcher {
            sentence += unsupported.isEmpty ? "" : ", and "
            sentence += "the entry declares no file extension, filename or pattern, "
                + "so it matches no file here or in VS Code"
        }
        if !dropped.skippedExtensions.isEmpty {
            sentence += unsupported.isEmpty && !dropped.declaredNoMatcher ? "" : ". "
            // Quoted: a skipped value is often the empty string, and unquoted
            // it renders as a hole in the sentence with no name in it.
            sentence += "The file \(dropped.skippedExtensions.count == 1 ? "extension" : "extensions") "
                + "\(list(dropped.skippedExtensions.map { "“\($0)”" })) could not be used"
        }
        return sentence + "."
    }

    /// The conflict, told from the panel it is shown on.
    ///
    /// Both sides are shown it, because a mapping that did not take effect is
    /// news to whoever is reading — but the loser's sentence on the winner's
    /// panel reads as somebody else's problem, so the winner is told what it
    /// won instead.
    static func line(for conflict: LanguageContributionConflict, viewedFrom identifier: String) -> String {
        guard conflict.winner != conflict.loser else {
            return "This extension claims \(conflict.fileExtension) more than once; "
                + "\(conflict.losingLanguageID) does not apply to it."
        }
        guard identifier == conflict.winner else {
            return "\(conflict.fileExtension) is mapped by \(conflict.winner); "
                + "\(conflict.loser)'s \(conflict.losingLanguageID) does not apply to it."
        }
        return "\(conflict.fileExtension) is mapped by this extension; "
            + "\(conflict.loser)'s \(conflict.losingLanguageID) does not apply to it."
    }

    private static func list(_ values: [String]) -> String {
        guard values.count > 1, let last = values.last else { return values.joined() }
        return values.dropLast().joined(separator: ", ") + " and " + last
    }
}

// MARK: - Nothing installed

/// What the panel shows when no extension loaded — which is every install
/// today. A blank detail pane reads as a defect; this reads as a place to put
/// something.
@MainActor
final class ExtensionsEmptyStatePanel: ComposableSettings.SettingsPanelViewController {

    private let searchPaths: [URL]

    init(searchPaths: [URL]) {
        self.searchPaths = searchPaths
        super.init(with: ComposableSettings.SettingsPanelDescriptor(
            title: "No Extensions Installed",
            icon: NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: nil)
        ))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let group = ComposableSettings.GroupView(withTitle: "Where Extensions Are Looked For")
        for path in searchPaths {
            group.addSettingSubview(ComposableSettings.ExplanationView(withText: path.path))
        }
        group.addSettingSubview(
            ComposableSettings.ExplanationView(
                withText: "Unpack a VS Code extension folder into either place and relaunch — "
                    + "extensions are read once at startup. Installing one from inside the app "
                    + "is not possible yet, and there is no marketplace to install from."),
            style: .continuation)
        addGroup(group)
    }
}

// MARK: - What went wrong

/// The trailing panel listing `ExtensionRegistry.failures`.
///
/// Split in two, because the two kinds are not the same news: a
/// `contributionPointFailed` names one refused contribution of an extension
/// that loaded fine and is still installed, and reporting it as a failed load
/// would tell a user their working extension is broken.
@MainActor
final class ExtensionLoadProblemsPanel: ComposableSettings.SettingsPanelViewController {

    private let refused: [ExtensionLoadFailure]
    private let didNotLoad: [ExtensionLoadFailure]
    private let scanIdentifiedEveryExtension: Bool

    init(failures: [ExtensionLoadFailure], scanIdentifiedEveryExtension: Bool) {
        self.refused = failures.filter { Self.isRefusedContribution($0) }
        self.didNotLoad = failures.filter { !Self.isRefusedContribution($0) }
        self.scanIdentifiedEveryExtension = scanIdentifiedEveryExtension
        super.init(with: ComposableSettings.SettingsPanelDescriptor(
            title: Self.summaryTitle(for: failures),
            icon: NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
        ))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var helpContent: ComposableSettings.PanelHelp? {
        ComposableSettings.PanelHelp(topics: [
            .init(
                title: "Refused Contributions",
                body: "The extension is installed and everything else it declares is in "
                    + "force; one contribution could not be applied. The reason names which "
                    + "part and why."
            ),
            .init(
                title: "Extensions That Did Not Load",
                body: "A folder in a search path that is not a usable extension: no "
                    + "package.json, one that will not parse, a VS Code version range this "
                    + "app does not satisfy, or a second copy of an identifier already "
                    + "loaded. Nothing it declares is in force."
            )
        ])
    }

    /// What a scan that could not name every directory costs the user,
    /// said where the *cause* is already listed above it.
    ///
    /// A skipped prune is otherwise invisible: the themes of an extension the
    /// user really did delete stay in the picker with nothing on screen to
    /// say why. Deriving the flag from the same
    /// `ExtensionRegistry.establishedIdentifiers` the prune reads keeps this
    /// sentence and that behaviour from drifting apart.
    static let incompleteScanNote =
        "Because an extension could not be read, themes from extensions that are no longer "
        + "installed have been left in place."

    static func isRefusedContribution(_ failure: ExtensionLoadFailure) -> Bool {
        if case .contributionPointFailed = failure.reason { return true }
        return false
    }

    /// Pure and static so the wording can be tested without a window.
    static func summaryTitle(for failures: [ExtensionLoadFailure]) -> String {
        let refused = failures.filter { isRefusedContribution($0) }.count
        if refused == failures.count {
            return "\(refused) contribution\(refused == 1 ? "" : "s") refused"
        }
        let failed = failures.count - refused
        if refused == 0 {
            return "\(failed) extension\(failed == 1 ? "" : "s") failed to load"
        }
        return "\(failures.count) extension problems"
    }

    /// The line for one refused contribution. Names the folder, the
    /// contribution, and the reason — and says the extension is installed,
    /// because it is.
    static func refusedLine(for failure: ExtensionLoadFailure) -> String {
        guard case .contributionPointFailed(let key, let message) = failure.reason else { return "" }
        return "\(failure.directory.lastPathComponent): installed, but its \(key) "
            + "contribution was refused — \(message)"
    }

    /// The line for one extension that did not load. `ExtensionLoadFailure`
    /// carries an identifier only when the manifest decoded, and the two
    /// reasons a user meets most here are the two where it did not — so the
    /// folder name is the one thing every row of this group can say.
    static func didNotLoadLine(for failure: ExtensionLoadFailure) -> String {
        "\(failure.directory.lastPathComponent): did not load — \(reason(for: failure.reason))"
    }

    private static func reason(for error: ExtensionLoadError) -> String {
        switch error {
        case .manifestMissing:
            return "the folder has no package.json."
        case .manifestUnreadable(let message):
            return "its package.json could not be read: \(message)"
        case .manifestMalformed(let message):
            return "its package.json could not be parsed: \(message)"
        case .engineRangeUnparsable(let range):
            return "its engines.vscode range “\(range)” could not be understood."
        case .engineIncompatible(let required, let host):
            return "it requires VS Code \(required); this app reports \(host)."
        case .duplicateIdentifier(let existing):
            // The only question a user staring at a duplicate install has is
            // which copy is live.
            return "another copy of the same extension is already loaded from \(existing)."
        case .contributionPointFailed(let key, let message):
            return "its \(key) contribution was refused — \(message)"
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if !refused.isEmpty {
            let group = ComposableSettings.GroupView(withTitle: "Installed, One Contribution Refused")
            for failure in refused {
                group.addSettingSubview(
                    ComposableSettings.ExplanationView(withText: Self.refusedLine(for: failure)))
            }
            addGroup(group)
        }

        if !didNotLoad.isEmpty {
            let group = ComposableSettings.GroupView(withTitle: "Did Not Load")
            for failure in didNotLoad {
                group.addSettingSubview(
                    ComposableSettings.ExplanationView(withText: Self.didNotLoadLine(for: failure)))
            }
            if !scanIdentifiedEveryExtension {
                group.addSettingSubview(
                    ComposableSettings.ExplanationView(withText: Self.incompleteScanNote))
            }
            addGroup(group)
        }
    }
}
