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
