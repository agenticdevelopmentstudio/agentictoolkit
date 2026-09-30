<!-- leaf: implement-extension-host-core-1/extensions-contributed-views--part-2 · source: extension-host-core-extensions-contributed-views.md -->

# ContributedViewsBuilder — continued (part 2)

**Rules** (cite as `implement-extension-host-core-1/extensions-contributed-views--part-2#<slug>`):

- `contributed-view-container-shape` MUST
- `contributed-view-shape` MUST
- `view-kind-enum` MUST
- `contributed-view-note-shape` MUST
- `note-kind-enum` MUST
- `build-is-pure` MUST
- `registry-id-format` MUST
- `containers-sort-order` MUST
- `views-sort-order` MUST
- `container-id-first-wins-for-axis` MUST
- `containers-not-deduplicated` MUST
- `duplicate-view-id-first-wins` MUST
- `dropped-duplicate-suppresses-its-own-notes` MUST
- `view-kind-default` MUST
- `icon-blank-input` MUST
- `icon-codicon-form` MUST
- `icon-codicon-animation-modifier-stripped` MUST
- `icon-codicon-empty-name` MUST
- `icon-codicon-mapped` MUST
- `icon-codicon-unmapped` MUST
- `icon-file-path-form` MUST
- `when-stored-not-evaluated` MUST
- `when-present-note` MUST
- `unreadable-key-note-per-key` MUST
- `known-target-rule` MUST
- `unknown-container-note` MUST
- `axis-rule` MUST
- `codicon-table-fixed` MUST
- `sendable-value-types` MUST
- `builder-isolation-free` MUST
- `container-notes-none` MUST

## Behavioral Requirements

- **contributed-view-container-shape**: `ContributedViewContainer` MUST be a `Sendable`, `Equatable` value type carrying `extensionIdentifier`, `location` (the `viewsContainers` key the entry was declared under, e.g. `activitybar`, `panel`), `containerID`, `title`, an optional `icon` (the declared value, raw and unresolved), and an optional `when` (the declared clause, raw and unevaluated).
- **contributed-view-shape**: `ContributedView` MUST be a `Sendable`, `Equatable` value type carrying `extensionIdentifier`, `viewID` (the raw VS Code view id), `registryID`, `targetContainerID`, `name`, `kind`, an optional `symbolName`, an optional `iconPath`, an optional `when`, an optional `visibility`, an optional `initialSize`, and `preferredAxisIsVertical`.
- **view-kind-enum**: `ContributedView.Kind` MUST be exactly one of two cases, `.tree` or `.webview`.
- **contributed-view-note-shape**: `ContributedViewNote` MUST be an `Equatable` type conforming to `ExtensionContributionNote`, carrying `extensionIdentifier`, `viewID`, `kind`, and a human-readable `detail` sentence.
- **note-kind-enum**: `ContributedViewNote.Kind` MUST be one of exactly six cases: `whenNotEvaluated`, `unmappedIcon`, `fileIcon`, `unknownContainer`, `duplicateViewID`, `malformedField`.
- **build-is-pure**: `ContributedViewsBuilder.build(from:manifest:)` MUST be a pure function of its two arguments: it MUST perform no file I/O, no network access, and no logging, and it MUST NOT open, read, or otherwise resolve any extension-bundled image file even when a declared icon names one.
- **registry-id-format**: `ContributedView.registryID` MUST equal the literal concatenation `"extension." + manifest.identifier + "." + declared.id`, so two different extensions declaring the identical `viewID` produce the same `viewID` but different `registryID` values, and one extension's `viewID` is always the same string as the corresponding VS Code `views` entry's own `id`.
- **containers-sort-order**: The returned `containers` array MUST be sorted by `location` (ascending), then by each container's index within its own `viewsContainers` array as the manifest declared it — never by `containerID` — so a location's containers keep the order the manifest author wrote them in while the (unordered) dictionary of locations is made deterministic by the location-name sort.
- **views-sort-order**: The returned `views` array MUST be sorted by `targetContainerID` (ascending), then by each view's index within its own `views` array as the manifest declared it — never by `viewID` — following the same rule as `containers-sort-order` for the same reason.
- **container-id-first-wins-for-axis**: When two or more `viewsContainers` entries across different locations declare the same `containerID`, only the first one encountered while iterating the already-sorted `containers` array MUST be used to resolve that `containerID`'s location for axis purposes (`known-target-rule`, `axis-rule`); later same-id declarations MUST NOT overwrite it and MUST NOT produce any note.
- **containers-not-deduplicated**: Unlike the location resolution in `container-id-first-wins-for-axis`, the `containers` array itself MUST include every declared `ContributedViewContainer` entry, including two or more entries that share the same `containerID` across different locations; this builder MUST NOT deduplicate or drop any container entry.
- **duplicate-view-id-first-wins**: When the same extension's manifest declares the same view `id` more than once — whether within one target's array or across two or more different targets — only the first entry in `views-sort-order`'s order MUST be registered as a `ContributedView`; every subsequent entry sharing that `id` MUST be dropped (never appended to `views`) and MUST produce exactly one `duplicateViewID` note naming the `viewID` and the target container that won.
- **dropped-duplicate-suppresses-its-own-notes**: A dropped duplicate entry (per `duplicate-view-id-first-wins`) MUST NOT produce a `whenNotEvaluated`, `unmappedIcon`, `fileIcon`, or `malformedField` note of its own even when its declaration would otherwise trigger one; only the `duplicateViewID` note MUST be produced for it.
- **view-kind-default**: A view's `kind` MUST be `.tree` whenever the declared `type` is absent or is any string other than the literal `"webview"`, and MUST be `.webview` only when the declared `type` is exactly `"webview"`; neither outcome MUST produce a note.
- **icon-blank-input**: When the declared `icon`, after trimming leading and trailing whitespace and newline characters, is an empty string, `symbolName` and `iconPath` MUST both be `nil` and no note MUST be produced.
- **icon-codicon-form**: A trimmed, non-empty `icon` value that begins with `"$("` and ends with `")"` MUST be treated as a codicon reference rather than a file path.
- **icon-codicon-animation-modifier-stripped**: Within a codicon reference, any suffix after a `~` character (e.g. the `~spin` in `$(sync~spin)`) MUST be removed before the codicon name is looked up, so `$(sync~spin)` and `$(sync)` MUST resolve to the identical `symbolName`.
- **icon-codicon-empty-name**: When a codicon reference's inner name is empty after the animation-modifier strip (e.g. the literal `"$()"`), `symbolName` and `iconPath` MUST both be `nil` and no note MUST be produced.
- **icon-codicon-mapped**: When a codicon reference's name (after the animation-modifier strip) is a key in `CodiconSymbols.table`, `symbolName` MUST be set to that key's mapped value, `iconPath` MUST be `nil`, and no note MUST be produced.
- **icon-codicon-unmapped**: When a codicon reference's name is not a key in `CodiconSymbols.table`, `symbolName` and `iconPath` MUST both be `nil`, and exactly one `unmappedIcon` note naming the codicon MUST be produced.
- **icon-file-path-form**: A trimmed, non-empty `icon` value that does not have both the `"$("` prefix and the `")"` suffix MUST be treated as a file path: `iconPath` MUST be set to the trimmed string, `symbolName` MUST be `nil`, and exactly one `fileIcon` note naming the path MUST be produced.
- **when-stored-not-evaluated**: A declared `when` clause MUST be copied verbatim into the built `ContributedView.when` (or, for a container, `ContributedViewContainer.when`), and the view or container MUST be built and registered regardless of the clause's content; this builder MUST NOT parse or evaluate the clause.
- **when-present-note**: When a view's declared `when` clause is present and non-empty, exactly one `whenNotEvaluated` note carrying the clause's literal text MUST be produced; an absent or empty `when` clause MUST NOT produce this note. `ContributedViewContainer.when` carries the same raw value but produces no equivalent note, because nothing in this host resolves containers yet (Ruling FD).
- **unreadable-key-note-per-key**: For every key name present in a declared view's `unreadableKeys`, exactly one `malformedField` note naming that key MUST be produced, and the view MUST still be built without a value for that field; a key that was absent from the manifest, or explicitly declared `null`, MUST NOT appear in `unreadableKeys` and MUST NOT produce a note.
- **known-target-rule**: A view's `targetContainerID` MUST be treated as known when it matches either a `containerID` declared anywhere in the manifest's own `viewsContainers` (subject to `container-id-first-wins-for-axis`) or one of the fixed built-in ids `"explorer"`, `"scm"`, `"debug"`, `"test"`, `"remote"`, `"panel"`; every other `targetContainerID` MUST be treated as unknown.
- **unknown-container-note**: When a view's `targetContainerID` is unknown (per `known-target-rule`), exactly one `unknownContainer` note naming the target MUST be produced, and the view MUST still be built, registered, and given `preferredAxisIsVertical == false`.
- **axis-rule**: `preferredAxisIsVertical` MUST be `true` if and only if the target is known (per `known-target-rule`) and its resolved location — the self-declared container's `location` when one was found, otherwise the target id itself for a built-in target — equals the literal string `"panel"`; it MUST be `false` for every other known target and for every unknown target.
- **codicon-table-fixed**: `CodiconSymbols.table` MUST be a fixed, immutable `[String: String]` mapping consulted by exact-match key lookup only (no case-folding, no partial matching); `CodiconSymbols.symbolName(forCodicon:)` MUST return `nil` for any name that is not a key in the table.
- **sendable-value-types**: `ContributedViewContainer`, `ContributedView`, and `ContributedViewNote` MUST be `Sendable` and `Equatable`, safe to pass across actor and task boundaries with no additional synchronization.
- **builder-isolation-free**: `ContributedViewsBuilder` MUST carry no actor isolation annotation and no stored instance state; `build(from:manifest:)` MUST be callable synchronously from any isolation domain, because every parameter and return value is `Sendable` and the function touches no shared mutable state.
- **container-notes-none**: Building `containers` MUST NOT produce any `ContributedViewNote` for a container entry — not for a missing icon, not for a repeated `containerID`, and not for a `when` clause — because nothing in this host currently reads, renders, or resolves a container (Ruling FD); every note this builder produces is keyed to a view.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `contributions` (`build(from:manifest:)`) | `ExtensionManifest.Contributions` | none — required | The already-decoded `views`/`viewsContainers` dictionaries this call reads; `Contributions.empty` supplies `[:]` for both when the manifest declares no `contributes` key at all |
| `manifest` (`build(from:manifest:)`) | `ExtensionManifest` | none — required | Supplies `manifest.identifier` (`publisher.name`, case-folded), used to build every `extensionIdentifier` field and every `registryID` |
| `CodiconSymbols.table` (internal) | `[String: String]` | fixed at compile time | Not caller-configurable; the same table answers every call, for every extension |

