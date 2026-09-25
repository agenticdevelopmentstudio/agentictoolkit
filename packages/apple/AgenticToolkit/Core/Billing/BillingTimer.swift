import Foundation

/// Hand-started time.
///
/// A manual timer is a `billing_segment` with `origin = "manual"` and an empty
/// `ended_at` — deliberately the same row shape a derived run uses, so it rolls
/// up, assigns, and displays through one code path instead of two.
public enum BillingTimer {

    public enum TimerError: LocalizedError {
        case unknownTimer(String)
        case notRunning(String)

        public var errorDescription: String? {
            switch self {
            case .unknownTimer: return BillingRefusalText.unknownTimer
            case .notRunning: return BillingRefusalText.timerNotRunning
            }
        }
    }

    /// Starts a timer, closing any other running one at the same instant.
    ///
    /// Stopping the previous timer is not a convenience — it is the invariant.
    /// Two running timers would bill the same wall-clock minute twice, and no
    /// later reconciliation can tell which of them was the real work.
    @discardableResult
    public static func start(
        _ request: BillingTimerStartDTO,
        now: String = UTCTimestamp.now(),
        database: any BillingPersistence
    ) throws -> BillingSegmentDTO {
        // Only resolve when the caller did not already choose. A start from the
        // Projects window names its project; one from the Activity window may
        // name only a path, and should land where derivation would put it.
        var projectId = request.projectId
        var repoId = request.repoId
        if projectId == nil, !request.projectRoot.isEmpty {
            let resolution = try BillingStore.resolveRate(
                projectRoot: request.projectRoot, branch: request.branch, database: database
            )
            projectId = resolution.projectId
            repoId = resolution.repoId
        }

        let segment = BillingSegmentDTO(
            id: UUID().uuidString,
            sessionId: "",
            origin: BillingSegmentDTO.manualOrigin,
            projectId: projectId,
            repoId: repoId,
            projectRoot: request.projectRoot,
            branch: request.branch,
            startedAt: now,
            endedAt: "",
            tz: TimeZone.current.identifier,
            seconds: 0,
            note: request.note,
            createdAt: now,
            updatedAt: now
        )
        // One transaction: stopping the previous timer and inserting this one
        // must land together. Apart, a failed insert left nothing running, and
        // two concurrent starts could each stop "everything" and then both
        // insert — two running timers, which is the invariant broken.
        try database.transaction {
            _ = try stopAll(now: now, database: database)
            try database.upsertBillingSegment(segment)
        }
        return segment
    }

    @discardableResult
    public static func stop(
        id: String, now: String = UTCTimestamp.now(), database: any BillingPersistence
    ) throws -> BillingSegmentDTO {
        guard let segment = try database.billingSegment(id: id) else {
            throw TimerError.unknownTimer(id)
        }
        guard segment.isRunning else { throw TimerError.notRunning(id) }

        try database.closeBillingSegment(
            id: id, endedAt: now, seconds: UTCTimestamp.seconds(from: segment.startedAt, to: now)
        )
        guard let closed = try database.billingSegment(id: id) else {
            throw TimerError.unknownTimer(id)
        }
        return closed
    }

    /// Closes every running *manual* timer. Derived runs are left alone: a run
    /// in progress belongs to the derivation pass, and closing it by hand would
    /// simply be undone on the next one.
    @discardableResult
    public static func stopAll(now: String = UTCTimestamp.now(), database: any BillingPersistence) throws -> Int {
        var stopped = 0
        for timer in try database.runningBillingSegments(origin: BillingSegmentDTO.manualOrigin) {
            try database.closeBillingSegment(
                id: timer.id, endedAt: now,
                seconds: UTCTimestamp.seconds(from: timer.startedAt, to: now)
            )
            stopped += 1
        }
        return stopped
    }

    /// Every running timer and run, for the Activity window.
    public static func running(database: any BillingPersistence) throws -> [BillingSegmentDTO] {
        try database.runningBillingSegments(origin: nil)
    }

    /// Marks manual timers that have been running longer than the cap.
    ///
    /// Flagged, not stopped, and not truncated. The daemon cannot tell a nine
    /// hour day from a timer somebody forgot to stop; truncating would lose
    /// real hours, and stopping would invent an end time. Marking it puts the
    /// question in front of the only one who knows.
    @discardableResult
    public static func flagRunaways(
        capSeconds: Int, now: String = UTCTimestamp.now(), database: any BillingPersistence
    ) throws -> Int {
        guard capSeconds > 0 else { return 0 }
        var flagged = 0
        for timer in try database.runningBillingSegments(origin: BillingSegmentDTO.manualOrigin)
        where UTCTimestamp.seconds(from: timer.startedAt, to: now) > capSeconds {
            if try database.addBillingSegmentFlag(id: timer.id, flag: "runaway") { flagged += 1 }
        }
        return flagged
    }
}
