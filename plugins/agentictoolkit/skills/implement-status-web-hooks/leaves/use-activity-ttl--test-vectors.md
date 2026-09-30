<!-- leaf: implement-status-web-hooks/use-activity-ttl--test-vectors · source: status-web-hooks-use-activity-ttl.md -->

# useActivityTtl

## Conformance Test Vectors

| ID | Requirements | Input/Precondition | Action | Expected Output |
|----|---|---|---|---|
| activity-ttl-001 | initialization | First render, no localStorage | Render hook | Returns `{ ttlMin: 60, ttlMs: 3600000, setTtl: <function> }` |
| activity-ttl-002 | hydration | localStorage contains `"adh-healthy-ttl": 30` | Render hook and allow useEffect | After effect runs, `ttlMin` becomes `30` and `ttlMs` becomes `1800000` |
| activity-ttl-003 | null-as-stored-value | localStorage contains `"adh-healthy-ttl": null` | Render hook and allow useEffect | After effect runs, `ttlMin` is `null` and `ttlMs` is `null` |
| activity-ttl-004 | invalid-value-rejection | localStorage contains `"adh-healthy-ttl": 45` (not in valid options) | Render hook and allow useEffect | State remains at default (`ttlMin: 60`, `ttlMs: 3600000`) |
| activity-ttl-005 | parse-error-handling | localStorage contains `"adh-healthy-ttl": "{invalid json"` | Render hook and allow useEffect | Exception is caught, state remains default |
| activity-ttl-006 | setTtl-valid | Call `setTtl(15)` | Observe state change and localStorage write | `ttlMin` is `15`, `ttlMs` is `900000`, localStorage has `"adh-healthy-ttl": 15` |
| activity-ttl-007 | setTtl-null | Call `setTtl(null)` | Observe state change and localStorage write | `ttlMin` is `null`, `ttlMs` is `null`, localStorage has `"adh-healthy-ttl": null` |
| activity-ttl-008 | persistence-error-handling | `localStorage.setItem` throws (e.g., quota exceeded) | Call `setTtl(30)` | State updates to `ttlMin: 30, ttlMs: 1800000`, exception is caught, in-memory value persists |
| activity-ttl-009 | ssr-hydration-match | SSR render followed by browser hydration | Server-render and hydrate in browser with empty localStorage | Initial paint matches default (`ttlMin: 60`, `ttlMs: 3600000`), no hydration warning |
