<!-- leaf: implement-extension-host-core-1/extensions-contribution-point · source: extension-host-core-extensions-contribution-point.md -->

**Rules** (cite as `implement-extension-host-core-1/extensions-contribution-point#<slug>`):

- `contribution-key` MUST
- `reference-type-conformance` MUST
- `main-actor-isolation` MUST
- `apply-parameters` MUST
- `apply-directory-is-the-extension-folder` MUST
- `apply-may-throw` MUST
- `apply-contributions-never-absent` MUST
- `apply-called-only-for-enabled-extensions` MUST
- `withdraw-does-not-throw` MUST
- `withdraw-removes-everything-applied` MUST
- `withdraw-safe-on-unapplied-identifier` MUST
- `reload-withdraws-before-reapplying` MUST
- `caller-error-isolation` MUST
- `persisted-state-absence-distinction` MUST
- `extension-contribution-note-identity` MUST
- `extension-contribution-note-sendable` MUST
- `registrations-generic-parameters` MUST
- `registrations-value-type` MUST
- `registrations-not-sendable` MUST
- `identifiers-in-application-order` MUST
- `record-replaces-existing-entry` MUST
- `record-moves-identifier-to-end` MUST
- `notes-in-application-order-unfiltered` MUST
- `payload-lookup-by-identifier` MUST
- `filtered-identifiers-preserve-order` MUST
- `remove-clears-payload-and-its-notes` MUST
- `remove-safe-on-unrecorded-identifier` MUST

# Contribution Point

## Overview

`ContributionPoint.swift` (`packages/apple/AgenticToolkit/Core/Extensions/ContributionPoint.swift`) defines the contract an extension host uses to apply and withdraw one kind of `contributes.*` manifest block — themes, commands, settings, and so on — across every extension that declares it. `ExtensionRegistry` (same directory) holds an array of registered conformers and, for each loaded and enabled extension, calls `apply` on every one of them; on disable or uninstall, and before every full rescan, it calls `withdraw` on every one of them. The file also defines `ExtensionContributionNote`, the shared shape of a compromise note a point records while applying an extension, and `ContributionRegistrations`, the one bookkeeping collection every point whose own state is not itself persisted, user-owned data needs: one payload per applied extension in application order, and the notes those applications produced. The file's own doc comment states this exists because the same bookkeeping — the same struct, the same array, the same remove-all-by-identifier, the same withdraw-before-apply — was written out four separate times before this type existed.

## Behavioral Requirements

- **contribution-key**: A `ContributionPoint` conformer MUST expose `contributionKey: String`, the manifest key it consumes (for example `"themes"`); `ExtensionRegistry` uses this value only for diagnostics and log messages (`ExtensionRegistry.applyContributions`'s error log line), never as a lookup key into the manifest.
- **reference-type-conformance**: `ContributionPoint` MUST be adopted only by a class, because the protocol is constrained to `AnyObject`: `ExtensionRegistry` holds registered points by reference identity, so applying and withdrawing the same extension must reach the same conformer instance.
- **main-actor-isolation**: `ContributionPoint` MUST be `@MainActor`-isolated, because every existing conformer mutates main-actor-isolated state (the theme store, settings panels, the tabs registry).
- **apply-parameters**: `apply(_:from:at:)` MUST accept the extension's decoded `ExtensionManifest.Contributions`, its full `ExtensionManifest`, and the `URL` of the extension's own installed directory.
- **apply-directory-is-the-extension-folder**: The `directory` parameter to `apply(_:from:at:)` MUST be the extension's own installed folder, because manifest-relative paths (`theme.path`, `snippet.path`) resolve against it; a conformer MUST NOT reconstruct this path from any other source.
- **apply-may-throw**: `apply(_:from:at:)` MUST be able to throw an `Error` to report that applying this extension's contribution failed.
- **apply-contributions-never-absent**: The `contributions` parameter `apply(_:from:at:)` receives MUST always be a concrete `ExtensionManifest.Contributions` value, never omitted or `nil`: per `ExtensionRegistry.apply(_:)`, a manifest with no `contributes` key still reaches every point, passed `Contributions.empty` rather than being skipped, so "the extension declares nothing" and "the extension's manifest has no `contributes` key" are the same statement to a conformer.
- **apply-called-only-for-enabled-extensions**: Per this protocol's own doc comment, a host MUST call `apply(_:from:at:)` only for an extension that is enabled — at initial load, and again whenever a previously disabled extension is re-enabled.
- **withdraw-does-not-throw**: `withdraw(extensionIdentifier:)` MUST NOT throw, because withdrawal happens on disable and uninstall, where the protocol's own doc comment states there is nothing useful a caller could do with an error, and a half-withdrawn contribution is worse than a logged one.
- **withdraw-removes-everything-applied**: `withdraw(extensionIdentifier:)` MUST remove everything `apply(_:from:at:)` installed for the given identifier.
- **withdraw-safe-on-unapplied-identifier**: `withdraw(extensionIdentifier:)` MUST be safe to call for an identifier that was never applied, per this protocol's own doc comment.
- **reload-withdraws-before-reapplying**: Per `ExtensionRegistry.apply(_ scan:)`, a full rescan (`loadAll()`) MUST call `withdraw(extensionIdentifier:)` on every registered point for every currently loaded extension before reapplying any of them, even extensions that will be reapplied unchanged in the same pass; a conformer's `withdraw` MUST therefore tolerate being called immediately before a matching `apply` for the same identifier.
- **caller-error-isolation**: Per `ExtensionRegistry.applyContributions(_:from:at:)`, when one conformer's `apply(_:from:at:)` throws, the host MUST log the failure, record it, and continue calling `apply` on the remaining registered points and loading the remaining extensions; one conformer's thrown error MUST NOT prevent another conformer's `apply` from running, and MUST NOT remove the extension from the host's loaded set.
- **persisted-state-absence-distinction**: A `ContributionPoint` conformer whose applied state is persisted, user-owned data — as opposed to in-memory state rebuilt from every extension's manifest at each launch, which this rule exempts — MUST distinguish, while applying a manifest's contributions, "this extension declares nothing of this kind" from "I could not determine what this extension declares," and MUST NOT treat the second as the first: acting on an absence of information as though it were an instruction deletes or orphans the user's persisted data. This is stated in the protocol's own doc comment as a property of the contract itself, citing four prior instances of the conflation (Rulings GO, GS, GV, and I1/I2), all in `ThemeContributionPoint`, the only existing conformer whose state is the user's own persisted `ThemeStore`.
- **extension-contribution-note-identity**: `ExtensionContributionNote` MUST expose `extensionIdentifier: String`, the identifier of the extension whose manifest produced the note.
- **extension-contribution-note-sendable**: Every `ExtensionContributionNote` conformer MUST be `Sendable`, since the protocol itself is declared `Sendable`.
- **registrations-generic-parameters**: `ContributionRegistrations<Payload, Note>` MUST accept any `Payload` type with no constraint, and MUST constrain `Note` to `ExtensionContributionNote`.
- **registrations-value-type**: `ContributionRegistrations` MUST be a `struct` with `mutating` members, not a class, because each `ContributionPoint` conformer holds exactly one instance as private state that only it mutates, and nothing in the file's own doc comment calls for sharing the collection by reference.
- **registrations-not-sendable**: `ContributionRegistrations` MUST NOT conform to `Sendable`, regardless of whether its `Payload` and `Note` type arguments are `Sendable`; the declaration adds no such conformance.
- **identifiers-in-application-order**: `identifiers` MUST return the identifiers with a recorded payload in the order `record(_:notes:for:)` was called for them.
- **record-replaces-existing-entry**: `record(_:notes:for:)` MUST replace, not add to, any payload and notes already recorded for the same identifier, so exactly one payload and one set of notes exist for that identifier afterward.
- **record-moves-identifier-to-end**: When `record(_:notes:for:)` replaces an existing entry, it MUST move that identifier to the end of `identifiers`'s order, because per the file's own doc comment a re-application is the most recent application and keeping its original position would report an order no sequence of events produced.
- **notes-in-application-order-unfiltered**: `notes` MUST return every recorded note across every identifier in application order, with no accessor that pre-filters by identifier; per the file's own doc comment, callers filter by `extensionIdentifier` themselves at display time, and a withdrawal drops only the withdrawn extension's notes.
- **payload-lookup-by-identifier**: `payload(for:)` MUST return the payload most recently recorded for the given identifier, or `nil` if no payload has been recorded for it.
- **filtered-identifiers-preserve-order**: `identifiers(where:)` MUST return the identifiers whose recorded payload satisfies the given predicate, in the same application order as `identifiers`.
- **remove-clears-payload-and-its-notes**: `remove(_:)` MUST remove the given identifier's payload and every note in `notes` whose `extensionIdentifier` equals it, leaving every other identifier's payload and notes unchanged.
- **remove-safe-on-unrecorded-identifier**: `remove(_:)` MUST be safe to call for an identifier with no recorded payload, leaving `identifiers` and `notes` unchanged.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `contributionKey` | `String` | none — required, declared by each conformer | The manifest key this point consumes, e.g. `"themes"`; diagnostics only. |
| `contributions` | `ExtensionManifest.Contributions` | none — required, supplied by the caller to `apply` | The extension's decoded contribution data; `.empty` when its manifest has no `contributes` key. |
| `manifest` | `ExtensionManifest` | none — required, supplied by the caller to `apply` | The extension's full decoded manifest. |
| `directory` | `URL` | none — required, supplied by the caller to `apply` | The extension's own installed folder; manifest-relative paths resolve against it. |
| `extensionIdentifier` | `String` | none — required, supplied by the caller to `withdraw` | The identifier of the extension whose contributions to remove. |
| `Payload` | generic type parameter | none — chosen by the owner of a `ContributionRegistrations` instance | What one applied extension's registration records; unconstrained. |
| `Note` | generic type parameter constrained to `ExtensionContributionNote` | none — chosen by the owner | The note type this registration collection keeps alongside each payload. |

