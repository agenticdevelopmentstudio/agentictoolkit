<!-- leaf: implement-window-management/window-frame-manager--part-3 · source: window-management-window-frame-manager.md -->

# WindowFrameManager — continued (part 3)

**Rules** (cite as `implement-window-management/window-frame-manager--part-3#<slug>`):

- `restore-tags-window` MUST
- `restore-no-spec` MUST
- `restore-min-size` MUST
- `restore-no-persistence` MUST
- `restore-touch-set` MUST
- `restore-no-screens` MUST
- `restore-known-set` MUST
- `restore-known-set-resave` MUST
- `restore-unknown-set` MUST
- `restore-legacy-migration` MUST
- `restore-fallthrough` MUST
- `resolve-screen-choice` MUST
- `resolve-exact-replay` MUST
- `resolve-relative` MUST
- `resolve-validate` MUST
- `relative-fallback-source` MUST
- `save-guard-spec` MUST
- `save-touch-first` MUST
- `save-best-screen` MUST
- `save-no-screen` MUST
- `save-placement-values` MUST
- `save-preserves-other-sets` MUST
- `save-drops-legacy` MUST
- `save-prune` MUST
- `save-write-through` MUST
- `cache-read-through` MUST
- `cache-miss-not-cached` MUST
- `reset-frame` MUST
- `reset-all-frames` MUST
- `clear-saved-state` MUST
- `reset-leaves-visibility` MUST
- `load-visibility` MUST
- `save-visibility` MUST
- `clear-visibility` MUST
- `visible-window-ids` MUST
- `default-position-screen` MUST
- `geometric-center` MUST
- `change-no-screens` MUST
- `change-window-lookup` MUST
- `change-known-placement` MUST
- `change-new-set-fallback` MUST
- `change-reclamp` MUST
- `change-apply-only-real` MUST
- `change-animate-visible` MUST
- `change-resave-by-delegate` MUST
- `storage-default-backend` MUST

### Restore

- **restore-tags-window**: `restoreFrame(for:id:)` MUST set the window's identifier to `wm_<id>` before any other step, including when it then fails.
- **restore-no-spec**: With no spec registered for the id, restore MUST log a warning, center the window geometrically on the main screen's visible frame, and return `false`.
- **restore-min-size**: With a spec, restore MUST set the window's minimum size to `spec.minSize`.
- **restore-no-persistence**: When the spec does not persist frames, or no state is stored for the id, restore MUST apply the spec's default frame on the main screen (first screen if there is no main) and return `false`.
- **restore-touch-set**: Before looking a placement up, restore MUST call `ScreenManager.touchCurrentSet()` and then read `currentSetID`.
- **restore-no-screens**: When the provider reports no screens, restore MUST center the window geometrically and return `false`.
- **restore-known-set**: When a placement exists under the current set id, restore MUST apply the resolved frame (see placement-resolution rules) and return `true`.
- **restore-known-set-resave**: When that resolution was not an exact screen match, restore MUST immediately save the window's frame so the placement records the new screen geometry.
- **restore-unknown-set**: When no placement exists for the current set but other placements do, restore MUST apply the relative-fallback frame, save the window's frame under the current set, and return `true`.
- **restore-legacy-migration**: When there are no placements and a `legacy` record exists, restore MUST place the window with `absoluteFrame` from the legacy proportions and size on the best-matching screen (main, then first screen when none matches), pass it through `validateFrame`, apply it, save the frame as a per-set placement, and return `true`.
- **restore-fallthrough**: When stored state has neither placements nor a legacy record, restore MUST apply the spec's default frame and return `false`.

### Placement resolution

- **resolve-screen-choice**: A saved placement MUST be resolved on the screen `ScreenMatcher` finds for its fingerprint, falling back to the main screen, then the first screen.
- **resolve-exact-replay**: On an `exact` match the frame MUST be rebuilt from the saved `topLeftX` / `topLeftY` and saved size with `frame(topLeftOffset:...)`.
- **resolve-relative**: On any non-exact match or no match, the frame MUST be rebuilt from `relativeX` / `relativeY` and saved size with `frame(relativePosition:...)` and the spec's `minSize`.
- **resolve-validate**: Every resolved frame MUST pass through `validateFrame` against the chosen screen's visible frame and the spec's `minSize`.
- **relative-fallback-source**: The relative fallback MUST use the placement with the latest `savedAt`, placed on the main screen (first screen when there is no main), through `frame(relativePosition:...)` then `validateFrame`; it MUST return nothing when there are no placements.

### Save

- **save-guard-spec**: `saveFrame(for:id:)` MUST do nothing when no spec is registered for the id or the spec does not persist frames.
- **save-touch-first**: Save MUST call `ScreenManager.touchCurrentSet()` and read `currentSetID` before choosing the screen to fingerprint, so a move that AppKit delivers before the screen-change notification is filed under the live set.
- **save-best-screen**: Save MUST fingerprint the screen that contains the largest area of the window's frame intersected with each screen's visible frame; with no intersecting screen it MUST fall back to the window's own screen, then the system main screen, both read directly from AppKit rather than the injected provider.
- **save-no-screen**: When no screen can be chosen, save MUST return without writing.
- **save-placement-values**: The placement written MUST carry the chosen screen's fingerprint, the window's top-left offset and relative position computed against that screen's visible frame, the window's current width and height, and `savedAt` equal to `ScreenManager.now()`.
- **save-preserves-other-sets**: Save MUST rebuild state from the cached (or freshly loaded) placements, replace only the current set's entry, and keep other sets' entries subject to pruning.
- **save-drops-legacy**: The state written by save MUST have `legacy` equal to `nil`, so the first save consumes a decoded v1 record.
- **save-prune**: Save MUST keep a placement only when its key is the current set id, or its key is in `ScreenManager.knownSetIDs`, or its `savedAt` is later than `now() - maxSetAge`.
- **save-write-through**: Save MUST update the in-memory cache for the id and then call `storage.saveState(_:for:)` exactly once.

### Cache

- **cache-read-through**: Restore and screen-change handling MUST read an id's state from the in-memory cache when present, and otherwise load it from storage and cache the result.
- **cache-miss-not-cached**: A load that returns `nil` MUST leave the cache without an entry for the id, so the next read loads from storage again.

### Reset and clear

- **reset-frame**: `resetFrame(for:id:)` MUST remove the id's stored state, clear its cache entry, and apply the spec's default frame, or center the window geometrically when no spec is registered.
- **reset-all-frames**: `resetAllFrames()` MUST remove stored state for every registered id and empty the whole cache; it MUST NOT reposition any window and MUST NOT remove stored state for ids that are not registered.
- **clear-saved-state**: `clearSavedState(for:)` MUST remove the id's stored state and cache entry without moving any window.
- **reset-leaves-visibility**: `resetFrame`, `resetAllFrames` and `clearSavedState` MUST NOT touch persisted visibility.

### Visibility

- **load-visibility**: `loadVisibility(for:)` MUST return `nil` when no spec is registered or the spec does not persist visibility, and otherwise the storage's value (`nil` when never saved).
- **save-visibility**: `saveVisibility(_:for:)` MUST write the flag only when a spec is registered that persists visibility, and otherwise do nothing.
- **clear-visibility**: `clearVisibility(for:)` MUST remove the stored flag without consulting the spec.
- **visible-window-ids**: `visibleWindowIDs()` MUST return the storage's list of ids whose saved visibility is `true`.

### Default placement

- **default-position-screen**: Applying a default position MUST use the main screen's visible frame, falling back to the first screen, and MUST center geometrically when there are no screens.
- **geometric-center**: Geometric centering MUST set the window origin to `visible.origin + (visible.size - window.size) / 2` on each axis, keeping the window's size; with no screen at all it MUST fall back to the window's own `center()` placement.

### Screen-change handling

- **change-no-screens**: On a screen change with no screens, the handler MUST do nothing.
- **change-window-lookup**: The handler MUST snapshot the live windows once per event, key them by the id after the `wm_` identifier prefix, and consider every registered spec whose window is present, visible or hidden.
- **change-known-placement**: For a window with a placement under the current set, the handler MUST apply the resolved frame, for every kind of `ScreenChange`.
- **change-new-set-fallback**: For a `screenSetChanged` event where the window has no placement under the current set but has other placements, the handler MUST apply the relative-fallback frame and then save the window's frame.
- **change-reclamp**: Every other managed window (no persisted state, frame persistence off, or a non-set change with no placement) MUST keep its current frame pushed on screen through `validateFrame` on its best screen.
- **change-apply-only-real**: The handler MUST skip `setFrame` when the validated frame equals the window's current frame.
- **change-animate-visible**: The handler MUST animate the frame change only when the window is visible.
- **change-resave-by-delegate**: Apart from the new-set fallback, the handler MUST NOT save frames itself; re-saving after a reposition relies on the window controller's move/resize delegate hooks.

### Persistence durability

- **storage-default-backend**: The default `UserDefaultsWindowStateStorage` MUST store each id's state as JSON under `WindowState_<id>` and visibility as a `Bool` under `WindowVisible_<id>`, both qualified by `WindowStateNamespace`, so state survives app relaunch.
- **storage-failure-signal**: NEEDS REVIEW: Not implemented in source. `WindowStateStorage` has no error channel; the default backend returns `nil` for undecodable data (restore then applies the default frame and the next save overwrites the blob) and silently skips a write whose encoding fails, with no log. Settle by deciding whether load/save failures must be logged or surfaced to `WindowFrameManager`.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `screenProvider` | `ScreenProvider` | `RealScreenProvider()` | Source of live screens and the main screen. |
| `storage` | `WindowStateStorage` | `UserDefaultsWindowStateStorage()` | Persistence for per-window state and visibility. |
| `screenManager` | `ScreenManager` | none (required) | Supplies `currentSetID`, `knownSetIDs`, `maxSetAge`, `now()`, `touchCurrentSet()` and screen-change events. |
| `windowLister` | `@MainActor () -> [NSWindow]` (internal) | `{ NSApp?.windows ?? [] }` | Source of live windows for screen-change repositioning; injectable in tests. |
| `WindowSpec.minSize` / `defaultSize` / `defaultPosition` | `NSSize` / `NSSize` / `WindowPosition` | per spec | Sizing floor and default frame. |
| `WindowSpec.behavior` `.persistsFrame` | option bit | on (in `.default`) | Enables frame save/restore for the id. |
| `WindowSpec.behavior` `.persistsVisibility` | option bit | on (in `.default`) | Enables visibility save/load for the id. |
| `UserDefaultsWindowStateStorage.keyPrefix` | `String` | `"WindowState_"` | Key prefix for state blobs (namespaced by `WindowStateNamespace`). |
| `UserDefaultsWindowStateStorage.visibilityKeyPrefix` | `String` | `"WindowVisible_"` | Key prefix for visibility flags (namespaced by `WindowStateNamespace`). |
| `anchors` (`contentHuggingFrame`) | `FrameAnchors?` | `nil` | Anchors carried across steps of one resize gesture; `nil` picks them by nearest edge. |

