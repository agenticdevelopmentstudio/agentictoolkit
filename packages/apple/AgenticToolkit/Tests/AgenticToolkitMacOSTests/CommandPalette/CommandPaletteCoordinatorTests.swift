import AppKit
import Testing
@testable import AgenticToolkitMacOS

/// Pins the coordinator's wiring: the id it registers, that the id is
/// dispatchable, and that its menu item goes through the registry rather than
/// holding a closure of its own.
///
/// Nothing here opens the palette. `showPalette()` builds an `NSPanel`, and
/// these tests run with no app to own one — so the two tests that would
/// otherwise fire the command replace it with a probe under the same id first.
/// That is deliberate and it costs nothing: what is under test is the wiring
/// (the id, the late lookup), and a probe registered under the id proves the
/// dispatch path more sharply than the real handler would.
///
/// Each test unregisters its coordinator: `AppFeature.init()` enrols itself in
/// the process-global `AppFeatureRegistry.shared`, which outlives the test.
///
/// Nothing here calls `start()`, and that is deliberate rather than incidental:
/// `start()` claims a real, system-global Carbon hotkey, so a test that called
/// it would take ⌃⌥C away from the whole machine for the length of the run.
/// `constructionClaimsNoGlobalHotkey` below is what holds that property in
/// place — moving the registration back into `init` fails it.
@Suite("CommandPaletteCoordinator")
@MainActor
struct CommandPaletteCoordinatorTests {

    private var paletteID: String { CommandPaletteCoordinator.CommandID.showCommands }

    @Test("Constructing the coordinator registers VS Code's own show-commands id")
    func constructingRegistersTheCommand() {
        let registry = CommandRegistry()
        let coordinator = CommandPaletteCoordinator(commandRegistry: registry)
        defer { coordinator.unregister() }

        #expect(paletteID == "workbench.action.showCommands")

        let command = registry.command(id: "workbench.action.showCommands")
        #expect(command?.title == "Show All Commands")
        #expect(command?.category == "View")
    }

    @Test("Constructing the coordinator claims no system-global hotkey")
    func constructionClaimsNoGlobalHotkey() {
        let registry = CommandRegistry()
        let coordinator = CommandPaletteCoordinator(commandRegistry: registry)
        defer { coordinator.unregister() }

        // Construction is inert; `start()` is where the machine-wide ⌃⌥C is
        // claimed and `stop()` is where it is given back. A coordinator built
        // in a test bundle has no business holding a hotkey the rest of the
        // process — and the rest of the machine — can see.
        #expect(!coordinator.isGlobalShortcutInstalled)
    }

    @Test("The registered command is enabled, so dispatching it cannot be refused")
    func theCommandIsDispatchable() throws {
        let registry = CommandRegistry()
        let coordinator = CommandPaletteCoordinator(commandRegistry: registry)
        defer { coordinator.unregister() }

        #expect(registry.isEnabled(id: paletteID))

        var ran = false
        registry.register(AppCommand(
            id: paletteID, title: "Show All Commands", category: "View", run: { ran = true }
        ))
        try registry.execute(id: paletteID)
        #expect(ran)
    }

    @Test("The menu contribution dispatches by id, not by a captured closure")
    func theMenuContributionDispatchesByID() {
        let registry = CommandRegistry()
        let coordinator = CommandPaletteCoordinator(commandRegistry: registry)
        defer { coordinator.unregister() }

        #expect(!coordinator.menuContributions.isEmpty)
        let contribution = coordinator.menuContributions.first

        // Replacing the command after the contribution was built is the whole
        // test: an item holding its own closure would still run the palette,
        // while one addressing the registry by id runs whatever answers to that
        // id now.
        var ranProbe = false
        registry.register(AppCommand(
            id: paletteID, title: "Probe", category: "View", run: { ranProbe = true }
        ))

        contribution?.action()
        #expect(ranProbe)
    }

    @Test("The menu item's enablement is the registered command's own answer")
    func theMenuItemAsksTheRegistry() {
        let registry = CommandRegistry()
        let coordinator = CommandPaletteCoordinator(commandRegistry: registry)
        defer { coordinator.unregister() }

        let contribution = coordinator.menuContributions.first
        #expect(contribution?.isEnabled() == true)

        var enabled = false
        registry.register(AppCommand(
            id: paletteID, title: "Probe", category: "View",
            isEnabled: { enabled }, run: {}
        ))
        #expect(contribution?.isEnabled() == false)

        enabled = true
        #expect(contribution?.isEnabled() == true)
    }
}

/// Counts what a dismissal did, from inside the notification that announces it.
///
/// A reference type, and `@MainActor`, so the `@Sendable` notification block can
/// hold it: AppKit posts `willCloseNotification` synchronously on the main
/// thread, which is what makes the `assumeIsolated` below true rather than
/// hopeful.
@MainActor
private final class PaletteCloseProbe {
    var closes = 0
    var hasResignedKeyOnce = false
    /// The controller under test, reached through the probe rather than
    /// captured directly: an `NSWindowController` subclass is not `Sendable`
    /// (its superclass is not), while this actor-isolated class is.
    var controller: CommandPaletteWindowController?
}

/// One dismissal, one close.
///
/// `CommandPaletteWindowController` funnels all four ways out of the palette —
/// Escape, running a command, clicking another window, switching apps — through
/// `close()`, and `windowWillClose` is where the palette is cleared. AppKit
/// resigns key *during* a close of the key window, so the dismissal path can be
/// re-entered before the window is ordered out; these tests reproduce that
/// ordering directly rather than waiting for a window server to produce it.
@Suite("CommandPaletteWindowController dismissal")
@MainActor
struct CommandPaletteWindowDismissalTests {

    private func makeController() -> CommandPaletteWindowController {
        CommandPaletteWindowController(model: CommandPaletteModel(registry: CommandRegistry()))
    }

    @Test("Resigning key mid-close does not close the palette a second time")
    func resigningKeyDuringTheCloseDoesNotReenter() throws {
        let controller = makeController()
        let window = try #require(controller.window)
        window.orderFrontQuietly()

        let probe = PaletteCloseProbe()
        probe.controller = controller
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                probe.closes += 1
                guard !probe.hasResignedKeyOnce else { return }
                probe.hasResignedKeyOnce = true
                // What AppKit does to a key window that is closing: the
                // resignation arrives while the window is still visible, so
                // anything deciding reentrancy by visibility cannot see that
                // this is the same dismissal.
                probe.controller?.windowDidResignKey(
                    Notification(name: NSWindow.didResignKeyNotification, object: window))
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        controller.close()

        #expect(probe.hasResignedKeyOnce)
        #expect(probe.closes == 1)
    }

    @Test("The guard is per dismissal, not for the life of the palette")
    func aLaterDismissalStillCloses() throws {
        let controller = makeController()
        let window = try #require(controller.window)

        let probe = PaletteCloseProbe()
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: nil
        ) { _ in
            MainActor.assumeIsolated { probe.closes += 1 }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        window.orderFrontQuietly()
        controller.close()
        window.orderFrontQuietly()
        controller.close()

        #expect(probe.closes == 2)
    }
}
