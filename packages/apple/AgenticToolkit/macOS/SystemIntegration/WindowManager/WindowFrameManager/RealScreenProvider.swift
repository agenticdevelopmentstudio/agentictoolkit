import AppKit

/// Wraps NSScreen to conform to ScreenInfo.
/// Identity comes from AgenticToolkitDisplays (see ScreenFingerprint.from).
public struct RealScreenInfo: ScreenInfo {
    public let screen: NSScreen

    public init(screen: NSScreen) {
        self.screen = screen
    }

    public var frame: NSRect { screen.frame }
    public var visibleFrame: NSRect { screen.visibleFrame }
    public var backingScaleFactor: CGFloat { screen.backingScaleFactor }

    public var fingerprint: ScreenFingerprint {
        ScreenFingerprint.from(screen)
    }
}

/// Provides real NSScreen data.
public struct RealScreenProvider: ScreenProvider {
    public init() {}

    public var screens: [ScreenInfo] {
        NSScreen.screens.map { RealScreenInfo(screen: $0) }
    }

    public var mainScreen: ScreenInfo? {
        NSScreen.main.map { RealScreenInfo(screen: $0) }
    }
}
