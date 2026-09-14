import Foundation
import Testing
@testable import AgenticToolkitMacOS

/// Pins `ExtensionInputBoxModel`'s accept/reject rule and initial-selection
/// arithmetic — see that type's own doc comment for why neither needs a
/// window.
@Suite("ExtensionInputBoxModel")
@MainActor
struct ExtensionInputBoxModelTests {

    private func request(
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

    @Test("canAccept is false only after an .error validation")
    func canAcceptFalseOnlyAfterError() {
        let model = ExtensionInputBoxModel(request: request())

        model.recordValidation(ExtensionInputValidation(message: "m", severity: .error))
        #expect(model.canAccept == false)

        model.recordValidation(ExtensionInputValidation(message: "m", severity: .warning))
        #expect(model.canAccept == true)

        model.recordValidation(ExtensionInputValidation(message: "m", severity: .information))
        #expect(model.canAccept == true)

        model.recordValidation(nil)
        #expect(model.canAccept == true)
    }

    @Test("setting value after an .error clears validation and restores canAccept")
    func settingValueClearsErrorValidation() {
        let model = ExtensionInputBoxModel(request: request(value: "abc"))
        model.recordValidation(ExtensionInputValidation(message: "m", severity: .error))
        #expect(model.canAccept == false)

        model.value = "abcd"
        #expect(model.validation == nil)
        #expect(model.canAccept == true)
    }

    @Test("initialSelection() returns nil for a request with no selection")
    func initialSelectionNilWhenNoSelection() {
        let model = ExtensionInputBoxModel(request: request(value: "hello", valueSelection: nil))
        #expect(model.initialSelection() == nil)
    }

    @Test("initialSelection() returns the given range for a request with a valid selection")
    func initialSelectionReturnsGivenRange() {
        let model = ExtensionInputBoxModel(request: request(value: "hello", valueSelection: 1..<3))
        #expect(model.initialSelection() == 1..<3)
    }

    @Test("initialSelection() clamps to the value's length when it is shorter than the recorded end")
    func initialSelectionClampsToValueLength() {
        let model = ExtensionInputBoxModel(request: request(value: "hi", valueSelection: 1..<10))
        #expect(model.initialSelection() == 1..<2)
    }

    @Test("initialSelectionUTF16Range() converts a Character-offset range to UTF-16 offsets for a non-BMP value")
    func initialSelectionUTF16RangeConvertsNonBMPCharacter() {
        // "👍ab": 3 Characters (👍, a, b) but 4 UTF-16 units — 👍 is a
        // surrogate pair, occupying two units by itself. Character offset 1
        // (the start of "a") is UTF-16 offset 2; Character offset 3 (the end
        // of the string) is UTF-16 offset 4. Feeding the Character-offset
        // range 1..<3 straight into `NSRange(location:length:)` (the F7 bug)
        // would have produced `NSRange(location: 1, length: 2)`, which lands
        // one code unit into the middle of 👍's surrogate pair rather than
        // selecting "ab".
        let model = ExtensionInputBoxModel(request: request(value: "👍ab", valueSelection: 1..<3))
        #expect(model.initialSelection() == 1..<3)
        #expect(model.initialSelectionUTF16Range() == NSRange(location: 2, length: 2))
    }

    @Test("initialSelectionUTF16Range() selects the whole value in UTF-16 terms when there is no selection")
    func initialSelectionUTF16RangeCoversWholeNonBMPValueWhenNil() {
        let model = ExtensionInputBoxModel(request: request(value: "👍ab", valueSelection: nil))
        #expect(model.initialSelectionUTF16Range() == NSRange(location: 0, length: 4))
    }
}
