import CoreGraphics

public struct DisplayMatchKey: Equatable, Sendable {
    public let uuid: String?
    public let name: String?
    public let size: CGSize
    public let isMain: Bool

    public init(uuid: String?, name: String?, size: CGSize, isMain: Bool) {
        self.uuid = uuid
        self.name = name
        self.size = size
        self.isMain = isMain
    }
}

public enum DisplayMatchQuality: Int, Comparable, Sendable {
    case positionOnly = 1
    case nameOnly = 2
    case uuidSizeChanged = 3
    case exact = 4

    public static func < (lhs: DisplayMatchQuality, rhs: DisplayMatchQuality) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Layered matching: UUID (+size) → name → "was main, is main".
public enum DisplayMatcher {
    public static func bestMatch<Candidate>(
        for saved: DisplayMatchKey,
        among candidates: [Candidate],
        key keyOf: (Candidate) -> DisplayMatchKey
    ) -> (candidate: Candidate, quality: DisplayMatchQuality)? {
        var scored: [(Candidate, DisplayMatchQuality)] = []
        for candidate in candidates {
            if let quality = quality(of: keyOf(candidate), against: saved) { scored.append((candidate, quality)) }
        }
        return scored.max { $0.1 < $1.1 }.map { (candidate: $0.0, quality: $0.1) }
    }

    static func quality(of current: DisplayMatchKey, against saved: DisplayMatchKey) -> DisplayMatchQuality? {
        if let savedUUID = saved.uuid, let currentUUID = current.uuid, savedUUID == currentUUID {
            let sameSize = abs(current.size.width - saved.size.width) < 1
                && abs(current.size.height - saved.size.height) < 1
            return sameSize ? .exact : .uuidSizeChanged
        }
        if let savedName = saved.name, let currentName = current.name, savedName == currentName { return .nameOnly }
        if saved.isMain && current.isMain { return .positionOnly }
        return nil
    }
}
