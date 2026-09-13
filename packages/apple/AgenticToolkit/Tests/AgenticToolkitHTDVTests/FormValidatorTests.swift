import XCTest
@testable import AgenticToolkitHTDV

final class FormValidatorTests: XCTestCase {
    func testRequiredTextRejectsEmptyAndWhitespace() {
        let field = FormField.text(FormTextField(key: "name", label: "Name", isRequired: true))
        XCTAssertEqual(FormValidator.validate(field: field, value: .string("")), "Name is required")
        XCTAssertEqual(FormValidator.validate(field: field, value: .string("   ")), "Name is required")
        XCTAssertEqual(FormValidator.validate(field: field, value: .null), "Name is required")
        XCTAssertNil(FormValidator.validate(field: field, value: .string("ok")))
    }

    func testOptionalTextAcceptsEmpty() {
        let field = FormField.text(FormTextField(key: "name", label: "Name"))
        XCTAssertNil(FormValidator.validate(field: field, value: .string("")))
    }

    func testPatternUsesCustomMessage() {
        let field = FormField.text(FormTextField(
            key: "slug", label: "Slug", pattern: "^[a-z0-9-]+$", patternMessage: "Lowercase letters, digits, dashes"
        ))
        XCTAssertEqual(
            FormValidator.validate(field: field, value: .string("Bad Slug")),
            "Lowercase letters, digits, dashes"
        )
        XCTAssertNil(FormValidator.validate(field: field, value: .string("good-slug")))
    }

    func testPatternDefaultMessage() {
        let field = FormField.text(FormTextField(key: "slug", label: "Slug", pattern: "^[a-z]+$"))
        XCTAssertEqual(FormValidator.validate(field: field, value: .string("A")), "Slug has an invalid format")
    }

    func testNumberBoundsAndInteger() {
        let field = FormField.number(
            FormNumberField(key: "n", label: "Count", minimum: 1, maximum: 10, isInteger: true)
        )
        XCTAssertEqual(FormValidator.validate(field: field, value: .number(0)), "Count must be at least 1")
        XCTAssertEqual(FormValidator.validate(field: field, value: .number(11)), "Count must be at most 10")
        XCTAssertEqual(FormValidator.validate(field: field, value: .number(2.5)), "Count must be a whole number")
        XCTAssertNil(FormValidator.validate(field: field, value: .number(5)))
        XCTAssertNil(FormValidator.validate(field: field, value: .number(1)))
        XCTAssertNil(FormValidator.validate(field: field, value: .number(10)))
    }

    func testRequiredNumberRejectsNull() {
        let field = FormField.number(FormNumberField(key: "n", label: "Count", isRequired: true))
        XCTAssertEqual(FormValidator.validate(field: field, value: .null), "Count is required")
    }

    func testRequiredSelectRejectsUnknownOption() {
        let field = FormField.select(FormSelectField(
            key: "kind", label: "Kind",
            options: [FormSelectOption(value: "a", title: "A"), FormSelectOption(value: "b", title: "B")],
            isRequired: true
        ))
        XCTAssertEqual(
            FormValidator.validate(field: field, value: .string("c")),
            "Kind must be one of the listed options"
        )
        XCTAssertEqual(FormValidator.validate(field: field, value: .null), "Kind is required")
        XCTAssertNil(FormValidator.validate(field: field, value: .string("a")))
    }

    /// Both patterns in the tests above are `^…$`-anchored, so they would pass even if the validator
    /// only ever did a substring search — the anchoring came from the test, not the code. `FormSpec`
    /// documents `pattern` as matching the WHOLE value, which is the natural way a caller writes one.
    /// "My Slug!! (draft)" contains the embedded match "raft"; an unanchored `range(of:)` accepts it.
    func testUnanchoredPatternRejectsValueWithOnlyAnEmbeddedMatch() {
        let field = FormField.text(FormTextField(
            key: "slug", label: "Slug", pattern: "[a-z0-9-]{3,40}",
            patternMessage: "Lowercase letters, digits and dashes only"
        ))
        XCTAssertEqual(
            FormValidator.validate(field: field, value: .string("My Slug!! (draft)")),
            "Lowercase letters, digits and dashes only"
        )
        XCTAssertNil(FormValidator.validate(field: field, value: .string("my-slug")))
    }

    /// `format(_:)` used to be `String(Int(number))` for whole numbers, and `Int(_:)` traps rather
    /// than saturating — so a bound above `Int64.max` crashed the app while building the very error
    /// message that reports the violation. Reaching the assertion at all proves it no longer traps.
    func testOutOfIntRangeBoundFormatsInsteadOfTrapping() {
        let field = FormField.number(FormNumberField(key: "n", label: "Count", maximum: 1e19))
        XCTAssertEqual(
            FormValidator.validate(field: field, value: .number(1e20)),
            "Count must be at most 10000000000000000000"
        )
    }

    /// The `NumberFormatter` that replaced `String(Int(number))` must keep printing whole bounds
    /// without a decimal point, and fractional bounds with one. The locale is pinned because the
    /// message is deliberately locale-aware (see the two-locale test below) and this one is about
    /// the digits, not the separator.
    func testBoundFormattingKeepsWholeAndFractionalShapes() {
        let posix = Locale(identifier: "en_US_POSIX")
        let whole = FormField.number(FormNumberField(key: "n", label: "Count", minimum: 3))
        XCTAssertEqual(
            FormValidator.validate(field: whole, value: .number(1), locale: posix), "Count must be at least 3"
        )
        let fractional = FormField.number(FormNumberField(key: "n", label: "Count", minimum: 2.5))
        XCTAssertEqual(
            FormValidator.validate(field: fractional, value: .number(1), locale: posix), "Count must be at least 2.5"
        )
    }

    /// M1's `NumberFormatter` made the bound locale-aware, which is the right user-facing behaviour —
    /// a comma-decimal user should read "2,5" — but left the assertion above hard-coding a US shape,
    /// so the suite failed on a `de_DE` machine. Pin the locale and assert BOTH shapes, rather than
    /// reverting the production behaviour or rebuilding the expectation through the same formatter
    /// (which would assert nothing).
    func testBoundFormattingFollowsTheSuppliedLocale() {
        let field = FormField.number(FormNumberField(key: "n", label: "Count", minimum: 2.5))
        XCTAssertEqual(
            FormValidator.validate(field: field, value: .number(1), locale: Locale(identifier: "en_US_POSIX")),
            "Count must be at least 2.5"
        )
        XCTAssertEqual(
            FormValidator.validate(field: field, value: .number(1), locale: Locale(identifier: "de_DE")),
            "Count must be at least 2,5"
        )
    }

    func testJSONMustParse() {
        let field = FormField.json(FormJSONField(key: "cfg", label: "Config"))
        XCTAssertEqual(FormValidator.validate(field: field, value: .string("{nope")), "Config must be valid JSON")
        XCTAssertNil(FormValidator.validate(field: field, value: .string("{\"a\":1}")))
        XCTAssertNil(FormValidator.validate(field: field, value: .string("")))
    }

    func testRequiredStringSetRejectsEmpty() {
        let field = FormField.stringSet(FormStringSetField(key: "tags", label: "Tags", isRequired: true))
        XCTAssertEqual(FormValidator.validate(field: field, value: .stringSet([])), "Tags is required")
        XCTAssertNil(FormValidator.validate(field: field, value: .stringSet(["x"])))
    }

    func testRequiredDateRejectsNullAcceptsValue() {
        let field = FormField.date(FormDateField(key: "when", label: "When", isRequired: true))
        XCTAssertEqual(FormValidator.validate(field: field, value: .null), "When is required")
        XCTAssertNil(FormValidator.validate(field: field, value: .date(Date())))
    }

    func testReadOnlyAndToggleNeverFail() {
        XCTAssertNil(FormValidator.validate(field: .readOnly(FormReadOnlyField(key: "id", label: "ID")), value: .null))
        XCTAssertNil(FormValidator.validate(field: .toggle(FormToggleField(key: "on", label: "On")), value: .null))
    }

    func testSpecFlattensFields() {
        let spec = FormSpec(sections: [
            FormSection(title: "A", fields: [.text(FormTextField(key: "x", label: "X"))]),
            FormSection(fields: [.toggle(FormToggleField(key: "y", label: "Y"))])
        ])
        XCTAssertEqual(spec.fields.map(\.key), ["x", "y"])
        XCTAssertEqual(spec.fields.map(\.defaultValue), [.string(""), .bool(false)])
        XCTAssertNil(spec.actions.save)
    }

    func testFormValueAccessors() {
        XCTAssertEqual(FormValue.string("s").stringValue, "s")
        XCTAssertNil(FormValue.number(1).stringValue)
        XCTAssertEqual(FormValue.bool(true).boolValue, true)
        XCTAssertEqual(FormValue.number(2).numberValue, 2)
        XCTAssertEqual(FormValue.stringSet(["a"]).stringSetValue, ["a"])
        XCTAssertTrue(FormValue.null.isNull)
        XCTAssertFalse(FormValue.string("").isNull)
    }
}
