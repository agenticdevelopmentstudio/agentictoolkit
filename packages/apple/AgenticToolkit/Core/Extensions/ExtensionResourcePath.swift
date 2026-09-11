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

/// Where user-installed add-ons live: the two directories this project's hosts
/// look in for content a user drops beside the app rather than inside it.
///
/// Both conventions were written out twice before this type existed — once in
/// `AIPluginManager.init(appName:additionalSearchPaths:)` for `.aiplugin`
/// bundles, once in the app leaf for VS Code extensions — and the copies had
/// already drifted in how they name the home directory (`NSHomeDirectory()`
/// against an overridable one). A change to either convention — a sandbox
/// container, a Time Machine exclusion, a security-scoped bookmark — now has
/// one place to happen instead of one place to happen and one to be forgotten
/// (`dry`).
///
/// **Locations, not a list.** Each host composes its own search *order*,
/// because the orders differ and the difference means something: the plugin
/// manager looks inside the app bundle first, so a shipped plugin wins over a
/// hand-installed one of the same identifier, while the extension host looks
/// in Application Support first, where an installer writes. One ordered list
/// here would have had to pick one of those silently, and changing which
/// directory wins is a behaviour change wearing a refactor's clothes.
///
/// Not beside `AppStorageLocation`, despite that type owning the app's *own*
/// `~/.<token>` directory, for two reasons. It lives in `apple-database`,
/// which `apple-pluginkit` does not depend on, so sharing from there would add
/// a framework to the embed set for no behaviour. And it is not the same
/// convention: these folders are named after the kind of content
/// (`.agenticplugins`, `.agenticextensions`), not after the app.
///
/// In this file rather than one of its own to keep the `apple-core` tier's
/// file set as it is; the type is independent of everything else here beyond
/// both being about where extension content is found.
///
/// Nothing here touches the file system: these are derivations, and every
/// caller already skips a search path it cannot read. Creating an empty folder
/// for a feature the user has not used is a side effect nobody asked for.
public enum InstalledContentLocation {

    /// `~/Library/Application Support/<appName>/<subdirectory>`, or `nil` when
    /// the user domain has no Application Support directory to name.
    ///
    /// `appName` is the display name, spaces and all — that is what names an
    /// Application Support subdirectory by macOS convention. It must not be
    /// empty: an empty component collapses the path onto the *shared*
    /// `Application Support/<subdirectory>` and silently widens the search to
    /// every app's content of that kind. Callers derive it through something
    /// that cannot answer `""` — `AppStorageLocation.displayName` for this
    /// project's apps.
    public static func applicationSupport(appName: String, subdirectory: String) -> URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent(subdirectory, isDirectory: true)
    }

    /// `<home>/.<name>` — the dotfolder a developer can fill by hand, with no
    /// installer and no code signature in the way.
    ///
    /// - Parameters:
    ///   - name: The folder name *without* its leading dot, e.g.
    ///     `"agenticplugins"`. Dotless at the call site is what keeps "these
    ///     are hidden folders" a property of this function rather than of each
    ///     caller's string literal.
    ///   - home: The home directory to resolve against, defaulting to the
    ///     process's own. A host that lets a test point the home somewhere
    ///     temporary passes that instead, so a test run reads its own fixture
    ///     rather than whatever the developer has installed.
    public static func homeDotDirectory(
        named name: String,
        in home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> URL {
        home.appendingPathComponent(".\(name)", isDirectory: true)
    }
}
