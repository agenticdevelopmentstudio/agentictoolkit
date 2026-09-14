import AppKit
import Testing
@testable import AgenticToolkitMacOS

/// Pins fix round 1's F1: `ExtensionPickerWindowController.init` reads
/// `content.preferredContentSize` only after forcing `content.view` to load
/// (see that type's own doc comment). The evidence F1's own report gave was
/// an inference from `NSViewController.loadView`'s lifecycle, not a
/// measurement — these tests measure the **window** itself, the way
/// `TabPaneViewControllerTests` measures `preferredContentSize` elsewhere in
/// this target.
@Suite("ExtensionPickerWindowController")
@MainActor
struct ExtensionPickerWindowControllerTests {

    // MARK: - Quick pick fixtures
    // Same shape as `ExtensionQuickPickViewControllerTests`'s own fixtures.

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

    private func quickPickRequest(
        items: [ExtensionQuickPickItem], canPickMany: Bool = false
    ) -> ExtensionQuickPickRequest {
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

    // MARK: - Input box fixture
    // Same shape as `ExtensionInputBoxModelTests`'s own fixture.

    private func inputBoxRequest(
        value: String = "",
        valueSelection: Range<Int>? = nil,
        isPassword: Bool = false,
        isValidating: Bool = false
    ) -> ExtensionInputBoxRequest {
        ExtensionInputBoxRequest(
            title: nil,
            prompt: nil,
            placeHolder: nil,
            value: value,
            valueSelection: valueSelection,
            isPassword: isPassword,
            ignoreFocusOut: false,
            isValidating: isValidating
        )
    }

    // MARK: - Tests

    /// Does NOT kill the F1 mutation (moving the `preferredContentSize` read
    /// back above `let hostedView = content.view` in
    /// `ExtensionPickerWindowController.init`). `ExtensionQuickPickViewController`
    /// sets `preferredContentSize = NSSize(width: 560, height: 400)` in its
    /// own `init` (`ExtensionQuickPickViewController.swift:71`), so the value
    /// is already present no matter how early the window controller reads
    /// it — reverting F1 would still leave this panel 560x400. This is a
    /// positive control that the sizing path (content size -> panel content
    /// rect -> window frame) works at all, not a mutation-killer.
    @Test(
        """
        quick pick window is 560x400 from ExtensionQuickPickViewController's own preferredContentSize \
        (does not kill the F1 mutation — that value is set in init, not loadView)
        """
    )
    func quickPickWindowSizedToFixedPreferredContentSize() {
        let model = ExtensionQuickPickModel(request: quickPickRequest(items: [item("a"), item("b")]))
        let content = ExtensionQuickPickViewController(model: model)
        let windowController = ExtensionPickerWindowController(content: content, ignoreFocusOut: false)

        let size = windowController.window?.frame.size
        #expect(size == NSSize(width: 560, height: 400))
    }

    /// Kills the F1 mutation. `ExtensionInputBoxViewController` sets
    /// `preferredContentSize` only at the end of `loadView()`
    /// (`ExtensionInputBoxViewController.swift:127`), computed from the
    /// assembled Auto Layout height — never in `init`. Reverting F1 (reading
    /// `preferredContentSize` before forcing `content.view` to load) would
    /// read that property before it is ever set, i.e. `NSZeroSize`, and this
    /// panel's window would collapse to zero. Asserted against
    /// `content.preferredContentSize` itself rather than a retyped height,
    /// since that height comes from Auto Layout and is not a spelled
    /// constant — only the `72` floor is.
    @Test(
        """
        input box window is sized to ExtensionInputBoxViewController's own computed preferredContentSize, \
        at least the 72pt floor (kills the F1 mutation — that value is set at the end of loadView, not init)
        """
    )
    func inputBoxWindowSizedToComputedPreferredContentSize() {
        let model = ExtensionInputBoxModel(request: inputBoxRequest(value: "hello"))
        let content = ExtensionInputBoxViewController(model: model)
        let windowController = ExtensionPickerWindowController(content: content, ignoreFocusOut: false)

        // `ExtensionPickerWindowController.init` has already forced
        // `content.view` to load (and with it, `loadView()`'s
        // `preferredContentSize` assignment) by the time this constructor
        // returns, so reading it now reads the same value `loadView()` set —
        // not a value this test computes independently.
        let expected = content.preferredContentSize
        #expect(expected.height >= 72, "loadView() floors the height at 72")

        let size = windowController.window?.frame.size
        #expect(size == expected)
    }
}
