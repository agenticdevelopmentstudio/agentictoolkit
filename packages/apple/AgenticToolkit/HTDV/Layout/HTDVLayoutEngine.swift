import Foundation

/// Decides how many rails fit beside the detail pane. Pure; both platform
/// view controllers call it on resize.
public struct HTDVLayoutEngine: Sendable {
    public enum Mode: Equatable, Sendable {
        /// Side-by-side rails (the rightmost `visibleRails`) with an
        /// optional detail pane.
        case columns(visibleRails: Range<Int>, showsDetail: Bool)
        /// One level at a time (compact width classes).
        case stack
    }

    public var railWidth: CGFloat
    public var minDetailWidth: CGFloat

    public init(railWidth: CGFloat = 240, minDetailWidth: CGFloat = 480) {
        precondition(railWidth > 0)
        self.railWidth = railWidth
        self.minDetailWidth = minDetailWidth
    }

    public func layout(
        availableWidth: CGFloat,
        levelCount: Int,
        hasDetail: Bool,
        isCompact: Bool
    ) -> Mode {
        if isCompact { return .stack }
        guard levelCount > 0 else {
            return .columns(visibleRails: 0..<0, showsDetail: hasDetail)
        }
        // `railWidth` is a public settable `var`, so the `init` precondition does not protect this
        // division: an app that assigns 0 for one layout pass (collapsed sidebar, zero-width window
        // during a space switch) would divide by zero and then trap in `Int(.infinity)`, which is a
        // trapping conversion rather than a saturating one. Clamping the divisor here makes that
        // crash unreachable without taking the public setter away.
        let width = max(railWidth, 1)
        let railsWidth = availableWidth - (hasDetail ? minDetailWidth : 0)
        // Clamped into 0...levelCount before the conversion for the same trapping-`Int(_:)` reason;
        // the result is capped at `levelCount` on the next line regardless, so this changes nothing
        // except which inputs survive.
        let fitting = Int(max(0, min(floor(railsWidth / width), CGFloat(levelCount))))
        let visible = max(1, min(levelCount, fitting))
        return .columns(
            visibleRails: (levelCount - visible)..<levelCount,
            showsDetail: hasDetail
        )
    }
}
