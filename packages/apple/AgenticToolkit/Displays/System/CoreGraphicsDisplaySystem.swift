import AppKit
import CoreGraphics

@MainActor
public final class CoreGraphicsDisplaySystem: DisplaySystem {
    public init() {}

    public func onlineDisplays() -> [Display] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        let screens = screensByID()
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        return ids.prefix(Int(count))
            .filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
            .map { makeDisplay($0, screen: screens[$0], mainHeight: mainHeight) }
    }

    public func modes(for displayID: CGDirectDisplayID) -> [DisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] ?? []
        return modes.map(DisplayMode.init)
    }

    public func apply(_ changes: [DisplayConfigurationChange]) throws {
        var config: CGDisplayConfigRef?
        try check(CGBeginDisplayConfiguration(&config), step: "begin")
        do {
            for change in changes {
                switch change {
                case let .origin(id, point):
                    try check(
                        CGConfigureDisplayOrigin(config, id, Int32(point.x), Int32(point.y)), step: "origin \(id)"
                    )
                case let .mode(id, mode):
                    guard let handle = mode.handle else { throw DisplayError.modeNotAvailable(mode.spec) }
                    try check(CGConfigureDisplayWithDisplayMode(config, id, handle.mode, nil), step: "mode \(id)")
                }
            }
        } catch {
            CGCancelDisplayConfiguration(config)
            throw error
        }
        try check(CGCompleteDisplayConfiguration(config, .permanently), step: "complete")
    }

    public func addReconfigurationObserver(_ handler: @escaping @MainActor () -> Void) -> DisplayObservation {
        let box = ReconfigurationBox(handler: handler)
        let pointer = Unmanaged.passRetained(box).toOpaque()
        CGDisplayRegisterReconfigurationCallback(reconfigurationCallback, pointer)
        return DisplayObservation {
            CGDisplayRemoveReconfigurationCallback(reconfigurationCallback, pointer)
            Unmanaged<ReconfigurationBox>.fromOpaque(pointer).release()
        }
    }

    private func check(_ error: CGError, step: String) throws {
        guard error == .success else { throw DisplayError.configurationFailed(step: step, code: error.rawValue) }
    }

    private func screensByID() -> [CGDirectDisplayID: NSScreen] {
        var result: [CGDirectDisplayID: NSScreen] = [:]
        for screen in NSScreen.screens {
            if let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                result[id] = screen
            }
        }
        return result
    }

    private func makeDisplay(_ id: CGDirectDisplayID, screen: NSScreen?, mainHeight: CGFloat) -> Display {
        let bounds = CGDisplayBounds(id)
        let frame = Display.appKitRect(fromCG: bounds, mainHeight: mainHeight)
        return Display(
            id: id,
            identity: .of(id),
            name: screen?.localizedName ?? "Display \(id)",
            physicalSize: CGDisplayScreenSize(id),
            isBuiltin: CGDisplayIsBuiltin(id) != 0,
            isMain: CGDisplayIsMain(id) != 0,
            bounds: bounds,
            frame: frame,
            visibleFrame: screen?.visibleFrame ?? frame,
            backingScaleFactor: screen?.backingScaleFactor ?? 1,
            mode: CGDisplayCopyDisplayMode(id).map(DisplayMode.init),
            rotation: CGDisplayRotation(id)
        )
    }
}

/// Boxes a `@MainActor` closure for the C callback API. `Sendable` because the
/// callback dispatches back onto the main actor before invoking the handler,
/// so the closure is never actually called off that actor.
private final class ReconfigurationBox: @unchecked Sendable {
    let handler: @MainActor () -> Void
    init(handler: @escaping @MainActor () -> Void) { self.handler = handler }
}

/// Global C callback; ignores the "begin" pass so observers see completed changes only.
private func reconfigurationCallback(
    _ display: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    guard !flags.contains(.beginConfigurationFlag), let userInfo else { return }
    let box = Unmanaged<ReconfigurationBox>.fromOpaque(userInfo).takeUnretainedValue()
    Task { @MainActor in box.handler() }
}
