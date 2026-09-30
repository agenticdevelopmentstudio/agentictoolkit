import CoreGraphics

/// The geometry a change classification needs, independent of any screen type.
public struct DisplayGeometry: Equatable, Sendable {
    public let identityComponent: String
    public let frame: CGRect
    public let visibleFrame: CGRect

    public init(identityComponent: String, frame: CGRect, visibleFrame: CGRect) {
        self.identityComponent = identityComponent
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

public enum DisplayChange: Equatable, Sendable {
    case resolutionChanged
    case arrangementChanged
    case displaySetChanged(previous: String, current: String)

    /// Sorted identity components joined with "+". Duplicates are kept.
    public static func setID(of displays: [DisplayGeometry]) -> String {
        displays.map(\.identityComponent).sorted().joined(separator: "+")
    }

    /// Nil when nothing actually changed. Geometry is compared as unordered
    /// multisets so indistinguishable displays never mis-pair.
    public static func classify(from old: [DisplayGeometry], to new: [DisplayGeometry]) -> DisplayChange? {
        let oldID = setID(of: old)
        let newID = setID(of: new)
        guard oldID == newID else { return .displaySetChanged(previous: oldID, current: newID) }
        if sizes(old) != sizes(new) { return .resolutionChanged }
        if origins(old) != origins(new) { return .arrangementChanged }
        return nil
    }

    private static func sizes(_ displays: [DisplayGeometry]) -> [String: Int] {
        multiset(displays.flatMap { [$0.frame.size, $0.visibleFrame.size].map { "\($0.width)x\($0.height)" } })
    }

    private static func origins(_ displays: [DisplayGeometry]) -> [String: Int] {
        multiset(displays.flatMap { [$0.frame.origin, $0.visibleFrame.origin].map { "\($0.x),\($0.y)" } })
    }

    private static func multiset(_ keys: [String]) -> [String: Int] {
        Dictionary(keys.map { ($0, 1) }, uniquingKeysWith: +)
    }
}
