//
//  ExtensionQuickPickModel.swift
//  AgenticToolkit
//

import Foundation
import AgenticToolkitCore

/// What a `vscode.window.showQuickPick` panel shows, what is highlighted,
/// what is checked, and what Return answers.
///
/// **Deliberately free of AppKit**, on `CommandPaletteModel`'s precedent
/// (`macOS/Features/CommandPalette/CommandPaletteModel.swift:5-9`): a
/// picker's only interesting behaviour is its filter, its selection and its
/// checked set, and none of that needs a window server.
///
/// That split is not a style preference here — it is the fix for a defect
/// this task found. `macOS/SystemWindows/UI/ContextPickerView.swift` puts the
/// same three behaviours (filtering, `moveSelectionUp()`, `moveSelectionDown()`)
/// on a SwiftUI `View`, and its own doc comment claims the result "allows the
/// user to select a context with Enter or arrow keys"
/// (`ContextPickerView.swift:5-9`). The arrow-key half of that claim does
/// not hold: `grep -n "moveSelectionUp\|moveSelectionDown"
/// ContextPickerView.swift` finds only the two declarations, no caller —
/// arrow keys do nothing in that panel. (Enter does work, via `.onSubmit` at
/// `ContextPickerView.swift:74`; that half of the claim stands and is not
/// what is being fixed here.) Putting selection logic in a view is logic
/// nothing can test, and the failure mode is not a crash — it is a doc
/// comment that lies for months. This type, its filter, and its test suite
/// exist so that cannot happen here.
@MainActor
public final class ExtensionQuickPickModel {

    /// The request this model was built from. Public and not part of this
    /// task's literal API sketch, but necessary: `ExtensionQuickPickViewController`
    /// is initialised from a model alone (`init(model:)`) and has no other
    /// way to read `title`, `placeHolder`, `canPickMany`, or an item's
    /// `label`/`description`/`detail` for its own rendering.
    public let request: ExtensionQuickPickRequest

    /// The filter text. Setting it recomputes `visibleIndices` and resets the
    /// highlight to the first selectable row.
    public var query: String {
        get { storedQuery }
        set {
            storedQuery = newValue
            recompute()
        }
    }

    private var storedQuery = ""

    /// Indices into `request.items`, in order — never row numbers.
    public private(set) var visibleIndices: [Int]

    /// Index into `request.items` of the highlighted row, or nil when
    /// nothing is selectable.
    public private(set) var highlightedIndex: Int?

    /// Indices into `request.items` that are checked. Always empty when
    /// `request.canPickMany` is false.
    public private(set) var checkedIndices: Set<Int>

    public init(request: ExtensionQuickPickRequest) {
        self.request = request
        self.visibleIndices = Self.visibleIndices(
            for: "",
            in: request.items,
            matchOnDescription: request.matchOnDescription,
            matchOnDetail: request.matchOnDetail
        )
        self.highlightedIndex = Self.firstSelectableIndex(in: visibleIndices, items: request.items)
        // Only when `canPickMany` is true: a single-select list has nothing
        // to pre-check, and `ExtensionQuickPickItem.isPicked` is carried
        // truthfully regardless of `canPickMany` (`MainThreadWindow.swift`'s
        // own doc on `isPicked`), so applying it unconditionally here would
        // pre-check rows a single-select presenter has no way to show as
        // checked.
        self.checkedIndices = request.canPickMany
            ? Set(request.items.indices.filter { request.items[$0].isPicked })
            : []
    }

    // MARK: - Selection

    /// Move to the next **selectable** row in the direction `delta` names
    /// (positive is down, negative is up), skipping any number of
    /// consecutive separators, and stop at the ends rather than wrapping —
    /// `CommandPaletteModel.moveSelectionDown()` is the precedent for
    /// clamping: `selectedIndex = min(current + 1, matches.count - 1)`.
    /// Quoted rather than cited by line, because a line citation can go
    /// stale inside the very commit that introduces it — this commit's own
    /// added import already pushed that declaration from `:88` to `:89`. A
    /// separator is never selectable, and this never lands on one no matter
    /// how many are in a row.
    public func moveHighlight(by delta: Int) {
        guard let currentIndex = highlightedIndex,
              let currentRow = visibleIndices.firstIndex(of: currentIndex) else { return }
        let step = delta > 0 ? 1 : -1
        var row = currentRow + step
        while visibleIndices.indices.contains(row) {
            let itemIndex = visibleIndices[row]
            if !request.items[itemIndex].isSeparator {
                highlightedIndex = itemIndex
                return
            }
            row += step
        }
        // Ran off an end without finding another selectable row: stay put.
    }

    /// Highlight the row at `row`, a row number (an offset into
    /// `visibleIndices`) because that is what a table gives you. A no-op for
    /// a separator row or an out-of-range row.
    public func highlightRow(_ row: Int) {
        guard visibleIndices.indices.contains(row) else { return }
        let itemIndex = visibleIndices[row]
        guard !request.items[itemIndex].isSeparator else { return }
        highlightedIndex = itemIndex
    }

    /// Flip whether the row at `row` is checked. A no-op when
    /// `request.canPickMany` is false, when the row is a separator, or when
    /// `row` is out of range.
    public func toggleCheck(row: Int) {
        guard request.canPickMany else { return }
        guard visibleIndices.indices.contains(row) else { return }
        let itemIndex = visibleIndices[row]
        guard !request.items[itemIndex].isSeparator else { return }
        if checkedIndices.contains(itemIndex) {
            checkedIndices.remove(itemIndex)
        } else {
            checkedIndices.insert(itemIndex)
        }
    }

    // MARK: - Answer

    /// What the seam answers with. In single-select, the highlighted index
    /// as a one-element array, or nil when nothing is highlighted. In
    /// multi-select, the checked indices in ascending order — possibly
    /// empty, which is an answer and not a dismissal.
    public func acceptedIndices() -> [Int]? {
        guard request.canPickMany else {
            guard let highlightedIndex else { return nil }
            return [highlightedIndex]
        }
        return checkedIndices.sorted()
    }

    // MARK: - Filtering

    /// The filter, instance-free so a test can call it against a literal
    /// array with no model and no window.
    ///
    /// 1. A query that is empty or only whitespace returns every index in
    ///    order, separators included.
    /// 2. Otherwise a **non-separator** item at index `i` survives when any
    ///    of these holds, with both sides put through `TextFolding.folded(_:)`
    ///    and compared with `contains`: `item.alwaysShow` is true; the folded
    ///    `label` contains the folded query; `matchOnDescription` is true and
    ///    the folded `description` contains it; `matchOnDetail` is true and
    ///    the folded `detail` contains it. A nil `description`/`detail`
    ///    matches nothing.
    /// 3. A **separator** survives only when at least one non-separator item
    ///    that survived rule 2 lies after it and before the next separator.
    ///
    ///    Rule 3 is our rule, not a quoted upstream one: a heading over an
    ///    empty section is a heading over nothing. This brief did not verify
    ///    what VS Code itself does here, so this doc comment does not claim
    ///    it does the same.
    public static func visibleIndices(
        for query: String,
        in items: [ExtensionQuickPickItem],
        matchOnDescription: Bool,
        matchOnDetail: Bool
    ) -> [Int] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Array(items.indices) }

        let foldedQuery = TextFolding.folded(trimmed)
        let itemSurvives = items.map { item -> Bool in
            guard !item.isSeparator else { return false }
            if item.alwaysShow { return true }
            if TextFolding.folded(item.label).contains(foldedQuery) { return true }
            if matchOnDescription, let description = item.description,
               TextFolding.folded(description).contains(foldedQuery) {
                return true
            }
            if matchOnDetail, let detail = item.detail,
               TextFolding.folded(detail).contains(foldedQuery) {
                return true
            }
            return false
        }

        var result: [Int] = []
        for (index, item) in items.enumerated() {
            if item.isSeparator {
                if sectionHasSurvivor(after: index, in: items, itemSurvives: itemSurvives) {
                    result.append(index)
                }
            } else if itemSurvives[index] {
                result.append(index)
            }
        }
        return result
    }

    /// Whether some non-separator item after `separatorIndex` and before the
    /// next separator survived rule 2.
    private static func sectionHasSurvivor(
        after separatorIndex: Int, in items: [ExtensionQuickPickItem], itemSurvives: [Bool]
    ) -> Bool {
        var index = separatorIndex + 1
        while items.indices.contains(index), !items[index].isSeparator {
            if itemSurvives[index] { return true }
            index += 1
        }
        return false
    }

    private static func firstSelectableIndex(in visibleIndices: [Int], items: [ExtensionQuickPickItem]) -> Int? {
        for itemIndex in visibleIndices where !items[itemIndex].isSeparator {
            return itemIndex
        }
        return nil
    }

    private func recompute() {
        visibleIndices = Self.visibleIndices(
            for: storedQuery,
            in: request.items,
            matchOnDescription: request.matchOnDescription,
            matchOnDetail: request.matchOnDetail
        )
        highlightedIndex = Self.firstSelectableIndex(in: visibleIndices, items: request.items)
    }
}
