//
//  LSPCompletionEntryTests.swift
//  AgenticToolkit
//

import Foundation
import LanguageServerProtocol
import Testing
@testable import AgenticToolkitMacOS

/// The row model behind the completion window.
///
/// Nothing here needs a server: the whole type is a mapping from an LSP
/// `CompletionItem` onto `CodeSuggestionEntry`, and a mapping is exactly the
/// kind of code that rots silently when a field is renamed underneath it.
@Suite("LSPCompletionEntry")
@MainActor
struct LSPCompletionEntryTests {

    private let anyRange = LSPRange(
        start: Position(line: 0, character: 0),
        end: Position(line: 0, character: 0)
    )

    @Test("an item's label, detail, plain documentation and deprecation are carried through")
    func mapsPlainItem() {
        let item = CompletionItem(
            label: "makeWidget(with:)",
            kind: .function,
            detail: "(Configuration) -> Widget",
            documentation: .optionA("Builds a widget."),
            deprecated: true,
            filterText: "makeWidget"
        )
        let entry = LSPCompletionEntry(item: item, requestRange: anyRange)

        #expect(entry.label == "makeWidget(with:)")
        #expect(entry.detail == "(Configuration) -> Widget")
        #expect(entry.documentation == "Builds a widget.")
        #expect(entry.deprecated)
        // LSP says filter on `filterText` when the server sent one, which is
        // not always the label — `makeWidget(with:)` would never match what the
        // user types.
        #expect(entry.filterKey == "makeWidget")
    }

    @Test("markup documentation is unwrapped to its value")
    func mapsMarkupDocumentation() {
        let item = CompletionItem(
            label: "widget",
            documentation: .optionB(MarkupContent(kind: .markdown, value: "**bold**"))
        )
        let entry = LSPCompletionEntry(item: item, requestRange: anyRange)

        #expect(entry.documentation == "**bold**")
    }

    @Test("an item with nothing optional set reports nothing, and is not deprecated")
    func mapsBareItem() {
        let entry = LSPCompletionEntry(item: CompletionItem(label: "widget"), requestRange: anyRange)

        #expect(entry.label == "widget")
        #expect(entry.detail == nil)
        #expect(entry.documentation == nil)
        // `deprecated` is `Bool?` on the wire and `Bool` on the protocol, so an
        // item that never mentioned it must read as "not deprecated" rather
        // than crashing or defaulting the other way.
        #expect(entry.deprecated == false)
        // No `filterText`: the label is the fallback LSP prescribes.
        #expect(entry.filterKey == "widget")
    }

    @Test("the three jump-to-definition members of the protocol are nil for a completion")
    func reportsNoJumpTarget() {
        let entry = LSPCompletionEntry(item: CompletionItem(label: "widget"), requestRange: anyRange)

        // `CodeSuggestionEntry` is shared with `JumpToDefinitionLink`, which
        // fills these in. A completion has no target file, no target position
        // and no source line — and a non-nil value here would make the package
        // render a jump affordance on a completion row.
        #expect(entry.pathComponents == nil)
        #expect(entry.targetPosition == nil)
        #expect(entry.sourcePreview == nil)
    }

    @Test("the request range is carried on the entry, not recomputed later")
    func carriesRequestRange() {
        let range = LSPRange(
            start: Position(line: 3, character: 4),
            end: Position(line: 3, character: 9)
        )
        let entry = LSPCompletionEntry(item: CompletionItem(label: "widget"), requestRange: range)

        // The range cannot be recovered when the user picks the row: the live
        // caret has moved by whatever was typed while the window was open.
        #expect(entry.requestRange == range)
    }
}
