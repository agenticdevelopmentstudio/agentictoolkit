import CoreGraphics

/// A persistable description of a display mode: point size, refresh rate, HiDPI.
public struct ModeSpec: Hashable, Codable, Sendable, CustomStringConvertible {
    public let width: Int
    public let height: Int
    public let refreshRate: Double
    public let isHiDPI: Bool

    public init(width: Int, height: Int, refreshRate: Double, isHiDPI: Bool) {
        self.width = width
        self.height = height
        self.refreshRate = refreshRate
        self.isHiDPI = isHiDPI
    }

    /// Same size and scale; refresh rates within half a hertz (59.94 ≈ 60).
    public func matches(_ other: ModeSpec) -> Bool {
        width == other.width && height == other.height && isHiDPI == other.isHiDPI
            && abs(refreshRate - other.refreshRate) < 0.5
    }

    public var description: String {
        let hertz = refreshRate > 0 ? " \(Int(refreshRate.rounded()))Hz" : ""
        return "\(width) × \(height)\(hertz) (\(isHiDPI ? "2x" : "1x"))"
    }
}

/// Opaque wrapper for the CoreGraphics mode object (immutable CF type).
public final class DisplayModeHandle: @unchecked Sendable {
    public let mode: CGDisplayMode
    public init(_ mode: CGDisplayMode) { self.mode = mode }
}

/// One mode a display supports.
public struct DisplayMode: Equatable, Sendable {
    public let pointSize: CGSize
    public let pixelSize: CGSize
    public let refreshRate: Double
    public let isUsableForDesktopGUI: Bool
    public let ioModeID: Int32
    /// Nil for fake modes; required by `CoreGraphicsDisplaySystem.apply`.
    public let handle: DisplayModeHandle?

    public init(pointSize: CGSize, pixelSize: CGSize, refreshRate: Double,
                isUsableForDesktopGUI: Bool = true, ioModeID: Int32 = 0, handle: DisplayModeHandle? = nil) {
        self.pointSize = pointSize
        self.pixelSize = pixelSize
        self.refreshRate = refreshRate
        self.isUsableForDesktopGUI = isUsableForDesktopGUI
        self.ioModeID = ioModeID
        self.handle = handle
    }

    public init(_ mode: CGDisplayMode) {
        self.init(
            pointSize: CGSize(width: mode.width, height: mode.height),
            pixelSize: CGSize(width: mode.pixelWidth, height: mode.pixelHeight),
            refreshRate: mode.refreshRate,
            isUsableForDesktopGUI: mode.isUsableForDesktopGUI(),
            ioModeID: mode.ioDisplayModeID,
            handle: DisplayModeHandle(mode)
        )
    }

    public var isHiDPI: Bool { pixelSize.width > pointSize.width }

    public var spec: ModeSpec {
        ModeSpec(width: Int(pointSize.width), height: Int(pointSize.height), refreshRate: refreshRate, isHiDPI: isHiDPI)
    }

    public static func == (lhs: DisplayMode, rhs: DisplayMode) -> Bool {
        lhs.pointSize == rhs.pointSize && lhs.pixelSize == rhs.pixelSize && lhs.refreshRate == rhs.refreshRate
            && lhs.isUsableForDesktopGUI == rhs.isUsableForDesktopGUI && lhs.ioModeID == rhs.ioModeID
    }
}
