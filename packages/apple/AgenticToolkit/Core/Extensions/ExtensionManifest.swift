//
//  ExtensionManifest.swift
//  AgenticToolkit
//

import Foundation

/// One `contributes.*` array or dictionary entry that failed to decode.
///
/// The manifest never lets a single malformed entry sink the rest — see
/// `ExtensionManifest.Contributions`'s decoding — but it never drops the
/// failure silently either. This is that record.
public struct DecodingFailure: Sendable, Equatable, Codable {
    /// The manifest key the entry appeared under, e.g. "contributes.themes",
    /// or "contributes.menus.editor/context" for a keyed container's entry.
    public let key: String
    /// Zero-based index within that array, or nil for a keyed container (the
    /// whole keyed entry, or the container itself, failed) rather than one
    /// element of an array.
    public let index: Int?
    public let reason: String
}

/// A `Codable` subset of a VS Code `package.json`.
///
/// Decoded with a plain `JSONDecoder()` — VS Code's own keys are already
/// camelCase, and this toolkit has no shared decoder convention to follow
/// (every other decode site in `Core/` constructs a bare `JSONDecoder()`
/// inline). `name`, `version` and `engines.vscode` are the extension's
/// minimum identity; anything missing one of them isn't a VS Code extension
/// and fails to decode rather than producing a manifest with no name to
/// report failures against.
public struct ExtensionManifest: Codable, Sendable, Equatable {
    public let name: String
    public let publisher: String?
    public let version: String
    public let displayName: String?
    public let description: String?
    public let engines: Engines
    public let activationEvents: [String]
    public let main: String?
    public let browser: String?
    public let extensionKind: [String]?
    public let capabilities: Capabilities?
    public let contributes: Contributions?

    /// Top-level keys that were present and unreadable.
    ///
    /// The same record `Contributions` keeps for a malformed `contributes.*`
    /// entry, one level up. It exists because `capabilities`, `extensionKind`
    /// and `activationEvents` used to be decoded with a plain `try`: a
    /// manifest that spelled any one of them wrongly failed to decode at all,
    /// and an extension this host would otherwise have loaded correctly —
    /// nothing here reads those three — disappeared instead, taking its name
    /// with it.
    ///
    /// Not in `CodingKeys`, so it is never encoded and never round-trips: it
    /// describes *this decode*, not the manifest.
    public let decodingFailures: [DecodingFailure]

    /// `publisher.name` when a publisher is declared, otherwise `name`,
    /// **case-folded**. This is the identity everything else keys on —
    /// settings storage, the disabled list, uninstall, contribution
    /// withdrawal.
    ///
    /// Folded because the VS Code marketplace treats a publisher and
    /// extension name case-insensitively, and the gallery's own spelling of
    /// one drifts from what the manifest says. Left unfolded, `Ms-Python.foo`
    /// and `ms-python.foo` are two extensions to this host: disabling one
    /// leaves the other enabled, their settings land in two different storage
    /// keys, and an uninstall clears a tombstone nobody set. Show
    /// `displayIdentifier` in UI; key on this.
    public var identifier: String {
        displayIdentifier.lowercased()
    }

    /// The identifier exactly as the manifest spelled it — for display, never
    /// for lookup.
    public var displayIdentifier: String {
        guard let publisher else { return name }
        return "\(publisher).\(name)"
    }

    public struct Engines: Codable, Sendable, Equatable {
        public let vscode: String
    }

    /// A JSON value, for the parts of a manifest whose type is genuinely
    /// open (`contributes.configuration` defaults and `enum` entries, and a
    /// language-model tool's `inputSchema`).
    ///
    /// `AgenticToolkitSync` already has a `JSONValue` of this exact shape
    /// (`Sync/JSONValue.swift`), but `apple-sync` is a *sibling* foundation
    /// tier to `apple-core` — both declare `depends_on: []` in
    /// `.abstractr.json` — not a tier this one sits above, so importing it
    /// would be a lateral dependency between two foundation tiers.
    /// `abstractr check --content-file` confirmed this concretely: a
    /// top-level `public enum JSONValue` here is flagged `duplicate_name`
    /// ("already exported by apple-sync. Build on it or extend it — do not
    /// rebuild it here"), which — unlike the ordinary new-file-in-shared-tier
    /// block — does not clear on retry. Nesting it here as
    /// `ExtensionManifest.JSONValue` gives it a distinct export name (the
    /// duplicate-name check cleared once nested, verified the same way)
    /// while keeping the bare name `JSONValue` resolvable everywhere else in
    /// this file, since every other type below is itself nested under
    /// `ExtensionManifest` and ordinary Swift name lookup finds this one
    /// first. See the task report for the full before/after `abstractr`
    /// findings.
    public enum JSONValue: Codable, Sendable, Equatable {
        case null
        case bool(Bool)
        case number(Double)
        case string(String)
        case array([JSONValue])
        case object([String: JSONValue])

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode([JSONValue].self) {
                self = .array(value)
            } else if let value = try? container.decode([String: JSONValue].self) {
                self = .object(value)
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "not JSON")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .null: try container.encodeNil()
            case .bool(let value): try container.encode(value)
            case .number(let value): try container.encode(value)
            case .string(let value): try container.encode(value)
            case .array(let value): try container.encode(value)
            case .object(let value): try container.encode(value)
            }
        }
    }

    /// `capabilities.untrustedWorkspaces.supported` is the one field whose
    /// JSON type is not fixed — `true`, `false`, or the string `"limited"`.
    public struct Capabilities: Codable, Sendable, Equatable {
        public let untrustedWorkspaces: UntrustedWorkspaces?

        public struct UntrustedWorkspaces: Codable, Sendable, Equatable {
            public enum Support: Codable, Sendable, Equatable {
                case supported, limited, unsupported

                public init(from decoder: Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    if let boolValue = try? container.decode(Bool.self) {
                        self = boolValue ? .supported : .unsupported
                    } else if let stringValue = try? container.decode(String.self), stringValue == "limited" {
                        self = .limited
                    } else {
                        throw DecodingError.dataCorruptedError(
                            in: container,
                            debugDescription: "expected true, false, or \"limited\""
                        )
                    }
                }

                public func encode(to encoder: Encoder) throws {
                    var container = encoder.singleValueContainer()
                    switch self {
                    case .supported: try container.encode(true)
                    case .unsupported: try container.encode(false)
                    case .limited: try container.encode("limited")
                    }
                }
            }

            public let supported: Support
            public let description: String?
            public let restrictedConfigurations: [String]?
        }
    }

    private enum CodingKeys: String, CodingKey {
        case name, publisher, version, displayName, description, engines
        case activationEvents, main, browser, extensionKind, capabilities, contributes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Identity first, and deliberately so: `name` and `publisher` are what
        // a failure further down is *reported against*, and
        // `ExtensionRegistry.establishedIdentifiers` goes `nil` — disabling
        // orphan pruning for the whole scan — the moment one failure cannot
        // name its extension. Decoding them before anything that can throw is
        // the cheap half of keeping that from happening.
        name = try container.decode(String.self, forKey: .name)
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
        version = try container.decode(String.self, forKey: .version)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        engines = try container.decode(Engines.self, forKey: .engines)
        main = try container.decodeIfPresent(String.self, forKey: .main)
        browser = try container.decodeIfPresent(String.self, forKey: .browser)

        // `name`, `version` and `engines.vscode` above are the extension's
        // identity: without them this is not a VS Code extension and there is
        // nothing to load. The three below are not. Nothing in this host reads
        // `activationEvents`, `extensionKind` or `capabilities` — they are
        // carried for display and for a future activation model — so a
        // malformed one is recorded and skipped, exactly as a malformed
        // `contributes` entry is, rather than costing the extension its themes,
        // commands and settings.
        var failures: [DecodingFailure] = []
        // VS Code 1.74+ infers activation events from `contributes`, so a
        // manifest that relies on that inference omits the key entirely.
        activationEvents = LenientDecoding.array(
            String.self, from: container, key: .activationEvents,
            manifestKey: "activationEvents", failures: &failures)
        // `nil`, not `[]`, when the key is absent or its value was unreadable:
        // `[]` would be this manifest saying "runs in no extension host at
        // all", which is a claim, where `nil` is the absence of one.
        let kinds = LenientDecoding.array(
            String.self, from: container, key: .extensionKind,
            manifestKey: "extensionKind", failures: &failures)
        extensionKind = kinds.isEmpty ? nil : kinds
        capabilities = LenientDecoding.value(
            Capabilities.self, from: container, key: .capabilities,
            manifestKey: "capabilities", failures: &failures)
        // `contributes` stays strict, and deliberately so: it is not a field
        // nothing reads. A `contributes` of the wrong shape is not a manifest
        // with one bad key, it is a manifest whose entire contribution block
        // this host cannot see, and loading it as an extension that happens to
        // contribute nothing is the silent-wrong-answer the pinned test
        // "a contributes key of the wrong shape sinks the manifest rather than
        // reading as empty" exists to forbid. Its *elements* are already
        // lenient one level down, which is where leniency belongs.
        contributes = try container.decodeIfPresent(Contributions.self, forKey: .contributes)
        decodingFailures = failures
    }
}

extension ExtensionManifest {

    /// The `contributes` block: everything Stage 4c and Stages 5-7 read to
    /// install themes, snippets, commands, settings, views and (later)
    /// language-model tools.
    ///
    /// Every top-level array defaults to `[]` and every dictionary to `[:]`
    /// when its key is absent, so a caller never unwraps twice. Each array
    /// and each keyed container's values decode element-wise: one malformed
    /// theme does not cost the extension its other themes, and what could
    /// not be decoded lands in `decodingFailures` rather than vanishing —
    /// the required top-level fields on `ExtensionManifest` itself are the
    /// only place a malformed value is still a hard failure, because an
    /// extension with no name has no identity to report a failure against.
    public struct Contributions: Codable, Sendable, Equatable {
        public let themes: [Theme]
        public let snippets: [Snippet]
        public let languages: [Language]
        public let commands: [Command]
        public let keybindings: [Keybinding]
        public let menus: [String: [MenuItem]]
        public let configuration: [Configuration]
        public let views: [String: [View]]
        public let viewsContainers: [String: [ViewContainer]]
        public let languageModelTools: [LanguageModelTool]

        /// Entries that were present but could not be decoded, with the key
        /// they appeared under and why. Never silently dropped.
        public let decodingFailures: [DecodingFailure]

        /// A `contributes` block that declares nothing.
        ///
        /// `ExtensionRegistry` hands this to every contribution point when a
        /// manifest carries no `contributes` key at all, instead of skipping
        /// the points entirely. *Absent* and *empty* are the same statement —
        /// "this extension declares nothing" — and a point that is never told
        /// cannot reconcile away what a previous version of the same extension
        /// declared, which is how an update that drops the key orphans its
        /// themes permanently. Every point is already idempotent per extension
        /// and so already correct under this value.
        ///
        /// This is only sound because `contributes == nil` cannot mean "failed
        /// to decode". `decodeIfPresent` returns nil for an absent key or a
        /// literal `null` and *throws* for every other shape, so a malformed
        /// `contributes` sinks the whole manifest at
        /// `ExtensionRegistry.load`'s decode and never reaches a contribution
        /// point at all. Were that not so, an unparseable file would read here
        /// as "declares nothing" and delete the user's themes.
        public static let empty = Contributions()

        private init() {
            themes = []
            snippets = []
            languages = []
            commands = []
            keybindings = []
            menus = [:]
            configuration = []
            views = [:]
            viewsContainers = [:]
            languageModelTools = []
            decodingFailures = []
        }

        private enum CodingKeys: String, CodingKey {
            case themes, snippets, languages, commands, keybindings, menus
            case configuration, views, viewsContainers, languageModelTools
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            var failures: [DecodingFailure] = []

            themes = LenientDecoding.array(
                Theme.self, from: container, key: .themes,
                manifestKey: "contributes.themes", failures: &failures
            )
            snippets = LenientDecoding.array(
                Snippet.self, from: container, key: .snippets,
                manifestKey: "contributes.snippets", failures: &failures
            )
            languages = LenientDecoding.array(
                Language.self, from: container, key: .languages,
                manifestKey: "contributes.languages", failures: &failures
            )
            commands = LenientDecoding.array(
                Command.self, from: container, key: .commands,
                manifestKey: "contributes.commands", failures: &failures
            )
            keybindings = LenientDecoding.array(
                Keybinding.self, from: container, key: .keybindings,
                manifestKey: "contributes.keybindings", failures: &failures
            )
            configuration = LenientDecoding.array(
                Configuration.self, from: container, key: .configuration,
                manifestKey: "contributes.configuration", failures: &failures
            )
            languageModelTools = LenientDecoding.array(
                LanguageModelTool.self, from: container, key: .languageModelTools,
                manifestKey: "contributes.languageModelTools", failures: &failures
            )

            menus = LenientDecoding.dictionary(
                MenuItem.self, from: container, key: .menus,
                manifestKeyPrefix: "contributes.menus", failures: &failures
            )
            views = LenientDecoding.dictionary(
                View.self, from: container, key: .views,
                manifestKeyPrefix: "contributes.views", failures: &failures
            )
            viewsContainers = LenientDecoding.dictionary(
                ViewContainer.self, from: container, key: .viewsContainers,
                manifestKeyPrefix: "contributes.viewsContainers", failures: &failures
            )

            decodingFailures = failures
        }

        /// Encoding is deliberately lossy, in two distinct ways, and neither
        /// is an oversight.
        ///
        /// `decodingFailures` is diagnostic state derived at decode time, not
        /// manifest content: no `package.json` on disk carries such a key, so
        /// re-encoding it would invent one. It is therefore absent from
        /// `CodingKeys` and never written.
        ///
        /// The lossiness is wider than that, though. A `contributes.*` entry
        /// that failed to decode is gone from the encoded JSON *entirely* —
        /// not merely un-annotated — because this type only ever held the
        /// entries that decoded. So a round-trip through `encode` is **not** a
        /// faithful copy of the manifest that came in.
        ///
        /// Anything that must rewrite a manifest on disk therefore copies the
        /// original bytes; it does not re-encode this type.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(themes, forKey: .themes)
            try container.encode(snippets, forKey: .snippets)
            try container.encode(languages, forKey: .languages)
            try container.encode(commands, forKey: .commands)
            try container.encode(keybindings, forKey: .keybindings)
            try container.encode(menus, forKey: .menus)
            try container.encode(configuration, forKey: .configuration)
            try container.encode(views, forKey: .views)
            try container.encode(viewsContainers, forKey: .viewsContainers)
            try container.encode(languageModelTools, forKey: .languageModelTools)
        }

    }

    /// The manifest's one lenient-decoding implementation, shared by
    /// `Contributions` and by `ExtensionManifest` itself.
    ///
    /// It lived inside `Contributions` until the top-level manifest needed the
    /// same tolerance. `capabilities`, `activationEvents` and `extensionKind`
    /// decoded with a plain `try`, so one field nothing in this host reads
    /// could sink a whole extension — and take its *name* down with it, since
    /// the name is what a failure is reported against. That is what switched
    /// `ExtensionRegistry.establishedIdentifiers` to `nil` and turned orphan
    /// pruning off for every *other* extension in the scan.
    ///
    /// Generic over the key type so both callers' `CodingKeys` fit; otherwise
    /// unchanged from the version `Contributions` kept to itself.
    enum LenientDecoding {

        /// Decodes `contributes.<key>` element-wise: each element round-trips
        /// through `JSONValue` first (which always succeeds for well-formed
        /// JSON, sidestepping `UnkeyedDecodingContainer`'s cursor-stuck
        /// failure mode) and is then decoded into `Element` on its own, so
        /// one bad element only costs itself.
        ///
        /// A lone object where an array was expected is accepted as a
        /// one-element array. `contributes.configuration` is why: VS Code's
        /// schema for it is `object | object[]`, and the single-object form is
        /// what most real extensions ship, so refusing it would hand the
        /// generated settings panel almost nothing.
        ///
        /// That lenience is not confined to `configuration` — this is the one
        /// decode path every array-shaped `contributes` key takes, so a lone
        /// object is now accepted for `commands` and `themes` too, where VS
        /// Code's own schema requires an array. Deliberate: the alternative
        /// threads a per-key flag through every call site to reject an input
        /// no correct manifest produces, and the only consequence of accepting
        /// it is that this host loads something VS Code would have rejected —
        /// never that a correct manifest decodes wrongly.
        static func array<Element: Decodable, Key: CodingKey>(
            _ type: Element.Type,
            from container: KeyedDecodingContainer<Key>,
            key: Key,
            manifestKey: String,
            failures: inout [DecodingFailure]
        ) -> [Element] {
            guard container.contains(key) else { return [] }

            // The whole array, in one pass, when nothing is wrong with it —
            // which is every well-formed manifest, i.e. all of them, nearly
            // always. The element-wise path below is a *recovery* path and
            // costs what recovery costs: it builds a `JSONValue` graph for
            // every entry and then re-encodes and re-decodes each one, roughly
            // three parses per element. Measured on 100 synthetic extensions
            // (4 themes, 12 commands, 20 configuration properties each,
            // `ExtensionRegistryTests`' F52 benchmark), paying that for good
            // input cost ~275 ms of main-actor CPU at load against ~4 ms of
            // file reading — the launch stall F52 describes is this, not I/O.
            // Trying strict first leaves the recovery behaviour untouched: a
            // strict decode fails if and only if some element does, and that
            // is exactly when the slow path runs and isolates it.
            if let decoded = try? container.decode([Element].self, forKey: key) {
                return decoded
            }

            let raw: [JSONValue]
            if let array = try? container.decode([JSONValue].self, forKey: key) {
                raw = array
            } else if let single = try? container.decode(JSONValue.self, forKey: key), case .object = single {
                raw = [single]
            } else {
                failures.append(DecodingFailure(key: manifestKey, index: nil, reason: "expected an array"))
                return []
            }

            // One pair for the whole array. Neither is configured per element and
            // both are safe to reuse for this round-trip, and an encoder allocates
            // real internal state — a manifest contributing a few hundred entries
            // was paying for a few hundred of them, on the launch path.
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()
            var result: [Element] = []
            for (index, item) in raw.enumerated() {
                do {
                    let data = try encoder.encode(item)
                    result.append(try decoder.decode(Element.self, from: data))
                } catch {
                    failures.append(DecodingFailure(key: manifestKey, index: index, reason: describe(error)))
                }
            }
            return result
        }

        /// A decoding failure in words the extension author can act on.
        ///
        /// `reason` is rendered verbatim in the settings panel's Decisions
        /// group, so `String(describing:)` over a `DecodingError` would put the
        /// compiler's spelling of an enum case in front of the author —
        /// `keyNotFound(CodingKeys(stringValue: "path", intValue: nil), …)`.
        /// `localizedDescription` is no better here: Foundation renders every
        /// one of these as "The data couldn't be read because it is missing.",
        /// naming neither the key nor the entry. So each case is written out,
        /// and every one of them names the thing the author has to go and fix.
        static func describe(_ error: Error) -> String {
            guard let decoding = error as? DecodingError else { return error.localizedDescription }
            switch decoding {
            case .keyNotFound(let key, _):
                return "no “\(key.stringValue)”"
            case .typeMismatch(let type, let context):
                guard let name = jsonName(of: type) else {
                    return "\(subject(of: context)) is the wrong kind of value"
                }
                return "\(subject(of: context)) is not \(name)"
            case .valueNotFound(_, let context):
                return "\(subject(of: context)) is null"
            case .dataCorrupted(let context):
                return context.debugDescription
            @unknown default:
                return error.localizedDescription
            }
        }

        /// The JSON shape a Swift type stands for, in the words the manifest
        /// author writes their file in — or `nil` when there is no such shape.
        ///
        /// A `DecodingError.typeMismatch` carries the Swift type the decoder
        /// wanted, and interpolating it puts `Dictionary<String, Any>` in front
        /// of somebody editing a `package.json`. The author edits JSON, so the
        /// sentence they read is about JSON.
        ///
        /// The nouns are JSON's own rather than a settings panel's ("a group of
        /// settings"): this one table serves `themes`, `commands`, `menus` and
        /// `languages` as well as `configuration`, where an object is not a
        /// group of settings — and `LenientDecoding.dictionary` twenty lines below
        /// already says "expected an object", so anything else would have one
        /// file contradicting itself within a screen (Ruling GU).
        ///
        /// `nil` for everything else, and the caller must then say nothing
        /// about the type at all rather than falling back to `\(type)`. A type
        /// outside this table is a first-party `Decodable` with a custom
        /// `init(from:)`, so naming it would describe this app's internals
        /// rather than the author's file — which is G1's defect surviving in
        /// exactly the place nobody anticipated it.
        private static func jsonName(of type: Any.Type) -> String? {
            switch type {
            case is String.Type: return "text"
            case is Bool.Type: return "true or false"
            case is Double.Type, is Float.Type: return "a number"
            // Every width and both signednesses in one row; `JSONDecoder`
            // throws whichever one the property declared.
            case is any FixedWidthInteger.Type: return "a whole number"
            case is [String: Any].Type: return "an object"
            case is [Any].Type: return "a list"
            default: return nil
            }
        }

        /// What a `DecodingError.Context`'s coding path names.
        ///
        /// Empty whenever the *element itself* is the wrong shape, because each
        /// element is decoded on its own and its path starts there — and
        /// “” would name nothing at all.
        private static func subject(of context: DecodingError.Context) -> String {
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? "this entry" : "“\(path)”"
        }

        /// Same posture as `LenientDecoding.array`, for the menu/view/
        /// view-container contributions keyed by location (`commandPalette`,
        /// `activitybar`, …). A location whose value isn't itself an array is
        /// one failure naming that location; each element within it decodes
        /// independently.
        static func dictionary<Element: Decodable, Key: CodingKey>(
            _ type: Element.Type,
            from container: KeyedDecodingContainer<Key>,
            key: Key,
            manifestKeyPrefix: String,
            failures: inout [DecodingFailure]
        ) -> [String: [Element]] {
            guard container.contains(key) else { return [:] }

            // The same strict-first shortcut `array` takes, for the same
            // measured reason: the element-wise path is recovery, and a
            // well-formed manifest should not pay for it.
            if let decoded = try? container.decode([String: [Element]].self, forKey: key) {
                return decoded
            }

            guard let raw = try? container.decode([String: JSONValue].self, forKey: key) else {
                failures.append(DecodingFailure(key: manifestKeyPrefix, index: nil, reason: "expected an object"))
                return [:]
            }

            let encoder = JSONEncoder()
            let decoder = JSONDecoder()
            var result: [String: [Element]] = [:]
            for (location, value) in raw {
                guard case .array(let items) = value else {
                    let locationKey = "\(manifestKeyPrefix).\(location)"
                    failures.append(DecodingFailure(key: locationKey, index: nil, reason: "expected an array"))
                    continue
                }
                var decoded: [Element] = []
                for (index, item) in items.enumerated() {
                    do {
                        let data = try encoder.encode(item)
                        decoded.append(try decoder.decode(Element.self, from: data))
                    } catch {
                        let locationKey = "\(manifestKeyPrefix).\(location)"
                        failures.append(
                            DecodingFailure(key: locationKey, index: index, reason: describe(error))
                        )
                    }
                }
                result[location] = decoded
            }
            return result
        }

        /// One optional field, decoded the same way: a key that is present and
        /// unreadable records a failure and answers `nil` rather than throwing
        /// out of the whole manifest.
        ///
        /// The single-value sibling of `array` and `dictionary`, for a field
        /// whose JSON shape is one object and where a per-element recovery
        /// means nothing. Absent is still `nil` and still records nothing —
        /// "not declared" is not a failure.
        static func value<Value: Decodable, Key: CodingKey>(
            _ type: Value.Type,
            from container: KeyedDecodingContainer<Key>,
            key: Key,
            manifestKey: String,
            failures: inout [DecodingFailure]
        ) -> Value? {
            guard container.contains(key) else { return nil }
            do {
                return try container.decodeIfPresent(Value.self, forKey: key)
            } catch {
                failures.append(
                    DecodingFailure(key: manifestKey, index: nil, reason: describe(error)))
                return nil
            }
        }
    }

    public struct Theme: Codable, Sendable, Equatable {
        public let label: String
        public let uiTheme: String
        public let path: String
    }

    public struct Snippet: Codable, Sendable, Equatable {
        public let language: String
        public let path: String
    }

    public struct Language: Codable, Sendable, Equatable {
        public let id: String
        public let aliases: [String]?
        public let extensions: [String]?
        public let filenames: [String]?
        public let filenamePatterns: [String]?
        public let firstLine: String?
        /// Carried only so it can be *reported* as dropped: nothing in this
        /// host maps a file by MIME type, and without the key an entry that
        /// declared only `mimetypes` would be indistinguishable from one that
        /// declared nothing at all.
        public let mimetypes: [String]?
        public let configuration: String?
        public let icon: LanguageIcon?

        public struct LanguageIcon: Codable, Sendable, Equatable {
            public let light: String
            public let dark: String
        }
    }

    public struct Command: Codable, Sendable, Equatable {
        public let command: String
        public let title: String
        public let category: String?
        /// VS Code also allows an object form (`{light, dark}`) here, and
        /// published extensions use it constantly. Only the plain-string form
        /// is modeled, so the object form decodes to `nil` rather than
        /// throwing: `LenientDecoding.array` isolates at element granularity, so
        /// a throw from this one field would cost the whole command — its
        /// identifier, its title, its place in the palette — over a
        /// decoration. Dropping the icon is the smaller loss, and the only
        /// one this host can act on.
        public let icon: String?
        public let enablement: String?

        private enum CodingKeys: String, CodingKey {
            case command, title, category, icon, enablement
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            command = try container.decode(String.self, forKey: .command)
            title = try container.decode(String.self, forKey: .title)
            category = try container.decodeIfPresent(String.self, forKey: .category)
            icon = try? container.decode(String.self, forKey: .icon)
            enablement = try container.decodeIfPresent(String.self, forKey: .enablement)
        }
    }

    public struct Keybinding: Codable, Sendable, Equatable {
        public let command: String
        public let key: String
        public let mac: String?
        public let when: String?

        // `args` — arbitrary command arguments VS Code allows on a keybinding
        // — is deliberately not carried. Nothing in Stage 4 can act on them:
        // `CommandRegistry.execute` takes no arguments today, and carrying a
        // field this host cannot honour is worse than not carrying it. This
        // was a decision, not an oversight; revisit when a consumer needs it.
    }

    public struct MenuItem: Codable, Sendable, Equatable {
        public let command: String
        public let when: String?
        public let group: String?
        public let alt: String?
    }

    public struct Configuration: Codable, Sendable, Equatable {
        public let title: String?
        /// The section's `id`, carried but not acted on: 89 of the corpus's
        /// 741 sections declare one, and a key that decodes to nothing is a
        /// key the next reader has to rediscover is absent by choice rather
        /// than by oversight.
        public let id: String?
        public let order: Int?
        public let properties: [String: ConfigurationProperty]

        private enum CodingKeys: String, CodingKey { case title, id, order, properties }

        /// A property key, so the properties can be decoded one at a time.
        private struct PropertyKey: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        /// Every field is `try?` rather than `decodeIfPresent`, because
        /// `LenientDecoding.array` isolates failures at the *section*: one
        /// mistyped scalar here throws out of this initializer and takes
        /// every sibling property in the section with it. A section holds up
        /// to 186 properties in the corpus, and eight properties there
        /// already spell `order` as the string `"0"`. Losing a section's
        /// place in a sorted list is the smaller failure by far.
        ///
        /// The properties are decoded **one at a time** for the same reason
        /// one level down: decoded as a `[String: ConfigurationProperty]`,
        /// a single unusable property throws and the whole dictionary — every
        /// sibling in a section that can hold 186 of them — is lost with it.
        /// Isolating each property is also what makes strictness affordable
        /// later: with the blast radius bounded at one property, tightening a
        /// field is a one-line change instead of a new way to lose a section.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try? container.decode(String.self, forKey: .title)
            id = try? container.decode(String.self, forKey: .id)
            order = try? container.decode(Int.self, forKey: .order)

            var decoded: [String: ConfigurationProperty] = [:]
            if let properties = try? container.nestedContainer(
                keyedBy: PropertyKey.self, forKey: .properties) {
                for key in properties.allKeys {
                    if let property = try? properties.decode(
                        ConfigurationProperty.self, forKey: key) {
                        decoded[key.stringValue] = property
                    }
                }
            }
            properties = decoded
        }
    }

    public struct ConfigurationProperty: Codable, Sendable, Equatable {

        /// A JSON Schema `type`, which VS Code allows to be one name or a
        /// union of them.
        ///
        /// Modelled rather than spelled `String?` because the union form is
        /// live — 383 of the corpus's 7,464 properties use it — and a
        /// `String?` throws a `typeMismatch` on every one. That throw does
        /// not cost the property alone: `LenientDecoding.array` isolates at the
        /// section, so it costs every sibling property in the section too.
        public enum PropertyType: Codable, Sendable, Equatable {
            case single(String)
            /// The union's members as declared, with every non-string member
            /// dropped.
            ///
            /// Dropped rather than modelled because in practice a non-string
            /// member is always JSON `null` — four corpus properties spell
            /// nullability as `["number", null]` rather than
            /// `["number", "null"]` — and `null` is exactly the member
            /// `effectiveType` discards anyway. So the two spellings collapse
            /// to the same answer, at the cost of an encode that is not
            /// byte-faithful for those four; `Contributions.encode` already
            /// documents that this type does not round-trip a manifest.
            case union([String])

            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let name = try? container.decode(String.self) {
                    self = .single(name)
                    return
                }
                var names: [String] = []
                for member in try container.decode([JSONValue].self) {
                    if case .string(let name) = member { names.append(name) }
                }
                self = .union(names)
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .single(let name): try container.encode(name)
                case .union(let members): try container.encode(members)
                }
            }
        }

        public let type: PropertyType?
        public let `default`: JSONValue?
        public let description: String?
        public let markdownDescription: String?
        public let `enum`: [JSONValue]?
        public let enumDescriptions: [String]?
        public let markdownEnumDescriptions: [String]?
        /// One label per `enum` member, positionally. Optional *per element*
        /// because a manifest writes `null` for a member it wants labelled by
        /// its own raw value: `[null, null, null, "…"]` appears in the corpus,
        /// and a plain `[String]` throws on it — taking the section with it.
        public let enumItemLabels: [String?]?
        public let scope: String?
        public let order: Int?
        public let minimum: Double?
        public let maximum: Double?
        public let deprecationMessage: String?
        public let markdownDeprecationMessage: String?
        /// `"multilineText"` asks for an editor rather than a one-line field.
        /// It is the only value VS Code defines and the only one the corpus
        /// uses.
        public let editPresentation: String?

        /// The one type this property can be rendered as, or `nil` when the
        /// manifest does not settle it.
        ///
        /// A union collapses to its single non-`null` member: `["string",
        /// "null"]` is a string that may be unset. A union whose members
        /// genuinely disagree (`["boolean", "string"]`) has no single answer
        /// and returns `nil` — the caller's cue to fall back to editing the
        /// value as JSON text.
        public var effectiveType: String? {
            switch type {
            case .single(let name):
                return name
            case .union(let members):
                var distinct: [String] = []
                for member in members where member != "null" && !distinct.contains(member) {
                    distinct.append(member)
                }
                return distinct.count == 1 ? distinct[0] : nil
            case nil:
                return nil
            }
        }

        private enum CodingKeys: String, CodingKey {
            case type, `default`, description, markdownDescription
            case `enum`, enumDescriptions, markdownEnumDescriptions, enumItemLabels
            case scope, order, minimum, maximum
            case deprecationMessage, markdownDeprecationMessage, editPresentation
        }

        /// `try?` per field — **every** field, the value-bearing ones
        /// included. A field whose JSON does not fit its declared Swift type
        /// is dropped, and the property arrives without it rather than not
        /// arriving at all.
        ///
        /// The consequence, stated because it is not free: a manifest
        /// spelling `"minimum": "0"` as a string gets a row with *no* lower
        /// bound, and nothing tells the user — `ContributedSettingNote`
        /// records classification compromises, not decode losses.
        ///
        /// Strictness on the value fields was measured and rejected. Across
        /// all 7,464 corpus properties the only fields that ever fail a
        /// strict decode are `order` (8) and `markdownDescription` (1);
        /// `type`, `default`, `enum`, `minimum`, `maximum`, `scope`,
        /// `deprecationMessage`, `editPresentation` and `enumItemLabels`
        /// never fail anywhere. So strictness would buy a fail-fast guarantee
        /// against a case that does not occur, and pay for it by throwing —
        /// which, before `Configuration.init(from:)` began decoding its
        /// properties one at a time, cost a whole section. That isolation is
        /// now in place, which is what makes this decision cheap to revisit:
        /// tightening a field here can no longer take a property's siblings
        /// with it.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try? container.decode(PropertyType.self, forKey: .type)
            `default` = try? container.decode(JSONValue.self, forKey: .default)
            description = try? container.decode(String.self, forKey: .description)
            markdownDescription = try? container.decode(String.self, forKey: .markdownDescription)
            `enum` = try? container.decode([JSONValue].self, forKey: .enum)
            enumDescriptions = try? container.decode([String].self, forKey: .enumDescriptions)
            markdownEnumDescriptions = try? container.decode(
                [String].self, forKey: .markdownEnumDescriptions)
            enumItemLabels = try? container.decode([String?].self, forKey: .enumItemLabels)
            scope = try? container.decode(String.self, forKey: .scope)
            order = try? container.decode(Int.self, forKey: .order)
            minimum = try? container.decode(Double.self, forKey: .minimum)
            maximum = try? container.decode(Double.self, forKey: .maximum)
            deprecationMessage = try? container.decode(String.self, forKey: .deprecationMessage)
            markdownDeprecationMessage = try? container.decode(
                String.self, forKey: .markdownDeprecationMessage)
            editPresentation = try? container.decode(String.self, forKey: .editPresentation)
        }
    }

    public struct View: Codable, Sendable, Equatable {
        public let id: String
        public let name: String
        public let when: String?
        /// `"tree"` or `"webview"`. Absent means a tree — VS Code's own
        /// default, and what most entries rely on rather than spell.
        public let type: String?
        public let icon: String?
        public let contextualTitle: String?
        /// `visible`, `collapsed` or `hidden`, relative to the sibling views
        /// inside one VS Code container. Carried, never mapped: this host
        /// arranges panes into a split tree the user built, so there is no
        /// container for a view to be relative within.
        public let visibility: String?
        /// A *weight* against its siblings, not a fraction of anything.
        /// Carried for the same reason, and for the sharper one that mapping
        /// it onto `preferredThicknessFraction` would silently get the layout
        /// wrong.
        public let initialSize: Double?
        /// The keys this entry declared and this decoder could not read,
        /// in declaration order of the type rather than of the JSON.
        ///
        /// Dropping a field silently would trade a loud failure for a quiet
        /// one: before the widened decoder, a `when` given as a number threw,
        /// `LenientDecoding.dictionary` caught it, and a `DecodingFailure` was
        /// recorded with the key and the reason. Keeping the view is the right
        /// trade, but a `String?` cannot tell "absent" from "present and
        /// unreadable", so the difference is carried here instead and
        /// `ContributedViewsBuilder` turns each entry into a `malformedField`
        /// note (Ruling GF).
        ///
        /// This is decoder output, not manifest content, which is why it has no
        /// `CodingKeys` case: `Encodable` synthesis only encodes properties
        /// that have one, so a `View` still encodes to manifest-shaped JSON.
        /// Adding a case to "fix" the asymmetry would make the decoder look for
        /// a key no manifest has — `unreadableKeysAreNotEncoded` fails the
        /// moment someone does. Note also that `Equatable` synthesis is *not*
        /// selective the way `Encodable` is: it covers this property too, so
        /// `View` equality is no longer a statement about manifest content
        /// alone.
        public let unreadableKeys: [String]

        private enum CodingKeys: String, CodingKey {
            case id, name, when, type, icon, contextualTitle, visibility, initialSize
        }

        /// `id` and `name` are strict; everything else is `try?`.
        ///
        /// Not tidying — a measured hazard this task would otherwise have
        /// introduced. `LenientDecoding.dictionary` isolates a failure at the
        /// *view*, so any throw from here costs the whole entry: its id, its
        /// name, its place in the pane list. With `initialSize` added as a
        /// plain `Double?`, a manifest spelling it `"2"` as a string throws
        /// (verified) and loses a view that decoded perfectly well before this
        /// change. The same reasoning `Command.icon` already records, and the
        /// same shape `ConfigurationProperty.init(from:)` settled one level
        /// down: a field whose JSON does not fit is dropped, and the view
        /// arrives without it rather than not arriving at all.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)

            // A key that is absent was never declared and is nobody's problem;
            // a key that is present and will not decode is a lost declaration,
            // and the difference is the whole point of recording it.
            var unreadable: [String] = []
            func read<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
                guard container.contains(key) else { return nil }
                // An explicit `null` is a declaration withdrawn, not one this
                // host failed to read, so it is absence rather than a note.
                if (try? container.decodeNil(forKey: key)) == true { return nil }
                guard let value = try? container.decode(T.self, forKey: key) else {
                    unreadable.append(key.stringValue)
                    return nil
                }
                return value
            }

            when = read(String.self, .when)
            type = read(String.self, .type)
            icon = read(String.self, .icon)
            contextualTitle = read(String.self, .contextualTitle)
            visibility = read(String.self, .visibility)
            initialSize = read(Double.self, .initialSize)
            unreadableKeys = unreadable
        }
    }

    public struct ViewContainer: Codable, Sendable, Equatable {
        public let id: String
        public let title: String
        /// Optional, and that is the fix rather than the modelling.
        ///
        /// Declared non-optional, a container that omits its icon throws,
        /// `LenientDecoding.dictionary` catches it at the element, and the whole
        /// container disappears — its title, its id, and with the id gone,
        /// every view targeting it becomes an unknown-container note. Losing a
        /// container over a missing decoration is the wrong trade.
        public let icon: String?
        public let when: String?

        private enum CodingKeys: String, CodingKey {
            case id, title, icon, when
        }

        /// `id` and `title` are strict — a container with neither an identity
        /// nor a label is nothing a view could target or a person could read —
        /// and the two decorations are `try?`, so a wrong-typed one costs
        /// itself instead of the container. Same shape as `View` above.
        ///
        /// No `unreadableKeys` here, though, and that asymmetry is deliberate.
        /// A container's decorations do have value — its `icon` is carried raw
        /// for a future host — but under Ruling FD they reach no decision in
        /// this one: nothing renders a container, and nothing reads
        /// `containers(for:)` yet. When something does, container notes and
        /// this field arrive together; adding it now would be a property with
        /// no reader. It is the same reason containers get no notes at all. A
        /// view's dropped `when` is a different matter, because a view becomes
        /// a registered, always-offered pane.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            icon = try? container.decode(String.self, forKey: .icon)
            when = try? container.decode(String.self, forKey: .when)
        }
    }

    public struct LanguageModelTool: Codable, Sendable, Equatable {
        public let name: String
        public let displayName: String?
        public let modelDescription: String?
        public let toolReferenceName: String?
        public let inputSchema: JSONValue?
        public let tags: [String]?
        public let canBeReferencedInPrompt: Bool?
    }
}
