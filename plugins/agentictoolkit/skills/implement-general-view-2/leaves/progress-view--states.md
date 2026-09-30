<!-- leaf: implement-general-view-2/progress-view--states · source: progress-view.md -->

# ProgressView

## States

| State | Appearance change |
|-------|------------------|
| Default | Reflects `viewModel.progress` at construction time (**reflects-initial-progress-value**): a determinate bar if non-nil, an animating indeterminate bar if `nil`. `ProgressViewModel`'s `progress` parameter defaults to `nil`, so a `ProgressView` built from a default-valued view model starts indeterminate and animating. |
| Determinate | `progressIndicator.doubleValue` equals `viewModel.progress`; `isIndeterminate == false`; animation stopped; the bar shows the filled proportion of `doubleValue` against `NSProgressIndicator`'s default 0–100 range (see Configuration). |
| Indeterminate | `isIndeterminate == true`; `startAnimation(nil)` has been called, producing `NSProgressIndicator`'s default `.bar`-style indeterminate animation (a continuously animating bar, not a spinning wheel — `style` is never set away from its `.bar` default anywhere in source). |
| Pressed | Not applicable: `ProgressView` defines no target/action, gesture recognizer, or tracking area — it is a purely display-only, non-interactive view. |
| Disabled | Not implemented in `ProgressView`; the source never reads or sets `progressIndicator.isEnabled`. A caller may set it directly through the public `progressIndicator` property, at which point `NSProgressIndicator`'s native dimmed appearance applies. |
| Focused | Not applicable: the view never becomes key/first responder; the source overrides no responder-chain behavior, and `NSView`'s own default (`acceptsFirstResponder == false`) applies unmodified. |
| Loading | This is the Indeterminate state above (`viewModel.progress == nil`) — `ProgressView` has no separate loading concept beyond it. |
