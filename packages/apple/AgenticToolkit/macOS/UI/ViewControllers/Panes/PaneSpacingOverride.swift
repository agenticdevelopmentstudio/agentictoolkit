import AppKit

/// Adopted by pane content that already insets itself — a terminal reads
/// `UserSettings.terminalPadding*` and holds its grid off its own edges.
///
/// The spec's rule is "one gap at two scopes, not a second padding stacked on
/// the first", and this is what decides which of the two applies it: content
/// that adopts this is handed the resolved spacing and does the insetting, and
/// its pane pins it flush. Content that does not adopt it has the gap applied
/// for it, by the pane. Exactly one of the two, chosen by a conformance rather
/// than by the pane knowing what a terminal is (`explicit-over-implicit`).
@MainActor
public protocol PaneContentSpacingConsuming: AnyObject {

    /// The app-wide gap this content already honours, and so the default its
    /// pane's control overrides. A terminal answers with
    /// `UserSettings.terminalPadding*` — which is what makes the per-pane
    /// control override *that* number rather than introduce a second one.
    var inheritedPaneSpacing: Spacing { get }

    /// Apply this gap instead of the global. The pane pins the content flush
    /// once this is called, so nothing is applied twice.
    func applyPaneSpacing(_ spacing: Spacing)
}

/// One pane's answer to "how much room around my content" — either its own, or
/// silence, which means whatever the app says.
///
/// Absence is the point. A pane with no stored row *inherits*, so a later change
/// to the global still reaches it; "use default" deletes the row rather than
/// freezing today's global into it. That is why this is not simply a `Spacing`
/// with a default value: `nil` and "the same numbers as the default" are
/// different states, and only one of them follows the app.
@MainActor
public final class PaneSpacingOverride {

    /// The same range every spacing control in this framework offers, so a pane
    /// cannot store a number the settings panel could not have produced.
    public static let range: ClosedRange<Int> = 0...40

    /// Only the four edges. The two gutters are the *grid's* — the gap between
    /// two panes is one gap shared by both, so no single pane may own it.
    private struct StoredSpacing: Codable {
        var top: Int
        var leading: Int
        var bottom: Int
        var trailing: Int
    }

    private let store: PaneStateStore
    private let inheritedProvider: @MainActor () -> Spacing

    /// The write the user's current gesture has not finished earning.
    ///
    /// The spacing steppers are continuous — `SpacingControl` sets
    /// `isContinuous` and a 0.06s repeat interval — so holding an arrow key
    /// down produces about seventeen values a second, and every one of them
    /// used to become a JSON encode plus a synchronous SQLite write on the
    /// main thread. Coalescing them costs nothing anyone can see: the resolved
    /// value and `onChange` are still applied on the spot, so the pane redraws
    /// at every tick; only the row lags, and by less than the pause between
    /// two deliberate presses (`ComposableTabsViewController` debounces divider
    /// drags the same way, for the same reason).
    ///
    /// Captured strongly by the work item on purpose, so a pane torn down
    /// mid-gesture still writes what the user chose. The cycle that makes is
    /// broken by the item itself, which clears this on its way out.
    private var pendingPersist: DispatchWorkItem?

    /// The value that write would carry. Held beside the work item so a flush
    /// can do the write itself: `DispatchWorkItem.perform()` does nothing once
    /// the item has been cancelled, and cancelling is exactly what a flush has
    /// to do first to stop the timer running it a second time.
    private var pendingStored: StoredSpacing?

    /// Long enough to swallow an autorepeat run, short enough that a single
    /// click is on disk before anything a person could do next.
    private static let persistDelay: DispatchTimeInterval = .milliseconds(300)

    /// Fires with the *resolved* value whenever it changes, from either
    /// direction — so a listener applies what it is given and never has to ask
    /// which of the two scopes won.
    public var onChange: ((Spacing) -> Void)?

    public private(set) var overrideValue: Spacing?

    public init(store: PaneStateStore, inherited: @escaping @MainActor () -> Spacing) {
        self.store = store
        self.inheritedProvider = inherited
        self.overrideValue = Self.read(from: store)
    }

    public var inherited: Spacing { inheritedProvider() }

    public var isOverridden: Bool { overrideValue != nil }

    public var resolved: Spacing { overrideValue ?? inherited }

    public var insets: NSEdgeInsets {
        let value = resolved
        return NSEdgeInsets(
            top: CGFloat(value.top),
            left: CGFloat(value.leading),
            bottom: CGFloat(value.bottom),
            right: CGFloat(value.trailing)
        )
    }

    public func setOverride(_ value: Spacing) {
        let stored = StoredSpacing(
            top: Self.clamped(value.top),
            leading: Self.clamped(value.leading),
            bottom: Self.clamped(value.bottom),
            trailing: Self.clamped(value.trailing)
        )
        overrideValue = Spacing(
            top: stored.top,
            leading: stored.leading,
            bottom: stored.bottom,
            trailing: stored.trailing
        )
        schedulePersist(of: stored)
        onChange?(resolved)
    }

    /// Back to inheriting. The row is **deleted**, not overwritten with the
    /// current global — a pane that had been reset once would otherwise stop
    /// following the app from that moment on, which is the opposite of what the
    /// button says.
    public func reset() {
        overrideValue = nil
        // Cancelled, not merely superseded: a queued write from the gesture
        // just before the reset would otherwise land after the deletion and
        // put the override straight back.
        pendingPersist?.cancel()
        pendingPersist = nil
        pendingStored = nil
        store.setPaneStateValue(nil, forKey: PaneStateKey.spacingOverride)
        onChange?(resolved)
    }

    /// Writes a coalesced override now instead of when its timer says so.
    ///
    /// For anything that needs the row and the in-memory value to agree at a
    /// known moment — a test, or a caller about to read the store back through
    /// a second `PaneSpacingOverride` on the same pane. Nothing pending is a
    /// no-op, so it is always safe to call.
    public func flushPendingPersist() {
        pendingPersist?.cancel()
        writePendingOverride()
    }

    private func schedulePersist(of stored: StoredSpacing) {
        pendingStored = stored
        pendingPersist?.cancel()
        let work = DispatchWorkItem { [self] in writePendingOverride() }
        pendingPersist = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.persistDelay, execute: work)
    }

    private func writePendingOverride() {
        pendingPersist = nil
        guard let stored = pendingStored else { return }
        pendingStored = nil
        guard let data = try? JSONEncoder().encode(stored),
              let json = String(data: data, encoding: .utf8) else { return }
        store.setPaneStateValue(json, forKey: PaneStateKey.spacingOverride)
    }

    /// `static`, so the read path can hold to the same bound the write path
    /// does — `range` is a claim about what a stored override *is*, not merely
    /// about what this session's control is allowed to produce.
    private static func clamped(_ number: Int) -> Int {
        min(max(number, range.lowerBound), range.upperBound)
    }

    /// A row that no longer parses — written by an older build, or edited by
    /// hand — is read as "no override". The cost of being wrong is a pane
    /// spaced like the rest of the app, so there is nothing here worth
    /// stopping for.
    ///
    /// A row that parses but carries a number outside `range` is clamped rather
    /// than discarded: the same sources that can produce an unparseable row can
    /// produce an out-of-range one, and honouring it would put the pane in a
    /// state its own control could never have reached and cannot show.
    private static func read(from store: PaneStateStore) -> Spacing? {
        guard let json = store.paneStateValue(forKey: PaneStateKey.spacingOverride),
              let data = json.data(using: .utf8),
              let stored = try? JSONDecoder().decode(StoredSpacing.self, from: data)
        else { return nil }
        return Spacing(
            top: clamped(stored.top),
            leading: clamped(stored.leading),
            bottom: clamped(stored.bottom),
            trailing: clamped(stored.trailing)
        )
    }
}
