import Testing
@testable import AgenticToolkitMacOS

/// Pins the quick pick's filter, highlight and checked-set behaviour — see
/// `ExtensionQuickPickModel`'s own doc comment for why none of it needs a
/// window. The first eight cases call `visibleIndices(for:in:...)` directly
/// against a literal array; the rest build a model instance.
@Suite("ExtensionQuickPickModel")
@MainActor
struct ExtensionQuickPickModelTests {

    private func item(
        _ label: String,
        description: String? = nil,
        detail: String? = nil,
        isSeparator: Bool = false,
        isPicked: Bool = false,
        alwaysShow: Bool = false
    ) -> ExtensionQuickPickItem {
        ExtensionQuickPickItem(
            label: label,
            description: description,
            detail: detail,
            isSeparator: isSeparator,
            isPicked: isPicked,
            alwaysShow: alwaysShow
        )
    }

    private func request(
        items: [ExtensionQuickPickItem],
        canPickMany: Bool = false,
        matchOnDescription: Bool = false,
        matchOnDetail: Bool = false
    ) -> ExtensionQuickPickRequest {
        ExtensionQuickPickRequest(
            title: nil,
            placeHolder: nil,
            prompt: nil,
            items: items,
            canPickMany: canPickMany,
            matchOnDescription: matchOnDescription,
            matchOnDetail: matchOnDetail,
            ignoreFocusOut: false
        )
    }

    // MARK: - Filtering (static)

    @Test("an empty query returns every index, separators included")
    func emptyQueryReturnsEverything() {
        let items = [item("a"), item("sep", isSeparator: true), item("b")]
        let result = ExtensionQuickPickModel.visibleIndices(
            for: "", in: items, matchOnDescription: false, matchOnDetail: false)
        #expect(result == [0, 1, 2])
    }

    @Test("a whitespace-only query behaves as an empty one")
    func whitespaceQueryBehavesAsEmpty() {
        let items = [item("a"), item("b")]
        let result = ExtensionQuickPickModel.visibleIndices(
            for: "   ", in: items, matchOnDescription: false, matchOnDetail: false)
        #expect(result == [0, 1])
    }

    @Test("a query matching one label returns that index and drops the others")
    func queryMatchesOneLabelExactly() {
        let items = [item("alpha"), item("beta"), item("gamma")]
        let result = ExtensionQuickPickModel.visibleIndices(
            for: "bet", in: items, matchOnDescription: false, matchOnDetail: false)
        #expect(result == [1])
    }

    @Test("matchOnDescription gates matching on an item's description")
    func matchOnDescriptionGatesMatch() {
        let items = [item("alpha", description: "needle")]
        let withoutFlag = ExtensionQuickPickModel.visibleIndices(
            for: "needle", in: items, matchOnDescription: false, matchOnDetail: false)
        let withFlag = ExtensionQuickPickModel.visibleIndices(
            for: "needle", in: items, matchOnDescription: true, matchOnDetail: false)
        #expect(withoutFlag == [])
        #expect(withFlag == [0])
    }

    @Test("matchOnDetail gates matching on an item's detail")
    func matchOnDetailGatesMatch() {
        let items = [item("alpha", detail: "needle")]
        let withoutFlag = ExtensionQuickPickModel.visibleIndices(
            for: "needle", in: items, matchOnDescription: false, matchOnDetail: false)
        let withFlag = ExtensionQuickPickModel.visibleIndices(
            for: "needle", in: items, matchOnDescription: false, matchOnDetail: true)
        #expect(withoutFlag == [])
        #expect(withFlag == [0])
    }

    @Test("alwaysShow keeps an item whose label, description and detail all fail the query")
    func alwaysShowKeepsNonMatchingItem() {
        let items = [item("alpha", description: "beta", detail: "gamma", alwaysShow: true)]
        let result = ExtensionQuickPickModel.visibleIndices(
            for: "zzz", in: items, matchOnDescription: true, matchOnDetail: true)
        #expect(result == [0])
    }

    @Test("a separator is dropped when its section is filtered away, kept when one item survives")
    func separatorSurvivesOnlyWithASurvivingSection() {
        let items = [
            item("Section A", isSeparator: true),
            item("keep"),
            item("Section B", isSeparator: true),
            item("drop")
        ]
        let result = ExtensionQuickPickModel.visibleIndices(
            for: "keep", in: items, matchOnDescription: false, matchOnDetail: false)
        #expect(result == [0, 1])
    }

    @Test("a diacritic in the item and a plain query match each other")
    func diacriticFoldMatchesPlainQuery() {
        let items = [item("Café")]
        let result = ExtensionQuickPickModel.visibleIndices(
            for: "cafe", in: items, matchOnDescription: false, matchOnDetail: false)
        #expect(result == [0])
    }

    // MARK: - Selection and answer (instance)

    @Test("moveHighlight(by: 1) from immediately above a separator lands after it, not on it")
    func moveHighlightSkipsSeparator() {
        let items = [item("a"), item("sep", isSeparator: true), item("b")]
        let model = ExtensionQuickPickModel(request: request(items: items))
        model.moveHighlight(by: 1)
        #expect(model.highlightedIndex == 2)
    }

    @Test("two adjacent separators are both skipped in one moveHighlight(by: 1)")
    func moveHighlightSkipsTwoAdjacentSeparators() {
        let items = [item("a"), item("sep1", isSeparator: true), item("sep2", isSeparator: true), item("b")]
        let model = ExtensionQuickPickModel(request: request(items: items))
        model.moveHighlight(by: 1)
        #expect(model.highlightedIndex == 3)
    }

    @Test("moveHighlight(by: -1) at the first selectable row stays there")
    func moveHighlightUpClampsAtFirstRow() {
        let items = [item("a"), item("b")]
        let model = ExtensionQuickPickModel(request: request(items: items))
        model.moveHighlight(by: -1)
        #expect(model.highlightedIndex == 0)
    }

    @Test("a query matching nothing leaves highlightedIndex nil, and acceptedIndices() nil")
    func queryMatchingNothingClearsHighlightAndAcceptance() {
        let items = [item("a"), item("b")]
        let model = ExtensionQuickPickModel(request: request(items: items))
        model.query = "zzz"
        #expect(model.highlightedIndex == nil)
        #expect(model.acceptedIndices() == nil)
    }

    @Test("isPicked items are pre-checked only when canPickMany is true, on the same fixture")
    func isPickedPreChecksOnlyWhenCanPickMany() {
        let items = [item("a", isPicked: true), item("b")]
        let multiModel = ExtensionQuickPickModel(request: request(items: items, canPickMany: true))
        #expect(multiModel.checkedIndices == [0])
        let singleModel = ExtensionQuickPickModel(request: request(items: items, canPickMany: false))
        #expect(singleModel.checkedIndices == [])
    }

    @Test("in multi-select, acceptedIndices() with nothing checked returns an empty array, not nil")
    func acceptedIndicesEmptyInMultiSelectIsNotNil() {
        let items = [item("a"), item("b")]
        let model = ExtensionQuickPickModel(request: request(items: items, canPickMany: true))
        #expect(model.acceptedIndices() == [])
    }

    @Test("toggleCheck(row:) checks an unchecked row, and un-checks it again on a second call")
    func toggleCheckFlipsARealRow() {
        let items = [item("a"), item("b")]
        let model = ExtensionQuickPickModel(request: request(items: items, canPickMany: true))
        #expect(model.checkedIndices == [])

        model.toggleCheck(row: 1)
        #expect(model.checkedIndices == [1])

        model.toggleCheck(row: 1)
        #expect(model.checkedIndices == [])
    }

    @Test("toggleCheck(row:) on a separator row changes nothing, even reached from a non-empty checked set")
    func toggleCheckOnSeparatorRowIsNoOp() {
        let items = [item("sep", isSeparator: true), item("a")]
        let model = ExtensionQuickPickModel(request: request(items: items, canPickMany: true))
        model.toggleCheck(row: 1)
        #expect(model.checkedIndices == [1])

        model.toggleCheck(row: 0)
        #expect(model.checkedIndices == [1])
    }

    @Test("toggleCheck(row:) does nothing when canPickMany is false")
    func toggleCheckNoOpWhenSingleSelect() {
        let items = [item("a")]
        let model = ExtensionQuickPickModel(request: request(items: items, canPickMany: false))
        model.toggleCheck(row: 0)
        #expect(model.checkedIndices == [])
    }

    @Test("toggleCheck(row:) does nothing for a row past the end of visibleIndices")
    func toggleCheckNoOpWhenRowOutOfRange() {
        let items = [item("a")]
        let model = ExtensionQuickPickModel(request: request(items: items, canPickMany: true))
        model.toggleCheck(row: 5)
        #expect(model.checkedIndices == [])
    }

    @Test("highlightRow(_:) moves highlightedIndex to a real row")
    func highlightRowMovesToARealRow() {
        let items = [item("a"), item("b"), item("c")]
        let model = ExtensionQuickPickModel(request: request(items: items))
        #expect(model.highlightedIndex == 0)

        model.highlightRow(2)
        #expect(model.highlightedIndex == 2)
    }

    @Test("highlightRow(_:) on a separator row leaves highlightedIndex unchanged")
    func highlightRowNoOpOnSeparator() {
        let items = [item("a"), item("sep", isSeparator: true), item("b")]
        let model = ExtensionQuickPickModel(request: request(items: items))
        #expect(model.highlightedIndex == 0)

        model.highlightRow(1)
        #expect(model.highlightedIndex == 0)
    }

    @Test("highlightRow(_:) on an out-of-range row leaves highlightedIndex unchanged")
    func highlightRowNoOpWhenRowOutOfRange() {
        let items = [item("a"), item("b")]
        let model = ExtensionQuickPickModel(request: request(items: items))
        model.highlightRow(1)
        #expect(model.highlightedIndex == 1)

        model.highlightRow(99)
        #expect(model.highlightedIndex == 1)
    }
}
