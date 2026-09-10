//
//  SnippetStore.swift
//  AgenticToolkit
//

import AgenticToolkitCore
import Foundation

/// One snippet file an extension declared that could not be read.
///
/// `reason` is the thrown error's description rather than the error itself,
/// for the same reason `ExtensionLoadError.manifestMalformed` carries a
/// `String`: this is `Equatable` and `Sendable` so a settings panel can diff
/// it, and `any Error` is neither. Nothing downstream of a broken snippets
/// file branches on the error's *type* — it is shown to a human.
public struct SnippetFileFailure: Sendable, Equatable {
    public let extensionIdentifier: String
    /// The path exactly as the manifest declared it, not the resolved URL:
    /// what the extension author has to fix is the string in `package.json`.
    public let path: String
    public let reason: String
}

/// The `contributes.snippets` contribution point: every extension-supplied
/// snippet, keyed by the language it completes in.
///
/// A store, not an importer — one long-lived object that several extensions
/// apply into and withdraw from, which is the shape `ContributionPoint`
/// requires. What it produces is `CompletionItem`s with
/// `insertTextFormat == .snippet`, so extension snippets travel the same path
/// a language server's own snippets already do and need no insertion code of
/// their own.
@MainActor
public final class SnippetStore: ContributionPoint {

    // MARK: - Properties

    /// Snippets by language id, per extension identifier.
    ///
    /// Nested by extension rather than flat by language because withdrawal is
    /// by extension: a flat map would have to be swept language by language to
    /// remove one extension's contributions.
    private var snippetsByExtension: [String: [String: [ExtensionSnippet]]] = [:]

    /// Files that failed to parse, for the extensions settings panel.
    ///
    /// Not an error thrown out of `apply`: one unreadable file must not cost
    /// an extension its other snippet files, the same leniency
    /// `ExtensionManifest.decodeLenientArray` applies to contributions.
    public private(set) var failures: [SnippetFileFailure] = []

    // MARK: - Initialization

    public init() {}

    // MARK: - ContributionPoint

    public var contributionKey: String { "snippets" }

    /// Reads every snippet file this extension declares.
    ///
    /// Replaces whatever this extension contributed before, so applying twice
    /// leaves one copy rather than two — the registry withdraws before it
    /// reloads, but an idempotent apply means that ordering is not this
    /// class's to depend on.
    ///
    /// Never throws in practice: a file that will not parse is recorded in
    /// `failures` and the rest are read. `throws` remains in the signature
    /// because `ContributionPoint` declares it, and because a future
    /// whole-extension failure has somewhere to go.
    public func apply(
        _ contributions: ExtensionManifest.Contributions,
        from manifest: ExtensionManifest,
        at directory: URL
    ) throws {
        let identifier = manifest.identifier
        withdraw(extensionIdentifier: identifier)
        guard !contributions.snippets.isEmpty else { return }

        var byLanguage: [String: [ExtensionSnippet]] = [:]
        var recorded: [SnippetFileFailure] = []

        // Re-made as an explicit directory URL before anything is resolved
        // against it. `URL(fileURLWithPath:relativeTo:)` resolves relative to
        // the base's *parent* unless the base is known to be a directory, and
        // a `URL` built by a caller that did not say so — `URL(fileURLWithPath:)`
        // with no `isDirectory:` — silently reads every snippet file one level
        // too high.
        let base = URL(fileURLWithPath: directory.path, isDirectory: true)

        for entry in contributions.snippets {
            // The entry's path is relative to the extension's own folder.
            // `URL(fileURLWithPath:relativeTo:)` rather than a `./` strip:
            // nearly every real entry is written `./snippets/x.json`, but not
            // all of them are, and a strip that assumes the prefix mangles the
            // ones that are not.
            let url = URL(fileURLWithPath: entry.path, relativeTo: base)
            do {
                let snippets = try SnippetFile.parse(contentsOf: url, extensionIdentifier: identifier)
                byLanguage[entry.language, default: []].append(contentsOf: snippets)
            } catch {
                recorded.append(
                    SnippetFileFailure(
                        extensionIdentifier: identifier,
                        path: entry.path,
                        reason: String(describing: error)
                    )
                )
            }
        }

        if !byLanguage.isEmpty { snippetsByExtension[identifier] = byLanguage }
        failures.append(contentsOf: recorded)
    }

    /// Removes this extension's snippets and the failures recorded for it.
    ///
    /// Its failures go too: they describe files this extension declared, and a
    /// panel still listing them after the extension is gone is showing a
    /// problem nobody can fix.
    public func withdraw(extensionIdentifier: String) {
        snippetsByExtension.removeValue(forKey: extensionIdentifier)
        failures.removeAll { $0.extensionIdentifier == extensionIdentifier }
    }

    // MARK: - Lookup

    /// Every snippet available for a language id, across all applied
    /// extensions.
    ///
    /// Ordered by extension identifier, then by the order the files were
    /// declared in. A dictionary has no order of its own, and a completion
    /// list that reshuffles itself between launches is worse than one whose
    /// order is arbitrary but fixed.
    public func snippets(forLanguage language: String) -> [ExtensionSnippet] {
        snippetsByExtension.keys.sorted().flatMap { identifier in
            (snippetsByExtension[identifier]?[language] ?? []).filter { $0.applies(to: language) }
        }
    }
}
