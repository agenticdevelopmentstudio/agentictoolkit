import AppKit
internal import AgenticToolkitDisplays

/// A full record of one attached screen at a moment in time: its
/// `ScreenFingerprint` (the single source of truth for screen identity,
/// shared with placement matching), plus geometry (frame + visible frame in
/// global coordinates) and display scale. Persisted inside a `ScreenSet` so
/// the app can recognize a screen arrangement it has seen before — and,
/// eventually, show the user their saved arrangements.
public struct ScreenSnapshot: Codable, Equatable, Sendable {
    /// The screen's identity (UUID / name / resolution / isMain). Reused from
    /// `WindowFrameManager`'s matching layer rather than re-declared, so
    /// identity rules live in exactly one place.
    public let fingerprint: ScreenFingerprint
    /// Full screen frame in global (bottom-left-origin) desktop coordinates.
    public let frame: CGRect
    /// Frame minus the menu bar / Dock, in the same global coordinates.
    public let visibleFrame: CGRect
    public let backingScaleFactor: CGFloat

    public var displayUUID: String? { fingerprint.displayUUID }
    public var localizedName: String? { fingerprint.localizedName }
    public var isMain: Bool { fingerprint.isMain }

    public init(
        fingerprint: ScreenFingerprint,
        frame: CGRect,
        visibleFrame: CGRect,
        backingScaleFactor: CGFloat
    ) {
        self.fingerprint = fingerprint
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.backingScaleFactor = backingScaleFactor
    }

    public init(_ screen: ScreenInfo) {
        self.init(
            fingerprint: screen.fingerprint,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            backingScaleFactor: screen.backingScaleFactor
        )
    }

    /// The identity component this screen contributes to a `ScreenSet` id.
    /// Prefers the display UUID; for a screen without one, falls back to the
    /// localized name. Deliberately **resolution-independent** — a screen set
    /// is defined by which displays are attached, not their current
    /// resolution, so a resolution change on a UUID-less display keeps the
    /// same set id (and is classified as a resolution change, not a set
    /// change).
    public var identityComponent: String {
        if let displayUUID { return displayUUID }
        return localizedName ?? "unnamed-display"
    }
}

extension ScreenSnapshot {
    var geometry: DisplayGeometry {
        DisplayGeometry(identityComponent: identityComponent, frame: frame, visibleFrame: visibleFrame)
    }
}
