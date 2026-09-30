import CoreGraphics

public enum AnchorSolverError: Error, Equatable, Sendable {
    case mainNotConnected(DisplayIdentity)
    case unanchored(DisplayIdentity)
    case missingParent(child: DisplayIdentity, parent: DisplayRef)
    case cycle([DisplayIdentity])
    case invalidFraction(DisplayIdentity)
    case overlap(DisplayIdentity, DisplayIdentity)
    /// The child meets its parent at a corner only: less than
    /// `AnchorSolver.minimumContact` of the shared edge overlaps.
    case noContact(DisplayIdentity)
}

/// Turns anchors + current point sizes into CG origins. Pure; fails fast.
public enum AnchorSolver {
    /// How much of the shared edge a child must overlap its parent by, in
    /// points. macOS needs real edge contact; a corner-only touch detaches.
    public static let minimumContact: CGFloat = 1

    /// - Parameters:
    ///   - main: placed at (0,0); its own anchor, if any, is ignored.
    ///   - anchors: local children only (remote screens are not in CG space).
    ///   - sizes: point size of every connected local display.
    public static func solve(
        main: DisplayIdentity,
        anchors: [DisplayIdentity: Anchor],
        sizes: [DisplayIdentity: CGSize]
    ) throws -> [DisplayIdentity: CGPoint] {
        guard let mainSize = sizes[main] else { throw AnchorSolverError.mainNotConnected(main) }
        let others = sizes.keys.filter { $0 != main }.sorted { $0.key < $1.key }
        let parents = try validatedParents(of: others, anchors: anchors, sizes: sizes)
        var rects: [DisplayIdentity: CGRect] = [main: CGRect(origin: .zero, size: mainSize)]
        var pending = others
        while !pending.isEmpty {
            let ready = pending.filter { rects[parents[$0]!] != nil }
            guard !ready.isEmpty else { throw AnchorSolverError.cycle(pending) }
            for child in ready {
                let parent = rects[parents[child]!]!
                let origin = place(childSize: sizes[child]!, anchor: anchors[child]!, parent: parent)
                let rect = CGRect(origin: origin, size: sizes[child]!)
                guard contactLength(rect, parent, edge: anchors[child]!.edge) >= minimumContact else {
                    throw AnchorSolverError.noContact(child)
                }
                rects[child] = rect
            }
            pending.removeAll { rects[$0] != nil }
        }
        try checkOverlaps(rects)
        return rects.mapValues(\.origin)
    }

    public static func place(childSize: CGSize, anchor: Anchor, parent: CGRect) -> CGPoint {
        let parentT = CGFloat(anchor.parentFraction)
        let childT = CGFloat(anchor.childFraction)
        let alongY = parent.minY + parentT * parent.height - childT * childSize.height
        let alongX = parent.minX + parentT * parent.width - childT * childSize.width
        let point: CGPoint
        switch anchor.edge {
        case .left: point = CGPoint(x: parent.minX - childSize.width, y: alongY)
        case .right: point = CGPoint(x: parent.maxX, y: alongY)
        case .top: point = CGPoint(x: alongX, y: parent.minY - childSize.height)
        case .bottom: point = CGPoint(x: alongX, y: parent.maxY)
        }
        return CGPoint(x: point.x.rounded(), y: point.y.rounded())
    }

    /// Length of the stretch of `edge` that `child` and `parent` share.
    static func contactLength(_ child: CGRect, _ parent: CGRect, edge: DisplayEdge) -> CGFloat {
        switch edge {
        case .left, .right: return min(child.maxY, parent.maxY) - max(child.minY, parent.minY)
        case .top, .bottom: return min(child.maxX, parent.maxX) - max(child.minX, parent.minX)
        }
    }

    private static func validatedParents(
        of children: [DisplayIdentity],
        anchors: [DisplayIdentity: Anchor],
        sizes: [DisplayIdentity: CGSize]
    ) throws -> [DisplayIdentity: DisplayIdentity] {
        var parents: [DisplayIdentity: DisplayIdentity] = [:]
        for child in children {
            guard let anchor = anchors[child] else { throw AnchorSolverError.unanchored(child) }
            guard (0...1).contains(anchor.parentFraction), (0...1).contains(anchor.childFraction) else {
                throw AnchorSolverError.invalidFraction(child)
            }
            guard case let .local(parent) = anchor.parent, sizes[parent] != nil, parent != child else {
                throw AnchorSolverError.missingParent(child: child, parent: anchor.parent)
            }
            parents[child] = parent
        }
        return parents
    }

    private static func checkOverlaps(_ rects: [DisplayIdentity: CGRect]) throws {
        let ordered = rects.keys.sorted { $0.key < $1.key }
        for (index, first) in ordered.enumerated() {
            for second in ordered[(index + 1)...] {
                let shared = rects[first]!.intersection(rects[second]!)
                if !shared.isNull, shared.width > 0.5, shared.height > 0.5 {
                    throw AnchorSolverError.overlap(first, second)
                }
            }
        }
    }
}
