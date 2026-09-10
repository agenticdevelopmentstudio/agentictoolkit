//
//  ContributedSettings.swift
//  AgenticToolkit
//

import Foundation

/// One selectable member of a contributed `enum` setting.
public struct ContributedSettingOption: Sendable, Equatable {
    /// What the popup shows — `enumItemLabels[i]` when the manifest supplied
    /// one, otherwise the member itself.
    public let label: String
    /// What is stored. Always the member exactly as the manifest wrote it, so
    /// a value read back is the value VS Code would have read back.
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// The control one contributed setting resolves to.
///
/// Six cases, not one per JSON Schema type: this is the vocabulary of rows the
/// settings window actually has, and `json` is the honest name for "the schema
/// says something no row can express, so the value is edited as text".
public enum ContributedSettingKind: Sendable, Equatable {
    case toggle(default: Bool)
    case text(default: String, multiline: Bool)
    case choice(options: [ContributedSettingOption], default: String)
    case number(default: Double, minimum: Double?, maximum: Double?)
    case integer(default: Int, minimum: Int?, maximum: Int?)
    /// The escape hatch: the pretty-printed JSON text of the declared default,
    /// edited as text and parsed by whatever reads it. Arrays, objects, unions
    /// whose members disagree, and anything with nothing to classify on.
    case json(default: String)
}

/// One row of a generated settings panel.
public struct ContributedSetting: Sendable, Equatable {
    /// The dotted VS Code key, verbatim — and the row's title.
    ///
    /// Not a humanised leaf. The first segment matches the extension's own
    /// name only 84% of the time in the Open VSX corpus (`anysphere.pyright`
    /// declares `python.pythonPath`), so stripping a namespace strips the one
    /// token that says which setting this is. VS Code's own settings UI shows
    /// the full key for the same reason.
    public let key: String
    /// `extensions.<identifier>.<key>`.
    ///
    /// Per extension rather than under the raw VS Code key because 389 keys in
    /// the corpus are declared by more than one extension, 18 of them
    /// disagreeing on `(type, default)` — one flat slot provably cannot hold
    /// both — and because withdrawal has to name exactly what one extension
    /// owns.
    public let storageName: String
    /// `description`, else `markdownDescription` as plain text, with any
    /// deprecation message appended after a blank line.
    public let explanation: String?
    public let kind: ContributedSettingKind
    /// The manifest's own `order`, kept so a caller can see why a row sits
    /// where it does. Already applied to `ContributedSettingsSection.settings`.
    public let order: Int?

    public init(
        key: String,
        storageName: String,
        explanation: String?,
        kind: ContributedSettingKind,
        order: Int?
    ) {
        self.key = key
        self.storageName = storageName
        self.explanation = explanation
        self.kind = kind
        self.order = order
    }
}

/// One `contributes.configuration` section, as a group of rows.
public struct ContributedSettingsSection: Sendable, Equatable {
    public let title: String
    public let order: Int?
    /// Already sorted: `order` ascending where declared, then alphabetically
    /// by key. `Configuration.properties` is a `Dictionary`, so the manifest's
    /// own order is gone before this type ever sees it — and a panel that
    /// reshuffles itself between launches is a defect, not a detail.
    public let settings: [ContributedSetting]

    public init(title: String, order: Int?, settings: [ContributedSetting]) {
        self.title = title
        self.order = order
        self.settings = settings
    }
}

/// Something a manifest declared that this host could not honour exactly.
///
/// A record rather than a thrown error, for the reason `SnippetFileFailure` is
/// one: a property this host cannot render must not cost the extension its
/// other properties, and what was compromised is shown to a person rather than
/// swallowed.
public struct ContributedSettingNote: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        /// Nothing to classify on, so the value is edited as JSON text.
        case unrenderableType
        /// A union type whose members genuinely disagree (`[boolean, string]`).
        case mixedUnionType
        /// An `enum` with a non-string member, ignored in favour of `type`.
        case nonStringEnum
        /// A default outside its own `enum`, kept as a choice of its own.
        case defaultNotInEnum
        /// A default whose JSON type contradicts the declared type, including
        /// a `null` default under a non-null type. The declared type wins.
        case defaultTypeMismatch
        case missingDefault
        /// `enumDescriptions`/`markdownEnumDescriptions` were present and are
        /// not rendered: they describe the *selected* member, which is
        /// per-selection state no row here owns yet.
        case enumDescriptionsDropped
        case deprecated
        case missingSectionTitle
    }

    public let extensionIdentifier: String
    /// The property key, or the section title for a section-level note.
    public let key: String
    public let kind: Kind
    public let detail: String

    public init(extensionIdentifier: String, key: String, kind: Kind, detail: String) {
        self.extensionIdentifier = extensionIdentifier
        self.key = key
        self.kind = kind
        self.detail = detail
    }
}

/// What a manifest had to say about settings.
///
/// Two cases rather than an array that is sometimes empty, because "this
/// extension has no settings" and "this extension declared settings and none
/// of them survived" are different sentences a panel has to write differently —
/// and an empty array makes the caller guess which one it is holding.
public enum ContributedSettingsDeclaration: Sendable, Equatable {
    /// No `contributes.configuration` at all.
    case undeclared
    /// Declared. `sections` is still empty when every declared section held no
    /// properties (33 sections in the corpus do).
    case declared(sections: [ContributedSettingsSection])

    public var sections: [ContributedSettingsSection] {
        switch self {
        case .undeclared: []
        case .declared(let sections): sections
        }
    }
}

/// Turns `contributes.configuration` into rows a settings panel can build.
///
/// Pure and Foundation-only: this is where every ruling about what a schema
/// means lives, so it can be tested without a window, a store or a run loop.
/// Nothing here reads or writes a setting — it only says what row a setting
/// deserves and where its value would be stored.
public enum ContributedSettingsBuilder {

    // MARK: - Entry points

    /// The sections `manifest` contributes, and every compromise made to reach
    /// them.
    public static func sections(
        for manifest: ExtensionManifest
    ) -> (declaration: ContributedSettingsDeclaration, notes: [ContributedSettingNote]) {
        sections(
            for: manifest.contributes?.configuration ?? [],
            ofExtension: manifest.identifier,
            fallbackTitle: manifest.displayName ?? manifest.name
        )
    }

    /// The same, from a `Contributions` block held on its own.
    ///
    /// `ContributionPoint.apply` is handed its contributions as a parameter
    /// rather than reaching back through the manifest for them, and a point
    /// that ignored that parameter in favour of `manifest.contributes` would
    /// be answering a question it was not asked — which is exactly what the
    /// reference implementation, `SnippetStore.apply`, avoids by reading
    /// `contributions.snippets`. The registry happens to pass
    /// `manifest.contributes` at both of today's call sites, so the two are
    /// identical in practice; the parameter is the contract and the manifest
    /// is the current caller's implementation detail, and honouring the
    /// parameter is what keeps room for a caller that synthesises
    /// contributions rather than decoding them.
    ///
    /// `public` is the module boundary, not a guess at a future need: this
    /// type is `AgenticToolkitCore` and its only consumer,
    /// `ConfigurationContributionPoint`, is `AgenticToolkitMacOS`.
    ///
    /// - Parameter fallbackTitle: the title a section with none borrows —
    ///   `displayName ?? name`. 21 of the corpus's 741 sections have no title.
    public static func sections(
        for configuration: [ExtensionManifest.Configuration],
        ofExtension identifier: String,
        fallbackTitle: String
    ) -> (declaration: ContributedSettingsDeclaration, notes: [ContributedSettingNote]) {
        guard !configuration.isEmpty else { return (.undeclared, []) }

        var notes: [ContributedSettingNote] = []
        var built: [(index: Int, section: ContributedSettingsSection)] = []

        for (index, section) in configuration.enumerated() {
            // A section with no properties is not an empty group on screen;
            // it is nothing at all.
            guard !section.properties.isEmpty else { continue }

            let title: String
            if let declared = section.title, !declared.isEmpty {
                title = declared
            } else {
                title = fallbackTitle
                notes.append(ContributedSettingNote(
                    extensionIdentifier: identifier,
                    key: title,
                    kind: .missingSectionTitle,
                    detail: "section \(index) declared no title; using \"\(fallbackTitle)\""
                ))
            }

            var settings: [ContributedSetting] = []
            // Sorted keys, not `for (key, property) in`: a `Dictionary`'s
            // iteration order is not stable across launches, and it would
            // reach the outside world here through `notes`.
            for key in section.properties.keys.sorted() {
                guard let property = section.properties[key] else { continue }
                let (kind, propertyNotes) = classify(property, key: key, ofExtension: identifier)
                notes.append(contentsOf: propertyNotes)
                if let deprecation = deprecation(of: property) {
                    notes.append(ContributedSettingNote(
                        extensionIdentifier: identifier, key: key,
                        kind: .deprecated, detail: deprecation))
                }
                settings.append(ContributedSetting(
                    key: key,
                    storageName: storageName(forKey: key, ofExtension: identifier),
                    explanation: explanation(of: property),
                    kind: kind,
                    order: property.order
                ))
            }

            built.append((
                index,
                ContributedSettingsSection(
                    title: title,
                    order: section.order,
                    settings: settings.sorted(by: precedes))
            ))
        }

        return (.declared(sections: built.sorted(by: precedes).map(\.section)), notes)
    }

    /// Where one contributed setting's value lives.
    ///
    /// Public because a caller that wants to read a contributed value — or
    /// prove in a test that two extensions do not share a slot — must not have
    /// to re-spell this format and drift from it.
    public static func storageName(forKey key: String, ofExtension identifier: String) -> String {
        "extensions.\(identifier).\(key)"
    }

    // MARK: - Ordering

    /// `order` ascending where declared, everything without an `order` after
    /// it, ties broken by title and then by the section's place in the decoded
    /// array — the last of which is the only tiebreak that cannot itself tie.
    private static func precedes(
        _ lhs: (index: Int, section: ContributedSettingsSection),
        _ rhs: (index: Int, section: ContributedSettingsSection)
    ) -> Bool {
        if let left = lhs.section.order, let right = rhs.section.order, left != right {
            return left < right
        }
        if (lhs.section.order == nil) != (rhs.section.order == nil) {
            return rhs.section.order == nil
        }
        if lhs.section.title != rhs.section.title {
            return lhs.section.title < rhs.section.title
        }
        return lhs.index < rhs.index
    }

    /// The same rule for properties, with the key as the final tiebreak. Keys
    /// are unique within a section, so this is a total order.
    private static func precedes(_ lhs: ContributedSetting, _ rhs: ContributedSetting) -> Bool {
        if let left = lhs.order, let right = rhs.order, left != right {
            return left < right
        }
        if (lhs.order == nil) != (rhs.order == nil) {
            return rhs.order == nil
        }
        return lhs.key < rhs.key
    }

    // MARK: - Classification

    private static func classify(
        _ property: ExtensionManifest.ConfigurationProperty,
        key: String,
        ofExtension identifier: String
    ) -> (ContributedSettingKind, [ContributedSettingNote]) {
        var notes: [ContributedSettingNote] = []
        func note(_ kind: ContributedSettingNote.Kind, _ detail: String) {
            notes.append(ContributedSettingNote(
                extensionIdentifier: identifier, key: key, kind: kind, detail: detail))
        }

        if let members = property.enum, !members.isEmpty {
            if let choice = choice(from: members, of: property, note: note) {
                return (choice, notes)
            }
            note(.nonStringEnum, "enum has a member that is not a string; classifying on type instead")
        }

        guard let declaredType = property.effectiveType else {
            if case .union(let members) = property.type {
                note(.mixedUnionType, "type \(members) has no single non-null member")
                return (.json(default: jsonText(of: property.default)), notes)
            }
            return (inferred(from: property, note: note), notes)
        }

        switch declaredType {
        case "boolean":
            return (.toggle(default: boolean(from: property.default, note: note)), notes)
        case "string":
            return (.text(
                default: string(from: property.default, note: note),
                multiline: property.editPresentation == "multilineText"), notes)
        case "integer":
            // The bounds round *inward* — a minimum of 0.5 admits 1, not 0 —
            // because a bound that widens when narrowed is the one direction
            // that could let a clamp store a value the schema forbids.
            return (.integer(
                default: integer(from: property.default, note: note),
                minimum: property.minimum.flatMap { Int(exactly: $0.rounded(.up)) },
                maximum: property.maximum.flatMap { Int(exactly: $0.rounded(.down)) }), notes)
        case "number":
            return (.number(
                default: number(from: property.default, note: note),
                minimum: property.minimum,
                maximum: property.maximum), notes)
        case "array", "object":
            // Not a note: this is where a structured value is *supposed* to
            // land, not a compromise.
            return (.json(default: jsonText(of: property.default)), notes)
        default:
            note(.unrenderableType, "no row renders type \"\(declaredType)\"")
            return (.json(default: jsonText(of: property.default)), notes)
        }
    }

    /// A popup, when every `enum` member is a string.
    ///
    /// `nil` when it is not — the caller then ignores the `enum` and classifies
    /// on `type` alone. 1,191 of the corpus's 1,254 `enum` properties qualify;
    /// the rest mix strings with booleans or numbers, and a popup that stored
    /// `"true"` for a boolean member would be storing the wrong thing.
    ///
    /// A `null` member is dropped rather than disqualifying: `["a", "b", null]`
    /// is three strings and a way of saying unset.
    private static func choice(
        from members: [ExtensionManifest.JSONValue],
        of property: ExtensionManifest.ConfigurationProperty,
        note: (ContributedSettingNote.Kind, String) -> Void
    ) -> ContributedSettingKind? {
        var values: [String] = []
        var options: [ContributedSettingOption] = []
        for (index, member) in members.enumerated() {
            if case .null = member { continue }
            guard case .string(let value) = member else { return nil }
            values.append(value)
            // The label array is indexed against the *declared* members, so a
            // dropped null must not shift it.
            let label = property.enumItemLabels.flatMap { labels in
                index < labels.count ? labels[index] : nil
            }
            options.append(ContributedSettingOption(label: label ?? value, value: value))
        }
        guard let first = values.first else { return nil }

        let selected: String
        if let declared = property.default {
            if case .string(let value) = declared, values.contains(value) {
                selected = value
            } else if case .null = declared {
                note(.defaultTypeMismatch, "default is null; the first member stands in")
                selected = first
            } else {
                // Never substituted for a member: the stored value has to be
                // representable, or the popup would silently rewrite it.
                let raw = rawText(of: declared)
                note(.defaultNotInEnum, "default \"\(raw)\" is not one of the members")
                options.insert(ContributedSettingOption(label: raw, value: raw), at: 0)
                selected = raw
            }
        } else {
            note(.missingDefault, "no default; the first member stands in")
            selected = first
        }

        if property.enumDescriptions != nil || property.markdownEnumDescriptions != nil {
            note(.enumDescriptionsDropped, "per-member descriptions are not rendered")
        }
        return .choice(options: options, default: selected)
    }

    /// What a property with no usable `type` can be read off its default.
    ///
    /// 136 corpus properties declare no `type`; 34 of those declare nothing
    /// else either, and there is genuinely nothing to go on for those.
    private static func inferred(
        from property: ExtensionManifest.ConfigurationProperty,
        note: (ContributedSettingNote.Kind, String) -> Void
    ) -> ContributedSettingKind {
        guard let declared = property.default else {
            note(.unrenderableType, "no type, no enum and no default")
            return .json(default: jsonText(of: nil))
        }
        switch declared {
        case .bool(let flag):
            return .toggle(default: flag)
        case .number(let value):
            guard let exact = integral(value) else {
                return .number(default: value, minimum: property.minimum, maximum: property.maximum)
            }
            return .integer(
                default: exact,
                minimum: property.minimum.flatMap { Int(exactly: $0.rounded(.up)) },
                maximum: property.maximum.flatMap { Int(exactly: $0.rounded(.down)) })
        case .string(let text):
            return .text(default: text, multiline: property.editPresentation == "multilineText")
        case .array, .object:
            return .json(default: jsonText(of: declared))
        case .null:
            note(.unrenderableType, "no type, and a null default says nothing about one")
            return .json(default: jsonText(of: declared))
        }
    }

    // MARK: - Defaults

    // The declared type always wins over the default's own JSON type. 224
    // corpus properties declare `"default": null` under a non-null type and 15
    // more contradict their type outright; letting the default pick the row
    // would give ten `boolean` settings a text box.

    private static func boolean(
        from value: ExtensionManifest.JSONValue?,
        note: (ContributedSettingNote.Kind, String) -> Void
    ) -> Bool {
        guard let value else {
            note(.missingDefault, "no default; false stands in")
            return false
        }
        guard case .bool(let flag) = value else {
            note(.defaultTypeMismatch, "default \(rawText(of: value)) is not a boolean; false stands in")
            return false
        }
        return flag
    }

    private static func string(
        from value: ExtensionManifest.JSONValue?,
        note: (ContributedSettingNote.Kind, String) -> Void
    ) -> String {
        guard let value else {
            note(.missingDefault, "no default; the empty string stands in")
            return ""
        }
        guard case .string(let text) = value else {
            note(.defaultTypeMismatch, "default \(rawText(of: value)) is not a string; \"\" stands in")
            return ""
        }
        return text
    }

    private static func number(
        from value: ExtensionManifest.JSONValue?,
        note: (ContributedSettingNote.Kind, String) -> Void
    ) -> Double {
        guard let value else {
            note(.missingDefault, "no default; 0 stands in")
            return 0
        }
        guard case .number(let number) = value else {
            note(.defaultTypeMismatch, "default \(rawText(of: value)) is not a number; 0 stands in")
            return 0
        }
        return number
    }

    private static func integer(
        from value: ExtensionManifest.JSONValue?,
        note: (ContributedSettingNote.Kind, String) -> Void
    ) -> Int {
        guard let value else {
            note(.missingDefault, "no default; 0 stands in")
            return 0
        }
        guard case .number(let number) = value, let exact = integral(number) else {
            note(.defaultTypeMismatch, "default \(rawText(of: value)) is not an integer; 0 stands in")
            return 0
        }
        return exact
    }

    /// A JSON number that is exactly an `Int`. JSON has one number type, so a
    /// whole number arrives here as a `Double` and this is the only way to ask
    /// whether it was written as `3` or as `3.5`.
    private static func integral(_ value: Double) -> Int? {
        guard value == value.rounded() else { return nil }
        return Int(exactly: value)
    }

    // MARK: - Prose

    private static func explanation(of property: ExtensionManifest.ConfigurationProperty) -> String? {
        // `markdownDescription` as plain text rather than rendered: nothing
        // renders Markdown in a settings row, and the raw text of a sentence
        // with a link in it is still that sentence.
        let body = property.description ?? property.markdownDescription
        guard let deprecation = deprecation(of: property) else { return body }
        // The row still renders — a deprecated setting may already be set, and
        // hiding it would leave a value the user cannot see or clear.
        guard let body else { return deprecation }
        return "\(body)\n\n\(deprecation)"
    }

    private static func deprecation(of property: ExtensionManifest.ConfigurationProperty) -> String? {
        property.deprecationMessage ?? property.markdownDeprecationMessage
    }

    // MARK: - JSON text

    /// A value as the text the escape hatch edits: pretty-printed, keys
    /// sorted, and always valid JSON — including `null` for a value that was
    /// never declared, so a field's starting content can never be the one
    /// thing the editor refuses to accept back.
    static func jsonText(of value: ExtensionManifest.JSONValue?) -> String {
        let options: JSONSerialization.WritingOptions =
            [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        guard let data = try? JSONSerialization.data(
            withJSONObject: foundationValue(of: value ?? .null), options: options),
            let text = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return text
    }

    /// A value as a single line — a popup label, or a note's quotation of a
    /// default it refused.
    private static func rawText(of value: ExtensionManifest.JSONValue) -> String {
        switch value {
        case .string(let text):
            return text
        case .bool(let flag):
            return flag ? "true" : "false"
        case .number(let number):
            return integral(number).map(String.init) ?? String(number)
        case .null:
            return "null"
        case .array, .object:
            let options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
            guard let data = try? JSONSerialization.data(
                withJSONObject: foundationValue(of: value), options: options),
                let text = String(data: data, encoding: .utf8) else {
                return "null"
            }
            return text
        }
    }

    private static func foundationValue(of value: ExtensionManifest.JSONValue) -> Any {
        switch value {
        case .null:
            return NSNull()
        case .bool(let flag):
            return NSNumber(value: flag)
        case .number(let number):
            // A JSON number is always a `Double` here, and handing one to
            // `JSONSerialization` writes every whole number back with a
            // trailing `.0`. A count that reads `20.0` in the editor is a
            // count the extension author never wrote.
            return integral(number).map(NSNumber.init(value:)) ?? NSNumber(value: number)
        case .string(let text):
            return text
        case .array(let items):
            return items.map { foundationValue(of: $0) }
        case .object(let members):
            return members.mapValues { foundationValue(of: $0) }
        }
    }
}
