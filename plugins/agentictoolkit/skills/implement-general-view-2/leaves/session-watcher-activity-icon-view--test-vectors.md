<!-- leaf: implement-general-view-2/session-watcher-activity-icon-view--test-vectors · source: session-watcher-activity-icon-view.md -->

# SessionWatcherActivityIconView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| activity-icon-001 | fixed-glyph-size | Any constructed instance | Both `widthAnchor` and `heightAnchor` resolve to exactly 13pt |
| activity-icon-002 | horizontal-compression-resistance | Any constructed instance, placed in a horizontally-constrained stack view | The view's horizontal content-compression-resistance priority reads `.required`; it does not shrink below 13pt |
| activity-icon-003 | state-based-symbol-selection | `init(activity: .working, isSummarizing: true)` | The glyph is drawn from the `sparkles` symbol, not `arrow.triangle.2.circlepath` |
| activity-icon-003b | state-based-symbol-selection | `init(activity: .waiting, isSummarizing: false)` | The glyph is drawn from `exclamationmark.circle.fill` |
| activity-icon-003c | state-based-symbol-selection | `init(activity: .idle, isSummarizing: false)` | The glyph is drawn from `circle.fill` |
| activity-icon-003d | state-based-symbol-selection | `init(activity: .working, isSummarizing: false)` | The glyph is drawn from `arrow.triangle.2.circlepath` |
| activity-icon-004 | idle-visibility-suppression | `init(activity: .idle, isSummarizing: false)` | `isHidden == true` |
| activity-icon-004b | idle-visibility-suppression | `init(activity: .idle, isSummarizing: true)` | `isHidden == false` |
| activity-icon-005 | state-based-tint | `applyTheme(palette)` with `activity == .waiting, isSummarizing == false` | The glyph is filled with `palette.warningColor` |
| activity-icon-005b | state-based-tint | `applyTheme(palette)` with `activity == .idle, isSummarizing == false` | The glyph is filled with `palette.tertiaryTextColor` |
| activity-icon-005c | state-based-tint | `applyTheme(palette)` with `activity == .working, isSummarizing == false` | The glyph is filled with `palette.accentColor` |
| activity-icon-005d | state-based-tint | `applyTheme(palette)` with `isSummarizing == true` (any `activity`) | The glyph is filled with `palette.accentColor` |
| activity-icon-006 | pre-theme-tint-default | Newly constructed instance, `applyTheme` never called | The glyph is filled with `NSColor.tertiaryLabelColor` |
| activity-icon-007 | symbol-layer-distinction | `applyTheme(palette)` with `activity == .waiting` | Sampling the rendered raster at the glyph's center (the exclamation mark) yields a pixel outside the fill's solid color (e.g. transparent or antialiased against the surrounding fill), distinct from a sample taken on the surrounding ring — the tint did not collapse both layers into one flat silhouette |
| activity-icon-008 | unresolvable-symbol-fallback | The global/class-level `NSImage(systemSymbolName:accessibilityDescription:)` lookup intercepted (e.g. via method swizzling or an equivalent test double substituted for the system symbol lookup, since the source exposes no injectable seam for it) to return `nil` for the selected symbol name | `glyph.contents == nil` |
| activity-icon-009 | in-place-state-update | Existing instance, `update(activity: .waiting, isSummarizing: false)` called | The same instance now renders the waiting glyph; no new instance was created |
| activity-icon-010 | redundant-update-guard | Existing instance at `activity: .working, isSummarizing: false`, then `update(activity: .working, isSummarizing: false)` | No re-render, no `describeState()` call, and the running spin animation is left untouched (does not restart) |
| activity-icon-011 | animation-restart-on-change | Existing instance in a window at `activity: .idle, isSummarizing: false` (hidden), then `update(activity: .working, isSummarizing: false)` | `isHidden` becomes `false`; a new `rotationKey` animation is installed |
| activity-icon-012 | waiting-or-summarizing-pulse | Instance in a window, `update(activity: .waiting, isSummarizing: false)` | `glyph.animation(forKey: "session-activity-pulse")` is non-nil, opacity animates 1.0→0.25→1.0, 0.7s each way (1.4s full cycle), repeating |
| activity-icon-012b | waiting-or-summarizing-pulse | Instance in a window, `update(activity: .idle, isSummarizing: true)` | `glyph.animation(forKey: "session-activity-pulse")` is non-nil (the pulse fires for the summarizing-and-idle combination the same as any other summarizing case) |
| activity-icon-013 | working-state-spin | Instance in a window, `update(activity: .working, isSummarizing: false)` | `glyph.animation(forKey: "session-activity-rotation")` is non-nil, `transform.rotation.z` animates 0→−2π over 1.1s linear, repeating |
| activity-icon-014 | animation-install-idempotence | Instance already spinning (`working`), `startAnimation()` invoked again without an intervening `stopAnimation()` | `glyph.animation(forKey: "session-activity-rotation")` is unchanged (no duplicate animation added) |
| activity-icon-015 | off-window-animation-removal | Instance in a window and spinning (`working`), then removed from its superview (`window == nil`) | `glyph.animation(forKey: "session-activity-rotation")` becomes `nil` |
| activity-icon-016 | window-attach-animation-reinstall | Freshly constructed `activity: .working` instance, not yet in any window, then added to a window | The glyph re-renders and `glyph.animation(forKey: "session-activity-rotation")` becomes non-nil |
| activity-icon-017 | appearance-change-rerender | Instance on screen, `viewDidChangeEffectiveAppearance()` invoked (e.g. system switches light/dark) | `glyph.contents` is regenerated with a fill color equal to `tint.resolvedColor(in: newAppearance)`, not the color that had been resolved against the previous appearance |
| activity-icon-018 | display-scale-rerender | Instance moved to a window with a different `backingScaleFactor`, `viewDidChangeBackingProperties()` invoked | `glyph.contentsScale` matches the new window's `backingScaleFactor` |
| activity-icon-019 | glyph-bounds-layout | View resized, `layout()` invoked | `glyph.bounds == view.bounds`; `glyph.position == (bounds.midX, bounds.midY)`; no implicit layer animation plays for the change |
| activity-icon-020 | image-accessibility-role | Any constructed instance | `accessibilityRole() == .image`; `isAccessibilityElement() == true` |
| activity-icon-021 | state-based-label-and-tooltip | `init(activity: .waiting, isSummarizing: false)` | Accessibility label and `toolTip` both read `"Waiting for you"` |
| activity-icon-021b | state-based-label-and-tooltip | `init(activity: .working, isSummarizing: true)` | Accessibility label and `toolTip` both read `"Summarizing"` (summarizing overrides activity) |
| activity-icon-022 | state-based-accessibility-identifier | `init(activity: .idle, isSummarizing: false)` | `accessibilityIdentifier() == "session-panel.activity.idle"` |
| activity-icon-022b | state-based-accessibility-identifier | `init(activity: .idle, isSummarizing: true)` | `accessibilityIdentifier() == "session-panel.activity.summarizing"` |
| activity-icon-023 | programmatic-construction-only | `SessionWatcherActivityIconView(coder:)` invoked (e.g. nib/storyboard unarchiving) | Process traps with a fatal error |
