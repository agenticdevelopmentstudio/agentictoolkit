import Foundation

/// Business rules for the billing tables. Storage is the host's
/// ``BillingPersistence``; this decides what is allowed and what the values
/// should be.
public enum BillingStore {

    /// Refusals are specific enough to show the user verbatim — these surface
    /// in a sheet, not a log.
    public enum BillingError: Error, LocalizedError {
        case missingName
        case invalidRounding(Int)
        case unknownProject(String)
        case missingRepoRoot
        case repoAlreadyClaimed(root: String, branch: String)
        case projectHasEntries(id: String, count: Int)
        case invalidRate(Int)
        case clientHasBilledEntries(id: String, count: Int)
        /// Another record of the same kind already has this name. Two clients
        /// (or two projects) that read alike are indistinguishable in every
        /// menu and picker that lists them, so the second is refused.
        case duplicateName(String)

        public var errorDescription: String? {
            switch self {
            case .missingName:
                return BillingRefusalText.missingName
            case .invalidRounding(let minutes):
                guard minutes >= BillingLimits.roundingMinutes.lowerBound else {
                    return "Rounding must be at least one minute (got \(minutes))."
                }
                return "Rounding can be at most \(BillingLimits.roundingMinutes.upperBound) minutes (got \(minutes))."
            case .invalidRate(let cents):
                let most = BillingLimits.defaultRateCents.upperBound / 100
                return "A rate must be between 0 and \(most) per hour (got \(cents) cents)."
            case .unknownProject(let id):
                return "No project with id \(id)."
            case .missingRepoRoot:
                return BillingRefusalText.missingRepoRoot
            case .repoAlreadyClaimed(let root, let branch):
                return BillingRefusalText.repoAlreadyClaimed(root: root, branch: branch)
            case .projectHasEntries(let id, let count):
                let entries = count == 1 ? "1 billing entry" : "\(count) billing entries"
                return "Project \(id) has \(entries). Archive it instead of deleting it."
            case .clientHasBilledEntries(_, let count):
                let entries = count == 1 ? "1 billed or paid entry" : "\(count) billed or paid entries"
                return "This client has \(entries). Archive it instead of deleting it."
            case .duplicateName(let name):
                return "Another one is already called “\(name)”. Choose a different name."
            }
        }
    }

    // MARK: - Clients

    /// Insert when `id` is empty, update otherwise. Returns what was stored, so
    /// the caller — and the XPC reply — always sees the assigned id and stamps.
    @discardableResult
    public static func saveClient(
        _ dto: BillingClientDTO, database: any BillingPersistence
    ) throws -> BillingClientDTO {
        let name = dto.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw BillingError.missingName }
        let others = try database.billingClients(includeArchived: true).filter { $0.id != dto.id }
        guard !UniqueName.collides(name, with: others.map(\.name)) else { throw BillingError.duplicateName(name) }

        let now = UTCTimestamp.now()
        let id = dto.id.isEmpty ? UUID().uuidString : dto.id
        let existing = dto.id.isEmpty ? nil : try database.billingClient(id: dto.id)
        let stored = BillingClientDTO(
            id: id, name: name, contactName: dto.contactName, email: dto.email,
            phone: dto.phone, url: dto.url, notes: dto.notes, currency: dto.currency,
            archived: dto.archived,
            createdAt: existing?.createdAt ?? now, updatedAt: now
        )
        try database.upsertBillingClient(stored)
        return stored
    }

    /// A billed or paid entry records who it was billed to, and deleting the
    /// client would erase that from history. Refused, the way a project with
    /// entries is: archiving is the way to stop using a client. The check and
    /// the delete share one write transaction, like `deleteProject`.
    public static func deleteClient(id: String, database: any BillingPersistence) throws {
        try database.transaction {
            let billed = try database.billingLockedEntryCount(clientId: id)
            guard billed == 0 else { throw BillingError.clientHasBilledEntries(id: id, count: billed) }
            try database.deleteBillingClient(id: id)
        }
    }

    // MARK: - Projects

    @discardableResult
    public static func saveProject(
        _ dto: BillingProjectDTO, database: any BillingPersistence
    ) throws -> BillingProjectDTO {
        let name = dto.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw BillingError.missingName }
        let others = try database.billingProjects(includeArchived: true).filter { $0.id != dto.id }
        guard !UniqueName.collides(name, with: others.map(\.name)) else { throw BillingError.duplicateName(name) }
        // A zero or negative interval would make `BillingRounding` divide by
        // zero-length increments, and an absurd interval or rate overflows the
        // integer money arithmetic — a trap that repeats on every pass, since
        // the segment that caused it is never rolled. The same ranges the
        // global settings are clamped to; refused at the edge rather than
        // clamped, so the user learns the value didn't take.
        guard BillingLimits.roundingMinutes.contains(dto.roundingMinutes) else {
            throw BillingError.invalidRounding(dto.roundingMinutes)
        }
        try checkRate(dto.defaultRateCents)

        let now = UTCTimestamp.now()
        let id = dto.id.isEmpty ? UUID().uuidString : dto.id
        let existing = dto.id.isEmpty ? nil : try database.billingProject(id: dto.id)
        // A client id that no longer resolves becomes nil rather than dangling.
        let clientId = try dto.clientId.flatMap {
            try database.billingClient(id: $0) == nil ? nil : $0
        }
        let stored = BillingProjectDTO(
            id: id, clientId: clientId, name: name, notes: dto.notes,
            defaultRateCents: dto.defaultRateCents,
            roundingMinutes: dto.roundingMinutes, roundingMode: dto.roundingMode,
            billingEnabled: dto.billingEnabled, archived: dto.archived,
            createdAt: existing?.createdAt ?? now, updatedAt: now
        )
        try database.upsertBillingProject(stored)
        return stored
    }

    /// `billing_entry.project_id` is `NOT NULL`, so deleting a project out from
    /// under any entry — whatever its status — would strand a row the schema
    /// can't represent as detached. Refuse instead: archiving is the operation
    /// that means "stop billing this" without destroying its history.
    ///
    /// The count and the delete share one write transaction: a rollup that
    /// writes the project's first entry in between would otherwise leave an
    /// entry pointing at a project that no longer exists.
    public static func deleteProject(id: String, database: any BillingPersistence) throws {
        try database.transaction {
            let entryCount = try database.billingEntryCount(projectId: id)
            guard entryCount == 0 else {
                throw BillingError.projectHasEntries(id: id, count: entryCount)
            }
            try database.deleteBillingProject(id: id)
        }
    }

    /// A project or repo rate: absent, or inside `BillingLimits.defaultRateCents`.
    private static func checkRate(_ cents: Int?) throws {
        guard let cents else { return }
        guard BillingLimits.defaultRateCents.contains(cents) else { throw BillingError.invalidRate(cents) }
    }

    // MARK: - Repos

    @discardableResult
    public static func saveRepo(
        _ dto: BillingRepoDTO, database: any BillingPersistence
    ) throws -> BillingRepoDTO {
        let root = dto.projectRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty else { throw BillingError.missingRepoRoot }
        try checkRate(dto.rateCents)
        guard try database.billingProject(id: dto.projectId) != nil else {
            throw BillingError.unknownProject(dto.projectId)
        }

        // `UNIQUE(project_root, branch)` would catch this too, but as an opaque
        // constraint failure. Checking here turns it into a sentence naming the
        // path — fail-fast with an error the user can act on.
        let branch = dto.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        let clash = try database.billingRepos(projectId: nil).first {
            $0.projectRoot == root && $0.branch == branch && $0.id != dto.id
        }
        if clash != nil { throw BillingError.repoAlreadyClaimed(root: root, branch: branch) }

        let now = UTCTimestamp.now()
        let id = dto.id.isEmpty ? UUID().uuidString : dto.id
        let existing = dto.id.isEmpty ? nil : try database.billingRepo(id: dto.id)
        let stored = BillingRepoDTO(
            id: id, projectId: dto.projectId, projectRoot: root, branch: branch,
            rateCents: dto.rateCents, billingEnabled: dto.billingEnabled,
            createdAt: existing?.createdAt ?? now, updatedAt: now
        )
        try database.upsertBillingRepo(stored)
        return stored
    }

    public static func deleteRepo(id: String, database: any BillingPersistence) throws {
        try database.deleteBillingRepo(id: id)
    }

    // MARK: - Rates

    /// Which repo row and project claim this work, over the live tables (the
    /// rate itself is resolved per segment by the rollup). Archived projects
    /// are included: work already mapped to one must still resolve, or ending
    /// an engagement would silently drop its unbilled history.
    public static func resolveRate(
        projectRoot: String,
        branch: String,
        database: any BillingPersistence
    ) throws -> BillingRateResolution {
        try claim(projectRoot: projectRoot, branch: branch, database: database).resolution
    }

    /// The claim plus whether it is tracked: both the claiming repo row and
    /// its project must have Track Time on. Unassigned work has no switch.
    private static func claim(
        projectRoot: String, branch: String, database: any BillingPersistence
    ) throws -> (resolution: BillingRateResolution, tracked: Bool) {
        let repos = try database.billingRepos(projectId: nil)
        let projects = try database.billingProjects(includeArchived: true)
        let resolution = BillingRate.resolve(
            projectRoot: projectRoot, branch: branch, repos: repos, projects: projects
        )
        let repoOn = resolution.repoId.map { id in repos.first { $0.id == id }?.billingEnabled ?? true } ?? true
        let projectOn = resolution.projectId.map { id in
            projects.first { $0.id == id }?.billingEnabled ?? true
        } ?? true
        return (resolution, repoOn && projectOn)
    }

    // MARK: - Derivation

    /// Derives one session's runs and persists them. The unit of work is a
    /// session because that is the unit the watermark is stamped on: a failure
    /// mid-batch leaves every session either fully derived or untouched.
    ///
    /// Returns how many segments were written.
    @discardableResult
    public static func deriveSegments(
        for session: BillingSessionRow,
        cutoffSeconds: Int,
        trackUnassigned: Bool = true,
        now: String,
        database: any BillingPersistence,
        activity: BillingActivityCache = BillingActivityCache()
    ) throws -> Int {
        // The claim can come back unassigned (repoId and projectId nil). The
        // segment is still written: unmapped time is tracked, never discarded,
        // so it can be assigned to a project later without re-deriving history.
        let (resolution, tracked) = try claim(
            projectRoot: session.projectRoot,
            branch: session.branch,
            database: database
        )
        // The opt-out: with unassigned tracking off, work in a repo no project
        // claims leaves no new trace. A run tracked before the opt-out is still
        // closed — the open-segment clause re-selects this session every pass
        // until it is, so leaving it open meant a run shown Running forever.
        // The watermark still advances, so the session is not reconsidered on
        // every pass forever.
        guard resolution.projectId != nil || trackUnassigned else {
            try closeOpenRuns(of: session, cutoffSeconds: cutoffSeconds, now: now,
                              database: database, activity: activity)
            try database.markBillingDerived(sessionId: session.sessionId, at: session.lastActivityAt)
            return 0
        }

        // Only the events since the last pass are read when the cache is the
        // task's long-lived one; a fresh cache reads the whole history.
        let stamps = try activity.activitySeconds(sessionId: session.sessionId, database: database)
        let runs = BillingDerivation.runs(
            activitySeconds: stamps,
            sessionStartedAt: session.startedAt,
            sessionIsActive: session.isActive,
            now: now,
            cutoffSeconds: cutoffSeconds
        )
        let context = BillingSegmentContext(
            projectId: resolution.projectId,
            repoId: resolution.repoId,
            projectRoot: session.projectRoot,
            branch: session.branch,
            // The zone is captured at derivation, not read back at display
            // time: a segment worked in Lisbon stays a Lisbon segment after
            // the laptop lands somewhere else, which is what makes local-day
            // bucketing stable. This is only the zone for *new* time —
            // `replaceDerivedSegments` keeps the zone a run was first stamped
            // with, and `BillingTask` resets the cached system zone at the
            // start of every pass so "current" means current.
            tz: TimeZone.current.identifier,
            tracked: tracked
        )

        // Retention may have trimmed the session's early events; what was
        // derived from them is kept rather than re-derived from nothing.
        let historyStartsAt = try database.billingHistoryStart(
            sessionId: session.sessionId, sessionStartedAt: session.startedAt
        )
        let written = try database.replaceDerivedSegments(
            sessionId: session.sessionId, runs: runs, context: context, historyStartsAt: historyStartsAt
        )
        // Stamped with the value read at selection time, not "now": anything
        // that arrived during derivation leaves the watermark stale and is
        // picked up next pass rather than skipped.
        try database.markBillingDerived(sessionId: session.sessionId, at: session.lastActivityAt)
        return written
    }

    /// Closes this session's open derived runs without writing anything new:
    /// each ends where its run ends once the session is treated as finished,
    /// or — when no run covers it any more — at its own start, with no time.
    private static func closeOpenRuns(
        of session: BillingSessionRow,
        cutoffSeconds: Int,
        now: String,
        database: any BillingPersistence,
        activity: BillingActivityCache
    ) throws {
        let open = try database.runningBillingSegments(origin: BillingSegmentDTO.autoOrigin)
            .filter { $0.sessionId == session.sessionId }
        guard !open.isEmpty else { return }
        let runs = BillingDerivation.runs(
            activitySeconds: try activity.activitySeconds(sessionId: session.sessionId, database: database),
            sessionStartedAt: session.startedAt,
            sessionIsActive: false,
            now: now,
            cutoffSeconds: cutoffSeconds
        )
        for segment in open {
            let run = runs.first { $0.startedAt == segment.startedAt }
                ?? runs.first { $0.startedAt <= segment.startedAt && segment.startedAt <= $0.endedAt }
            let end = run.flatMap { $0.isOpen ? nil : $0.endedAt } ?? segment.startedAt
            try database.closeBillingSegment(
                id: segment.id, endedAt: end,
                seconds: UTCTimestamp.seconds(from: segment.startedAt, to: end)
            )
        }
    }
}
