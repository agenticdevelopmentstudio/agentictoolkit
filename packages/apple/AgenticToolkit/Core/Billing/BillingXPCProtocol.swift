import Foundation

/// The billing half of a daemon's XPC surface, as its own protocol so any app
/// — a menu-bar app, a Swift command-line tool — can talk billing to a daemon
/// without linking that daemon's whole protocol.
///
/// A daemon that serves billing declares a composite protocol that refines both
/// its own protocol and this one, and exports that; a billing client connects
/// with an interface built from this protocol alone. NSXPC dispatches by
/// selector, so the two sides agree as long as these selectors are unchanged.
@objc public protocol BillingXPCProtocol {

    // MARK: Billing — clients, projects, repos, entries, segments and timers.
    //
    // Every DTO crosses as JSON `Data` (snake_case, ISO-8601), like the rest of
    // the host's XPC protocol: NSXPC only carries plist types, and a DTO per method would
    // mean an `NSSecureCoding` class per DTO.
    //
    // A `nil` (or `false`) reply on a write always means *nothing was
    // written* — either the body did not decode or the store refused it. The
    // second reply argument then carries the refusal as a sentence fit to show
    // the user ("A name is required."), nil on success; without it the app
    // could only say "it didn't save", never why.
    //
    // A list read that *failed* is never an empty list: the reply is the one
    // element `BillingWire.readFailedRow`, so the app keeps what it shows
    // instead of blanking it. A count reply is `BillingWire.failedCount` (-1)
    // when the write threw — never 0, which means "nothing to do".

    /// Every client, archived included, one encoded ``BillingClientDTO`` per
    /// entry. The app filters: it must still name an archived client's
    /// history, and offer to unarchive it.
    func billingClients(reply: @escaping ([Data]) -> Void)

    /// Creates or updates one client (body = one encoded ``BillingClientDTO``;
    /// an empty `id` creates). Replies the stored client, or nil.
    func billingSaveClient(_ body: Data, reply: @escaping (Data?, String?) -> Void)

    /// Deletes a client. Projects that referenced it are detached, never
    /// deleted — the hours under them are not the client's to take away.
    func billingDeleteClient(_ id: String, reply: @escaping (Bool, String?) -> Void)

    /// Every project, archived included — an archived project's time must
    /// still show under its name, not as Unassigned.
    func billingProjects(reply: @escaping ([Data]) -> Void)

    func billingSaveProject(_ body: Data, reply: @escaping (Data?, String?) -> Void)

    /// Deletes a project and its repo mappings. Its segments survive, detached.
    func billingDeleteProject(_ id: String, reply: @escaping (Bool, String?) -> Void)

    /// The repo mappings under one project.
    func billingRepos(projectId: String, reply: @escaping ([Data]) -> Void)

    func billingSaveRepo(_ body: Data, reply: @escaping (Data?, String?) -> Void)

    func billingDeleteRepo(_ id: String, reply: @escaping (Bool, String?) -> Void)

    /// Entries, newest day first. `projectId` / `status` / `since` nil mean
    /// "any" — `since` is an ISO day (`2026-09-01`).
    func billingEntries(
        projectId: String?, status: String?, since: String?, reply: @escaping ([Data]) -> Void
    )

    /// Creates or updates one entry by hand. Refused — nil reply — when the
    /// entry is billed or paid.
    func billingSaveEntry(_ body: Data, reply: @escaping (Data?, String?) -> Void)

    /// Moves an entry between `unbilled`, `billed` and `paid`, writing an audit
    /// row. Replies the stored entry, or nil if the id or status is unknown.
    func billingSetEntryStatus(_ id: String, status: String, reply: @escaping (Data?, String?) -> Void)

    /// Changes only an entry's description; its figures stay the rollup's to
    /// maintain. The editor uses this rather than `billingSaveEntry` because
    /// a whole-row save from a stale window would freeze a growing entry.
    func billingSetEntryDescription(
        _ id: String, description: String, reply: @escaping (Data?, String?) -> Void
    )

    /// False when the entry is locked or unknown.
    func billingDeleteEntry(_ id: String, reply: @escaping (Bool, String?) -> Void)

    /// The audit trail for one entry, oldest first.
    func billingEntryAudit(_ entryId: String, reply: @escaping ([Data]) -> Void)

    /// Recorded time, newest first. `since` is an ISO-8601 timestamp.
    func billingSegments(since: String?, limit: Int, reply: @escaping ([Data]) -> Void)

    /// Running timers and runs, for the Activity window's live rows.
    func billingRunningTimers(reply: @escaping ([Data]) -> Void)

    /// Starts a manual timer (body = one encoded ``BillingTimerStartDTO``),
    /// stopping any other running one first.
    func billingStartTimer(_ body: Data, reply: @escaping (Data?, String?) -> Void)

    /// Stops one timer, replying the closed segment.
    func billingStopTimer(_ id: String, reply: @escaping (Data?, String?) -> Void)

    /// Moves unassigned segments into a project. Replies how many moved, or
    /// `BillingWire.failedCount` when the write failed.
    func billingAssignSegments(_ ids: [String], projectId: String?, reply: @escaping (Int) -> Void)

    /// Rolls the named segments into entries now instead of waiting for the
    /// scheduled pass. Replies how many entries were written, or
    /// `BillingWire.failedCount` when the write failed.
    func billingPromoteSegments(_ ids: [String], reply: @escaping (Int) -> Void)

    /// Moves every unassigned, unbilled segment recorded in `projectRoot` —
    /// all of them, of any age — into `projectId`, and rolls the finished
    /// ones into entries. Replies how many moved, or
    /// `BillingWire.failedCount` when the write failed.
    func billingAssignRepository(_ projectRoot: String, projectId: String, reply: @escaping (Int) -> Void)

    /// Unbilled / billed / paid totals, as one encoded ``BillingOverviewDTO``.
    func billingOverview(reply: @escaping (Data) -> Void)

    /// Queues every session active since `since` (ISO-8601) for derivation;
    /// the scheduled pass does the work. Replies how many sessions were
    /// queued, or `BillingWire.failedCount` when the write failed.
    func billingBackfill(since: String, reply: @escaping (Int) -> Void)

    /// Writes the eight billing knobs into the settings table, replying the
    /// snapshot that is now in force — clamped, so the app learns what the
    /// daemon actually holds rather than what it asked for. Task 16 pushes
    /// this on every change, at startup and on every reconnect. Replies empty
    /// `Data` when the write failed — nothing was applied, so push again.
    func billingSetPreferences(_ body: Data, reply: @escaping (Data) -> Void)
}
