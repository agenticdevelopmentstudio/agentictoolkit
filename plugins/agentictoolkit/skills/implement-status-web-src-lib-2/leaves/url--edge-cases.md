<!-- leaf: implement-status-web-src-lib-2/url--edge-cases · source: status-web-src-lib-url.md -->

# Status Web URL Host

**Rules** (cite as `implement-status-web-src-lib-2/url--edge-cases#<slug>`):

- `empty-string` MUST — new URL("") throws, so the function MUST return "" (url-008).
- `bare-domain-with-no-scheme` MUST — example.com is not an absolute URL, so the function MUST return it unchanged, which makes it read like a host (url-007).
- `host-and-port-with-no-scheme` MUST — localhost:3000 parses as an absolute URL with scheme localhost: and an empty host, so the function MUST return "", not …
- `non-special-schemes` MUST — mailto:, file: and similar URLs with no authority MUST yield "" (url-010, url-011).
- `surrounding-whitespace` MUST — The parser strips leading and trailing ASCII spaces and C0 controls, so a padded absolute URL MUST still yield its host …
- `mixed-case-and-idn` MUST — Special-scheme hosts MUST be returned lowercased and in Punycode form (url-002, url-005). Unparseable input comes back …
- `very-long-input` MUST — The source sets no length limit and does no truncation. The function MUST return whatever the URL parser produces, or …

## Edge Cases

- **Empty string**: `new URL("")` throws, so the function MUST return `""` (url-008).
- **Bare domain with no scheme**: `example.com` is not an absolute URL, so the function MUST return it unchanged, which makes it read like a host (url-007).
- **Host and port with no scheme**: `localhost:3000` parses as an absolute URL with scheme `localhost:` and an empty host, so the function MUST return `""`, not `localhost:3000` (url-009). Callers without a `||` fallback then render an empty label.
- **Non-special schemes**: `mailto:`, `file:` and similar URLs with no authority MUST yield `""` (url-010, url-011).
- **Surrounding whitespace**: The parser strips leading and trailing ASCII spaces and C0 controls, so a padded absolute URL MUST still yield its host (url-012). `EndpointsSection.save` also calls `trim()` before `hostOf`.
- **Mixed case and IDN**: Special-scheme hosts MUST be returned lowercased and in Punycode form (url-002, url-005). Unparseable input comes back with its original case, which is why `ProjectBrowser` applies its own `toLowerCase()`.
- **Nullish input**: The signature forbids `null` and `undefined`. `new URL(undefined)` would throw and the catch would return `undefined`, but callers coalesce first (caller-nullish-guard).
- **Concurrent access**: Not applicable. The function is synchronous, stateless and runs on the single JavaScript thread.
- **Error states**: Parse failure is the only error. It is caught and turned into the unchanged-input fallback (host-of-parse-failure-fallback). The function has no other dependency that can fail.
- **Offline or disconnected state**: Not applicable. Parsing is local and makes no network access.
- **Very long input**: The source sets no length limit and does no truncation. The function MUST return whatever the `URL` parser produces, or the input unchanged.
