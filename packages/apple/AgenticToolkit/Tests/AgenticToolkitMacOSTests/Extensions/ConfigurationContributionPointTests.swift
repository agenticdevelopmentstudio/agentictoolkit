import AppKit
import AgenticToolkitCore
import Foundation
import Testing
@testable import AgenticToolkitMacOS

/// The AppKit half of `contributes.configuration`. The classification itself
/// is pinned in `ContributedSettingsBuilderTests`, where it needs no window.
///
/// Every publisher here is `test`, so every storage name these tests touch
/// begins `extensions.test.` — a namespace no real extension can reach, since
/// the identifier is `publisher.name` and no publisher on Open VSX is called
/// `test`. Each test removes what it wrote.
@MainActor
@Suite
struct ConfigurationContributionPointTests {

    // MARK: - Fixtures

    /// Handed to `apply` and never opened: a `configuration` contribution
    /// names no file, and a directory that does not exist is the cheapest way
    /// to keep that true.
    private static let unusedDirectory = URL(fileURLWithPath: "/var/empty/agentic-tests-nonexistent")

    private func manifest(
        name: String,
        displayName: String = "Test Extension",
        configuration: String
    ) throws -> ExtensionManifest {
        let json = """
        {
            "name": "\(name)",
            "publisher": "test",
            "version": "1.0.0",
            "engines": { "vscode": "^1.74.0" },
            "displayName": "\(displayName)",
            "contributes": { "configuration": \(configuration) }
        }
        """
        return try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8))
    }

    @discardableResult
    private func apply(
        _ manifest: ExtensionManifest,
        to point: ConfigurationContributionPoint
    ) throws -> ExtensionManifest {
        let contributions = try #require(manifest.contributes)
        try point.apply(contributions, from: manifest, at: Self.unusedDirectory)
        return manifest
    }

    private func descendants<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        var found: [T] = []
        if let match = view as? T { found.append(match) }
        for subview in view.subviews {
            found.append(contentsOf: descendants(type, in: subview))
        }
        return found
    }

    // MARK: - 19

    @Test("a panel carries one group per section, titled with the display name")
    func applyThenPanelProducesOneGroupPerSection() throws {
        let point = ConfigurationContributionPoint()
        let manifest = try manifest(
            name: "groups",
            displayName: "Groups Extension",
            configuration: """
            [
                { "title": "One", "properties": { "g.a": { "type": "boolean" } } },
                { "title": "Two", "properties": { "g.b": { "type": "boolean" } } }
            ]
            """)
        try apply(manifest, to: point)
        defer {
            for key in ["g.a", "g.b"] {
                UserSetting(
                    ContributedSettingsBuilder.storageName(
                        forKey: key, ofExtension: manifest.identifier),
                    default: false
                ).remove()
            }
        }

        let panel = try #require(point.panel(for: manifest.identifier))
        #expect(panel.descriptor.title == "Groups Extension")
        #expect(descendants(ComposableSettings.GroupView.self, in: panel.settingsView).count == 2)
        // The keys are the only searchable text a panel has before it is built.
        #expect(panel.searchKeywords == ["g.a", "g.b"])

        // An extension nobody applied has no panel, and applying twice leaves
        // one copy rather than two.
        #expect(point.panel(for: "test.absent") == nil)
        try apply(manifest, to: point)
        #expect(point.contributingExtensions == [manifest.identifier])
        #expect(point.sections(for: manifest.identifier).count == 2)
    }

    // MARK: - 20

    @Test("each kind of setting produces its own kind of row")
    func eachKindProducesItsRow() throws {
        let point = ConfigurationContributionPoint()
        let manifest = try manifest(name: "kinds", configuration: """
        {
            "title": "Kinds",
            "properties": {
                "k.a": { "type": "boolean", "default": true },
                "k.b": { "type": "string", "default": "hi" },
                "k.c": { "type": "string", "enum": ["on", "off"], "default": "on" },
                "k.d": { "type": "number", "default": 1.5 },
                "k.e": { "type": "integer", "default": 3 },
                "k.f": { "type": "array", "default": [1, 2] }
            }
        }
        """)
        try apply(manifest, to: point)
        defer {
            for key in ["k.a", "k.b", "k.c", "k.d", "k.e", "k.f"] {
                UserSetting(
                    ContributedSettingsBuilder.storageName(
                        forKey: key, ofExtension: manifest.identifier),
                    default: ""
                ).remove()
            }
        }

        let panel = try #require(point.panel(for: manifest.identifier))
        let root = panel.settingsView
        #expect(descendants(ComposableSettings.CheckboxView.self, in: root).count == 1)
        #expect(descendants(ComposableSettings.TextEditView.self, in: root).count == 1)
        #expect(descendants(ComposableSettings.PopupMenuChoiceView<String>.self, in: root).count == 1)
        #expect(descendants(ComposableSettings.NumberFieldView<Double>.self, in: root).count == 1)
        #expect(descendants(ComposableSettings.NumberFieldView<Int>.self, in: root).count == 1)
        // The escape hatch's editor is a `TextAreaEditView` that validates on
        // commit, so it is still one of these.
        #expect(descendants(ComposableSettings.TextAreaEditView.self, in: root).count == 1)
    }

    // MARK: - 21

    @Test("withdraw removes the sections and leaves every stored value alone")
    func withdrawRemovesTheSectionsButNotTheValues() throws {
        let point = ConfigurationContributionPoint()
        let manifest = try manifest(name: "withdrawal", configuration: """
        { "title": "W", "properties": { "w.name": { "type": "string", "default": "default" } } }
        """)
        try apply(manifest, to: point)

        let storageName = ContributedSettingsBuilder.storageName(
            forKey: "w.name", ofExtension: manifest.identifier)
        #expect(storageName == "extensions.test.withdrawal.w.name")
        let setting = UserSetting(storageName, default: "default")
        defer { setting.remove() }

        setting.value = "typed by the user"
        point.withdraw(extensionIdentifier: manifest.identifier)

        #expect(point.sections(for: manifest.identifier).isEmpty)
        #expect(point.contributingExtensions.isEmpty)
        #expect(point.notes.isEmpty)
        // Disabling an extension is not a request to forget what you typed.
        #expect(setting.existsInStore())
        #expect(setting.value == "typed by the user")
    }

    // MARK: - 22

    @Test("a number field clamps only where it was given a bound")
    func numberFieldClampsOnlyWhereBounded() throws {
        let unbounded = UserSetting("extensions.test.numberfield.unbounded", default: 0)
        let bounded = UserSetting("extensions.test.numberfield.bounded", default: 0)
        defer {
            unbounded.remove()
            bounded.remove()
        }

        let open = ComposableSettings.NumberFieldView(
            viewModel: ComposableSettings.ViewModel(title: "open", setting: unbounded))
        open.textField.stringValue = "10000"
        open.commit()
        #expect(unbounded.value == 10_000)

        let capped = ComposableSettings.NumberFieldView(
            viewModel: ComposableSettings.ViewModel(title: "capped", setting: bounded),
            maximum: 10)
        capped.textField.stringValue = "10000"
        capped.commit()
        #expect(bounded.value == 10)
        #expect(capped.textField.stringValue == "10")

        // Text that is not a number is a typo, not a zero: the field reverts.
        capped.textField.stringValue = "not a number"
        capped.commit()
        #expect(bounded.value == 10)
        #expect(capped.textField.stringValue == "10")
    }

    // MARK: - 23

    @Test("two extensions declaring the same key do not share storage")
    func twoExtensionsDeclaringTheSameKeyDoNotShareStorage() throws {
        let point = ConfigurationContributionPoint()
        let configuration = """
        { "title": "S", "properties": { "python.pythonPath": { "type": "string", "default": "py" } } }
        """
        let first = try apply(
            try manifest(name: "alpha", configuration: configuration), to: point)
        let second = try apply(
            try manifest(name: "beta", configuration: configuration), to: point)

        let left = try #require(point.sections(for: first.identifier).first?.settings.first)
        let right = try #require(point.sections(for: second.identifier).first?.settings.first)
        #expect(left.key == right.key)
        #expect(left.storageName == "extensions.test.alpha.python.pythonPath")
        #expect(right.storageName == "extensions.test.beta.python.pythonPath")

        let leftSetting = UserSetting(left.storageName, default: "py")
        let rightSetting = UserSetting(right.storageName, default: "py")
        defer {
            leftSetting.remove()
            rightSetting.remove()
        }

        leftSetting.value = "/usr/bin/python3"
        #expect(rightSetting.value == "py")
        #expect(!rightSetting.existsInStore())
        #expect(point.contributingExtensions == [first.identifier, second.identifier])
    }

    // MARK: - 24 — the escape hatch's whole point

    @Test("the escape hatch reverts text that is not JSON, and accepts a bare fragment")
    func jsonRowRevertsInvalidTextAndAcceptsAFragment() throws {
        let point = ConfigurationContributionPoint()
        let manifest = try manifest(name: "hatch", configuration: """
        { "title": "Hatch", "properties": { "h.tags": { "type": "array", "default": [1, 2] } } }
        """)
        try apply(manifest, to: point)
        let setting = UserSetting(
            ContributedSettingsBuilder.storageName(
                forKey: "h.tags", ofExtension: manifest.identifier),
            default: "")
        defer { setting.remove() }

        let panel = try #require(point.panel(for: manifest.identifier))
        // The view the panel actually built, not one made here: a test that
        // constructs its own cannot notice the panel building the wrong class.
        let editor = try #require(
            descendants(JSONTextAreaEditView.self, in: panel.settingsView).first)
        let original = editor.textView.string

        editor.textView.string = "{ not json"
        editor.commit()
        #expect(editor.textView.string == original)
        // Nothing was stored: the value's only consumer parses it, so text
        // that does not parse is not a setting with an odd value.
        #expect(!setting.existsInStore())

        // `.fragmentsAllowed` is what lets a contributed default of `3` or
        // `"auto"` be edited at all; without it the row would reject exactly
        // the text it was given.
        editor.textView.string = "3"
        editor.commit()
        #expect(setting.value == "3")
        editor.textView.string = "\"auto\""
        editor.commit()
        #expect(setting.value == "\"auto\"")
    }

    // MARK: - 25 — the Double half of the number field

    @Test("a double field writes whole numbers without a fraction and refuses non-numbers")
    func doubleFieldRendersWholeNumbersAndRefusesNonFinite() throws {
        let setting = UserSetting("extensions.test.numberfield.double", default: 2.0)
        defer { setting.remove() }

        let field = ComposableSettings.NumberFieldView(
            viewModel: ComposableSettings.ViewModel(title: "double", setting: setting),
            minimum: 0,
            maximum: 1_000)
        // A manifest that said `2` must not be shown back as `2.0`.
        #expect(field.textField.stringValue == "2")

        field.textField.stringValue = "1.5"
        field.commit()
        #expect(setting.value == 1.5)

        // `nan` parses as a Double and then makes every clamp comparison
        // false — a bounded field would accept it and rewrite on every cycle.
        field.textField.stringValue = "nan"
        field.commit()
        #expect(setting.value == 1.5)
        #expect(field.textField.stringValue == "1.5")

        field.textField.stringValue = "inf"
        field.commit()
        #expect(setting.value == 1.5)
    }

    // MARK: - 26 — locale, and the ordering that makes it safe

    @Test("a locale's decimal comma is read, and POSIX text is never re-read as grouping")
    func localeParsingIsTriedOnlyAfterPOSIX() throws {
        let german = Locale(identifier: "de_DE")
        let english = Locale(identifier: "en_US")

        // The bug: a comma-decimal edit used to be discarded as a typo.
        #expect(Double(settingsFieldString: "1,5", locale: german) == 1.5)
        #expect(Int(settingsFieldString: "1,024", locale: english) == 1_024)

        // The hazard: the writer is POSIX and `sync()` puts its output back
        // into the field, so POSIX text must survive a de_DE read untouched.
        // The locale parse alone cannot read it — hence POSIX first.
        #expect(Double(settingsFieldString: "1.5", locale: german) == 1.5)
        #expect(Double.settingsLocaleNumber(from: "1.5", locale: german) == nil)

        // And this is the pair that actually pins the ordering. Three decimal
        // digits, not one: de_DE's grouping separator is `.` with a group size
        // of three, so `"1.234"` — ordinary writer output — is well-formed
        // grouping to a de_DE formatter and comes back a thousand times too
        // big, while the `"1.5"` above is a one-digit group the formatter
        // rejects on its own and therefore passes whichever way round the
        // ladder is. Simplifying this case to `"1.5"` would silently remove the
        // only regression net the POSIX-first ordering has.
        #expect(Double(settingsFieldString: "1.234", locale: german) == 1.234)
        #expect(Double.settingsLocaleNumber(from: "1.234", locale: german)?.doubleValue == 1234)

        // An integer field stores an integer or nothing: `allowsFloats` is
        // false for `Int`, so a fractional edit is refused, not rounded.
        #expect(Int.settingsAllowsFloats == false)
        #expect(Int(settingsFieldString: "1.5", locale: english) == nil)
        #expect(Int(settingsFieldString: "1,5", locale: german) == nil)

        // The one decision `allowsFloats` makes on its own. `Int(_:)` refuses
        // an integral value spelled with a fraction, so `"1.0"` reaches the
        // locale parse with nothing but the flag between it and a stored 1 —
        // the two lines above would still pass with the flag flipped, these
        // two would not.
        #expect(Int(settingsFieldString: "1.0", locale: english) == nil)
        #expect(Int(settingsFieldString: "1,0", locale: german) == nil)

        // A partial parse is refused here rather than left to the formatter:
        // en_US reads `"12abc"` as the prefix 12 and reports consuming two
        // characters of five, and a prefix would pass every value-shaped check
        // an integer field can make.
        #expect(Int.settingsLocaleNumber(from: "12abc", locale: english) == nil)
        #expect(Int(settingsFieldString: "12abc", locale: english) == nil)

        // Grouped input keeps its exactness: routed through a `Double` this
        // would be stored as ...992, and `Int(exactly:)` would not object,
        // because the rounded double is itself a whole number.
        #expect(
            Int(settingsFieldString: "9,007,199,254,740,993", locale: english)
                == 9_007_199_254_740_993)

        // The two ends of that change. `Int.max` grouped is the largest value
        // the locale path can carry, and it only survives because the value
        // comes from `int64Value` — its `Double` is 2^63, out of range. One
        // past it must be refused, in the spelling with separators exactly as
        // in the one without: a field that says no to "9223372036854775808"
        // and yes to the same digits with commas teaches nothing a user could
        // act on.
        #expect(Int(settingsFieldString: "9,223,372,036,854,775,807", locale: english) == Int.max)
        #expect(Int(settingsFieldString: "9,223,372,036,854,775,808", locale: english) == nil)
        #expect(Int(settingsFieldString: "9223372036854775808", locale: english) == nil)

        #expect(Double(settingsFieldString: "nan", locale: english) == nil)
        #expect(Double(settingsFieldString: "not a number", locale: english) == nil)
    }

    // MARK: - 27 — the forwarder other repos link

    @Test("an integer field still commits through its delegate after the rewrite")
    func integerFieldViewForwardsItsDelegateCallback() throws {
        let setting = UserSetting("extensions.test.numberfield.integerfield", default: 4)
        defer { setting.remove() }

        let field = ComposableSettings.IntegerFieldView(
            viewModel: ComposableSettings.RangeViewModel(
                title: "padding", setting: setting, minValue: 0, maxValue: 10))
        #expect(field.textField.stringValue == "4")

        field.textField.stringValue = "7"
        field.controlTextDidEndEditing(
            Notification(name: NSControl.textDidEndEditingNotification, object: field.textField))
        #expect(setting.value == 7)

        // The view model's two bounds still clamp, which is the whole of what
        // this class promised before it became a forwarder.
        field.textField.stringValue = "99"
        field.controlTextDidEndEditing(
            Notification(name: NSControl.textDidEndEditingNotification, object: field.textField))
        #expect(setting.value == 10)
        #expect(field.textField.stringValue == "10")
    }
}
