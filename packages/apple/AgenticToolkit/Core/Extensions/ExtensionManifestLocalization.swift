//
//  ExtensionManifestLocalization.swift
//  AgenticToolkit
//

import Foundation

/// Resolves the `%key%` placeholders a `package.json` uses in place of the
/// strings a person will read.
///
/// **A manifest that ships translations has no English in it.** Where a
/// single-language extension writes `"displayName": "Material Icon Theme"`, one
/// with translations writes `"displayName": "%name%"` and puts the English in
/// `package.nls.json` beside it, the German in `package.nls.de.json`, and so on
/// for however many languages it has. Load the manifest without reading those
/// files and the settings pane lists `%configuration.activeIconPack%` and
/// seventy-one more like it, while an extension with no translations at all
/// looks perfect — which is what made this easy to miss.
///
/// Foundation only, so it sits in `AgenticToolkitCore` beside the manifest it
/// serves, reachable from both of its readers: `ExtensionRegistry`, which
/// decodes an extension that is installed, and `VSIXInstaller`, which decodes
/// one it is about to install.
public enum ExtensionManifestLocalization {

    // MARK: - Public API

    /// `json` with every placeholder the tables beside it can answer replaced
    /// by the string it stands for.
    ///
    /// **This never throws and never fails.** A table that is missing,
    /// unreadable or not JSON costs the extension its translations and nothing
    /// else — refusing the manifest would turn a typo in a file nobody executes
    /// into an extension that has vanished. A placeholder with no entry is left
    /// standing, exactly as VS Code leaves it: `%name%` on screen says the
    /// extension's own table is incomplete, where a blank row says nothing at
    /// all.
    ///
    /// When there is nothing to substitute the input is returned **unchanged**,
    /// byte for byte, rather than parsed and re-serialised. Most extensions
    /// have no translations at all, and they should not pay for a round-trip —
    /// nor risk one.
    ///
    /// - Parameters:
    ///   - json: the bytes of a `package.json`, strict or JSONC.
    ///   - directory: the directory that file was read from, which is where the
    ///     tables live.
    ///   - locale: whose language to prefer. The default is the reader's.
    public static func localize(
        _ json: Data,
        forManifestIn directory: URL,
        locale: Locale = .current
    ) -> Data {
        let table = Self.table(in: directory, for: locale)
        guard !table.isEmpty else { return json }
        guard let tree = try? JSONCPreprocessor.jsonObject(from: json) else { return json }
        guard let rewritten = try? JSONSerialization.data(
            withJSONObject: Self.substituting(tree, using: table))
        else { return json }
        return rewritten
    }

    // MARK: - The tables

    /// Every table that applies to `locale`, merged, most specific last.
    ///
    /// **The default table stays underneath rather than being replaced.** A
    /// translation is nearly always less complete than the English it was made
    /// from, so overlaying is what stops choosing a language from turning the
    /// untranslated half of a manifest back into placeholders — which would be
    /// worse than not translating at all.
    private static func table(in directory: URL, for locale: Locale) -> [String: String] {
        let present = Self.fileNames(in: directory)
        var merged: [String: String] = [:]
        for name in Self.tableNames(for: locale) {
            // Matched without regard to case, because the names on disk are
            // not consistent about it: `package.nls.pt-BR.json` and
            // `package.nls.zh-CN.json` ship with exactly that capitalisation,
            // and the region subtag this composes is upper-case for the same
            // reason, but neither is a promise.
            guard let actual = present[name.lowercased()] else { continue }
            merged.merge(
                Self.entries(inTableAt: directory.appendingPathComponent(actual)),
                uniquingKeysWith: { _, morePreferred in morePreferred })
        }
        return merged
    }

    /// The table filenames that apply to `locale`, least specific first.
    ///
    /// VS Code looks for the region before the bare language before the
    /// default, and so does this — `package.nls.pt-BR.json` and
    /// `package.nls.pt-PT.json` both ship in real extensions and are not
    /// interchangeable. The order here is reversed from that, because these
    /// names are merged in sequence and the last one written is the one kept.
    private static func tableNames(for locale: Locale) -> [String] {
        var names = ["package.nls.json"]
        guard let language = locale.language.languageCode?.identifier else { return names }
        names.append("package.nls.\(language).json")
        if let region = locale.region?.identifier {
            names.append("package.nls.\(language)-\(region).json")
        }
        return names
    }

    /// The strings in one table file, or nothing at all if it cannot be read.
    private static func entries(inTableAt url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        guard let tree = try? JSONCPreprocessor.jsonObject(from: data) else { return [:] }
        guard let object = tree as? [String: Any] else { return [:] }
        return object.compactMapValues(Self.message(of:))
    }

    /// The string an entry stands for, in either shape a table uses.
    ///
    /// The older format is `"key": "the string"`. The newer one is
    /// `"key": { "message": "the string", "comment": ["for the translator"] }`,
    /// and both are on the registry today — an entry in the second shape that
    /// went unrecognised would leave its placeholder on screen.
    private static func message(of value: Any) -> String? {
        if let string = value as? String { return string }
        if let object = value as? [String: Any] { return object["message"] as? String }
        return nil
    }

    // MARK: - The substitution

    /// `value` with every placeholder anywhere inside it resolved.
    ///
    /// A walk of the parsed document rather than a search-and-replace over its
    /// text: placeholders appear at every depth (`contributes.configuration[]
    /// .properties.<setting>.description` is five levels down), and a textual
    /// pass cannot tell a `%key%` that is a value from one that is part of a
    /// key, a path, or a string that only looks like one.
    ///
    /// Everything that is not a string is returned as it came. The round-trip
    /// through `JSONSerialization` is safe for the rest because a number is the
    /// only lossy shape and `ExtensionManifest.JSONValue` models every number
    /// as a `Double`, so no distinction the manifest can observe survives to be
    /// lost.
    private static func substituting(_ value: Any, using table: [String: String]) -> Any {
        switch value {
        case let string as String:
            return Self.resolving(string, using: table)
        case let array as [Any]:
            return array.map { Self.substituting($0, using: table) }
        case let object as [String: Any]:
            // Values only. A key is a name the host matches on — a command id,
            // a setting id, a language id — and one that picked up a
            // translation would be looked up under a word nothing else uses.
            return object.mapValues { Self.substituting($0, using: table) }
        default:
            return value
        }
    }

    /// `string` resolved, if it is a placeholder and the table has an answer.
    ///
    /// **Only a string that is *entirely* a placeholder is a reference.** A
    /// percentage in ordinary prose is prose — "Uses 50% of one core" is a
    /// description, not a lookup of `of one core, at most" … "Uses 50`. That is
    /// VS Code's rule too, and it is why this tests both ends rather than
    /// scanning for `%`.
    private static func resolving(_ string: String, using table: [String: String]) -> String {
        guard string.count > 2, string.hasPrefix("%"), string.hasSuffix("%") else { return string }
        let key = String(string.dropFirst().dropLast())
        guard !key.contains("%") else { return string }
        return table[key] ?? string
    }

    /// Everything in `directory`, indexed by its lower-cased name.
    ///
    /// Read once for the whole call rather than probed per candidate: three
    /// `fileExists` calls would not answer the case question anyway, and this
    /// runs for every extension in every rescan.
    private static func fileNames(in directory: URL) -> [String: String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [:] }
        return Dictionary(
            contents.map { ($0.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first })
    }
}
