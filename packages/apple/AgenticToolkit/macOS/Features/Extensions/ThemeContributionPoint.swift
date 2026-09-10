//
//  ThemeContributionPoint.swift
//  AgenticToolkit
//

import Foundation

import AgenticToolkitCore

/// The `contributes.themes` point: turns an extension's VS Code colour theme
/// files into themes in the app's own `ThemeStore`.
///
/// It lives in `apple-macos` rather than beside `ExtensionRegistry` in
/// `apple-core` because `ThemeStore` ships from the `agenticdevelopertoolkit`
/// submodule and `Core/` only re-exports the model — a point that *writes* to
/// the store needs the tier that may depend on it.
///
/// The store is injected, never reached for globally: two stores over the same
/// persisted `customThemes` would each overwrite the other's list.
@MainActor
public final class ThemeContributionPoint: ContributionPoint {

    private let themeStore: ThemeStore

    /// Themes that would not parse, across every extension applied so far.
    public private(set) var importFailures: [ThemeImportFailure] = []

    public init(themeStore: ThemeStore) {
        self.themeStore = themeStore
    }

    public var contributionKey: String { "themes" }

    /// The id a contributed theme is stored under.
    ///
    /// Deterministic on purpose (Ruling FF). `ThemeStore.add` appends with no
    /// dedup and custom themes persist, so an id derived from the contribution
    /// itself is the only thing that lets `apply` reconcile instead of grow the
    /// user's theme list by one copy of everything on every launch.
    public static func themeID(extensionIdentifier: String, label: String) -> String {
        "vscode.\(extensionIdentifier).\(label)"
    }

    /// The `ColorTheme.attribution` value recording which extension owns a theme.
    ///
    /// Nothing in the UI produces this shape, so a theme carrying it can be
    /// pruned when its extension is gone without risking a theme the user made.
    public static func attribution(for extensionIdentifier: String) -> String {
        "extension:\(extensionIdentifier)"
    }

    public func apply(
        _ contributions: ExtensionManifest.Contributions,
        from manifest: ExtensionManifest,
        at directory: URL
    ) throws {
        let identifier = manifest.identifier
        guard !contributions.themes.isEmpty else { return }

        // `directory` arrives from the registry and may have been built with a
        // plain `URL(fileURLWithPath:)`, which carries no is-directory flag —
        // and `URL(fileURLWithPath:relativeTo:)` then resolves against its
        // *parent*, reading every theme one level too high. Re-make the base
        // with the flag set before resolving anything against it.
        let base = URL(fileURLWithPath: directory.path, isDirectory: true)

        var imported = 0
        var written: Set<String> = []
        for theme in contributions.themes {
            // `relativeTo:` rather than stripping a "./" prefix and appending:
            // most manifests write "./themes/x.json" but not all do, and a
            // strip that assumes the prefix mangles the ones that do not.
            let url = URL(fileURLWithPath: theme.path, relativeTo: base)

            // Two themes under one label share an id, so the second would
            // quietly replace the first and both would count as imported —
            // one file in the folder with nothing to show for it and no
            // failure recorded. Keep the first and name the collision.
            guard !written.contains(Self.themeID(extensionIdentifier: identifier, label: theme.label))
            else {
                importFailures.append(
                    ThemeImportFailure(
                        extensionIdentifier: identifier,
                        path: theme.path,
                        message: "another theme in this extension already uses the label "
                            + "“\(theme.label)”."
                    )
                )
                continue
            }

            do {
                let parsed = try VSCodeThemeImporter.parse(
                    contentsOf: url,
                    label: theme.label,
                    uiTheme: theme.uiTheme
                )
                written.insert(store(parsed, label: theme.label, extensionIdentifier: identifier))
                imported += 1
            } catch {
                // One bad file must not cost the extension its other four
                // themes; the panel reports this one and the rest install.
                importFailures.append(
                    ThemeImportFailure(
                        extensionIdentifier: identifier,
                        path: theme.path,
                        message: error.localizedDescription
                    )
                )
            }
        }

        // Nothing imported at all is a contribution with nothing to show for
        // it, so the registry's `contributionPointFailed` entry is the honest
        // report. A partial import is not.
        //
        // Throwing here also skips the reconciliation below, deliberately: a
        // wholly failed import is evidence about nothing, so the themes the
        // previous launch installed stay where they are rather than being taken
        // away as a side effect of one broken file (Ruling GO). The user's
        // recourse would be to reinstall the extension — the thing that just
        // failed.
        if imported == 0 {
            throw ThemeContributionError.everyThemeFailed(count: contributions.themes.count)
        }

        // Reconcile this extension's whole set against what it *declares*: an
        // update that renames "Night" to "Midnight" writes the new id and
        // leaves the old one looking exactly like a theme the extension still
        // provides. `pruneOrphans` cannot see it — the extension is installed —
        // so a successful apply is the only place it can go.
        //
        // Declared, never `written` — the ids that happened to load *this*
        // call (Ruling GS, refining GO one level down). Two themes where one
        // file broke on relaunch imports one, so GO's `imported == 0` throw
        // does not fire, and reconciling against `written` would then delete
        // the previous launch's *working* copy of the theme whose file just
        // broke, taking `activeThemeID` with it. A declaration is evidence of
        // what the extension provides; a load failure is evidence about
        // nothing, and the user's recourse would be to reinstall the extension
        // that just failed.
        //
        // Scoped to this extension's attribution: another extension's themes,
        // and the user's own, are never this call's to delete.
        let attribution = Self.attribution(for: identifier)
        let declared = Set(contributions.themes.map {
            Self.themeID(extensionIdentifier: identifier, label: $0.label)
        })
        for theme in themeStore.customThemes
        where theme.attribution == attribution && !declared.contains(theme.id) {
            themeStore.delete(id: theme.id)
        }
    }

    public func withdraw(extensionIdentifier: String) {
        let attribution = Self.attribution(for: extensionIdentifier)
        for theme in themeStore.customThemes where theme.attribution == attribution {
            // `delete(id:)` clears `activeThemeID` when the active theme goes,
            // so withdrawing the theme the user is looking at cannot leave
            // storage pointing at an id that no longer resolves.
            themeStore.delete(id: theme.id)
        }
        importFailures.removeAll { $0.extensionIdentifier == extensionIdentifier }
    }

    /// Deletes contributed themes whose owning extension is not installed.
    ///
    /// `withdraw` only runs in a live session, so an extension folder deleted
    /// while the app was closed would otherwise leave its themes in the list
    /// forever. Reconcile-on-launch is the only mechanism that can see a change
    /// made while the process was dead. Called once, after `loadAll()`.
    public func pruneOrphans(installedIdentifiers: Set<String>) {
        let installed = Set(installedIdentifiers.map { Self.attribution(for: $0) })
        for theme in themeStore.customThemes {
            // A theme with no attribution is the user's own import — never ours
            // to delete.
            guard let attribution = theme.attribution,
                  attribution.hasPrefix("extension:"),
                  !installed.contains(attribution) else { continue }
            themeStore.delete(id: theme.id)
        }
    }

    /// Writes one parsed theme under its deterministic id, replacing any copy
    /// left by a previous launch, and returns that id.
    ///
    /// `update` rather than `delete`-then-`add`: `ThemeStore.delete` also
    /// clears `activeThemeID`, so deleting the row a relaunch is about to put
    /// back under the same id would silently deselect a theme the user chose.
    /// Replacing in place keeps both the selection and the list order.
    private func store(_ parsed: ColorTheme, label: String, extensionIdentifier: String) -> String {
        var theme = parsed
        theme.id = Self.themeID(extensionIdentifier: extensionIdentifier, label: label)
        theme.isImported = true
        theme.attribution = Self.attribution(for: extensionIdentifier)
        if themeStore.customThemes.contains(where: { $0.id == theme.id }) {
            themeStore.update(theme)
        } else {
            themeStore.add(theme)
        }
        return theme.id
    }
}

/// One theme file that could not be imported, named so the settings panel can
/// show the author the path they have to fix.
///
/// A struct rather than the labelled tuple this started as: the four sibling
/// points all publish structs, and only a struct can conform, gain a field
/// without breaking every destructuring site, or carry these doc comments.
public struct ThemeImportFailure: Sendable, Equatable {
    public let extensionIdentifier: String
    /// The path exactly as the manifest declared it, not the resolved URL: the
    /// declared spelling is what the author edits.
    public let path: String
    public let message: String

    public init(extensionIdentifier: String, path: String, message: String) {
        self.extensionIdentifier = extensionIdentifier
        self.path = path
        self.message = message
    }
}

/// Why a themes contribution was refused wholesale.
public enum ThemeContributionError: LocalizedError, Equatable {
    /// Every theme the manifest declared failed to parse.
    case everyThemeFailed(count: Int)

    public var errorDescription: String? {
        switch self {
        case .everyThemeFailed(let count):
            return "None of the \(count) declared theme\(count == 1 ? "" : "s") could be read."
        }
    }
}

/// `ExtensionRegistry` records a refused contribution as `String(describing:)`,
/// which consults `CustomStringConvertible` and never `LocalizedError` — so
/// without this the settings panel renders the compiler's spelling of the case
/// ("everyThemeFailed(count: 2)") at the extension author it is written for.
extension ThemeContributionError: CustomStringConvertible {
    public var description: String { errorDescription ?? "the themes contribution failed." }
}
