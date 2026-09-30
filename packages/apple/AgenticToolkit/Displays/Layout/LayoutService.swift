import CoreGraphics
import Foundation

public enum LayoutServiceError: Error, Equatable, Sendable {
    case notFound(String)
    case duplicateName(String)
    case displaySetMismatch(expected: String, actual: String)
    case solver(AnchorSolverError)
    case capture(AnchorCaptureError)
    case display(DisplayError)
    case store(DocumentStoreError)
    case remote(RemoteScreenError)
    /// Several online displays share one identity (e.g. identical monitors
    /// without serials), so anchors cannot tell them apart. Sorted by key.
    case ambiguousDisplays([DisplayIdentity])
    /// The arrangement was captured, but its anchors do not solve back to a
    /// valid arrangement (e.g. displays overlap), so it was not saved.
    case unsolvableCapture(AnchorSolverError)
    /// An error none of the cases above describe, by its description.
    case unexpected(String)
}

/// Layout CRUD, capture and apply, over a `DisplaySystem` and a document store.
/// Remote (Universal Control) placement is optional: nil `remote` simply
/// leaves remote placements out of capture and plan/apply.
///
/// `init` throws `.store(.corrupt)` when the document cannot be decoded.
/// To recover, call `store.resetCorrupt()` (which moves the file aside and
/// returns the backup's URL) and construct the service again; it then
/// starts from an empty document.
@MainActor
public final class LayoutService {
    public let system: DisplaySystem
    public let store: DisplayDocumentStore
    public let remote: RemoteScreenPlacement?
    public private(set) var document: DisplayDocument

    public init(system: DisplaySystem, store: DisplayDocumentStore, remote: RemoteScreenPlacement? = nil) throws {
        self.system = system
        self.store = store
        self.remote = remote
        self.document = try Self.wrap { try store.load() }
    }

    public var layouts: [Layout] { document.layouts }
    public var labels: ModeLabels { ModeLabels(overrides: document.labels) }

    public func reload() throws { document = try Self.wrap { try store.load() } }

    public func layout(named name: String) -> Layout? {
        layouts.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public func layout(id: UUID) -> Layout? { layouts.first { $0.id == id } }

    public func currentDisplaySet() -> DisplaySet { DisplaySet(system.onlineDisplays().map(\.identity)) }

    // MARK: - CRUD

    /// Inserts or replaces by id. Enforces unique names and one auto-apply layout per display set.
    public func save(_ layout: Layout) throws {
        let hasNameClash = layouts.contains { existing in
            existing.id != layout.id && existing.name.caseInsensitiveCompare(layout.name) == .orderedSame
        }
        if hasNameClash {
            throw LayoutServiceError.duplicateName(layout.name)
        }
        var next = document
        if layout.autoApply {
            for index in next.layouts.indices where next.layouts[index].displaySetID == layout.displaySetID {
                next.layouts[index].autoApply = false
            }
        }
        if let index = next.layouts.firstIndex(where: { $0.id == layout.id }) {
            next.layouts[index] = layout
        } else {
            next.layouts.append(layout)
        }
        try commit(next)
    }

    public func rename(_ id: UUID, to name: String) throws {
        guard var layout = layout(id: id) else { throw LayoutServiceError.notFound(id.uuidString) }
        layout.name = name
        try save(layout)
    }

    public func delete(_ id: UUID) throws {
        guard layout(id: id) != nil else { throw LayoutServiceError.notFound(id.uuidString) }
        var next = document
        next.layouts.removeAll { $0.id == id }
        try commit(next)
    }

    public func duplicate(_ id: UUID) throws -> Layout {
        guard let source = layout(id: id) else { throw LayoutServiceError.notFound(id.uuidString) }
        var copy = source
        copy.id = UUID()
        copy.name = uniqueName("\(source.name) copy")
        copy.autoApply = false
        try save(copy)
        return copy
    }

    /// The name is checked for a duplicate before any capture or remote work
    /// happens, so a rejected capture never touches the store or reads remote
    /// state.
    public func captureCurrent(name: String, autoApply: Bool, withModes: Bool) throws -> Layout {
        if layouts.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            throw LayoutServiceError.duplicateName(name)
        }
        let displays = try distinguishableOnlineDisplays()
        guard let main = displays.first(where: \.isMain) else { throw LayoutServiceError.capture(.mainMissing) }
        let frames = Dictionary(uniqueKeysWithValues: displays.map { ($0.identity, $0.bounds) })
        let anchors: [DisplayIdentity: Anchor]
        do {
            anchors = try AnchorCapture.capture(main: main.identity, bounds: frames)
        } catch let error as AnchorCaptureError {
            throw LayoutServiceError.capture(error)
        }
        do {
            _ = try AnchorSolver.solve(
                main: main.identity, anchors: anchors, sizes: frames.mapValues(\.size)
            )
        } catch let error as AnchorSolverError {
            throw LayoutServiceError.unsolvableCapture(error)
        }
        var placements = displays.map { display in
            DisplayPlacement(display: .local(display.identity), anchor: anchors[display.identity],
                             mode: withModes ? display.mode?.spec : nil)
        }
        placements += try remotePlacements(
            localDisplayUUIDs: Self.uuids(of: displays), preferredParentUUID: main.identity.uuid
        )
        let layout = Layout(name: name, displaySetID: DisplaySet(displays.map(\.identity)).id, main: main.identity,
                            placements: placements, applyModes: withModes, autoApply: autoApply)
        try save(layout)
        return layout
    }

    // MARK: - Apply

    public func plan(_ layout: Layout) throws -> ApplyPlan {
        let displays = try displays(matching: layout)
        var modeChanges: [CGDirectDisplayID: ModeSpec] = [:]
        var sizes: [DisplayIdentity: CGSize] = [:]
        for display in displays {
            let wanted = layout.applyModes ? layout.mode(for: display.identity) : nil
            if let wanted, !(display.mode.map { $0.spec.matches(wanted) } ?? false) {
                modeChanges[display.id] = wanted
                sizes[display.identity] = CGSize(width: wanted.width, height: wanted.height)
            } else {
                sizes[display.identity] = display.bounds.size
            }
        }
        let solved: [DisplayIdentity: CGPoint]
        do {
            solved = try AnchorSolver.solve(main: layout.main, anchors: layout.localAnchors, sizes: sizes)
        } catch let error as AnchorSolverError {
            throw LayoutServiceError.solver(error)
        }
        var origins: [CGDirectDisplayID: CGPoint] = [:]
        var changed = false
        for display in displays {
            guard let origin = solved[display.identity] else { continue }
            origins[display.id] = origin
            if display.bounds.origin != origin { changed = true }
        }
        return ApplyPlan(modeChanges: modeChanges, origins: origins, originsChanged: changed,
                         remoteChanges: try pendingRemoteChanges(layout, localDisplayUUIDs: Self.uuids(of: displays)))
    }

    /// `try?` reads "cannot plan" (mismatched display set, an unsolvable
    /// anchor graph, a remote read failure, ...) as "not active": this is a
    /// boolean query, not a diagnostic, so any planning failure correctly
    /// means the layout isn't the one currently in effect.
    public func isActive(_ layout: Layout) -> Bool { (try? plan(layout))?.isNoOp ?? false }

    @discardableResult
    public func apply(_ layout: Layout) throws -> ApplyReport {
        let first = try plan(layout)
        let configurator = DisplayConfigurator(system: system)
        if !first.modeChanges.isEmpty {
            var changes: [DisplayConfigurationChange] = []
            for (id, spec) in first.modeChanges.sorted(by: { $0.key < $1.key }) {
                changes.append(.mode(id, try Self.wrap { try configurator.resolve(spec, for: id) }))
            }
            try Self.wrap { try system.apply(changes) }
        }
        let second = first.modeChanges.isEmpty ? first : try plan(layout)
        var drift: [ArrangeDrift] = []
        if second.originsChanged {
            drift = try Self.wrap { try configurator.arrange(origins: second.origins) }
        }
        let remoteResult = applyRemote(second.remoteChanges)
        // Recents are recorded last, and a failure is reported rather than
        // thrown, so a store error never leaves the hardware half-configured.
        var recentsError: LayoutServiceError?
        if !first.modeChanges.isEmpty {
            do { try recordRecents(first.modeChanges) } catch {
                recentsError = Self.serviceError(error)
            }
        }
        return ApplyReport(changedModes: first.modeChanges.keys.sorted(), arranged: second.originsChanged,
                           drift: drift, remote: remoteResult, recentsError: recentsError)
    }

    /// Remote screens whose current placement differs from the layout's
    /// anchor for them, in layout order. Reported whatever `support` is:
    /// when remote placements cannot be written, this is how the app flags
    /// a remote screen that has moved away from its anchor (spec §2.8).
    /// Empty when there is no remote adapter. Throws, like `plan`, when the
    /// online displays are not the layout's set or cannot be told apart.
    public func remoteDrift(_ layout: Layout) throws -> [RemoteScreenID] {
        let differing = try remoteDifferences(layout, localDisplayUUIDs: Self.uuids(of: displays(matching: layout)))
        return layout.placements.compactMap { placement in
            guard case let .remote(id) = placement.display, differing[id] != nil else { return nil }
            return id
        }
    }

    // MARK: - Modes, labels, preferences

    public func setMode(_ spec: ModeSpec, for displayID: CGDirectDisplayID) throws {
        try Self.wrap { _ = try DisplayConfigurator(system: system).setMode(spec, for: displayID) }
        try recordRecents([displayID: spec])
    }

    public func recentModes(for identity: DisplayIdentity) -> [ModeSpec] { document.recentModes[identity.key] ?? [] }

    public func setLabel(_ label: String?, width: Int, height: Int, refreshRate: Double?) throws {
        var labels = self.labels
        labels.set(label, width: width, height: height, refreshRate: refreshRate)
        var next = document
        next.labels = labels.overrides
        try commit(next)
    }

    public func setAutoApplyEnabled(_ enabled: Bool) throws {
        var next = document
        next.preferences.autoApplyEnabled = enabled
        try commit(next)
    }

    // MARK: - Private

    private func commit(_ next: DisplayDocument) throws {
        try Self.wrap { try store.save(next) }
        document = next
    }

    private func recordRecents(_ changes: [CGDirectDisplayID: ModeSpec]) throws {
        let identities = Dictionary(
            system.onlineDisplays().map { ($0.id, $0.identity) }, uniquingKeysWith: { first, _ in first }
        )
        var next = document
        for (id, spec) in changes {
            guard let identity = identities[id] else { continue }
            next.recentModes[identity.key] = RecentModes.recording(spec, in: next.recentModes[identity.key] ?? [])
        }
        try commit(next)
    }

    /// The online displays, refusing a set in which two share an identity:
    /// anchors are keyed by identity, so such displays would stack.
    private func distinguishableOnlineDisplays() throws -> [Display] {
        let displays = system.onlineDisplays()
        let counts = Dictionary(displays.map { ($0.identity, 1) }, uniquingKeysWith: +)
        let duplicated = counts.filter { $0.value > 1 }.keys.sorted { $0.key < $1.key }
        guard duplicated.isEmpty else { throw LayoutServiceError.ambiguousDisplays(duplicated) }
        return displays
    }

    /// The online displays, checked to be `layout`'s display set and
    /// distinguishable from each other.
    private func displays(matching layout: Layout) throws -> [Display] {
        let displays = try distinguishableOnlineDisplays()
        let actual = DisplaySet(displays.map(\.identity)).id
        guard actual == layout.displaySetID else {
            throw LayoutServiceError.displaySetMismatch(expected: layout.displaySetID, actual: actual)
        }
        return displays
    }

    private func uniqueName(_ base: String) -> String {
        var candidate = base
        var counter = 2
        while layout(named: candidate) != nil {
            candidate = "\(base) \(counter)"
            counter += 1
        }
        return candidate
    }

    /// Remote screens as placements, with their current anchor. Read failures
    /// are never swallowed: they propagate as `LayoutServiceError.remote`.
    private func remotePlacements(
        localDisplayUUIDs: Set<String>, preferredParentUUID: String?
    ) throws -> [DisplayPlacement] {
        guard let remote else { return [] }
        let current = try Self.wrap {
            try remote.placements(
                including: [], localDisplayUUIDs: localDisplayUUIDs, preferredParentUUID: { _ in preferredParentUUID }
            )
        }
        return current.map { DisplayPlacement(display: .remote($0.screen), anchor: $0.anchor, mode: nil) }
    }

    /// Remote anchors the layout wants that differ from the adapter's current
    /// placement. Unsupported adapters report no pending changes (there is
    /// nothing to write), never an error. Read failures propagate.
    private func pendingRemoteChanges(
        _ layout: Layout, localDisplayUUIDs: Set<String>
    ) throws -> [RemoteScreenID: Anchor] {
        guard let remote, case .supported = remote.support else { return [:] }
        return try remoteDifferences(layout, localDisplayUUIDs: localDisplayUUIDs)
    }

    /// Every remote anchor in the layout that differs from the current
    /// placement, whatever `support` is. Each current placement is read
    /// with the layout anchor's own parent as the preferred parent, so the
    /// two anchors compared share a parent whenever the remote screen still
    /// touches it.
    private func remoteDifferences(
        _ layout: Layout, localDisplayUUIDs: Set<String>
    ) throws -> [RemoteScreenID: Anchor] {
        guard let remote else { return [:] }
        let wanted = layout.remoteAnchors
        guard !wanted.isEmpty else { return [:] }
        let current = try Self.wrap {
            try remote.placements(
                including: Array(wanted.keys), localDisplayUUIDs: localDisplayUUIDs,
                preferredParentUUID: { id in wanted[id].flatMap(Self.parentUUID(of:)) }
            )
        }
        let currentAnchors = Dictionary(current.map { ($0.screen, $0.anchor) }) { first, _ in first }
        return wanted.filter { id, anchor in (currentAnchors[id] ?? nil) != anchor }
    }

    private static func parentUUID(of anchor: Anchor) -> String? {
        guard case let .local(identity) = anchor.parent else { return nil }
        return identity.uuid
    }

    private static func uuids(of displays: [Display]) -> Set<String> { Set(displays.compactMap(\.identity.uuid)) }

    /// Writes pending remote changes. A write failure is reported in the
    /// result rather than thrown: it surfaces to the caller either way, but
    /// local mode/arrangement changes already committed should not be undone
    /// because a remote Mac's placement failed to write.
    private func applyRemote(_ changes: [RemoteScreenID: Anchor]) -> RemoteApplyResult {
        guard let remote else { return .none }
        if case let .unsupported(reason) = remote.support { return .unsupported(reason) }
        guard !changes.isEmpty else { return .none }
        do throws(RemoteScreenError) {
            let localDisplayUUIDs = Self.uuids(of: system.onlineDisplays())
            for (id, anchor) in changes {
                try remote.setPlacement(anchor, for: id, localDisplayUUIDs: localDisplayUUIDs)
            }
            return .applied(changes.count)
        } catch {
            return .failed(error)
        }
    }

    private static func wrap<T>(_ body: () throws -> T) throws -> T {
        do { return try body() } catch { throw serviceError(error) }
    }

    /// Any error thrown inside the service as a `LayoutServiceError`.
    static func serviceError(_ error: any Error) -> LayoutServiceError {
        switch error {
        case let error as LayoutServiceError: error
        case let error as DisplayError: .display(error)
        case let error as DocumentStoreError: .store(error)
        case let error as RemoteScreenError: .remote(error)
        case let error as AnchorSolverError: .solver(error)
        case let error as AnchorCaptureError: .capture(error)
        default: .unexpected(String(describing: error))
        }
    }
}
