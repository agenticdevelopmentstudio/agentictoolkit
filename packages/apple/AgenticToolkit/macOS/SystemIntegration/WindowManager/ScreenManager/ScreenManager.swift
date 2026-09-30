import AppKit
import os
import AgenticToolkitCore
internal import AgenticToolkitDisplays

/// Owns everything screen-related: the current screen set, the persisted
/// list of every screen set the machine has been attached to (with
/// first/last-seen timestamps), and classification of live screen changes.
///
/// A "screen set" is the group of displays connected at one location; a
/// laptop that travels between home and office produces one set per desk.
/// `WindowFrameManager` keys window placements by `currentSetID` so each
/// window remembers a position per location.
///
/// Listens through `DisplayMonitor` (screen parameters, CG reconfiguration, wake),
/// classifies the change (`ScreenChange`), updates + persists the set list,
/// and notifies observers. Sets not seen for `maxSetAge` (default six
/// months) are aged out on load and on every update.
@MainActor
public final class ScreenManager {

    public static let shared = ScreenManager()

    public let screenProvider: ScreenProvider
    public let storage: ScreenSetStorage
    /// Sets whose `lastSeen` is older than this are dropped. Default 180 days.
    public let maxSetAge: TimeInterval

    /// Every known screen set, most recently seen first. Persisted.
    public private(set) var knownSets: [ScreenSet] = []
    /// Ids of every known set. Maintained alongside `knownSets` so hot callers
    /// (`WindowFrameManager.saveFrame`, on every drag tick) read it in O(1)
    /// instead of rebuilding a `Set` from `knownSets` each time.
    public private(set) var knownSetIDs: Set<String> = []
    /// Identity of the set of screens attached right now.
    public private(set) var currentSetID: String
    /// Latest per-screen snapshots. Refreshed both by change notifications and,
    /// on demand, by `touchCurrentSet()`.
    private var currentSnapshots: [ScreenSnapshot]
    /// The snapshots the last *delivered* classification was computed against.
    /// Deliberately separate from `currentSnapshots`: `touchCurrentSet()` may
    /// refresh the latter between notifications, and if that also moved the
    /// diff baseline the change notification that follows would classify as
    /// "nothing moved" and no window would be repositioned.
    private var lastNotifiedSnapshots: [ScreenSnapshot]

    private var observers: [UUID: @MainActor (ScreenChange) -> Void] = [:]
    /// Zero debounce: screen-parameters and wake events arrive synchronously,
    /// exactly as the old notification did; CG reconfiguration events arrive
    /// on a later main-actor turn.
    private let displayMonitor: DisplayMonitor
    /// Token of this manager's one monitor handler. Registered only once so
    /// re-arming via `startObservingScreenChanges()` can never double-fire.
    private var monitorHandler: UUID?
    /// Injected clock so tests can control `savedAt`/aging.
    let now: () -> Date
    /// Throttles persistence from high-frequency touch callers (a window
    /// drag fires `saveFrame` — and thus `touchCurrentSet` — every tick).
    private var lastPersistedTouch: Date?
    private static let touchPersistInterval: TimeInterval = 60

    public convenience init(
        screenProvider: ScreenProvider = RealScreenProvider(),
        storage: ScreenSetStorage = SettingsStoreScreenSetStorage(settings: UserSettings.shared),
        maxSetAge: TimeInterval = 180 * 24 * 60 * 60,
        now: @escaping () -> Date = { Date() }
    ) {
        self.init(
            screenProvider: screenProvider, storage: storage, maxSetAge: maxSetAge, now: now,
            displaySystem: CoreGraphicsDisplaySystem()
        )
    }

    /// Designated init. `displaySystem` feeds the `DisplayMonitor`; tests pass a
    /// `FakeDisplaySystem`. It has no default so calls that omit it resolve,
    /// unambiguously, to the public init above, which supplies the real one.
    init(
        screenProvider: ScreenProvider = RealScreenProvider(),
        storage: ScreenSetStorage = SettingsStoreScreenSetStorage(settings: UserSettings.shared),
        maxSetAge: TimeInterval = 180 * 24 * 60 * 60,
        now: @escaping () -> Date = { Date() },
        displaySystem: DisplaySystem
    ) {
        self.screenProvider = screenProvider
        self.storage = storage
        self.maxSetAge = maxSetAge
        self.now = now
        self.displayMonitor = DisplayMonitor(system: displaySystem, debounce: .zero)

        let snapshots = screenProvider.screens.map(ScreenSnapshot.init)
        self.currentSnapshots = snapshots
        self.lastNotifiedSnapshots = snapshots
        self.currentSetID = ScreenSet.identity(of: snapshots)
        self.knownSets = Self.pruned(storage.loadSets(), olderThan: maxSetAge, now: now())
        self.knownSetIDs = Set(knownSets.map(\.id))
        upsertCurrentSet(persist: true)
        startObservingScreenChanges()
    }

    /// The persisted record for the screens attached right now.
    public var currentSet: ScreenSet? {
        knownSets.first { $0.id == currentSetID }
    }

    // MARK: - Observers

    /// Registers a screen-change handler; fires after `currentSetID` and the
    /// persisted set list have been updated. Returns a token for removal.
    @discardableResult
    public func addObserver(_ handler: @escaping @MainActor (ScreenChange) -> Void) -> UUID {
        let token = UUID()
        observers[token] = handler
        return token
    }

    public func removeObserver(_ token: UUID) {
        observers[token] = nil
    }

    // MARK: - Change handling

    /// Starts observing screen changes through a `DisplayMonitor`. Called
    /// automatically by `init`; safe to call again to re-arm. Genuinely
    /// idempotent: `DisplayMonitor.start()` restarts (never duplicates) its
    /// sources, and the handler is registered only once, so a single event
    /// never double-fires.
    public func startObservingScreenChanges() {
        if monitorHandler == nil {
            monitorHandler = displayMonitor.addHandler { [weak self] _ in self?.processScreenChange() }
        }
        displayMonitor.start()
    }

    /// Diffs the live screens against the last snapshot; on a real change,
    /// updates the current set, persists, and notifies observers. Internal
    /// (not private) so tests can drive it without posting notifications.
    func processScreenChange() {
        let snapshots = screenProvider.screens.map(ScreenSnapshot.init)
        // Diff against the last snapshots we *notified* on, not the live ones:
        // `touchCurrentSet()` may have already refreshed `currentSnapshots`
        // ahead of this notification, and diffing against those would report
        // "nothing changed" and skip repositioning.
        let change = Self.classifyChange(from: lastNotifiedSnapshots, to: snapshots)
        currentSnapshots = snapshots
        currentSetID = ScreenSet.identity(of: snapshots)
        lastNotifiedSnapshots = snapshots
        guard let change else { return }
        upsertCurrentSet(persist: true)
        let description = String(describing: change)
        logger.info("ScreenManager: \(description, privacy: .public) → set '\(self.currentSetID, privacy: .public)'")
        for handler in observers.values {
            handler(change)
        }
    }

    /// Classifies what changed between two snapshot lists. Returns nil for a
    /// spurious notification (nothing actually moved).
    static func classifyChange(
        from old: [ScreenSnapshot],
        to new: [ScreenSnapshot]
    ) -> ScreenChange? {
        switch DisplayChange.classify(from: old.map(\.geometry), to: new.map(\.geometry)) {
        case nil: return nil
        case .resolutionChanged: return .resolutionChanged
        case .arrangementChanged: return .arrangementChanged
        case let .displaySetChanged(previous, current):
            return .screenSetChanged(previousSetID: previous, currentSetID: current)
        }
    }

    // MARK: - Set bookkeeping

    /// Refreshes the current set's `lastSeen` (and snapshots) — called from
    /// window save/restore paths so a set stays alive while it's in use.
    /// Persistence is throttled; the in-memory record updates every call.
    public func touchCurrentSet() {
        reconcileWithLiveScreens()
        let timestamp = now()
        let shouldPersist: Bool
        if let last = lastPersistedTouch, timestamp.timeIntervalSince(last) < Self.touchPersistInterval {
            shouldPersist = false
        } else {
            shouldPersist = true
            lastPersistedTouch = timestamp
        }
        upsertCurrentSet(persist: shouldPersist)
    }

    /// Re-derives `currentSetID` (and `currentSnapshots`) from the live screen
    /// list when the two have drifted apart.
    ///
    /// `currentSetID` is otherwise only refreshed when a screen-parameters
    /// notification arrives, but `WindowFrameManager` reads the live screens
    /// and the set id *together*: `saveFrame` fingerprints the screen the
    /// window is actually on and files that placement under `currentSetID`.
    /// During a display reconfiguration AppKit repositions windows itself —
    /// firing `windowDidMove` → `saveFrame` — before, or between, those
    /// notifications, so the two sources disagree. The placement then lands
    /// under the *wrong* arrangement's key, fingerprinted for a display that
    /// arrangement doesn't even contain, and overwrites the good placement for
    /// that arrangement: the window comes back on the wrong screen.
    ///
    /// Deliberately does **not** classify or notify. Doing so here would
    /// re-enter `saveFrame` (via the reposition handlers) in the middle of the
    /// save that called us; `lastNotifiedSnapshots` keeps the following
    /// notification able to classify off the pre-refresh baseline instead.
    private func reconcileWithLiveScreens() {
        let live = screenProvider.screens
        // Cheap guard first — this runs on every drag tick, and building
        // snapshots means a CoreGraphics UUID lookup plus an IODisplay name
        // lookup per screen. Screen *membership* cannot change without the
        // frame list changing too, so an identical frame list means an
        // identical set. (`visibleFrame` is left out on purpose: the Dock
        // hiding changes it without touching membership.)
        if live.count == currentSnapshots.count,
           zip(live, currentSnapshots).allSatisfy({ $0.frame == $1.frame }) {
            return
        }
        let snapshots = live.map(ScreenSnapshot.init)
        currentSnapshots = snapshots
        currentSetID = ScreenSet.identity(of: snapshots)
    }

    /// Inserts or updates the current set in `knownSets` (bumping `lastSeen`
    /// and refreshing snapshots), prunes aged-out sets, and optionally
    /// persists the list.
    private func upsertCurrentSet(persist: Bool) {
        let timestamp = now()
        if let index = knownSets.firstIndex(where: { $0.id == currentSetID }) {
            // Membership unchanged — only bump lastSeen/snapshots. This is the
            // hot path (every drag tick via `touchCurrentSet`); it does no
            // sort, prune, or Set rebuild.
            knownSets[index].screens = currentSnapshots
            knownSets[index].lastSeen = timestamp
        } else {
            knownSets.append(ScreenSet(
                id: currentSetID,
                screens: currentSnapshots,
                firstSeen: timestamp,
                lastSeen: timestamp
            ))
            knownSetIDs.insert(currentSetID)
        }
        // Prune + sort only when we're about to persist — nothing between
        // persists depends on aged-out sets (6-month scale) or array order.
        if persist {
            let before = knownSets.count
            knownSets = Self.pruned(knownSets, olderThan: maxSetAge, now: timestamp)
            if knownSets.count != before { knownSetIDs = Set(knownSets.map(\.id)) }
            knownSets.sort { $0.lastSeen > $1.lastSeen }
            storage.saveSets(knownSets)
        }
    }

    private static func pruned(_ sets: [ScreenSet], olderThan maxAge: TimeInterval, now: Date) -> [ScreenSet] {
        sets.filter { now.timeIntervalSince($0.lastSeen) <= maxAge }
    }
}

extension ScreenManager: Loggable {
    public static nonisolated let logger = makeLogger()
}
