import Testing
@testable import AgenticToolkitCore

@Suite
struct TextFoldingTests {

    @Test("case and diacritic fold to the same string")
    func foldsCaseAndDiacritic() {
        #expect(TextFolding.folded("CAFÉ") == TextFolding.folded("cafe"))
    }

    @Test("the empty string folds to the empty string")
    func foldsEmptyString() {
        #expect(TextFolding.folded("") == "")
    }
}
