import AppKit

public struct DisplayEvent: Equatable, Sendable {
    public enum Reason: String, Hashable, Sendable {
        case launch, reconfigured, screenParameters, didWake, screensDidWake
    }

    public let reasons: Set<Reason>
    public init(reasons: Set<Reason>) { self.reasons = reasons }
}

/// One debounced stream of "the displays may have changed" signals: CG
/// reconfiguration, AppKit screen parameters (which also covers Dock and
/// visible-frame changes), wake, screens-wake and explicit launch.
@MainActor
public final class DisplayMonitor {
    public let system: DisplaySystem
    public let debounce: Duration
    private let notificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    /// Ordered, not keyed by UUID, so handlers run in registration order.
    private var handlers: [(id: UUID, handler: @MainActor (DisplayEvent) -> Void)] = []
    private var tokens: [NSObjectProtocol] = []
    private var reconfiguration: DisplayObservation?
    private var pending: Set<DisplayEvent.Reason> = []
    private var flushTask: Task<Void, Never>?

    public init(system: DisplaySystem, debounce: Duration = .seconds(1),
                notificationCenter: NotificationCenter = .default,
                workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.system = system
        self.debounce = debounce
        self.notificationCenter = notificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
    }

    /// Releasing a monitor stops it, so its CG observation and notification
    /// tokens never outlive it.
    isolated deinit { stop() }

    public var isRunning: Bool { reconfiguration != nil }

    /// Exposed for tests only: lets `streamTerminationRemovesItsHandler` observe
    /// that a dropped stream's handler is actually removed.
    var handlerCount: Int { handlers.count }

    public func start() {
        stop()
        reconfiguration = system.addReconfigurationObserver { [weak self] in self?.receive(.reconfigured) }
        tokens = [
            observe(notificationCenter, NSApplication.didChangeScreenParametersNotification, .screenParameters),
            observe(workspaceNotificationCenter, NSWorkspace.didWakeNotification, .didWake),
            observe(workspaceNotificationCenter, NSWorkspace.screensDidWakeNotification, .screensDidWake)
        ]
    }

    public func stop() {
        reconfiguration?.cancel()
        reconfiguration = nil
        for token in tokens {
            notificationCenter.removeObserver(token)
            workspaceNotificationCenter.removeObserver(token)
        }
        tokens = []
        flushTask?.cancel()
        flushTask = nil
        pending = []
    }

    @discardableResult
    public func addHandler(_ handler: @escaping @MainActor (DisplayEvent) -> Void) -> UUID {
        let token = UUID()
        handlers.append((token, handler))
        return token
    }

    public func removeHandler(_ token: UUID) {
        handlers.removeAll { $0.id == token }
    }

    public func events() -> AsyncStream<DisplayEvent> {
        AsyncStream { continuation in
            let token = addHandler { continuation.yield($0) }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.removeHandler(token) }
            }
        }
    }

    public func sendLaunch() { receive(.launch) }

    private func observe(
        _ center: NotificationCenter, _ name: Notification.Name, _ reason: DisplayEvent.Reason
    ) -> NSObjectProtocol {
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.receive(reason) }
        }
    }

    private func receive(_ reason: DisplayEvent.Reason) {
        pending.insert(reason)
        guard debounce > .zero else { return flush() }
        flushTask?.cancel()
        flushTask = Task { [weak self, debounce] in
            // Cancellation is the only error `Task.sleep(for:)` can throw, and
            // the `Task.isCancelled` check below handles it, so swallowing it
            // here is safe.
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    private func flush() {
        guard !pending.isEmpty else { return }
        let event = DisplayEvent(reasons: pending)
        pending = []
        for entry in handlers { entry.handler(event) }
    }
}
