import Foundation
import AgenticToolkitCore

/// An in-memory stand-in for the daemon's billing surface. It keeps the rules
/// the windows depend on — ids are assigned on save, a blank name is refused,
/// a locked entry cannot be edited or deleted, deleting a client detaches its
/// projects — and nothing else; the real rules are Tasks 7–11's to prove.
/// `reachable = false` answers every call the way a dead transport does: nil
/// for a read, ``BillingRefusal/unreachable`` for a write. A refused write
/// carries the daemon's own sentence, read from ``BillingRefusalText`` — the
/// same constants the daemon's errors return.
final class FakeBillingClient: BillingService, @unchecked Sendable {
    var reachable = true
    var clients: [BillingClientDTO] = []
    var projects: [BillingProjectDTO] = []
    var repos: [BillingRepoDTO] = []
    var entries: [BillingEntryDTO] = []
    var audits: [BillingAuditDTO] = []
    var segments: [BillingSegmentDTO] = []
    var overviewValue = BillingOverviewDTO(
        unbilled: BillingOverviewBucketDTO(seconds: 0, amountCents: 0, entryCount: 0),
        billed: BillingOverviewBucketDTO(seconds: 0, amountCents: 0, entryCount: 0),
        paid: BillingOverviewBucketDTO(seconds: 0, amountCents: 0, entryCount: 0)
    )
    /// The overview alone fails to answer, the way a timeout or the
    /// daemon's undecodable `{}` does, while every list read succeeds.
    var overviewFails = false
    var lastBackfillSince: String?
    var lastStartedTimer: BillingTimerStartDTO?
    /// The ids of the last `billingPromoteSegments` call, as sent.
    var lastPromotedIDs: [String] = []
    private var counter = 0
    /// How many times the project list and the running timers were read.
    var projectReads = 0
    var runningReads = 0
    /// Held by the next project-list read after it has taken its answer, so
    /// a test can let a write land between a refresh's read and its return.
    var holdNextProjectsRead: FakeGate?

    /// One client, one live and one archived project, one running and one
    /// loose segment, and an unbilled balance — enough for every window to
    /// have something in each list.
    static func seeded() -> FakeBillingClient {
        let fake = FakeBillingClient()
        fake.clients = [BillingClientDTO(id: "c1", name: "Acme")]
        fake.projects = [
            BillingProjectDTO(id: "p1", clientId: "c1", name: "Website"),
            BillingProjectDTO(id: "p2", name: "Old thing", archived: true)
        ]
        fake.segments = [
            BillingSegmentDTO(id: "s-running", origin: "auto", projectId: "p1",
                              projectRoot: "/src/site", startedAt: "2026-09-22T09:00:00Z"),
            BillingSegmentDTO(id: "s-loose", origin: "auto", projectRoot: "/src/misc",
                              startedAt: "2026-09-22T08:00:00Z", endedAt: "2026-09-22T08:30:00Z",
                              seconds: 1800)
        ]
        fake.overviewValue = BillingOverviewDTO(
            unbilled: BillingOverviewBucketDTO(seconds: 9000, amountCents: 25_000, entryCount: 2),
            billed: BillingOverviewBucketDTO(seconds: 0, amountCents: 0, entryCount: 0),
            paid: BillingOverviewBucketDTO(seconds: 0, amountCents: 0, entryCount: 0)
        )
        return fake
    }

    private func nextID(_ prefix: String) -> String {
        counter += 1
        return "\(prefix)-\(counter)"
    }

    static let nameRequired = BillingRefusal(message: BillingRefusalText.missingName)
    static let entryLocked = BillingRefusal(message: BillingRefusalText.entryIsLocked)
    static let unknownEntry = BillingRefusal(message: BillingRefusalText.unknownEntry)

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func upsert<T: Identifiable>(_ value: T, into list: inout [T]) where T.ID == String {
        if let index = list.firstIndex(where: { $0.id == value.id }) {
            list[index] = value
        } else {
            list.append(value)
        }
    }

    // MARK: Clients

    func billingClients() async -> [BillingClientDTO]? { reachable ? clients : nil }

    func billingSaveClient(_ client: BillingClientDTO) async -> Result<BillingClientDTO, BillingRefusal> {
        guard reachable else { return .failure(.unreachable) }
        guard !Self.isBlank(client.name) else { return .failure(Self.nameRequired) }
        let saved = client.id.isEmpty ? client.replacing(id: nextID("c")) : client
        upsert(saved, into: &clients)
        return .success(saved)
    }

    func billingDeleteClient(id: String) async -> Result<Void, BillingRefusal> {
        guard reachable else { return .failure(.unreachable) }
        clients.removeAll { $0.id == id }
        projects = projects.map { $0.clientId == id ? $0.replacing(clientId: .some(nil)) : $0 }
        return .success(())
    }

    // MARK: Projects

    func billingProjects() async -> [BillingProjectDTO]? {
        projectReads += 1
        let answer = reachable ? projects : nil
        if let gate = holdNextProjectsRead {
            holdNextProjectsRead = nil
            await gate.pass()
        }
        return answer
    }

    func billingSaveProject(_ project: BillingProjectDTO) async -> Result<BillingProjectDTO, BillingRefusal> {
        guard reachable else { return .failure(.unreachable) }
        guard !Self.isBlank(project.name) else { return .failure(Self.nameRequired) }
        let saved = project.id.isEmpty ? project.replacing(id: nextID("p")) : project
        upsert(saved, into: &projects)
        return .success(saved)
    }

    func billingDeleteProject(id: String) async -> Result<Void, BillingRefusal> {
        guard reachable else { return .failure(.unreachable) }
        projects.removeAll { $0.id == id }
        repos.removeAll { $0.projectId == id }
        segments = segments.map { $0.projectId == id ? Self.segment($0, projectId: .some(nil)) : $0 }
        return .success(())
    }

    // MARK: Repos

    func billingRepos(projectId: String) async -> [BillingRepoDTO]? {
        reachable ? repos.filter { $0.projectId == projectId } : nil
    }

    func billingSaveRepo(_ repo: BillingRepoDTO) async -> Result<BillingRepoDTO, BillingRefusal> {
        guard reachable else { return .failure(.unreachable) }
        guard !Self.isBlank(repo.projectRoot) else {
            return .failure(BillingRefusal(message: BillingRefusalText.missingRepoRoot))
        }
        guard !repos.contains(where: {
            $0.id != repo.id && $0.projectRoot == repo.projectRoot && $0.branch == repo.branch
        }) else {
            return .failure(BillingRefusal(
                message: BillingRefusalText.repoAlreadyClaimed(root: repo.projectRoot, branch: repo.branch)
            ))
        }
        let saved = repo.id.isEmpty
            ? BillingRepoDTO(id: nextID("r"), projectId: repo.projectId, projectRoot: repo.projectRoot,
                             branch: repo.branch, rateCents: repo.rateCents,
                             billingEnabled: repo.billingEnabled)
            : repo
        upsert(saved, into: &repos)
        return .success(saved)
    }

    func billingDeleteRepo(id: String) async -> Result<Void, BillingRefusal> {
        guard reachable else { return .failure(.unreachable) }
        repos.removeAll { $0.id == id }
        return .success(())
    }

    // MARK: Entries

    func billingEntries(
        projectId: String?, status: BillingStatus?, since: String?
    ) async -> [BillingEntryDTO]? {
        guard reachable else { return nil }
        return entries
            .filter { projectId == nil || $0.projectId == projectId }
            .filter { status == nil || $0.status == status?.rawValue }
            .filter { since == nil || $0.day >= since! }
            .sorted { $0.day > $1.day }
    }

    func billingSaveEntry(_ entry: BillingEntryDTO) async -> Result<BillingEntryDTO, BillingRefusal> {
        guard reachable else { return .failure(.unreachable) }
        let existing = entries.first(where: { $0.id == entry.id })
        if let existing, existing.locked { return .failure(Self.entryLocked) }
        // The daemon's rule: a save never moves status — that's setEntryStatus's
        // job, because only it writes the audit row.
        guard entry.status == (existing?.status ?? BillingStatus.unbilled.rawValue) else {
            return .failure(BillingRefusal(message: BillingRefusalText.statusChangeNotAllowed(
                current: existing?.status ?? BillingStatus.unbilled.rawValue, requested: entry.status
            )))
        }
        let saved = entry.id.isEmpty ? Self.entry(entry, id: nextID("e")) : entry
        upsert(saved, into: &entries)
        return .success(saved)
    }

    func billingSetEntryStatus(
        id: String, status: BillingStatus
    ) async -> Result<BillingEntryDTO, BillingRefusal> {
        guard reachable else { return .failure(.unreachable) }
        guard let old = entries.first(where: { $0.id == id }) else { return .failure(Self.unknownEntry) }
        // The daemon answers a move to the status the entry already has with
        // the row unchanged and writes no audit row.
        guard old.status != status.rawValue else { return .success(old) }
        let moved = Self.entry(old, status: status)
        upsert(moved, into: &entries)
        audits.append(BillingAuditDTO(entryId: id, at: "2026-09-22T12:00:00Z", field: "status",
                                      oldValue: old.status, newValue: status.rawValue, source: "user"))
        return .success(moved)
    }

    /// Every description-only save, in order — the proof the editor sent the
    /// words rather than a whole (possibly stale) row.
    var descriptionSaves: [(id: String, description: String)] = []

    func billingSetEntryDescription(
        id: String, description: String
    ) async -> Result<BillingEntryDTO, BillingRefusal> {
        guard reachable else { return .failure(.unreachable) }
        guard let old = entries.first(where: { $0.id == id }) else { return .failure(Self.unknownEntry) }
        if old.locked { return .failure(Self.entryLocked) }
        descriptionSaves.append((id, description))
        let saved = old.replacing(description: description)
        upsert(saved, into: &entries)
        return .success(saved)
    }

    func billingDeleteEntry(id: String) async -> Result<Void, BillingRefusal> {
        guard reachable else { return .failure(.unreachable) }
        guard let entry = entries.first(where: { $0.id == id }) else { return .failure(Self.unknownEntry) }
        guard !entry.locked else { return .failure(Self.entryLocked) }
        entries.removeAll { $0.id == id }
        return .success(())
    }

    func billingEntryAudit(entryId: String) async -> [BillingAuditDTO]? {
        reachable ? audits.filter { $0.entryId == entryId } : nil
    }

    // MARK: Segments and timers

    func billingSegments(since: String?, limit: Int) async -> [BillingSegmentDTO]? {
        reachable ? Array(segments.sorted { $0.startedAt > $1.startedAt }.prefix(limit)) : nil
    }

    func billingRunningTimers() async -> [BillingSegmentDTO]? {
        runningReads += 1
        return reachable ? segments.filter(\.isRunning) : nil
    }

    func billingStartTimer(_ start: BillingTimerStartDTO) async -> Result<BillingSegmentDTO, BillingRefusal> {
        guard reachable else { return .failure(.unreachable) }
        lastStartedTimer = start
        let segment = BillingSegmentDTO(id: nextID("s"), origin: "manual", projectId: start.projectId,
                                        repoId: start.repoId, projectRoot: start.projectRoot,
                                        branch: start.branch, startedAt: "2026-09-22T10:00:00Z",
                                        note: start.note)
        segments.append(segment)
        return .success(segment)
    }

    func billingStopTimer(id: String) async -> Result<BillingSegmentDTO, BillingRefusal> {
        guard reachable else { return .failure(.unreachable) }
        guard let old = segments.first(where: { $0.id == id }) else {
            return .failure(BillingRefusal(message: BillingRefusalText.unknownTimer))
        }
        guard old.isRunning else { return .failure(BillingRefusal(message: BillingRefusalText.timerNotRunning)) }
        let stopped = Self.segment(old, endedAt: "2026-09-22T11:00:00Z", seconds: 3600)
        upsert(stopped, into: &segments)
        return .success(stopped)
    }

    func billingAssignSegments(ids: [String], projectId: String?) async -> Int? {
        guard reachable else { return nil }
        var moved = 0
        // The daemon's UPDATE matches only `entry_id IS NULL`: time already
        // on a billable stays where it is and is not counted.
        segments = segments.map { segment in
            guard ids.contains(segment.id), segment.entryId == nil else { return segment }
            moved += 1
            return Self.segment(segment, projectId: .some(projectId))
        }
        return moved
    }

    func billingPromoteSegments(ids: [String]) async -> Int? {
        guard reachable else { return nil }
        lastPromotedIDs = ids
        return segments.filter { ids.contains($0.id) && !$0.isRunning && $0.entryId == nil }.count
    }

    /// The daemon's own list: every loose segment from the root, whatever
    /// page of recent runs the app holds.
    func billingAssignRepository(projectRoot: String, projectId: String) async -> Int? {
        guard reachable else { return nil }
        let ids = segments
            .filter { $0.projectRoot == projectRoot && $0.projectId == nil && $0.entryId == nil }
            .map(\.id)
        let moved = await billingAssignSegments(ids: ids, projectId: projectId)
        _ = await billingPromoteSegments(ids: ids)
        return moved
    }

    func billingBackfill(since: String) async -> Int? {
        guard reachable else { return nil }
        lastBackfillSince = since
        return 3
    }

    func billingOverview() async -> BillingOverviewDTO? {
        reachable && !overviewFails ? overviewValue : nil
    }

    // MARK: Copies the app's `replacing` helpers deliberately don't offer

    private static func segment(
        _ seg: BillingSegmentDTO, projectId: String?? = nil, endedAt: String? = nil, seconds: Int? = nil
    ) -> BillingSegmentDTO {
        BillingSegmentDTO(id: seg.id, sessionId: seg.sessionId, origin: seg.origin,
                          projectId: projectId ?? seg.projectId, repoId: seg.repoId,
                          projectRoot: seg.projectRoot, branch: seg.branch, startedAt: seg.startedAt,
                          endedAt: endedAt ?? seg.endedAt, tz: seg.tz, seconds: seconds ?? seg.seconds,
                          note: seg.note, entryId: seg.entryId, flags: seg.flags)
    }

    private static func entry(
        _ ent: BillingEntryDTO, id: String? = nil, status: BillingStatus? = nil
    ) -> BillingEntryDTO {
        let status = status?.rawValue ?? ent.status
        return BillingEntryDTO(
            id: id ?? ent.id, projectId: ent.projectId, clientId: ent.clientId, day: ent.day,
            groupKey: ent.groupKey, startedAt: ent.startedAt, endedAt: ent.endedAt,
            rawSeconds: ent.rawSeconds, billedSeconds: ent.billedSeconds, rateCents: ent.rateCents,
            currency: ent.currency, amountCents: ent.amountCents, roundingMinutes: ent.roundingMinutes,
            roundingMode: ent.roundingMode, status: status, description: ent.description,
            origin: ent.origin, locked: BillingStatus(rawValue: status)?.locksTheEntry ?? false,
            supplementsEntryId: ent.supplementsEntryId
        )
    }
}

/// A one-shot rendezvous: `pass()` parks until ``open()``, and ``reached()``
/// waits until something has parked.
final class FakeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var parked: CheckedContinuation<Void, Never>?
    private var watcher: CheckedContinuation<Void, Never>?
    private var isOpen = false
    private var hasArrived = false

    func pass() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isOpen {
                lock.unlock()
                continuation.resume()
                return
            }
            parked = continuation
            hasArrived = true
            let watcher = self.watcher
            self.watcher = nil
            lock.unlock()
            watcher?.resume()
        }
    }

    func reached() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if hasArrived {
                lock.unlock()
                continuation.resume()
                return
            }
            watcher = continuation
            lock.unlock()
        }
    }

    func open() {
        lock.lock()
        isOpen = true
        let parked = self.parked
        self.parked = nil
        lock.unlock()
        parked?.resume()
    }
}
