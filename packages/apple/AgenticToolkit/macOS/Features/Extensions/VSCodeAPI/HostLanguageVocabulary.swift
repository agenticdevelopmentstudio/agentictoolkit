//
//  HostLanguageVocabulary.swift
//  AgenticToolkit
//

import CodeEditLanguages
import Foundation

/// The production `ExtensionLanguageVocabulary`: every language identifier
/// this host knows, for `vscode.languages.getLanguages()`.
///
/// Composes two halves that are each already deterministic, so the
/// concatenation is too:
///
/// - **Built-ins first** — `CodeLanguage.allLanguages`, in that array's own
///   order, with `CodeLanguage.default`'s id appended. `allLanguages` does not
///   include `.default` (VS Code's "plain text"); it is read from
///   `CodeLanguage.default.id` rather than spelled `"plainText"` so a
///   CodeEditLanguages release that changes the default follows without an
///   edit here.
/// - **Then every contributed identifier not already present**, in
///   `LanguageContributionPoint.contributedLanguageIdentifiers`'s order.
///
/// Built-ins lead because an extension contributing an id CodeEditLanguages
/// already has is adding a file-extension claim to an existing language, not
/// declaring a new one, and the built-in entry is the one that was there
/// first.
///
/// **Does not use `CodeLanguage.tsName`.** It names the tree-sitter grammar,
/// not the language — `jsx`/`javascript`, `tsx`/`typescript` and
/// `ocamlInterface`/`ocaml` each share one, so building on it would return
/// duplicates and lose three languages that `id` keeps distinct.
///
/// **The built-in loop's `seen.insert` is defensive, not load-bearing
/// today.** Every entry in `CodeLanguage.allLanguages` is a distinct
/// `TreeSitterLanguage` case, so `id` is already unique across them and no
/// test can distinguish this guard from an unconditional append. It stays
/// anyway: `allLanguages` is a third-party package's table, not ours, the
/// guard costs one set insertion this code is already paying for the later
/// loops, and removing it would let a future duplicate in someone else's
/// array reach an extension silently.
///
/// **This host's own vocabulary, not a translation into VS Code's.** Some of
/// these ids (`cSharp`, `jsx`, `tsx`, `objc`, `bash`, `goMod`, `jsdoc`,
/// `markdownInline`, `regex`) are not spellings VS Code uses. They are
/// returned anyway, deliberately: upstream's push-and-cache exists to
/// amortize a process boundary this host does not have, not to translate
/// vocabulary, and this host's own ids are what an extension asking "what
/// languages does this editor know" actually wants.
@MainActor
public final class HostLanguageVocabulary: ExtensionLanguageVocabulary {
    private let contributionPoint: LanguageContributionPoint

    public init(contributionPoint: LanguageContributionPoint) {
        self.contributionPoint = contributionPoint
    }

    /// Computed, never cached: `contributionPoint`'s contributions can change
    /// between calls as extensions load and unload, and `Ruling 16` requires
    /// a fresh array on every call in any case.
    public var languageIdentifiers: [String] {
        var seen: Set<String> = []
        var identifiers: [String] = []

        for language in CodeLanguage.allLanguages {
            let id = language.id.rawValue
            if seen.insert(id).inserted {
                identifiers.append(id)
            }
        }
        let defaultId = CodeLanguage.default.id.rawValue
        if seen.insert(defaultId).inserted {
            identifiers.append(defaultId)
        }

        for id in contributionPoint.contributedLanguageIdentifiers where seen.insert(id).inserted {
            identifiers.append(id)
        }

        return identifiers
    }
}
