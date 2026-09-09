import AppKit
import Testing
@testable import AgenticToolkitMacOS

/// Pins everything the command palette decides: which commands a query selects,
/// what order they come back in, which row is highlighted, and what Return does
/// to it.
///
/// This suite is the task's acceptance. The palette's window cannot be opened
/// here — there is no window server and the app is not to be run — so every
/// behaviour worth checking was deliberately put in this AppKit-free model, and
/// anything not covered below is genuinely unverified.
@Suite("CommandPaletteModel")
@MainActor
struct CommandPaletteModelTests {

    private func command(
        id: String,
        title: String = "Untitled",
        category: String = "",
        isEnabled: @escaping () -> Bool = { true },
        run: @escaping () -> Void = {}
    ) -> AppCommand {
        AppCommand(id: id, title: title, category: category, isEnabled: isEnabled, run: run)
    }

    private func registry(_ commands: [AppCommand]) -> CommandRegistry {
        let registry = CommandRegistry()
        for command in commands { registry.register(command) }
        return registry
    }

    // MARK: - The ordering fixture

    /// The order the two ordering tests register their commands in.
    ///
    /// Forty-eight slots, and the count is the point: Swift's `sorted(by:)` is
    /// an introsort that falls back to plain insertion sort below roughly twenty
    /// elements, and insertion sort *is* stable — so on two or four rows an
    /// implementation with no tiebreaker is indistinguishable from one with it,
    /// and a test at that size proves nothing. Forty-eight is well clear.
    ///
    /// Strided rather than ascending, because the other way a test like this
    /// fools you is by registering in an order the sort would have produced
    /// anyway. 29 is coprime with 48, so the stride visits every slot exactly
    /// once and leaves an order that is neither ascending by id nor
    /// alphabetical by title.
    private var scrambledSlots: [Int] { (0..<48).map { ($0 * 29) % 48 } }

    /// One command for `scrambledSlots`. `prefixed` decides its rank against the
    /// query `"widget"`: a title that *starts* "Widget" ranks 0, one that merely
    /// contains it ranks 1.
    private func widgetCommand(slot: Int, prefixed: Bool) -> AppCommand {
        let number = String(format: "%02d", slot)
        return command(
            id: "test.widget.\(number)",
            title: prefixed ? "Widget Slot \(number)" : "Configure Widget \(number)",
            category: "Widgets"
        )
    }

    // MARK: - Filtering

    @Test("An empty query lists every command, in registration order")
    func emptyQueryListsEverythingInRegistrationOrder() {
        let model = CommandPaletteModel(registry: registry([
            command(id: "test.charlie"),
            command(id: "test.alpha"),
            command(id: "test.bravo")
        ]))

        #expect(model.matches.map(\.id) == ["test.charlie", "test.alpha", "test.bravo"])
    }

    @Test("A whitespace-only query behaves like an empty one")
    func whitespaceOnlyQueryBehavesLikeEmpty() {
        let model = CommandPaletteModel(registry: registry([
            command(id: "test.alpha", title: "Alpha"),
            command(id: "test.bravo", title: "Bravo")
        ]))

        model.query = "   \n "
        #expect(model.matches.map(\.id) == ["test.alpha", "test.bravo"])
    }

    @Test("Title prefixes beat title substrings, which beat category matches")
    func rankingPrefersTitlePrefixThenSubstringThenCategory() {
        let model = CommandPaletteModel(registry: registry([
            command(id: "test.four", title: "Zoom", category: "In Terminal"),
            command(id: "test.three", title: "Clear", category: "Terminal"),
            command(id: "test.two", title: "New Terminal Window", category: "Window"),
            command(id: "test.one", title: "Terminal Settings", category: "Settings")
        ]))

        model.query = "term"
        #expect(model.matches.map(\.id) == ["test.one", "test.two", "test.three", "test.four"])
    }

    @Test("Forty-eight commands of equal rank all keep registration order")
    func tiesKeepRegistrationOrder() {
        let commands = scrambledSlots.map { widgetCommand(slot: $0, prefixed: false) }
        let model = CommandPaletteModel(registry: registry(commands))

        model.query = "widget"
        #expect(model.matches.count == 48)
        #expect(model.matches.map(\.id) == commands.map(\.id))
        // The fixture is only a test of stability while it is out of order:
        // if registration order were also alphabetical order, a sort that had
        // lost its tiebreaker would pass the line above by coincidence.
        #expect(commands.map(\.id) != commands.map(\.id).sorted())
    }

    @Test("Rank decides between buckets; registration order decides inside one")
    func rankingIsStableAcrossInvocations() {
        // Two buckets of twenty-four, interleaved on the way in: every "Widget
        // Slot NN" ranks 0 and every "Configure Widget NN" ranks 1, so the
        // answer is the whole first bucket in registration order followed by the
        // whole second, and no other order is correct.
        let commands = scrambledSlots.enumerated().map {
            widgetCommand(slot: $0.element, prefixed: $0.offset.isMultiple(of: 2))
        }
        let expected = commands.filter { $0.title.hasPrefix("Widget") }.map(\.id)
            + commands.filter { !$0.title.hasPrefix("Widget") }.map(\.id)

        let first = CommandPaletteModel.matches(for: "widget", in: commands).map(\.id)
        let second = CommandPaletteModel.matches(for: "widget", in: commands).map(\.id)
        #expect(first == second)
        #expect(first == expected)
        #expect(first.count == 48)
    }

    @Test("Matching ignores case")
    func matchingIgnoresCase() {
        let model = CommandPaletteModel(registry: registry([
            command(id: "test.one", title: "Show All Commands")
        ]))

        model.query = "SHOW ALL"
        #expect(model.matches.map(\.id) == ["test.one"])
    }

    @Test("Matching ignores diacritics")
    func matchingIgnoresDiacritics() {
        let model = CommandPaletteModel(registry: registry([
            command(id: "test.one", title: "Réveal in Finder")
        ]))

        model.query = "reveal"
        #expect(model.matches.map(\.id) == ["test.one"])
    }

    @Test("A query spanning category and title finds the command")
    func categoryAndTitleTogetherMatch() {
        let model = CommandPaletteModel(registry: registry([
            command(id: "test.one", title: "New Window", category: "Terminal"),
            command(id: "test.two", title: "New Note", category: "Notes")
        ]))

        model.query = "terminal new"
        #expect(model.matches.map(\.id) == ["test.one"])
    }

    @Test("A query that matches nothing leaves no rows and nothing selected")
    func noMatchEmptiesTheListAndTheSelection() {
        let model = CommandPaletteModel(registry: registry([
            command(id: "test.one", title: "Alpha"),
            command(id: "test.two", title: "Bravo")
        ]))

        model.query = "zzzz"
        #expect(model.matches.isEmpty)
        #expect(model.selectedIndex == nil)
    }

    // MARK: - Selection

    @Test("Changing the query puts the selection back on the first row")
    func changingTheQueryResetsSelectionToTheTop() {
        let model = CommandPaletteModel(registry: registry([
            command(id: "test.one", title: "Alpha One"),
            command(id: "test.two", title: "Alpha Two"),
            command(id: "test.three", title: "Beta Three")
        ]))

        model.moveSelectionDown()
        #expect(model.selectedIndex == 1)

        model.query = "alpha"
        #expect(model.matches.count == 2)
        #expect(model.selectedIndex == 0)
    }

    @Test("The selection clamps at both ends rather than wrapping")
    func selectionClampsAtBothEnds() {
        let model = CommandPaletteModel(registry: registry([
            command(id: "test.one"),
            command(id: "test.two"),
            command(id: "test.three")
        ]))

        #expect(model.selectedIndex == 0)
        model.moveSelectionUp()
        #expect(model.selectedIndex == 0)

        for _ in 0..<5 { model.moveSelectionDown() }
        #expect(model.selectedIndex == 2)
    }

    @Test("Selecting a row no list position holds is ignored")
    func selectingOutOfRangeIsIgnored() {
        let model = CommandPaletteModel(registry: registry([command(id: "test.one")]))

        model.select(index: 7)
        #expect(model.selectedIndex == 0)
    }

    @Test("A disabled command is listed and selectable, not hidden")
    func disabledCommandsAreListed() {
        let model = CommandPaletteModel(registry: registry([
            command(id: "test.one", title: "Enabled"),
            command(id: "test.two", title: "Disabled", isEnabled: { false })
        ]))

        #expect(model.matches.map(\.id) == ["test.one", "test.two"])
        model.moveSelectionDown()
        #expect(model.selectedIndex == 1)
    }

    // MARK: - Running

    @Test("runSelection runs the selected command exactly once")
    func runSelectionRunsTheSelectedCommandOnce() throws {
        var ranFirst = 0
        var ranSecond = 0
        let model = CommandPaletteModel(registry: registry([
            command(id: "test.one", run: { ranFirst += 1 }),
            command(id: "test.two", run: { ranSecond += 1 })
        ]))

        model.moveSelectionDown()
        let didRun = try model.runSelection()
        #expect(didRun)
        #expect(ranFirst == 0)
        #expect(ranSecond == 1)
    }

    @Test("runSelection refuses a disabled selection and runs nothing")
    func runSelectionRefusesADisabledSelection() throws {
        var ran = false
        let model = CommandPaletteModel(registry: registry([
            command(id: "test.one", isEnabled: { false }, run: { ran = true })
        ]))

        let didRun = try model.runSelection()
        #expect(!didRun)
        #expect(!ran)
    }

    @Test("runSelection with nothing selected returns false")
    func runSelectionWithNoSelectionReturnsFalse() throws {
        let model = CommandPaletteModel(registry: registry([command(id: "test.one")]))

        model.query = "zzzz"
        #expect(model.selectedIndex == nil)
        let didRun = try model.runSelection()
        #expect(!didRun)
    }

    // MARK: - Reloading

    @Test("reload picks up a command registered after the model was built")
    func reloadPicksUpLaterRegistrations() {
        let registry = registry([command(id: "test.one", title: "Alpha")])
        let model = CommandPaletteModel(registry: registry)
        #expect(model.matches.count == 1)

        registry.register(command(id: "test.two", title: "Bravo"))
        #expect(model.matches.count == 1)

        model.reload()
        #expect(model.matches.map(\.id) == ["test.one", "test.two"])
    }

    @Test("reload keeps the current query")
    func reloadKeepsTheQuery() {
        let registry = registry([
            command(id: "test.one", title: "Alpha"),
            command(id: "test.two", title: "Bravo")
        ])
        let model = CommandPaletteModel(registry: registry)

        model.query = "alpha"
        registry.register(command(id: "test.three", title: "Alphabet"))
        model.reload()

        #expect(model.matches.map(\.id) == ["test.one", "test.three"])
    }

    // MARK: - Dismissal

    /// The palette resets on every dismissal (`windowWillClose` →
    /// `CommandPaletteViewController.reset()` → here), so a closed palette holds
    /// none of the last visit's state. This is that behaviour at the only seam
    /// reachable without a window server.
    @Test("reset clears the query, re-reads the registry and re-selects the top row")
    func resetClearsTheQueryAndRereadsTheRegistry() {
        let registry = registry([
            command(id: "test.one", title: "Alpha"),
            command(id: "test.two", title: "Alphabet")
        ])
        let model = CommandPaletteModel(registry: registry)

        model.query = "alpha"
        model.moveSelectionDown()
        #expect(model.selectedIndex == 1)

        registry.register(command(id: "test.three", title: "Bravo"))
        model.reset()

        #expect(model.query.isEmpty)
        #expect(model.matches.map(\.id) == ["test.one", "test.two", "test.three"])
        #expect(model.selectedIndex == 0)
    }

    @Test("A command taken before the dismissal still runs after it")
    func aCapturedCommandSurvivesTheReset() throws {
        var ranSecond = false
        let model = CommandPaletteModel(registry: registry([
            command(id: "test.one", title: "Alpha"),
            command(id: "test.two", title: "Bravo", run: { ranSecond = true })
        ]))

        model.moveSelectionDown()
        let selected = try #require(model.selectedCommand)
        #expect(selected.id == "test.two")

        // What the view controller does, in order: take the selection, dismiss
        // (which resets), then dispatch. Reading the selection back after the
        // reset instead would run "Alpha" — row 0 of the cleared list.
        model.reset()
        #expect(model.selectedCommand?.id == "test.one")

        let didRun = try model.run(selected)
        #expect(didRun)
        #expect(ranSecond)
    }

    @Test("run refuses a disabled command, whatever the selection is")
    func runRefusesADisabledCommand() throws {
        var ran = false
        let disabled = command(id: "test.two", title: "Bravo", isEnabled: { false }, run: { ran = true })
        let model = CommandPaletteModel(registry: registry([
            command(id: "test.one", title: "Alpha"),
            disabled
        ]))

        let didRun = try model.run(disabled)
        #expect(!didRun)
        #expect(!ran)
    }

    @Test("A command re-registered under an existing id is listed once")
    func replacedCommandIsListedOnce() throws {
        var ranOriginal = false
        var ranReplacement = false
        let registry = registry([
            command(id: "test.one", title: "Original", run: { ranOriginal = true })
        ])
        let model = CommandPaletteModel(registry: registry)

        registry.register(command(id: "test.one", title: "Replacement", run: { ranReplacement = true }))
        model.reload()

        #expect(model.matches.map(\.id) == ["test.one"])
        #expect(model.matches.first?.title == "Replacement")
        let didRun = try model.runSelection()
        #expect(didRun)
        #expect(!ranOriginal)
        #expect(ranReplacement)
    }
}
