import CoreGraphics

public enum AnchorCaptureError: Error, Equatable, Sendable {
    case mainMissing
    /// This display touches none of the displays already placed.
    case detached(DisplayIdentity)
}

/// The inverse of `AnchorSolver`: derives anchors from an arrangement.
public enum AnchorCapture {
    public static let snapTolerance = 0.005
    private static let touchTolerance: CGFloat = 1

    public static func capture(
        main: DisplayIdentity,
        bounds frames: [DisplayIdentity: CGRect]
    ) throws -> [DisplayIdentity: Anchor] {
        guard frames[main] != nil else { throw AnchorCaptureError.mainMissing }
        var placed: [DisplayIdentity] = [main]
        var unplaced = frames.keys.filter { $0 != main }.sorted { $0.key < $1.key }
        var anchors: [DisplayIdentity: Anchor] = [:]
        while let first = unplaced.first {
            var best: (child: DisplayIdentity, parent: DisplayIdentity, edge: DisplayEdge, length: CGFloat)?
            for parent in placed {
                for child in unplaced {
                    guard let contact = contact(child: frames[child]!, parent: frames[parent]!) else { continue }
                    if contact.length > (best?.length ?? 0) {
                        best = (child, parent, contact.edge, contact.length)
                    }
                }
            }
            guard let best else { throw AnchorCaptureError.detached(first) }
            anchors[best.child] = anchor(
                child: frames[best.child]!, parent: frames[best.parent]!,
                parentID: best.parent, edge: best.edge
            )
            placed.append(best.child)
            unplaced.removeAll { $0 == best.child }
        }
        return anchors
    }

    static func contact(child: CGRect, parent: CGRect) -> (edge: DisplayEdge, length: CGFloat)? {
        let vertical = min(child.maxY, parent.maxY) - max(child.minY, parent.minY)
        let horizontal = min(child.maxX, parent.maxX) - max(child.minX, parent.minX)
        if abs(child.maxX - parent.minX) <= touchTolerance, vertical > 0 { return (.left, vertical) }
        if abs(child.minX - parent.maxX) <= touchTolerance, vertical > 0 { return (.right, vertical) }
        if abs(child.maxY - parent.minY) <= touchTolerance, horizontal > 0 { return (.top, horizontal) }
        if abs(child.minY - parent.maxY) <= touchTolerance, horizontal > 0 { return (.bottom, horizontal) }
        return nil
    }

    private static func anchor(
        child: CGRect, parent: CGRect, parentID: DisplayIdentity, edge: DisplayEdge
    ) -> Anchor {
        let vertical = edge == .left || edge == .right
        let parentStart = Double(vertical ? parent.minY : parent.minX)
        let parentLength = Double(vertical ? parent.height : parent.width)
        let childStart = Double(vertical ? child.minY : child.minX)
        let childLength = Double(vertical ? child.height : child.width)
        let snaps = [0.0, 0.5, 1.0]
        let candidates = [0.0, 1.0, 0.5].compactMap { childFrac -> (parentF: Double, childF: Double, score: Double)? in
            let parentF = (childStart + childFrac * childLength - parentStart) / parentLength
            guard parentF >= -snapTolerance, parentF <= 1 + snapTolerance else { return nil }
            return (parentF, childFrac, snaps.map { abs(parentF - $0) }.min()!)
        }
        let chosen: (parentF: Double, childF: Double)
        // Scores that are mathematically tied (e.g. 5/2160 computed two different ways) can differ
        // by ~1e-16 of floating-point noise; an epsilon keeps the "first candidate wins ties" rule
        // from the brief instead of a strict `<` picking whichever side the noise happened to favor.
        if var best = candidates.first {
            for candidate in candidates.dropFirst() where candidate.score < best.score - 1e-9 {
                best = candidate
            }
            chosen = (best.parentF, best.childF)
        } else {
            let mid = (max(parentStart, childStart) + min(parentStart + parentLength, childStart + childLength)) / 2
            chosen = ((mid - parentStart) / parentLength, (mid - childStart) / childLength)
        }
        let snapped = Anchor(
            parent: .local(parentID), edge: edge,
            parentFraction: snap(chosen.parentF), childFraction: snap(chosen.childF)
        )
        // Snapping moves the child by up to `snapTolerance` of the edge. When
        // the real contact is shorter than that, the snap would slide the
        // child to a corner the solver rejects, so keep the exact fractions.
        guard contactAfterSolving(snapped, child: child, parent: parent) < AnchorSolver.minimumContact else {
            return snapped
        }
        return Anchor(
            parent: .local(parentID), edge: edge,
            parentFraction: clamp(chosen.parentF), childFraction: clamp(chosen.childF)
        )
    }

    private static func contactAfterSolving(_ anchor: Anchor, child: CGRect, parent: CGRect) -> CGFloat {
        let origin = AnchorSolver.place(childSize: child.size, anchor: anchor, parent: parent)
        return AnchorSolver.contactLength(CGRect(origin: origin, size: child.size), parent, edge: anchor.edge)
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }

    private static func snap(_ value: Double) -> Double {
        for target in [0.0, 0.5, 1.0] where abs(value - target) <= snapTolerance { return target }
        return clamp(value)
    }
}
