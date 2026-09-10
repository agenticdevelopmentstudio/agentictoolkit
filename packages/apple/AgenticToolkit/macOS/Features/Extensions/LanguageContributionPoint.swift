//
//  LanguageContributionPoint.swift
//  AgenticToolkit
//

import AgenticToolkitCore
import Foundation

/// One matcher an extension declared that this build cannot honour.
///
/// A record rather than a thrown error, for the same reason
/// `SnippetFileFailure` is one: a language entry this host cannot fully
/// represent must not cost the extension its other entries, and what was
/// dropped is shown to a person in the extensions settings panel.
public struct DroppedLanguageMatcher: Sendable, Equatable {
    public let extensionIdentifier: String
    public let languageID: String

    /// The manifest keys dropped, in the order
    /// `LanguageContributionPoint.unrepresentableKeys(of:)` reports them:
    /// `filenames`, `filenamePatterns`, `firstLine`, `icon`,
    /// `configuration`, then `extensions` when *individual* values were
    /// unrepresentable.
    ///
    /// A fixed order rather than the order the keys appeared in the JSON:
    /// `ExtensionManifest.Language` is a decoded struct, and a decoder does
    /// not preserve key order, so the manifest's own order is not
    /// recoverable here. This one matches the order the keys are listed in
    /// VS Code's `contributes.languages` schema.
    public let keys: [String]

    /// The individual `extensions` values skipped, exactly as the manifest
    /// wrote them — what an extension author has to change is the string in
    /// `package.json`, not its normalised form.
    public let skippedExtensions: [String]

    public init(
        extensionIdentifier: String,
        languageID: String,
        keys: [String],
        skippedExtensions: [String]
    ) {
        self.extensionIdentifier = extensionIdentifier
        self.languageID = languageID
        self.keys = keys
        self.skippedExtensions = skippedExtensions
    }
}

/// Two language entries claiming the same file extension. First registered
/// wins — within one manifest that is manifest order, across manifests it is
/// the order they were applied in.
public struct LanguageContributionConflict: Sendable, Equatable {
    public let fileExtension: String
    /// The extension identifier whose mapping is in force.
    public let winner: String
    /// The extension identifier whose mapping was refused. Equal to `winner`
    /// when one manifest claimed the same file extension twice.
    public let loser: String
    public let losingLanguageID: String

    public init(fileExtension: String, winner: String, loser: String, losingLanguageID: String) {
        self.fileExtension = fileExtension
        self.winner = winner
        self.loser = loser
        self.losingLanguageID = losingLanguageID
    }
}

/// The `contributes.languages` contribution point: an extension's declared
/// file extensions, answered through the file-type mapping table the file
/// browser and the editor already consult.
///
/// Contributed mappings never enter `CustomFileTypeMappings`' persisted
/// array. They are answered from here, through
/// `CustomFileTypeMappings.contributedProvider`, and only when the user's own
/// mappings do not claim the extension — so precedence is user > extension >
/// built-in, and an installed extension can never silently change a mapping
/// the user typed themselves. The persisted array is also the exact array
/// `FileTypesSettingsView` presents as the user's own editable, deletable
/// rows, and it outlives any extension that wrote into it.
///
/// Only `extensions` maps. `CustomFileTypeMapping` is extension-keyed by
/// construction — `filenames`, `filenamePatterns` and `firstLine` have
/// nowhere to go without a persistence migration on a user-facing model, and
/// `icon` is a pair of file paths where `iconName` wants an SF Symbol. Each
/// of those is reported in `dropped` rather than ignored, so a user who
/// wonders why `Dockerfile` did not take is told.
@MainActor
public final class LanguageContributionPoint: ContributionPoint {

    // MARK: - Constants

    /// Every contributed mapping carries this icon.
    ///
    /// A placeholder, not a lookup: the manifest's `icon` is a `{light, dark}`
    /// pair of *file paths* into the extension, and `iconName` is an SF Symbol
    /// name. There is no conversion between the two, so the icon is dropped
    /// (and reported) and every contributed row shows the generic document
    /// symbol.
    private static let placeholderIconName = "doc.text"

    // MARK: - Properties

    /// Each applied extension's language entries, in manifest order.
    private var languagesByExtension: [String: [ExtensionManifest.Language]] = [:]

    /// The identifiers in the order they were first applied, which is the
    /// order conflicts are resolved in. A dictionary has none of its own, and
    /// "first registered wins" is only meaningful against a recorded order.
    private var applicationOrder: [String] = []

    /// The resolved lookup table, behind a lock.
    ///
    /// Not main-actor state, even though everything that builds it is:
    /// `FileTreeNode.fileIconName` — one of the two callers that reach this
    /// through `CustomFileTypeMappings.mapping(for:)` — is a nonisolated
    /// member of an `@unchecked Sendable` class and runs while a directory is
    /// being enumerated off the main actor. A main-actor-isolated provider
    /// could not be called from there at all, and one that hopped through
    /// `MainActor.assumeIsolated` would trap there.
    private nonisolated let table = ContributedMappings()

    /// Matchers that could not be represented, across every applied
    /// extension, in application order then manifest order.
    public private(set) var dropped: [DroppedLanguageMatcher] = []

    /// File extensions claimed more than once, with the claim that won.
    public private(set) var conflicts: [LanguageContributionConflict] = []

    // MARK: - Initialization

    public init() {}

    // MARK: - ContributionPoint

    public var contributionKey: String { "languages" }

    /// Registers this extension's language entries.
    ///
    /// `at directory:` is deliberately unused, and this is the one
    /// contribution point where that is true. Every key of a language entry
    /// that names a file — `configuration`, `icon` — is dropped and reported
    /// rather than read, so there is no manifest-relative path to resolve and
    /// nothing to open. Read as an omission it looks like a bug; it is not.
    ///
    /// Replaces whatever this extension contributed before, so applying twice
    /// leaves one copy. Deliberately *not* a call to `withdraw` first, unlike
    /// the snippet point: withdrawal also drops the extension's place in
    /// `applicationOrder`, and a reloaded extension would silently lose every
    /// file extension it had won against an extension applied after it.
    /// Replacing the entry in place keeps precedence stable across a reload.
    ///
    /// Never throws. A language entry that contributes nothing usable is a
    /// `dropped` row, not a failure — there is no input here that costs the
    /// extension its load. `throws` remains because `ContributionPoint`
    /// declares it.
    public func apply(
        _ contributions: ExtensionManifest.Contributions,
        from manifest: ExtensionManifest,
        at _: URL
    ) throws {
        let identifier = manifest.identifier
        if !applicationOrder.contains(identifier) {
            applicationOrder.append(identifier)
        }
        languagesByExtension[identifier] = contributions.languages
        rebuild()
    }

    /// Removes this extension's mappings, its dropped rows and every conflict
    /// naming it as either party.
    ///
    /// The whole table is re-derived rather than patched: a mapping that was
    /// losing to a now-uninstalled extension has to take effect, and its
    /// conflict row has to go. Patching in place would have to find both, and
    /// these tables are small enough that correctness is the cheaper trade.
    public func withdraw(extensionIdentifier: String) {
        guard languagesByExtension.removeValue(forKey: extensionIdentifier) != nil else { return }
        applicationOrder.removeAll { $0 == extensionIdentifier }
        rebuild()
    }

    // MARK: - Lookup

    /// The contributed mapping for a file extension, if any.
    ///
    /// `fileExtension` arrives already lowercased and non-empty — it is the
    /// key `CustomFileTypeMappings.mapping(for:)` looked itself up with — so
    /// this neither re-lowercases nor guards. Nonisolated because
    /// `CustomFileTypeMappings.contributedProvider` is called from wherever a
    /// file icon is resolved; see `table`.
    public nonisolated func mapping(for fileExtension: String) -> CustomFileTypeMapping? {
        table.mapping(for: fileExtension)
    }

    /// Installs `mapping(for:)` as `CustomFileTypeMappings.contributedProvider`.
    ///
    /// Separate from `init` so a test can build one without touching global
    /// state, and so the host decides when the hook goes live. `weak` so a
    /// discarded point stops answering rather than being kept alive forever by
    /// a global.
    public func install() {
        CustomFileTypeMappings.contributedProvider = { [weak self] fileExtension in
            self?.mapping(for: fileExtension)
        }
    }

    // MARK: - Derivation

    /// Rebuilds the lookup table, the dropped rows and the conflicts from
    /// everything currently applied. The single place any of the three is
    /// written, so they cannot disagree.
    private func rebuild() {
        var resolved: [String: (owner: String, mapping: CustomFileTypeMapping)] = [:]
        var droppedRows: [DroppedLanguageMatcher] = []
        var conflictRows: [LanguageContributionConflict] = []

        for identifier in applicationOrder {
            for language in languagesByExtension[identifier] ?? [] {
                // VS Code shows the first alias as the language's display
                // name and falls back to the id; `languageName` is a display
                // string, so it follows the same rule.
                let displayName = language.aliases?.first ?? language.id
                var skipped: [String] = []

                for declared in language.extensions ?? [] {
                    guard let normalized = Self.normalizedExtension(declared) else {
                        skipped.append(declared)
                        continue
                    }
                    if let winner = resolved[normalized] {
                        conflictRows.append(
                            LanguageContributionConflict(
                                fileExtension: normalized,
                                winner: winner.owner,
                                loser: identifier,
                                losingLanguageID: language.id
                            )
                        )
                        continue
                    }
                    resolved[normalized] = (
                        owner: identifier,
                        mapping: CustomFileTypeMapping(
                            fileExtension: normalized,
                            languageName: displayName,
                            iconName: Self.placeholderIconName
                        )
                    )
                }

                var keys = Self.unrepresentableKeys(of: language)
                if !skipped.isEmpty { keys.append("extensions") }
                // An entry with nothing to drop produces no row — including
                // one that declared no matcher at all. A row naming no keys
                // and no skipped values tells a reader nothing they could act
                // on.
                guard !keys.isEmpty else { continue }
                droppedRows.append(
                    DroppedLanguageMatcher(
                        extensionIdentifier: identifier,
                        languageID: language.id,
                        keys: keys,
                        skippedExtensions: skipped
                    )
                )
            }
        }

        table.replace(with: resolved.mapValues(\.mapping))
        dropped = droppedRows
        conflicts = conflictRows
    }

    /// The keys of a language entry this build cannot honour at all.
    ///
    /// `mimetypes` is in VS Code's schema and is equally unrepresentable
    /// here, but `ExtensionManifest.Language` does not model it, so it cannot
    /// be reported: it is gone before this point sees the entry.
    private static func unrepresentableKeys(of language: ExtensionManifest.Language) -> [String] {
        var keys: [String] = []
        if language.filenames?.isEmpty == false { keys.append("filenames") }
        if language.filenamePatterns?.isEmpty == false { keys.append("filenamePatterns") }
        if language.firstLine?.isEmpty == false { keys.append("firstLine") }
        if language.icon != nil { keys.append("icon") }
        if language.configuration?.isEmpty == false { keys.append("configuration") }
        return keys
    }

    /// The lookup key for one declared `extensions` value, or `nil` when the
    /// value cannot be one.
    ///
    /// Both spellings are real — a recon over 1,069 published values found
    /// 95.3% written `.rb` and 4.7% written `rb` — so exactly one leading dot
    /// is stripped and neither form is assumed.
    ///
    /// A value that still contains a `.` after that (`cspell.json`,
    /// `color-theme.json`, `js.j2`) or contains a glob character (`*.log.?`)
    /// is refused rather than stored: this table is only ever consulted with
    /// `URL.pathExtension`, which is the final segment alone, so such a key
    /// could never match. A mapping that cannot fire is worse than an honest
    /// report that it was skipped.
    private static func normalizedExtension(_ declared: String) -> String? {
        var value = declared
        if value.hasPrefix(".") { value.removeFirst() }
        value = value.lowercased()
        guard !value.isEmpty else { return nil }
        guard !value.contains("."), !value.contains("*"), !value.contains("?") else { return nil }
        return value
    }
}

// MARK: - Contributed Mappings

/// The resolved extension→mapping table, readable from any thread.
///
/// `NSLock` rather than an actor or a `nonisolated(unsafe)` dictionary: the
/// readers are synchronous and cannot await, and the writes are rare (an
/// extension load or unload) while the reads are on the file-tree rendering
/// path. Matches `HeuristicRegistry`'s idiom in `Core/`.
private final class ContributedMappings: @unchecked Sendable {
    private let lock = NSLock()
    private var mappings: [String: CustomFileTypeMapping] = [:]

    func replace(with mappings: [String: CustomFileTypeMapping]) {
        lock.lock()
        defer { lock.unlock() }
        self.mappings = mappings
    }

    func mapping(for fileExtension: String) -> CustomFileTypeMapping? {
        lock.lock()
        defer { lock.unlock() }
        return mappings[fileExtension]
    }
}
