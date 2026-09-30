import CoreGraphics

/// Immutable snapshot of one connected display.
public struct Display: Equatable, Sendable, Identifiable {
    /// Session-scoped CoreGraphics id. Never persist it; persist `identity`.
    public let id: CGDirectDisplayID
    public let identity: DisplayIdentity
    public let name: String
    /// Physical size in millimetres (zero when the display doesn't report it).
    public let physicalSize: CGSize
    public let isBuiltin: Bool
    public let isMain: Bool
    /// CG global coordinates (top-left origin), points.
    public let bounds: CGRect
    /// AppKit global coordinates (bottom-left origin).
    public let frame: CGRect
    /// AppKit coordinates, minus menu bar and Dock.
    public let visibleFrame: CGRect
    public let backingScaleFactor: CGFloat
    public let mode: DisplayMode?
    public let rotation: Double

    public init(id: CGDirectDisplayID, identity: DisplayIdentity, name: String, physicalSize: CGSize,
                isBuiltin: Bool, isMain: Bool, bounds: CGRect, frame: CGRect, visibleFrame: CGRect,
                backingScaleFactor: CGFloat, mode: DisplayMode?, rotation: Double) {
        self.id = id
        self.identity = identity
        self.name = name
        self.physicalSize = physicalSize
        self.isBuiltin = isBuiltin
        self.isMain = isMain
        self.bounds = bounds
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.backingScaleFactor = backingScaleFactor
        self.mode = mode
        self.rotation = rotation
    }

    public var diagonalInches: Double? {
        guard physicalSize.width > 0, physicalSize.height > 0 else { return nil }
        return Double(hypot(physicalSize.width, physicalSize.height)) / 25.4
    }

    /// `27" External`, `Built-in`, or `External` when the size is unknown.
    public var menuLabel: String {
        if isBuiltin { return "Built-in" }
        guard let inches = diagonalInches else { return "External" }
        return "\(Int(inches.rounded()))\" External"
    }

    /// Converts a CG global rect to AppKit global coordinates, given the main display's height.
    public static func appKitRect(fromCG rect: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
