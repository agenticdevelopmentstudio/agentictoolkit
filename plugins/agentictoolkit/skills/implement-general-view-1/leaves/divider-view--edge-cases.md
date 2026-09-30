<!-- leaf: implement-general-view-1/divider-view--edge-cases · source: divider-view.md -->

# Divider View

## Edge Cases

- **Null/empty input**: Not applicable — `DividerView`'s only public initializer, `convenience init()`, takes no parameters; the inherited `init(frame:)` parameter is accepted but discarded (see **ignores-explicit-frame**), so there is no caller-supplied value to be null or empty.
- **Boundary values**: `SettingsLayout.default[.dividerThickness]` (1.0pt) is read exactly once, into an activated `NSLayoutConstraint`, at `init` time. `SettingsLayout` is `Observable`/`@Published`, but `DividerView` never subscribes to it, so if a caller mutates `SettingsLayout.default`'s underlying value after a `DividerView` already exists, that instance's height constraint does not update — it stays at whatever `.dividerThickness` was when it was constructed (see **ignores-settings-layout-changes**). This staleness is a genuine, source-grounded limitation, also recorded in Design Decisions.
- **Concurrent access**: Not applicable — the class is declared `@MainActor`, so construction and all four color-repaint paths are serialized to the main actor by the Swift compiler.
- **Error states**: Not applicable — `DividerView` has no dependency on network, database, or file-system access, and the source shows no error path of any kind.
- **Offline/disconnected state**: Not applicable — `DividerView` performs no networking.
- **No `ThemeManager` available**: `ThemeScope.palette` (which every repaint path reads through, directly or via `ThemePaletteObserver`) falls back to `SemanticPalette(theme: BuiltInThemes.solarizedDark)` when `ThemeManager.shared` is `nil` (e.g. a preview or a unit test with no app host) — `DividerView` paints with that fallback's divider color rather than crashing or leaving its layer transparent.
- **No `ThemeScopeProviding` ancestor**: `resolvedThemeScope`'s superview walk finds no ancestor declaring a scope and falls back to `ThemeScope.app`, so `DividerView` paints with the app-wide palette rather than failing to resolve a color.
