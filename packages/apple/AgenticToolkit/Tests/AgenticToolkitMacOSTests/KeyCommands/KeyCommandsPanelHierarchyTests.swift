import AppKit
import XCTest
import KeyboardShortcuts
@testable import AgenticToolkitMacOS

/// The three levels the Key Commands panel draws — where a command fires, the
/// window it belongs to, and the feature of that window it operates on — and
/// the model underneath them.
@MainActor
final class KeyCommandsPanelHierarchyTests: XCTestCase {

    // MARK: - A section owns the scope

    func testASectionStampsItsScopeOnEverythingItCarries() {
        let section = KeyCommandSection(
            title: "Widgets Window",
            scope: .global,
            commands: [command("widgets.open", "Open Widgets")],
            features: [KeyCommandFeature(
                title: "Editing",
                commands: [command("widgets.undo", "Undo")])])

        XCTAssertEqual(section.allCommands.map(\.scope), [.global, .global])
    }

    func testAllCommandsListsTheWindowsOwnBeforeItsFeatures() {
        let section = KeyCommandSection(
            title: "Widgets Window",
            scope: .app,
            commands: [command("widgets.open", "Open Widgets")],
            features: [
                KeyCommandFeature(title: "Editing", commands: [command("widgets.undo", "Undo")]),
                KeyCommandFeature(title: "Sorting", commands: [command("widgets.sort", "Sort")])
            ])

        XCTAssertEqual(
            section.allCommands.map(\.id),
            ["widgets.open", "widgets.undo", "widgets.sort"])
    }

    // MARK: - The registry

    /// A command declared inside a feature is a command like any other: it has
    /// to dispatch, and it has to be found when something asks whether a chord
    /// is free.
    func testARegistryFindsACommandDeclaredInsideAFeature() {
        var ran = false
        let registry = KeyCommandRegistry()
        registry.install(KeyCommandSection(
            title: "Widgets Window",
            scope: .app,
            features: [KeyCommandFeature(
                title: "Editing",
                commands: [
                    KeyCommandDescriptor(
                        id: "widgets.undo",
                        title: "Undo",
                        defaultShortcut: KeyboardShortcuts.Shortcut(.f19, modifiers: .command),
                        run: { ran = true })
                ])]))

        XCTAssertEqual(registry.allCommands.map(\.id), ["widgets.undo"])
        XCTAssertNotNil(registry.descriptor(for: "widgets.undo"))
        registry.descriptor(for: "widgets.undo")?.run()
        XCTAssertTrue(ran)
        XCTAssertEqual(
            registry.availability(
                of: KeyboardShortcuts.Shortcut(.f19, modifiers: .command), for: "other")
                .reason,
            "taken by “Undo”")
    }

    func testSectionsInScopeFiltersAndKeepsDeclarationOrder() {
        let registry = KeyCommandRegistry()
        registry.install(KeyCommandSection(title: "Widgets Window", scope: .app))
        registry.install(KeyCommandSection(title: "Windows", scope: .global))
        registry.install(KeyCommandSection(title: "Gadgets Window", scope: .app))

        XCTAssertEqual(
            registry.sections(in: .app).map(\.title), ["Widgets Window", "Gadgets Window"])
        XCTAssertEqual(registry.sections(in: .global).map(\.title), ["Windows"])
    }

    // MARK: - What the panel draws

    func testThePanelHeadsEachScopeOnceAndOnlyWhenItHasSections() {
        let registry = KeyCommandRegistry()
        registry.install(KeyCommandSection(
            title: "Widgets Window",
            scope: .app,
            commands: [command("widgets.open", "Open Widgets")]))

        XCTAssertEqual(outline(of: panel(over: registry)), [
            "# App",
            "## Widgets Window",
            "- widgets.open"
        ])
    }

    func testAFeaturesCommandsSitUnderItsNameInsideTheWindowsCard() {
        let registry = KeyCommandRegistry()
        registry.install(KeyCommandSection(
            title: "Widgets Window",
            scope: .app,
            commands: [command("widgets.open", "Open Widgets")],
            features: [KeyCommandFeature(
                title: "Editing",
                commands: [command("widgets.undo", "Undo"), command("widgets.redo", "Redo")])]))
        registry.install(KeyCommandSection(
            title: "Windows",
            scope: .global,
            commands: [command("window.sessions", "Sessions")]))

        XCTAssertEqual(outline(of: panel(over: registry)), [
            "# App",
            "## Widgets Window",
            "- widgets.open",
            "### Editing",
            "- widgets.undo",
            "- widgets.redo",
            "# Global",
            "## Windows",
            "- window.sessions"
        ])
    }

    /// The scope heading is where the panel says what a scope *is* — every
    /// section under it fires the same way, so saying it per section said the
    /// same sentence twice on the way down the page.
    func testTheScopeHeadingCarriesTheExplanation() throws {
        let registry = KeyCommandRegistry()
        registry.install(KeyCommandSection(
            title: "Windows",
            scope: .global,
            commands: [command("window.sessions", "Sessions")]))

        let headings = headings(of: panel(over: registry))
        let global = try XCTUnwrap(headings.first)
        XCTAssertEqual(global.titleLabel.stringValue, "Global")
        XCTAssertEqual(global.captionLabel?.stringValue, KeyCommandScope.global.settingsCaption)
    }

    func testAPanelWithNothingDeclaredSaysSoRatherThanShowingHeadings() {
        let view = panel(over: KeyCommandRegistry())
        XCTAssertTrue(headings(of: view).isEmpty)
        XCTAssertEqual(outline(of: view), ["## Key Commands"])
    }

    // MARK: - The Conversations window, as it is actually declared

    func testTheConversationsWindowListsItsSingleModeCommandsUnderTheMode() {
        let registry = KeyCommandRegistry()
        registry.install(ConversationsKeyCommands.section(resolve: { nil }))

        XCTAssertEqual(outline(of: panel(over: registry)), [
            "# App",
            "## Conversations Window",
            "- \(ConversationsKeyCommands.toggleShelfID)",
            "### Single Conversation Mode",
            "- \(ConversationsKeyCommands.moveSelectionUpID)",
            "- \(ConversationsKeyCommands.moveSelectionDownID)"
        ])
    }

    // MARK: - Helpers

    private func command(_ id: String, _ title: String) -> KeyCommandDescriptor {
        KeyCommandDescriptor(id: id, title: title, isEnabledByDefault: false, run: {})
    }

    private func panel(over registry: KeyCommandRegistry) -> NSView {
        let controller = KeyCommandsSettingsPanelViewController(registry: registry)
        return controller.view
    }

    private func headings(of view: NSView) -> [ComposableSettings.PanelHeadingView] {
        if let heading = view as? ComposableSettings.PanelHeadingView { return [heading] }
        return view.subviews.flatMap { headings(of: $0) }
    }

    /// The panel as a reader sees it, in drawing order: `#` a scope heading,
    /// `##` a card's title, `###` a feature inside that card, `-` a command.
    private func outline(
        of view: NSView,
        card: NSView? = nil
    ) -> [String] {
        var lines: [String] = []
        for subview in view.subviews {
            if let heading = subview as? ComposableSettings.PanelHeadingView {
                lines.append("# \(heading.titleLabel.stringValue)")
            } else if let group = subview as? ComposableSettings.GroupView {
                lines += outline(of: group, card: group.cardView)
            } else if let header = subview as? ComposableSettings.HeaderView {
                let inCard = card.map { header.isDescendant(of: $0) } ?? false
                lines.append("\(inCard ? "###" : "##") \(header.titleLabel.stringValue)")
            } else if let row = subview as? KeyCommandRowView, let id = commandID(of: row) {
                lines.append("- \(id)")
            } else {
                lines += outline(of: subview, card: card)
            }
        }
        return lines
    }

    /// A row identifies itself by the recorder it contains — the one handle the
    /// row publishes, and the same one a UI test addresses it by. Searched the
    /// whole way down, because how deeply a row nests its field is the row's
    /// business and not something an outline should depend on.
    private func commandID(of view: NSView) -> String? {
        let prefix = "settings.key-commands."
        let suffix = ".recorder"
        let identifier = view.accessibilityIdentifier()
        if identifier.hasPrefix(prefix), identifier.hasSuffix(suffix) {
            return String(identifier.dropFirst(prefix.count).dropLast(suffix.count))
        }
        for subview in view.subviews {
            if let found = commandID(of: subview) { return found }
        }
        return nil
    }
}
