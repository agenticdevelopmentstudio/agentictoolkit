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
