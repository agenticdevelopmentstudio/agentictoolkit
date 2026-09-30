<!-- leaf: implement-status-web-src-lib-1/peer-url--edge-cases · source: status-web-src-lib-peer-url.md -->

# Status Web Peer URL

**Rules** (cite as `implement-status-web-src-lib-1/peer-url--edge-cases#<slug>`):

- `empty-or-whitespace-only-input` MUST — normalizePeerBaseUrl MUST return "", and isValidPeerBaseUrl MUST return false. The editor treats an empty normalized …
- `half-typed-input` MUST (`https:/`, `b.exa`) — normalizePeerBaseUrl MUST fall back to trim and strip without throwing, and isValidPeerBaseUrl MUST return false until …
- `valid-but-un-canonical-input` MUST — isValidPeerBaseUrl MUST judge the typed string, not the normalized one. The editor validates draft.baseUrl as typed, …
- `non-http-scheme-that-parses` MUST (`javascript:alert(1) — , mailto:a@b): normalizePeerBaseUrl MUST still return a string built from the parsed parts. For an opaque URL with no …
- `credentials-in-the-url` MUST — normalizePeerBaseUrl MUST drop the userinfo (normalize-drop-userinfo). A peer URL that needs embedded credentials …
- `only-trailing-slashes` MUST (`"///"`) — the input does not parse, so the fallback MUST return "".
- `divergence-from-the-backend` MUST — if one copy of the rules changes without the other, the board's dirty check and inline message disagree with the …

## Edge Cases

- **Empty or whitespace-only input**: `normalizePeerBaseUrl` MUST return `""`, and `isValidPeerBaseUrl` MUST return `false`. The editor treats an empty normalized value as "not yet typed" and shows no invalid message (`PeersSection.tsx` sets `urlInvalid` only when the normalized URL is non-empty).
- **Half-typed input** (`https:/`, `b.exa`): `normalizePeerBaseUrl` MUST fall back to trim and strip without throwing, and `isValidPeerBaseUrl` MUST return `false` until the text parses as an absolute http(s) URL.
- **Valid but un-canonical input**: `isValidPeerBaseUrl` MUST judge the typed string, not the normalized one. The editor validates `draft.baseUrl` as typed, and validation trims internally.
- **Non-http scheme that parses** (`javascript:alert(1)`, `mailto:a@b`): `normalizePeerBaseUrl` MUST still return a string built from the parsed parts. For an opaque URL with no host this puts `//` after the scheme (`javascript:alert(1)` becomes `javascript://alert(1)`). `isValidPeerBaseUrl` rejects these inputs, so the result is never stored.
- **Credentials in the URL**: `normalizePeerBaseUrl` MUST drop the userinfo (normalize-drop-userinfo). A peer URL that needs embedded credentials cannot round-trip through the canonical form.
- **Only trailing slashes** (`"///"`): the input does not parse, so the fallback MUST return `""`.
- **Divergence from the backend**: if one copy of the rules changes without the other, the board's dirty check and inline message disagree with the server. The server's answer MUST win (backend-authority). The only guard against drift is the shared test cases.
- **Concurrent access**: not applicable. Both functions are synchronous and pure on single-threaded JavaScript.
- **Error states and offline**: not applicable. The module does no I/O, so no dependency can fail and connectivity does not matter.
