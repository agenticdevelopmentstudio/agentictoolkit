import AppKit
import XCTest
import AgenticToolkitDisplays
@testable import AgenticToolkitMacOS

/// Re-arming observation must never register a second handler: one screen
/// event has to run `processScreenChange` exactly once.
@MainActor
final class ScreenManagerObservationTests: XCTestCase {

    /// Counts reads of `screens`; `processScreenChange` reads it exactly once
    /// per run, so the count is the number of times it ran.
    private final class CountingScreenProvider: ScreenProvider {
        var stored: [ScreenInfo]
        var reads = 0
        var screens: [ScreenInfo] {
            reads += 1
            return stored
        }
        var mainScreen: ScreenInfo? { stored.first }

        init(screens: [ScreenInfo]) { stored = screens }
    }

    private static let builtin = MockScreen(
        frame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
        uuid: "BUILTIN", name: "Built-in", isMain: true
    )
    private static let external = MockScreen(
        frame: NSRect(x: 1920, y: 0, width: 2560, height: 1440),
        uuid: "EXTERNAL", name: "LG Monitor", isMain: false
    )

    func testRestartingObservationProcessesOneEventOnce() {
        let provider = CountingScreenProvider(screens: [Self.builtin])
        let system = FakeDisplaySystem.desk()
        let manager = ScreenManager(screenProvider: provider, storage: MockScreenSetStorage(), displaySystem: system)
        manager.startObservingScreenChanges()
        manager.startObservingScreenChanges()

        var received: [ScreenChange] = []
        manager.addObserver { received.append($0) }
        provider.stored = [Self.builtin, Self.external]
        provider.reads = 0

        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        XCTAssertEqual(provider.reads, 1, "one event must run processScreenChange exactly once")
        XCTAssertEqual(received.count, 1)

        // The CG-reconfiguration source is wired to the same single handler.
        provider.stored = [Self.builtin]
        provider.reads = 0
        system.fireReconfiguration()
        XCTAssertEqual(provider.reads, 1)
        XCTAssertEqual(received.count, 2)
    }
}
