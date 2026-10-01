---
id: 236659d0-ee7d-45c9-8986-181f027a4058
title: Contributed Views
domain: agentictoolkit://cookbook/workspace/extensions/manifest/contributed-views
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Turns a decoded extension manifest's contributes.views and contributes.viewsContainers
  into sorted, notes-carrying registry data, resolving codicon names to this host's
  icon symbols without opening any file.
platforms:
- swift
- macos
tags:
- extensions
- contributed-views
- view-containers
- manifest-parsing
- icon-mapping
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# Contributed Views

## Overview

This component defines the data this host keeps for a VS Code extension's `contributes.views` and `contributes.viewsContainers` manifest entries, and the pure, stateless function that produces them from an already-decoded set of manifest contributions. Nothing here renders anything: a container record is recorded but never drawn, because nothing in this host resolves a container yet (Ruling FD). A view record is resolved as far as a host without a real VS Code extension host can resolve it — its icon is turned into a symbol name where a mapping exists, its target container decides one Boolean (`preferredAxisIsVertical`), and everything this host cannot honor exactly (an unevaluated `when` clause, an icon with no symbol equivalent, a field the decoder could not read, a repeated view id, a container-less target) is recorded as a note rather than silently dropped or thrown. The codicon-to-symbol table is the fixed, hand-built table this component consults to answer the icon question; it is a lookup table, not a transformation, because the two icon vocabularies (VS Code codicons and this host's icon symbols) have no algorithmic relationship.

## Behavioral Requirements

- **contributed-view-container-shape**: a container record MUST be an immutable, comparable value carrying `extensionIdentifier`, `location` (the `viewsContainers` key the entry was declared under, e.g. `activitybar`, `panel`), `containerID`, `title`, an optional `icon` (the declared value, raw and unresolved), and an optional `when` (the declared clause, raw and unevaluated).
- **contributed-view-shape**: a view record MUST be an immutable, comparable value carrying `extensionIdentifier`, `viewID` (the raw VS Code view id), `registryID`, `targetContainerID`, `name`, `kind`, an optional `symbolName`, an optional `iconPath`, an optional `when`, an optional `visibility`, an optional `initialSize`, and `preferredAxisIsVertical`.
- **view-kind-enum**: a view's kind MUST be exactly one of two cases, tree or webview.
- **contributed-view-note-shape**: a note MUST be a comparable value carrying `extensionIdentifier`, `viewID`, `kind`, and a human-readable `detail` sentence.
- **note-kind-enum**: a note's kind MUST be one of exactly six cases: `whenNotEvaluated`, `unmappedIcon`, `fileIcon`, `unknownContainer`, `duplicateViewID`, `malformedField`.
- **build-is-pure**: building views from a manifest's contributions MUST be a pure function of its two inputs: it MUST perform no file I/O, no network access, and no logging, and it MUST NOT open, read, or otherwise resolve any extension-bundled image file even when a declared icon names one.
- **registry-id-format**: a view's `registryID` MUST equal the literal concatenation `"extension." + <the manifest's identifier> + "." + <the declared id>`, so two different extensions declaring the identical `viewID` produce the same `viewID` but different `registryID` values, and one extension's `viewID` is always the same string as the corresponding VS Code `views` entry's own `id`.
- **containers-sort-order**: the returned containers list MUST be sorted by `location` (ascending), then by each container's index within its own `viewsContainers` array as the manifest declared it — never by `containerID` — so a location's containers keep the order the manifest author wrote them in while the (unordered) collection of locations is made deterministic by the location-name sort.
- **views-sort-order**: the returned views list MUST be sorted by `targetContainerID` (ascending), then by each view's index within its own `views` array as the manifest declared it — never by `viewID` — following the same rule as `containers-sort-order` for the same reason.
- **container-id-first-wins-for-axis**: when two or more `viewsContainers` entries across different locations declare the same `containerID`, only the first one encountered while iterating the already-sorted containers list MUST be used to resolve that `containerID`'s location for axis purposes (`known-target-rule`, `axis-rule`); later same-id declarations MUST NOT overwrite it and MUST NOT produce any note.
- **containers-not-deduplicated**: unlike the location resolution in `container-id-first-wins-for-axis`, the containers list itself MUST include every declared container record, including two or more entries that share the same `containerID` across different locations; this component MUST NOT deduplicate or drop any container entry.
- **duplicate-view-id-first-wins**: when the same extension's manifest declares the same view `id` more than once — whether within one target's array or across two or more different targets — only the first entry in `views-sort-order`'s order MUST be registered as a view record; every subsequent entry sharing that `id` MUST be dropped (never appended to the views list) and MUST produce exactly one `duplicateViewID` note naming the `viewID` and the target container that won.
- **dropped-duplicate-suppresses-its-own-notes**: a dropped duplicate entry (per `duplicate-view-id-first-wins`) MUST NOT produce a `whenNotEvaluated`, `unmappedIcon`, `fileIcon`, or `malformedField` note of its own even when its declaration would otherwise trigger one; only the `duplicateViewID` note MUST be produced for it.
- **view-kind-default**: a view's kind MUST be tree whenever the declared `type` is absent or is any string other than the literal `"webview"`, and MUST be webview only when the declared `type` is exactly `"webview"`; neither outcome MUST produce a note.
- **icon-blank-input**: when the declared `icon`, after trimming leading and trailing whitespace and newline characters, is an empty string, `symbolName` and `iconPath` MUST both be absent and no note MUST be produced.
- **icon-codicon-form**: a trimmed, non-empty `icon` value that begins with `"$("` and ends with `")"` MUST be treated as a codicon reference rather than a file path.
- **icon-codicon-animation-modifier-stripped**: within a codicon reference, any suffix after a `~` character (e.g. the `~spin` in `$(sync~spin)`) MUST be removed before the codicon name is looked up, so `$(sync~spin)` and `$(sync)` MUST resolve to the identical `symbolName`.
- **icon-codicon-empty-name**: when a codicon reference's inner name is empty after the animation-modifier strip (e.g. the literal `"$()"`), `symbolName` and `iconPath` MUST both be absent and no note MUST be produced.
- **icon-codicon-mapped**: when a codicon reference's name (after the animation-modifier strip) is a key in the codicon-to-symbol table, `symbolName` MUST be set to that key's mapped value, `iconPath` MUST be absent, and no note MUST be produced.
- **icon-codicon-unmapped**: when a codicon reference's name is not a key in the codicon-to-symbol table, `symbolName` and `iconPath` MUST both be absent, and exactly one `unmappedIcon` note naming the codicon MUST be produced.
- **icon-file-path-form**: a trimmed, non-empty `icon` value that does not have both the `"$("` prefix and the `")"` suffix MUST be treated as a file path: `iconPath` MUST be set to the trimmed string, `symbolName` MUST be absent, and exactly one `fileIcon` note naming the path MUST be produced.
- **when-stored-not-evaluated**: a declared `when` clause MUST be copied verbatim into the built view record's `when` (or, for a container record, its own `when`), and the view or container MUST be built and registered regardless of the clause's content; this component MUST NOT parse or evaluate the clause.
- **when-present-note**: when a view's declared `when` clause is present and non-empty, exactly one `whenNotEvaluated` note carrying the clause's literal text MUST be produced; an absent or empty `when` clause MUST NOT produce this note. A container record's `when` carries the same raw value but produces no equivalent note, because nothing in this host resolves containers yet (Ruling FD).
- **unreadable-key-note-per-key**: for every key name present in a declared view's set of unreadable keys, exactly one `malformedField` note naming that key MUST be produced, and the view MUST still be built without a value for that field; a key that was absent from the manifest, or explicitly declared `null`, MUST NOT appear in that set and MUST NOT produce a note.
- **known-target-rule**: a view's `targetContainerID` MUST be treated as known when it matches either a `containerID` declared anywhere in the manifest's own `viewsContainers` (subject to `container-id-first-wins-for-axis`) or one of the fixed built-in ids `"explorer"`, `"scm"`, `"debug"`, `"test"`, `"remote"`, `"panel"`; every other `targetContainerID` MUST be treated as unknown.
- **unknown-container-note**: when a view's `targetContainerID` is unknown (per `known-target-rule`), exactly one `unknownContainer` note naming the target MUST be produced, and the view MUST still be built, registered, and given `preferredAxisIsVertical == false`.
- **axis-rule**: `preferredAxisIsVertical` MUST be `true` if and only if the target is known (per `known-target-rule`) and its resolved location — the self-declared container's `location` when one was found, otherwise the target id itself for a built-in target — equals the literal string `"panel"`; it MUST be `false` for every other known target and for every unknown target.
- **codicon-table-fixed**: the codicon-to-symbol table MUST be a fixed mapping consulted by exact-match key lookup only (no case-folding, no partial matching); looking up a symbol for a codicon MUST return no result for any name that is not a key in the table.
- **thread-safe-value-types**: a container record, a view record, and a note MUST each be immutable, comparable values safe to pass across any concurrency boundary with no additional synchronization.
- **builder-isolation-free**: the component that builds views MUST carry no concurrency-isolation restriction and no stored instance state; building views MUST be callable synchronously from any context, because every parameter and return value is safe to share across threads and the function touches no shared mutable state.
- **container-notes-none**: building the containers list MUST NOT produce any note for a container entry — not for a missing icon, not for a repeated `containerID`, and not for a `when` clause — because nothing in this host currently reads, renders, or resolves a container (Ruling FD); every note this component produces is keyed to a view.

## Appearance

Not applicable — this is a manifest-to-registry data builder, not a visual component.

## States

Not applicable — this is a manifest-to-registry data builder, not a visual component.

## Accessibility

Not applicable — this is a manifest-to-registry data builder, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| contributed-views-001 | registry-id-format | Two manifests, publishers `llvm` and `fork`, each declaring `{ "id": "clangd.ast", "name": "AST" }` under the same extension name | Both views' `viewID` equal `"clangd.ast"`; `registryID` equals `"extension.llvm.sample.clangd.ast"` for the first and `"extension.fork.sample.clangd.ast"` for the second — different from each other |
| contributed-views-002 | view-kind-default | `{ "explorer": [{ "id": "acme.tree", "name": "Tree" }] }`, no `type` key | The first view's kind is tree; the notes list is empty |
| contributed-views-003 | view-kind-default | `{ "explorer": [{ "id": "acme.web", "name": "Web", "type": "webview" }] }` | The first view's kind is webview; the notes list is empty |
| contributed-views-004 | icon-codicon-form, icon-codicon-mapped | `{ "id": "acme.find", "name": "Find", "icon": "$(search)" }` | `symbolName` is `"magnifyingglass"`; `iconPath` is absent; no `unmappedIcon` or `fileIcon` note is produced |
| contributed-views-005 | icon-codicon-animation-modifier-stripped | `{ "id": "acme.spin", "name": "Spin", "icon": "$(search~spin)" }` | `symbolName` is `"magnifyingglass"`; no `unmappedIcon` note is produced |
| contributed-views-006 | icon-blank-input, icon-codicon-empty-name | Two entries, one with `"icon": "  "` and one with `"icon": "$()"` | Both: `symbolName` and `iconPath` are absent, and no note is produced for either entry |
| contributed-views-007 | icon-codicon-unmapped | `{ "id": "acme.graph", "name": "Graph", "icon": "$(gitlens-graph)" }` | `symbolName` is absent; exactly one `unmappedIcon` note whose `viewID` is `"acme.graph"` and whose `detail` contains `"gitlens-graph"` |
| contributed-views-008 | icon-file-path-form | `{ "id": "acme.pic", "name": "Pic", "icon": "resources/tree.svg" }` | `symbolName` is absent; `iconPath` is `"resources/tree.svg"`; exactly one `fileIcon` note whose `detail` contains `"resources/tree.svg"` |
| contributed-views-009 | when-stored-not-evaluated, when-present-note | `{ "id": "acme.cond", "name": "Cond", "when": "resourceScheme == file" }` | The built view's `when` is `"resourceScheme == file"`; exactly one `whenNotEvaluated` note whose `detail` contains `"resourceScheme == file"`; the view is still present in the views list |
| contributed-views-010 | axis-rule, known-target-rule | Containers `{ "panel": [{ "id": "acme.strip", ... }], "activitybar": [{ "id": "acme.side", ... }] }`; one view targeting each of `acme.strip`, `acme.side`, `explorer`, and `someoneElsesContainer` in turn | `preferredAxisIsVertical` is `true` only for the view targeting `acme.strip`; `false` for the other three |
| contributed-views-011 | axis-rule, known-target-rule, unknown-container-note | View with `target: "panel"` and no self-declared `viewsContainers` entry | `preferredAxisIsVertical` is `true`; no `unknownContainer` note |
| contributed-views-012 | known-target-rule, unknown-container-note | View with `target: "explorer"` and no self-declared `viewsContainers` entry | No `unknownContainer` note is produced |
| contributed-views-013 | unknown-container-note | View with `target: "someoneElsesContainer"`, declared by nobody | Exactly one `unknownContainer` note whose `detail` contains `"someoneElsesContainer"` |
| contributed-views-014 | contributed-view-shape | `{ "id": "acme.sized", "name": "Sized", "visibility": "collapsed", "initialSize": 2 }` | `visibility` is `"collapsed"`; `initialSize` is `2` |
| contributed-views-015 | containers-sort-order, views-sort-order, axis-rule | Views under `acme.p1` (`viewZ`, `viewA`) and `acme.a1` (`viewM`, `viewB`); containers under `panel` (`acme.p2`, `acme.p1`) and `activitybar` (`acme.a2`, `acme.a1`) | Containers map to `containerID`s `["acme.a2","acme.a1","acme.p2","acme.p1"]`; views map to `viewID`s `["acme.viewM","acme.viewB","acme.viewZ","acme.viewA"]`, with `preferredAxisIsVertical` `[false,false,true,true]` |
| contributed-views-016 | duplicate-view-id-first-wins | One target's array declares `{ "id": "acme.dupe", "name": "First" }` then `{ "id": "acme.dupe", "name": "Second" }` | Exactly one view is registered; its `name` is `"First"`; exactly one `duplicateViewID` note whose `detail` contains `"explorer"` |
| contributed-views-017 | duplicate-view-id-first-wins, views-sort-order | `"zeta"` (declared first in the JSON) and `"explorer"` (declared second) each contribute one view with `id == "acme.dupe"` | The surviving view's `name` is `"FromExplorer"` (because `"explorer"` sorts before `"zeta"`), not `"FromZeta"`; the note's `detail` contains `"explorer"` and not `"zeta"` |
| contributed-views-018 | contributed-view-container-shape | `viewsContainers` entry with `title` but no `icon` key | Exactly one container record is returned; its `icon` is absent; the container is still returned and no view targeting it is treated as an `unknownContainer` |
| contributed-views-019 | unreadable-key-note-per-key | `{ "id": "acme.sized", "name": "Sized", "initialSize": "2", "visibility": 7 }` | `initialSize` is absent; `visibility` is absent; `name` is `"Sized"`; exactly two `malformedField` notes for `viewID == "acme.sized"`, one naming `"initialSize"` and one naming `"visibility"` |
| contributed-views-020 | unreadable-key-note-per-key | One entry with no optional keys at all, and one entry with `"when": null, "initialSize": null` | Two views are registered; no `malformedField` note is produced for either entry |
| contributed-views-021 | thread-safe-value-types, builder-isolation-free | Pass a view record, a container record, or a note across a concurrency boundary (for example, into a background task), and call the component that builds views from any concurrency context | Every value type here is safe to share across threads and the build function is callable from any context with no additional synchronization — no thread-safety violation results |
| contributed-views-022 | container-id-first-wins-for-axis, containers-not-deduplicated | `containerID == "dup"` declared once under `"activitybar"` and once under `"panel"` (both at index 0); a view targeting `"dup"` | Two container records are returned (both `"dup"` entries present, one per location); the view's `preferredAxisIsVertical` is `false`, because `"activitybar"` sorts before `"panel"` and is the first-seen declaration used to resolve `"dup"`'s location |

## Edge Cases

- Empty contributions (an extension manifest whose `contributes` declares no `views` or `viewsContainers` key at all): building views MUST return no containers, no views, and no notes.
- A `viewsContainers` dictionary present but every location's array empty: MUST return an empty containers list and produce no notes.
- Whitespace-only or empty-parenthesis icon (`"  "`, `"$()"`): per `icon-blank-input`/`icon-codicon-empty-name`, MUST resolve to an absent `symbolName` and `iconPath` with no note — a blank declaration MUST NOT be reported as a missing or unmapped icon.
- Codicon name given in the wrong case (e.g. `"$(SEARCH)"` where `"search"` is mapped): per `codicon-table-fixed`, the exact-match lookup MUST fail and MUST produce an `unmappedIcon` note, even though a case-insensitive match would have succeeded; this component performs no case-folding.
- A view id repeated inside one extension, whether in one target's array or split across two targets: per `duplicate-view-id-first-wins`, only the first (in `views-sort-order`) is registered, and a dropped duplicate's own `when`/icon/unreadable-key declarations MUST NOT produce their own notes (`dropped-duplicate-suppresses-its-own-notes`) — losing the duplicate is total, not partial.
- Two extensions declaring the identical view id: MUST NOT collide, because the first-wins tracking behind `duplicate-view-id-first-wins` is scoped to one call — one extension's manifest — and `registryID`'s namespacing (`registry-id-format`) is what keeps two extensions' same-named views distinct at the registry layer.
- A `viewsContainers` entry whose `containerID` collides with a VS Code built-in id (e.g. an extension self-declaring a container literally named `"panel"`): the built-in set in `known-target-rule` is checked independently of self-declared containers, so a self-declaration and a built-in id sharing a name is not a conflict this component detects or reports.
- Boundary `initialSize` values (`0`, a negative number, a very large number): carried through unchanged with no validation, per `contributed-view-shape`; this component makes no claim about what a negative or zero weight means to a layout — it is passed through raw, as documented on the source field itself ("a weight against its siblings, not a fraction of anything").
- Concurrent access: building views (`build-is-pure`, `builder-isolation-free`) reads only its two inputs and the fixed codicon-to-symbol table; it holds no mutable state shared across calls, so calling it from multiple threads simultaneously — with the same or different inputs — MUST each produce its own correct, independent result with no synchronization required.
- Error states (dependency unavailable): not applicable — this component consults no network, database, or file system; an icon that names a file is recorded as a string and never opened (`icon-file-path-form`, `build-is-pure`).
- Offline/disconnected state: not applicable — nothing in this component performs network access.
- Cancellation and timeouts: not applicable — building views returns immediately, with nothing to cancel or time out.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| contributions (to building views) | the manifest's decoded contributions | none — required | The already-decoded `views`/`viewsContainers` dictionaries this call reads; an empty contributions value supplies no entries for either when the manifest declares no `contributes` key at all |
| manifest (to building views) | the extension manifest | none — required | Supplies the manifest's identifier (`publisher.name`, case-folded), used to build every `extensionIdentifier` field and every `registryID` |
| the codicon-to-symbol table (internal) | a fixed mapping | fixed at build time | Not caller-configurable; the same table answers every call, for every extension |

## Deep Linking

Not applicable: this component defines no URL scheme handling and nothing in it registers, parses, or responds to a deep link.

## Localization

No string in this component is externalized through a localization key. Every note's `detail` is a hardcoded English string, built by interpolating manifest-supplied values into a fixed English template:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded) | `declared more than once; the declaration in "<target>" is the one registered.` | A `duplicateViewID` note |
| (none — hardcoded) | `targets the container "<target>", which neither this extension nor this host declares; the pane is arranged along the horizontal axis.` | An `unknownContainer` note |
| (none — hardcoded) | `declares <key> in a form this host cannot read; the pane is offered without it.` | A `malformedField` note |
| (none — hardcoded) | `declares when: <clause>. This host does not evaluate when clauses, so the pane is offered whatever the condition would have said.` | A `whenNotEvaluated` note |
| (none — hardcoded) | `asks for the icon $(<name>), which has no equivalent in this host's symbol set; the pane is offered without an icon.` | An `unmappedIcon` note |
| (none — hardcoded) | `asks for the image <path> from inside the extension; this host does not draw extension image files, so the pane is offered without an icon.` | A `fileIcon` note |

## Accessibility Options

Not applicable: this is a non-UI data builder with no visible surface, so it consults none of the system accessibility display options (Reduce Motion, Increase Contrast, Differentiate Without Color).

## Feature Flags

Not applicable: this component reads no feature-flag key and gates none of its behavior behind one.

## Analytics

Not applicable: this component emits no analytics events.

## Privacy

- **Data collected**: this component reads only manifest-declared display metadata — extension identifier, view id, name, icon reference (a codicon name or a relative file path string, never opened), `when` clause text, `visibility`, and `initialSize`. It never reads, stores, or transmits a credential, token, or user-content value.
- **Storage**: this component writes nothing to disk or to any persistent store; it returns its result to the caller, which decides what to keep (a separate registry component, outside this file's scope).
- **Transmission**: this component performs no network communication.
- **Retention**: the returned containers, views, and notes lists exist only as values the caller holds; this component itself retains nothing between calls.

## Logging

Not applicable: this component makes no logging call of any kind; every compromise it makes is communicated through the returned notes list instead of a log.

## Platform Notes

- **SwiftUI**: The source itself; `ContributedViews.swift` has no view-layer dependency at all (Foundation-only, no `@MainActor`, no observable state). Every value type here — `ContributedViewContainer`, `ContributedView`, `ContributedViewNote` — is declared `Sendable` and `Equatable`; `ContributedViewNote` additionally conforms to the shared `ExtensionContributionNote` protocol. `ContributedViewsBuilder` carries no actor-isolation annotation, so `build(from:manifest:)` is callable synchronously from any isolation domain (`nonisolated` contexts included) and its results may be captured in a `@Sendable` closure with no compiler diagnostic — the resolved icon is a named SF Symbol where a mapping exists, never a rendered image. Neither `NSLocalizedString` nor `String(localized:)` is used (see Localization); neither `Logger` nor `os_log` is used (see Logging). A SwiftUI extension host consumes `ContributedView`/`ContributedViewContainer` values the same way any other consumer does — typically by feeding `build(from:manifest:)`'s result into an `@Observable` registry that a view observes, since the builder itself is a one-shot pure computation with nothing to observe.
- **Compose**: Kotlin equivalents: `ContributedView.Kind` as a Kotlin `enum class`; `ContributedView`/`ContributedViewContainer`/`ContributedViewNote` as `data class`es; `Map<String, List<View>>` for the keyed manifest dictionaries, decoded with `kotlinx.serialization`. Kotlin's `Map` gives no iteration-order guarantee either, so the same explicit `sortedWith(compareBy(...))` on `(location, index)`/`(target, index)` composite keys is required for the same determinism reason.
- **React/Web**: TypeScript `interface`s for the three value types and a string-literal union (`"tree" | "webview"`) for `Kind`. `Record<string, ViewEntry[]>` mirrors the Swift dictionaries; a manual tolerant-decode layer (checking each optional field's `typeof` before assignment) replaces the unreadable-key/`try?` pattern, since `JSON.parse` alone gives no per-field recovery. `Array.prototype.sort` with an explicit comparator on the same composite keys reproduces the ordering; note that JavaScript's `sort` has been a stable sort since ES2019 (unlike Swift's), so a web port's ordering bug surface is narrower, but keeping the explicit composite key is still correct and clearer.
- **AppKit / UIKit**: Same note as SwiftUI — `ContributedViews.swift` has no AppKit or UIKit dependency of any kind; a platform-specific consumer (such as a tabs registry or pane controller) is what turns these values into a rendered pane, not this file.
- **WinUI 3**: `Kind` as a C# `enum`; `ContributedView`, `ContributedViewContainer`, and `ContributedViewNote` as `record` types (giving structural equality for free, matching Swift's `Equatable` synthesis). `System.Text.Json` with a custom `JsonConverter` reproduces the per-field try/fallback-to-`null` decode that produces the unreadable-key set — `System.Text.Json`'s default behavior is to throw for the whole object on one bad property, so each optional property needs its own guarded read inside the converter, the same shape as the source's local `read<T>` closure. `Dictionary<string, List<T>>` for the manifest's keyed containers. `Enumerable.OrderBy(...).ThenBy(...)` reproduces the sort; LINQ's `OrderBy` is documented as stable, so — unlike the Swift source, which states its composite key exists *because* `sort` is not stable — a WinUI 3 port could rely on `OrderBy`'s stability alone, but keeping the explicit `(location, index)`/`(target, index)` key is still recommended for parity with the source and for correctness if the sort implementation ever changes. No `Task`/`async` is needed: the source performs no I/O and this port's equivalent method should stay a plain synchronous method, matching the source's own signature.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/Extensions/ContributedViews.swift` |

## Design Decisions

**Decision**: A repeated `containerID` across two different `viewsContainers` locations is resolved to whichever declaration is first in the already-sorted `containers` array (alphabetical by location, then declared order within it) for the purpose of deciding a view's axis — not first in the manifest's raw text, and not deduplicated out of the returned `containers` array itself.
**Rationale**: The source's own comment states this directly: "First declaration wins for a repeated container id, and `containers` is already sorted, so 'first' is a fact about the manifest's content rather than about a dictionary's hash seed." Deduplicating the returned `containers` array was rejected because nothing currently reads that array for rendering (Ruling FD); only the axis-resolution map (`locationsByContainerID`) needs a single answer per id.
**Approved**: pending

**Decision**: A dropped duplicate view (the second-or-later declaration of a repeated `id`) contributes only its `duplicateViewID` note and no others — its own `when`, icon, or unreadable-key declarations never produce a `whenNotEvaluated`, `unmappedIcon`, `fileIcon`, or `malformedField` note, because the `continue` after recording the duplicate note skips every later check in the loop body entirely.
**Rationale**: This follows directly from the control flow in `build(from:manifest:)`: the duplicate check and its `continue` run before the icon, `when`, and unreadable-key handling for that same loop iteration, so a dropped entry's other declarations are never inspected at all. This is stated here because a reader tracing only the duplicate-id branch could otherwise expect a dropped duplicate to still contribute its other notes.
**Approved**: pending

**Decision**: Codicon name matching is exact-case only; the codicon-to-symbol table's keys are looked up with no normalization.
**Rationale**: Traceable directly to `CodiconSymbols.symbolName(forCodicon:)`, which is a plain `table[codicon]` dictionary subscript with no `.lowercased()` or other normalization applied to `codicon` first. Every real-world codicon reference VS Code itself emits is already lowercase, so this has no observed cost in the corpus this table was built from, but a manifest that spells a codicon in a different case will see it treated as unmapped.
**Approved**: pending

**Decision**: `preferredAxisIsVertical` is `true` exactly when a view's resolved location is the literal string `"panel"`, including when a view targets the *built-in* container id `"panel"` directly with no self-declared `viewsContainers` entry at all — even though the enumerated built-in ids are otherwise all `false`.
**Rationale**: The source's own comment calls this out explicitly as a deliberate departure from a literal reading of the built-in-id enumeration: "`panel`... is the one location that means 'the bottom strip'... Ruling FD says a view's axis follows its container's *location*... `panel` is both: it is the `viewsContainers` key that means the bottom strip **and** a built-in container id... This resolves it to vertical, applying the ruling's reasoning... rather than its enumeration." The `isKnownTarget &&` conjunction in the axis computation is written out for the same reason the comment calls "unreachable today... which is exactly why it needs saying": the only string that satisfies the location-equals-`"panel"` check is `"panel"` itself, which is always a known target, so the conjunction is currently redundant but documents that the code did not silently rely on that coincidence.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |

`graceful-degradation` passes because a malformed field, an unmapped icon, an unknown container, or a duplicate view id each costs only that one field or entry — per `unreadable-key-note-per-key`, `icon-codicon-unmapped`, `unknown-container-note`, and `duplicate-view-id-first-wins` — never the extension's other views or the whole build. `idempotent-operations` passes because building views is a pure function (`build-is-pure`) over immutable inputs and a fixed table, so calling it twice with identical arguments MUST return bit-for-bit identical containers, views, and notes lists, with no accumulation between calls. `no-hardcoded-strings` fails because every note's `detail` sentence is an unlocalized English string literal (see Localization), with no localization key of any kind. `unit-test-coverage` passes: `ContributedViewsBuilderTests.swift` exercises registry-id namespacing, the tree/webview default, every icon-resolution branch (mapped, unmapped, animated, blank, file-path), the `when`-clause note, all four axis-rule target kinds, both duplicate-view-id shapes (within one target and across two), container-without-icon survival, both directions of the unreadable-key leniency, and declared-order preservation for both containers and views.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/manifest/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation |
