import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// One project's pane in the Projects window. It has three cards: what the
/// project is, how its time is billed, and which repositories count as its
/// work — then its billables, their totals and history below them.
///
/// The record, the sidebar title and `onSave` are `RecordDetailPanel`'s. Like
/// `ClientDetailPanel`, it never talks to the daemon: `ProjectsWindowController`
/// does. The billing settings it reads (the fallback rate and currency) are
/// injected, so any app can host it with its own settings keys.
@MainActor
public final class ProjectDetailPanel: ComposableSettings.RecordDetailPanel<BillingProjectDTO> {

    public static let addClientTitle = "Add Client…"

    /// The project as last stored or shown.
    public var project: BillingProjectDTO { record }
    public private(set) var clients: [BillingClientDTO] = []
    public private(set) var repos: [BillingRepoDTO] = []

    public var onAddClient: (() -> Void)?
    public var onAddRepo: (() -> Void)?
    public var onSaveRepo: ((BillingRepoDTO) -> Void)?
    public var onRemoveRepo: ((BillingRepoDTO) -> Void)?

    public private(set) var nameField: ComposableSettings.TextEditView!
    public private(set) var clientPopup: ComposableSettings.PopupMenuChoiceView<String>!
    public private(set) var notesField: ComposableSettings.TextAreaEditView!
    public private(set) var billingToggle: ComposableSettings.CheckboxView!
    public private(set) var rateField: ComposableSettings.MoneyFieldView!
    public private(set) var roundingField: ComposableSettings.IntegerFieldView!
    public private(set) var roundingModePopup: ComposableSettings.PopupMenuChoiceView<String>!
    public private(set) var archivedToggle: ComposableSettings.CheckboxView!
    public private(set) var reposCard: ComposableSettings.EditableTableCard!

    /// Billables, totals and history.
    public let billables = ProjectBillablesSection()

    private let settings: BillingUserSettings
    private var nameModel: ComposableSettings.ViewModel<String>!
    private var clientChoice: ComposableSettings.ChoiceViewModel<String>!
    private var notesModel: ComposableSettings.ViewModel<String>!
    private var billingModel: ComposableSettings.ViewModel<Bool>!
    private var roundingModel: ComposableSettings.RangeViewModel<Int>!
    private var roundingModeModel: ComposableSettings.ChoiceViewModel<String>!
    private var archivedModel: ComposableSettings.ViewModel<Bool>!
    /// The blank-rate hint shows the Settings default, which can change while
    /// the pane is open and nothing in the billing lists changes with it.
    private var settingObservers: [AnyObject] = []

    /// - Parameter settings: where the fallback rate and currency are read.
    public init(project: BillingProjectDTO, settings: BillingUserSettings) {
        self.settings = settings
        super.init(record: project, icon: NSImage(systemSymbolName: "briefcase", accessibilityDescription: nil))
    }

    public override var nameTextField: NSTextField? { nameField?.textField }

    public override var searchKeywords: [String] {
        var words = [project.name, "project", "rate", "rounding", "repository",
                     "billable", "unbilled", "billed", "paid", "hours"]
        if let client = clients.first(where: { $0.id == project.clientId }) { words.append(client.name) }
        words += repos.map { ($0.projectRoot as NSString).lastPathComponent }
        return words.filter { !$0.isEmpty }
    }

    public override var helpContent: ComposableSettings.PanelHelp? {
        ComposableSettings.PanelHelp(topics: [
            .init(
                title: "Projects",
                body: "A project is what time is billed to. Time spent in its repositories is "
                    + "tracked automatically; timers can also be started by hand."
            ),
            .init(
                title: "Rates",
                body: "A repository's own rate wins, then the project's default rate, then the "
                    + "default rate in Billing settings. Leave a rate blank to use the next one."
            ),
            .init(
                title: "Rounding",
                body: "Each billable's time is rounded to this many minutes when it is written. "
                    + "Changing it later never rewrites a billable that is already billed."
            ),
            .init(
                title: "Repositories",
                body: "Choose any folder in a repository and the whole repository is added, "
                    + "including its worktrees. Give it a branch to bill only that branch, "
                    + "for example when one repository serves two clients."
            ),
            .init(
                title: "Billables",
                body: "Tracked time becomes one unbilled billable per day on its own. Add one "
                    + "with + for time spent away from the computer. Hours typed by hand are "
                    + "used as typed; the amount is always hours times rate."
            ),
            .init(
                title: "Billed and Paid",
                body: "Mark a billable Billed once it is on an invoice, and Paid when the money "
                    + "arrives. Billed and paid billables can't be changed, so a figure a client "
                    + "has seen never moves. Mark one Unbilled to correct it."
            ),
            .init(
                title: "Late Time",
                body: "Time tracked on a day that is already billed goes on a new, highlighted "
                    + "billable instead of changing the billed one."
            ),
            .init(
                title: "Archiving and Deleting",
                body: "Archiving keeps a project and its history but takes it out of every "
                    + "chooser. A project with billables can only be archived, so that no "
                    + "billed hours disappear."
            )
        ])
    }

    /// Rates are typed and shown in the client's currency, or the Settings
    /// currency for a project with no client.
    private var currency: String {
        clients.first { $0.id == project.clientId }?.currency ?? settings.currency.value
    }

    private var formatter: MoneyFormatter { MoneyFormatter(currency: currency) }

    public override func viewDidLoad() {
        super.viewDidLoad()
        addGroup(makeProjectCard())
        addGroup(makeBillingCard())
        reposCard = makeReposCard()
        addGroup(reposCard)
        showRepos(repos)
        billables.cards.forEach { addGroup($0) }
        // A currency change re-renders the rate in the new format, too.
        let refreshRate: (Any) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshRate() }
        }
        settingObservers = [
            UserSettingObserver(settings.defaultRateCents) { refreshRate($0) },
            UserSettingObserver(settings.currency) { refreshRate($0) }
        ]
    }

    // MARK: - Cards

    private func makeProjectCard() -> ComposableSettings.GroupView {
        let card = ComposableSettings.GroupView(withTitle: "Project")

        nameModel = ComposableSettings.ViewModel<String>(
            title: "Name",
            get: { [weak self] in self?.project.name ?? "" },
            set: { [weak self] text in
                guard let self else { return }
                let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
                // A blank name is refused by not saving it: the field re-reads
                // `get` after every set and shows the stored name again.
                guard !name.isEmpty else { return }
                self.commit(self.project.replacing(name: name))
            }
        )
        nameField = ComposableSettings.TextEditView(with: nameModel)
        _ = nameField.textField.accessibilityID("billing.project.name")
        card.addSettingSubview(nameField)

        clientChoice = ComposableSettings.ChoiceViewModel<String>(
            title: "Client",
            choices: Self.clientChoices(clients: clients, current: project.clientId),
            get: { [weak self] in self?.project.clientId ?? "" },
            set: { [weak self] value in
                guard let self else { return }
                self.commit(self.project.replacing(clientId: .some(value.isEmpty ? nil : value)))
            },
            explanation: "Leave as None for your own work."
        )
        // A command, not a choice: picking it leaves the popup on the real
        // client, so a cancelled add leaves no trace.
        clientChoice.commands = [.init(title: Self.addClientTitle) { [weak self] in self?.onAddClient?() }]
        clientPopup = ComposableSettings.PopupMenuChoiceView(viewModel: clientChoice)
        _ = clientPopup.popUpButton.accessibilityID("billing.project.client")
        card.addSettingSubview(clientPopup)

        notesModel = ComposableSettings.ViewModel<String>(
            title: "Notes",
            get: { [weak self] in self?.project.notes ?? "" },
            set: { [weak self] notes in
                guard let self else { return }
                self.commit(self.project.replacing(notes: notes))
            }
        )
        notesField = ComposableSettings.TextAreaEditView(with: notesModel, visibleLines: 4)
        _ = notesField.textView.accessibilityID("billing.project.notes")
        card.addSettingSubview(notesField)
        return card
    }

    private func makeBillingCard() -> ComposableSettings.GroupView {
        let card = ComposableSettings.GroupView(withTitle: "Billing")

        billingModel = ComposableSettings.ViewModel<Bool>(
            title: "Track Time",
            get: { [weak self] in self?.project.billingEnabled ?? true },
            set: { [weak self] isOn in
                guard let self else { return }
                self.commit(self.project.replacing(billingEnabled: isOn))
            },
            explanation: "When off, activity in this project's repositories is not tracked."
        )
        billingToggle = ComposableSettings.CheckboxView(with: billingModel)
        _ = billingToggle.toggle.accessibilityID("billing.project.enabled")
        card.addSettingSubview(billingToggle)

        rateField = ComposableSettings.MoneyFieldView(
            title: "Default Rate (per hour)",
            range: BillingLimits.defaultRateCents,
            allowsBlank: true,
            formatter: { [weak self] in self?.formatter ?? MoneyFormatter(currency: "USD") },
            get: { [weak self] in self?.project.defaultRateCents },
            set: { [weak self] cents in
                guard let self else { return }
                self.commit(self.project.replacing(defaultRateCents: .some(cents)))
            },
            explanation: "Blank uses the default rate in Billing settings."
        )
        rateField.placeholderCents = settings.defaultRateCents.value
        _ = rateField.textField.accessibilityID("billing.project.rate")
        card.addSettingSubview(rateField)

        roundingModel = ComposableSettings.RangeViewModel<Int>(
            title: "Round To (minutes)",
            minValue: BillingLimits.roundingMinutes.lowerBound,
            maxValue: BillingLimits.roundingMinutes.upperBound,
            get: { [weak self] in self?.project.roundingMinutes ?? 15 },
            set: { [weak self] minutes in
                guard let self else { return }
                self.commit(self.project.replacing(roundingMinutes: minutes))
            }
        )
        roundingField = ComposableSettings.IntegerFieldView(viewModel: roundingModel)
        _ = roundingField.textField.accessibilityID("billing.project.rounding")
        card.addSettingSubview(roundingField)

        roundingModeModel = ComposableSettings.ChoiceViewModel<String>(
            title: "Rounding",
            choices: BillingSettingsPanel.roundingModeChoices,
            get: { [weak self] in self?.project.roundingMode ?? "up" },
            set: { [weak self] mode in
                guard let self else { return }
                self.commit(self.project.replacing(roundingMode: mode))
            }
        )
        roundingModePopup = ComposableSettings.PopupMenuChoiceView(viewModel: roundingModeModel)
        _ = roundingModePopup.popUpButton.accessibilityID("billing.project.roundingMode")
        card.addSettingSubview(roundingModePopup)

        archivedModel = ComposableSettings.ViewModel<Bool>(
            title: "Archived",
            get: { [weak self] in self?.project.archived ?? false },
            set: { [weak self] archived in
                guard let self else { return }
                self.commit(self.project.replacing(archived: archived))
            },
            explanation: "Kept with its history, but no longer offered when starting a timer."
        )
        archivedToggle = ComposableSettings.CheckboxView(with: archivedModel)
        _ = archivedToggle.toggle.accessibilityID("billing.project.archived")
        card.addSettingSubview(archivedToggle)
        return card
    }

    private func makeReposCard() -> ComposableSettings.EditableTableCard {
        let card = ComposableSettings.EditableTableCard(
            title: "Repositories",
            columns: [
                .init(id: "path", title: "Repository", width: 220),
                .init(id: "branch", title: "Branch", width: 110, kind: .text(editable: true)),
                .init(id: "rate", title: "Rate", width: 80,
                      kind: .money(range: BillingLimits.defaultRateCents, allowsBlank: true)),
                .init(id: "enabled", title: "Track", width: 44, kind: .toggle)
            ],
            emptyMessage: "Add a repository to track its time.",
            visibleRows: 4,
            accessibilityPrefix: "billing.project.repos"
        )
        card.onAdd = { [weak self] in self?.onAddRepo?() }
        card.onRemove = { [weak self] rowID in
            guard let self, let repo = self.repos.first(where: { $0.id == rowID }) else { return }
            self.onRemoveRepo?(repo)
        }
        card.onEdit = { [weak self] rowID, columnID, text in
            self?.editRepo(rowID, columnID, text)
        }
        card.onTypedEdit = { [weak self] rowID, columnID, value in
            guard let self, columnID == "rate", case .money(let cents) = value,
                  let repo = self.repos.first(where: { $0.id == rowID }), cents != repo.rateCents else { return }
            self.onSaveRepo?(repo.replacing(rateCents: .some(cents)))
        }
        card.onToggle = { [weak self] rowID, _, isOn in
            guard let self, let repo = self.repos.first(where: { $0.id == rowID }),
                  repo.billingEnabled != isOn else { return }
            self.onSaveRepo?(repo.replacing(billingEnabled: isOn))
        }
        return card
    }

    // MARK: - Model → fields

    /// The project's stored values and the current clients. Called on every
    /// reload; a field being typed in keeps what is typed.
    public func apply(_ fresh: BillingProjectDTO, clients: [BillingClientDTO]) {
        adopt(fresh)
        self.clients = clients
        guard isViewLoaded else { return }
        nameModel.refresh()
        billingModel.refresh()
        roundingModel.refresh()
        roundingModeModel.refresh()
        archivedModel.refresh()
        clientChoice.updateChoices(Self.clientChoices(clients: clients, current: fresh.clientId))
        clientChoice.refresh()
        notesModel.refresh()
        // The client, and so the currency the rate is shown in, may have moved;
        // what a blank rate bills at follows Settings.
        refreshRate()
    }

    /// After a save the daemon refused: the stored values, and every field
    /// whose attempted value was refused shows the stored one again — even
    /// the one still being edited, whose text is exactly what failed.
    public func revert(attempted: BillingProjectDTO, stored: BillingProjectDTO, clients: [BillingClientDTO]) {
        apply(stored, clients: clients)
        guard isViewLoaded else { return }
        if attempted.name != stored.name { nameModel.revert() }
        if attempted.defaultRateCents != stored.defaultRateCents { rateField.revert() }
        if attempted.roundingMinutes != stored.roundingMinutes { roundingModel.revert() }
        if attempted.notes != stored.notes { notesModel.revert() }
    }

    private func refreshRate() {
        guard let rateField else { return }
        rateField.placeholderCents = settings.defaultRateCents.value
        rateField.refresh()
        showRepos(repos)
    }

    /// The project's repositories, ordered by path with the any-branch row first.
    public func showRepos(_ repos: [BillingRepoDTO]) {
        self.repos = repos.sorted {
            ($0.projectRoot, $0.branch) < ($1.projectRoot, $1.branch)
        }
        guard isViewLoaded, let reposCard else { return }
        let currency = self.currency
        reposCard.setRows(self.repos.map { repo in
            ComposableSettings.EditableTableRow(id: repo.id, cells: [
                "path": .text((repo.projectRoot as NSString).abbreviatingWithTildeInPath),
                "branch": repo.branch.isEmpty ? .placeholder("Any branch") : .text(repo.branch),
                "rate": .money(repo.rateCents, currency: currency, placeholder: "Project rate"),
                "enabled": .toggle(repo.billingEnabled)
            ])
        })
    }

    private func editRepo(_ rowID: String, _ columnID: String, _ text: String) {
        guard columnID == "branch", let repo = repos.first(where: { $0.id == rowID }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != repo.branch else { return }
        onSaveRepo?(repo.replacing(branch: trimmed))
    }

    // MARK: - Helpers

    /// None, then the active clients by name, then the current client if it is
    /// archived (so an archived client never makes its projects look
    /// client-less). "Add Client…" is a command after them, not a choice. Two clients with one name are told
    /// apart by their contact, because `NSPopUpButton` merges equal titles.
    public static func clientChoices(
        clients: [BillingClientDTO], current: String?
    ) -> [ComposableSettings.ChoiceViewModel<String>.Choice] {
        var shown = clients.filter { !$0.archived || $0.id == current }
        shown.sort { $0.recordTitle.localizedStandardCompare($1.recordTitle) == .orderedAscending }
        let nameCounts = Dictionary(grouping: shown, by: \.recordTitle).mapValues(\.count)
        var choices: [ComposableSettings.ChoiceViewModel<String>.Choice] = [.init(label: "None", value: "")]
        for client in shown {
            var label = client.recordTitle
            if nameCounts[label, default: 0] > 1 {
                label += " — " + (client.contactName.isEmpty ? String(client.id.prefix(6)) : client.contactName)
            }
            if client.archived { label += " (Archived)" }
            choices.append(.init(label: label, value: client.id))
        }
        return choices
    }
}
