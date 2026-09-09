import AppKit
import Testing
@testable import AgenticToolkitMacOS

/// Pins `CommandRegistry`'s contract (task 4.1): registration and lookup,
/// `allCommands` order, dispatch by id, and the two ways `execute(id:)` refuses
/// — both of which must be loud, because "the menu item did nothing" is exactly
/// the failure this type exists to make impossible.
@Suite("CommandRegistry")
@MainActor
struct CommandRegistryTests {

    private func command(
        id: String,
        title: String = "Untitled",
        category: String = "Test",
        isEnabled: @escaping () -> Bool = { true },
        run: @escaping () -> Void = {}
    ) -> AppCommand {
        AppCommand(id: id, title: title, category: category, isEnabled: isEnabled, run: run)
    }

    @Test("A registered command is found by its id")
    func registeredCommandIsFoundByID() {
        let registry = CommandRegistry()
        registry.register(command(id: "test.action.one", title: "One", category: "Tests"))

        let found = registry.command(id: "test.action.one")
        #expect(found?.id == "test.action.one")
        #expect(found?.title == "One")
        #expect(found?.category == "Tests")
    }

    @Test("An unregistered id looks up to nil")
    func unregisteredIDLooksUpToNil() {
        let registry = CommandRegistry()
        registry.register(command(id: "test.action.one"))
        #expect(registry.command(id: "test.action.missing") == nil)
    }

    @Test("allCommands is empty until something registers")
    func allCommandsStartsEmpty() {
        #expect(CommandRegistry().allCommands.isEmpty)
    }

    @Test("allCommands returns every command in registration order")
    func allCommandsIsInRegistrationOrder() {
        let registry = CommandRegistry()
        registry.register(command(id: "test.action.charlie"))
        registry.register(command(id: "test.action.alpha"))
        registry.register(command(id: "test.action.bravo"))

        #expect(registry.allCommands.map(\.id) == [
            "test.action.charlie",
            "test.action.alpha",
            "test.action.bravo"
        ])
    }

    @Test("execute runs the registered command's run closure")
    func executeRunsTheCommand() throws {
        let registry = CommandRegistry()
        var runCount = 0
        registry.register(command(id: "test.action.run", run: { runCount += 1 }))

        try registry.execute(id: "test.action.run")
        #expect(runCount == 1)

        try registry.execute(id: "test.action.run")
        #expect(runCount == 2)
    }

    @Test("execute dispatches to the command named, not to some other one")
    func executeDispatchesToTheNamedCommand() throws {
        let registry = CommandRegistry()
        var ranFirst = false
        var ranSecond = false
        registry.register(command(id: "test.action.first", run: { ranFirst = true }))
        registry.register(command(id: "test.action.second", run: { ranSecond = true }))

        try registry.execute(id: "test.action.second")
        #expect(!ranFirst)
        #expect(ranSecond)
    }

    @Test("execute of an unknown id throws unknownCommand")
    func executeOfUnknownIDThrows() {
        let registry = CommandRegistry()
        registry.register(command(id: "test.action.one"))

        #expect(throws: CommandRegistryError.unknownCommand(id: "test.action.missing")) {
            try registry.execute(id: "test.action.missing")
        }
    }

    @Test("execute of a disabled command throws commandDisabled and does not run it")
    func executeOfDisabledCommandThrows() {
        let registry = CommandRegistry()
        var ran = false
        registry.register(command(
            id: "test.action.disabled",
            isEnabled: { false },
            run: { ran = true }
        ))

        #expect(throws: CommandRegistryError.commandDisabled(id: "test.action.disabled")) {
            try registry.execute(id: "test.action.disabled")
        }
        #expect(!ran)
    }

    @Test("isEnabled asks the command, every time")
    func isEnabledAsksTheCommand() {
        let registry = CommandRegistry()
        var enabled = false
        registry.register(command(id: "test.action.gated", isEnabled: { enabled }))

        #expect(!registry.isEnabled(id: "test.action.gated"))
        enabled = true
        #expect(registry.isEnabled(id: "test.action.gated"))
    }

    @Test("isEnabled of an unknown id is false, not true")
    func isEnabledOfUnknownIDIsFalse() {
        #expect(!CommandRegistry().isEnabled(id: "test.action.missing"))
    }

    @Test("Registering a duplicate id replaces the command")
    func duplicateIDReplaces() throws {
        let registry = CommandRegistry()
        var ranOriginal = false
        var ranReplacement = false
        registry.register(command(id: "test.action.dup", title: "Original", run: { ranOriginal = true }))
        registry.register(command(id: "test.action.dup", title: "Replacement", run: { ranReplacement = true }))

        #expect(registry.command(id: "test.action.dup")?.title == "Replacement")
        try registry.execute(id: "test.action.dup")
        #expect(!ranOriginal)
        #expect(ranReplacement)
    }

    @Test("Registering a duplicate id keeps one entry, in its original position")
    func duplicateIDKeepsItsPosition() {
        let registry = CommandRegistry()
        registry.register(command(id: "test.action.alpha"))
        registry.register(command(id: "test.action.bravo"))
        registry.register(command(id: "test.action.charlie"))
        registry.register(command(id: "test.action.alpha", title: "Alpha again"))

        #expect(registry.allCommands.map(\.id) == [
            "test.action.alpha",
            "test.action.bravo",
            "test.action.charlie"
        ])
        #expect(registry.allCommands.first?.title == "Alpha again")
    }
}

/// Pins the additive command-ID `MenuContribution` initializer (task 4.1): it
/// must produce a contribution `MenuManager` can consume with no change at all,
/// whose `action` dispatches through the registry and whose `isEnabled` is the
/// command's own answer — including the case where nothing registered the id.
@Suite("MenuContribution command-ID initializer")
@MainActor
struct MenuContributionCommandTests {

    @Test("action dispatches through the registry to the named command")
    func actionDispatchesThroughTheRegistry() {
        let registry = CommandRegistry()
        var ranNamed = false
        var ranOther = false
        registry.register(AppCommand(id: "test.action.named", title: "Named", run: { ranNamed = true }))
        registry.register(AppCommand(id: "test.action.other", title: "Other", run: { ranOther = true }))

        let contribution = MenuContribution(
            slot: .file,
            title: "Named",
            commandID: "test.action.named",
            registry: registry
        )

        contribution.action()
        #expect(ranNamed)
        #expect(!ranOther)
    }

    @Test("isEnabled reflects the registered command's own isEnabled")
    func isEnabledReflectsTheCommand() {
        let registry = CommandRegistry()
        var enabled = false
        registry.register(AppCommand(
            id: "test.action.gated",
            title: "Gated",
            isEnabled: { enabled },
            run: {}
        ))

        let contribution = MenuContribution(
            slot: .file,
            title: "Gated",
            commandID: "test.action.gated",
            registry: registry
        )

        #expect(!contribution.isEnabled())
        enabled = true
        #expect(contribution.isEnabled())
    }

    @Test("A disabled command's menu item does not run when fired anyway")
    func disabledCommandDoesNotRun() {
        let registry = CommandRegistry()
        var ran = false
        registry.register(AppCommand(
            id: "test.action.disabled",
            title: "Disabled",
            isEnabled: { false },
            run: { ran = true }
        ))

        let contribution = MenuContribution(
            slot: .file,
            title: "Disabled",
            commandID: "test.action.disabled",
            registry: registry
        )

        #expect(!contribution.isEnabled())
        contribution.action()
        #expect(!ran)
    }

    @Test("An item whose command is not registered is not enabled")
    func unregisteredCommandIsNotEnabled() {
        let contribution = MenuContribution(
            slot: .file,
            title: "Nothing registered this",
            commandID: "test.action.missing",
            registry: CommandRegistry()
        )

        #expect(!contribution.isEnabled())
        // And firing it anyway is survivable — the error is logged, not thrown
        // out of a `() -> Void`.
        contribution.action()
    }

    @Test("The lookup is late: a command registered after the item still runs")
    func lateRegistrationStillRuns() {
        let registry = CommandRegistry()
        let contribution = MenuContribution(
            slot: .file,
            title: "Late",
            commandID: "test.action.late",
            registry: registry
        )
        #expect(!contribution.isEnabled())

        var ran = false
        registry.register(AppCommand(id: "test.action.late", title: "Late", run: { ran = true }))

        #expect(contribution.isEnabled())
        contribution.action()
        #expect(ran)
    }

    @Test("Replacing a command re-points menu items already built on its id")
    func replacementRePointsExistingItems() {
        let registry = CommandRegistry()
        var ranOriginal = false
        var ranReplacement = false
        registry.register(AppCommand(id: "test.action.dup", title: "Dup", run: { ranOriginal = true }))

        let contribution = MenuContribution(
            slot: .file,
            title: "Dup",
            commandID: "test.action.dup",
            registry: registry
        )

        registry.register(AppCommand(id: "test.action.dup", title: "Dup", run: { ranReplacement = true }))
        contribution.action()

        #expect(!ranOriginal)
        #expect(ranReplacement)
    }

    @Test("Every other field is carried through unchanged")
    func otherFieldsAreCarriedThrough() {
        let registry = CommandRegistry()
        registry.register(AppCommand(id: "test.action.fields", title: "Fields", run: {}))

        var hidden = false
        let contribution = MenuContribution(
            slot: .statusItem(section: 2),
            title: "Fields",
            commandID: "test.action.fields",
            registry: registry,
            order: 42,
            key: "k",
            modifiers: [.command, .shift],
            isHidden: { hidden }
        )

        #expect(contribution.slot == .statusItem(section: 2))
        #expect(contribution.title == "Fields")
        #expect(contribution.order == 42)
        #expect(contribution.key == "k")
        #expect(contribution.modifiers == [.command, .shift])
        #expect(contribution.isHidden?() == false)
        hidden = true
        #expect(contribution.isHidden?() == true)
    }

    @Test("isHidden defaults to nil, as it does on the closure initializer")
    func isHiddenDefaultsToNil() {
        let registry = CommandRegistry()
        registry.register(AppCommand(id: "test.action.plain", title: "Plain", run: {}))

        let contribution = MenuContribution(
            slot: .file,
            title: "Plain",
            commandID: "test.action.plain",
            registry: registry
        )

        #expect(contribution.isHidden == nil)
    }
}

/// The routing half of task 4.1: the coordinators no longer hold their menu
/// actions as inline closures, so a registry handed to one comes back holding
/// that feature's commands under the documented ids. `TerminalCoordinator` is
/// the cheapest of the five to build headlessly — no database, no storage, no
/// chat backend.
@Suite("Coordinator command routing")
@MainActor
struct CoordinatorCommandRoutingTests {

    @Test("TerminalCoordinator registers its menu actions as commands")
    func terminalCoordinatorRegistersItsCommands() {
        let registry = CommandRegistry()
        let coordinator = TerminalCoordinator(commandRegistry: registry)
        defer { coordinator.unregister() }

        #expect(registry.allCommands.map(\.id) == [
            TerminalCoordinator.CommandID.newWindow,
            TerminalCoordinator.CommandID.newSession,
            TerminalCoordinator.CommandID.toggleSidebar
        ])
        #expect(registry.command(id: TerminalCoordinator.CommandID.newSession)?.title
            == "New Terminal Session")
        #expect(registry.command(id: TerminalCoordinator.CommandID.newSession)?.category == "Terminal")
    }

    @Test("Its two New Terminal Window items share one command id")
    func repeatedMenuItemsShareOneCommand() {
        let registry = CommandRegistry()
        let coordinator = TerminalCoordinator(commandRegistry: registry)
        defer { coordinator.unregister() }

        let windowItems = coordinator.menuContributions.filter { $0.title == "New Terminal Window" }
        #expect(windowItems.count == 2)
        // Two menu items, one command: the registry holds three commands for
        // four contributions.
        #expect(coordinator.menuContributions.count == 4)
        #expect(registry.allCommands.count == 3)
    }

    @Test("Every contribution resolves through the caller's registry, never a private one")
    func contributionsResolveThroughTheCallersRegistry() {
        let registry = CommandRegistry()
        let coordinator = TerminalCoordinator(commandRegistry: registry)
        defer { coordinator.unregister() }

        #expect(coordinator.menuContributions.count == 4)
        #expect(coordinator.menuContributions.allSatisfy { $0.isEnabled() })

        // The negative control, and the reason `commandRegistry` is required
        // rather than defaulted: disabling a command *on the caller's registry*
        // must reach the menu items. A coordinator that had quietly fallen back
        // to a private registry would ignore this entirely and leave all four
        // items enabled — which is exactly the silent half-populated palette an
        // optional parameter made possible.
        registry.register(AppCommand(
            id: TerminalCoordinator.CommandID.newWindow,
            title: "New Terminal Window",
            category: "Terminal",
            isEnabled: { false },
            run: {}
        ))

        let windowItems = coordinator.menuContributions.filter { $0.title == "New Terminal Window" }
        #expect(windowItems.count == 2)
        #expect(windowItems.allSatisfy { !$0.isEnabled() })
        #expect(coordinator.menuContributions
            .filter { $0.title != "New Terminal Window" }
            .allSatisfy { $0.isEnabled() })
    }
}
