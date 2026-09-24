---
id: 088ed758-8c79-443d-999f-425c69df4d4d
title: Contribution Point
domain: agentictoolkit://recipes/extension-host-core-extensions-contribution-point
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Protocol and bookkeeping struct an extension host uses to apply and withdraw
  one kind of contributes.* block across every loaded extension.
platforms:
- swift
- macos
tags:
- extensions
- contribution-point
- registry
- protocol
- mainactor
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a protocol and a bookkeeping value type for the extension host's contribution system, not a visual component.

## States

Not applicable — this is a protocol and a bookkeeping value type for the extension host's contribution system, not a visual component. The applied-or-withdrawn lifecycle of an extension's contribution is covered under Behavioral Requirements, not as a visual-state table.

## Accessibility

Not applicable — this is a protocol and a bookkeeping value type for the extension host's contribution system, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| contribution-point-001 | identifiers-in-application-order, notes-in-application-order-unfiltered, payload-lookup-by-identifier | `record(1, notes: [note("a","a.one")], for: "a")`, then `record(2, notes: [note("b","b.one")], for: "b")`, then `record(3, notes: [], for: "c")` (traced to `ContributionRegistrationsTests.applicationOrderIsReported`) | `identifiers == ["a", "b", "c"]`; `payload(for: "b") == 2`; `notes.map(\.viewID) == ["a.one", "b.one"]` |
| contribution-point-002 | payload-lookup-by-identifier, remove-safe-on-unrecorded-identifier | `record(1, notes: [note("a","a.one")], for: "a")`, then `payload(for: "absent")`, then `remove("absent")` (traced to `ContributionRegistrationsTests.anUnknownIdentifierIsInert`) | `payload(for: "absent") == nil`; after `remove("absent")`, `identifiers == ["a"]` and `notes.count == 1` |
| contribution-point-003 | record-replaces-existing-entry, record-moves-identifier-to-end | `record(1, notes: [note("a","a.one")], for: "a")`, `record(2, notes: [note("b","b.one")], for: "b")`, then `record(10, notes: [note("a","a.two")], for: "a")` (traced to `ContributionRegistrationsTests.recordingTwiceReplaces`) | `identifiers == ["b", "a"]`; `payload(for: "a") == 10`; `notes.map(\.viewID) == ["b.one", "a.two"]` |
| contribution-point-004 | remove-clears-payload-and-its-notes | `record(1, notes: [note("a","a.one"), note("a","a.two")], for: "a")`, `record(2, notes: [note("b","b.one")], for: "b")`, then `remove("a")` (traced to `ContributionRegistrationsTests.removalIsPerExtension`) | `identifiers == ["b"]`; `payload(for: "a") == nil`; `notes.map(\.viewID) == ["b.one"]` |
| contribution-point-005 | filtered-identifiers-preserve-order | `record(index, notes: [], for: identifier)` for `("a","b","c","d")` at indices `(0,1,2,3)`, then `identifiers(where: { $0.isMultiple(of: 2) })` (traced to `ContributionRegistrationsTests.filteringKeepsOrder`) | Returns `["a", "c"]` |

## Edge Cases

- **Empty `notes` array on `record`**: `record(_:notes:for:)` MUST accept an empty `notes` array (`contribution-point-001`'s third call, for identifier `"c"`), recording a payload with zero notes.
- **A manifest with no `contributes` key**: `apply(_:from:at:)`'s `contributions` parameter MUST be `Contributions.empty` in this case, never omitted (apply-contributions-never-absent); a conformer MUST treat this identically to a manifest whose `contributes` key is present but names nothing for this point's `contributionKey`.
- **Concurrent access**: `ContributionPoint` and `ContributionRegistrations` are single-threaded in effect: every conformer is `@MainActor`-isolated (main-actor-isolation), and `ContributionRegistrations` is not `Sendable` (registrations-not-sendable), so the compiler prevents a second, concurrently-running task from holding or mutating the same instance; all mutation is serialized onto the main actor.
- **Withdraw immediately followed by re-apply of the same identifier**: on a full rescan, `ExtensionRegistry` withdraws every currently loaded extension from every point before reapplying any of them (reload-withdraws-before-reapplying), so a conformer MUST be able to withdraw an identifier it is about to immediately reapply without leaving stale state behind; `ContributionRegistrations.record`'s replace-not-add behavior (record-replaces-existing-entry) is what makes this safe for the shared bookkeeping type.
- **Error states — a conformer's `apply` throws partway through applying an extension**: `ContributionPoint.apply(_:from:at:)`'s doc comment states only that it MAY throw; it does not state whether a conformer MUST leave its own state unchanged when it throws (an atomic apply) or MAY leave a partial application in place. `ExtensionRegistry.applyContributions(_:from:at:)` catches the thrown error, logs it, and records an `ExtensionLoadFailure`, but calls no compensating `withdraw(extensionIdentifier:)` on the point that threw, so a conformer that mutated its own state before throwing leaves that partial state in place with no automatic cleanup. The contract does not require `apply` to be atomic, so a port MUST NOT assume a failed `apply` left the point unchanged.
- **Offline or disconnected state**: Not applicable — `ContributionPoint.swift` performs no network access of its own; any conformer that reads network state is a separate file's concern, outside this contract.
- **A missing file or an unreachable server**: Not applicable at this layer for the same reason — this file defines the contract only; a conformer that reads files (for example theme files) handles that failure itself, and this file imposes no requirement on how.
- **Duplicate `contributionKey` across two registered points**: not validated anywhere in this file or in `ExtensionRegistry.register(_:)`; per contribution-key, `contributionKey` is used only for diagnostics, so a collision would only make a log line ambiguous — it would not misroute a contribution, since each point receives the full `Contributions` value directly rather than a `contributionKey`-keyed lookup.

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

## Deep Linking

Not applicable: `ContributionPoint.swift` defines no URL routing, navigation, or scheme handling.

## Localization

Not applicable: `ContributionPoint.swift` defines no user-facing string of its own; every string it carries (`contributionKey`, `extensionIdentifier`) is a manifest-derived key or identifier, not display text.

## Accessibility Options

Not applicable: this file has no UI of its own, so it responds to no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: `ContributionPoint.swift` declares no feature-flag key and contains no conditional feature-gating logic.

## Analytics

Not applicable: `ContributionPoint.swift` contains no analytics or event-emission call.

## Privacy

- **Data collected**: This file carries only extension identifiers and diagnostic keys (`contributionKey`, `extensionIdentifier`); it defines no field for a credential, token, or other user-sensitive value.
- **Storage**: `ContributionPoint.swift` itself performs no storage; `ContributionRegistrations` holds its payload and notes only in memory for as long as the owning conformer keeps it. A conformer whose payload is itself persisted, user-owned state is bound by persisted-state-absence-distinction, but that persistence mechanism lives in the conformer, not in this file.
- **Transmission**: Not applicable — this file contains no networking code.
- **Retention**: Not applicable at this layer — `ContributionRegistrations`' in-memory entries live only as long as the owning conformer keeps them, and are replaced or removed by `record`/`remove` (record-replaces-existing-entry, remove-clears-payload-and-its-notes); this file defines no retention policy beyond that.

## Logging

Not applicable: `ContributionPoint.swift` contains no `os_log`, `Logger`, `print`, or other logging call; the one log line quoted under contribution-key (`Contribution point '...' failed to apply '...'`) is emitted by `ExtensionRegistry.applyContributions(_:from:at:)`, a different file.

## Platform Notes

- **AppKit / UIKit**: this is the source. The file is `packages/apple/AgenticToolkit/Core/Extensions/ContributionPoint.swift`, part of the `AgenticToolkitCore` framework target, which `project.yml` declares `platform: macOS`. The registry that drives it, `ExtensionRegistry.swift`, lives in the same directory and target. Every conformer today (`ThemeContributionPoint`, `ConfigurationContributionPoint`, `LanguageContributionPoint`, `ViewsContributionPoint`) lives one level up, under `macOS/Features/Extensions/`.
- **SwiftUI**: no SwiftUI dependency exists in this file. A SwiftUI-backed conformer would still need to be a `@MainActor`-isolated class per reference-type-conformance and main-actor-isolation; its `ContributionRegistrations` state would typically back an `@Published`/`@Observable` property on that class rather than being exposed directly, since the struct itself has no observation mechanism.
- **Compose**: a Kotlin port would model `ContributionPoint` as an `interface` whose implementers are confined to a single coroutine dispatcher (mirroring main-actor-isolation) rather than declared `@MainActor`, since Kotlin has no actor-isolated type system; `withdraw` stays non-throwing (`Unit`, not a `Result`), and `apply` becomes a function that can throw or return a `Result` failure. `ContributionRegistrations<Payload, Note>` becomes a generic class or data class wrapping a `MutableList<Registration<Payload>>` and a `MutableList<Note>`, since Kotlin has no direct `struct`-with-`mutating`-methods equivalent; callers must copy defensively if value semantics matter.
- **React/Web**: a TypeScript port has no actor isolation to enforce (reference-type-conformance and main-actor-isolation have no direct analogue), so a port would instead document that every `ContributionPoint` implementation and every call into a shared `ContributionRegistrations` instance must run on the same JavaScript event-loop turn/task queue it always does, and any asynchronous `apply` must not interleave state mutation with another call. `ContributionRegistrations` becomes a plain class over two arrays (`registrations`, `notes`) with the same replace-on-`record`, filter-on-`remove` semantics (record-replaces-existing-entry, remove-clears-payload-and-its-notes).
- **WinUI 3**: a .NET port would model `ContributionPoint` as an interface (`IContributionPoint`) with `Apply(Contributions, ExtensionManifest, string directoryPath)` (throwing an exception is the direct analogue of `apply-may-throw`) and `Withdraw(string extensionIdentifier)` (returning `void`, mirroring withdraw-does-not-throw). Because WinUI 3/`Windows App SDK` has no compile-time actor isolation, main-actor-isolation would instead be enforced by requiring every call to originate on the UI thread (`DispatcherQueue`), typically asserted with `Debug.Assert(DispatcherQueue.HasThreadAccess)` at the top of each implementation, since nothing else stops a background `Task` from calling in. `ContributionRegistrations<TPayload, TNote>` ports as a `sealed class` wrapping two `List<T>` fields (`List<(string Identifier, TPayload Payload)>` and `List<TNote>`) with `Record`, `Remove`, `Payload`, and `Identifiers`/`IdentifiersWhere` methods reproducing record-moves-identifier-to-end's move-to-end-on-replace behavior explicitly, since `List<T>.RemoveAll` followed by `Add` is the direct translation of `remove` followed by `append` in the Swift source. `INotifyPropertyChanged` is not needed on the collection itself, matching registrations-not-sendable's intent that this is private bookkeeping, not a bindable view-model property.

## Design Decisions

**Decision**: `ContributionPoint` is constrained to `AnyObject` and isolated to `@MainActor`.
**Rationale**: `ExtensionRegistry` holds registered points by reference identity — the same instance that applies an extension's contributions must be the one asked to withdraw them — which only a class can guarantee under Swift's value semantics; `@MainActor` follows because every implementer written so far touches main-actor state (the theme store, settings panels, the tabs registry).
**Approved**: pending

**Decision**: `ContributionRegistrations.record(_:notes:for:)` replaces an existing entry in place and moves the identifier to the end of the reported order, rather than merging the new payload into the identifier's original position.
**Rationale**: per the file's own doc comment, a re-application is the most recent application, and keeping the identifier's original position would report an order no real sequence of events produced; this also makes reload-withdraws-before-reapplying safe, since a rescan's withdraw-then-reapply of an unchanged extension still leaves exactly one entry, now at the end.
**Approved**: pending

**Decision**: both `registrations` and `notes` inside `ContributionRegistrations` are arrays, not dictionaries, even though lookup by identifier is a common operation.
**Rationale**: per the file's own doc comment, application order is the only order either collection has, and it is an order callers report back — `identifiers` is specified in it, and so is the notes list a person reads in the Extensions UI; a dictionary has no order to give back, so it cannot satisfy identifiers-in-application-order or notes-in-application-order-unfiltered.
**Approved**: pending

**Decision**: the persisted-state-absence-distinction rule is written into `ContributionPoint`'s own doc comment as a property of the contract, rather than left to each conformer to rediscover.
**Rationale**: the doc comment cites four separate prior defects (Rulings GO, GS, GV, and I1/I2), all in `ThemeContributionPoint`, that trace back to the same conflation — reading "I could not determine what this extension declares" as "this extension declares nothing" — each time deleting or orphaning a user's persisted theme. The rule is scoped to conformers whose applied state is itself persisted and user-owned; a conformer whose state is rebuilt from the manifests at every launch is explicitly exempt, because a wrong answer there costs a session, not data.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |

`separation-of-concerns` passes because `ContributionPoint.swift` performs no I/O, persistence, or networking of its own — it defines only the contract, the note protocol, and a pure in-memory bookkeeping struct; every conformer owns its own side effects. `idempotent-operations` passes because `record` replaces rather than accumulates (record-replaces-existing-entry), and `withdraw` and `remove` are both documented and tested safe to call on an identifier with nothing recorded (withdraw-safe-on-unapplied-identifier, remove-safe-on-unrecorded-identifier). `unit-test-coverage` is `partial`: `ContributionRegistrationsTests.swift` exhaustively covers `ContributionRegistrations` itself, but the `ContributionPoint` protocol's own contractual requirements — `apply-called-only-for-enabled-extensions`, `caller-error-isolation`, `reload-withdraws-before-reapplying`, and persisted-state-absence-distinction — are exercised only indirectly, through each conformer's own test suite (for example `ThemeContributionPointTests.swift`), never against the protocol's contract directly. `data-integrity` is `partial`: persisted-state-absence-distinction is documented as a MUST in the protocol's doc comment, but nothing in `ContributionPoint.swift` enforces it on a conformer — a non-atomic `apply` that throws partway (no compensating `withdraw` follows) is one further way a conformer's own state can drift from what the contract describes.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
