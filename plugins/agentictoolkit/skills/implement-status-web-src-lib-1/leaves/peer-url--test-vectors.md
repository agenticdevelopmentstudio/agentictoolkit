<!-- leaf: implement-status-web-src-lib-1/peer-url--test-vectors · source: status-web-src-lib-peer-url.md -->

# Status Web Peer URL

## Conformance Test Vectors

Vectors 001–015 come from `peer-url.test.ts`. Vectors 016–018 follow from the code and WHATWG URL parsing.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| peer-url-001 | normalize-trim, normalize-strip-trailing-slashes | `normalizePeerBaseUrl("  https://b.example.com/// ")` | `"https://b.example.com"` |
| peer-url-002 | normalize-canonical-form, normalize-idempotent | `normalizePeerBaseUrl("https://b.example.com")` | `"https://b.example.com"` |
| peer-url-003 | normalize-keep-path | `normalizePeerBaseUrl("https://b.example.com/status/")` | `"https://b.example.com/status"` |
| peer-url-004 | normalize-lowercase | `normalizePeerBaseUrl("HTTPS://B.Example.COM")` | `"https://b.example.com"` |
| peer-url-005 | normalize-default-port | `normalizePeerBaseUrl("https://b.example.com:443")` | `"https://b.example.com"` |
| peer-url-006 | normalize-default-port | `normalizePeerBaseUrl("http://b.example.com:80")` | `"http://b.example.com"` |
| peer-url-007 | normalize-drop-query-fragment | `normalizePeerBaseUrl("https://b.example.com/?x=1#frag")` | `"https://b.example.com"` |
| peer-url-008 | normalize-keep-port | `normalizePeerBaseUrl("http://localhost:3000/")` | `"http://localhost:3000"` |
| peer-url-009 | normalize-total | `normalizePeerBaseUrl("  b.example.com/ ")` | `"b.example.com"`, no exception |
| peer-url-010 | valid-http-https | `isValidPeerBaseUrl("https://b.example.com")` | `true` |
| peer-url-011 | valid-http-https | `isValidPeerBaseUrl("http://localhost:3000")` | `true` |
| peer-url-012 | valid-trim, valid-no-normalize-required | `isValidPeerBaseUrl("  https://b.example.com/ ")` | `true` |
| peer-url-013 | valid-unparseable | `isValidPeerBaseUrl("b.example.com")`, `isValidPeerBaseUrl("/relative")`, `isValidPeerBaseUrl("")` | `false` each, no exception |
| peer-url-014 | valid-other-scheme | `isValidPeerBaseUrl("ftp://b.example.com")` | `false` |
| peer-url-015 | valid-other-scheme | `isValidPeerBaseUrl("javascript:alert(1)")`, `isValidPeerBaseUrl("file:///etc/passwd")` | `false` each |
| peer-url-016 | normalize-drop-userinfo | `normalizePeerBaseUrl("https://user:pw@b.example.com/")` | `"https://b.example.com"` |
| peer-url-017 | normalize-total | `normalizePeerBaseUrl("")` | `""` |
| peer-url-018 | normalize-total | `normalizePeerBaseUrl("B.Example.COM/")` (unparseable) | `"B.Example.COM"`, case unchanged |
