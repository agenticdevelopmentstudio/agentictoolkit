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

        // Applying is what decides which of this extension's themes failed, so
        // the previous answer is discarded rather than added to: apply twice —
        // a reload, a disable/enable — and the settings panel would otherwise
        // list one broken file twice. Every other point in this subsystem says
        // the same thing in its own words; this one is the outlier being
        // brought into line.
        //
        // **Not `withdraw(extensionIdentifier:)`, which is how the other four
        // do it.** This point's state is the *user's*: `withdraw` deletes their
        // persisted themes and `delete(id:)` clears `activeThemeID` with them,
        // so opening `apply` with a withdrawal would re-run the F7
        // delete-then-re-add on every single launch — the churn `store`'s
        // `update`-in-place exists to prevent. The clear is narrowed to the
        // diagnostics, which are the only thing here this class owns.
        importFailures.removeAll { $0.extensionIdentifier == identifier }

        // No `themes.isEmpty` early return. An update that drops the key
        // declares *nothing*, which is not the same as having nothing to say:
        // the reconciliation below is exactly what has to run, and returning
        // above it orphaned every theme the extension ever contributed, with no
        // route out but uninstalling it (`pruneOrphans` cannot see them — the
        // extension is still installed). The empty case falls through: the loop
        // runs zero times, GO's throw is conditioned below, and `declared` is
        // empty so reconciliation deletes them all. Which is the right answer.

        var imported = 0
        var written: Set<String> = []
        for theme in contributions.themes {
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
                // `ExtensionResourcePath` owns both halves of resolving a
                // declared path: the is-directory base — `directory` arrives
                // from the registry and may carry no is-directory flag, which
                // makes `relativeTo:` resolve against its *parent* and read
                // every theme one level too high — and the symlink-resolving
                // containment check that refuses `../../../secret.json`. The
                // snippets point and the host's entry point resolve theirs
                // through the same function.
                let url = try ExtensionResourcePath.resolve(theme.path, inside: directory)
                let parsed = try VSCodeThemeImporter.parse(
                    contentsOf: url,
                    label: theme.label,
                    uiTheme: theme.uiTheme,
                    // The extension's whole folder, not the theme file's own:
                    // an `include` is legitimately written `../base.json` from
                    // inside `themes/`, and may go no further.
                    containedIn: directory
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
        //
        // Conditioned on something having been declared, rather than moving the
        // guard back above the loop: Ruling GO's sentence is "everything this
        // extension declared failed", and an extension that declared nothing
        // has not failed at anything. Keeping the throw where it is keeps GO
        // literally true and lets the empty case reach the reconciliation.
        if imported == 0 && !contributions.themes.isEmpty {
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
    ///
    /// - Parameter installedIdentifiers: every identifier the scan
    ///   established, or `nil` when it could not establish them all — in
    ///   which case nothing is pruned at all.
    ///
    /// **The Optional is the safety property, not a convenience** (I1/I2, and
    /// the persisted-state invariant on `ContributionPoint`). "Nothing is
    /// installed" and "I do not know what is installed" have to behave
    /// oppositely here — the first is an instruction to delete every
    /// contributed theme, the second is an absence of information — and
    /// while both spelled `Set<String>()` a single unreadable `package.json`
    /// anywhere in a search path deleted the themes of every extension
    /// beside it, permanently, with all their folders still on disk.
    public func pruneOrphans(installedIdentifiers: Set<String>?) {
        // Not `?? []`: an incomplete scan is no evidence about anyone, so the
        // themes stay exactly where they are until a launch that can name
        // every directory it looked at.
        guard let installedIdentifiers else { return }
        // Compared exactly, not case-folded, and that is deliberate. Every
        // producer of an attribution and every member of this set now comes
        // from `ExtensionManifest.identifier`, which case-folds (F39), so in a
        // consistent store folding here would be a no-op. Where it is *not* a
        // no-op is a store written before the folding — `extension:Ms-Python.Foo`
        // beside the freshly written `extension:ms-python.foo` — and there the
        // exact comparison is the one that heals: the stale row names an
        // extension identifier that no longer exists in any spelling, so it is
        // an orphan, and pruning it is how the duplicate goes away instead of
        // sitting in the user's theme list forever.
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
