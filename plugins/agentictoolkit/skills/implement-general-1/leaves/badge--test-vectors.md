<!-- leaf: implement-general-1/badge--test-vectors · source: badge.md -->

# Badge

**Rules** (cite as `implement-general-1/badge--test-vectors#<slug>`):

- `has-test-vector-constraining-what-colors-caller` SHOULD — prefers-semantic-palette-colors has no test vector: it is a SHOULD constraining what colors a caller chooses to pass …

## Conformance Test Vectors

Vectors that reference dynamic system colors (`.systemGreen`, `.systemRed`,
`.systemGray`, `.systemBlue`) assume tests run under a fixed `NSAppearance`
(e.g. `.aqua`), since these colors resolve to different `CGColor` values under
light vs. dark appearance.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| badge-001 | renders-rounded-pill | Any `init(text:color:)` call | The badge's layer has `cornerRadius == 5` |
| badge-002 | displays-caller-text | `init(text: "dev", color: .systemGreen)` | The label's `stringValue` is exactly `"dev"` |
| badge-003 | defaults-to-filled-style | `init(text: "dev", color: .systemGreen)` (no `style`), under a fixed `NSAppearance` | Background is `.systemGreen`; border width is 0 |
| badge-004 | paints-filled-background | `init(text: "dev", color: .systemGreen, style: .filled)`, under a fixed `NSAppearance` | `layer.backgroundColor == NSColor.systemGreen.cgColor`; `layer.borderWidth == 0` |
| badge-005 | computes-contrasting-text-color | `color` = light gray, RGB (230, 230, 230) i.e. (0.902, 0.902, 0.902) in sRGB 0–1 — luminance ≈ 0.902 | Label text color is black |
| badge-005b | computes-contrasting-text-color | `color` = dark navy, RGB (0, 0, 128) i.e. (0, 0, 0.502) in sRGB 0–1 — luminance ≈ 0.057 | Label text color is white |
| badge-005c | computes-contrasting-text-color | `color` = mid-gray, RGB (153, 153, 153) i.e. (0.6, 0.6, 0.6) in sRGB 0–1 — luminance exactly 0.6 (boundary: the comparison is `>` 0.6, not `>=`) | Label text color is white |
| badge-006 | falls-back-to-white-on-unconvertible-color | `color` for which `usingColorSpace(.sRGB)` returns `nil` (e.g. a pattern-image `NSColor`), `style: .filled` | Label text color is white |
| badge-007 | paints-outlined-appearance | `init(text: "3", color: .systemRed, style: .outlined)`, under a fixed `NSAppearance` | `layer.backgroundColor == NSColor.clear.cgColor`; `layer.borderWidth == 1`; `layer.borderColor == NSColor.systemRed.cgColor`; label text color equals `.systemRed` |
| badge-008 | supports-in-place-restyle | Existing badge, then `update(text: "stopped", color: .systemGray, style: .outlined)`, under a fixed `NSAppearance` | Label reads `"stopped"`; background/border/text reflect `.outlined` with `.systemGray` |
| badge-009 | resets-style-to-filled-by-default-on-update | Badge currently `.outlined`, then `update(text: "3", color: .systemBlue)` (no `style`) | Badge renders `.filled` (solid `.systemBlue` background, border width 0), not `.outlined` |
| badge-010 | applies-fixed-content-padding | Any badge | Label's leading/trailing constraints resolve to 6pt insets; top/bottom resolve to 2pt insets |
| badge-011 | centers-label-text | Any badge | `label.alignment == .center` |
| badge-012 | tracks-theme-caption-font | Theme change while a badge is on screen | Label's font updates to the new theme's `.caption` font |
| badge-013 | sizes-to-fit-content | Badge placed with no explicit width constraint | Badge's fitting width equals the label's intrinsic width plus 12pt (6pt × 2) horizontal padding; badge does not stretch to fill a wider container |
| badge-014 | confines-mutation-to-main-actor | Attempt to call `Badge.init`/`update` from a non-main-actor context | Code does not compile (Swift concurrency checker rejects the call) |
| badge-015 | rejects-storyboard-instantiation | `Badge(coder:)` invoked (e.g. via nib/storyboard unarchiving) | Process traps with a fatal error |

`badge-014` is a static, compile-time check (the Swift concurrency checker
rejects the offending code at build time), not a vector observed by running
the program; a port on a platform without an equivalent compile-time
enforcement should verify this as a build-verification note rather than a
runtime test.

`prefers-semantic-palette-colors` has no test vector: it is a SHOULD
constraining what colors a caller chooses to pass in, not an observable
behavior of `Badge` itself, so no component-level test can verify it (see
Design Decisions).
