<!-- leaf: implement-status-web/stores--test-vectors · source: status-web-stores.md -->

# Status Web Stores

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| stores-001 | parse-projection, snapshot-shape | `parseSnapshot(JSON.stringify(snap))` where `snap` has `generatedAt: "2026-06-13T12:00:00.000Z"`, one error (`id: "1"`, `project: "hub"`, `title: "boom"`, `count: 3`) and one analytics metric (`pageviews`, `24h`, `all`, `10`) (from `local-cache.test.ts`) | Result deep-equals `snap` |
| stores-002 | parse-null-empty | `parseSnapshot(null)` and `parseSnapshot("")` (from `local-cache.test.ts`) | Both return `null` |
| stores-003 | parse-malformed-json | `parseSnapshot("{not json")` (from `local-cache.test.ts`) | Returns `null`; no exception thrown |
| stores-004 | parse-json-null | `parseSnapshot(JSON.stringify(null))` (from `local-cache.test.ts`) | Returns `null` |
| stores-005 | parse-errors-gate, parse-analytics-gate | `parseSnapshot(JSON.stringify({ generatedAt: "x" }))` (from `local-cache.test.ts`) | Returns `null` |
| stores-006 | parse-generated-at-gate | `parseSnapshot(JSON.stringify({ generatedAt: 1, errors: [], analytics: [] }))` (from `local-cache.test.ts`) | Returns `null` |
| stores-007 | parse-errors-gate | `parseSnapshot(JSON.stringify({ generatedAt: "x", errors: "nope", analytics: [] }))` (from `local-cache.test.ts`) | Returns `null` |
| stores-008 | parse-analytics-gate | `parseSnapshot('{"generatedAt":"x","errors":[],"analytics":{}}')` | Returns `null` |
| stores-009 | parse-projection | `parseSnapshot('{"generatedAt":"x","errors":[],"analytics":[],"extra":1}')` | Returns `{ generatedAt: "x", errors: [], analytics: [] }` with no `extra` key |
| stores-010 | parse-shallow | `parseSnapshot('{"generatedAt":"x","errors":[42],"analytics":["y"]}')` | Returns `{ generatedAt: "x", errors: [42], analytics: ["y"] }` |
| stores-011 | parse-generated-at-gate | `parseSnapshot('{"generatedAt":"","errors":[],"analytics":[]}')` | Returns `{ generatedAt: "", errors: [], analytics: [] }` (empty string is still a string) |
| stores-012 | save-format, load-reads-key, durability-reload | In a browser with empty storage, `localCache.save(snap)` then `localCache.load()` | `localStorage.getItem("adh-telemetry-v1")` equals `JSON.stringify(snap)`; `load()` deep-equals `snap` |
| stores-013 | load-missing-key | Browser storage with no `adh-telemetry-v1` key; call `localCache.load()` | Returns `null` |
| stores-014 | save-overwrites | `save(a)` then `save(b)`; call `load()` | Returns `b`; nothing of `a` remains |
| stores-015 | load-no-window, save-no-window | Runtime where `typeof window === "undefined"`; call `localCache.load()` and `localCache.save(snap)` | `load` returns `null`; `save` returns without throwing and writes nothing |
| stores-016 | load-storage-throws | `window.localStorage.getItem` stubbed to throw; call `localCache.load()` | Returns `null`; no exception propagates |
| stores-017 | save-best-effort | `window.localStorage.setItem` stubbed to throw a quota error; call `localCache.save(snap)` | Returns normally; no exception propagates; stored value unchanged |
| stores-018 | load-no-cleanup | Key holds `"{not json"`; call `localCache.load()` then read the key | `load` returns `null`; key still holds `"{not json"` |
| stores-019 | save-no-projection | `save({ ...snap, extra: 1 })`; read the raw key | Raw JSON contains `"extra":1`; `load()` returns the snapshot without `extra` |
| stores-020 | only-side-effect | Spy on `fetch`, `console` and every `localStorage` method; call `save(snap)` then `load()` | Only `setItem("adh-telemetry-v1", …)` and `getItem("adh-telemetry-v1")` are called |
