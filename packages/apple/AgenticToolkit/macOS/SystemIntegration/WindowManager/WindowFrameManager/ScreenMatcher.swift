import AppKit
internal import AgenticToolkitDisplays

/// Finds the best matching current screen for a saved screen fingerprint.
/// Matching rules live in `DisplayMatcher`; this keeps WindowManager's API.
public enum ScreenMatcher {

    public enum MatchQuality: Int, Comparable, Sendable {
        case positionOnly = 1
        case nameOnly = 2
        case uuidResChanged = 3
        case exact = 4

        public static func < (lhs: MatchQuality, rhs: MatchQuality) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public struct ScreenMatch {
        public let screen: ScreenInfo
        public let quality: MatchQuality
    }

    /// Finds the best current screen matching the saved fingerprint.
    public static func findBestMatch(
        for fingerprint: ScreenFingerprint,
        among screens: [ScreenInfo]
    ) -> ScreenMatch? {
        DisplayMatcher.bestMatch(for: fingerprint.matchKey, among: screens, key: { $0.fingerprint.matchKey })
            .map { ScreenMatch(screen: $0.candidate, quality: MatchQuality($0.quality)) }
    }
}

extension ScreenMatcher.MatchQuality {
    init(_ quality: DisplayMatchQuality) {
        switch quality {
        case .positionOnly: self = .positionOnly
        case .nameOnly: self = .nameOnly
        case .uuidSizeChanged: self = .uuidResChanged
        case .exact: self = .exact
        }
    }
}

extension ScreenFingerprint {
    var matchKey: DisplayMatchKey {
        DisplayMatchKey(uuid: displayUUID, name: localizedName,
                        size: CGSize(width: resolutionWidth, height: resolutionHeight), isMain: isMain)
    }
}
