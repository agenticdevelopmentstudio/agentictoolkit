<!-- leaf: implement-status-web-hooks/use-activity-ttl--edge-cases · source: status-web-hooks-use-activity-ttl.md -->

# useActivityTtl

**Rules** (cite as `implement-status-web-hooks/use-activity-ttl--edge-cases#<slug>`):

- `empty-localstorage-key` MUST — If localStorage.getItem("adh-healthy-ttl") returns null, the hook MUST keep the default and not attempt to parse null.
- `malformed-json-in-storage` MUST — If stored value is valid JSON but not a recognized structure (e.g., "adh-healthy-ttl": "string" or "adh-healthy-ttl": …
- `out-of-range-number` MUST — If a number outside ACTIVITY_TTL_OPTIONS_MIN is stored (e.g., 50 or 120), the hook MUST reject it and keep the default.
- `type-narrowing-after-json-parse` MUST — After JSON.parse, the value is unknown; the hook MUST check both type and membership in VALID before accepting.
- `localstorage-unavailable` MUST — If the browser environment lacks localStorage (e.g., private browsing, blocked), both read and write operations MUST …
- `quota-exceeded-on-write` MUST — If localStorage.setItem throws due to quota, the state change MUST proceed in-memory and the hook MUST not propagate …
- `rapid-setttl-calls` MUST — Multiple setTtl calls in quick succession MUST each attempt to persist; if some writes fail, others MAY succeed …
- `hook-unmount-before-hydration` MUST — If the component unmounts before useEffect runs, no state update attempt MUST occur (React's cleanup handles this).

## Edge Cases

- **Empty localStorage key**: If `localStorage.getItem("adh-healthy-ttl")` returns `null`, the hook MUST keep the default and not attempt to parse `null`.
- **Malformed JSON in storage**: If stored value is valid JSON but not a recognized structure (e.g., `"adh-healthy-ttl": "string"` or `"adh-healthy-ttl": {}`), the hook MUST reject it and keep the default.
- **Out-of-range number**: If a number outside `ACTIVITY_TTL_OPTIONS_MIN` is stored (e.g., `50` or `120`), the hook MUST reject it and keep the default.
- **Type narrowing after JSON parse**: After `JSON.parse`, the value is `unknown`; the hook MUST check both type and membership in `VALID` before accepting.
- **localStorage unavailable**: If the browser environment lacks `localStorage` (e.g., private browsing, blocked), both read and write operations MUST catch and ignore exceptions.
- **Quota exceeded on write**: If `localStorage.setItem` throws due to quota, the state change MUST proceed in-memory and the hook MUST not propagate the error.
- **Rapid setTtl calls**: Multiple `setTtl` calls in quick succession MUST each attempt to persist; if some writes fail, others MAY succeed independently.
- **Hook unmount before hydration**: If the component unmounts before `useEffect` runs, no state update attempt MUST occur (React's cleanup handles this).
