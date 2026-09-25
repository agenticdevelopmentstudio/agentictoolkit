import Foundation

/// One session, reduced to what billing derivation needs.
public struct BillingSessionRow: Sendable, Equatable {
    public let sessionId: String
    public let projectRoot: String
    public let branch: String
    public let startedAt: String
    /// The watermark value to stamp once this row's activity has been consumed.
    public let lastActivityAt: String
    public let isActive: Bool

    public init(
        sessionId: String, projectRoot: String, branch: String,
        startedAt: String, lastActivityAt: String, isActive: Bool
    ) {
        self.sessionId = sessionId
        self.projectRoot = projectRoot
        self.branch = branch
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.isActive = isActive
    }
}

/// What a derived run is attributed to. Resolved once per session, then applied
/// to every run that session produced.
public struct BillingSegmentContext: Sendable, Equatable {
    public let projectId: String?
    public let repoId: String?
    public let projectRoot: String
    public let branch: String
    // swiftlint:disable:next identifier_name
    public let tz: String
    /// False when the claiming project or repo has Track Time off. Time first
    /// derived then is flagged `untracked` and never rolled, even after
    /// tracking is turned back on: "track the time, create no entry".
    public let tracked: Bool

    // swiftlint:disable:next identifier_name
    public init(projectId: String?, repoId: String?, projectRoot: String, branch: String, tz: String, tracked: Bool) {
        self.projectId = projectId
        self.repoId = repoId
        self.projectRoot = projectRoot
        self.branch = branch
        self.tz = tz
        self.tracked = tracked
    }
}

/// Which existing row an `upsertBillingEntry` may overwrite. A new id always
/// inserts; the guard decides only the update of an existing row, and the
/// store checks it against the row as it is *now*, so a status change or a
/// hand edit committed after the caller read the row is never undone.
public enum BillingEntryOverwrite: Sendable, Equatable {
    /// Any row — `setStatus`, which is the one path allowed to unlock.
    case any
    /// Only an unlocked row — a hand edit.
    case unlocked
    /// Only a row the rollup still owns: unlocked and `origin = 'auto'`.
    case rollupOwned
}

/// An entry together with whether its description was hand edited, which is
/// not on the wire DTO but decides whether the rollup may rewrite it.
public struct StoredBillingEntry: Sendable, Equatable {
    public let entry: BillingEntryDTO
    public let descriptionEdited: Bool

    public init(entry: BillingEntryDTO, descriptionEdited: Bool) {
        self.entry = entry
        self.descriptionEdited = descriptionEdited
    }
}

/// The storage billing's logic runs against.
///
/// Every rule — who claims a repo, how runs roll into entries, what a locked
/// entry refuses — lives beside this protocol in the shared tier; only the
/// storage is the host's. A host conforms its database (Stenographer's
/// SQLite `DatabaseManager`) and hands it to ``BillingStore``,
/// ``BillingRollup``, ``BillingTimer`` and ``BillingPrefs``.
///
/// Requirements carry no default arguments (a protocol cannot), so the shared
/// logic always passes every argument explicitly.
public protocol BillingPersistence {

    // MARK: Settings and transactions

    /// The keys this host stores its billing knobs under.
    var billingSettingsKeys: BillingSettingsKeys { get }
    func setting(for key: String) throws -> String?
    func setSetting(_ key: String, _ value: String) throws
    /// Runs `body` as one write transaction: all of it lands, or none.
    func transaction(_ body: () throws -> Void) throws
    /// Forgets every derived session's watermark, so all derived time is
    /// re-split on the next pass. Returns how many sessions were reset.
    @discardableResult
    func resetBillingDerivationOfDerivedSessions() throws -> Int

    // MARK: Clients

    func billingClients(includeArchived: Bool) throws -> [BillingClientDTO]
    func billingClient(id: String) throws -> BillingClientDTO?
    func upsertBillingClient(_ dto: BillingClientDTO) throws
    func deleteBillingClient(id: String) throws
    func billingLockedEntryCount(clientId: String) throws -> Int

    // MARK: Projects

    func billingProjects(includeArchived: Bool) throws -> [BillingProjectDTO]
    func billingProject(id: String) throws -> BillingProjectDTO?
    func upsertBillingProject(_ dto: BillingProjectDTO) throws
    func billingEntryCount(projectId: String) throws -> Int
    func deleteBillingProject(id: String) throws

    // MARK: Repos

    func billingRepos(projectId: String?) throws -> [BillingRepoDTO]
    func billingRepo(id: String) throws -> BillingRepoDTO?
    func upsertBillingRepo(_ dto: BillingRepoDTO) throws
    func deleteBillingRepo(id: String) throws

    // MARK: Segments

    func billingSegment(id: String) throws -> BillingSegmentDTO?
    /// Every open segment; `origin` narrows to one origin, nil takes all.
    func runningBillingSegments(origin: String?) throws -> [BillingSegmentDTO]
    @discardableResult
    func closeBillingSegment(id: String, endedAt: String, seconds: Int) throws -> Bool
    @discardableResult
    func addBillingSegmentFlag(id: String, flag: String) throws -> Bool
    func upsertBillingSegment(_ dto: BillingSegmentDTO) throws

    // MARK: Derivation

    func billingHistoryStart(sessionId: String, sessionStartedAt: String) throws -> String?
    /// The session's activity instants as epoch seconds, read after the
    /// `afterId` cursor, and the cursor to resume from.
    func billingActivitySeconds(sessionId: String, afterId: Int64) throws -> (seconds: [Int], lastId: Int64)
    func markBillingDerived(sessionId: String, at value: String) throws
    @discardableResult
    func replaceDerivedSegments(
        sessionId: String, runs: [BillingRun], context: BillingSegmentContext, historyStartsAt: String?
    ) throws -> Int

    // MARK: Entries

    func billingEntries(projectId: String?, status: String?, since: String) throws -> [BillingEntryDTO]
    func billingEntry(id: String) throws -> BillingEntryDTO?
    /// Returns whether a row was written — false only when `overwrite`
    /// refused an existing row.
    @discardableResult
    func upsertBillingEntry(_ dto: BillingEntryDTO, overwrite: BillingEntryOverwrite) throws -> Bool
    func deleteBillingEntry(id: String) throws
    func billingFrozenSupplementCount(of entryId: String) throws -> Int
    func billingStoredEntry(id: String) throws -> StoredBillingEntry?
    func billingEntryForSlot(projectId: String, day: String, groupKey: String) throws -> StoredBillingEntry?
    func billingOpenSupplement(of entryId: String) throws -> StoredBillingEntry?
    func billingRecomputableEntryIds() throws -> [String]
    @discardableResult
    func deleteEmptyBillingEntry(id: String) throws -> Bool
    func markBillingEntryDescriptionEdited(id: String) throws
    @discardableResult
    func setBillingEntryDescription(id: String, description: String, at now: String) throws -> Bool
    /// Closed, unrolled segments of billing-enabled projects; `ids` narrows to
    /// those segments, nil takes all.
    func billingRollupCandidates(ids: [String]?) throws -> [BillingSegmentDTO]
    func billingSegmentsForEntry(id: String) throws -> [BillingSegmentDTO]
    func attachSegments(ids: [String], toEntry entryId: String) throws
    func appendBillingAudit(entryId: String, field: String, oldValue: String, newValue: String, source: String) throws
    func billingSessionTitles(sessionIds: [String]) throws -> [String]

    // MARK: Assignment and overview

    func unassignedSegmentIDs(projectRoot: String) throws -> [String]
    func assignSegments(ids: [String], toProject projectId: String?) throws -> Int
    func billingOverviewBuckets() throws -> [(currency: String, buckets: [String: BillingOverviewBucketDTO])]
}
