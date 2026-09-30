<!-- leaf: implement-status-web-src-lib-1/deploy-display--edge-cases · source: status-web-src-lib-deploy-display.md -->

# Deploy Display

**Rules** (cite as `implement-status-web-src-lib-1/deploy-display--edge-cases#<slug>`):

- `empty-platform-string` MUST — platformGlyph("") MUST return ◆, platformColor("") MUST return the muted token, and platformLabel("") and …
- `empty-status-string` MUST — deployStatusColor("") MUST return the amber canceled color, and deployStatusLabel("") MUST return "".
- `case-mismatch` MUST — A key that differs only in case, such as Vercel or SUCCESS, MUST miss every map and take the fallback path. There is no …
- `unknown-platform` MUST — A platform the module does not know MUST still render. It gets the ◆ glyph, the muted color, and its own name …
- `unknown-status` MUST — An unrecognised status MUST render amber (the canceled color), and its label MUST be the raw string. This differs from …
- `glitchtip-partial-registration` MUST — glitchtip has a glyph and a color but no label entry and no short label. Both label functions MUST yield GLITCHTIP …
- `shared-hues` MUST — crunchy/http and glitchtip/cloudflare-pages MUST return identical colors. The source comment says the glyph and label …
- `glyph-string-length` MUST — The glitchtip glyph MUST be two UTF-16 code units long. A port that measures or truncates glyphs by code-unit count …

## Edge Cases

- **Empty platform string**: `platformGlyph("")` MUST return `◆`, `platformColor("")` MUST return the muted token, and `platformLabel("")` and `platformLabelShort("")` MUST return `""`. No function validates or rejects the empty string.
- **Empty status string**: `deployStatusColor("")` MUST return the amber `canceled` color, and `deployStatusLabel("")` MUST return `""`.
- **Case mismatch**: A key that differs only in case, such as `Vercel` or `SUCCESS`, MUST miss every map and take the fallback path. There is no normalisation.
- **Unknown platform**: A platform the module does not know MUST still render. It gets the `◆` glyph, the muted color, and its own name upper-cased as the label. The module MUST NOT throw.
- **Unknown status**: An unrecognised status MUST render amber (the `canceled` color), and its label MUST be the raw string. This differs from the known `unknown` status, which renders muted with the label `outcome unknown`.
- **glitchtip partial registration**: `glitchtip` has a glyph and a color but no label entry and no short label. Both label functions MUST yield `GLITCHTIP` through the upper-case fallback.
- **Shared hues**: `crunchy`/`http` and `glitchtip`/`cloudflare-pages` MUST return identical colors. The source comment says the glyph and label disambiguate them, and glitchtip rows (error incidents) and cloudflare rows (deploys) never appear in the same list.
- **Glyph string length**: The `glitchtip` glyph MUST be two UTF-16 code units long. A port that measures or truncates glyphs by code-unit count MUST keep the variation selector.
- **Inherited object keys**: Inputs such as `constructor`, `toString` or `__proto__` currently return non-string values from the map lookups. See prototype-key-lookup.
- **Concurrent calls**: Not applicable. The functions are pure and run on the single JavaScript thread.
- **Error states, offline, timeouts, cancellation**: Not applicable. The module performs no I/O, has no dependency that can fail, and cannot be cancelled or time out.
