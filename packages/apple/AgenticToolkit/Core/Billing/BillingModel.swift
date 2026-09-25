import Foundation
import Combine

/// Always-running billing state for an app. Windows (or any other view of
/// billing) are consumers: they subscribe to `changes` and read the latest
/// state, and they write only through the methods here, each of which
/// refreshes — so an edit in one window reaches every other without them
/// knowing about each other.
///
/// Written against ``BillingService``, so a host hands in its own client — an
/// XPC client to its daemon, or a fake in a test — and the model is the same
/// in every app.
///
/// State is sticky through failures: a failed refresh sets `lastError` and
/// keeps the last good lists on screen.
@MainActor
public final class BillingModel {

    /// The name used for time in a repo no project claims.
    public nonisolated static let unassignedTitle = "Unassigned"

    /// How far back the recent-run list reaches.
    public nonisolated static let recentWindowDays = 14
    public nonisolated static let recentSegmentLimit = 500

    public nonisolated static let alreadyOnABillable =
        "The time is already on a billable, so it stays where it is."

    public private(set) var clients: [BillingClientDTO] = []
    public private(set) var projects: [BillingProjectDTO] = []
    public private(set) var runningTimers: [BillingSegmentDTO] = []
    public private(set) var recentSegments: [BillingSegmentDTO] = []
    public private(set) var overview: BillingOverviewDTO?
    public private(set) var lastError: String?
    public private(set) var lastUpdated: Date?

    public let changes = PassthroughSubject<Void, Never>()

    /// Where every read and write goes.
    public let service: any BillingService

    private let refresher: PeriodicRefresher
    private var refreshInterval: TimeInterval { refresher.interval }

    /// The consumers, each able to say whether it is on screen. With none
    /// showing, the poll reads only the running timers, which a menu's Stop
    /// Timer needs; the lists are read again when a consumer is shown.
    private struct Consumer {
        weak var owner: AnyObject?
        let isShowing: @MainActor () -> Bool
    }
    private var consumers: [ObjectIdentifier: Consumer] = [:]
    /// The first pass reads everything: a window restored at launch is on
    /// screen before it has said so.
    private var hasPolled = false

    /// Counts writes as they start. A refresh drops its answers if a write
    /// began while it was reading: they may predate it, and applying them
    /// would roll the write back on screen, where the next whole-record save
    /// would send the old values back to the daemon. The write's own refresh
    /// follows and lands.
    private var writesStarted = 0

    /// 30s by default: a daemon's own pass runs every minute, so polling
    /// faster only re-reads the same rows. Running timers tick locally in
    /// between.
    public init(service: any BillingService, refreshInterval: TimeInterval = 30) {
        self.service = service
        self.refresher = PeriodicRefresher(interval: refreshInterval)
    }

    public func start() {
        refresher.start(for: self) { await $0.poll() }
    }

    public func stop() {
        refresher.stop()
    }

    /// Adds a consumer that shows the lists. `isShowing` is asked on every
    /// pass; the entry goes when `owner` does or on ``removeConsumer(_:)``.
    public func addConsumer(_ owner: AnyObject, isShowing: @escaping @MainActor () -> Bool) {
        consumers[ObjectIdentifier(owner)] = Consumer(owner: owner, isShowing: isShowing)
    }

    public func removeConsumer(_ owner: AnyObject) {
        consumers[ObjectIdentifier(owner)] = nil
    }

    /// A consumer was just shown: read the lists now unless they are fresh,
    /// rather than at the next pass.
    public func consumerShown() {
        let fresh = lastUpdated.map { Date().timeIntervalSince($0) < refreshInterval } ?? false
        if !fresh { Task { await self.refresh() } }
    }

    /// Whether any consumer is on screen. Forgets consumers whose owner has
    /// gone.
    public func anyConsumerShowing() -> Bool {
        consumers = consumers.filter { $0.value.owner != nil }
        return consumers.values.contains { $0.isShowing() }
    }

    /// One scheduled pass: everything while a consumer is showing, only the
    /// running timers otherwise. A pass that finds nothing new tells no one.
    public func poll() async {
        if !hasPolled || anyConsumerShowing() {
            hasPolled = true
            await refresh(notifyUnchanged: false)
        } else {
            await refreshRunningTimers()
        }
    }

    /// Reads everything the windows list. `notifyUnchanged: false` is the
    /// poll's: it stays quiet when nothing moved, so an open window isn't
    /// rebuilt every pass for nothing.
    public func refresh(notifyUnchanged: Bool = true) async {
        let generation = writesStarted
        let service = service
        let since = UTCTimestamp.string(daysAgo: Self.recentWindowDays)
        async let clients = service.billingClients()
        async let projects = service.billingProjects()
        async let running = service.billingRunningTimers()
        async let segments = service.billingSegments(since: since, limit: Self.recentSegmentLimit)
        async let overview = service.billingOverview()

        guard let clients = await clients, let projects = await projects,
              let running = await running, let segments = await segments else {
            guard generation == writesStarted else { return }
            let changed = lastError == nil
            lastError = BillingRefusal.unreachable.message
            if changed || notifyUnchanged { changes.send() }
            return
        }
        // The overview is its own read and can fail alone — a timeout, or a
        // reply that doesn't decode. The last good figures stay rather than
        // turning into dashes, as if nothing were billable.
        let overviewValue = await overview ?? self.overview
        guard generation == writesStarted else { return }
        let changed = clients != self.clients || projects != self.projects
            || running != self.runningTimers || segments != self.recentSegments
            || overviewValue != self.overview || lastError != nil
        self.clients = clients
        self.projects = projects
        self.runningTimers = running
        self.recentSegments = segments
        self.overview = overviewValue
        lastError = nil
        lastUpdated = Date()
        if changed || notifyUnchanged { changes.send() }
    }

    private func refreshRunningTimers() async {
        let generation = writesStarted
        guard let running = await service.billingRunningTimers(),
              generation == writesStarted, running != runningTimers else { return }
        runningTimers = running
        changes.send()
    }

    // MARK: - Lookups

    /// The projects that can take new time — not archived — by name. The
    /// one definition every chooser offers from.
    public nonisolated static func activeSorted(_ projects: [BillingProjectDTO]) -> [BillingProjectDTO] {
        projects
            .filter { !$0.archived }
            .sorted {
                BillingRecordTitle.of($0.name).localizedStandardCompare(BillingRecordTitle.of($1.name))
                    == .orderedAscending
            }
    }

    public func project(id: String?) -> BillingProjectDTO? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    public func client(id: String?) -> BillingClientDTO? {
        guard let id else { return nil }
        return clients.first { $0.id == id }
    }

    public func projectName(for segment: BillingSegmentDTO) -> String {
        project(id: segment.projectId).map { BillingRecordTitle.of($0.name) } ?? Self.unassignedTitle
    }

    // MARK: - On-demand reads (per project, so not cached)

    public func repos(projectId: String) async -> [BillingRepoDTO] {
        await service.billingRepos(projectId: projectId) ?? []
    }

    public func entries(projectId: String?) async -> [BillingEntryDTO] {
        await service.billingEntries(projectId: projectId, status: nil, since: nil) ?? []
    }

    public func audit(entryId: String) async -> [BillingAuditDTO] {
        await service.billingEntryAudit(entryId: entryId) ?? []
    }

    // MARK: - Writes (each refreshes, so every consumer sees it)

    @discardableResult
    public func saveClient(_ value: BillingClientDTO) async -> BillingClientDTO? {
        await writing { await $0.billingSaveClient(value) }
    }

    @discardableResult
    public func deleteClient(id: String) async -> Bool {
        await deleting { await $0.billingDeleteClient(id: id) }
    }

    @discardableResult
    public func saveProject(_ value: BillingProjectDTO) async -> BillingProjectDTO? {
        await writing { await $0.billingSaveProject(value) }
    }

    @discardableResult
    public func deleteProject(id: String) async -> Bool {
        await deleting { await $0.billingDeleteProject(id: id) }
    }

    @discardableResult
    public func saveRepo(_ value: BillingRepoDTO) async -> BillingRepoDTO? {
        await writing { await $0.billingSaveRepo(value) }
    }

    @discardableResult
    public func deleteRepo(id: String) async -> Bool {
        await deleting { await $0.billingDeleteRepo(id: id) }
    }

    @discardableResult
    public func saveEntry(_ value: BillingEntryDTO) async -> BillingEntryDTO? {
        await writing { await $0.billingSaveEntry(value) }
    }

    @discardableResult
    public func setEntryStatus(id: String, status: BillingStatus) async -> BillingEntryDTO? {
        await writing { await $0.billingSetEntryStatus(id: id, status: status) }
    }

    /// The description editor's save: sends the words alone, so a window
    /// showing a minute-old copy of a growing entry can't freeze its figures.
    @discardableResult
    public func setEntryDescription(id: String, description: String) async -> BillingEntryDTO? {
        await writing { await $0.billingSetEntryDescription(id: id, description: description) }
    }

    @discardableResult
    public func deleteEntry(id: String) async -> Bool {
        await deleting { await $0.billingDeleteEntry(id: id) }
    }

    @discardableResult
    public func startTimer(_ start: BillingTimerStartDTO) async -> BillingSegmentDTO? {
        await writing { await $0.billingStartTimer(start) }
    }

    @discardableResult
    public func stopTimer(id: String) async -> BillingSegmentDTO? {
        await writing { await $0.billingStopTimer(id: id) }
    }

    @discardableResult
    public func promote(segmentIDs: [String]) async -> Int? {
        await refreshing { await $0.billingPromoteSegments(ids: segmentIDs) }
    }

    /// Gives every loose run from `projectRoot` to the project and rolls the
    /// finished ones into billables. The daemon picks the runs, so ones older
    /// than `recentSegments` reaches move too. Returns how many moved.
    @discardableResult
    public func assignRepository(projectRoot: String, projectId: String) async -> Int? {
        await refreshing { await $0.billingAssignRepository(projectRoot: projectRoot, projectId: projectId) }
    }

    /// Gives segments to a project and rolls them into billables straight
    /// away, with one refresh. The pass rolls up only what it derives itself,
    /// so time moved here by hand would otherwise wait for its session to
    /// become active again. Returns how many were rolled up (a running segment
    /// is moved but not rolled), or nil if either call failed or nothing
    /// moved.
    ///
    /// The daemon moves only time not yet on a billable, and answers 0 when
    /// every run asked for already is: its minute pass can roll a run between
    /// this list's refreshes. That is a failure, not a success that did
    /// nothing — the time stays billed to the project it was on.
    @discardableResult
    public func assignAndRoll(segmentIDs: [String], projectId: String) async -> Int? {
        let (movedNothing, rolled) = await refreshing { service -> (Bool, Int?) in
            guard let moved = await service.billingAssignSegments(ids: segmentIDs, projectId: projectId) else {
                return (false, nil)
            }
            guard moved > 0 || segmentIDs.isEmpty else { return (true, nil) }
            return (false, await service.billingPromoteSegments(ids: segmentIDs))
        }
        // After the refresh, which clears `lastError`.
        if movedNothing { lastError = Self.alreadyOnABillable }
        return rolled
    }

    /// Queues history since `since` for derivation. The daemon's next passes
    /// do the work, so the counts move over the following minutes, not now.
    @discardableResult
    public func backfill(since: String) async -> Int? {
        await refreshing { await $0.billingBackfill(since: since) }
    }

    private func refreshing<T>(_ write: (any BillingService) async -> T) async -> T {
        writesStarted += 1
        let result = await write(service)
        await refresh()
        return result
    }

    /// A write the daemon can refuse. The refusal's sentence becomes
    /// `lastError` *after* the refresh — which would otherwise clear it — so
    /// the window's alert reads the daemon's reason, not just "couldn't save".
    private func writing<T>(
        _ write: (any BillingService) async -> Result<T, BillingRefusal>
    ) async -> T? {
        let result = await refreshing(write)
        switch result {
        case .success(let value):
            return value
        case .failure(let refusal):
            lastError = refusal.message
            return nil
        }
    }

    private func deleting(
        _ delete: (any BillingService) async -> Result<Void, BillingRefusal>
    ) async -> Bool {
        await writing(delete) != nil
    }

    // MARK: - Time

    /// An instant the daemon wrote: ISO-8601 UTC, with or without fractional
    /// seconds. Nil for an empty string, which is how the daemon stores "not
    /// yet" (a running segment's end, a billable with no times).
    public nonisolated static func date(iso: String) -> Date? {
        TimestampParsing.parse(iso)
    }
}
