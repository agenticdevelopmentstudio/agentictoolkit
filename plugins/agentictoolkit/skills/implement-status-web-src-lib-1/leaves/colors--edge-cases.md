<!-- leaf: implement-status-web-src-lib-1/colors--edge-cases · source: status-web-src-lib-colors.md -->

# Status Web Colors

**Rules** (cite as `implement-status-web-src-lib-1/colors--edge-cases#<slug>`):

- `null-and-empty-env-for-envcolor` MUST — null, undefined or "" MUST return ENV_FALLBACK_COLOR via the truthiness guard.
- `null-env-for-envbadgelabel` MUST — passing null or undefined violates the string parameter type; at runtime env.toUpperCase() throws a TypeError. Callers …
- `empty-env-for-envbadgelabel` MUST — "" has no entry, so the function MUST return "".toUpperCase(), the empty string.
- `unknown-env-names` MUST — an unknown env MUST get the dim fallback color from envColor and its full upper-cased name from envBadgeLabel; the …
- `case-variants` MUST — "PRODUCTION" or "Production" MUST NOT match production; envColor returns the fallback and envBadgeLabel returns the …
- `missing-status-key` MUST — a status string absent from a status table MUST yield undefined; the module raises no error and the caller supplies the …

## Edge Cases

- **Null and empty env for envColor**: `null`, `undefined` or `""` MUST return `ENV_FALLBACK_COLOR` via the truthiness guard.
- **Null env for envBadgeLabel**: passing `null` or `undefined` violates the `string` parameter type; at runtime `env.toUpperCase()` throws a `TypeError`. Callers MUST supply a string.
- **Empty env for envBadgeLabel**: `""` has no entry, so the function MUST return `"".toUpperCase()`, the empty string.
- **Unknown env names**: an unknown env MUST get the dim fallback color from `envColor` and its full upper-cased name from `envBadgeLabel`; the badge is not truncated, so long names widen the env column beyond the four characters the authoring comment describes for known envs.
- **Case variants**: `"PRODUCTION"` or `"Production"` MUST NOT match `production`; `envColor` returns the fallback and `envBadgeLabel` returns the upper-cased input (`"PRODUCTION"`).
- **Inherited object keys**: env strings such as `"constructor"`, `"toString"` or `"__proto__"` resolve inherited members of the object literals and return non-string values; see env-object-prototype-keys.
- **Missing status key**: a status string absent from a status table MUST yield `undefined`; the module raises no error and the caller supplies the fallback.
- **Undefined theme token**: if the host page does not define a referenced `--color-apt-*` property, the browser treats the `var()` as invalid at computed-value time and the CSS property falls back to its inherited or initial value; this module neither detects nor reports that, and the token set is owned by `@agenticdevelopertoolkit/themes`.
- **Browsers without color-mix()**: `COLORS.textSoft`, the amber surfaces and every `TINT` value depend on CSS `color-mix()`; in an engine without it the declaration is invalid and is dropped by the browser. The module provides no fallback value.
- **Runtime mutation**: the exported objects are not frozen, so a consumer that writes to one (possible for the `Record<string, string>` tables without a type error) changes the value for every other consumer in the page. No consumer in the package does this.
- **Concurrent access**: not applicable; the module has no mutable state and runs on the single JavaScript thread.
- **Error, offline and I/O states**: not applicable; the module performs no I/O.
