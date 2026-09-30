import AppKit
import Testing
@testable import AgenticToolkitDisplays

@MainActor @Suite struct DisplayMonitorTests {
    let system = FakeDisplaySystem.desk()
    let center = NotificationCenter()
    let workspace = NotificationCenter()

    private func monitor(_ debounce: Duration) -> DisplayMonitor {
        DisplayMonitor(system: system, debounce: debounce, notificationCenter: center,
                       workspaceNotificationCenter: workspace)
    }

    @Test func zeroDebounceDeliversSynchronouslyForEverySource() {
        let monitor = monitor(.zero)
        var received: [Set<DisplayEvent.Reason>] = []
        monitor.addHandler { received.append($0.reasons) }
        monitor.start()
        system.fireReconfiguration()
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        monitor.sendLaunch()
        #expect(received == [[.reconfigured], [.screenParameters], [.didWake], [.screensDidWake], [.launch]])
        monitor.stop()
    }

    @Test func debounceCoalescesABurst() async throws {
        let monitor = monitor(.milliseconds(50))
        var received: [Set<DisplayEvent.Reason>] = []
        monitor.addHandler { received.append($0.reasons) }
        monitor.start()
        system.fireReconfiguration()
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        system.fireReconfiguration()
        #expect(received.isEmpty)
        try await Task.sleep(for: .milliseconds(200))
        #expect(received == [[.reconfigured, .screenParameters]])
        monitor.stop()
    }

    @Test func stopSilencesAndStartIsIdempotent() {
        let monitor = monitor(.zero)
        var count = 0
        monitor.addHandler { _ in count += 1 }
        monitor.start()
        monitor.start()
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(count == 1)
        monitor.stop()
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(count == 1)
    }

    /// Counts `removeObserver(_:)` calls so a test can see that a monitor's
    /// notification tokens were actually unregistered.
    private final class RemovalCountingCenter: NotificationCenter, @unchecked Sendable {
        var removals = 0
        override func removeObserver(_ observer: Any) {
            removals += 1
            super.removeObserver(observer)
        }
    }

    @Test func releasingAStartedMonitorStopsIt() {
        let center = RemovalCountingCenter()
        let workspace = RemovalCountingCenter()
        var count = 0
        weak var released: DisplayMonitor?
        do {
            let monitor = DisplayMonitor(system: system, debounce: .zero, notificationCenter: center,
                                         workspaceNotificationCenter: workspace)
            monitor.addHandler { _ in count += 1 }
            monitor.start()
            #expect(system.observerCount == 1)
            released = monitor
        }
        #expect(released == nil)
        #expect(system.observerCount == 0)
        // `stop()` removes each of the three tokens from both centers.
        #expect(center.removals == 3)
        #expect(workspace.removals == 3)
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        system.fireReconfiguration()
        #expect(count == 0)
    }

    @Test func asyncStreamYieldsEvents() async {
        let monitor = monitor(.zero)
        monitor.start()
        let stream = monitor.events()
        monitor.sendLaunch()
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next()?.reasons == [.launch])
        monitor.stop()
    }

    // M2: handlers must run in the order they were registered, since a
    // dictionary keyed by UUID would not preserve that.
    @Test func handlersRunInRegistrationOrder() {
        let monitor = monitor(.zero)
        var order: [Int] = []
        monitor.addHandler { _ in order.append(1) }
        monitor.addHandler { _ in order.append(2) }
        monitor.addHandler { _ in order.append(3) }
        monitor.start()
        monitor.sendLaunch()
        #expect(order == [1, 2, 3])
        monitor.stop()
    }

    // M4: dropping the stream (without ever iterating it) must eventually
    // remove its handler, once the MainActor hop in `onTermination` runs.
    @Test func streamTerminationRemovesItsHandler() async throws {
        let monitor = monitor(.zero)
        monitor.start()
        do {
            let stream = monitor.events()
            #expect(monitor.handlerCount == 1)
            _ = stream
        }
        for _ in 0..<5 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(monitor.handlerCount == 0)
        monitor.stop()
    }
}
