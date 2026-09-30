<!-- leaf: implement-general-1/htdv-engine--part-2 · source: htdv-engine.md -->

# HTDV Engine — continued (part 2)

**Rules** (cite as `implement-general-1/htdv-engine--part-2#<slug>`):

- `item-shape` MUST
- `level-shape` MUST
- `detail-shape` MUST
- `child-shape` MUST
- `leads-to-shape` MUST
- `badge-shape` MUST
- `badge-color-theme-role` MUST
- `create-action-shape` MUST
- `data-source-contract` MUST
- `platform-view-controller-alias` MUST
- `cell-content-projection` MUST
- `cell-content-equality` MUST
- `initial-state` MUST
- `is-loading-derivation` MUST
- `load-resets-then-fetches` MUST
- `select-validates-membership` MUST
- `select-truncates-then-fetches` MUST
- `select-applies-whatever-child-returns` MUST
- `reload-root-vs-nested` MUST
- `reload-preserves-or-drops-selection` MUST
- `reload-parent-became-non-level` MUST
- `retry-reissues-exact-failed-operation` MUST
- `stale-response-dropped` MUST
- `error-shape` MUST
- `pop-to-level-contract` MUST
- `clear-detail-contract` MUST
- `on-change-fires-after-every-transition` MUST
- `single-observer-callback` MUST
- `main-actor-confinement` MUST
- `selected-path-and-item-queries` MUST

## Behavioral Requirements

### HTDVModel.swift — data model and data source contract

- **item-shape**: `HTDVItem` MUST be an `Identifiable`, `Hashable`,
  `Sendable` struct exposing immutable `id: String`, `label: String`,
  `sublabel: String?`, `systemImage: String?`, `dividerAfter: Bool`,
  `leadsTo: HTDVLeadsTo`, and `badge: HTDVBadge?`, constructible only through
  its public `init`, whose `dividerAfter` defaults to `false`, `leadsTo`
  defaults to `.list`, and `sublabel`/`systemImage`/`badge` default to `nil`.
- **level-shape**: `HTDVLevel` MUST be an `Identifiable`, `Sendable` struct
  exposing immutable `id: String`, `title: String`, `items: [HTDVItem]`,
  `emptyMessage: String`, and `createAction: HTDVCreateAction?`, whose
  `emptyMessage` defaults to the literal `"Nothing here yet"` and whose
  `createAction` defaults to `nil`.
- **detail-shape**: `HTDVDetail` MUST be a `Sendable` struct exposing
  immutable `id: String`, `title: String`, and a `make: @MainActor @Sendable
  () -> PlatformViewController` factory, constructible only through its
  public `init`.
- **child-shape**: `HTDVChild` MUST be a `Sendable` enum with exactly three
  cases — `.level(HTDVLevel)`, `.detail(HTDVDetail)`, and `.empty` — the
  three possible answers to "what lies beneath a selected path."
- **leads-to-shape**: `HTDVLeadsTo` MUST be a `Sendable`, `Hashable` enum with
  exactly two cases, `.list` and `.detail`, naming what selecting an item
  reveals to its right.
- **badge-shape**: `HTDVBadge` MUST be a `Sendable`, `Hashable` enum with
  exactly two cases, `.dot(HTDVBadgeColor)` and `.count(Int)`.
- **badge-color-theme-role**: `HTDVBadgeColor.themeRole` MUST map `.red` to
  `.danger`, `.green` to `.success`, `.blue` to `.accent`, `.gray` to
  `.secondaryText`, and both `.orange` and `.yellow` to `.warning` — the two
  names collapsing onto one role because, per the source's own comment, "the
  palette has no separate orange."
- **create-action-shape**: `HTDVCreateAction` MUST be a `Sendable` struct
  exposing an immutable `title: String` and a `perform: @MainActor @Sendable
  (PlatformViewController) async -> Void` closure that receives the hosting
  view controller so it can present its own UI.
- **data-source-contract**: `HTDVDataSource` MUST be a `Sendable`,
  `AnyObject`-constrained protocol declaring `func rootLevel() async throws
  -> HTDVLevel` and `func child(for path: [HTDVItem]) async throws ->
  HTDVChild`; per its own doc comment, implementations are typically actors
  or `@unchecked Sendable` classes wrapping a client.
- **platform-view-controller-alias**: `PlatformViewController` MUST resolve
  to `NSViewController` when `AppKit` is importable and the build is not
  Mac Catalyst, and to `UIViewController` when `UIKit` is importable, so
  every closure in this file that vends or receives a view controller
  (`HTDVDetail.make`, `HTDVCreateAction.perform`) is typed identically on
  both platforms.

### HTDVCellContent.swift — rail-row projection

- **cell-content-projection**: `HTDVCellContent.init(item:)` MUST copy
  `label`, `sublabel`, `systemImage`, and `badge` from the given `HTDVItem`
  unchanged, and MUST set `isDisclosing` to `true` if and only if
  `item.leadsTo == .list`.
- **cell-content-equality**: `HTDVCellContent` MUST be `Hashable` and
  `Sendable` so a rail's diffable data source can key rows by it and pass it
  across the `@MainActor` boundary to the view layer.

### HTDVController.swift — navigation, selection, and loading state machine

- **initial-state**: A newly constructed `HTDVController` MUST have empty
  `levels`, empty `selection`, a `nil` `detail`, a `nil`
  `loadingLevelIndex`, and a `nil` `error`.
- **is-loading-derivation**: `isLoading` MUST be `true` if and only if
  `loadingLevelIndex` is non-`nil`; it MUST NOT be backed by its own stored
  flag.
- **load-resets-then-fetches**: `load()` MUST clear `levels`, `selection`,
  `detail`, `error`, and `failedRequest` before fetching, MUST call
  `dataSource.rootLevel()`, and on success MUST set `levels` to the single
  returned root level.
- **select-validates-membership**: `select(itemID:atLevel:)` MUST no-op
  (leaving `levels`, `selection`, `detail`, and `error` unchanged) unless
  `levelIndex` is a valid index into `levels` and `itemID` names an item
  present in `levels[levelIndex].items`.
- **select-truncates-then-fetches**: On a valid `itemID`, `select` MUST
  first truncate `levels` to `levelIndex + 1` entries and `selection` to
  `levelIndex` entries plus the newly selected `itemID`, clear `detail` and
  `error`, and only then call `dataSource.child(for: selectedPath())`.
- **select-applies-whatever-child-returns**: On success, `select` MUST apply
  the returned `HTDVChild` via `apply(_:)` — appending a `.level` to
  `levels`, replacing `detail` with a `.detail`, or doing nothing for
  `.empty` — regardless of whether the selected item's own `leadsTo` was
  `.list` or `.detail`; the controller does not validate agreement between
  `HTDVItem.leadsTo` and the `HTDVChild` the data source actually returns for
  it.
- **reload-root-vs-nested**: `reload(level:)` MUST call
  `dataSource.rootLevel()` when `levelIndex == 0`, and for `levelIndex > 0`
  MUST call `dataSource.child(for:)` with the path truncated to the parent
  of `levelIndex` and require the result to be `.level`; a valid `levelIndex`
  that is out of bounds for the current `levels` MUST make `reload` no-op.
- **reload-preserves-or-drops-selection**: When a nested `reload` succeeds
  with a `.level`, `reload` MUST replace `levels[levelIndex]` with the fresh
  level and MUST preserve the current selection at that level if the
  selected item's `id` still appears in the fresh level's `items`, and MUST
  otherwise truncate `levels`, `selection`, and `detail` from `levelIndex`
  onward.
- **reload-parent-became-non-level**: When a nested `reload`'s parent lookup
  (`dataSource.child(for:)` on the parent path) returns `.detail` or
  `.empty` instead of the expected `.level`, `reload` MUST drop `levels` and
  `selection` from `levelIndex` onward, clear `detail`, and apply whatever
  `HTDVChild` was actually returned (a `.detail` is shown; `.empty` shows
  nothing) rather than discarding it, per the source's own comment: "a
  `.detail` is real content the caller handed us, and throwing it away would
  show the user nothing at all."
- **retry-reissues-exact-failed-operation**: `retry()` MUST no-op unless
  `error` is non-`nil` and a `failedRequest` was recorded, and when both are
  present MUST re-invoke exactly the operation that failed — `load()` for a
  failed root load, `select(itemID:atLevel:)` with the same arguments for a
  failed selection, or `reload(level:)` with the same level for a failed
  reload.
- **stale-response-dropped**: Every fetch MUST capture the `generation`
  counter's value at the moment it began (via `beginRequest`, which
  increments `generation` first); on completion — success or failure — the
  controller MUST discard the result and make no state change whenever the
  captured generation no longer equals the current `generation`, because a
  newer request (or a `popToLevel`/`clearDetail` call) started in the
  interim.
- **error-shape**: On a thrown error, `fail(gen:levelIndex:_:request:)` MUST
  set `error` to an `HTDVLoadError` carrying the failing `levelIndex` and a
  `message` derived from `(error as? LocalizedError)?.errorDescription ??
  String(describing: error)`, MUST record the `failedRequest` so `retry()`
  can reissue it, and MUST clear `loadingLevelIndex` — unless the failure is
  itself stale (see stale-response-dropped), in which case none of this MUST
  happen.
- **pop-to-level-contract**: `popToLevel(_:)` MUST no-op when `levelIndex <
  -1` or `levelIndex >= levels.count - 1`; otherwise it MUST bump
  `generation` (discarding any in-flight deeper load), truncate `levels` to
  `levelIndex + 1` entries (or to zero entries when `levelIndex == -1`),
  truncate `selection` to `max(0, levelIndex)` entries, clear `detail`,
  clear `error` and `failedRequest`, clear `loadingLevelIndex`, and fire
  `onChange` exactly once.
- **clear-detail-contract**: `clearDetail()` MUST no-op when `detail` is
  already `nil`; otherwise it MUST bump `generation` (discarding any
  in-flight detail load), clear `detail`, `error`, `failedRequest`, and
  `loadingLevelIndex`, leave `levels` and `selection` untouched, and fire
  `onChange` exactly once.
- **on-change-fires-after-every-transition**: `onChange` MUST be invoked
  after every state transition made by `load`, `select`, `reload`,
  `popToLevel`, and `clearDetail` — including the loading-started transition
  at the start of a fetch (`beginRequest` calls `onChange` before the
  `await`) — and MUST default to a no-op closure (`{ _ in }`) until a host
  assigns one.
- **single-observer-callback**: `onChange` MUST be a single-slot property,
  not a multicast; assigning it a second time MUST silently replace the
  first observer with no diagnostic, per `docs/htdv.md`'s "One host per
  controller" note — each `HTDVController` MUST be driven by exactly one
  host.
- **main-actor-confinement**: `HTDVController` MUST be declared
  `@MainActor` and MUST NOT declare `Sendable` conformance of its own; every
  one of its mutable properties and methods is therefore confined to the
  main actor's isolation domain, and a caller on a different isolation
  domain MUST hop to the main actor (`await`) to read or mutate it.
- **selected-path-and-item-queries**: `selectedPath()` MUST return the
  `HTDVItem` at each selected id in `selection`, skipping (via
  `compactMap`) any level/id pair that no longer resolves — for example
  after a level was replaced by `reload` — and `selectedItem(atLevel:)` MUST
  return `nil` when `levelIndex` is out of bounds for `selection` or for
  `levels`.

