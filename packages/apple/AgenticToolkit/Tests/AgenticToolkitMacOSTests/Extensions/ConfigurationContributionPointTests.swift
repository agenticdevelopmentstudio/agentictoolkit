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
}
