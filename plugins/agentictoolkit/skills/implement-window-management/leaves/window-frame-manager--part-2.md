<!-- leaf: implement-window-management/window-frame-manager--part-2 · source: window-management-window-frame-manager.md -->

# WindowFrameManager — continued (part 2)

**Rules** (cite as `implement-window-management/window-frame-manager--part-2#<slug>`):

- `main-actor-isolation` MUST
- `storage-main-actor` MUST
- `sendable-value-types` MUST
- `non-sendable-screen-types` MUST
- `sole-writer-precondition` MUST
- `screen-observer-registration` MUST
- `start-observing-delegates` MUST
- `spec-accessor` MUST
- `window-placement-fields` MUST
- `persisted-state-shape` MUST
- `persisted-state-encode` MUST
- `persisted-state-decode-v2` MUST
- `persisted-state-decode-v1` MUST
- `persisted-state-decode-degrade` MUST
- `legacy-state-fields` MUST
- `fingerprint-fields` MUST
- `fingerprint-from-screen` MUST
- `screen-info-contract` MUST
- `screen-provider-contract` MUST
- `window-position-values` MUST
- `frame-anchors-shape` MUST
- `clamped-length-rule` MUST
- `min-size-wins-everywhere` MUST
- `proportional-position` MUST
- `absolute-frame` MUST
- `default-frame` MUST
- `top-left-offset` MUST
- `frame-from-top-left` MUST
- `relative-position` MUST
- `frame-from-relative` MUST
- `validate-frame-size` MUST
- `validate-frame-push` MUST
- `hug-per-axis` MUST
- `hug-nearest-edge` MUST
- `hug-held-anchor` MUST
- `hug-end-anchor-offset` MUST
- `hug-push-on-screen` MUST
- `hug-length-clamp` MUST
- `match-quality-order` MUST
- `match-uuid-tier` MUST
- `match-name-tier` MUST
- `match-position-tier` MUST
- `match-best` MUST
- `register-spec` MUST

## Behavioral Requirements

### Isolation and ownership

- **main-actor-isolation**: `WindowFrameManager` MUST be `@MainActor`-isolated; every public operation, the screen-change handler, and the injected `windowLister` closure run on the main actor.
- **storage-main-actor**: The `WindowStateStorage` protocol MUST be `@MainActor`, so storage backends are only called from the main actor.
- **sendable-value-types**: `FrameAnchor`, `FrameAnchors`, `WindowPlacement`, `PersistedWindowState`, `LegacyPersistedWindowState`, `ScreenFingerprint`, `WindowPosition` and `ScreenMatcher.MatchQuality` MUST be `Sendable` value types.
- **non-sendable-screen-types**: `ScreenInfo`, `ScreenProvider`, `RealScreenInfo`, `RealScreenProvider` and `ScreenMatcher.ScreenMatch` MUST remain non-`Sendable`, so the compiler keeps them in the caller's isolation domain.
- **sole-writer-precondition**: Callers MUST ensure this process is the only writer of a given window id's persisted state; the `stateCache` doc comment states the write-through cache is "safe because this process is the sole writer of a given id's state", and the manager never re-reads storage for an id it has cached.
- **screen-observer-registration**: `init` MUST register one observer with the injected `ScreenManager` that forwards each `ScreenChange` to the screen-change handler through a weak reference to the manager.
- **start-observing-delegates**: `startObservingScreenChanges()` MUST delegate to `ScreenManager.startObservingScreenChanges()` and add no registration of its own.
- **spec-accessor**: `SingleWindowController.windowSpec` MUST read and write the spec registered under the controller's `windowID` in `WindowManager.shared.frames`.

### Data shapes

- **window-placement-fields**: `WindowPlacement` MUST be a `Codable`, `Equatable` value holding `screenFingerprint`, `topLeftX`, `topLeftY` (offset from the screen's visible-frame top-left, y pointing down), `width`, `height`, `relativeX`, `relativeY` (0...1 fractions of travel, 0 = left/top) and `savedAt: Date`, all immutable.
- **persisted-state-shape**: `PersistedWindowState` MUST hold `placements: [String: WindowPlacement]` keyed by screen-set id, and a read-only `legacy: LegacyPersistedWindowState?`.
- **persisted-state-encode**: Encoding `PersistedWindowState` MUST write only the `placements` key and MUST NOT encode `legacy`.
- **persisted-state-decode-v2**: Decoding MUST read `placements` when the key is present and non-null, with `legacy` set to `nil`.
- **persisted-state-decode-v1**: When `placements` is absent or null and the payload decodes as `LegacyPersistedWindowState`, decoding MUST produce empty `placements` and that value in `legacy`.
- **persisted-state-decode-degrade**: When the payload has neither a usable `placements` key nor a decodable v1 record (for example `{}`, `{"placements": null}` or `{"unrelated": 1}`), decoding MUST produce empty `placements` and `nil` `legacy` rather than throwing.
- **legacy-state-fields**: `LegacyPersistedWindowState` MUST hold `proportionalX`, `proportionalY` (bottom-left-anchored fractions of travel), `width`, `height`, `screenFingerprint` and `savedAt`.
- **fingerprint-fields**: `ScreenFingerprint` MUST be a `Codable`, `Equatable` value holding `displayUUID: String?`, `localizedName: String?`, `resolutionWidth`, `resolutionHeight` and `isMain`.
- **fingerprint-from-screen**: `ScreenFingerprint.from(_:)` MUST take `displayUUID` from the display's CoreGraphics UUID (nil when the screen number or UUID is unavailable), `localizedName` from the screen, the resolution from the screen's full `frame` (not its visible frame), and `isMain` from whether the screen equals the current main screen.
- **screen-info-contract**: `ScreenInfo` MUST expose `frame`, `visibleFrame`, `fingerprint` and `backingScaleFactor`; conformers that do not supply `backingScaleFactor` MUST report `2`.
- **screen-provider-contract**: `ScreenProvider` MUST expose `screens: [ScreenInfo]` and `mainScreen: ScreenInfo?`; `RealScreenProvider` MUST map `NSScreen.screens` and `NSScreen.main`.
- **window-position-values**: `WindowPosition` MUST map `center` to (0.5, 0.5), `topRight` to (0.85, 0.85), and `custom(horizontal:vertical:)` to its two values, as bottom-left-anchored fractions of travel (0 = left/bottom, 1 = right/top).
- **frame-anchors-shape**: `FrameAnchor` MUST have exactly the cases `start` (left or top) and `end` (right or bottom); `FrameAnchors` MUST hold one `horizontal` and one `vertical` anchor.

### Frame math (FrameCalculator)

- **clamped-length-rule**: `clampedLength(_:min:visible:)` MUST return `min(max(desired, minLength), max(visibleLength, minLength))`, so a length is never below `minLength`, never past the visible length, and `minLength` wins when the two disagree.
- **min-size-wins-everywhere**: `absoluteFrame`, `frame(relativePosition:...)`, `contentHuggingFrame` and `validateFrame` MUST all size each axis with `clampedLength`, so a minimum larger than the screen is kept and the window overhangs.
- **proportional-position**: `proportionalPosition` MUST return `(origin - visibleOrigin) / (visibleLength - windowLength)` per axis, bottom-left anchored, clamped to -0.1...1.1, and `0.5` on an axis with no positive travel.
- **absolute-frame**: `absoluteFrame` MUST clamp width and height with `clampedLength`, then set each origin to `visibleOrigin + proportion * max(visibleLength - clampedLength, 0)`.
- **default-frame**: `defaultFrame(spec:screenVisibleFrame:)` MUST equal `absoluteFrame` with the spec's `defaultPosition` fractions, `defaultSize` and `minSize`.
- **top-left-offset**: `topLeftOffset` MUST return `(window.minX - visible.minX, visible.maxY - window.maxY)`.
- **frame-from-top-left**: `frame(topLeftOffset:size:screenVisibleFrame:)` MUST return a frame at `x = visible.minX + offset.x`, `y = visible.maxY - offset.y - size.height` with the given size unclamped.
- **relative-position**: `relativePosition` MUST return the top-left offset divided by the travel (`visibleLength - windowLength`) per axis, clamped to 0...1, and `0.5` on an axis with no positive travel.
- **frame-from-relative**: `frame(relativePosition:size:screenVisibleFrame:minSize:)` MUST clamp the size with `clampedLength`, then place the top-left at `relative * max(visibleLength - clampedLength, 0)` from the visible top-left.
- **validate-frame-size**: `validateFrame` MUST clamp width and height with `clampedLength`.
- **validate-frame-push**: `validateFrame` MUST then push the origin inside the visible frame in this order: right edge, left edge, top edge, bottom edge; a window wider or taller than the visible frame therefore ends flush with the left and bottom edges.
- **hug-per-axis**: `contentHuggingFrame` MUST solve each axis independently in top-left user coordinates through the same one-axis rule (`fittedAxis`) and return the fitted frame with the anchors it used.
- **hug-nearest-edge**: With no anchor supplied, an axis MUST hold its `end` edge when the end gap is strictly smaller than the start gap, and its `start` edge otherwise (ties, including a window filling the axis, keep `start`).
- **hug-held-anchor**: When `anchors` is supplied, `contentHuggingFrame` MUST use those anchors unchanged instead of re-reading them from the frame, and MUST return them.
- **hug-end-anchor-offset**: Holding `end` MUST keep `offset + length` fixed before on-screen correction; holding `start` MUST keep `offset` fixed.
- **hug-push-on-screen**: After anchoring, the axis offset MUST be clamped to at most `visibleLength - newLength`, then to at least `0`, so a window that cannot fit ends flush with the start (left or top) edge.
- **hug-length-clamp**: The new axis length MUST be `clampedLength(desired, min: minLength, visible: visibleLength)`.

### Screen matching (ScreenMatcher)

- **match-quality-order**: `MatchQuality` MUST order `positionOnly` (1) < `nameOnly` (2) < `uuidResChanged` (3) < `exact` (4).
- **match-uuid-tier**: A screen whose `displayUUID` equals the saved non-nil `displayUUID` MUST match as `exact` when both resolution components differ by less than 1 point, and as `uuidResChanged` otherwise; that screen MUST NOT be considered for a lower tier.
- **match-name-tier**: A screen not matched by UUID whose `localizedName` equals the saved non-nil `localizedName` MUST match as `nameOnly`, even when both UUIDs are present and differ.
- **match-position-tier**: A screen not matched by UUID or name MUST match as `positionOnly` when both the saved and current fingerprints have `isMain` true.
- **match-best**: `findBestMatch` MUST return the candidate with the highest quality, the first such candidate in `screens` order on a tie, and `nil` when no screen matches.

### Registration

- **register-spec**: `register(id:spec:)` MUST store the spec under the id, replacing any spec previously registered under it.

