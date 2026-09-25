import Foundation

/// One continuous stretch of work derived from a session's activity.
/// `endedAt == ""` means still running, in which case `seconds` is 0: a run is
/// only billable once it has closed.
public struct BillingRun: Sendable, Equatable {
    public let startedAt: String
    public let endedAt: String
    public let seconds: Int

    public init(startedAt: String, endedAt: String, seconds: Int) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.seconds = seconds
    }

    public var isOpen: Bool { endedAt.isEmpty }
}

/// Turns a session's activity timestamps into runs.
///
/// Pure by design. Segments are *derived*, never driven by a live state
/// machine, which is why a daemon crash, a reinstall mid-session, a laptop
/// sleep, or a timer nobody stopped all cost nothing: sleep produces a gap, a
/// gap produces a split, and re-deriving the same events produces the same
/// runs. The price is up to one scheduling interval of lag, and a run that is
/// still open is not yet billable.
public enum BillingDerivation {

    /// The cutoff used when the caller supplies a nonsensical one.
    public static let defaultCutoffSeconds = 15 * 60

    /// - Parameters:
    ///   - activityTimestamps: UTC ISO-8601, any order; ambient event types are
    ///     already excluded by the caller (the host decides which events count as activity).
    ///   - sessionStartedAt: used only as a lead-in for the *first* run.
    ///   - sessionIsActive: whether the session is still live.
    ///   - now: the caller's clock, passed in so this stays testable.
    ///   - cutoffSeconds: idle gap that ends a run.
    public static func runs(
        activityTimestamps: [String],
        sessionStartedAt: String,
        sessionIsActive: Bool,
        now: String,
        cutoffSeconds: Int
    ) -> [BillingRun] {
        // Parse, drop anything that isn't a timestamp, de-duplicate, and sort.
        // Whole epoch seconds are what make the order chronological (fractional
        // seconds would otherwise sort before their own whole second as
        // strings). Hooks land out of order often enough that trusting arrival
        // order would produce negative-length runs.
        let seconds = activityTimestamps.compactMap { UTCTimestamp.epochSeconds($0) }
        return runs(
            activitySeconds: Array(Set(seconds)).sorted(),
            sessionStartedAt: sessionStartedAt,
            sessionIsActive: sessionIsActive,
            now: now,
            cutoffSeconds: cutoffSeconds
        )
    }

    /// The same derivation over stamps already parsed to whole epoch seconds,
    /// **sorted ascending and de-duplicated** — the form `BillingActivityCache`
    /// keeps, so a pass over a long session does no parsing at all.
    public static func runs(
        activitySeconds stamps: [Int],
        sessionStartedAt: String,
        sessionIsActive: Bool,
        now: String,
        cutoffSeconds: Int
    ) -> [BillingRun] {
        let cutoff = cutoffSeconds > 0 ? cutoffSeconds : defaultCutoffSeconds
        guard let first = stamps.first else { return [] }

        // The first run may lead in from the session's own start: the minutes
        // spent reading the prompt that caused the first event are real work,
        // and this is the one place there is evidence for them. Later runs get
        // no lead-in — see the spec's head-of-run undercount note.
        // `sessions.started_at` is usually SQLite's space-separated form, which
        // `epochSeconds` accepts.
        var runStart = first
        if let started = UTCTimestamp.epochSeconds(sessionStartedAt),
           started < first,
           first - started <= cutoff {
            runStart = started
        }

        var result: [BillingRun] = []
        var previous = first

        for stamp in stamps.dropFirst() {
            if stamp - previous > cutoff {
                // Close at the PREVIOUS event. The idle stretch is how the stop
                // is detected; it is never billed.
                result.append(closed(from: runStart, to: previous))
                runStart = stamp
            }
            previous = stamp
        }

        // The last run stays open only if the session is still live and its
        // most recent event is inside the cutoff. Anything else has stopped,
        // whether or not anything told us so. A malformed `now` can't prove
        // recency, so it closes the run rather than leaving it open forever.
        let nowSeconds = UTCTimestamp.epochSeconds(now)
        let stillRunning = sessionIsActive
            && nowSeconds.map { $0 - previous <= cutoff } == true
        result.append(
            stillRunning
                ? BillingRun(startedAt: UTCTimestamp.string(epochSeconds: runStart), endedAt: "", seconds: 0)
                : closed(from: runStart, to: previous)
        )
        return result
    }

    private static func closed(from start: Int, to end: Int) -> BillingRun {
        BillingRun(
            startedAt: UTCTimestamp.string(epochSeconds: start),
            endedAt: UTCTimestamp.string(epochSeconds: end),
            seconds: max(0, end - start)
        )
    }
}
