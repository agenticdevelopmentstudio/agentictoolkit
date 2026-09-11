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
/// absence of information, and acting on it deletes the user's data — while
/// failing to act on the first, reading a real "nothing" as though it were an
/// absence of information, orphans that data instead. Both directions cost the
/// user; only the conflation is common to them. A point
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

/// One compromise a contribution point had to make while applying an
/// extension, written down instead of thrown.
///
/// Every point that keeps notes keys them the same way — by the extension that
/// caused them — because that is the only question anything asks of the
/// collection: the Extensions UI filters by identifier at display time, and a
/// withdrawal drops the withdrawn extension's notes and nobody else's. This
/// protocol is that one shared requirement, and it is all
/// `ContributionRegistrations` needs to know about a note to keep the two
/// collections in step.
public protocol ExtensionContributionNote: Sendable {
    /// The extension whose manifest produced this note.
    var extensionIdentifier: String { get }
}

/// What a contribution point remembers between `apply` and `withdraw`: one
/// payload per applied extension, in application order, and the notes those
/// applications produced.
///
/// Every point whose state is its own — as opposed to `ThemeContributionPoint`,
/// whose state is the user's `ThemeStore` on disk and which reconciles rather
/// than re-registers — needs exactly this, and before this type existed each
/// wrote it out again: the same `Registration` struct, the same array, the same
/// remove-all-by-identifier in `withdraw`, the same withdraw-before-apply.
/// Four copies of a rule is four places to fix it (`dry`), and the rule here is
/// one the extension subsystem has already been burned by — see the rulings
/// above.
///
/// An array rather than a dictionary, deliberately and in both halves:
/// application order is the only order these have, and it is an order callers
/// report — `contributingExtensions` is specified in it, and so is the notes
/// list a person reads. A dictionary has none to give back.
///
/// A value type with `mutating` members rather than a class: a point holds one
/// of these as private state it alone mutates, and nothing benefits from being
/// able to hand the collection around as a shared reference.
public struct ContributionRegistrations<Payload, Note: ExtensionContributionNote> {

    private struct Registration {
        let identifier: String
        let payload: Payload
    }

    private var registrations: [Registration] = []

    /// Every note recorded across every applied extension, in application
    /// order. Callers filter by identifier at display time, which is why
    /// there is no pre-filtered accessor.
    public private(set) var notes: [Note] = []

    public init() {}

    /// The extensions with a payload recorded, in application order.
    public var identifiers: [String] { registrations.map(\.identifier) }

    /// What was recorded for this extension, or `nil` if nothing was.
    public func payload(for identifier: String) -> Payload? {
        registrations.first { $0.identifier == identifier }?.payload
    }

    /// The extensions whose payload satisfies `predicate`, in application
    /// order — for the callers that publish a *useful* subset, such as "has at
    /// least one settings section to show".
    public func identifiers(where predicate: (Payload) -> Bool) -> [String] {
        registrations.filter { predicate($0.payload) }.map(\.identifier)
    }

    /// Records this extension's payload and notes, replacing anything already
    /// recorded for it.
    ///
    /// The replacement is what makes re-applying idempotent (`idempotency`):
    /// a reload or a disable/enable must leave one payload and one copy of
    /// each note, and a point that forgot to withdraw first would otherwise
    /// accumulate both. Callers still withdraw first when withdrawal means
    /// more than forgetting — unregistering a view from the tabs registry, say
    /// — but they no longer have to do it for this collection's sake.
    ///
    /// Re-recording moves the extension to the end of the order, because a
    /// re-application *is* the most recent application; keeping its original
    /// position would report an order no sequence of events produced.
    public mutating func record(_ payload: Payload, notes newNotes: [Note], for identifier: String) {
        remove(identifier)
        registrations.append(Registration(identifier: identifier, payload: payload))
        notes.append(contentsOf: newNotes)
    }

    /// Forgets this extension's payload and its notes. Safe for an identifier
    /// that was never recorded, because withdrawal is called on disable and
    /// uninstall for points that may never have applied it.
    public mutating func remove(_ identifier: String) {
        registrations.removeAll { $0.identifier == identifier }
        notes.removeAll { $0.extensionIdentifier == identifier }
    }
}
