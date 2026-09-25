import AppKit
import AgenticToolkitCore

/// The Billing Activity window's content: starting a timer, the timers running
/// now, every run of the last 14 days, deriving older history, and the
/// overview.
///
/// Like `UnassignedPanel`, it holds values and reports actions. The daemon
/// belongs to `BillingActivityWindowController`. Its views are built in
/// `init`, because the window hands it runs before it has ever been shown.
@MainActor
public final class BillingActivityViewController: NSViewController {

    public static let accessibilityPrefix = "billing.activity"
    /// The spans Derive History offers, in days.
    public static let deriveSpans = [7, 30, 90]

    public var onProjectChosen: ((String?) -> Void)?
    public var onStart: ((BillingTimerStartDTO) -> Void)?
    public var onStop: ((BillingSegmentDTO) -> Void)?
    public var onCreateBillable: ((BillingSegmentDTO) -> Void)?
    public var onAssign: ((BillingSegmentDTO, String) -> Void)?
    public var onDeriveHistory: ((Int) -> Void)?

    /// The clock both elapsed columns count against. Injected so a test can
    /// state the time instead of waiting for it.
    public var now: () -> Date = Date.init
    /// Start times are shown in this zone. The user's own, except in tests.
    public var timeZone: TimeZone = .current
    /// Start times are worded for this locale. The user's own, except in tests.
    public var locale: Locale = .current
    /// The timers running now. It moves their clocks — and, through its
    /// `onTick`, the Runs table's Elapsed column — once a second while the
    /// window can be seen and something is running.
    public let runningList = ComposableSettings.LiveTimerListView(emptyMessage: "No timers running.")

    private let scrollView = ComposableSettings.PanelScrollView()
    private let panel = ComposableSettings.PanelView()

    public private(set) var projectPopup: ComposableSettings.PopupMenuChoiceView<String>!
    public private(set) var repositoryPopup: ComposableSettings.PopupMenuChoiceView<String>!
    public private(set) var noteField: ComposableSettings.TextEditView!
    public private(set) var startButton: NSButton!
    public private(set) var runsCard: ComposableSettings.EditableTableCard!
    public private(set) var stopButton: NSButton!
    public private(set) var createBillableButton: NSButton!
    public private(set) var assignButton: NSPopUpButton!
    public private(set) var deriveSpanPopup: ComposableSettings.PopupMenuChoiceView<Int>!
    public private(set) var deriveButton: NSButton!
    public private(set) var notice: ComposableSettings.ExplanationView!
    public private(set) var unbilledRow: ComposableSettings.ValueRowView!
    public private(set) var billedRow: ComposableSettings.ValueRowView!
    public private(set) var paidRow: ComposableSettings.ValueRowView!

    /// The timers running now, newest first.
    public private(set) var running: [BillingSegmentDTO] = []
    /// Every run the table lists, newest first.
    public private(set) var runs: [BillingSegmentDTO] = []
    public private(set) var projects: [BillingProjectDTO] = []
    /// Only for telling apart projects that share a name in the choosers.
    private var clients: [BillingClientDTO] = []
    /// The chosen project's repositories, once they have loaded.
    public private(set) var repos: [BillingRepoDTO] = []
    /// Nil means No Project: the timer's time goes to Unassigned.
    public private(set) var chosenProjectId: String?
    /// Nil means Any Repository.
    public private(set) var chosenRepoId: String?
    public private(set) var deriveDays = 30

    private var note = ""
    private var projectChoice: ComposableSettings.ChoiceViewModel<String>!
    private var repositoryChoice: ComposableSettings.ChoiceViewModel<String>!

    public var selectedRun: BillingSegmentDTO? {
        guard let id = runsCard.selectedRowID else { return nil }
        return runs.first { $0.id == id }
    }

    private var activeProjects: [BillingProjectDTO] {
        BillingModel.activeSorted(projects)
    }

    public init() {
        super.init(nibName: nil, bundle: nil)
        title = "Billing Activity"
        panel.addGroup(makeNewTimerGroup())
        panel.addGroup(makeRunningGroup())
        panel.addGroup(makeRunsCard())
        panel.addGroup(makeHistoryGroup())
        panel.addGroup(makeOverviewGroup())
        scrollView.setContent(panel)
        runningList.automaticOriginTooltip = "Started from session activity"
        runningList.now = { [weak self] in self?.now() ?? Date() }
        runningList.onTick = { [weak self] in self?.tickRuns() }
        runningList.onStop = { [weak self] id in
            guard let self, let segment = self.running.first(where: { $0.id == id }) else { return }
            self.onStop?(segment)
        }
        updateButtons()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override func loadView() {
        view = scrollView
    }

    // MARK: - Groups

    private func makeNewTimerGroup() -> ComposableSettings.GroupView {
        let group = ComposableSettings.GroupView(withTitle: "New Timer")
        projectChoice = ComposableSettings.ChoiceViewModel<String>(
            title: "Project",
            choices: [Self.noProjectChoice],
            get: { [weak self] in self?.chosenProjectId ?? "" },
            set: { [weak self] value in self?.chooseProject(value.isEmpty ? nil : value) },
            explanation: "Time on a timer with no project goes to Unassigned."
        )
        projectPopup = ComposableSettings.PopupMenuChoiceView(viewModel: projectChoice)
        _ = projectPopup.popUpButton.accessibilityID("\(Self.accessibilityPrefix).project")
        group.addSettingSubview(projectPopup)

        repositoryChoice = ComposableSettings.ChoiceViewModel<String>(
            title: "Repository",
            choices: [Self.anyRepositoryChoice],
            get: { [weak self] in self?.chosenRepoId ?? "" },
            set: { [weak self] value in self?.chosenRepoId = value.isEmpty ? nil : value }
        )
        repositoryPopup = ComposableSettings.PopupMenuChoiceView(viewModel: repositoryChoice)
        repositoryPopup.isEnabled = false
        _ = repositoryPopup.popUpButton.accessibilityID("\(Self.accessibilityPrefix).repository")
        group.addSettingSubview(repositoryPopup)

        noteField = ComposableSettings.TextEditView(with: ComposableSettings.ViewModel<String>(
            title: "Note",
            get: { [weak self] in self?.note ?? "" },
            set: { [weak self] text in self?.note = text },
            explanation: "Optional. Shown on the timer while it runs."
        ))
        _ = noteField.textField.accessibilityID("\(Self.accessibilityPrefix).note")
        group.addSettingSubview(noteField)

        let start = ComposableSettings.ButtonView(
            viewModel: ComposableSettings.ButtonViewModel(title: "Start Timer") { [weak self] in
                self?.startPressed()
            },
            placement: .leading
        )
        startButton = start.button
        _ = startButton.accessibilityID("\(Self.accessibilityPrefix).start")
        group.addSettingSubview(start)
        return group
    }

    private func makeRunningGroup() -> ComposableSettings.GroupView {
        let group = ComposableSettings.GroupView(withTitle: "Running")
        group.addSettingSubview(runningList)
        return group
    }

    private func makeRunsCard() -> ComposableSettings.EditableTableCard {
        let card = ComposableSettings.EditableTableCard(
            title: "Runs",
            columns: [
                .init(id: "running", title: "", width: 22, kind: .indicator),
                .init(id: "project", title: "Project", width: 130),
                .init(id: "repository", title: "Repository", width: 190),
                .init(id: "started", title: "Started", width: 100),
                .init(id: "elapsed", title: "Elapsed", width: 70),
                .init(id: "origin", title: "From", width: 60),
                .init(id: "status", title: "Status", width: 120)
            ],
            emptyMessage: "No runs in the last 14 days.",
            visibleRows: 10,
            accessibilityPrefix: "\(Self.accessibilityPrefix).runs"
        )
        card.showsAddRemove = false
        card.onSelectionChange = { [weak self] _ in self?.updateButtons() }

        let prefix = "\(Self.accessibilityPrefix).runs"
        stopButton = card.addFooterButton(title: "Stop", identifier: "\(prefix).stop") { [weak self] in
            guard let self, let run = self.selectedRun, run.isRunning, run.isManual else { return }
            self.onStop?(run)
        }
        createBillableButton = card.addFooterButton(
            title: "Create Billable", identifier: "\(prefix).createBillable"
        ) { [weak self] in
            guard let self, let run = self.selectedRun, Self.canBill(run) else { return }
            self.onCreateBillable?(run)
        }
        // A pull-down, built as it opens: the projects offered depend on the
        // run selected at that moment.
        assignButton = card.addFooterMenuButton(
            title: "Assign to Project…", identifier: "\(prefix).assign"
        ) { [weak self] in
            self?.assignMenuItems() ?? []
        }
        runsCard = card
        return card
    }

    private func makeHistoryGroup() -> ComposableSettings.GroupView {
        let group = ComposableSettings.GroupView(withTitle: "History")
        deriveSpanPopup = ComposableSettings.PopupMenuChoiceView(viewModel: ComposableSettings.ChoiceViewModel<Int>(
            title: "Derive From",
            choices: Self.deriveSpans.map { .init(label: "Last \($0) Days", value: $0) },
            get: { [weak self] in self?.deriveDays ?? 30 },
            set: { [weak self] days in self?.deriveDays = days },
            explanation: "Finds runs in sessions recorded before billing was set up. "
                + "Deriving again is safe: no time is counted twice."
        ))
        _ = deriveSpanPopup.popUpButton.accessibilityID("\(Self.accessibilityPrefix).deriveSpan")
        group.addSettingSubview(deriveSpanPopup)

        let derive = ComposableSettings.ButtonView(
            viewModel: ComposableSettings.ButtonViewModel(title: "Derive History") { [weak self] in
                guard let self else { return }
                self.onDeriveHistory?(self.deriveDays)
            },
            placement: .leading
        )
        deriveButton = derive.button
        _ = deriveButton.accessibilityID("\(Self.accessibilityPrefix).derive")
        group.addSettingSubview(derive)

        // An ExplanationView, not a bare label: it wraps at any Text Size,
        // and its card row follows it when it is shown after starting hidden.
        notice = ComposableSettings.ExplanationView(withText: "")
        notice.isHidden = true
        group.addSettingSubview(notice, style: .continuation)
        return group
    }

    private func makeOverviewGroup() -> ComposableSettings.GroupView {
        let group = ComposableSettings.GroupView(withTitle: "Overview")
        unbilledRow = ComposableSettings.ValueRowView(title: "Unbilled", value: "—")
        billedRow = ComposableSettings.ValueRowView(title: "Billed", value: "—")
        paidRow = ComposableSettings.ValueRowView(title: "Paid", value: "—")
        for row in [unbilledRow!, billedRow!, paidRow!] {
            group.addSettingSubview(row)
        }
        return group
    }

    // MARK: - Model → views

    /// Everything the window shows. `recent` is the model's last 14 days;
    /// `running` is added to it, because a timer left running for longer
    /// is still something the user has to see.
    public func show(
        running: [BillingSegmentDTO],
        recent: [BillingSegmentDTO],
        projects: [BillingProjectDTO],
        clients: [BillingClientDTO] = [],
        overview: BillingOverviewDTO?
    ) {
        self.projects = projects
        self.clients = clients
        self.running = running.sorted(by: Self.newestFirst)
        var byID: [String: BillingSegmentDTO] = [:]
        for segment in recent { byID[segment.id] = segment }
        for segment in running { byID[segment.id] = segment }
        runs = byID.values.sorted(by: Self.newestFirst)

        showProjects()
        // A tracked run ends when its session goes quiet; only a timer has a stop.
        runningList.setTimers(self.running.map(timerModel(for:)))
        runsCard.setRows(runRows())
        unbilledRow.value = Self.describe(overview, \.unbilled)
        billedRow.value = Self.describe(overview, \.billed)
        paidRow.value = Self.describe(overview, \.paid)
        updateButtons()
    }

    /// The chosen project's repositories. An answer for a project no longer
    /// chosen is dropped, since the user has moved on.
    public func showRepos(_ repos: [BillingRepoDTO], projectId: String) {
        guard projectId == chosenProjectId else { return }
        self.repos = repos
        repositoryChoice.choices = [Self.anyRepositoryChoice] + repos.map {
            .init(label: GitProjectRoot.displayLabel(root: $0.projectRoot, branch: $0.branch), value: $0.id)
        }
        repositoryPopup.isEnabled = !repos.isEmpty
    }

    /// Empties the note once the timer it described has started.
    public func clearNote() {
        note = ""
        noteField.textField.stringValue = ""
    }

    /// A line under Derive History, or nil to hide it.
    public func showNotice(_ text: String?) {
        notice.text = text ?? ""
        notice.isHidden = text == nil
    }

    public func select(runId: String) {
        runsCard.selectRow(id: runId)
    }

    /// The projects the selected run can move to: every active one but its own.
    public func assignMenuItems() -> [NSMenuItem] {
        let offered = activeProjects.filter { $0.id != selectedRun?.projectId }
        let labels = BillingRecordTitle.projectLabels(offered, clients: clients)
        return offered.map { project in
            let item = NSMenuItem(
                title: labels[project.id] ?? project.recordTitle,
                action: #selector(assignChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = project.id
            return item
        }
    }

    @objc private func assignChosen(_ item: NSMenuItem) {
        guard let run = selectedRun, let projectId = item.representedObject as? String else { return }
        onAssign?(run, projectId)
    }

    private func showProjects() {
        let active = activeProjects
        // An archived or deleted project can't take new time.
        if let chosen = chosenProjectId, !active.contains(where: { $0.id == chosen }) {
            chooseProject(nil)
        }
        let labels = BillingRecordTitle.projectLabels(active, clients: clients)
        // Only when they changed: a rebuild under an open menu closes it.
        projectChoice.updateChoices([Self.noProjectChoice]
            + active.map { .init(label: labels[$0.id] ?? $0.recordTitle, value: $0.id) })
    }

    private func chooseProject(_ id: String?) {
        guard id != chosenProjectId else { return }
        chosenProjectId = id
        chosenRepoId = nil
        repos = []
        if !repositoryChoice.updateChoices([Self.anyRepositoryChoice]) {
            repositoryChoice.onChange?("")
        }
        repositoryPopup.isEnabled = false
        // The popups show the values just set: a change made here, not by
        // a pick in the popup, would otherwise leave the old one showing.
        projectChoice.onChange?(id ?? "")
        onProjectChosen?(id)
    }

    private func timerModel(for segment: BillingSegmentDTO) -> ComposableSettings.LiveTimerRowView.Model {
        var details: [String] = []
        if !segment.projectRoot.isEmpty {
            details.append(GitProjectRoot.displayLabel(root: segment.projectRoot, branch: segment.branch))
        }
        if !segment.note.isEmpty { details.append(segment.note) }
        if Self.isRunaway(segment) { details.append("Running past the cap") }
        return .init(
            id: segment.id,
            title: projectName(segment.projectId),
            subtitle: details.isEmpty ? nil : details.joined(separator: " · "),
            startedAt: BillingModel.date(iso: segment.startedAt) ?? now(),
            isManual: segment.isManual
        )
    }

    private func runRows() -> [ComposableSettings.EditableTableRow] {
        let now = now()
        return runs.map { runRow(for: $0, now: now) }
    }

    private func runRow(for segment: BillingSegmentDTO, now: Date) -> ComposableSettings.EditableTableRow {
        let start = BillingModel.date(iso: segment.startedAt)
        let elapsed = segment.isRunning
            ? max(0, Int(now.timeIntervalSince(start ?? now)))
            : segment.seconds
        let root = segment.projectRoot
        return ComposableSettings.EditableTableRow(id: segment.id, cells: [
            "running": .indicator(segment.isRunning),
            "project": .text(projectName(segment.projectId)),
            "repository": root.isEmpty
                ? .placeholder("No repository")
                : .text(GitProjectRoot.displayLabel(root: root, branch: segment.branch)),
            "started": .text(start.map {
                LocalTimeText.dayAndClock($0, timeZone: timeZone, locale: locale)
            } ?? segment.startedAt),
            "elapsed": .text(DurationFormatter.clock(seconds: elapsed)),
            "origin": .text(segment.isManual ? "Timer" : "Tracked"),
            "status": .text(Self.status(of: segment))
        ], isFlagged: Self.isRunaway(segment))
    }

    private func projectName(_ id: String?) -> String {
        projects.first { $0.id == id }?.recordTitle ?? BillingModel.unassignedTitle
    }

    // MARK: - Actions

    private func startPressed() {
        // The field, not `note`: text still being typed has not been committed yet.
        let text = noteField.textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = repos.first { $0.id == chosenRepoId }
        onStart?(BillingTimerStartDTO(
            projectId: chosenProjectId,
            repoId: repo?.id,
            projectRoot: repo?.projectRoot ?? "",
            branch: repo?.branch ?? "",
            note: text
        ))
    }

    private func updateButtons() {
        let run = selectedRun
        stopButton?.isEnabled = run.map { $0.isRunning && $0.isManual } ?? false
        createBillableButton?.isEnabled = run.map(Self.canBill) ?? false
        // Time already on a billable stays there; moving it would change a
        // figure the user may have sent.
        assignButton?.isEnabled = (run.map { $0.entryId == nil } ?? false) && !activeProjects.isEmpty
    }

    /// Only the running rows' clocks move, so only they are rebuilt; the
    /// rest of the table (hundreds of rows over 14 days) is left alone.
    private func tickRuns() {
        let now = now()
        let changed = runs.filter(\.isRunning).map { runRow(for: $0, now: now) }
        if !runsCard.updateRows(changed) {
            // A running row the table doesn't hold yet: redraw it whole.
            runsCard.setRows(runRows())
        }
    }

    // MARK: - Wording

    /// Where a run stands, in the order the user cares about: a runaway
    /// first, then anything still going, then where the time went.
    public static func status(of segment: BillingSegmentDTO) -> String {
        if segment.isRunning { return isRunaway(segment) ? "Past the cap" : "Running" }
        if segment.entryId != nil { return "On a billable" }
        if segment.projectId == nil { return BillingModel.unassignedTitle }
        return "Not on a billable"
    }

    public static func isRunaway(_ segment: BillingSegmentDTO) -> Bool {
        segment.flags.contains("runaway")
    }

    /// One overview status, worded the way the Projects window words a
    /// project's totals, across every currency in use: counts and hours add up, the
    /// money never does — each currency keeps its own figure ("$250.00 +
    /// €80.00"), because there is no conversion to add them with. A daemon
    /// that predates `byCurrency` sends none, so the top-level bucket stands in.
    public static func describe(
        _ overview: BillingOverviewDTO?,
        _ status: KeyPath<BillingOverviewCurrencyDTO, BillingOverviewBucketDTO>
    ) -> String {
        guard let overview else { return ProjectBillablesSection.describe(nil) }
        let rows = overview.byCurrency.isEmpty
            ? [BillingOverviewCurrencyDTO(currency: overview.currency, unbilled: overview.unbilled,
                                          billed: overview.billed, paid: overview.paid)]
            : overview.byCurrency
        var totals = ProjectBillablesSection.Totals()
        for row in rows {
            let bucket = row[keyPath: status]
            guard bucket.entryCount > 0 else { continue }
            totals.count += bucket.entryCount
            totals.seconds += bucket.seconds
            totals.money.add(cents: bucket.amountCents, currency: row.currency)
        }
        return ProjectBillablesSection.describe(totals)
    }

    /// A stopped run with a project and no billable yet.
    private static func canBill(_ segment: BillingSegmentDTO) -> Bool {
        !segment.isRunning && segment.projectId != nil && segment.entryId == nil
    }

    private static func newestFirst(_ lhs: BillingSegmentDTO, _ rhs: BillingSegmentDTO) -> Bool {
        (lhs.startedAt, lhs.id) > (rhs.startedAt, rhs.id)
    }

    private static let noProjectChoice = ComposableSettings.ChoiceViewModel<String>.Choice(
        label: "No Project", value: "")
    private static let anyRepositoryChoice = ComposableSettings.ChoiceViewModel<String>.Choice(
        label: "Any Repository", value: "")
}
