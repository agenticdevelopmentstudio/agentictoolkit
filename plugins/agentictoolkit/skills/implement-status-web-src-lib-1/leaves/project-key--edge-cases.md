<!-- leaf: implement-status-web-src-lib-1/project-key--edge-cases · source: status-web-src-lib-project-key.md -->

# Project Key

**Rules** (cite as `implement-status-web-src-lib-1/project-key--edge-cases#<slug>`):

- `empty-input-array` MUST — uniqueByProject([]) MUST return an empty array.
- `empty-field-values` MUST — projectKeyOf MUST produce "|" for empty platform and projectName; two such entries MUST collapse to one in …
- `separator-inside-a-field` MUST — The key is a plain concatenation with no escaping, so {platform:"a|b", projectName:"c"} and {platform:"a", …
- `case-variant-platforms` MUST — Entries whose platform differs only in case (for example Railway vs railway) MUST be treated as distinct projects, …
- `single-entry` MUST — uniqueByProject([X]) MUST return [X].
- `all-duplicates` MUST — An input where every entry shares one key MUST reduce to a one-element array holding the first entry.
- `backend-order-not-production-first` MUST — If the input lists a non-production environment first, the kept entry MUST be that non-production entry; the module …
- `malformed-input-at-runtime` MUST — The functions rely on the TypeScript signature for shape. An entry whose platform or projectName is undefined at …

## Edge Cases

- **Empty input array**: `uniqueByProject([])` MUST return an empty array.
- **Empty field values**: `projectKeyOf` MUST produce `"|"` for empty `platform` and `projectName`; two such entries MUST collapse to one in `uniqueByProject`.
- **Separator inside a field**: The key is a plain concatenation with no escaping, so `{platform:"a|b", projectName:"c"}` and `{platform:"a", projectName:"b|c"}` MUST both produce `"a|b|c"` and MUST collapse together. Collision requires a platform identifier containing `|`; platforms come from the backend's fixed platform set, so this is a documented limitation rather than an expected input.
- **Case-variant platforms**: Entries whose platform differs only in case (for example `Railway` vs `railway`) MUST be treated as distinct projects, because the raw platform is keyed deliberately.
- **Single entry**: `uniqueByProject([X])` MUST return `[X]`.
- **All duplicates**: An input where every entry shares one key MUST reduce to a one-element array holding the first entry.
- **Backend order not production-first**: If the input lists a non-production environment first, the kept entry MUST be that non-production entry; the module performs no correction.
- **Malformed input at runtime**: The functions rely on the TypeScript signature for shape. An entry whose `platform` or `projectName` is `undefined` at runtime MUST be stringified by template-literal rules (for example `"undefined|api"`); no runtime validation or exception occurs.
- **Concurrent access**: Not applicable — both functions are synchronous and run on the single JavaScript thread, and `uniqueByProject` allocates its seen-set per call, so calls cannot interleave.
- **Error states and offline**: Not applicable — the module performs no I/O and has no dependencies that can fail or disconnect.
