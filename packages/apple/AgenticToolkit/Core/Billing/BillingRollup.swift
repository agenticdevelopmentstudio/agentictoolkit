import Foundation

/// What one entry covers. Switchable at any time: it only decides how the
/// *next* pass groups, so nothing already written changes meaning.
public enum BillingGranularity: String, Sendable {
    case day
    case run
}

public struct BillingRollupOptions: Sendable, Equatable {
    public let granularity: BillingGranularity
    /// Used only when neither the repo nor the project names a rate.
    public let defaultRateCents: Int
    public let currency: String

    public init(granularity: BillingGranularity = .day, defaultRateCents: Int = 0, currency: String = "USD") {
        self.granularity = granularity
        self.defaultRateCents = defaultRateCents
        self.currency = currency
    }
}

/// Turns closed, assigned segments into billing entries.
///
/// The whole type rests on one rule: an entry at `unbilled` is a *view* of its
/// segments and may be recomputed on every pass; an entry past `unbilled` is
/// *history* and is never recomputed, never edited, and never silently grown.
/// Late work on a frozen day becomes a supplemental entry you can see.
public enum BillingRollup {

    public enum RollupError: LocalizedError {
        case unknownEntry(String)
        case entryIsLocked(String)
        case statusChangeNotAllowed(current: String, requested: String)
        case entryChanged(String)
        case entryHasFrozenSupplements(id: String, count: Int)

        public var errorDescription: String? {
            switch self {
            case .unknownEntry:
                return BillingRefusalText.unknownEntry
            case .entryIsLocked:
                return BillingRefusalText.entryIsLocked
            case .statusChangeNotAllowed(let current, let requested):
                return BillingRefusalText.statusChangeNotAllowed(current: current, requested: requested)
            case .entryChanged:
                return "This entry changed since you opened it. Review the new figures and save again."
            case .entryHasFrozenSupplements(_, let count):
                let supplements = count == 1 ? "a supplement that is" : "\(count) supplements that are"
                return "This entry has \(supplements) billed, paid or edited by hand. Delete those first."
            }
        }
    }

    // MARK: - The pass

    /// Rolls every eligible segment, then recomputes the entries the rollup
    /// still owns — every one, or only `recomputing` when the caller knows
    /// which entries its derivation can have touched (`BillingTask`). Returns
    /// the number of entries created, recomputed or removed — zero is the
    /// normal steady state.
    @discardableResult
    public static func run(
        options: BillingRollupOptions, database: any BillingPersistence, recomputing: Set<String>? = nil
    ) throws -> Int {
        let rolled = try roll(try database.billingRollupCandidates(ids: nil), options: options, database: database)
        return rolled + (try recomputeOwnedEntries(database: database, only: recomputing))
    }

    /// The same pass restricted to named segments — what the Billing Activity
    /// window's "Create billable" button runs after assigning an orphan.
    @discardableResult
    public static func promoteSegments(
        ids: [String], options: BillingRollupOptions, database: any BillingPersistence
    ) throws -> Int {
        guard !ids.isEmpty else { return 0 }
        return try roll(try database.billingRollupCandidates(ids: ids), options: options, database: database)
    }

    private struct Slot: Hashable {
        let projectId: String
        let day: String
        let groupKey: String
        /// The rate this slot's time bills at, resolved per segment. Part of
        /// the slot (and, at day granularity, of `groupKey`), so one entry
        /// never mixes two rates.
        let rateCents: Int
    }

    /// A derived run's identity is `(session_id, started_at)` — the same pair
    /// `idx_billing_segment_auto_identity` enforces, and what survives
    /// re-derivation. A manual timer is never re-derived, so its id is stable
    /// and, unlike its start, cannot collide with another timer's.
    public static func runGroupKey(for segment: BillingSegmentDTO) -> String {
        segment.origin == BillingSegmentDTO.autoOrigin ? "\(segment.sessionId)|\(segment.startedAt)" : segment.id
    }

    private static func roll(
        _ candidates: [BillingSegmentDTO], options: BillingRollupOptions, database: any BillingPersistence
    ) throws -> Int {
        guard !candidates.isEmpty else { return 0 }

        let repos = try database.billingRepos(projectId: nil)
        var projects: [String: BillingProjectDTO?] = [:]
        var grouped: [Slot: [BillingSegmentDTO]] = [:]
        var order: [Slot] = []
        for segment in candidates {
            guard let projectId = segment.projectId, !projectId.isEmpty else { continue }
            if projects[projectId] == nil { projects[projectId] = .some(try database.billingProject(id: projectId)) }
            let project = projects[projectId] ?? nil
            let rate = BillingRate.rateCents(
                repo: segment.repoId.flatMap { id in repos.first { $0.id == id } },
                repos: repos,
                project: project,
                globalDefaultRateCents: options.defaultRateCents
            )
            let groupKey: String
            switch options.granularity {
            case .run:
                // At run granularity the run *is* the group, which is why
                // `group_key` exists: two runs on one day would otherwise
                // collide on the project-day unique index. Keyed on the run's
                // stable identity, never a row id a rewrite could replace.
                groupKey = runGroupKey(for: segment)
            case .day:
                // One entry per project, day **and rate**, always keyed by the
                // rate itself. A key meaning "the project's *current* default"
                // made a default-rate change route new time into the entry
                // holding time at the old rate, repricing all of it.
                groupKey = dayGroupKey(rateCents: rate)
            }
            let slot = Slot(
                projectId: projectId,
                day: BillingClock.localDay(utc: segment.startedAt, tz: segment.tz),
                groupKey: groupKey,
                rateCents: rate
            )
            if grouped[slot] == nil { order.append(slot) }
            grouped[slot, default: []].append(segment)
        }

        var touched = 0
        for slot in order
        where try apply(grouped[slot] ?? [], to: slot, project: projects[slot.projectId] ?? nil,
                        options: options, database: database) {
            touched += 1
        }
        return touched
    }

    /// The day-granularity key for time billed at `rateCents`.
    public static func dayGroupKey(rateCents: Int) -> String { "rate:\(rateCents)" }

    /// Routes one group's segments to the entry that should own them.
    /// Returns whether an entry was written.
    ///
    /// Everything — re-reading the segments, finding the owner, summing what
    /// it already holds, writing — happens in one write transaction. Read on a
    /// snapshot, a Mark Billed committed in between was undone by the write,
    /// and a promote racing the task pass double-counted a segment or collided
    /// on the slot's unique index.
    private static func apply(
        _ segments: [BillingSegmentDTO],
        to slot: Slot,
        project: BillingProjectDTO?,
        options: BillingRollupOptions,
        database: any BillingPersistence
    ) throws -> Bool {
        var wrote = false
        try database.transaction {
            // Still unattached, still billable, still where they were grouped:
            // another writer may have rolled, re-derived or reassigned them,
            // or deleted the project, since the candidate read.
            let grouped = Dictionary(segments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let fresh = try database.billingRollupCandidates(ids: segments.map(\.id)).filter { segment in
                guard let original = grouped[segment.id] else { return false }
                return segment.projectId == slot.projectId && segment.repoId == original.repoId
                    && segment.startedAt == original.startedAt && segment.tz == original.tz
            }
            guard !fresh.isEmpty else { return }

            let owner = try slotOwner(slot, database: database)

            // A frozen owner — billed or paid, or with figures the user typed —
            // never grows. Its later time goes to a supplement you can see.
            let target: StoredBillingEntry?
            let supplements: String?
            if let owner, owner.entry.locked || owner.entry.origin == "user" {
                target = try database.billingOpenSupplement(of: owner.entry.id)
                supplements = owner.entry.id
            } else {
                target = owner
                supplements = owner?.entry.supplementsEntryId
            }

            let freshIds = Set(fresh.map(\.id))
            let previouslyAttached = try target.map {
                try database.billingSegmentsForEntry(id: $0.entry.id).filter { !freshIds.contains($0.id) }
            } ?? []
            let entry = try compose(
                slot: slot,
                segments: previouslyAttached + fresh,
                previous: target,
                supplements: supplements,
                project: project,
                options: options,
                database: database
            )

            // The entry row goes in first: a segment may only point at an
            // entry that exists. The guard is the backstop — a row that is no
            // longer the rollup's is never overwritten.
            guard try database.upsertBillingEntry(entry, overwrite: .rollupOwned) else { return }
            try database.attachSegments(ids: fresh.map(\.id), toEntry: entry.id)
            wrote = true
        }
        return wrote
    }

    /// The entry owning `slot`. A day entry written before day keys carried
    /// the rate has the plain `''` key; it still owns time at its own
    /// snapshotted rate, and is re-keyed when the rollup next writes it.
    private static func slotOwner(
        _ slot: Slot, database: any BillingPersistence
    ) throws -> StoredBillingEntry? {
        if let owner = try database.billingEntryForSlot(
            projectId: slot.projectId, day: slot.day, groupKey: slot.groupKey
        ) {
            return owner
        }
        guard slot.groupKey == dayGroupKey(rateCents: slot.rateCents),
              let legacy = try database.billingEntryForSlot(projectId: slot.projectId, day: slot.day, groupKey: ""),
              legacy.entry.rateCents == slot.rateCents else { return nil }
        return legacy
    }

    /// Builds the entry for one group. Everything rate-shaped is *snapshotted*
    /// the first time the entry is written and never read through a reference
    /// again — that is what lets a rate change in March leave January's
    /// numbers alone, even when January's time is re-derived and re-rolled.
    private static func compose(
        slot: Slot,
        segments: [BillingSegmentDTO],
        previous: StoredBillingEntry?,
        supplements: String?,
        project: BillingProjectDTO?,
        options: BillingRollupOptions,
        database: any BillingPersistence
    ) throws -> BillingEntryDTO {
        let old = previous?.entry
        let roundingMinutes = old?.roundingMinutes ?? project?.roundingMinutes ?? 15
        let roundingMode = old?.roundingMode ?? project?.roundingMode ?? "up"
        let rate = old?.rateCents ?? slot.rateCents
        let currency = try old?.currency ?? currencyCode(for: project, options: options, database: database)
        let clientId = old.map(\.clientId) ?? project?.clientId
        let computed = figures(
            of: segments, roundingMinutes: roundingMinutes, roundingMode: roundingMode, rateCents: rate
        )
        let now = UTCTimestamp.now()

        return BillingEntryDTO(
            id: old?.id ?? UUID().uuidString,
            projectId: slot.projectId,
            clientId: clientId,
            day: slot.day,
            groupKey: slot.groupKey,
            startedAt: computed.startedAt,
            endedAt: computed.endedAt,
            rawSeconds: computed.raw,
            billedSeconds: computed.billed,
            rateCents: rate,
            currency: currency,
            amountCents: computed.amount,
            roundingMinutes: roundingMinutes,
            roundingMode: roundingMode,
            status: old?.status ?? BillingStatus.unbilled.rawValue,
            description: previous?.descriptionEdited == true
                ? old?.description ?? ""
                : try describe(segments: segments, database: database),
            origin: "auto",
            locked: false,
            supplementsEntryId: supplements,
            createdAt: old?.createdAt ?? now,
            updatedAt: now
        )
    }

    /// An entry's figures over its segments — the one formula both the roll
    /// and the recompute use.
    private struct Figures: Equatable {
        let startedAt: String
        let endedAt: String
        let raw: Int
        let billed: Int
        let amount: Int
    }

    private static func figures(
        of segments: [BillingSegmentDTO], roundingMinutes: Int, roundingMode: String, rateCents: Int
    ) -> Figures {
        let raw = segments.reduce(0) { $0 + $1.seconds }
        // Once, over the total. Rounding each segment first is how five
        // five-minute checks become 75 billed minutes.
        let billed = BillingRounding.billedSeconds(
            rawSeconds: raw, roundingMinutes: roundingMinutes, mode: roundingMode
        )
        return Figures(
            startedAt: segments.map(\.startedAt).min() ?? "",
            // The latest *end*, not the end of the segment that starts last:
            // parallel sessions overlap, and a short one starting late would
            // otherwise cut the entry's end hours early.
            endedAt: segments.map(\.endedAt).max() ?? "",
            raw: raw,
            billed: billed,
            amount: amountCents(billedSeconds: billed, rateCents: rateCents)
        )
    }

    /// Currency lives on the client — a client is billed in one currency and
    /// every project under them inherits it. No client means the global
    /// setting.
    private static func currencyCode(
        for project: BillingProjectDTO?,
        options: BillingRollupOptions,
        database: any BillingPersistence
    ) throws -> String {
        guard let clientId = project?.clientId, !clientId.isEmpty,
              let client = try database.billingClient(id: clientId),
              !client.currency.isEmpty else {
            return options.currency
        }
        return client.currency
    }

    /// What makes an entry defensible three months later: the titles of the
    /// sessions the time came from, the notes typed on its timers, and the
    /// branches they ran on. A generic time tracker cannot write this line,
    /// because it never saw the work.
    private static func describe(
        segments: [BillingSegmentDTO], database: any BillingPersistence
    ) throws -> String {
        var sessionIds: [String] = []
        var notes: [String] = []
        var branches: [String] = []
        for segment in segments {
            if !segment.sessionId.isEmpty, !sessionIds.contains(segment.sessionId) {
                sessionIds.append(segment.sessionId)
            }
            let note = segment.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty, !notes.contains(note) { notes.append(note) }
            if !segment.branch.isEmpty, !branches.contains(segment.branch) {
                branches.append(segment.branch)
            }
        }

        var parts = try database.billingSessionTitles(sessionIds: sessionIds)
        parts.append(contentsOf: notes)
        if !branches.isEmpty { parts.append("on \(branches.joined(separator: ", "))") }
        return parts.joined(separator: "; ")
    }

    // MARK: - Recompute

    /// Brings every entry the rollup owns (unbilled, not hand-edited) back in
    /// line with the segments still attached to it, and removes one left with
    /// none. Returns how many changed.
    ///
    /// The roll only ever *adds* to entries. Re-derivation detaches segments
    /// (a cutoff change reshapes runs, a repo is re-mapped to another project,
    /// a run reopens), and without this pass the entry kept its old figures —
    /// while the same time rolled again into its new slot. That was double
    /// billing. The entry's own snapshotted rate and rounding are used, never
    /// the live settings: recomputing is about *which time*, not *what price*.
    ///
    /// Each entry is re-read and rewritten in one write transaction, so a
    /// status change or hand edit committed since the id list was read is
    /// seen and left alone.
    ///
    /// An emptied entry is deleted — unless a supplement points at it, in
    /// which case it stays, at zero, so the supplement never refers to a row
    /// that is gone.
    @discardableResult
    public static func recomputeOwnedEntries(database: any BillingPersistence, only: Set<String>? = nil) throws -> Int {
        var changed = 0
        let ids = try database.billingRecomputableEntryIds().filter { only?.contains($0) ?? true }
        for id in ids {
            try database.transaction {
                guard let stored = try database.billingStoredEntry(id: id),
                      !stored.entry.locked, stored.entry.origin == "auto" else { return }
                let entry = stored.entry
                let segments = try database.billingSegmentsForEntry(id: id)
                if segments.isEmpty, try database.deleteEmptyBillingEntry(id: id) {
                    changed += 1
                    return
                }

                let computed = figures(
                    of: segments, roundingMinutes: entry.roundingMinutes,
                    roundingMode: entry.roundingMode, rateCents: entry.rateCents
                )
                let description = stored.descriptionEdited
                    ? entry.description
                    : try describe(segments: segments, database: database)
                let current = Figures(
                    startedAt: entry.startedAt, endedAt: entry.endedAt, raw: entry.rawSeconds,
                    billed: entry.billedSeconds, amount: entry.amountCents
                )
                guard current != computed || entry.description != description else { return }

                let written = try database.upsertBillingEntry(BillingEntryDTO(
                    id: entry.id,
                    projectId: entry.projectId,
                    clientId: entry.clientId,
                    day: entry.day,
                    groupKey: entry.groupKey,
                    startedAt: computed.startedAt,
                    endedAt: computed.endedAt,
                    rawSeconds: computed.raw,
                    billedSeconds: computed.billed,
                    rateCents: entry.rateCents,
                    currency: entry.currency,
                    amountCents: computed.amount,
                    roundingMinutes: entry.roundingMinutes,
                    roundingMode: entry.roundingMode,
                    status: entry.status,
                    description: description,
                    origin: entry.origin,
                    locked: entry.locked,
                    supplementsEntryId: entry.supplementsEntryId,
                    createdAt: entry.createdAt,
                    updatedAt: UTCTimestamp.now()
                ), overwrite: .rollupOwned)
                if written { changed += 1 }
            }
        }
        return changed
    }

    // MARK: - Money

    /// `billedSeconds` at `rateCents` per hour, in whole cents, rounded half-up.
    ///
    /// Delegates to `Money.amountCents`, the one formula the app's reprice
    /// path also uses, so the daemon's figure and the editor's figure can
    /// never disagree by a cent.
    public static func amountCents(billedSeconds: Int, rateCents: Int) -> Int {
        Money.amountCents(seconds: billedSeconds, rateCents: rateCents)
    }

    // MARK: - Editing

    /// A hand edit.
    ///
    /// - A **new** entry, or an edit that changes a **figure** (project, day,
    ///   times, hours, rate, currency, amount, rounding), lands as
    ///   `origin: "user"`. That freezes it against the rollup: the next pass
    ///   neither recomputes the figure the user just chose nor grows it — later
    ///   work that day goes to a supplement.
    /// - An edit that changes **only the description** keeps the entry's
    ///   origin, so an auto entry goes on tracking its time; the words are
    ///   remembered (`description_edited`) and kept through every recompute.
    /// - **Status never changes here.** `setStatus` is the one path, because it
    ///   is the one that writes the audit row. A save that would move status is
    ///   refused rather than silently applied or silently ignored.
    /// - **A stale save is refused.** The editor sends the whole row it last
    ///   read; if the rollup has written the entry since (its `updated_at` or
    ///   tracked seconds moved), writing those figures would drop the time the
    ///   rollup just attached and freeze the entry without it.
    @discardableResult
    public static func saveEntry(_ dto: BillingEntryDTO, database: any BillingPersistence) throws -> BillingEntryDTO {
        var saved: BillingEntryDTO?
        try database.transaction {
            let existing = dto.id.isEmpty ? nil : try database.billingEntry(id: dto.id)
            if let existing, existing.locked { throw RollupError.entryIsLocked(dto.id) }
            let currentStatus = existing?.status ?? BillingStatus.unbilled.rawValue
            guard dto.status == currentStatus else {
                throw RollupError.statusChangeNotAllowed(current: currentStatus, requested: dto.status)
            }
            if let existing, existing.updatedAt != dto.updatedAt || existing.rawSeconds != dto.rawSeconds {
                throw RollupError.entryChanged(dto.id)
            }

            let figuresChanged = existing.map { old in
                old.projectId != dto.projectId || old.day != dto.day
                    || old.startedAt != dto.startedAt || old.endedAt != dto.endedAt
                    || old.rawSeconds != dto.rawSeconds || old.billedSeconds != dto.billedSeconds
                    || old.rateCents != dto.rateCents || old.currency != dto.currency
                    || old.amountCents != dto.amountCents
                    || old.roundingMinutes != dto.roundingMinutes || old.roundingMode != dto.roundingMode
            } ?? true
            let descriptionChanged = existing.map { $0.description != dto.description } ?? false

            let now = UTCTimestamp.now()
            let entry = BillingEntryDTO(
                id: existing?.id ?? (dto.id.isEmpty ? UUID().uuidString : dto.id),
                projectId: dto.projectId,
                clientId: dto.clientId,
                day: dto.day,
                groupKey: dto.groupKey,
                startedAt: dto.startedAt,
                endedAt: dto.endedAt,
                rawSeconds: dto.rawSeconds,
                billedSeconds: dto.billedSeconds,
                rateCents: dto.rateCents,
                currency: dto.currency,
                amountCents: dto.amountCents,
                roundingMinutes: dto.roundingMinutes,
                roundingMode: dto.roundingMode,
                status: currentStatus,
                description: dto.description,
                origin: figuresChanged ? "user" : (existing?.origin ?? "user"),
                locked: false,
                supplementsEntryId: dto.supplementsEntryId,
                createdAt: existing?.createdAt ?? now,
                updatedAt: now
            )
            guard try database.upsertBillingEntry(entry, overwrite: .unlocked) else {
                throw RollupError.entryIsLocked(entry.id)
            }
            if descriptionChanged { try database.markBillingEntryDescriptionEdited(id: entry.id) }
            saved = entry
        }
        guard let saved else { throw RollupError.unknownEntry(dto.id) }
        return saved
    }

    /// Changes an entry's description and nothing else.
    ///
    /// The editor's path for the words. It sends the one field it changed, not
    /// a copy of the row: today's auto entry grows every pass, so a whole-row
    /// save from a window opened a minute ago carries stale figures. Here the
    /// figures are never written, so the entry stays the rollup's to maintain;
    /// `description_edited` keeps the words through every recompute.
    @discardableResult
    public static func setDescription(
        entryId: String, description: String, database: any BillingPersistence
    ) throws -> BillingEntryDTO {
        var stored: BillingEntryDTO?
        try database.transaction {
            guard let existing = try database.billingEntry(id: entryId) else {
                throw RollupError.unknownEntry(entryId)
            }
            guard !existing.locked else { throw RollupError.entryIsLocked(entryId) }
            let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
            // The SQL re-checks `locked = 0`; a refused write is a refusal,
            // never the unchanged row passed off as success.
            guard try database.setBillingEntryDescription(id: entryId, description: text, at: UTCTimestamp.now())
            else { throw RollupError.entryIsLocked(entryId) }
            stored = try database.billingEntry(id: entryId)
        }
        guard let stored else { throw RollupError.unknownEntry(entryId) }
        return stored
    }

    public static func deleteEntry(id: String, database: any BillingPersistence) throws {
        try database.transaction {
            guard let existing = try database.billingEntry(id: id) else {
                throw RollupError.unknownEntry(id)
            }
            guard !existing.locked else { throw RollupError.entryIsLocked(id) }
            // Its supplements go with it, so a billed one would take invoiced
            // time out of the totals and free it to be billed again.
            let frozen = try database.billingFrozenSupplementCount(of: id)
            guard frozen == 0 else { throw RollupError.entryHasFrozenSupplements(id: id, count: frozen) }
            try database.deleteBillingEntry(id: id)
        }
    }

    /// The only way an entry's status ever changes. Every move is audited,
    /// including moves backwards — reopening a billed day is allowed, because
    /// mistakes happen, but it leaves a mark.
    @discardableResult
    public static func setStatus(
        entryId: String, to status: BillingStatus, source: String, database: any BillingPersistence
    ) throws -> BillingEntryDTO {
        var result: BillingEntryDTO?
        // Read and write under one write lock, so the row written is the row
        // as it is now — never a snapshot a rollup pass has since grown.
        try database.transaction {
            guard let existing = try database.billingEntry(id: entryId) else {
                throw RollupError.unknownEntry(entryId)
            }
            guard existing.status != status.rawValue else {
                result = existing
                return
            }

            let updated = BillingEntryDTO(
                id: existing.id,
                projectId: existing.projectId,
                clientId: existing.clientId,
                day: existing.day,
                groupKey: existing.groupKey,
                startedAt: existing.startedAt,
                endedAt: existing.endedAt,
                rawSeconds: existing.rawSeconds,
                billedSeconds: existing.billedSeconds,
                rateCents: existing.rateCents,
                currency: existing.currency,
                amountCents: existing.amountCents,
                roundingMinutes: existing.roundingMinutes,
                roundingMode: existing.roundingMode,
                status: status.rawValue,
                description: existing.description,
                origin: existing.origin,
                locked: status.locksTheEntry,
                supplementsEntryId: existing.supplementsEntryId,
                createdAt: existing.createdAt,
                updatedAt: UTCTimestamp.now()
            )
            try database.upsertBillingEntry(updated, overwrite: .any)
            try database.appendBillingAudit(
                entryId: entryId, field: "status",
                oldValue: existing.status, newValue: status.rawValue, source: source
            )
            result = updated
        }
        guard let result else { throw RollupError.unknownEntry(entryId) }
        return result
    }

    /// Moves orphaned segments into a project. Returns how many moved.
    @discardableResult
    public static func assignSegments(
        ids: [String], projectId: String?, database: any BillingPersistence
    ) throws -> Int {
        try database.assignSegments(ids: ids, toProject: projectId)
    }

    /// Moves every unassigned, unbilled segment from `projectRoot` into the
    /// project and rolls the finished ones into entries. The daemon's own
    /// list, not the page of recent runs a window holds, so older runs from
    /// the repository are billed too. Returns how many moved.
    @discardableResult
    public static func assignRepository(
        projectRoot: String, projectId: String, options: BillingRollupOptions, database: any BillingPersistence
    ) throws -> Int {
        guard !projectRoot.isEmpty else { return 0 }
        let ids = try database.unassignedSegmentIDs(projectRoot: projectRoot)
        let moved = try database.assignSegments(ids: ids, toProject: projectId)
        try promoteSegments(ids: ids, options: options, database: database)
        return moved
    }

    // MARK: - Overview

    /// One row per currency, never a cross-currency sum. The top-level figures
    /// are the most-used currency's row (see `BillingOverviewDTO`).
    public static func overview(database: any BillingPersistence) throws -> BillingOverviewDTO {
        let empty = BillingOverviewBucketDTO(seconds: 0, amountCents: 0, entryCount: 0)
        let rows = try database.billingOverviewBuckets().map { group in
            BillingOverviewCurrencyDTO(
                currency: group.currency,
                unbilled: group.buckets[BillingStatus.unbilled.rawValue] ?? empty,
                billed: group.buckets[BillingStatus.billed.rawValue] ?? empty,
                paid: group.buckets[BillingStatus.paid.rawValue] ?? empty
            )
        }
        return BillingOverviewDTO(
            unbilled: rows.first?.unbilled ?? empty,
            billed: rows.first?.billed ?? empty,
            paid: rows.first?.paid ?? empty,
            currency: rows.first?.currency ?? "USD",
            byCurrency: rows
        )
    }
}
