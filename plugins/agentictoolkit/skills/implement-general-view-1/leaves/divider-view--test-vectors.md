<!-- leaf: implement-general-view-1/divider-view--test-vectors · source: divider-view.md -->

# Divider View

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| divider-view-001 | confines-to-main-actor | Attempt to construct or mutate a `DividerView` from off the main actor | Static/compile-time check, not executable at runtime: the compiler rejects the call under Swift's `@MainActor` isolation checking |
| divider-view-002 | disables-autoresizing-mask-translation | Any initialized `DividerView` | `view.translatesAutoresizingMaskIntoConstraints == false` |
| divider-view-003 | enables-layer-backing | Any initialized `DividerView` | `view.wantsLayer == true` and `view.layer` is non-nil |
| divider-view-004 | constrains-height-to-divider-thickness | Any initialized `DividerView`, laid out in a window | The view's active height constraint resolves to `1.0` (`SettingsLayout.default[.dividerThickness]`) |
| divider-view-005 | ignores-explicit-frame | Construct via `DividerView(frame: NSRect(x: 10, y: 10, width: 200, height: 50))` | `view.frame == .zero` immediately after `init` returns |
| divider-view-006 | convenience-init-uses-zero-frame | Construct via `DividerView()` | `view.frame == .zero`, the height constraint's constant equals `1.0`, and `view.wantsLayer == true` |
| divider-view-007 | applies-divider-color-on-init | Construct a `DividerView` while a known palette is active, before adding it to any window | `view.layer?.backgroundColor == palette.dividerColor.cgColor` immediately after `init` returns |
| divider-view-008 | resolves-color-through-nearest-theme-scope | Add a `DividerView` as a descendant of a view conforming to `ThemeScopeProviding` whose scope's palette differs from `ThemeScope.app`'s | The divider's applied color matches the ancestor scope's `palette.dividerColor`, not `ThemeScope.app`'s |
| divider-view-009 | reapplies-divider-color-on-theme-change | Construct a `DividerView`, switch the active theme, then post `ThemeManager.didChangeNotification` | `view.layer?.backgroundColor` updates to the new theme's `dividerColor` |
| divider-view-010 | reapplies-divider-color-on-own-scope-change | Construct a `DividerView` resolved to scope A; change scope A's underlying theme/palette to one whose `dividerColor` differs from its previous value, then post `ThemeScope.didChangeNotification` with `object` set to scope A | `view.layer?.backgroundColor` updates to scope A's new `dividerColor` |
| divider-view-011 | ignores-other-scope-change-notifications | Construct a `DividerView` resolved to scope A; post `ThemeScope.didChangeNotification` with `object` set to a different scope B | `view.layer?.backgroundColor` does not change |
| divider-view-012 | retains-theme-observer-for-view-lifetime | Construct a `DividerView`, keep only the view (no separate reference to any observer), then post `ThemeManager.didChangeNotification` | `view.layer?.backgroundColor` still updates, showing the observer's subscriptions survived |
| divider-view-013 | reapplies-divider-color-on-layer-update | Construct a `DividerView`, swap the ancestor scope's theme/palette to a different `dividerColor` without posting any notification, then invoke `updateLayer()` directly (e.g. via `setNeedsDisplay` + a display pass, or a direct call) | `view.layer?.backgroundColor` matches the new `dividerColor` after `updateLayer()` runs |
| divider-view-014 | rejects-coder-initializer | Construct via `DividerView(coder:)` with any `NSCoder` | Execution traps via `fatalError` with message `init(coder:) has not been implemented` |
| divider-view-015 | conforms-to-settings-view-protocol | Any initialized `DividerView` | `view is SettingsViewProtocol` is `true` |
| divider-view-016 | ignores-settings-layout-changes | Construct a `DividerView`, add it to a window, then mutate `SettingsLayout.default`'s `.dividerThickness` value | The view's existing height constraint constant remains unchanged at the value read during `init`; it does not update to the new value |
