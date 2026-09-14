import Testing
@testable import AgenticToolkitMacOS

/// Pins `ExtensionQuickPickViewController.handleRowClick(_:)` — the seam
/// `rowClicked()` forwards `tableView.clickedRow` to. Drives it
/// directly with a row number rather than a real mouse event, the way
/// `TopicListViewControllerTests` forces `loadView` and calls in.
@Suite("ExtensionQuickPickViewController")
@MainActor
struct ExtensionQuickPickViewControllerTests {

    private func item(_ label: String, isSeparator: Bool = false) -> ExtensionQuickPickItem {
        ExtensionQuickPickItem(
            label: label,
            description: nil,
            detail: nil,
            isSeparator: isSeparator,
            isPicked: false,
            alwaysShow: false
        )
    }

    private func request(items: [ExtensionQuickPickItem], canPickMany: Bool = false) -> ExtensionQuickPickRequest {
        ExtensionQuickPickRequest(
            title: nil,
            placeHolder: nil,
            prompt: nil,
            items: items,
            canPickMany: canPickMany,
            matchOnDescription: false,
            matchOnDetail: false,
            ignoreFocusOut: false
        )
    }

    private func makeLoaded(
        model: ExtensionQuickPickModel
    ) -> ExtensionQuickPickViewController {
        let controller = ExtensionQuickPickViewController(model: model)
        _ = controller.view // force loadView so the table exists
        return controller
    }

    @Test("a click on a separator row does not accept whatever was previously highlighted")
    func clickOnSeparatorDoesNotAcceptStaleHighlight() {
        let items = [item("a"), item("sep", isSeparator: true), item("b")]
        let model = ExtensionQuickPickModel(request: request(items: items))
        let controller = makeLoaded(model: model)

        var accepted: [Int]?
        controller.onAccept = { accepted = $0 }

        #expect(model.highlightedIndex == 0)
        controller.handleRowClick(1) // the separator's row
        #expect(accepted == nil, "a separator click must not accept the previously highlighted row")
        #expect(model.highlightedIndex == 0, "a separator click must not move the highlight either")
    }

    @Test("a click on a real single-select row highlights and accepts it")
    func clickOnRealRowAcceptsIt() {
        let items = [item("a"), item("b")]
        let model = ExtensionQuickPickModel(request: request(items: items))
        let controller = makeLoaded(model: model)

        var accepted: [Int]?
        controller.onAccept = { accepted = $0 }

        controller.handleRowClick(1)
        #expect(accepted == [1])
        #expect(model.highlightedIndex == 1)
    }

    @Test("a click on a real multi-select row toggles its check and accepts nothing")
    func clickOnRealRowInMultiSelectTogglesCheck() {
        let items = [item("a"), item("b")]
        let model = ExtensionQuickPickModel(request: request(items: items, canPickMany: true))
        let controller = makeLoaded(model: model)

        var accepted: [Int]?
        controller.onAccept = { accepted = $0 }

        controller.handleRowClick(1)
        #expect(model.checkedIndices == [1])
        #expect(accepted == nil, "a multi-select click must not close the panel")
    }

    @Test("a click on a separator row in multi-select does not check it")
    func clickOnSeparatorInMultiSelectDoesNotCheck() {
        let items = [item("sep", isSeparator: true), item("a")]
        let model = ExtensionQuickPickModel(request: request(items: items, canPickMany: true))
        let controller = makeLoaded(model: model)

        controller.handleRowClick(0)
        #expect(model.checkedIndices == [])
    }

    @Test("a negative row (no row clicked) does nothing")
    func negativeRowIsNoOp() {
        let items = [item("a")]
        let model = ExtensionQuickPickModel(request: request(items: items))
        let controller = makeLoaded(model: model)

        var accepted: [Int]?
        controller.onAccept = { accepted = $0 }

        controller.handleRowClick(-1)
        #expect(accepted == nil)
    }
}
