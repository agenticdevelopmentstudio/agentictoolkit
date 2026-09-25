import AppKit
import AgenticToolkitCore

/// The Projects window's last row: tracked time no project claims, and the
/// three ways to give it one.
///
/// Like `ProjectDetailPanel`, it holds values and reports actions. The
/// daemon belongs to `ProjectsWindowController`. Its views are built in
/// `init`, not `viewDidLoad`, because the window hands it segments on every
/// reload, including before the pane has ever been shown.
@MainActor
public final class UnassignedPanel: ComposableSettings.SettingsPanelViewController {

    public static let accessibilityPrefix = "billing.unassigned"

    public var onAssignRun: ((BillingSegmentDTO, String) -> Void)?
    public var onAssignRepository: ((BillingSegmentDTO, String) -> Void)?
    public var onNewProject: ((BillingSegmentDTO) -> Void)?

    /// Start times are shown in this zone, on this locale's clock. The
    /// user's own, except in tests.
    public var timeZone: TimeZone = .current
    public var locale: Locale = .current

    public private(set) var assignCard: ComposableSettings.GroupView!
    public private(set) var timeCard: ComposableSettings.EditableTableCard!
    public private(set) var projectPopup: ComposableSettings.PopupMenuChoiceView<String>!
    public private(set) var assignRunButton: NSButton!
    public private(set) var assignRepositoryButton: NSButton!
    public private(set) var newProjectButton: NSButton!

    public private(set) var segments: [BillingSegmentDTO] = []
    /// The project the Assign buttons give time to. Nil only when there is no
    /// active project to choose.
    public private(set) var chosenProjectId: String?
    private var projectChoice: ComposableSettings.ChoiceViewModel<String>!

    public var selectedSegment: BillingSegmentDTO? {
        guard let id = timeCard.selectedRowID else { return nil }
        return segments.first { $0.id == id }
    }

    public init() {
        super.init(with: ComposableSettings.SettingsPanelDescriptor(
            title: BillingModel.unassignedTitle,
            icon: NSImage(systemSymbolName: "tray", accessibilityDescription: nil)
        ))
        buildCards()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override var searchKeywords: [String] {
        var words = ["unassigned", "assign", "time", "repository"]
        words += segments.map { ($0.projectRoot as NSString).lastPathComponent }
        return words.filter { !$0.isEmpty }
    }

    public override var helpContent: ComposableSettings.PanelHelp? {
        ComposableSettings.PanelHelp(topics: [
            .init(
                title: "Unassigned Time",
                body: "Time tracked in a repository that no project includes. It isn't billed "
                    + "until it's given to a project. Only the last 14 days are listed."
            ),
            .init(
                title: "Assigning",
                body: "Assign Run gives one run to the chosen project. Assign Repository adds the "
                    + "run's repository to the project, so all of its time here moves too and "
                    + "future work there is tracked to that project. New Project creates a "
                    + "project named after the repository and assigns the repository to it."
            )
        ])
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        addGroup(assignCard)
        addGroup(timeCard)
    }

    // MARK: - Cards

    private func buildCards() {
        assignCard = ComposableSettings.GroupView(withTitle: "Assign To")
        projectChoice = ComposableSettings.ChoiceViewModel<String>(
            title: "Project",
            choices: [Self.noProjectsChoice],
            get: { [weak self] in self?.chosenProjectId ?? "" },
            set: { [weak self] value in
                guard let self, !value.isEmpty else { return }
                self.chosenProjectId = value
                self.updateButtons()
            },
            explanation: "Archived projects aren't offered. Unarchive one in its own pane first."
        )
        projectPopup = ComposableSettings.PopupMenuChoiceView(viewModel: projectChoice)
        _ = projectPopup.popUpButton.accessibilityID("\(Self.accessibilityPrefix).project")
        assignCard.addSettingSubview(projectPopup)

        timeCard = ComposableSettings.EditableTableCard(
            title: "Unassigned Time",
            columns: [
                .init(id: "repository", title: "Repository", width: 200),
                .init(id: "branch", title: "Branch", width: 110),
                .init(id: "started", title: "Started", width: 100),
                .init(id: "hours", title: "Hours", width: 56),
                .init(id: "origin", title: "From", width: 64)
            ],
            emptyMessage: "No unassigned time in the last 14 days.",
            visibleRows: 10,
            accessibilityPrefix: "\(Self.accessibilityPrefix).time"
        )
        timeCard.showsAddRemove = false
        timeCard.onSelectionChange = { [weak self] _ in self?.updateButtons() }

        let prefix = Self.accessibilityPrefix
        assignRunButton = timeCard.addFooterButton(
            title: "Assign Run", identifier: "\(prefix).assignRun"
        ) { [weak self] in
            guard let self, let segment = self.selectedSegment, let project = self.chosenProjectId else { return }
            self.onAssignRun?(segment, project)
        }
        assignRepositoryButton = timeCard.addFooterButton(
            title: "Assign Repository", identifier: "\(prefix).assignRepository"
        ) { [weak self] in
            guard let self, let segment = self.selectedSegment, !segment.projectRoot.isEmpty,
                  let project = self.chosenProjectId else { return }
            self.onAssignRepository?(segment, project)
        }
        newProjectButton = timeCard.addFooterButton(
            title: "New Project…", identifier: "\(prefix).newProject"
        ) { [weak self] in
            guard let self, let segment = self.selectedSegment else { return }
            self.onNewProject?(segment)
        }
        updateButtons()
    }

    // MARK: - Model → cards

    /// Runs with no project, stopped and not yet on a billable, newest first.
    /// A running segment is left out: it has no length to bill yet, and Task 22's
    /// Activity window is where a run in progress is watched.
    public static func unassigned(_ segments: [BillingSegmentDTO]) -> [BillingSegmentDTO] {
        segments
            .filter { $0.projectId == nil && !$0.isRunning && $0.entryId == nil }
            .sorted { ($0.startedAt, $0.id) > ($1.startedAt, $1.id) }
    }

    public func show(
        segments all: [BillingSegmentDTO], projects: [BillingProjectDTO], clients: [BillingClientDTO] = []
    ) {
        segments = Self.unassigned(all)

        let active = BillingModel.activeSorted(projects)
        // The user's choice survives a reload unless its project has gone, in
        // which case the first project takes its place.
        if !active.contains(where: { $0.id == chosenProjectId }) {
            chosenProjectId = active.first?.id
        }
        let labels = BillingRecordTitle.projectLabels(active, clients: clients)
        let choices: [ComposableSettings.ChoiceViewModel<String>.Choice] = active.isEmpty
            ? [Self.noProjectsChoice]
            : active.map { .init(label: labels[$0.id] ?? $0.recordTitle, value: $0.id) }
        // Only when they changed: a rebuild under an open menu closes it.
        projectChoice.updateChoices(choices)
        projectPopup.isEnabled = !active.isEmpty

        timeCard.setRows(segments.map(row(for:)))
        updateButtons()
    }

    public func select(segmentId: String) {
        timeCard.selectRow(id: segmentId)
    }

    private func row(for segment: BillingSegmentDTO) -> ComposableSettings.EditableTableRow {
        let started = TimestampParsing.parse(segment.startedAt).map {
            LocalTimeText.dayAndClock($0, timeZone: timeZone, locale: locale)
        }
        let root = segment.projectRoot
        return ComposableSettings.EditableTableRow(id: segment.id, cells: [
            "repository": root.isEmpty
                ? .placeholder("No repository") : .text((root as NSString).abbreviatingWithTildeInPath),
            "branch": segment.branch.isEmpty ? .placeholder("—") : .text(segment.branch),
            "started": .text(started ?? segment.startedAt),
            "hours": .text(DurationFormatter.decimalHours(seconds: segment.seconds)),
            "origin": .text(segment.isManual ? "Timer" : "Tracked")
        ])
    }

    private func updateButtons() {
        let segment = selectedSegment
        let canAssign = segment != nil && chosenProjectId != nil
        assignRunButton?.isEnabled = canAssign
        assignRepositoryButton?.isEnabled = canAssign && !(segment?.projectRoot.isEmpty ?? true)
        newProjectButton?.isEnabled = segment != nil
    }

    private static let noProjectsChoice = ComposableSettings.ChoiceViewModel<String>.Choice(
        label: "No Projects", value: "")
}
