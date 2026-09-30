<!-- leaf: implement-status-web-src-lib-1/deploy-display--part-2 · source: status-web-src-lib-deploy-display.md -->

# Deploy Display — continued (part 2)

## Platform Notes

- **SwiftUI**: Port as a caseless `enum DeployDisplay` namespace of `static func`s, or as computed properties on a `String`-backed `Platform` enum with an `.unknown(String)` case. Use `[String: String]` dictionaries with `?? fallback`. Swift dictionaries have no prototype chain, so inherited keys (prototype-key-lookup) fall back normally. The theme tokens become `Color` assets or a theme struct. Put the U+26A0 U+FE0E glyph in a `Text` literal as `"\u{26A0}\u{FE0E}"`. `String.uppercased()` matches the fallback. Mark the namespace `Sendable` (it is, being stateless).
- **Compose**: Use a Kotlin `object DeployDisplay` with `mapOf(...)` lookups and `?:` fallbacks, and `uppercase()` (locale-invariant) for the label fallback. Colors map to `MaterialTheme`/custom theme `Color` values rather than CSS vars. Kotlin maps have no inherited keys.
- **React/Web**: This is the source, `src/lib/deploy-display.ts`. The colors are CSS `var(--color-apt-*)` strings consumed through inline `style` or `color-mix` in components. Glyphs are rendered as text, often inside `aria-hidden` spans by the callers. Lookups use plain object literals with `??`. A `Map` or `Object.hasOwn` check would make inherited keys fall back (prototype-key-lookup).
- **AppKit / UIKit**: Use the same pure Swift namespace as the SwiftUI port, returning `NSColor`/`UIColor` from a theme type. Nothing is UI-bound, so the code belongs in a shared framework target.
- **WinUI 3**: Port as a `public static class DeployDisplay` in C#. Hold each map as a `static readonly FrozenDictionary<string, string>` (or `IReadOnlyDictionary<string, string>`) with `StringComparer.Ordinal`, and use `TryGetValue` for the fallback. This rules out the inherited-key issue. Return `ToUpperInvariant()` for unknown labels. Colors cannot be CSS vars, so return a theme resource key (for example `"AptCatOrangeBrush"`) and resolve it with `Application.Current.Resources[key]` in a `ThemeResource`-aware `IValueConverter`. That way light/dark theme switches retarget through `ThemeDictionaries`. Model `DeployStatus` as an `enum` with a `JsonStringEnumConverter` for `System.Text.Json`, and keep a `string` overload for the pass-through label and the amber fallback. Render the glitchtip glyph as `"⚠︎"` in a `TextBlock` with `FontFamily="Segoe UI Symbol"` so that Segoe UI Emoji does not take the character. The functions are synchronous: no `Task`, `ObservableCollection` or `INotifyPropertyChanged`. The view model that binds a row raises property change for its own status field.

## Design Decisions

**Decision**: One module owns the full platform taxonomy (glyph, color, label, short label).
**Rationale**: The header comment says "adding a platform is a single edit here", so every component renders platforms consistently and no component keeps its own table.
**Approved**: pending

**Decision**: Platform colors use categorical theme hues kept clear of the three environment hues.
**Rationale**: A row can show both an env badge and a platform badge. Sharing a hue would make one read as the other. The categorical palette is fully allocated, so `crunchy` reuses `http`'s teal and `glitchtip` reuses Cloudflare's orange.
**Approved**: pending

**Decision**: `glitchtip` takes orange rather than another reused hue.
**Rationale**: The source comment says orange is the hue that reads as a warning. Glitchtip rows (error incidents) and Cloudflare rows (deploys) never appear in the same list, so the glyph and label disambiguate them.
**Approved**: pending

**Decision**: The glitchtip glyph carries VARIATION SELECTOR-15.
**Rationale**: Without it, macOS and iOS render U+26A0 as a full-colour, double-width emoji beside six monochrome glyphs.
**Approved**: pending

**Decision**: `unknown` status is labelled `outcome unknown` and colored muted.
**Rationale**: It marks an in-flight phase the backend expired without confirmation, which is the absence of a verdict. Echoing the raw enum or using the amber of live progress would imply a claim the data cannot back.
**Approved**: pending

**Decision**: Unrecognised statuses fall back to the `canceled` color (amber), and unrecognised platforms fall back to the muted color, `◆` and the upper-cased name.
**Rationale**: The source chooses to render something for any input rather than throw. The status fallback reuses an existing entry instead of a separate token. As a result an unknown status reads amber, while the known `unknown` status reads muted.
**Approved**: pending

**Decision**: `failed` is the only upper-case status label.
**Rationale**: The source returns `FAILED` while every other label is lower case, which makes a failure stand out in a list.
**Approved**: pending
