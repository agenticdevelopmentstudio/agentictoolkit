import Foundation

/// What the command palette shows, what is highlighted, and what Return runs.
///
/// Deliberately free of AppKit. A palette's only interesting behaviour is its
/// filter, its ranking and its refusal to fire a disabled row, and none of that
/// needs a window server — so all of it lives here where a unit test can reach
/// it, and `CommandPaletteViewController` is left with nothing but the drawing
/// (`separation-of-concerns`).
///
/// `@MainActor` because `CommandRegistry` is, and every consumer of this model
/// is a view controller that already is.
@MainActor
public final class CommandPaletteModel {

    // MARK: - Dependencies

    /// Held rather than snapshotted: `runSelection()` dispatches through the
    /// registry so the command that runs is the one registered *now*, not the
    /// copy `reload()` happened to capture. Stage 5 reloads extensions while the
    /// app is running, and a palette holding stale closures would run the old
    /// extension's code.
    private let registry: CommandRegistry

    /// The registry's contents as of the last `reload()`. A snapshot, so
    /// keystroke-by-keystroke filtering does not re-read the registry (and so
    /// the list cannot change shape between a keystroke and the Return that
    /// follows it).
    private var commands: [AppCommand] = []

    // MARK: - State

    /// The current filter text. Setting it recomputes `matches` and moves the
    /// selection back to the top of the new list.
    public var query: String {
        didSet { applyQuery() }
    }

    /// What the list shows, in display order, for the current `query`.
    public private(set) var matches: [AppCommand] = []

    /// Index into `matches`, or `nil` when `matches` is empty — the only case
    /// where nothing is selected. A palette showing rows always has one of them
    /// highlighted, so Return never has to ask what it meant.
    public private(set) var selectedIndex: Int?

    // MARK: - Lifecycle

    public init(registry: CommandRegistry) {
        self.registry = registry
        self.query = ""
        reload()
    }

    /// Re-read the registry and re-apply the current query.
    ///
    /// Commands can be registered and re-registered at any time — a coordinator
    /// built after this model, or (Stage 5) an extension reloading — so the
    /// palette re-reads on every open rather than trusting what it saw once.
    public func reload() {
        commands = registry.allCommands
        applyQuery()
    }

    // MARK: - Selection

    /// Move down one row, stopping at the last.
    ///
    /// Clamps rather than wraps. A palette list is short and usually shorter
    /// still once filtered, so arrowing off the end and reappearing at the top
    /// reads as the selection having been lost rather than moved
    /// (`principle-of-least-astonishment`). `NSMenu` clamps for the same reason.
    public func moveSelectionDown() {
        guard let current = selectedIndex else { return }
        selectedIndex = min(current + 1, matches.count - 1)
    }

    /// Move up one row, stopping at the first. Clamps — see `moveSelectionDown`.
    public func moveSelectionUp() {
        guard let current = selectedIndex else { return }
        selectedIndex = max(current - 1, 0)
    }

    /// Select the row at `index`, ignoring an index no row occupies. Out of
    /// range is a stale click, not a programmer error: AppKit reports the row a
    /// click landed on, and the list can have been rebuilt since.
    public func select(index: Int) {
        guard matches.indices.contains(index) else { return }
        selectedIndex = index
    }

    // MARK: - Running

    /// Run the selected command through the registry.
    ///
    /// - Returns: `false` when there is no selection, or when the selected
    ///   command's own `isEnabled` says running it now would mean nothing. A
    ///   disabled row is visible and selectable but inert — exactly what an
    ///   `NSMenu` does with a dimmed item — so refusing it is ordinary
    ///   behaviour and not worth an error.
    /// - Throws: Whatever `CommandRegistry.execute(id:)` throws. Reachable when
    ///   the selected command has been unregistered since the last `reload()`,
    ///   which is a wiring mistake rather than a user action and must be seen
    ///   (`fail-fast`).
    @discardableResult
    public func runSelection() throws -> Bool {
        guard let index = selectedIndex, matches.indices.contains(index) else { return false }
        let command = matches[index]
        guard command.isEnabled() else { return false }
        try registry.execute(id: command.id)
        return true
    }

    // MARK: - Filtering

    /// The commands `query` selects, best match first.
    ///
    /// Substring matching, not fuzzy. Nothing in this toolkit scores a fuzzy
    /// match today, a scorer is a large thing to get right, and the one existing
    /// filterable table here (`ModelChooserContent.filter`) matches by
    /// substring — so a palette that did something cleverer would be the only
    /// list in the app whose answers could not be predicted from what was typed
    /// (`yagni`, `principle-of-least-astonishment`).
    ///
    /// `static` and instance-free so the ranking rule can be tested directly
    /// against a literal array, with no registry and no window.
    public static func matches(for query: String, in commands: [AppCommand]) -> [AppCommand] {
        let needle = folded(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return commands }

        let ranked = commands.compactMap { command -> (rank: Int, command: AppCommand)? in
            guard let rank = rank(of: command, for: needle) else { return nil }
            return (rank, command)
        }

        // The offset tiebreaker is what makes this stable: `sorted(by:)` gives
        // no stability guarantee, and two same-rank rows swapping places
        // between keystrokes is a list the eye cannot follow.
        return ranked.enumerated()
            .sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }
            .map(\.element.command)
    }

    /// How well `command` answers `needle`, or `nil` when it does not.
    ///
    /// Lower is better: a title that *starts* with what was typed is what the
    /// user meant, a title that merely contains it is a near miss, and a
    /// category match is the broadest of the three.
    private static func rank(of command: AppCommand, for needle: String) -> Int? {
        let title = folded(command.title)
        let category = folded(command.category)
        if title.hasPrefix(needle) { return 0 }
        if title.contains(needle) { return 1 }
        if category.hasPrefix(needle) { return 2 }
        // "terminal new" finds New Terminal Session: the category and the title
        // are one phrase as far as the reader is concerned, so they are matched
        // as one too.
        if category.contains(needle) || folded("\(command.category) \(command.title)").contains(needle) {
            return 3
        }
        return nil
    }

    /// Case- and diacritic-insensitively normalised, so "reveal" finds "Réveal"
    /// and capitalisation never decides a match. `locale: nil` keeps the folding
    /// the same everywhere — command ids and titles are not localised, and a
    /// Turkish locale's dotless-i rule would otherwise make the palette answer
    /// differently on one machine than another.
    private static func folded(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private func applyQuery() {
        matches = Self.matches(for: query, in: commands)
        // Always the top row, including when the top row is disabled. Skipping
        // to the first *runnable* row would make the highlight jump over rows
        // the user can see, and would move on its own as commands enabled and
        // disabled themselves under it.
        selectedIndex = matches.isEmpty ? nil : 0
    }
}
