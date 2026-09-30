<!-- leaf: implement-status-web-src-lib-2/slug--edge-cases · source: status-web-src-lib-slug.md -->

# Status Web Slug

**Rules** (cite as `implement-status-web-src-lib-2/slug--edge-cases#<slug>`):

- `empty-or-whitespace-only-input` MUST — The function MUST return "". In ConfigPanel.tsx this means a group whose name and slug are both blank is sent with …
- `input-with-no-ascii-alphanumerics` MUST (`"日本"`, `"🚀"`, `"!!!"`) — The function MUST return "". Non-Latin names produce no slug.
- `accented-latin-letters` MUST (`"Ünïcode"`) — Each accented letter MUST be treated as a separator, so "Ünïcode" becomes "n-code". The function does no …
- `case-mappings-that-change-length` MUST — Lower-casing happens before filtering, so a character whose lower-case form includes ASCII letters keeps them. The …
- `distinct-names-that-collapse-together` MUST — Two group names such as "Ops Team" and "ops-team" MUST produce the same slug (no-uniqueness). The backend's unique slug …

## Edge Cases

- **Empty or whitespace-only input**: The function MUST return `""`. In `ConfigPanel.tsx` this means a group whose name and slug are both blank is sent with `slug: ""`. Whether the backend accepts that is up to status-server, not this module.
- **Input with no ASCII alphanumerics** (`"日本"`, `"🚀"`, `"!!!"`): The function MUST return `""`. Non-Latin names produce no slug.
- **Accented Latin letters** (`"Ünïcode"`): Each accented letter MUST be treated as a separator, so `"Ünïcode"` becomes `"n-code"`. The function does no transliteration or Unicode normalization.
- **Case mappings that change length**: Lower-casing happens before filtering, so a character whose lower-case form includes ASCII letters keeps them. The Kelvin sign U+212A lower-cases to ASCII `k`, and `İ` lower-cases to `i` plus a combining dot, which then acts as a separator (`İx` becomes `i-x`). The function MUST produce whatever the locale-independent `toLowerCase` followed by the ASCII filter gives.
- **Distinct names that collapse together**: Two group names such as `"Ops Team"` and `"ops-team"` MUST produce the same slug (no-uniqueness). The backend's unique slug index decides which write wins. The board surfaces the backend's error, and this module adds no suffix or retry.
- **Typed group slug**: `ConfigPanel.tsx` sends a non-blank typed slug trimmed but not passed through `slugify`. The shared form applies only to the default. This belongs to the caller, not to this module.
- **Very long input**: No length cap is applied. The output is never longer than the input.
- **Concurrent access**: Not applicable. The function is synchronous and pure on single-threaded JavaScript.
- **Error states and offline**: Not applicable. The module does no I/O, so no dependency can fail and connectivity does not matter.
