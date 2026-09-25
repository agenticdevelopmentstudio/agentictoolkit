import Foundation

/// The two interval algorithms every "how long was someone working" measure is
/// built from: splitting activity stamps into runs at idle gaps, and taking the
/// union of overlapping intervals.
///
/// Generic over the stamp type, so epoch seconds (`Int` or `Double`) and
/// fixed-width ISO strings (for the union, which needs only ordering) share one
/// copy. Policy — a lead-in before the first stamp, whether the last run is
/// still open, what the cutoff is — stays with the caller.
public enum ActivityRuns {

    /// One closed span of activity, first stamp to last.
    public struct Span<Stamp: Comparable>: Equatable {
        public var start: Stamp
        public var end: Stamp

        public init(start: Stamp, end: Stamp) {
            self.start = start
            self.end = end
        }
    }

    /// Streams stamps into spans, for callers reading rows one at a time.
    ///
    /// Stamps must arrive in ascending order. A gap strictly greater than
    /// `idleGap` closes the running span at the *previous* stamp — the idle
    /// stretch is how the stop is detected, never part of the span.
    public struct Splitter<Stamp: Comparable & AdditiveArithmetic> {
        public let idleGap: Stamp
        public private(set) var spans: [Span<Stamp>] = []
        private var open: Span<Stamp>?

        public init(idleGap: Stamp) {
            self.idleGap = idleGap
        }

        /// Adds the next stamp (ascending).
        public mutating func add(_ stamp: Stamp) {
            guard var current = open else {
                open = Span(start: stamp, end: stamp)
                return
            }
            if stamp - current.end > idleGap {
                spans.append(current)
                open = Span(start: stamp, end: stamp)
            } else {
                current.end = stamp
                open = current
            }
        }

        /// Closes the running span — at a boundary the stamps don't show, such
        /// as the next stamp belonging to a different session.
        public mutating func closeRun() {
            if let current = open { spans.append(current) }
            open = nil
        }

        /// Every span, the running one closed.
        public mutating func finish() -> [Span<Stamp>] {
            closeRun()
            return spans
        }
    }

    /// Splits ascending stamps into spans at every gap greater than `idleGap`.
    public static func split<Stamp: Comparable & AdditiveArithmetic>(
        _ ascending: some Sequence<Stamp>, idleGap: Stamp
    ) -> [Span<Stamp>] {
        var splitter = Splitter(idleGap: idleGap)
        for stamp in ascending { splitter.add(stamp) }
        return splitter.finish()
    }

    /// The union of `intervals`: sorted by start, overlapping or touching
    /// intervals merged. Needs only ordering, so fixed-width ISO strings work
    /// as well as numbers.
    public static func union<Stamp: Comparable>(_ intervals: [Span<Stamp>]) -> [Span<Stamp>] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [Span<Stamp>] = []
        for interval in sorted {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1].end = max(last.end, interval.end)
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    /// The total length of the union of `intervals` — wall-clock time, with
    /// overlaps counted once.
    public static func unionLength<Stamp: Comparable & AdditiveArithmetic>(_ intervals: [Span<Stamp>]) -> Stamp {
        union(intervals).reduce(.zero) { $0 + ($1.end - $1.start) }
    }
}

extension ActivityRuns.Span: Sendable where Stamp: Sendable {}
