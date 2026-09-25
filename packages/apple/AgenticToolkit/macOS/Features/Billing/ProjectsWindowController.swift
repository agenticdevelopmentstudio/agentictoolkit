import AppKit
import Combine
import AgenticToolkitCore

/// The Projects window: `BillingModel.projects` in the toolkit's record-detail
/// window, then an Unassigned row for time no project claims. Each project's
/// repositories and billables load when it is selected, and every edit is
/// saved back through the model.
///
/// Everything app-specific — the model, the settings keys — arrives in a
/// ``BillingUIContext``, so any app can host it.
@MainActor
public final class ProjectsWindowController {

    public static private(set) var current: ProjectsWindowController?

    public static let newProjectName = "New Project"

    /// Runs `git`, so the controller calls it off the main actor.
    public typealias ResolveRoot = @Sendable (String) -> GitProjectRoot.Resolution
    /// Creates a client for "Add Client…". Injected because the real one opens
    /// the Clients window.
    public typealias AddClient = @MainActor () async -> BillingClientDTO?

    public let windowController: ComposableSettings.RecordDetailWindowController<BillingProjectDTO>
    /// The Unassigned row, listed under the projects. Built once, since it is
    /// handed runs before it is ever shown.
    public let unassignedPanel = UnassignedPanel()

    /// The write in flight, the selected project's detail load (repositories,
    /// billables, and the selected billable's history), and a history load on
    /// its own. Tests await them.
    public private(set) var lastWrite: Task<Void, Never>?
    public private(set) var lastDetailLoad: Task<Void, Never>?
    public private(set) var lastAuditLoad: Task<Void, Never>?

    private let model: BillingModel
    private let settings: BillingUserSettings
    private let chooseFolder: ComposableSettings.Alerts.ChooseFolder
    private let resolveRoot: ResolveRoot
    private let addClientCommand: AddClient
    private var subscription: AnyCancellable?
    private var lease: BillingWindowLease?

    private var confirm: ComposableSettings.Alerts.Confirm { windowController.confirm }
    private var reportFailure: ComposableSettings.Alerts.Report { windowController.reportFailure }

    /// Brings the window forward, building it first if needed, and activates
    /// the app: a menu command picked while another app is frontmost would
    /// otherwise open it behind that app.
    public static func present(context: BillingUIContext) {
        ensureCurrent(context: context).show()
        NSApp.activateUnlessQuiet()
    }

    /// Shows the window and keeps the model polling the lists while it is open.
    public func show() {
        windowController.showWindow()
        lease?.shown()
    }

    /// The window closed: stop listening, and let `present(context:)` build a
    /// fresh controller next time rather than keep this one alive and rebuilt
    /// on every poll.
    private func released() {
        subscription = nil
        if Self.current === self { Self.current = nil }
    }

    @discardableResult
    public static func ensureCurrent(context: BillingUIContext) -> ProjectsWindowController {
        if let current { return current }
        let controller = ProjectsWindowController(context: context)
        current = controller
        return controller
    }

    /// - Parameters:
    ///   - confirm, reportFailure: sheets on this window unless given.
    ///   - chooseFolder: the repository chooser; a sheet on this window unless given.
    ///   - addClient: "Add Client…"; opens the Clients window unless given.
    public init(
        context: BillingUIContext,
        confirm: ComposableSettings.Alerts.Confirm? = nil,
        reportFailure: ComposableSettings.Alerts.Report? = nil,
        chooseFolder: ComposableSettings.Alerts.ChooseFolder? = nil,
        resolveRoot: @escaping ResolveRoot = { GitProjectRoot.resolve(at: $0) },
        addClient: AddClient? = nil
    ) {
        let model = context.model
        let settings = context.settings
        self.model = model
        self.settings = settings
        let windowController = ComposableSettings.RecordDetailWindowController<BillingProjectDTO>(
            windowID: "billing.projects",
            title: "Projects",
            accessibilityPrefix: "billing.projects",
            makeDetailPanel: { ProjectDetailPanel(project: $0, settings: settings) },
            updateDetailPanel: { panel, project in
                (panel as? ProjectDetailPanel)?.apply(project, clients: model.clients)
            }
        )
        self.windowController = windowController
        if let confirm { windowController.confirm = confirm }
        if let reportFailure { windowController.reportFailure = reportFailure }
        self.chooseFolder = chooseFolder ?? { window, answer in
            ComposableSettings.Alerts.chooseFolder(
                on: window, prompt: "Add",
                message: "Choose a repository. Any folder inside it adds the whole repository.",
                answer)
        }
        self.resolveRoot = resolveRoot
        self.addClientCommand = addClient ?? {
            ClientsWindowController.present(context: context)
            return await ClientsWindowController.ensureCurrent(context: context).addClient()
        }

        windowController.windowStyleMask = [.titled, .closable, .resizable, .miniaturizable]
        windowController.windowSpec = WindowSpec(
            defaultSize: NSSize(width: 860, height: 640),
            minSize: NSSize(width: 640, height: 460),
            defaultPosition: .center,
            persistsFrame: true
        )
        windowController.onAddRecord = { [weak self] in
            guard let self else { return }
            self.lastWrite = Task { await self.addProject() }
        }
        windowController.onRemoveRecord = { [weak self] project in
            guard let self else { return }
            self.lastWrite = Task { await self.remove(project) }
        }
        windowController.onSelectRecord = { [weak self] project in
            guard let self, let project else { return }
            self.loadDetails(projectId: project.id)
        }
        // The factory runs before `self` exists; wire each pane as it is listed.
        windowController.onConfigurePanel = { [weak self] panel, _ in
            guard let self, let panel = panel as? ProjectDetailPanel else { return }
            self.wire(panel)
        }
        wire(unassignedPanel)
        windowController.setFixedPanels([unassignedPanel])

        reload()
        subscription = model.changes.sink { [weak self] in self?.reload() }
        lease = BillingWindowLease(model: model, windowController: windowController) { [weak self] in
            self?.released()
        }
    }

    // MARK: - Content

    public func panel(for id: String) -> ProjectDetailPanel? {
        windowController.panel(forRecordID: id) as? ProjectDetailPanel
    }

    /// Selects the Unassigned row.
    public func selectUnassigned() {
        windowController.selectFixedPanel(unassignedPanel)
    }

    /// Projects by name, archived last, then Unassigned. Reloads the selected
    /// project's details, which may have changed in another window.
    private func reload() {
        let sorted = model.projects.sorted { lhs, rhs in
            if lhs.archived != rhs.archived { return !lhs.archived }
            return lhs.recordTitle.localizedStandardCompare(rhs.recordTitle) == .orderedAscending
        }
        windowController.setRecords(sorted)
        unassignedPanel.show(segments: model.recentSegments, projects: model.projects, clients: model.clients)
        if let selected = windowController.selectedRecord {
            loadDetails(projectId: selected.id)
        }
    }

    private func wire(_ panel: ProjectDetailPanel) {
        panel.onSave = { [weak self] edited in self?.save(edited) }
        panel.onAddClient = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.lastWrite = Task { await self.addClient(to: panel.project) }
        }
        panel.onAddRepo = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.chooseRepo(for: panel.project)
        }
        panel.onSaveRepo = { [weak self] repo in self?.saveRepo(repo) }
        panel.onRemoveRepo = { [weak self] repo in
            guard let self else { return }
            self.lastWrite = Task {
                if !(await self.model.deleteRepo(id: repo.id)) {
                    self.reportFailure("The repository couldn't be removed. \(self.model.lastError ?? "")")
                }
                await self.settleDetails()
            }
        }

        let billables = panel.billables
        billables.onAdd = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.lastWrite = Task { await self.addBillable(to: panel.project) }
        }
        billables.onSave = { [weak self] entry in self?.saveEntry(entry) }
        billables.onSaveDescription = { [weak self] id, text in self?.saveDescription(of: id, text) }
        billables.onRemove = { [weak self] entry in
            guard let self else { return }
            self.lastWrite = Task { await self.removeBillable(entry) }
        }
        billables.onSetStatus = { [weak self] entry, status in self?.setStatus(of: entry, to: status) }
        billables.onSelect = { [weak self, weak billables] entryId in
            guard let self, let billables else { return }
            self.loadAudit(entryId: entryId, in: billables)
        }
        billables.onRefused = { [weak self] message in self?.reportFailure(message) }
    }

    private func wire(_ panel: UnassignedPanel) {
        panel.onAssignRun = { [weak self] segment, projectId in
            guard let self else { return }
            self.lastWrite = Task { _ = await self.assign([segment.id], to: projectId) }
        }
        panel.onAssignRepository = { [weak self] segment, projectId in
            guard let self, let project = self.model.project(id: projectId) else { return }
            self.lastWrite = Task { await self.assignRepository(of: segment, to: project) }
        }
        panel.onNewProject = { [weak self] segment in
            guard let self else { return }
            self.lastWrite = Task { _ = await self.newProject(from: segment) }
        }
    }

    /// Reads the selected project's repositories and billables side by side,
    /// replacing any load still in flight, whose answer would be older. The
    /// billables are read whole because the pane's totals are over all of
    /// them.
    private func loadDetails(projectId: String) {
        lastDetailLoad?.cancel()
        lastDetailLoad = Task { [weak self] in
            guard let self else { return }
            let model = self.model
            async let repos = model.repos(projectId: projectId)
            async let entries = model.entries(projectId: projectId)
            let (loadedRepos, loadedEntries) = await (repos, entries)
            guard !Task.isCancelled, let panel = self.panel(for: projectId) else { return }
            panel.showRepos(loadedRepos)
            panel.billables.show(loadedEntries)
            // A status change or an edit adds history rows for the selection.
            if let selected = panel.billables.selectedEntry {
                let audit = await model.audit(entryId: selected.id)
                guard !Task.isCancelled else { return }
                panel.billables.showAudit(audit)
            }
        }
    }

    /// Waits for the detail load in flight and for any that replaced it
    /// meanwhile, so what the pane shows is the latest.
    public func settleDetails() async {
        while let load = lastDetailLoad {
            await load.value
            if load == lastDetailLoad { return }
        }
    }

    private func loadAudit(entryId: String?, in section: ProjectBillablesSection) {
        lastAuditLoad = Task { [weak self] in
            guard let self else { return }
            guard let entryId else { return section.showAudit([]) }
            section.showAudit(await self.model.audit(entryId: entryId))
        }
    }

    // MARK: - Billables

    /// A billable entered by hand: today, one rounding increment, on the
    /// project's terms. Its group is its own, so it never collides with the
    /// derived billable for the same day (see the task notes).
    @discardableResult
    public func addBillable(to project: BillingProjectDTO) async -> BillingEntryDTO? {
        let seconds = project.roundingMinutes * 60
        let rate = project.defaultRateCents ?? settings.defaultRateCents.value
        let draft = BillingEntryDTO(
            id: "", projectId: project.id, clientId: project.clientId,
            day: UTCTimestamp.day(of: Date(), in: .current),
            groupKey: "manual-\(UUID().uuidString)",
            rawSeconds: 0, billedSeconds: seconds, rateCents: rate,
            currency: model.client(id: project.clientId)?.currency
                ?? settings.currency.value,
            amountCents: Money.amountCents(seconds: seconds, rateCents: rate),
            roundingMinutes: project.roundingMinutes, roundingMode: project.roundingMode,
            origin: "user"
        )
        guard let saved = await model.saveEntry(draft) else {
            reportFailure("The new billable couldn't be saved. \(model.lastError ?? "")")
            return nil
        }
        // The save's refresh has started a detail load; select once it lands.
        await settleDetails()
        panel(for: project.id)?.billables.select(entryId: saved.id)
        return saved
    }

    private func saveEntry(_ entry: BillingEntryDTO) {
        lastWrite = Task { [weak self] in
            guard let self else { return }
            if await self.model.saveEntry(entry) == nil {
                // The refresh that follows every write has already put the stored row back.
                self.reportFailure("The billable couldn't be saved. \(self.model.lastError ?? "")")
            }
        }
    }

    private func saveDescription(of entryId: String, _ description: String) {
        lastWrite = Task { [weak self] in
            guard let self else { return }
            if await self.model.setEntryDescription(id: entryId, description: description) == nil {
                self.reportFailure("The billable couldn't be saved. \(self.model.lastError ?? "")")
            }
        }
    }

    private func setStatus(of entry: BillingEntryDTO, to status: BillingStatus) {
        lastWrite = Task { [weak self] in
            guard let self else { return }
            if await self.model.setEntryStatus(id: entry.id, status: status) == nil {
                self.reportFailure("The billable couldn't be marked \(status.rawValue.capitalized). "
                    + (self.model.lastError ?? ""))
            }
        }
    }

    /// Deleting a derived billable gives its time back to the next pass, which
    /// bills it again, undoing any hand edits. A hand-made one simply goes.
    private func removeBillable(_ entry: BillingEntryDTO) async {
        let detail = entry.rawSeconds > 0
            ? "Its tracked time goes back to the project and is billed again on the next pass, "
                + "without any changes made by hand."
            : "It was entered by hand, so nothing else changes."
        guard await ComposableSettings.Alerts.ask(
            confirm, "Delete the billable for \(entry.day)?", detail: detail) else { return }
        if !(await model.deleteEntry(id: entry.id)) {
            reportFailure("The billable couldn't be deleted. \(model.lastError ?? "")")
        }
    }

    // MARK: - Projects

    @discardableResult
    public func addProject() async -> BillingProjectDTO? {
        guard let saved = await createProject(named: Self.newProjectName) else { return nil }
        windowController.selectRecord(id: saved.id)
        panel(for: saved.id)?.focusName()
        return saved
    }

    /// A new project with the settings' rounding, named `base` or, if that is
    /// taken, `base 2`, `base 3`… Two projects with one name would be two
    /// identical rows in every chooser.
    private func createProject(named base: String) async -> BillingProjectDTO? {
        let name = UniqueName.next(base: base, taken: model.projects.map(\.name))
        let draft = BillingProjectDTO(
            id: "", name: name,
            roundingMinutes: settings.roundingMinutes.value,
            roundingMode: settings.roundingMode.value
        )
        guard let saved = await model.saveProject(draft) else {
            reportFailure("The new project couldn't be saved. \(model.lastError ?? "")")
            return nil
        }
        return saved
    }

    private func save(_ project: BillingProjectDTO) {
        lastWrite = Task { [weak self] in
            guard let self else { return }
            if await self.model.saveProject(project) == nil {
                // The refresh that follows the write has re-applied the stored
                // project, but a refresh leaves alone a field still being
                // edited, and the refused text is in exactly that field. Force
                // it back, so ending the edit can't send it again.
                if let stored = self.model.project(id: project.id) {
                    self.panel(for: project.id)?.revert(attempted: project, stored: stored, clients: self.model.clients)
                }
                self.reportFailure("“\(project.recordTitle)” couldn't be saved. \(self.model.lastError ?? "")")
            }
        }
    }

    /// Billed hours must stay visible somewhere. A project with billables is
    /// archived, never deleted. See the task notes.
    private func remove(_ project: BillingProjectDTO) async {
        let billables = await model.entries(projectId: project.id)
        guard billables.isEmpty else {
            reportFailure("“\(project.recordTitle)” has \(billables.count) billable"
                + (billables.count == 1 ? "" : "s")
                + ", so it can't be deleted. Archive it instead to keep its history.")
            return
        }
        guard await ComposableSettings.Alerts.ask(
            confirm, "Delete “\(project.recordTitle)”?",
            detail: "Its repositories are forgotten. Time already tracked is kept and moves to Unassigned.")
        else { return }
        if !(await model.deleteProject(id: project.id)) {
            reportFailure("“\(project.recordTitle)” couldn't be deleted. \(model.lastError ?? "")")
        }
    }

    /// Creates a client and gives it the project. The project is read again
    /// once the client exists, not taken from when "Add Client…" was
    /// chosen: an edit saved meanwhile (say, Archived ticked while the
    /// Clients window opened) would otherwise be overwritten.
    private func addClient(to project: BillingProjectDTO) async {
        guard let client = await addClientCommand() else { return }
        let current = model.project(id: project.id) ?? project
        if await model.saveProject(current.replacing(clientId: .some(client.id))) == nil {
            reportFailure("“\(current.recordTitle)” couldn't be saved. \(model.lastError ?? "")")
        }
    }

    // MARK: - Unassigned

    /// Gives the runs to the project and rolls them into billables.
    private func assign(_ segmentIDs: [String], to projectId: String) async -> Bool {
        guard !segmentIDs.isEmpty else { return true }
        guard await model.assignAndRoll(segmentIDs: segmentIDs, projectId: projectId) != nil else {
            reportFailure("The time couldn't be assigned. \(model.lastError ?? "")")
            return false
        }
        return true
    }

    /// Records the run's repository under the project, then moves every
    /// unassigned run from that repository with it, however old, including
    /// one still running, which is billed when it stops. The daemon picks the
    /// runs: the window holds only the newest page of them. From here on the
    /// daemon maps the repository's activity to the project on its own.
    public func assignRepository(of segment: BillingSegmentDTO, to project: BillingProjectDTO) async {
        let root = segment.projectRoot
        guard !root.isEmpty, await recordRepo(root: root, to: project) != nil else { return }
        if await model.assignRepository(projectRoot: root, projectId: project.id) == nil {
            reportFailure("The time couldn't be assigned. \(model.lastError ?? "")")
        }
    }

    /// A project named after the run's repository, holding that repository
    /// and its time, then selected with its name ready to type. A timer run
    /// with no repository becomes "New Project" and takes only that run.
    @discardableResult
    public func newProject(from segment: BillingSegmentDTO) async -> BillingProjectDTO? {
        let root = segment.projectRoot
        let base = root.isEmpty ? Self.newProjectName : (root as NSString).lastPathComponent
        guard let project = await createProject(named: base) else { return nil }
        if root.isEmpty {
            _ = await assign([segment.id], to: project.id)
        } else {
            await assignRepository(of: segment, to: project)
        }
        windowController.selectRecord(id: project.id)
        panel(for: project.id)?.focusName()
        return project
    }

    // MARK: - Repositories

    private func chooseRepo(for project: BillingProjectDTO) {
        chooseFolder(windowController.window) { [weak self] url in
            guard let self, let url else { return }
            self.lastWrite = Task { _ = await self.addRepo(at: url.path, to: project) }
        }
    }

    /// Records the repository containing `path`, resolved to the root sessions
    /// report. Returns what was recorded, or nil after reporting why not.
    @discardableResult
    public func addRepo(at path: String, to project: BillingProjectDTO) async -> BillingRepoDTO? {
        let resolve = resolveRoot
        let resolution = await Task.detached { resolve(path) }.value
        let shown = (path as NSString).abbreviatingWithTildeInPath
        switch resolution {
        case .resolved(let root):
            return await recordRepo(root: root, to: project)
        case .notAGitWorkingTree:
            reportFailure("“\(shown)” isn't in a git repository. Only a repository's activity can be tracked.")
        case .undetermined:
            reportFailure("Git couldn't read “\(shown)”. Try again in a moment.")
        }
        return nil
    }

    /// Records `root` exactly as given. A folder the user picked is resolved
    /// first (`addRepo`). A segment's root is what a session reported, so it
    /// already is the root and is recorded as it is (see the task notes).
    private func recordRepo(root: String, to project: BillingProjectDTO) async -> BillingRepoDTO? {
        let repo = BillingRepoDTO(id: "", projectId: project.id, projectRoot: root)
        guard let saved = await model.saveRepo(repo) else {
            reportFailure("“\((root as NSString).abbreviatingWithTildeInPath)” couldn't be added. "
                + (model.lastError ?? "It may already belong to another project."))
            return nil
        }
        return saved
    }

    private func saveRepo(_ repo: BillingRepoDTO) {
        lastWrite = Task { [weak self] in
            guard let self else { return }
            if await self.model.saveRepo(repo) == nil {
                self.reportFailure("The repository couldn't be saved. "
                    + (self.model.lastError ?? "That branch may already belong to another project."))
            }
            // Repos aren't part of BillingModel's own refreshed state (they're
            // fetched per-project on demand), so a save's `changes` reload only
            // reassigns lastDetailLoad synchronously — it doesn't itself finish
            // before this task returns. Wait for it, so a second edit made right
            // after this one (as edits made from the pane's own callbacks are)
            // reads the pane's now-current repos rather than a stale snapshot.
            await self.settleDetails()
        }
    }
}
