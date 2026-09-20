import Foundation
import Testing
@testable import AgenticToolkitCore

/// Resolving the `%key%` placeholders a `package.json` uses for every string a
/// person will read.
///
/// **The symptom this exists for was on screen.** Material Icon Theme's
/// settings listed `%configuration.activeIconPack%`, `%configuration.title%`
/// and seventy-one more, because a manifest that ships translations does not
/// put English in `package.json` — it puts a key there and the English in
/// `package.nls.json`. An extension with no translations at all was unaffected
/// and looked perfect, which is why this was easy to miss.
@Suite
struct ExtensionManifestLocalizationTests {

    // MARK: - Fixtures

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManifestLocalization-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func write(_ contents: String, named name: String, in directory: URL) throws {
        try contents.write(
            to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    /// A manifest whose user-facing strings are all placeholders, shaped like a
    /// real one: a top-level field, a field inside an array, and a field
    /// nested three levels down inside `contributes.configuration`.
    private let manifest = """
        {
            "name": "widget",
            "publisher": "acme",
            "version": "1.0.0",
            "displayName": "%extension.title%",
            "description": "%extension.blurb%",
            "engines": { "vscode": "^1.74.0" },
            "contributes": {
                "commands": [ { "command": "acme.widget.run", "title": "%command.run%" } ],
                "configuration": [ {
                    "title": "%configuration.title%",
                    "properties": {
                        "acme.widget.mode": {
                            "type": "string",
                            "default": "fast",
                            "description": "%configuration.mode%"
                        }
                    }
                } ]
            }
        }
        """

    private func decode(_ data: Data) throws -> ExtensionManifest {
        try JSONDecoder().decode(ExtensionManifest.self, from: data)
    }

    private func localizedManifest(
        in directory: URL,
        locale: Locale = Locale(identifier: "en_US")
    ) throws -> ExtensionManifest {
        try decode(ExtensionManifestLocalization.localize(
            Data(manifest.utf8), forManifestIn: directory, locale: locale))
    }

    // MARK: - The default table

    @Test("package.nls.json supplies the strings the manifest only has keys for")
    func theDefaultTableSuppliesTheStrings() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try write("""
            {
                "extension.title": "Widget",
                "extension.blurb": "Widgets, for you",
                "command.run": "Run the widget",
                "configuration.title": "Widget",
                "configuration.mode": "How hard the widget tries"
            }
            """, named: "package.nls.json", in: directory)

        let decoded = try localizedManifest(in: directory)

        #expect(decoded.displayName == "Widget")
        #expect(decoded.description == "Widgets, for you")
        #expect(decoded.contributes?.commands.first?.title == "Run the widget")
        #expect(decoded.contributes?.configuration.first?.title == "Widget")
        #expect(decoded.contributes?.configuration.first?
            .properties["acme.widget.mode"]?.description == "How hard the widget tries")
    }

    /// The fields that are not for reading must come through untouched — an
    /// identifier that picked up a translation would install under one name
    /// and be looked up under another.
    @Test("the identifying fields are not translated")
    func theIdentifyingFieldsAreUntouched() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try write("""
            {"extension.title": "Widget", "widget": "NOT THE NAME", "1.0.0": "NOT THE VERSION"}
            """, named: "package.nls.json", in: directory)

        let decoded = try localizedManifest(in: directory)

        #expect(decoded.name == "widget")
        #expect(decoded.version == "1.0.0")
        #expect(decoded.identifier == "acme.widget")
    }

    // MARK: - Which table

    @Test("a table for the reader's language is preferred over the default one")
    func theReadersLanguageWins() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try write(#"{"extension.title": "Widget"}"#, named: "package.nls.json", in: directory)
        try write(#"{"extension.title": "Widget auf Deutsch"}"#,
                  named: "package.nls.de.json", in: directory)

        let decoded = try localizedManifest(in: directory, locale: Locale(identifier: "de_DE"))

        #expect(decoded.displayName == "Widget auf Deutsch")
    }

    /// `package.nls.pt-BR.json` and `package.nls.pt-PT.json` both ship in real
    /// extensions, and they are not interchangeable.
    @Test("a regional table is preferred over its own language's")
    func aRegionalTableWins() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try write(#"{"extension.title": "Widget"}"#, named: "package.nls.json", in: directory)
        try write(#"{"extension.title": "Widget PT"}"#,
                  named: "package.nls.pt.json", in: directory)
        try write(#"{"extension.title": "Widget BR"}"#,
                  named: "package.nls.pt-BR.json", in: directory)

        let decoded = try localizedManifest(in: directory, locale: Locale(identifier: "pt_BR"))

        #expect(decoded.displayName == "Widget BR")
    }

    /// A translation is nearly always less complete than the English it was
    /// made from, so the default table has to stay underneath rather than be
    /// replaced — otherwise picking a language turns some strings back into
    /// placeholders, which is worse than not translating at all.
    @Test("a key the translation is missing still comes from the default table")
    func theDefaultTableFillsTheGapsInATranslation() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try write("""
            {"extension.title": "Widget", "command.run": "Run the widget"}
            """, named: "package.nls.json", in: directory)
        try write(#"{"extension.title": "Widget auf Deutsch"}"#,
                  named: "package.nls.de.json", in: directory)

        let decoded = try localizedManifest(in: directory, locale: Locale(identifier: "de_DE"))

        #expect(decoded.displayName == "Widget auf Deutsch")
        #expect(decoded.contributes?.commands.first?.title == "Run the widget")
    }

    @Test("a language with no table of its own falls back to the default")
    func anUntranslatedLanguageFallsBack() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try write(#"{"extension.title": "Widget"}"#, named: "package.nls.json", in: directory)

        let decoded = try localizedManifest(in: directory, locale: Locale(identifier: "ja_JP"))

        #expect(decoded.displayName == "Widget")
    }

    // MARK: - The other entry shape

    /// The newer table format gives each entry a message and a translator's
    /// comment. Both shapes appear in extensions on the registry today, and an
    /// object where a string was expected must not read back as a placeholder.
    @Test("an entry written as a message-and-comment object is understood")
    func theMessageAndCommentShapeIsUnderstood() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try write("""
            {
                "extension.title": { "message": "Widget", "comment": ["The product name"] },
                "extension.blurb": "Widgets, for you"
            }
            """, named: "package.nls.json", in: directory)

        let decoded = try localizedManifest(in: directory)

        #expect(decoded.displayName == "Widget")
        #expect(decoded.description == "Widgets, for you")
    }

    // MARK: - Nothing to do, and nothing that works

    @Test("a manifest with no table beside it is unchanged, byte for byte")
    func noTableMeansNoChange() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = Data(manifest.utf8)
        let localized = ExtensionManifestLocalization.localize(
            original, forManifestIn: directory, locale: Locale(identifier: "en_US"))

        #expect(localized == original)
    }

    /// VS Code leaves an unresolved placeholder visible rather than blanking
    /// the field, and so does this: a name that reads `%extension.title%` says
    /// the extension's own table is incomplete, where an empty row says
    /// nothing at all *(fail-fast)*.
    @Test("a key the table does not have is left visible")
    func anUnknownKeyIsLeftVisible() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try write(#"{"extension.blurb": "Widgets, for you"}"#,
                  named: "package.nls.json", in: directory)

        let decoded = try localizedManifest(in: directory)

        #expect(decoded.displayName == "%extension.title%")
        #expect(decoded.description == "Widgets, for you")
    }

    /// Only a string that is *entirely* a placeholder is a reference. A
    /// percentage in ordinary prose is prose.
    @Test("a string that merely contains a percent sign is left alone")
    func proseIsNotAPlaceholder() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try write(#"{"extension.title": "Widget", "50": "fifty"}"#,
                  named: "package.nls.json", in: directory)

        let json = """
            {
                "name": "widget", "publisher": "acme", "version": "1.0.0",
                "displayName": "%extension.title%",
                "description": "Uses 50% of one core, at most",
                "engines": { "vscode": "^1.74.0" }
            }
            """
        let decoded = try decode(ExtensionManifestLocalization.localize(
            Data(json.utf8), forManifestIn: directory, locale: Locale(identifier: "en_US")))

        #expect(decoded.displayName == "Widget")
        #expect(decoded.description == "Uses 50% of one core, at most")
    }

    /// A table this cannot read must cost the extension its translations and
    /// nothing else. Refusing the manifest would turn a typo in a file nobody
    /// runs into an extension that has disappeared.
    @Test("an unreadable table leaves the manifest loadable")
    func anUnreadableTableIsNotFatal() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try write("{ this is not json", named: "package.nls.json", in: directory)

        let decoded = try localizedManifest(in: directory)

        #expect(decoded.identifier == "acme.widget")
        #expect(decoded.displayName == "%extension.title%")
    }

    /// The substitution rewrites the document, so everything it did not come
    /// for has to survive the trip.
    @Test("the values that are not strings survive the rewrite")
    func nonStringValuesSurvive() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try write(#"{"configuration.mode": "How hard it tries"}"#,
                  named: "package.nls.json", in: directory)

        let json = """
            {
                "name": "widget", "publisher": "acme", "version": "1.0.0",
                "engines": { "vscode": "^1.74.0" },
                "contributes": { "configuration": [ {
                    "title": "Widget",
                    "properties": {
                        "acme.widget.mode": {
                            "type": "number",
                            "default": 0.5,
                            "description": "%configuration.mode%"
                        },
                        "acme.widget.loud": {
                            "type": "boolean",
                            "default": true,
                            "description": "Loud"
                        },
                        "acme.widget.tags": {
                            "type": "array",
                            "default": ["a", "b"],
                            "description": "Tags"
                        }
                    }
                } ] }
            }
            """
        let decoded = try decode(ExtensionManifestLocalization.localize(
            Data(json.utf8), forManifestIn: directory, locale: Locale(identifier: "en_US")))

        let properties = try #require(decoded.contributes?.configuration.first?.properties)
        let mode = try #require(properties["acme.widget.mode"])
        let loud = try #require(properties["acme.widget.loud"])
        let tags = try #require(properties["acme.widget.tags"])

        #expect(mode.description == "How hard it tries")
        #expect(mode.default == .number(0.5))
        #expect(loud.default == .bool(true))
        #expect(tags.default == .array([.string("a"), .string("b")]))
    }
}
