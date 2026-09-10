import Testing
import Foundation
@testable import AgenticToolkitCore

@Suite
struct ExtensionManifestTests {

    private static let fullManifestJSON = """
    {
        "name": "kitchen-sink",
        "publisher": "acme",
        "version": "1.2.3",
        "displayName": "Kitchen Sink",
        "description": "Exercises every contributes key.",
        "engines": { "vscode": "^1.74.0" },
        "activationEvents": ["onStartupFinished"],
        "main": "./out/extension.js",
        "browser": "./out/extension-browser.js",
        "extensionKind": ["workspace"],
        "capabilities": {
            "untrustedWorkspaces": { "supported": "limited", "description": "partial" }
        },
        "contributes": {
            "themes": [
                { "label": "Acme Dark", "uiTheme": "vs-dark", "path": "./themes/dark.json" }
            ],
            "snippets": [
                { "language": "swift", "path": "./snippets/swift.json" }
            ],
            "languages": [
                { "id": "acme-lang", "aliases": ["Acme"], "extensions": [".acme"] }
            ],
            "commands": [
                { "command": "acme.doThing", "title": "Do Thing" }
            ],
            "keybindings": [
                { "command": "acme.doThing", "key": "ctrl+shift+d", "mac": "cmd+shift+d" }
            ],
            "menus": {
                "commandPalette": [
                    { "command": "acme.doThing", "when": "editorTextFocus" }
                ]
            },
            "configuration": [
                {
                    "title": "Acme",
                    "properties": {
                        "acme.enabled": { "type": "boolean", "default": true }
                    }
                }
            ],
            "views": {
                "explorer": [
                    { "id": "acmeView", "name": "Acme View" }
                ]
            },
            "viewsContainers": {
                "activitybar": [
                    { "id": "acmeContainer", "title": "Acme", "icon": "./icon.svg" }
                ]
            },
            "languageModelTools": [
                { "name": "acme.tool", "displayName": "Acme Tool" }
            ]
        }
    }
    """

    private static let minimalManifestJSON = """
    { "name": "bare", "version": "0.0.1", "engines": { "vscode": "^1.74.0" } }
    """

    @Test("decodes a full manifest exercising every contributes key")
    func decodesFullManifest() throws {
        let manifest = try JSONDecoder().decode(
            ExtensionManifest.self,
            from: Data(Self.fullManifestJSON.utf8)
        )

        #expect(manifest.identifier == "acme.kitchen-sink")
        #expect(manifest.engines.vscode == "^1.74.0")
        #expect(manifest.activationEvents == ["onStartupFinished"])

        let contributes = try #require(manifest.contributes)
        #expect(contributes.themes.count == 1)
        #expect(contributes.snippets.count == 1)
        #expect(contributes.languages.count == 1)
        #expect(contributes.commands.count == 1)
        #expect(contributes.keybindings.count == 1)
        #expect(contributes.menus["commandPalette"]?.count == 1)
        #expect(contributes.configuration.count == 1)
        #expect(contributes.configuration.first?.properties["acme.enabled"]?.effectiveType == "boolean")
        #expect(contributes.views["explorer"]?.count == 1)
        #expect(contributes.viewsContainers["activitybar"]?.count == 1)
        #expect(contributes.languageModelTools.count == 1)
        #expect(contributes.decodingFailures.isEmpty)
    }

    @Test("a minimal manifest defaults every contributes array to empty, not nil")
    func decodesMinimalManifest() throws {
        let manifest = try JSONDecoder().decode(
            ExtensionManifest.self,
            from: Data(Self.minimalManifestJSON.utf8)
        )

        // No publisher, so `identifier` falls back to the bare name — the
        // identity every setting, uninstall and withdrawal keys on.
        #expect(manifest.identifier == "bare")
        #expect(manifest.contributes == nil)
        #expect(manifest.activationEvents.isEmpty)
        #expect(manifest.capabilities == nil)

        // The `Contributions` type itself defaults every array/dictionary to
        // empty when its key is absent, independent of the manifest omitting
        // `contributes` entirely.
        let emptyContributes = try JSONDecoder().decode(
            ExtensionManifest.Contributions.self,
            from: Data("{}".utf8)
        )
        #expect(emptyContributes.themes.isEmpty)
        #expect(emptyContributes.snippets.isEmpty)
        #expect(emptyContributes.languages.isEmpty)
        #expect(emptyContributes.commands.isEmpty)
        #expect(emptyContributes.keybindings.isEmpty)
        #expect(emptyContributes.menus.isEmpty)
        #expect(emptyContributes.configuration.isEmpty)
        #expect(emptyContributes.views.isEmpty)
        #expect(emptyContributes.viewsContainers.isEmpty)
        #expect(emptyContributes.languageModelTools.isEmpty)
        #expect(emptyContributes.decodingFailures.isEmpty)
    }

    @Test("a missing name fails to decode")
    func missingNameFails() {
        let json = """
        { "version": "0.0.1", "engines": { "vscode": "^1.74.0" } }
        """
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8))
        }
    }

    @Test("all three untrustedWorkspaces.supported forms decode and re-encode")
    func untrustedWorkspacesRoundTrips() throws {
        for (raw, expected) in [
            ("true", ExtensionManifest.Capabilities.UntrustedWorkspaces.Support.supported),
            ("false", .unsupported),
            ("\"limited\"", .limited)
        ] {
            let json = """
            { "supported": \(raw) }
            """
            let decoded = try JSONDecoder().decode(
                ExtensionManifest.Capabilities.UntrustedWorkspaces.self,
                from: Data(json.utf8)
            )
            #expect(decoded.supported == expected)

            let reencoded = try JSONEncoder().encode(decoded)
            let roundTripped = try JSONDecoder().decode(
                ExtensionManifest.Capabilities.UntrustedWorkspaces.self,
                from: reencoded
            )
            #expect(roundTripped.supported == expected)
        }
    }

    @Test("a malformed theme leaves the other themes intact and records one decodingFailure")
    func malformedThemeIsIsolated() throws {
        let json = """
        {
            "themes": [
                { "label": "Good", "uiTheme": "vs-dark", "path": "./good.json" },
                { "label": "Bad", "uiTheme": 42, "path": "./bad.json" }
            ]
        }
        """
        let contributes = try JSONDecoder().decode(
            ExtensionManifest.Contributions.self,
            from: Data(json.utf8)
        )

        #expect(contributes.themes.count == 1)
        #expect(contributes.themes.first?.label == "Good")
        #expect(contributes.decodingFailures.count == 1)
        let failure = try #require(contributes.decodingFailures.first)
        #expect(failure.key == "contributes.themes")
        #expect(failure.index == 1)
    }

    @Test("an object-form command icon drops the icon, not the command")
    func objectFormCommandIconKeepsTheCommand() throws {
        let json = """
        {
            "commands": [
                {
                    "command": "acme.doThing",
                    "title": "Do Thing",
                    "category": "Acme",
                    "enablement": "editorTextFocus",
                    "icon": { "light": "./light.svg", "dark": "./dark.svg" }
                },
                { "command": "acme.other", "title": "Other", "icon": "./plain.svg" }
            ]
        }
        """
        let contributes = try JSONDecoder().decode(
            ExtensionManifest.Contributions.self,
            from: Data(json.utf8)
        )

        #expect(contributes.commands.count == 2)
        let themed = try #require(contributes.commands.first)
        #expect(themed.command == "acme.doThing")
        #expect(themed.title == "Do Thing")
        #expect(themed.category == "Acme")
        #expect(themed.enablement == "editorTextFocus")
        #expect(themed.icon == nil)

        // The sibling with a string icon is untouched.
        #expect(contributes.commands.last?.icon == "./plain.svg")
        #expect(contributes.decodingFailures.isEmpty)
    }

    @Test("the single-object form of contributes.configuration decodes as one element")
    func singleObjectConfigurationDecodes() throws {
        let json = """
        {
            "configuration": {
                "title": "Acme",
                "properties": {
                    "acme.enabled": { "type": "boolean", "default": true }
                }
            }
        }
        """
        let contributes = try JSONDecoder().decode(
            ExtensionManifest.Contributions.self,
            from: Data(json.utf8)
        )

        #expect(contributes.configuration.count == 1)
        #expect(contributes.configuration.first?.title == "Acme")
        #expect(contributes.configuration.first?.properties["acme.enabled"]?.effectiveType == "boolean")
        #expect(contributes.decodingFailures.isEmpty)
    }

    @Test("a keyed location whose value is not an array is one failure naming that location")
    func keyedLocationThatIsNotAnArrayIsIsolated() throws {
        let json = """
        { "menus": { "editor/context": 42 } }
        """
        let contributes = try JSONDecoder().decode(
            ExtensionManifest.Contributions.self,
            from: Data(json.utf8)
        )

        #expect(contributes.menus.isEmpty)
        #expect(contributes.decodingFailures.count == 1)
        let failure = try #require(contributes.decodingFailures.first)
        #expect(failure.key == "contributes.menus.editor/context")
        #expect(failure.index == nil)
    }

    @Test("a malformed element inside a keyed location costs only itself")
    func malformedElementInsideAKeyedLocationIsIsolated() throws {
        let json = """
        {
            "menus": {
                "commandPalette": [
                    { "command": "acme.doThing", "when": "editorTextFocus" },
                    { "when": "editorTextFocus" }
                ]
            }
        }
        """
        let contributes = try JSONDecoder().decode(
            ExtensionManifest.Contributions.self,
            from: Data(json.utf8)
        )

        #expect(contributes.menus["commandPalette"]?.count == 1)
        #expect(contributes.menus["commandPalette"]?.first?.command == "acme.doThing")
        #expect(contributes.decodingFailures.count == 1)
        let failure = try #require(contributes.decodingFailures.first)
        #expect(failure.key == "contributes.menus.commandPalette")
        #expect(failure.index == 1)
    }
}
