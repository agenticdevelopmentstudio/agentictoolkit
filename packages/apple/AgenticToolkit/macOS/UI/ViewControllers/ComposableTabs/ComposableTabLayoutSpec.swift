import AppKit
import Foundation
import AgenticToolkitCore

/// How many of one view a region may hold, and which way it prefers to be added.
public struct ComposableTabsViewAllowance: Sendable {

    public var viewID: ComposableTabsViewID
    /// Fewest instances the region should hold. `0` means the view is optional.
    public var min: Int
    /// Most instances the region may hold. `nil` is unbounded.
    public var max: Int?
    /// Overrides the registry descriptor's `preferredAxis` for this region.
    /// A *default direction only*: it decides which way the Split menu offers
    /// the view first, and does not forbid the other axis.
    public var preferredAxis: ComposableTabsAxis?

    public init(
        _ viewID: ComposableTabsViewID,
        min: Int = 0,
        max: Int? = 1,
        preferredAxis: ComposableTabsAxis? = nil
    ) {
        self.viewID = viewID
        self.min = min
        self.max = max
        self.preferredAxis = preferredAxis
    }

    public static func unbounded(
        _ viewID: ComposableTabsViewID,
        min: Int = 0,
        preferredAxis: ComposableTabsAxis? = nil
    ) -> Self {
        .init(viewID, min: min, max: nil, preferredAxis: preferredAxis)
    }
}

public enum ComposableTabLayoutSpecError: Error, CustomStringConvertible, Equatable {
    case unregisteredView(ComposableTabsViewID)
    case nodeAllowsNothing
    case invalidCardinality(ComposableTabsViewID, min: Int, max: Int)
    case initialViewNotAllowed(ComposableTabsViewID)
    case splitWithoutChildren

    public var description: String {
        switch self {
        case .unregisteredView(let id):
            return "layout spec names \(id.rawValue), which is not in the registry"
        case .nodeAllowsNothing:
            return "layout spec has a region that allows no views"
        case .invalidCardinality(let id, let min, let max):
            return "layout spec allows \(id.rawValue) min: \(min) max: \(max)"
        case .initialViewNotAllowed(let id):
            return "layout spec starts a pane with \(id.rawValue), which that pane does not allow"
        case .splitWithoutChildren:
            return "layout spec has a split with no children"
        }
    }
}

/// The whole layout contract for a tab: the arrangement it starts in, and the
/// arrangements the user may reach from there.
///
/// Structured as a struct wrapping a `Kind`, matching `LayoutNode` — the value
/// type it describes — so both trees read the same way and both can grow a
/// per-node field without churning every case pattern.
///
/// ## How a spec maps onto a live tree
///
/// The spec is a *template*, and the live tree diverges from it as soon as the
/// user splits a pane. The two are walked in parallel from the root: a spec
/// `.split` lines its `children[0]`/`children[1]` up with the live split's two
/// halves, and where the live tree is deeper than the template, everything
/// below stays governed by the spec node it grew out of. A live leaf's
/// **effective allowances** are the merged `allows` of its spec chain, root
/// first, with the nearest declaration winning; `isFixed` is true if any node
/// in that chain sets it.
///
/// Cardinality is counted **within the subtree the declaring node governs**, so
/// `max: 1` on the root caps a view for the whole tab while the same allowance
/// on one side of a split caps only that side.
public struct ComposableTabLayoutSpec: Sendable {

    public indirect enum Kind: Sendable {
        case split(axis: ComposableTabsAxis, children: [ComposableTabLayoutSpec])
        case pane(initial: ComposableTabsViewID?)
    }

    public var kind: Kind
    /// Views this region may hold. Inherited by descendants that don't restate
    /// them; an empty list on a `.pane` means "whatever an ancestor allows".
    public var allows: [ComposableTabsViewAllowance]
    /// A region the user may neither remove nor split. Applies to descendants.
    public var isFixed: Bool

    public init(
        kind: Kind,
        allows: [ComposableTabsViewAllowance] = [],
        isFixed: Bool = false
    ) {
        self.kind = kind
        self.allows = allows
        self.isFixed = isFixed
    }

    public static func split(
        axis: ComposableTabsAxis,
        children: [ComposableTabLayoutSpec],
        allows: [ComposableTabsViewAllowance] = [],
        isFixed: Bool = false
    ) -> Self {
        .init(kind: .split(axis: axis, children: children), allows: allows, isFixed: isFixed)
    }

    public static func pane(
        _ initial: ComposableTabsViewID? = nil,
        allows: [ComposableTabsViewAllowance] = [],
        isFixed: Bool = false
    ) -> Self {
        .init(kind: .pane(initial: initial), allows: allows, isFixed: isFixed)
    }

    /// The two-placeholder split every document fell back to before an app
    /// installed a layout of its own.
    public static let placeholders = ComposableTabLayoutSpec.split(
        axis: .horizontal,
        children: [.pane(.placeholder), .pane(.placeholder)],
        allows: [.unbounded(.placeholder)]
    )

    // MARK: - Validation

    /// Checks the spec against the registry it will be used with, once, at
    /// install time — so a malformed spec fails at launch rather than on the
    /// user gesture that first consults it (`fail-fast`).
    @MainActor
    public func validate(against registry: ComposableTabsViewRegistry) throws {
        try validate(against: registry, inherited: [:])
    }

    @MainActor
    private func validate(
        against registry: ComposableTabsViewRegistry,
        inherited: [ComposableTabsViewID: ComposableTabsViewAllowance]
    ) throws {
        var effective = inherited
        for allowance in allows {
            guard registry.isRegistered(allowance.viewID) else {
                throw ComposableTabLayoutSpecError.unregisteredView(allowance.viewID)
            }
            if let max = allowance.max, allowance.min > max {
                throw ComposableTabLayoutSpecError.invalidCardinality(
                    allowance.viewID, min: allowance.min, max: max)
            }
            effective[allowance.viewID] = allowance
        }

        switch kind {
        case .split(_, let children):
            guard !children.isEmpty else { throw ComposableTabLayoutSpecError.splitWithoutChildren }
            for child in children {
                try child.validate(against: registry, inherited: effective)
            }
        case .pane(let initial):
            guard !effective.isEmpty else { throw ComposableTabLayoutSpecError.nodeAllowsNothing }
            if let initial {
                guard registry.isRegistered(initial) else {
                    throw ComposableTabLayoutSpecError.unregisteredView(initial)
                }
                guard effective[initial] != nil else {
                    throw ComposableTabLayoutSpecError.initialViewNotAllowed(initial)
                }
            }
        }
    }

    // MARK: - Widening

    /// This spec with one unbounded allowance added to its root for each
    /// contributed view.
    ///
    /// `validate(against:)` only checks that the ids a spec *names* are
    /// registered — never the reverse — so a view an extension registers but no
    /// allowance names is registered and unplaceable. Unbounded rather than
    /// `max: 1`: an extension view is auxiliary, and capping it would stop a
    /// user opening the same view in two panes for no reason the host can
    /// justify.
    ///
    /// A pure function on the spec, so the host app's wiring site — which no
    /// toolkit test can reach — is not the only place this can be exercised.
    public func widened(for views: [ContributedView]) -> Self {
        guard !views.isEmpty else { return self }
        var widened = self
        widened.allows += views.map { view in
            .unbounded(
                ComposableTabsViewID(view.registryID),
                preferredAxis: view.preferredAxisIsVertical ? .vertical : .horizontal
            )
        }
        return widened
    }

    // MARK: - Blueprint

    /// The `LayoutNode` a brand-new tab starts with.
    ///
    /// A split with more than two children becomes a right-leaning chain of
    /// binary splits, because that is the only shape the storage tree and the
    /// split-view controller have.
    public func blueprint() -> LayoutNode {
        switch kind {
        case .pane(let initial):
            return LayoutNode.leaf(contentType: initial ?? firstAllowedView() ?? .placeholder)
        case .split(let axis, let children):
            return Self.chain(children.map { $0.blueprint() }, axis: axis)
        }
    }

    private func firstAllowedView() -> ComposableTabsViewID? {
        allows.first(where: { $0.min > 0 })?.viewID ?? allows.first?.viewID
    }

    private static func chain(_ nodes: [LayoutNode], axis: ComposableTabsAxis) -> LayoutNode {
        switch nodes.count {
        case 0:
            return LayoutNode.leaf(contentType: .placeholder)
        case 1:
            return nodes[0]
        default:
            return LayoutNode.split(
                orientation: axis,
                first: nodes[0],
                second: chain(Array(nodes.dropFirst()), axis: axis)
            )
        }
    }

    // MARK: - Legal moves

    /// One entry in a pane's Split menu: a view that may be added here, and the
    /// direction to offer first.
    public struct Insertion: Sendable, Equatable {
        public let viewID: ComposableTabsViewID
        public let preferredAxis: ComposableTabsAxis
    }

    /// Views that may be added beside `leafID`, honouring every `max` in scope.
    /// Empty when the leaf sits in a fixed region.
    @MainActor
    public func allowedInsertions(
        at leafID: UUID,
        in tree: LayoutNode,
        registry: ComposableTabsViewRegistry
    ) -> [Insertion] {
        let resolution = Resolution(spec: self, tree: tree)
        guard let chain = resolution.chain(forLeaf: leafID), !resolution.isFixed(leaf: leafID) else {
            return []
        }
        return resolution.effectiveAllowances(for: chain)
            .filter { path, allowance in
                guard let max = allowance.max else { return true }
                return resolution.count(allowance.viewID, under: path, in: tree) < max
            }
            .map { _, allowance in
                Insertion(
                    viewID: allowance.viewID,
                    preferredAxis: allowance.preferredAxis
                        ?? registry.descriptor(for: allowance.viewID).preferredAxis
                )
            }
            .sorted { $0.viewID.rawValue < $1.viewID.rawValue }
    }

    /// The allowance governing `viewID` at `leafID`, or `nil` when the view is
    /// not allowed there. What a pane shows about itself comes from here.
    public func allowance(
        for viewID: ComposableTabsViewID,
        at leafID: UUID,
        in tree: LayoutNode
    ) -> ComposableTabsViewAllowance? {
        let resolution = Resolution(spec: self, tree: tree)
        guard let chain = resolution.chain(forLeaf: leafID) else { return nil }
        return resolution.effectiveAllowances(for: chain).first { $0.1.viewID == viewID }?.1
    }

    /// Whether `leafID` sits in a region the user may neither split nor remove.
    public func isFixed(_ leafID: UUID, in tree: LayoutNode) -> Bool {
        Resolution(spec: self, tree: tree).isFixed(leaf: leafID)
    }

    /// False when the leaf or an ancestor is fixed, when it is the tab's last
    /// pane, or when removing it would drop a view below its `min`.
    public func canRemove(_ leafID: UUID, from tree: LayoutNode) -> Bool {
        let resolution = Resolution(spec: self, tree: tree)
        guard let chain = resolution.chain(forLeaf: leafID), !resolution.isFixed(leaf: leafID) else {
            return false
        }
        guard Self.leaves(in: tree).count > 1 else { return false }
        guard let viewID = Self.viewID(ofLeaf: leafID, in: tree) else { return false }
        for (path, allowance) in resolution.effectiveAllowances(for: chain)
        where allowance.viewID == viewID && allowance.min > 0 {
            if resolution.count(viewID, under: path, in: tree) <= allowance.min { return false }
        }
        return true
    }

    /// A fixed region cannot gain panes either — splitting it would create one.
    public func canSplit(_ leafID: UUID, in tree: LayoutNode) -> Bool {
        !Resolution(spec: self, tree: tree).isFixed(leaf: leafID)
    }

    // MARK: - Reconciliation

    /// The load-time repair pass. A stored tree can outlive the spec that made
    /// it — an app ships a tighter `max`, drops a view, or renames one — and a
    /// tree that contradicts its spec would let the user reach states the spec
    /// forbids. Offending leaves become placeholders rather than being deleted,
    /// because the shape of the layout is the user's and the content is ours.
    ///
    /// The repair runs both ways: a view the spec no longer allows is demoted,
    /// and a view it *requires* and the tree does not have is added.
    public func reconcile(_ tree: LayoutNode) -> LayoutNode {
        let demoted = demotedLeaves(in: tree)
        let trimmed = demoted.isEmpty ? tree : Self.demoting(tree, leaves: demoted)
        return addingRequiredViews(to: trimmed)
    }

    /// The other half of the repair: a `min` the stored tree does not meet is
    /// met, by adding the view where this spec's own blueprint puts it.
    ///
    /// This is what carries a layout across a release that makes a pane
    /// mandatory. A window stored before the Document pane existed comes back
    /// with one, beside the panes it was stored with rather than instead of
    /// them, and every pane already there keeps the share of the window it had.
    ///
    /// Only a `min` declared on the spec's **root** is repaired, and only along
    /// the root's own axis. A `min` on one side of a split says how many that
    /// side must hold, and nothing in the spec says which of the live tree's
    /// nodes below it should be the one to gain a pane — inventing an answer
    /// would move panes the user arranged (`principle-of-least-astonishment`).
    private func addingRequiredViews(to tree: LayoutNode) -> LayoutNode {
        guard case .split(let axis, _) = kind else { return tree }
        let required = allows.filter { $0.min > 0 }
        guard !required.isEmpty else { return tree }

        let order = Self.leafViewIDs(in: blueprint())
        var segments = Self.chainSegments(of: tree, along: axis)
        var added = false
        for allowance in required {
            while Self.count(allowance.viewID, in: segments) < allowance.min {
                let index = Self.insertionIndex(
                    for: allowance.viewID, among: segments, blueprintOrder: order)
                // No fraction: a pane nobody has sized takes the share its
                // registration asks for, which is the same share it would have
                // had in a window opened fresh today.
                segments.insert(.leaf(contentType: allowance.viewID), at: index)
                added = true
            }
        }
        guard added else { return tree }
        return Self.chain(segments, axis: axis)
    }

    /// The views a chain of same-axis splits is made of, left to right.
    ///
    /// A tree the user has rearranged can lean either way — a pane split off
    /// the left half nests to the left — so both halves are flattened, and what
    /// comes back is the row as the eye reads it. The spine's own nodes are
    /// dropped: `chain(_:axis:)` puts an equivalent one back, and a split node
    /// carries nothing but the slot it sits in, which its segments carry
    /// themselves.
    private static func chainSegments(
        of node: LayoutNode,
        along axis: ComposableTabsAxis
    ) -> [LayoutNode] {
        guard case .split(let orientation, let first, let second) = node.kind,
              orientation == axis else { return [node] }
        return chainSegments(of: first, along: axis) + chainSegments(of: second, along: axis)
    }

    /// Where a view belongs in a row that is missing it: after the last view
    /// the blueprint puts before it, and otherwise at the front. So a stored
    /// layout of browser · notes gains its Document pane between the two,
    /// exactly where a window opened today would have it.
    private static func insertionIndex(
        for viewID: ComposableTabsViewID,
        among segments: [LayoutNode],
        blueprintOrder: [ComposableTabsViewID]
    ) -> Int {
        guard let position = blueprintOrder.firstIndex(of: viewID) else { return segments.count }
        let precedents = Set(blueprintOrder[..<position])
        let last = segments.lastIndex { segment in
            !leafViewIDs(in: segment).filter(precedents.contains).isEmpty
        }
        return last.map { $0 + 1 } ?? 0
    }

    private static func leafViewIDs(in node: LayoutNode) -> [ComposableTabsViewID] {
        leaves(in: node).compactMap { leaf in
            guard case .leaf(let contentType, _) = leaf.kind else { return nil }
            return contentType
        }
    }

    private static func count(_ viewID: ComposableTabsViewID, in segments: [LayoutNode]) -> Int {
        segments.reduce(0) { $0 + leafViewIDs(in: $1).filter { $0 == viewID }.count }
    }

    /// Whether there is nothing in `tree` for `reconcile(_:)` to demote.
    ///
    /// The question a rearrangement has to ask before it commits: moving a pane
    /// can land it in a region whose spec does not allow that view, and a tree
    /// the user is looking at which the next load will gut is worse than an
    /// arrow that was never offered (`fail-fast`).
    ///
    /// Deliberately silent about the other half of the repair. A move carries a
    /// pane from one slot to another and changes no count, so a tree that met
    /// every `min` before a move still meets it after — the only way to fail
    /// one is to remove a pane, which `canRemove(_:from:)` already refuses.
    public func allows(_ tree: LayoutNode) -> Bool {
        demotedLeaves(in: tree).isEmpty
    }

    /// The leaves `reconcile(_:)` would turn into placeholders.
    private func demotedLeaves(in tree: LayoutNode) -> Set<UUID> {
        let resolution = Resolution(spec: self, tree: tree)
        var budget: [ResolutionPath: [ComposableTabsViewID: Int]] = [:]
        var demoted: Set<UUID> = []

        for leafID in Self.leaves(in: tree).map(\.id) {
            guard let chain = resolution.chain(forLeaf: leafID),
                  let viewID = Self.viewID(ofLeaf: leafID, in: tree),
                  viewID != .placeholder else { continue }
            let allowances = resolution.effectiveAllowances(for: chain)
            guard let match = allowances.first(where: { $0.1.viewID == viewID }) else {
                demoted.insert(leafID)
                continue
            }
            guard let max = match.1.max else { continue }
            let used = budget[match.0, default: [:]][viewID, default: 0]
            if used >= max {
                demoted.insert(leafID)
            } else {
                budget[match.0, default: [:]][viewID] = used + 1
            }
        }

        return demoted
    }

    private static func demoting(_ node: LayoutNode, leaves: Set<UUID>) -> LayoutNode {
        switch node.kind {
        case .leaf(_, let paneLabel):
            guard leaves.contains(node.id) else { return node }
            return LayoutNode(
                id: node.id,
                kind: .leaf(contentType: .placeholder, paneLabel: paneLabel),
                thicknessFraction: node.thicknessFraction
            )
        case .split(let orientation, let first, let second):
            return LayoutNode(
                id: node.id,
                kind: .split(
                    orientation: orientation,
                    first: demoting(first, leaves: leaves),
                    second: demoting(second, leaves: leaves)
                ),
                thicknessFraction: node.thicknessFraction
            )
        }
    }

    // MARK: - Tree helpers

    static func leaves(in node: LayoutNode) -> [LayoutNode] {
        switch node.kind {
        case .leaf:
            return [node]
        case .split(_, let first, let second):
            return leaves(in: first) + leaves(in: second)
        }
    }

    static func viewID(ofLeaf leafID: UUID, in node: LayoutNode) -> ComposableTabsViewID? {
        leaves(in: node).first(where: { $0.id == leafID }).flatMap {
            if case .leaf(let contentType, _) = $0.kind { return contentType }
            return nil
        }
    }
}

// MARK: - Spec ↔ tree resolution

/// Position of a spec node in the spec tree — the identity cardinality is
/// counted against, since spec nodes are values and have no reference identity.
typealias ResolutionPath = [Int]

/// The parallel walk of spec and live tree described on
/// `ComposableTabLayoutSpec`. Built per query: these trees are a handful of
/// nodes, and caching one would need invalidating on every split.
private struct Resolution {

    private var chainsByLeafID: [UUID: [(path: ResolutionPath, spec: ComposableTabLayoutSpec)]] = [:]
    private var leafIDsByPath: [ResolutionPath: Set<UUID>] = [:]

    init(spec: ComposableTabLayoutSpec, tree: LayoutNode) {
        walk(tree, spec: spec, path: [], chain: [])
    }

    private mutating func walk(
        _ node: LayoutNode,
        spec: ComposableTabLayoutSpec,
        path: ResolutionPath,
        chain: [(path: ResolutionPath, spec: ComposableTabLayoutSpec)]
    ) {
        let extended = chain + [(path, spec)]
        for (ancestorPath, _) in extended {
            leafIDsByPath[ancestorPath, default: []].formUnion(ComposableTabLayoutSpec.leaves(in: node).map(\.id))
        }

        switch node.kind {
        case .leaf:
            chainsByLeafID[node.id] = extended
        case .split(_, let first, let second):
            if case .split(let axis, let children) = spec.kind, children.count >= 2 {
                walk(first, spec: children[0], path: path + [0], chain: extended)
                // `blueprint()` right-chains three or more children into the
                // binary shape the live tree has, so the *second* half of a
                // split with a tail is the rest of the chain — not `children[1]`
                // alone. Pairing it with `children[1]` handed that pane's rules
                // to every node in the tail (`dry` — one description of the
                // chaining, mirrored here rather than restated differently).
                let tail = children.count == 2
                    ? children[1]
                    : ComposableTabLayoutSpec.split(axis: axis, children: Array(children.dropFirst()))
                walk(second, spec: tail, path: path + [1], chain: extended)
            } else {
                // The live tree grew past the template: everything below stays
                // governed by the spec node it grew out of.
                walk(first, spec: spec, path: path, chain: chain)
                walk(second, spec: spec, path: path, chain: chain)
            }
        }
    }

    func chain(forLeaf leafID: UUID) -> [(path: ResolutionPath, spec: ComposableTabLayoutSpec)]? {
        chainsByLeafID[leafID]
    }

    func isFixed(leaf leafID: UUID) -> Bool {
        chainsByLeafID[leafID]?.contains { $0.spec.isFixed } ?? false
    }

    /// Merged root-first, nearest declaration winning, each paired with the
    /// path of the node that declared it — which is the subtree its `max`
    /// counts over.
    func effectiveAllowances(
        for chain: [(path: ResolutionPath, spec: ComposableTabLayoutSpec)]
    ) -> [(ResolutionPath, ComposableTabsViewAllowance)] {
        var merged: [ComposableTabsViewID: (ResolutionPath, ComposableTabsViewAllowance)] = [:]
        var order: [ComposableTabsViewID] = []
        for (path, spec) in chain {
            for allowance in spec.allows {
                if merged[allowance.viewID] == nil { order.append(allowance.viewID) }
                merged[allowance.viewID] = (path, allowance)
            }
        }
        return order.compactMap { merged[$0] }
    }

    func count(_ viewID: ComposableTabsViewID, under path: ResolutionPath, in tree: LayoutNode) -> Int {
        guard let ids = leafIDsByPath[path] else { return 0 }
        return ComposableTabLayoutSpec.leaves(in: tree).filter { leaf in
            guard ids.contains(leaf.id), case .leaf(let contentType, _) = leaf.kind else { return false }
            return contentType == viewID
        }.count
    }
}
