<!-- leaf: implement-status-web-src-lib-2/url--test-vectors · source: status-web-src-lib-url.md -->

# Status Web URL Host

## Conformance Test Vectors

These vectors follow the WHATWG URL parsing behavior that `hostOf` delegates to. They were checked against Node's `URL` implementation. The source has no test file of its own (there is no `url.test.ts`).

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| url-001 | host-of-parsed-host, host-of-no-path-query-userinfo | `"https://adh.app/health?x=1#top"` | `"adh.app"` |
| url-002 | host-of-non-default-port, host-of-normalized-host | `"https://Example.COM:8443/a?b"` | `"example.com:8443"` |
| url-003 | host-of-default-port-dropped | `"https://example.com:443/"` | `"example.com"` |
| url-004 | host-of-no-path-query-userinfo | `"http://user:pw@host.test/"` | `"host.test"` |
| url-005 | host-of-normalized-host | `"https://bücher.de/"` | `"xn--bcher-kva.de"` |
| url-006 | host-of-normalized-host, host-of-non-default-port | `"http://[::1]:8080/"` | `"[::1]:8080"` |
| url-007 | host-of-parse-failure-fallback, host-of-no-throw | `"example.com"` | `"example.com"` (returned unchanged, no exception) |
| url-008 | host-of-parse-failure-fallback, host-of-no-throw | `""` | `""` (returned unchanged, no exception) |
| url-009 | host-of-empty-host | `"localhost:3000"` | `""` (parses as scheme `localhost:` with an empty host) |
| url-010 | host-of-empty-host | `"mailto:a@b.c"` | `""` |
| url-011 | host-of-empty-host | `"file:///tmp/x"` | `""` |
| url-012 | host-of-parsed-host | `"  https://a.test  "` | `"a.test"` (the parser strips leading and trailing spaces) |
| url-013 | host-of-deterministic, host-of-pure | Call `"https://adh.app"` twice | Both calls return `"adh.app"`, and no global state changes |
| url-014 | host-of-failure-indistinguishable | `"not a url"` and `"https://not-a-url.test"` | `"not a url"` and `"not-a-url.test"`: both are plain strings, with no flag or exception telling the caller which one fell back |
