<!-- leaf: implement-extension-host-core-1/extensions-contributed-views--edge-cases · source: extension-host-core-extensions-contributed-views.md -->

# ContributedViewsBuilder

**Rules** (cite as `implement-extension-host-core-1/extensions-contributed-views--edge-cases#<slug>`):

- `build-from-manifest-return-containers-views-notes` MUST — Empty contributes block (ExtensionManifest.Contributions.empty, i.e. no views or viewsContainers key at all): …
- `location-array-empty-return-containers-produce-notes` MUST — A viewsContainers dictionary present but every location's array empty: MUST return containers: [] and produce no notes.
- `codicon-empty-name-resolve-symbolname-nil-iconpath` MUST — Whitespace-only or empty-parenthesis icon (" ", "$()"): per icon-blank-input/icon-codicon-empty-name, MUST resolve to …
- `exact-match-lookup-fail-produce-unmappedicon-note` MUST — Codicon name given in the wrong case (e.g. "$(SEARCH)" where "search" is mapped): per codicon-table-fixed, the …
- `own-icon-unreadablekeys-not-produce-their-own-notes` MUST — A view id repeated inside one extension, whether in one target's array or split across two targets: per …
- `identical-view-id-not-collide-because-duplicate-view` MUST — Two extensions declaring the identical view id: MUST NOT collide, because duplicate-view-id-first-wins's tracking …
- `same-different-inputs-produce-own-correct-independent` MUST — Concurrent access: build(from:manifest:) (build-is-pure, builder-isolation-free) reads only its two parameters and the …

## Edge Cases

- Empty `contributes` block (`ExtensionManifest.Contributions.empty`, i.e. no `views` or `viewsContainers` key at all): `build(from:manifest:)` MUST return `(containers: [], views: [], notes: [])`.
- A `viewsContainers` dictionary present but every location's array empty: MUST return `containers: []` and produce no notes.
- Whitespace-only or empty-parenthesis icon (`"  "`, `"$()"`): per `icon-blank-input`/`icon-codicon-empty-name`, MUST resolve to `symbolName == nil, iconPath == nil` with no note — a blank declaration MUST NOT be reported as a missing or unmapped icon.
- Codicon name given in the wrong case (e.g. `"$(SEARCH)"` where `"search"` is mapped): per `codicon-table-fixed`, the exact-match lookup MUST fail and MUST produce an `unmappedIcon` note, even though a case-insensitive match would have succeeded; this builder performs no case-folding.
- A view id repeated inside one extension, whether in one target's array or split across two targets: per `duplicate-view-id-first-wins`, only the first (in `views-sort-order`) is registered, and a dropped duplicate's own `when`/icon/`unreadableKeys` MUST NOT produce their own notes (`dropped-duplicate-suppresses-its-own-notes`) — losing the duplicate is total, not partial.
- Two extensions declaring the identical view id: MUST NOT collide, because `duplicate-view-id-first-wins`'s tracking (`seenViewIDs`) is scoped to one call of `build(from:manifest:)`, i.e. one extension's manifest; `registryID`'s namespacing (`registry-id-format`) is what keeps two extensions' same-named views distinct at the registry layer.
- A `viewsContainers` entry whose `containerID` collides with a VS Code built-in id (e.g. an extension self-declaring a container literally named `"panel"`): the built-in set in `known-target-rule` is checked independently of self-declared containers, so a self-declaration and a built-in id sharing a name is not a conflict this builder detects or reports.
- Boundary `initialSize` values (`0`, a negative number, a very large number): carried through unchanged with no validation, per `contributed-view-shape`; this builder makes no claim about what a negative or zero weight means to a layout — it is passed through raw, as documented on the source field itself ("a weight against its siblings, not a fraction of anything").
- Concurrent access: `build(from:manifest:)` (`build-is-pure`, `builder-isolation-free`) reads only its two parameters and the fixed `CodiconSymbols.table`; it holds no mutable state shared across calls, so calling it from multiple threads or tasks simultaneously — with the same or different inputs — MUST each produce its own correct, independent result with no synchronization required.
- Error states (dependency unavailable): not applicable — this builder consults no network, database, or file system; an icon that names a file is recorded as a string and never opened (`icon-file-path-form`, `build-is-pure`).
- Offline/disconnected state: not applicable — nothing in `ContributedViews.swift` performs network access.
- Cancellation and timeouts: not applicable — `build(from:manifest:)` is synchronous, non-`async`, and returns immediately; there is no long-running or cancellable operation to time out.
