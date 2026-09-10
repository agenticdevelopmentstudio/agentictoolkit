//
//  ExtensionResourcePath.swift
//  AgenticToolkit
//

import Foundation

/// Why a path an extension declared was refused.
public enum ExtensionResourcePathError: Error, Equatable {
    /// The declared path resolved outside the directory it had to stay inside.
    /// Both spellings are carried: `declared` is the string the extension
    /// author has to fix, `resolved` is where it actually landed — which is
    /// the only thing that makes a refusal checkable.
    case escapesExtensionDirectory(declared: String, resolved: String)
}

extension ExtensionResourcePathError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .escapesExtensionDirectory(let declared, let resolved):
            return "The path “\(declared)” resolves to \(resolved), which is outside "
                 + "the extension's own directory."
        }
    }
}

/// Resolves a path a third-party extension declared, and proves it stayed
/// inside the directory it was allowed to reach.
///
/// **One implementation, four call sites.** `contributes.snippets[].path`,
/// `contributes.themes[].path`, a theme file's `include`, and an extension's
/// `browser` entry point are all strings an extension author chose, resolved
/// against a directory this app owns. Each one used to re-derive the base URL
/// in its own words and only the entry point checked for escape, so the same
/// `../../../.ssh/config` read arbitrary files through the other three. The
/// rule is written once here so a fifth contribution point inherits it rather
/// than re-deriving it (`dry`).
///
/// Foundation only, so it sits in `AgenticToolkitCore` — the lowest tier that
/// can hold it, reachable from `Language/` and `macOS/` alike.
public enum ExtensionResourcePath {

    // MARK: - Resolution

    /// The URL `declared` names inside `directory`, refusing anything that
    /// escapes it.
    ///
    /// - Parameters:
    ///   - declared: The path exactly as the manifest or theme file spelled it,
    ///     typically `./themes/dark.json`.
    ///   - directory: The extension's own folder — both what `declared` is
    ///     resolved against and what it may not leave.
    /// - Returns: The canonical (symlink-resolved, standardized) URL.
    /// - Throws: `ExtensionResourcePathError.escapesExtensionDirectory`.
    public static func resolve(_ declared: String, inside directory: URL) throws -> URL {
        try resolve(declared, relativeTo: directory, containedIn: directory)
    }

    /// The URL `declared` names relative to `base`, refusing anything outside
    /// `root`.
    ///
    /// The two directories come apart for a theme file's `include`: the
    /// include is written relative to the *including file's* directory, but
    /// what it may not leave is the whole extension folder, which is usually
    /// one level up.
    ///
    /// - Throws: `ExtensionResourcePathError.escapesExtensionDirectory`.
    public static func resolve(
        _ declared: String,
        relativeTo base: URL,
        containedIn root: URL
    ) throws -> URL {
        let canonicalRoot = canonicalDirectory(root)
        // `relativeTo:` rather than stripping a leading "./" and appending:
        // most declarations are written "./themes/x.json" but not all are, and
        // a strip that assumes the prefix mangles the ones that are not.
        let candidate = URL(fileURLWithPath: declared, relativeTo: canonicalDirectory(base))
            .resolvingSymlinksInPath()
            .standardizedFileURL

        guard url(candidate, isContainedIn: canonicalRoot) else {
            throw ExtensionResourcePathError.escapesExtensionDirectory(
                declared: declared,
                resolved: candidate.path
            )
        }
        return candidate
    }

    // MARK: - Primitives

    /// A directory URL fit to resolve relative paths against.
    ///
    /// `isDirectory: true` is spelled out because the single-argument
    /// initializers consult the file system for that flag, and a base that
    /// lost it makes `URL(fileURLWithPath:relativeTo:)` resolve against the
    /// base's *parent* — reading every declared file one level too high, which
    /// is an escape by itself.
    ///
    /// Symlinks first, then `..` removal, and the same treatment for both
    /// sides of the comparison: on macOS the temporary directory alone is a
    /// symlink (`/var` → `/private/var`), so a base and a candidate normalized
    /// differently would compare unequal for every path and the check would
    /// refuse everything — or, resolved the other way round, would accept an
    /// escape through a symlink planted inside the extension.
    public static func canonicalDirectory(_ directory: URL) -> URL {
        URL(fileURLWithPath: directory.path, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
    }

    /// Whether `candidate` is strictly below `base`.
    ///
    /// Compares path *components*, not string prefixes: `/tmp/ext-evil` has
    /// `/tmp/ext` as a string prefix and is not inside it, and a check that
    /// missed that would let an attacker choose a sibling directory name.
    ///
    /// Both arguments are expected to be canonical already —
    /// `resolve(_:relativeTo:containedIn:)` is what normally supplies them.
    public static func url(_ candidate: URL, isContainedIn base: URL) -> Bool {
        let baseComponents = base.pathComponents
        let candidateComponents = candidate.pathComponents
        guard candidateComponents.count > baseComponents.count else { return false }
        return Array(candidateComponents.prefix(baseComponents.count)) == baseComponents
    }
}
