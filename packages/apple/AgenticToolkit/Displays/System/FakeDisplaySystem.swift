import CoreGraphics
import Foundation

/// In-memory `DisplaySystem` for tests and previews. Ships in the framework
/// (not the test bundle) because downstream test targets need it too.
@MainActor
public final class FakeDisplaySystem: DisplaySystem {
    public private(set) var displays: [Display]
    public var modesByDisplay: [CGDirectDisplayID: [DisplayMode]]
    /// When set, the next `apply` throws this error and changes nothing.
    public var failNextApply: DisplayError?
    /// Every successful `apply` batch, in order.
    public private(set) var appliedBatches: [[DisplayConfigurationChange]] = []
    /// Simulates macOS nudging a requested origin (e.g. snapping to an edge).
    public var originAdjustment: (CGDirectDisplayID, CGPoint) -> CGPoint = { $1 }
    private var observers: [UUID: @MainActor () -> Void] = [:]
    /// Exposed for tests only: how many reconfiguration observers are live.
    var observerCount: Int { observers.count }

    public init(displays: [Display], modes: [CGDirectDisplayID: [DisplayMode]] = [:]) {
        self.displays = displays
        self.modesByDisplay = modes
    }

    public func onlineDisplays() -> [Display] { displays }
    public func modes(for displayID: CGDirectDisplayID) -> [DisplayMode] { modesByDisplay[displayID] ?? [] }

    public func apply(_ changes: [DisplayConfigurationChange]) throws {
        if let failure = failNextApply {
            failNextApply = nil
            throw failure
        }
        var next = displays
        for change in changes {
            switch change {
            case let .origin(id, point):
                guard let index = next.firstIndex(where: { $0.id == id }) else {
                    throw DisplayError.displayNotFound(id)
                }
                next[index] = Self.replacing(
                    next[index], bounds: CGRect(origin: originAdjustment(id, point), size: next[index].bounds.size)
                )
            case let .mode(id, mode):
                guard let index = next.firstIndex(where: { $0.id == id }) else {
                    throw DisplayError.displayNotFound(id)
                }
                next[index] = Self.replacing(
                    next[index], bounds: CGRect(origin: next[index].bounds.origin, size: mode.pointSize), mode: mode
                )
            }
        }
        displays = Self.recomputingAppKitFrames(next)
        appliedBatches.append(changes)
        fireReconfiguration()
    }

    public func addReconfigurationObserver(_ handler: @escaping @MainActor () -> Void) -> DisplayObservation {
        let token = UUID()
        observers[token] = handler
        return DisplayObservation { [weak self] in self?.observers[token] = nil }
    }

    /// Simulates a change made outside the app (System Settings, hotplug).
    public func replaceDisplays(_ displays: [Display]) {
        self.displays = Self.recomputingAppKitFrames(displays)
        fireReconfiguration()
    }

    public func fireReconfiguration() {
        for handler in observers.values { handler() }
    }

    // MARK: - Builders

    public static func makeDisplay(
        id: CGDirectDisplayID, uuid: String?, name: String = "Display", bounds: CGRect,
        physicalSize: CGSize = .zero, isBuiltin: Bool = false, refreshRate: Double = 60, scale: CGFloat = 1
    ) -> Display {
        let mode = DisplayMode(pointSize: bounds.size,
                               pixelSize: CGSize(width: bounds.width * scale, height: bounds.height * scale),
                               refreshRate: refreshRate)
        return Display(id: id, identity: DisplayIdentity(uuid: uuid, vendor: 0, model: 0, serial: id), name: name,
                       physicalSize: physicalSize, isBuiltin: isBuiltin, isMain: bounds.origin == .zero,
                       bounds: bounds, frame: bounds, visibleFrame: bounds, backingScaleFactor: scale,
                       mode: mode, rotation: 0)
    }

    /// The user's desk: Odyssey (3, main), LG (2, upper left), RTK (8, below).
    public static func desk() -> FakeDisplaySystem {
        let odyssey = makeDisplay(id: 3, uuid: "ODYSSEY", name: "Odyssey G95NC",
                                  bounds: CGRect(x: 0, y: 0, width: 7680, height: 2160),
                                  physicalSize: CGSize(width: 1403, height: 400), refreshRate: 120)
        let lgDisplay = makeDisplay(id: 2, uuid: "LG", name: "LG UltraFine",
                             bounds: CGRect(x: -3840, y: -615, width: 3840, height: 2160),
                             physicalSize: CGSize(width: 597, height: 336), scale: 1)
        let rtk = makeDisplay(id: 8, uuid: "RTK", name: "RTK UHD HDR",
                              bounds: CGRect(x: 1173, y: 2160, width: 2560, height: 1440),
                              physicalSize: CGSize(width: 597, height: 336), scale: 2)
        let lgModes = [
            DisplayMode(pointSize: CGSize(width: 3840, height: 2160),
                       pixelSize: CGSize(width: 3840, height: 2160), refreshRate: 60),
            DisplayMode(pointSize: CGSize(width: 2560, height: 1440),
                       pixelSize: CGSize(width: 5120, height: 2880), refreshRate: 60),
            DisplayMode(pointSize: CGSize(width: 1920, height: 1080),
                       pixelSize: CGSize(width: 3840, height: 2160), refreshRate: 60),
            DisplayMode(pointSize: CGSize(width: 1920, height: 1080),
                       pixelSize: CGSize(width: 1920, height: 1080), refreshRate: 60)
        ]
        return FakeDisplaySystem(
            displays: [odyssey, lgDisplay, rtk],
            modes: [3: [odyssey.mode].compactMap { $0 }, 2: lgModes, 8: [rtk.mode].compactMap { $0 }]
        )
    }

    private static func replacing(_ display: Display, bounds: CGRect, mode: DisplayMode? = nil) -> Display {
        Display(id: display.id, identity: display.identity, name: display.name, physicalSize: display.physicalSize,
                isBuiltin: display.isBuiltin, isMain: bounds.origin == .zero, bounds: bounds, frame: bounds,
                visibleFrame: bounds, backingScaleFactor: display.backingScaleFactor, mode: mode ?? display.mode,
                rotation: display.rotation)
    }

    private static func recomputingAppKitFrames(_ displays: [Display]) -> [Display] {
        let mainHeight = displays.first { $0.bounds.origin == .zero }?.bounds.height ?? 0
        return displays.map { display in
            let frame = Display.appKitRect(fromCG: display.bounds, mainHeight: mainHeight)
            return Display(id: display.id, identity: display.identity, name: display.name,
                           physicalSize: display.physicalSize, isBuiltin: display.isBuiltin,
                           isMain: display.bounds.origin == .zero, bounds: display.bounds, frame: frame,
                           visibleFrame: frame, backingScaleFactor: display.backingScaleFactor,
                           mode: display.mode, rotation: display.rotation)
        }
    }
}
