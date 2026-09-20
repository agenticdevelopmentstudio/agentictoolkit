//
//  ExtensionsBrowsePanel.swift
//  AgenticToolkit
//

import AppKit
import Foundation

import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// Browse Open VSX, read an extension's licence, install it, and update what is
/// already installed — without leaving the app.
///
/// One panel rather than three. Search, the thing found, and the updates for
/// things already found are the same errand from the reader's side, and a
/// sidebar with three registry-shaped entries beside a list of *their own*
/// extensions would put the shop in the same list as the shelf.
///
/// Every row here is built once in `viewDidLoad` and afterwards only has its
/// text changed. `GroupView` can add a subview and cannot remove one, so a
/// panel that rebuilt its cards per selection would grow a new copy of every
/// row on every click; the two places that genuinely vary in *number* (the
/// results table, the update list) own a container of their own and empty it
/// themselves.
@MainActor
final class ExtensionsBrowsePanel: ComposableSettings.SettingsPanelViewController {

    private let coordinator: ExtensionsCoordinator
    private let client: OpenVSXClient

    /// Rebuilds the sidebar after an install, because the installed list is the
    /// other half of this panel's effect and it is a sibling, not a child.
    private let onInstalled: () -> Void

    /// How an extension actually gets installed.
    ///
    /// Injected for the same reason `client` and `onInstalled` are: the real
    /// one downloads a multi-megabyte archive, checks a digest against the
    /// registry's metadata and expands it onto disk, and a test of *which row
    /// reports where* has no business doing any of that.
    private let installer: Installer

    typealias Installer = @MainActor (OpenVSXExtensionDetail) async throws -> VSIXInstallation

    // MARK: - Search

    private let searchField = AccessibleSearchField()
    private let resultsTable = ThemedTableView()
    private let resultsScroll = NSScrollView()
    private let resultsStatus = ComposableSettings.ExplanationView(
        withText: ExtensionsBrowsePanel.idleSearchPrompt)

    private var results: [OpenVSXSearchEntry] = []

    /// The in-flight search, kept so the next keystroke can cancel it. Without
    /// this a fast typist has six searches racing, and the answer on screen is
    /// whichever the network happened to finish last — not the one matching
    /// what is in the field.
    private var searchTask: Task<Void, Never>?

    // MARK: - The selected extension

    private let selectionGroup = ComposableSettings.GroupView(withTitle: "Selected Extension")
    private let selectionName = ComposableSettings.ExplanationView(withText: "")
    private let selectionDescription = ComposableSettings.ExplanationView(withText: "")
    private let selectionFacts = ComposableSettings.ExplanationView(withText: "")
    private let selectionLicense = ComposableSettings.ExplanationView(withText: "")
    private let selectionVerdict = ComposableSettings.ExplanationView(withText: "")

    /// What an install of the selected extension is doing or has done.
    ///
    /// Its own row rather than the verdict's, because the two answer different
    /// questions and the install changes what the *verdict* says: the moment
    /// "Installed 2.25.1, signature verified" is true, so is "version 2.25.1 is
    /// already installed", and a single row would have the report overwritten
    /// by its own consequence before anyone read it.
    private let selectionStatus = ComposableSettings.ExplanationView(withText: "")
    private var licenseButton: ComposableSettings.ButtonView?
    private var installButton: ComposableSettings.ButtonView?

    private var selection: OpenVSXExtensionDetail?
    private var detailTask: Task<Void, Never>?
    private var licenseTask: Task<Void, Never>?

    /// The installs in flight, one slot per extension.
    ///
    /// **Keyed, because this panel offers more than one install at a time.**
    /// The Selected card has an Install button and every Updates row has its
    /// own, and they all end up here. A single slot meant starting the second
    /// cancelled the first — and a cancelled install returns without touching
    /// anything, so the row it belonged to sat at "Downloading 1.2.3…" for the
    /// life of the panel. Keying by identifier makes a cancellation mean the
    /// one thing it should: this extension is being installed again, stop the
    /// previous attempt at it.
    ///
    /// A finished task is left in its slot rather than removed. Removing it
    /// from the task's own completion races the next click's replacement —
    /// the late `nil` would drop a *running* install out of the table — and
    /// the table is bounded by the number of extensions either way.
    private var installTasks: [String: Task<Void, Never>] = [:]

    // MARK: - Updates

    private let updatesStatus = ComposableSettings.ExplanationView(
        withText: "Not checked yet.")
    private let updatesList = NSStackView()
    private var updatesButton: ComposableSettings.ButtonView?
    private var updateTask: Task<Void, Never>?

    // MARK: - Lifecycle

    init(
        coordinator: ExtensionsCoordinator,
        client: OpenVSXClient = OpenVSXClient(),
        onInstalled: @escaping () -> Void,
        installer: Installer? = nil
    ) {
        self.coordinator = coordinator
        self.client = client
        self.onInstalled = onInstalled
        self.installer = installer ?? { detail in
            try await coordinator.installFromRegistry(detail, using: client)
        }
        super.init(with: ComposableSettings.SettingsPanelDescriptor(
            title: "Browse & Install",
            icon: NSImage(systemSymbolName: "square.and.arrow.down",
                          accessibilityDescription: nil)
        ))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        // Not a nicety. Every task here holds `self`, and an install task holds
        // a multi-megabyte download; a panel closed mid-search that kept them
        // running would report into a view tree nobody is looking at.
        searchTask?.cancel()
        detailTask?.cancel()
        licenseTask?.cancel()
        updateTask?.cancel()
        for task in installTasks.values {
            task.cancel()
        }
    }

    override var helpContent: ComposableSettings.PanelHelp? {
        ComposableSettings.PanelHelp(topics: [
            .init(
                title: "Where These Come From",
                body: "Open VSX, the open registry VS Code-compatible editors use. "
                    + "The Visual Studio Marketplace is not searched: its terms permit "
                    + "its extensions to be downloaded only by Microsoft's own products."
            ),
            .init(
                title: "What Gets Checked Before Install",
                body: "The download is checked against the digest the registry published "
                    + "for it, and — where the publisher signed it — against their "
                    + "signature. The extension's own package.json is then read back off "
                    + "disk and has to name the extension the registry said it was, and "
                    + "to accept this app's version. Anything that fails is not installed."
            ),
            .init(
                title: "Licences",
                body: "An extension is someone else's work under their own terms. The "
                    + "licence is shown before the Install button, and the full text can "
                    + "be read where the publisher supplied one. An extension with no "
                    + "declared licence is not a permissive one — it is one whose author "
                    + "has not said what you may do with it."
            ),
            .init(
                title: "Updates",
                body: "An update is only offered when installing it would actually "
                    + "succeed here. A newer version that raises its required editor "
                    + "version past this app's, or that ships only for another platform, "
                    + "is not shown — there would be nothing to do but refuse it."
            )
        ])
    }

    override var searchKeywords: [String] {
        [
            "install", "browse", "search", "marketplace", "registry",
            "open vsx", "openvsx", "vsix", "update", "updates", "license", "licence"
        ]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addGroup(makeSearchGroup())
        addGroup(makeResultsGroup())
        addGroup(makeSelectionGroup())
        addGroup(makeUpdatesGroup())
        showSelection(nil)
        // The empty query is the browse case: the registry answers it with the
        // most-downloaded extensions, which is a far better opening screen than
        // a blank list telling the reader to think of a name.
        scheduleSearch(debounced: false)
    }

    // MARK: - Groups

    private func makeSearchGroup() -> ComposableSettings.GroupView {
        let group = ComposableSettings.GroupView(withTitle: "Search Open VSX")
        searchField.placeholderString = "Search extensions"
        searchField.accessibilityID("extensions.browse.search")
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchSubmitted)
        // Each keystroke is a network request, so the field must not send one:
        // `controlTextDidChange` below debounces instead, and Return still
        // searches immediately through the action above.
        searchField.sendsWholeSearchString = true
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(searchField)
        NSView.pinToEdges(searchField, of: row)
        group.addSettingSubview(row)
        group.addSettingSubview(
            ComposableSettings.ExplanationView(
                withText: "Extensions come from Open VSX. The Visual Studio Marketplace is "
                    + "not searched — its terms allow only Microsoft's own products to "
                    + "download from it."),
            style: .continuation)
        return group
    }

    private func makeResultsGroup() -> ComposableSettings.GroupView {
        let group = ComposableSettings.GroupView(withTitle: "Results")

        resultsTable.headerView = nil
        resultsTable.rowHeight = 38
        resultsTable.allowsEmptySelection = true
        resultsTable.allowsMultipleSelection = false
        resultsTable.selectionHighlightStyle = .regular
        resultsTable.dataSource = self
        resultsTable.delegate = self
        resultsTable.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        let column = NSTableColumn(identifier: Self.resultColumnID)
        column.resizingMask = .autoresizingMask
        resultsTable.addTableColumn(column)

        resultsScroll.documentView = resultsTable
        resultsScroll.hasVerticalScroller = true
        resultsScroll.autohidesScrollers = true
        resultsScroll.borderType = .noBorder
        resultsScroll.drawsBackground = false
        resultsScroll.translatesAutoresizingMaskIntoConstraints = false
        // A settings card has no height of its own to lend a scroll view, and
        // the panel scrolls as a whole — so the list states its own height
        // rather than growing without limit as results arrive.
        resultsScroll.heightAnchor.constraint(equalToConstant: 220).isActive = true
        resultsTable.accessibilityID("extensions.browse.results")
        resultsStatus.label.accessibilityID("extensions.browse.results.status")

        group.addSettingSubview(resultsScroll)
        group.addSettingSubview(resultsStatus, style: .continuation)
        return group
    }

    private func makeSelectionGroup() -> ComposableSettings.GroupView {
        let group = selectionGroup
        group.addSettingSubview(selectionName)
        group.addSettingSubview(selectionDescription, style: .continuation)
        group.addSettingSubview(selectionFacts, style: .continuation)
        // The licence sits above the buttons, not below them, because the point
        // of showing it is that it is read before the install is pressed.
        group.addSettingSubview(selectionLicense, style: .continuation)
        group.addSettingSubview(selectionVerdict, style: .continuation)

        selectionName.label.accessibilityID("extensions.browse.selected.name")
        selectionDescription.label.accessibilityID("extensions.browse.selected.description")
        selectionFacts.label.accessibilityID("extensions.browse.selected.facts")
        selectionLicense.label.accessibilityID("extensions.browse.selected.license")
        selectionVerdict.label.accessibilityID("extensions.browse.selected.verdict")

        let license = ComposableSettings.ButtonView(
            viewModel: ComposableSettings.ButtonViewModel(
                title: "Read Licence…",
                wasPressedCallback: { [weak self] in self?.readLicense() }
            ),
            placement: .leading)
        licenseButton = license
        license.button.accessibilityID("extensions.browse.read-license")
        group.addSettingSubview(license, style: .continuation)

        let install = ComposableSettings.ButtonView(
            viewModel: ComposableSettings.ButtonViewModel(
                title: "Install",
                wasPressedCallback: { [weak self] in self?.installSelection() }
            ),
            placement: .leading)
        installButton = install
        install.button.accessibilityID("extensions.browse.install")
        group.addSettingSubview(install, style: .continuation)

        selectionStatus.label.accessibilityID("extensions.browse.selected.status")
        group.addSettingSubview(selectionStatus, style: .continuation)
        return group
    }

    private func makeUpdatesGroup() -> ComposableSettings.GroupView {
        let group = ComposableSettings.GroupView(withTitle: "Updates")
        let button = ComposableSettings.ButtonView(
            viewModel: ComposableSettings.ButtonViewModel(
                title: "Check for Updates",
                explanation: "Asks the registry whether anything installed has a newer "
                    + "version this app could run.",
                wasPressedCallback: { [weak self] in self?.checkForUpdates() }
            ),
            placement: .leading)
        updatesButton = button
        button.button.accessibilityID("extensions.browse.check-updates")
        updatesStatus.label.accessibilityID("extensions.browse.updates.status")
        group.addSettingSubview(button)
        group.addSettingSubview(updatesStatus, style: .continuation)

        updatesList.orientation = .vertical
        updatesList.alignment = .leading
        updatesList.spacing = 6
        updatesList.translatesAutoresizingMaskIntoConstraints = false
        let holder = NSView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(updatesList)
        NSView.pinToEdges(updatesList, of: holder)
        group.addSettingSubview(holder, style: .continuation)
        return group
    }

    // MARK: - Searching

    @objc private func searchSubmitted() {
        scheduleSearch(debounced: false)
    }

    /// Runs the search in the field, replacing any search already running.
    ///
    /// `debounced` is the difference between typing and pressing Return. A
    /// keystroke waits, because the next one is probably 80ms away and the
    /// registry should not be asked about every prefix of a word; Return is a
    /// statement that the word is finished.
    private func scheduleSearch(debounced: Bool) {
        let query = searchField.stringValue
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            if debounced {
                try? await Task.sleep(for: .milliseconds(350))
                if Task.isCancelled { return }
            }
            await self?.runSearch(query)
        }
    }

    private func runSearch(_ query: String) async {
        resultsStatus.label.stringValue = query.isEmpty
            ? "Loading the most-downloaded extensions…"
            : "Searching for “\(query)”…"
        do {
            let page = try await client.search(query, size: 50)
            if Task.isCancelled { return }
            results = page.extensions
            resultsTable.reloadData()
            resultsTable.deselectAll(nil)
            showSelection(nil)
            resultsStatus.label.stringValue = Self.resultsSummary(for: page, query: query)
        } catch {
            if Task.isCancelled { return }
            results = []
            resultsTable.reloadData()
            showSelection(nil)
            resultsStatus.label.stringValue = "Could not reach the registry: "
                + Self.sentence(for: error)
        }
    }

    /// What the results line says once a page has arrived.
    ///
    /// The total matters as much as the count shown: "50 of 2,322" is the only
    /// thing that tells a reader who did not find what they wanted that there
    /// is more behind a narrower query, rather than that the registry has
    /// nothing else.
    static func resultsSummary(for page: OpenVSXSearchPage, query: String) -> String {
        guard !page.extensions.isEmpty else {
            return query.isEmpty
                ? "The registry returned nothing."
                : "Nothing matched “\(query)”."
        }
        let shown = number(page.extensions.count)
        let total = number(page.totalSize)
        if page.extensions.count >= page.totalSize {
            return "\(shown) \(page.extensions.count == 1 ? "extension" : "extensions")."
        }
        return "Showing \(shown) of \(total). Narrow the search to see the rest."
    }

    // MARK: - Selection

    /// Loads the full record for `entry`, which is where the licence, the
    /// engine range and the download actually live — a search row carries none
    /// of them.
    private func loadDetail(for entry: OpenVSXSearchEntry) {
        detailTask?.cancel()
        selection = nil
        selectionGroup.isHidden = false
        selectionName.label.stringValue = entry.displayName ?? entry.name
        selectionDescription.label.stringValue = entry.description ?? ""
        selectionFacts.label.stringValue = "Loading…"
        selectionLicense.label.stringValue = ""
        selectionVerdict.label.stringValue = ""
        selectionStatus.label.stringValue = ""
        licenseButton?.isHidden = true
        installButton?.button.isEnabled = false

        detailTask = Task { [weak self] in
            guard let self else { return }
            do {
                let detail = try await self.client.detail(
                    namespace: entry.namespace, name: entry.name)
                if Task.isCancelled { return }
                self.showSelection(detail)
            } catch {
                if Task.isCancelled { return }
                self.selectionFacts.label.stringValue =
                    "Could not read this extension's record: " + Self.sentence(for: error)
            }
        }
    }

    /// Puts one extension in the Selected card, or hides the card.
    ///
    /// Not `private`: the test target drives this rather than a search result,
    /// because reaching the same state through the results table would mean
    /// answering a registry search.
    func showSelection(_ detail: OpenVSXExtensionDetail?) {
        selection = detail
        guard let detail else {
            selectionGroup.isHidden = true
            return
        }
        selectionGroup.isHidden = false
        selectionName.label.stringValue = detail.displayName ?? detail.name
        selectionDescription.label.stringValue = detail.description ?? ""
        selectionFacts.label.stringValue = Self.factsLine(for: detail)
        selectionLicense.label.stringValue = Self.licenseLine(for: detail)
        licenseButton?.isHidden = detail.licenseTextURL == nil

        let installability = detail.installability(
            forHostVersion: ExtensionRegistry.declaredVSCodeVersion)
        let installed = coordinator.registry.extensions
            .first { $0.identifier == detail.identifier }
        selectionVerdict.label.stringValue = Self.verdictLine(
            for: installability,
            installedVersion: installed?.manifest.version,
            publishedVersion: detail.version,
            canInstallAnywhere: coordinator.installDirectory != nil)
        installButton?.button.isEnabled =
            installability.isInstallable && coordinator.installDirectory != nil
        installButton?.button.title = installed == nil ? "Install" : "Reinstall"
    }

    static func factsLine(for detail: OpenVSXExtensionDetail) -> String {
        var parts = ["Version \(detail.version)"]
        parts.append("published by \(detail.namespace)")
        if let downloads = detail.downloadCount {
            parts.append("\(number(downloads)) downloads")
        }
        if let engine = detail.engines?["vscode"], !engine.isEmpty {
            parts.append("needs VS Code \(engine)")
        }
        return parts.joined(separator: " · ")
    }

    /// The licence line, which is deliberately not silent when there is none.
    ///
    /// An extension with no declared licence is the case a reader most needs
    /// told: no declaration is not a permissive default, it is an author who
    /// has not said what may be done with their work. Leaving the row blank
    /// there would make "unlicensed" look like "unremarkable".
    static func licenseLine(for detail: OpenVSXExtensionDetail) -> String {
        guard let license = detail.license, !license.isEmpty else {
            return "No licence declared — the publisher has not said how this may be used."
        }
        return "Licence: \(license)"
    }

    static func verdictLine(
        for installability: OpenVSXInstallability,
        installedVersion: String?,
        publishedVersion: String,
        canInstallAnywhere: Bool
    ) -> String {
        switch installability {
        case .installable:
            guard canInstallAnywhere else {
                return "This app has nowhere to install extensions to."
            }
            guard let installedVersion else { return "" }
            if installedVersion == publishedVersion {
                return "Version \(installedVersion) is already installed."
            }
            return "Version \(installedVersion) is installed; \(publishedVersion) is published."
        case .engineIncompatible(let range):
            return "Needs VS Code \(range.description), which this app does not claim "
                + "(it implements \(ExtensionRegistry.declaredVSCodeVersion.description))."
        case .engineRangeUnreadable(let declared):
            return "Declares an editor version this app cannot read: “\(declared)”."
        case .platformSpecific(let platform):
            return "Published only for \(platform), not as a universal build."
        case .noUniversalBuild:
            return "The registry publishes no downloadable build of this version."
        }
    }

    private func readLicense() {
        guard let detail = selection, let url = detail.licenseTextURL else { return }
        licenseTask?.cancel()
        licenseButton?.button.isEnabled = false
        licenseTask = Task { [weak self] in
            guard let self else { return }
            defer { self.licenseButton?.button.isEnabled = true }
            do {
                let text = try await self.client.text(at: url)
                if Task.isCancelled { return }
                self.presentLicense(text, for: detail)
            } catch {
                if Task.isCancelled { return }
                self.selectionLicense.label.stringValue =
                    Self.licenseLine(for: detail) + " — the text could not be fetched."
            }
        }
    }

    /// Shows the licence text in an alert's accessory view.
    ///
    /// A scrolling text view inside an alert rather than a window of its own:
    /// this is reference material read once, immediately before a decision, and
    /// a second window would outlive the decision and have to be managed.
    private func presentLicense(_ text: String, for detail: OpenVSXExtensionDetail) {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 460, height: 300))
        textView.isEditable = false
        textView.drawsBackground = false
        textView.string = text
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 460, height: 300))
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let alert = NSAlert()
        alert.messageText = "\(detail.displayName ?? detail.name) — \(detail.license ?? "licence")"
        alert.informativeText = "The licence text as the publisher supplied it."
        alert.accessoryView = scroll
        alert.addButton(withTitle: "Done")
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    // MARK: - Installing

    private func installSelection() {
        guard let detail = selection else { return }
        install(detail, progressInto: selectionStatus, disabling: installButton?.button)
    }

    /// Installs `detail`, reporting into the status row that asked for it and
    /// disabling the button that was pressed while it runs.
    ///
    /// **Every part of this is per-caller, and that is the point.** An install
    /// is started from the Selected card or from any Updates row, and each of
    /// those has its own status line and its own button. Reporting into a
    /// status the caller hands over, and re-enabling the button the caller
    /// hands over, is what keeps a click on one row from writing into another
    /// one's — the previous version disabled the *card's* Install button
    /// whichever row was pressed, and left it that way on success.
    private func install(
        _ detail: OpenVSXExtensionDetail,
        progressInto status: ComposableSettings.ExplanationView,
        disabling button: NSButton?
    ) {
        installTasks[detail.identifier]?.cancel()
        button?.isEnabled = false
        status.label.stringValue = "Downloading \(detail.version)…"
        installTasks[detail.identifier] = Task { [weak self] in
            guard let self else { return }
            do {
                let installation = try await self.installer(detail)
                if Task.isCancelled { return }
                status.label.stringValue = Self.installedLine(for: installation)
                button?.isEnabled = true
                // The installed list is a sibling panel built from the registry,
                // and the registry has just changed underneath it.
                self.onInstalled()
                // Only when the card is showing what was installed. An update
                // row installs something the reader may never have selected,
                // and redrawing the card from it replaced whatever they were
                // reading with an extension they had not asked to see.
                if self.selection?.identifier == detail.identifier {
                    self.showSelection(detail)
                }
            } catch {
                if Task.isCancelled { return }
                status.label.stringValue = "Not installed: " + Self.sentence(for: error)
                button?.isEnabled = true
            }
        }
    }

    /// What an install reports when it worked.
    ///
    /// **Every clause here says "the registry published", and that is the
    /// point.** The digest and the signing key both arrive from the registry's
    /// own metadata response, so nothing an install can check establishes who
    /// published the extension — and this line used to say "the publisher's
    /// signature over the download was verified", which is the one reading it
    /// cannot support. It also claimed a digest match unconditionally, in the
    /// branch where no digest had been published at all.
    ///
    /// Stated either way rather than only when something was checked: silence
    /// about an unverified download reads as a verification that happened.
    static func installedLine(for installation: VSIXInstallation) -> String {
        var line = "Installed \(installation.version)."
        switch (installation.verification.digest, installation.verification.signature) {
        case (.matched, .registryAttested):
            line += " It matched both the digest and the signature the registry "
                + "published for it."
        case (.matched, .notPublished):
            line += " It matched the digest the registry published for it, which "
                + "published no signature."
        case (.notPublished, .registryAttested):
            line += " It matched the signature the registry published for it, which "
                + "published no digest."
        case (.notPublished, .notPublished):
            line += " The registry published nothing to check the download against."
        }
        if !installation.supersededDirectories.isEmpty {
            let count = installation.supersededDirectories.count
            line += " \(count) older \(count == 1 ? "copy was" : "copies were") removed."
        }
        if !installation.runnableHere {
            line += " Its code will not run here — it is built for the Node extension "
                + "host, which this app does not have. Anything it contributes without "
                + "running code (themes, snippets, file types) still works."
        }
        return line
    }

    // MARK: - Updates

    private func checkForUpdates() {
        updateTask?.cancel()
        updatesButton?.button.isEnabled = false
        updatesStatus.label.stringValue = "Checking…"
        clearUpdateRows()
        let installed = coordinator.registry.extensions
        updateTask = Task { [weak self] in
            guard let self else { return }
            let check = ExtensionUpdateCheck(client: self.client)
            let report = await check.check(installed)
            if Task.isCancelled { return }
            self.updatesButton?.button.isEnabled = true
            self.showUpdates(report)
        }
    }

    /// Puts a finished check on screen: the summary, then a row per update.
    ///
    /// Separate from `checkForUpdates()` so the rows can be built from a report
    /// without a registry to get one from — which is how the rows are tested.
    func showUpdates(_ report: ExtensionUpdateReport) {
        clearUpdateRows()
        updatesStatus.label.stringValue = Self.updatesSummary(for: report)
        for update in report.updates {
            updatesList.addArrangedSubview(makeUpdateRow(update))
        }
    }

    static func updatesSummary(for report: ExtensionUpdateReport) -> String {
        var sentences: [String] = []
        if report.updates.isEmpty {
            sentences.append("Everything installed is up to date.")
        } else {
            let count = report.updates.count
            sentences.append(
                "\(count) \(count == 1 ? "extension has" : "extensions have") an update.")
        }
        if !report.notCheckable.isEmpty {
            // Named, not counted: the usual cause is an extension installed by
            // hand that the registry has never heard of, and the reader can
            // only recognise that from the name.
            let count = report.notCheckable.count
            sentences.append(
                "\(count) could not be checked (\(report.notCheckable.joined(separator: ", "))) "
                    + "— the registry has no record of them.")
        }
        return sentences.joined(separator: " ")
    }

    private func makeUpdateRow(_ update: ExtensionUpdate) -> NSView {
        let label = ComposableSettings.makeRowLabel(
            "\(update.identifier)  \(update.installedVersion) → \(update.latestVersion)")
        let status = ComposableSettings.ExplanationView(withText: "")
        let button = NSButton(title: "Update", target: nil, action: nil)
        button.bezelStyle = .rounded
        // Named after the extension, not by position: these rows are one per
        // update and reorder as extensions come and go, so "the second Update
        // button" is not a thing anyone — a scripting client, voice control, a
        // driven check — can hold onto between two checks.
        button.accessibilityID("extensions.browse.update.\(update.identifier)")
        status.label.accessibilityID("extensions.browse.update.\(update.identifier).status")
        let action = UpdateRowAction { [weak self, weak button] in
            self?.install(update.latest, progressInto: status, disabling: button)
        }
        button.target = action
        button.action = #selector(UpdateRowAction.fire)
        // A button's target is unowned; without somewhere to live, the action
        // object is gone before the click and the button quietly does nothing.
        updateRowActions.append(action)

        let row = NSStackView(views: [NSView.makeRow([label, button]), status])
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 2
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func clearUpdateRows() {
        for view in updatesList.arrangedSubviews {
            updatesList.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        updateRowActions.removeAll()
    }

    private var updateRowActions: [UpdateRowAction] = []

    /// A target for one update row's button. `NSButton` holds its target
    /// weakly and there is no view-model vocabulary for a button inside an
    /// arbitrary row, so the closure needs an owner that outlives the click.
    private final class UpdateRowAction: NSObject {
        private let body: () -> Void
        init(_ body: @escaping () -> Void) { self.body = body }
        @objc func fire() { body() }
    }

    // MARK: - Shared text

    static let idleSearchPrompt = "Type to search the registry."

    /// One readable sentence for anything thrown between here and the registry.
    ///
    /// Every error in this path is already a named case carrying what it needs;
    /// what none of them has is a sentence. `String(describing:)` on an enum
    /// with associated values reads like a stack trace in a settings panel.
    static func sentence(for error: Error) -> String {
        switch error {
        case let error as OpenVSXError:
            switch error {
            case .malformedRegistryURL(let url):
                return "the registry address (\(url.absoluteString)) is not usable."
            case .requestFailed(_, let status):
                return status == 404
                    ? "the registry has no such extension."
                    : "the registry answered \(status)."
            case .undecodableResponse:
                return "the registry's answer was not in the expected form."
            case .artifactNotText:
                return "a file the registry served was not readable text."
            case .artifactNotFetchable(_, let scheme):
                return scheme.isEmpty
                    ? "the registry pointed at an address with no scheme, which this "
                        + "app will not fetch."
                    : "the registry pointed at a \(scheme): address, which this app "
                        + "will not fetch."
            case .responseNotHTTP:
                return "the registry's answer was not an HTTP response."
            }
        case let error as VSIXInstallError:
            return sentence(forInstall: error)
        case let error as VSIXVerificationError:
            switch error {
            case .digestMismatch:
                return "the download did not match the digest the registry published "
                    + "for it."
            case .signatureInvalid:
                return "the signature the registry published does not cover these bytes."
            case .signatureIncomplete(let missing):
                return "the registry published only half of the signature for it — "
                    + "no \(missing)."
            case .signatureArchiveUnreadable, .publicKeyUnreadable:
                return "the signature the registry published could not be read."
            }
        case let error as VSIXArchiveError:
            switch error {
            case .destinationExists(let url):
                return "\(url.lastPathComponent) is already there."
            case .expansionUnavailable, .expansionFailed:
                return "the archive could not be expanded."
            }
        case is ExtensionInstallUnavailable:
            return "this app has nowhere to install extensions to."
        default:
            return "\(error.localizedDescription)"
        }
    }

    private static func sentence(forInstall error: VSIXInstallError) -> String {
        switch error {
        case .registryVersionUnusable:
            return "this version cannot run here."
        case .noPayloadDirectory:
            return "the archive holds no extension."
        case .manifestUnreadable, .manifestMalformed:
            return "the extension's package.json could not be read."
        case .identityMismatch(let claimed, let found):
            return "the registry called it \(claimed) and the archive contains \(found)."
        case .engineIncompatible(let declared, let host):
            return "it needs VS Code \(declared) and this app implements \(host)."
        case .engineRangeUnreadable(let declared):
            return "its required editor version, “\(declared)”, could not be read."
        case .verificationIncomplete(let published, let missing):
            // Named rather than softened, for the same reason `unsafeIdentity`
            // is below: a registry that publishes a signature and no key has
            // either broken or removed a check, and which half is missing is
            // exactly what a report against it needs.
            return "the registry published a \(published) for it but no \(missing), "
                + "so the download could not be checked."
        case .unsafeIdentity(let field, let value):
            // Named rather than softened: an archive whose own manifest asks
            // to be written outside the extensions folder is not a mistake to
            // apologise for, and the value is what someone reporting it needs.
            return "its \(field), “\(value)”, is not a name this app will install under."
        case .couldNotInstall(let reason):
            return reason
        }
    }

    private static let counter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    static func number(_ value: Int) -> String {
        counter.string(from: NSNumber(value: value)) ?? String(value)
    }

    fileprivate static let resultColumnID = NSUserInterfaceItemIdentifier("openvsx.result")
}

// MARK: - The results list

extension ExtensionsBrowsePanel: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(
        _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
    ) -> NSView? {
        guard results.indices.contains(row) else { return nil }
        let entry = results[row]
        let identifier = NSUserInterfaceItemIdentifier("openvsx.result.cell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil)
            as? ResultCellView ?? ResultCellView(identifier: identifier)
        // On the label rather than the cell or the row: AppKit synthesizes a
        // table's `AXRow` and `AXCell` itself, and an identifier set on
        // `NSTableCellView` never reaches them. Set per configure, not at
        // creation, because cells are pooled — one baked in would name
        // whichever extension the cell first showed, forever.
        cell.title.accessibilityID("extensions.browse.result.\(entry.identifier)")
        cell.title.stringValue = entry.displayName ?? entry.name
        var subtitle = "\(entry.namespace).\(entry.name) · \(entry.version)"
        if let downloads = entry.downloadCount {
            subtitle += " · \(ExtensionsBrowsePanel.number(downloads)) downloads"
        }
        if entry.deprecated == true {
            subtitle += " · deprecated"
        }
        cell.subtitle.stringValue = subtitle
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ThemedTableRowView(frame: .zero)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = resultsTable.selectedRow
        guard results.indices.contains(row) else {
            showSelection(nil)
            return
        }
        loadDetail(for: results[row])
    }
}

extension ExtensionsBrowsePanel: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        scheduleSearch(debounced: true)
    }
}

/// One search result: what it is called, and what it is.
///
/// Two lines rather than one. The display name alone is ambiguous across
/// publishers — there are several "Ruby" extensions — and the identifier alone
/// is not what anybody is looking for.
@MainActor
private final class ResultCellView: NSTableCellView {

    let title = ResultTitleLabel()
    let subtitle = ThemedLabel(role: .secondaryText, textRole: .caption)

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        for label in [title, subtitle] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
        }
        textField = title
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

/// The result title, which is also the row's only real accessibility element —
/// so it is what selects the row.
///
/// The same arrangement `TopicListItemLabel` uses in the settings sidebar, for
/// the same reason: AppKit's synthesized `AXRow`/`AXCell` carry no identifier
/// and answer no press, so without this a list is visible to an assistive
/// client and unusable by one.
///
/// Its own class rather than a `ThemedLabel` subclass because `ThemedLabel` is
/// `final` — and it is final in a framework this one only consumes, so the way
/// to add a press here is to repeat eight lines of theming, not to open up
/// somebody else's published type.
@MainActor
final class ResultTitleLabel: NSTextField, Themeable {

    private var observer: ThemePaletteObserver?

    init() {
        super.init(frame: .zero)
        isEditable = false
        isBordered = false
        isBezeled = false
        drawsBackground = false
        cell?.wraps = false
        cell?.usesSingleLineMode = true
        lineBreakMode = .byTruncatingTail
        observer = ThemePaletteObserver(host: self) { [weak self] palette in
            self?.applyTheme(palette)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func applyTheme(_ palette: SemanticPalette) {
        textColor = palette.nsColor(.primaryText)
        font = palette.font(.body)
    }

    override func accessibilityPerformPress() -> Bool {
        var ancestor: NSView? = superview
        while let view = ancestor, !(view is NSTableView) { ancestor = view.superview }
        guard let table = ancestor as? NSTableView else { return false }
        let row = table.row(for: self)
        guard row >= 0 else { return false }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        return true
    }

    /// AppKit publishes the actions it infers from what a class implements, and
    /// this is the only selector this type adds. Saying so keeps the answer off
    /// that inference.
    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        if selector == #selector(accessibilityPerformPress) { return true }
        return super.isAccessibilitySelectorAllowed(selector)
    }
}

/// A search field that actually searches when its value is set through
/// accessibility.
///
/// `NSSearchField` sends its action on Return and its delegate a notification
/// on each keystroke — both of which are *editing* events, and neither of which
/// an assistive client setting `AXValue` produces. So voice control, a
/// scripting client, or anything else that fills the field the supported way
/// put text on screen and left the results below it showing someone else's
/// query. Running the action after the value lands makes the two routes agree.
@MainActor
final class AccessibleSearchField: NSSearchField {

    override func setAccessibilityValue(_ accessibilityValue: Any?) {
        super.setAccessibilityValue(accessibilityValue)
        if let text = accessibilityValue as? String { stringValue = text }
        sendAction(action, to: target)
    }

    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        if selector == #selector(NSSearchField.setAccessibilityValue(_:)) { return true }
        return super.isAccessibilitySelectorAllowed(selector)
    }
}
