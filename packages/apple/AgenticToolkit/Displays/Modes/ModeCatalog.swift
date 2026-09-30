import CoreGraphics

/// A display's modes as the menu shows them: Retina (2x) and Standard (1x),
/// exact duplicates removed, largest first, then highest refresh first.
public struct ModeCatalog: Equatable, Sendable {
    public let retina: [DisplayMode]
    public let standard: [DisplayMode]

    public init(modes: [DisplayMode], includeUnusable: Bool = false) {
        var seen = Set<ModeSpec>()
        let unique = modes
            .filter { includeUnusable || $0.isUsableForDesktopGUI }
            .sorted(by: Self.largestFirst)
            .filter { seen.insert($0.spec).inserted }
        retina = unique.filter(\.isHiDPI)
        standard = unique.filter { !$0.isHiDPI }
    }

    @MainActor
    public static func modes(for displayID: CGDirectDisplayID, in system: DisplaySystem,
                             includeUnusable: Bool = false) -> ModeCatalog {
        ModeCatalog(modes: system.modes(for: displayID), includeUnusable: includeUnusable)
    }

    public var all: [DisplayMode] { retina + standard }

    private static func largestFirst(_ lhs: DisplayMode, _ rhs: DisplayMode) -> Bool {
        if lhs.pointSize.width != rhs.pointSize.width { return lhs.pointSize.width > rhs.pointSize.width }
        if lhs.pointSize.height != rhs.pointSize.height { return lhs.pointSize.height > rhs.pointSize.height }
        if lhs.refreshRate != rhs.refreshRate { return lhs.refreshRate > rhs.refreshRate }
        return lhs.pixelSize.width > rhs.pixelSize.width
    }
}
