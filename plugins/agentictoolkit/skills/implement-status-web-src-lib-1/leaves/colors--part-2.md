<!-- leaf: implement-status-web-src-lib-1/colors--part-2 · source: status-web-src-lib-colors.md -->

# Status Web Colors — continued (part 2)

## Platform Notes

- **SwiftUI**: Model the tables as `[String: Color]` dictionaries or, better, as enums with a `color` property (`enum HealthStatus { case healthy, degraded, down, unknown }`) so lookups are total. Theme tokens map to named colors in an asset catalog or a shared `ShapeStyle` extension; `color-mix` translates to `Color.mix(with:by:in:)` (iOS 18 / macOS 15+) or `.opacity(_:)` for the mix-with-`transparent` tints. `envColor`/`envBadgeLabel` become static functions on an `Environment` type; a Swift dictionary has no prototype chain, so the inherited-key issue disappears.
- **Compose**: Hold tokens in a `MaterialTheme`-style `CompositionLocal` of a custom `Immutable` data class (`AptColors`); status tables become `when` expressions over enum classes. Tints are `color.copy(alpha = 0.06f)`; mixes into a background use `androidx.compose.ui.graphics.lerp(bg, gold, 0.08f)`. Kotlin `Map` lookups return `null` for missing keys, matching the JS `undefined`, and have no inherited keys.
- **React/Web**: Source platform. `packages/web/packages/status-web/src/lib/colors.ts` returns CSS strings consumed in inline `style` props, so resolution is deferred to the browser and theme switches apply without re-render. It depends on the host stylesheet defining `--color-apt-*` and on CSS `color-mix()` support. A safer port would use `Object.hasOwn` or a `Map` for the env lookups.
- **AppKit / UIKit**: Use `NSColor(named:)` / `UIColor(named:)` from an asset catalog with appearance variants for the tokens; tints via `withAlphaComponent(_:)`, mixes via `NSColor.blended(withFraction:of:)` (AppKit) or manual component interpolation (UIKit). Dynamic colors resolve per trait collection, which is the analogue of CSS variables re-resolving on theme change.
- **WinUI 3**: Put each token in a `ResourceDictionary` under `ThemeDictionaries` (`Default`/`Light`/`HighContrast`) as `SolidColorBrush` resources (`AptGreenBrush`, `AptGoldBrush`, …) and reference them with `{ThemeResource AptGoldBrush}` so they re-resolve on theme change like `var()`. There is no `color-mix`: precompute tints as brushes with `Opacity="0.06"` or as `Color` values with a scaled alpha channel, and blended surfaces (`amberBgDeep`) as separate theme resources or via a helper that interpolates `Windows.UI.Color` channels. Status tables become C# `enum`s with a `switch` expression returning a brush key, or a `FrozenDictionary<string, string>` (System.Collections.Frozen) of resource keys; `TryGetValue` replaces the `undefined` result, and C# dictionaries have no inherited-key hazard. `envBadgeLabel` becomes a static method using `ToUpperInvariant()` for unknowns. For code-behind lookups use `Application.Current.Resources["AptGoldBrush"]`; for binding, an `IValueConverter` that maps a status string to a brush.

## Design Decisions

**Decision**: Every color is a theme-token reference, never a hard-coded hex value.
**Rationale**: The authoring comment states the board "tracks the same theme as the rest of the suite" and that shade changes against the old bespoke values are intentional; ownership of values stays with `@agenticdevelopertoolkit/themes`.
**Approved**: pending

**Decision**: Alpha is applied with `color-mix(in srgb, <token> N%, transparent)` rather than `rgba()`.
**Rationale**: A `var()` token cannot take an alpha channel directly, and the comment names `color-mix` as "the form the UI checker accepts"; the percentages mirror the old `rgba` opacities.
**Approved**: pending

**Decision**: `DEPLOY_COLORS.unknown` is muted text, while `unknown` in the health and overall tables is amber.
**Rationale**: For deploys, `unknown` is an expired, unconfirmable in-flight phase, "an ABSENCE of a verdict, muted (never the amber of live progress)", matching `row-model`'s `stale` tone. The health and overall tables keep `unknown` at caution.
**Approved**: pending

**Decision**: Environment colors use the categorical `apt-cat-*` hues.
**Rationale**: They must read as "which env", never as a health signal, and must not collide with the platform badges, which use other `apt-cat-*` hues.
**Approved**: pending

**Decision**: Surface steps finer than the theme's three levels collapse onto the nearest token (`surfacePane` and `surfaceHover` share `surface-2`).
**Rationale**: The monitor had finer steps than the theme exposes; collapsing keeps every value theme-owned at the cost of a visible hover step.
**Approved**: pending

**Decision**: Only amber has a bright headline variant (`amberLight`).
**Rationale**: The theme exposes `gold-bright` but no bright green or red, so green and red headlines use `PALETTE.green` / `PALETTE.red` directly with "no redundant same-value alias".
**Approved**: pending

**Decision**: Env badge labels are four upper-case characters for known envs; unknown envs are upper-cased but not truncated.
**Rationale**: Four characters keep the env column narrow; unknowns stay recognizable rather than ambiguous.
**Approved**: pending

**Decision**: Shadows and the white ghost use literal `black` / `white`.
**Rationale**: The comment calls them theme-independent.
**Approved**: pending
