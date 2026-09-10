//
//  ContributionPoint.swift
//  AgenticToolkit
//

import Foundation

/// One kind of `contributes.*` block an extension can populate — themes,
/// commands, settings, and so on, one conformer per kind (Tasks 4.4-4.6).
///
/// This is not `MenuContribution` (`apple-macos`,
/// `macOS/UI/AppShell/MenuContribution.swift`): that is a declarative struct
/// describing a single menu item, collected into arrays and consumed
/// wholesale by `MenuManager`. A `ContributionPoint` is the opposite shape —
/// one long-lived object per contribution *kind* that knows how to apply and
/// withdraw an *extension's* worth of that kind, across every extension that
/// declares it.
///
/// `@MainActor` because every implementer in Tasks 4.4-4.6 touches
/// main-actor state (the theme store, settings panels, the tabs registry).
/// `AnyObject` because `ExtensionRegistry` holds these by identity: applying
/// and withdrawing the same extension must reach the same conformer.
///
/// **A point that writes to persisted, user-owned state must distinguish
/// "the extension declares nothing" from "I could not read what it
/// declares"** (Ruling GX). The first is an instruction; the second is an
/// absence of information, and acting on it deletes the user's data. A point
/// whose state is in-memory and rebuilt from the manifests each launch is
/// exempt, because a wrong answer there costs a session rather than data.
///
/// This is a property of the contract rather than advice about one method,
/// and it is written here because the same mistake has now been found four
/// times — every time in `ThemeContributionPoint`, the only conformer whose
/// state is persisted and the user's:
///
/// - **Ruling GO** — every declared theme file failing to open was read as
///   "this extension has no themes", so one broken file took the previous
///   launch's working copies with it.
/// - **Ruling GS** — reconciliation ran against the ids that happened to
///   load *this* call rather than the ones the manifest *declares*, so a
///   file that broke on relaunch deleted the working copy of that same
///   theme, and `activeThemeID` with it.
/// - **Ruling GV** — a manifest with no `contributes` key skipped every
///   point instead of being handed `Contributions.empty`, so an update that
///   dropped the key orphaned its themes with no route out but uninstalling
///   the extension.
/// - **I1/I2** — `pruneOrphans` was handed the identifiers that *decoded*,
///   so an extension whose manifest stopped parsing — or one merely
///   incompatible with this host, which is not an error at all — lost every
///   theme with its folder still on disk. Hence
///   `ThemeContributionPoint.pruneOrphans(installedIdentifiers:)` takes an
///   Optional and prunes nothing when the scan could not name everyone.
///
/// A future point that persisted the user's keymap, or cached snippets to
/// disk, would inherit all four on its first day.
@MainActor
public protocol ContributionPoint: AnyObject {
    /// The manifest key this point consumes, e.g. "themes". Used only for
    /// diagnostics and to make the registry's logging legible.
    var contributionKey: String { get }

    /// Apply this extension's contributions. Called when an enabled extension
    /// loads, and when a disabled extension is re-enabled.
    ///
    /// `directory` is the extension's own folder — paths in the manifest
    /// (`theme.path`, `snippet.path`) are relative to it, and an implementer
    /// that had to reconstruct that path would get it wrong.
    func apply(
        _ contributions: ExtensionManifest.Contributions,
        from manifest: ExtensionManifest,
        at directory: URL
    ) throws

    /// Remove everything `apply` installed for this identifier. Must be safe
    /// to call for an identifier that was never applied.
    ///
    /// Does not throw: withdrawal happens on disable and uninstall, where
    /// there is nothing useful a caller could do with an error, and a
    /// half-withdrawn contribution is worse than a logged one.
    func withdraw(extensionIdentifier: String)
}
