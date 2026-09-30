<!-- leaf: implement-status-web-src-lib-2/status-sublabel--edge-cases · source: status-web-src-lib-status-sublabel.md -->

# Status Sublabel

**Rules** (cite as `implement-status-web-src-lib-2/status-sublabel--edge-cases#<slug>`):

- `empty-problems-with-a-non-ok-state` MUST — The function MUST return "". BigIndicator renders the sublabel only when it is truthy, so the caption disappears. The …
- `non-empty-problems-with-state-ok` MUST — The problems MUST be ignored, and the clear-board line MUST be returned.
- `zero-services-while-ok` MUST — buildSublabel("ok", 0, 0, []) MUST return "0/0 endpoints healthy · no failed builds". The function does not treat …
- `healthycount-greater-than-serviceslength` MUST — The function MUST take the "monitored" branch. It never prints an impossible fraction.
- `negative-fractional-or-nan-counts` MUST — They are interpolated with default number-to-string conversion (e.g. "NaN endpoints monitored · no failed builds"), and …
- `unknown-status-word` MUST — The row MUST still be counted and rendered verbatim, so the breakdown keeps its sum-to-count guarantee.
- `empty-string-status-word` MUST — It is an unmapped word and MUST render as ${n} (count followed by a trailing space) in the unmapped section.
- `status-word-differing-only-by-case-or-whitespace` MUST — It MUST be treated as a distinct, unmapped word (e.g. "Down" or "down ").

## Edge Cases

- **Empty problems with a non-ok state**: The function MUST return `""`. `BigIndicator` renders the sublabel only when it is truthy, so the caption disappears. The module itself does not guard this pairing.
- **Non-empty problems with `state === "ok"`**: The problems MUST be ignored, and the clear-board line MUST be returned.
- **Zero services while ok**: `buildSublabel("ok", 0, 0, [])` MUST return `"0/0 endpoints healthy · no failed builds"`. The function does not treat "monitoring nothing" as blindness. `OverviewTab` handles that case with its `store.blind` panel, so this string does not reach the screen there.
- **`healthyCount` greater than `servicesLength`**: The function MUST take the "monitored" branch. It never prints an impossible fraction.
- **Negative, fractional or `NaN` counts**: They are interpolated with default number-to-string conversion (e.g. `"NaN endpoints monitored · no failed builds"`), and the function MUST NOT throw. `NaN === NaN` is false, so `NaN` inputs MUST take the "monitored" branch. The caller derives both counts from array lengths, which makes this a typed caller precondition.
- **Unknown status word**: The row MUST still be counted and rendered verbatim, so the breakdown keeps its sum-to-count guarantee.
- **Empty-string status word**: It is an unmapped word and MUST render as `` `${n} ` `` (count followed by a trailing space) in the unmapped section.
- **Status word differing only by case or whitespace**: It MUST be treated as a distinct, unmapped word (e.g. `"Down"` or `"down "`).
- **Large counts**: The count is interpolated as-is. Every value other than exactly 1 takes the plural suffix, including 0, which cannot occur because zero-count groups are skipped.
- **Concurrent access**: Not applicable. The function is stateless and runs on single-threaded JavaScript. `SUBLABEL_PHRASE` is a module constant that is never written.
- **Error states and offline**: Not applicable. The function performs no I/O. A missing or stale board is handled by `OverviewTab`'s early returns before `buildSublabel` is called.
