import CoreGraphics

public enum DisplayConfigurationChange: Equatable, Sendable {
    case origin(CGDirectDisplayID, CGPoint)
    case mode(CGDirectDisplayID, DisplayMode)
}

/// Token for a reconfiguration observer. Call `cancel()` to unregister;
/// dropping the token cancels it too, so a released owner never leaks its
/// registration.
@MainActor
public final class DisplayObservation {
    private var onCancel: (() -> Void)?
    public init(onCancel: @escaping () -> Void) { self.onCancel = onCancel }

    /// Idempotent: `onCancel` is cleared after the first call.
    public func cancel() {
        onCancel?()
        onCancel = nil
    }

    isolated deinit { cancel() }
}

/// The only place display hardware is touched. Everything else in the
/// framework talks to this protocol, so it can run against `FakeDisplaySystem`.
@MainActor
public protocol DisplaySystem: AnyObject {
    /// Active, non-mirrored displays (mirror masters included).
    func onlineDisplays() -> [Display]
    /// Every mode, including duplicate low-resolution (HiDPI) modes.
    func modes(for displayID: CGDirectDisplayID) -> [DisplayMode]
    /// Applies all changes in one configuration transaction, permanently.
    func apply(_ changes: [DisplayConfigurationChange]) throws
    /// Calls `handler` on the main actor after each completed reconfiguration.
    func addReconfigurationObserver(_ handler: @escaping @MainActor () -> Void) -> DisplayObservation
}
