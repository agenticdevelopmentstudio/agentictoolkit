import Testing
import Foundation
@testable import AgenticToolkitCore

/// The classification, tested where it is pure — no window, no store, no
/// run loop. Every case here pins one ruling from the corpus study.
@Suite
struct ContributedSettingsBuilderTests {

    // MARK: - Fixtures

    private typealias Built = (
        declaration: ContributedSettingsDeclaration,
        notes: [ContributedSettingNote]
    )

    /// A manifest carrying `configuration` verbatim, decoded the way the
    /// extension loader decodes one.
    private func build(
        configuration: String,
        name: String = "sample",
        publisher: String = "acme",
        displayName: String? = "Sample Extension"
    ) throws -> Built {
        let displayNameLine = displayName.map { "\"displayName\": \"\($0)\"," } ?? ""
        let json = """
        {
            "name": "\(name)",
            "publisher": "\(publisher)",
            "version": "1.0.0",
            "engines": { "vscode": "^1.74.0" },
            \(displayNameLine)
            "contributes": { "configuration": \(configuration) }
        }
        """
        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8))
        return ContributedSettingsBuilder.sections(for: manifest)
    }

    /// One section of one property, the shape most of these cases need.
    private func setting(_ key: String, _ property: String) throws -> ContributedSetting {
        let built = try build(configuration: """
        { "title": "Sample", "properties": { "\(key)": \(property) } }
        """)
        let sections = built.declaration.sections
        try #require(sections.count == 1)
        try #require(sections[0].settings.count == 1)
        return sections[0].settings[0]
    }

    private func notes(_ key: String, _ property: String) throws -> [ContributedSettingNote] {
        try build(configuration: """
        { "title": "Sample", "properties": { "\(key)": \(property) } }
        """).notes
    }

    // MARK: - 1, 2 — the object-or-array union

    @Test("the single-object form of contributes.configuration yields one section")
    func singleObjectFormDecodes() throws {
        let built = try build(configuration: """
        { "title": "One", "properties": { "a.flag": { "type": "boolean", "default": true } } }
        """)
        #expect(built.declaration.sections.map(\.title) == ["One"])
    }

    @Test("the array form yields one section per element")
    func arrayFormDecodes() throws {
        let built = try build(configuration: """
        [
            { "title": "One", "properties": { "a.flag": { "type": "boolean" } } },
            { "title": "Two", "properties": { "a.name": { "type": "string" } } }
        ]
        """)
        #expect(built.declaration.sections.map(\.title) == ["One", "Two"])
    }

    // MARK: - 3 — storage is per extension, the key is verbatim

    @Test("two extensions declaring the same key get different storage names")
    func storageNamesAreNamespacedPerExtension() throws {
        let property = """
        { "title": "S", "properties": { "python.pythonPath": { "type": "string", "default": "py" } } }
        """
        let first = try build(configuration: property, name: "pyright", publisher: "anysphere")
        let second = try build(configuration: property, name: "python", publisher: "ms-python")

        let left = try #require(first.declaration.sections.first?.settings.first)
        let right = try #require(second.declaration.sections.first?.settings.first)

        #expect(left.storageName == "extensions.anysphere.pyright.python.pythonPath")
        #expect(right.storageName == "extensions.ms-python.python.python.pythonPath")
        #expect(left.storageName != right.storageName)
        // The row's own title stays the dotted key exactly as declared.
        #expect(left.key == "python.pythonPath")
        #expect(right.key == "python.pythonPath")
    }

    // MARK: - 4, 5 — union types

    @Test("a nullable union collapses to its one real type, and its siblings survive")
    func unionTypeCollapses() throws {
        let built = try build(configuration: """
        {
            "title": "Sample",
            "properties": {
                "a.name": { "type": ["string", "null"], "default": "auto" },
                "a.flag": { "type": "boolean", "default": true }
            }
        }
        """)
        let sections = built.declaration.sections
        try #require(sections.count == 1)
        // The regression the section-wide drop caused: one union type used to
        // throw out of the decoder and take every sibling with it.
        #expect(sections[0].settings.map(\.key) == ["a.flag", "a.name"])

        guard case .text(let value, let multiline) = sections[0].settings[1].kind else {
            Issue.record("expected .text, got \(sections[0].settings[1].kind)")
            return
        }
        #expect(value == "auto")
        #expect(multiline == false)
        guard case .toggle(let flag) = sections[0].settings[0].kind else {
            Issue.record("expected .toggle, got \(sections[0].settings[0].kind)")
            return
        }
        #expect(flag)
    }

    @Test("a union whose members disagree falls to the JSON escape hatch")
    func mixedUnionFallsToJSON() throws {
        let setting = try setting("a.mixed", """
        { "type": ["boolean", "string"], "default": true }
        """)
        guard case .json(let text) = setting.kind else {
            Issue.record("expected .json, got \(setting.kind)")
            return
        }
        #expect(text == "true")

        let recorded = try notes("a.mixed", """
        { "type": ["boolean", "string"], "default": true }
        """)
        #expect(recorded.map(\.kind) == [.mixedUnionType])
        #expect(recorded[0].key == "a.mixed")
        #expect(recorded[0].extensionIdentifier == "acme.sample")
    }

    // MARK: - 6, 7, 8 — enums

    @Test("an all-string enum becomes a choice, labelled positionally")
    func stringEnumBecomesChoice() throws {
        let setting = try setting("a.mode", """
        {
            "type": "string",
            "enum": ["off", "on", "auto"],
            "enumItemLabels": ["Never", "Always", null],
            "default": "on"
        }
        """)
        guard case .choice(let options, let selected) = setting.kind else {
            Issue.record("expected .choice, got \(setting.kind)")
            return
        }
        #expect(options.map(\.label) == ["Never", "Always", "auto"])
        #expect(options.map(\.value) == ["off", "on", "auto"])
        #expect(selected == "on")
    }

    @Test("a default outside its own enum is prepended as an option of its own")
    func defaultOutsideEnumIsPrepended() throws {
        let property = """
        { "type": "string", "enum": ["a", "b"], "default": "legacy" }
        """
        let setting = try setting("a.mode", property)
        guard case .choice(let options, let selected) = setting.kind else {
            Issue.record("expected .choice, got \(setting.kind)")
            return
        }
        #expect(options.map(\.value) == ["legacy", "a", "b"])
        #expect(selected == "legacy")
        #expect(try notes("a.mode", property).map(\.kind) == [.defaultNotInEnum])
    }

    @Test("an enum with a non-string member is ignored in favour of the type")
    func nonStringEnumIgnoresTheEnum() throws {
        let property = """
        { "type": "boolean", "enum": [true, "auto"], "default": true }
        """
        let setting = try setting("a.mode", property)
        guard case .toggle(let flag) = setting.kind else {
            Issue.record("expected .toggle, got \(setting.kind)")
            return
        }
        #expect(flag)
        #expect(try notes("a.mode", property).map(\.kind) == [.nonStringEnum])
    }

    // MARK: - 9 — numbers

    @Test("a number with no bounds keeps nil bounds rather than inventing any")
    func numberWithoutBoundsKeepsNilBounds() throws {
        let setting = try setting("a.size", """
        { "type": "number", "default": 1.5 }
        """)
        guard case .number(let value, let minimum, let maximum) = setting.kind else {
            Issue.record("expected .number, got \(setting.kind)")
            return
        }
        #expect(value == 1.5)
        #expect(minimum == nil)
        #expect(maximum == nil)
    }

    @Test("a number with both bounds carries them through unchanged")
    func numberWithBothBounds() throws {
        let setting = try setting("a.size", """
        { "type": "number", "default": 1.5, "minimum": 0.5, "maximum": 2.5 }
        """)
        guard case .number(let value, let minimum, let maximum) = setting.kind else {
            Issue.record("expected .number, got \(setting.kind)")
            return
        }
        #expect(value == 1.5)
        #expect(minimum == 0.5)
        #expect(maximum == 2.5)
    }

    // MARK: - 10, 11 — the declared type wins over the default

    @Test("a null default under a real type falls to that type's zero value")
    func nullDefaultFallsToZeroValue() throws {
        let property = """
        { "type": "string", "default": null }
        """
        let setting = try setting("a.name", property)
        guard case .text(let value, let multiline) = setting.kind else {
            Issue.record("expected .text, got \(setting.kind)")
            return
        }
        #expect(value.isEmpty)
        #expect(multiline == false)
        #expect(try notes("a.name", property).map(\.kind) == [.defaultTypeMismatch])
    }

    @Test("a default of the wrong JSON type does not change the row")
    func mismatchedDefaultUsesTheDeclaredType() throws {
        let property = """
        { "type": "boolean", "default": "yes" }
        """
        let setting = try setting("a.flag", property)
        guard case .toggle(let flag) = setting.kind else {
            Issue.record("expected .toggle, got \(setting.kind)")
            return
        }
        #expect(flag == false)
        #expect(try notes("a.flag", property).map(\.kind) == [.defaultTypeMismatch])
    }

    // MARK: - 12 — inference

    @Test("with no type, the default's own JSON type decides — and nothing decides nothing")
    func noTypeInfersFromDefault() throws {
        let inferred = try setting("a.count", """
        { "default": 3 }
        """)
        guard case .integer(let value, let minimum, let maximum) = inferred.kind else {
            Issue.record("expected .integer, got \(inferred.kind)")
            return
        }
        #expect(value == 3)
        #expect(minimum == nil)
        #expect(maximum == nil)

        let bare = try setting("a.mystery", """
        { "description": "nothing to go on" }
        """)
        guard case .json(let text) = bare.kind else {
            Issue.record("expected .json, got \(bare.kind)")
            return
        }
        #expect(text == "null")
        #expect(try notes("a.mystery", """
        { "description": "nothing to go on" }
        """).map(\.kind) == [.unrenderableType])
    }

    // MARK: - 13 — the escape hatch's text

    @Test("array and object defaults arrive as pretty-printed, key-sorted JSON")
    func arrayAndObjectGetTheEscapeHatch() throws {
        let object = try setting("a.map", """
        { "type": "object", "default": { "zebra": 1, "apple": [1, 2] } }
        """)
        guard case .json(let text) = object.kind else {
            Issue.record("expected .json, got \(object.kind)")
            return
        }
        // Pinned semantically rather than byte-for-byte: `JSONSerialization`'s
        // pretty printer is the platform's, and its exact spacing is not this
        // code's promise. What *is* promised: the same value, keys in sorted
        // order, over more than one line.
        let reparsed = try JSONDecoder().decode(
            ExtensionManifest.JSONValue.self, from: Data(text.utf8))
        #expect(reparsed == .object([
            "apple": .array([.number(1), .number(2)]),
            "zebra": .number(1)
        ]))
        let apple = try #require(text.range(of: "\"apple\""))
        let zebra = try #require(text.range(of: "\"zebra\""))
        #expect(apple.lowerBound < zebra.lowerBound)
        #expect(text.contains("\n"))
        // A whole number stays whole: `20` must not come back as `20.0`.
        #expect(!text.contains(".0"))

        let array = try setting("a.list", """
        { "type": "array", "default": ["b", "a"] }
        """)
        guard case .json(let listText) = array.kind else {
            Issue.record("expected .json, got \(array.kind)")
            return
        }
        // An array's own order is data, not presentation: it is not sorted.
        #expect(try JSONDecoder().decode(
            ExtensionManifest.JSONValue.self, from: Data(listText.utf8))
            == .array([.string("b"), .string("a")]))
    }

    // MARK: - 14 — multiline

    @Test("editPresentation multilineText asks for an editor, not a field")
    func multilineTextIsHonoured() throws {
        let setting = try setting("a.template", """
        { "type": "string", "default": "hi", "editPresentation": "multilineText" }
        """)
        guard case .text(let value, let multiline) = setting.kind else {
            Issue.record("expected .text, got \(setting.kind)")
            return
        }
        #expect(value == "hi")
        #expect(multiline)
    }

    // MARK: - 15 — ordering

    @Test("order comes first, then the key alphabetically — for settings and sections")
    func orderingIsOrderThenKey() throws {
        let built = try build(configuration: """
        [
            {
                "title": "Zeta",
                "order": 2,
                "properties": {
                    "z.alpha": { "type": "boolean", "order": 1 },
                    "a.beta": { "type": "boolean", "order": 2 },
                    "m.gamma": { "type": "boolean" },
                    "b.delta": { "type": "boolean" }
                }
            },
            { "title": "Alpha", "properties": { "x.one": { "type": "boolean" } } },
            { "title": "Beta", "order": 1, "properties": { "x.two": { "type": "boolean" } } }
        ]
        """)
        let sections = built.declaration.sections
        // `order` ascending, then everything without one — so the section
        // titled "Alpha" comes last, which no accidental sort produces.
        #expect(sections.map(\.title) == ["Beta", "Zeta", "Alpha"])
        #expect(sections[1].settings.map(\.key) == ["z.alpha", "a.beta", "b.delta", "m.gamma"])
    }

    // MARK: - 16, 17, 18 — sections and prose

    @Test("a section with no title borrows the extension's display name, and says so")
    func missingSectionTitleFallsBackToDisplayName() throws {
        let built = try build(configuration: """
        { "properties": { "a.flag": { "type": "boolean", "default": false } } }
        """)
        #expect(built.declaration.sections.map(\.title) == ["Sample Extension"])
        #expect(built.notes.map(\.kind) == [.missingSectionTitle])
        #expect(built.notes[0].key == "Sample Extension")

        // With no displayName either, the package name is the last fallback.
        let bare = try build(
            configuration: """
            { "properties": { "a.flag": { "type": "boolean", "default": false } } }
            """,
            displayName: nil)
        #expect(bare.declaration.sections.map(\.title) == ["sample"])
    }

    @Test("a deprecation message is appended to the explanation after a blank line")
    func deprecationIsAppendedToTheExplanation() throws {
        let setting = try setting("a.old", """
        {
            "type": "boolean",
            "default": false,
            "description": "Turns the thing on.",
            "deprecationMessage": "Use a.new instead."
        }
        """)
        #expect(setting.explanation == "Turns the thing on.\n\nUse a.new instead.")
        #expect(try notes("a.old", """
        {
            "type": "boolean",
            "default": false,
            "description": "Turns the thing on.",
            "deprecationMessage": "Use a.new instead."
        }
        """).map(\.kind) == [.deprecated])
    }

    @Test("a section with no properties produces no section, and none at all is undeclared")
    func emptySectionIsDropped() throws {
        let built = try build(configuration: """
        [
            { "title": "Empty", "properties": {} },
            { "title": "Real", "properties": { "a.flag": { "type": "boolean" } } }
        ]
        """)
        #expect(built.declaration.sections.map(\.title) == ["Real"])

        // Declared-but-empty and never-declared are different sentences, and
        // an empty array cannot tell them apart.
        let onlyEmpty = try build(configuration: """
        { "title": "Empty", "properties": {} }
        """)
        #expect(onlyEmpty.declaration == .declared(sections: []))

        let none = try JSONDecoder().decode(
            ExtensionManifest.self,
            from: Data("""
            {
                "name": "sample", "publisher": "acme", "version": "1.0.0",
                "engines": { "vscode": "^1.74.0" }
            }
            """.utf8))
        #expect(ContributedSettingsBuilder.sections(for: none).declaration == .undeclared)
    }

    // MARK: - 24 — note order

    @Test("notes come out in sorted-key order, not the dictionary's order")
    func notesFollowSortedKeyOrderNotDisplayOrder() throws {
        // Five note-producing properties, each a different kind, with `order`
        // reversing their display order. Notes follow the *key*, so a build
        // that emitted them in display order — or in whatever order the
        // properties dictionary happened to hash into this process — fails.
        let built = try build(configuration: """
        {
            "title": "Notes",
            "properties": {
                "e.five": {
                    "type": "string", "order": 1,
                    "enum": ["a", "b"], "default": "a", "enumDescriptions": ["A", "B"]
                },
                "d.four": {
                    "type": "string", "order": 2,
                    "enum": ["a", 2], "default": "a"
                },
                "c.three": { "type": ["boolean", "string"], "order": 3, "default": "x" },
                "b.two": { "type": "widget", "order": 4, "default": "x" },
                "a.one": { "type": "boolean", "order": 5 }
            }
        }
        """)
        let section = try #require(built.declaration.sections.first)
        #expect(section.settings.map(\.key) == ["e.five", "d.four", "c.three", "b.two", "a.one"])
        #expect(built.notes.map(\.key) == ["a.one", "b.two", "c.three", "d.four", "e.five"])
        #expect(built.notes.map(\.kind) == [
            .missingDefault, .unrenderableType, .mixedUnionType,
            .nonStringEnum, .enumDescriptionsDropped
        ])
    }

    // MARK: - 25 — the corpus shapes the decoder was changed for

    @Test("a type spelled [\"number\", null] is still a number")
    func nullMemberInATypeUnionSurvives() throws {
        // Four corpus properties spell nullability with a JSON null rather
        // than the string "null". Decoded into [String] the whole property
        // throws; here it collapses to `number` like its written-out sibling.
        let nullMember = try setting("a.size", """
        { "type": ["number", null], "default": 1.5 }
        """)
        guard case .number(let value, _, _) = nullMember.kind else {
            Issue.record("expected a number, got \(nullMember.kind)")
            return
        }
        #expect(value == 1.5)

        let spelled = try setting("a.size", """
        { "type": ["number", "null"], "default": 1.5 }
        """)
        #expect(spelled.kind == nullMember.kind)
    }

    @Test("a property survives a field it spells wrongly, and its siblings survive it entirely")
    func aMistypedFieldCostsOnlyThatField() throws {
        // Eight corpus properties write `"order": "0"`. The property arrives
        // without an order rather than not arriving.
        let built = try build(configuration: """
        {
            "title": "Lenient",
            "properties": {
                "a.first": { "type": "boolean", "default": false, "order": "0" },
                "b.second": { "type": "boolean", "default": false, "order": 1 }
            }
        }
        """)
        let section = try #require(built.declaration.sections.first)
        #expect(section.settings.map(\.key) == ["b.second", "a.first"])
        #expect(section.settings.map(\.order) == [1, nil])

        // And a property that is not an object at all takes only itself down:
        // decoded as one dictionary, it would take every sibling with it.
        let broken = try build(configuration: """
        {
            "title": "Broken",
            "properties": {
                "a.rubbish": "not an object",
                "b.fine": { "type": "boolean", "default": true }
            }
        }
        """)
        #expect(broken.declaration.sections.first?.settings.map(\.key) == ["b.fine"])
    }

    @Test("a property round-trips through encode and back, union type and all")
    func propertyEncodingIsAFixedPoint() throws {
        let json = """
        {
            "type": ["string", "null"],
            "default": "b",
            "description": "A choice.",
            "enum": ["a", "b", null],
            "enumItemLabels": [null, "Bee"],
            "scope": "window",
            "order": 3,
            "minimum": 0,
            "maximum": 10,
            "editPresentation": "multilineText"
        }
        """
        let decoder = JSONDecoder()
        let first = try decoder.decode(
            ExtensionManifest.ConfigurationProperty.self, from: Data(json.utf8))
        let second = try decoder.decode(
            ExtensionManifest.ConfigurationProperty.self,
            from: try JSONEncoder().encode(first))
        #expect(second == first)
        #expect(second.type == .union(["string", "null"]))
        #expect(second.effectiveType == "string")

        // The other spelling of `type` has its own encode branch.
        let single = try decoder.decode(
            ExtensionManifest.ConfigurationProperty.self,
            from: Data("{ \"type\": \"boolean\", \"default\": true }".utf8))
        let again = try decoder.decode(
            ExtensionManifest.ConfigurationProperty.self,
            from: try JSONEncoder().encode(single))
        #expect(again == single)
        #expect(again.type == .single("boolean"))
    }

    // MARK: - 26 — the note for a property that declares no default

    @Test("a property with no default says so, and the row takes the type's zero")
    func missingDefaultIsReported() throws {
        #expect(try notes("a.flag", "{ \"type\": \"boolean\" }").map(\.kind) == [.missingDefault])
        #expect(try setting("a.flag", "{ \"type\": \"boolean\" }").kind == .toggle(default: false))
        #expect(try notes("a.name", "{ \"type\": \"string\" }").map(\.kind) == [.missingDefault])
    }

    // MARK: - F36 — one key is one storage slot, so one key is one row

    @Test("a key declared by two sections of one extension yields one row")
    func aKeyDeclaredTwiceYieldsOneRow() throws {
        let built = try build(configuration: """
        [
            {
                "title": "General",
                "properties": { "acme.mode": { "type": "boolean", "default": false } }
            },
            {
                "title": "Advanced",
                "properties": { "acme.mode": { "type": "string", "default": "auto" } }
            }
        ]
        """)

        let rows = built.declaration.sections.flatMap(\.settings)
        #expect(rows.count == 1)
        // The first declaration stands: a second row would bind a String view
        // to the slot the Bool view already owns.
        #expect(rows.first?.kind == .toggle(default: false))
        #expect(built.notes.contains { $0.kind == .duplicateKey && $0.key == "acme.mode" })
    }

    // MARK: - F37 — bounds that contradict each other are not bounds

    @Test("an inverted minimum and maximum are dropped rather than passed on")
    func invertedBoundsAreDropped() throws {
        let row = try setting(
            "acme.size", """
            { "type": "number", "default": 5, "minimum": 10, "maximum": 1 }
            """)
        #expect(row.kind == .number(default: 5, minimum: nil, maximum: nil))

        let notes = try notes(
            "acme.size", """
            { "type": "number", "default": 5, "minimum": 10, "maximum": 1 }
            """)
        #expect(notes.contains { $0.kind == .contradictoryBounds })
    }

    @Test("integer bounds that invert only after rounding inward are dropped too")
    func integerBoundsThatInvertAfterRoundingAreDropped() throws {
        let row = try setting(
            "acme.count", """
            { "type": "integer", "default": 1, "minimum": 0.5, "maximum": 0.9 }
            """)
        #expect(row.kind == .integer(default: 1, minimum: nil, maximum: nil))
    }

    @Test("a default outside its own bounds is brought inside them and said so")
    func defaultOutsideItsBoundsIsClamped() throws {
        let row = try setting(
            "acme.size", """
            { "type": "number", "default": 5, "minimum": 10, "maximum": 20 }
            """)
        #expect(row.kind == .number(default: 10, minimum: 10, maximum: 20))

        let notes = try notes(
            "acme.size", """
            { "type": "number", "default": 5, "minimum": 10, "maximum": 20 }
            """)
        #expect(notes.contains { $0.kind == .defaultOutOfRange })
    }

    // MARK: - F46 — "declares nothing" is not "I could not read what it declares"

    @Test("a configuration key that is present but unreadable is not undeclared")
    func unreadableConfigurationIsNotUndeclared() throws {
        let built = try build(configuration: "\"see the docs\"")

        #expect(built.declaration != .undeclared)
        #expect(built.declaration.sections.isEmpty)
        if case .unreadable = built.declaration {
            // expected
        } else {
            Issue.record("expected .unreadable, got \(built.declaration)")
        }
    }

    @Test("a configuration key that is genuinely absent stays undeclared")
    func absentConfigurationStaysUndeclared() throws {
        let none = try JSONDecoder().decode(
            ExtensionManifest.self,
            from: Data("""
            {
                "name": "sample", "publisher": "acme", "version": "1.0.0",
                "engines": { "vscode": "^1.74.0" },
                "contributes": { "commands": [] }
            }
            """.utf8))
        #expect(ContributedSettingsBuilder.sections(for: none).declaration == .undeclared)
    }
}
