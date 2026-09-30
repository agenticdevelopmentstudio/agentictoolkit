import AppKit
internal import AgenticToolkitDisplays

/// Identifies a screen across app relaunches using layered matching.
public struct ScreenFingerprint: Codable, Equatable, Sendable {
    public let displayUUID: String?
    public let localizedName: String?
    public let resolutionWidth: CGFloat
    public let resolutionHeight: CGFloat
    public let isMain: Bool

    public init(
        displayUUID: String?,
        localizedName: String?,
        resolutionWidth: CGFloat,
        resolutionHeight: CGFloat,
        isMain: Bool
    ) {
        self.displayUUID = displayUUID
        self.localizedName = localizedName
        self.resolutionWidth = resolutionWidth
        self.resolutionHeight = resolutionHeight
        self.isMain = isMain
    }

    /// Creates a fingerprint for a real NSScreen.
    public static func from(_ screen: NSScreen) -> ScreenFingerprint {
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        return ScreenFingerprint(
            displayUUID: displayID.flatMap(DisplayIdentity.uuidString(for:)),
            localizedName: screen.localizedName,
            resolutionWidth: screen.frame.width,
            resolutionHeight: screen.frame.height,
            isMain: screen == NSScreen.main
        )
    }
}
