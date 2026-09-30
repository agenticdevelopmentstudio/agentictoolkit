<!-- leaf: implement-status-web-src-lib-2/status-sublabel · source: status-web-src-lib-status-sublabel.md -->

**Rules** (cite as `implement-status-web-src-lib-2/status-sublabel#<slug>`):

- `sublabel-signature` MUST
- `sublabel-pure` MUST
- `sublabel-synchronous` MUST
- `sublabel-no-throw` MUST
- `ok-ignores-problems` MUST
- `ok-all-healthy` MUST
- `ok-not-all-healthy` MUST
- `ok-strict-equality` MUST
- `breakdown-group-by-status-word` MUST
- `breakdown-ignores-counts-args` MUST
- `breakdown-phrase-down` MUST
- `breakdown-phrase-degraded` MUST
- `breakdown-phrase-build-failed` MUST
- `breakdown-phrase-deploy-failed` MUST
- `breakdown-phrase-deployment-failed` MUST
- `breakdown-phrase-building` MUST
- `breakdown-phrase-platform-unreachable` MUST
- `breakdown-mapped-order` MUST
- `breakdown-unmapped-verbatim` MUST
- `breakdown-unmapped-after-mapped` MUST
- `breakdown-no-zero-groups` MUST
- `breakdown-separator` MUST
- `breakdown-sums-to-problem-count` MUST
- `breakdown-empty-problems` MUST
- `caller-pairs-state-and-problems` MUST

# Status Sublabel

## Overview

`status-sublabel.ts` (`packages/web/packages/status-web/src/lib/status-sublabel.ts`) exports one pure, synchronous function, `buildSublabel(state, healthyCount, servicesLength, problems)`, that returns the one-line caption shown under the status headline. When the board is clear it reads like "12/12 endpoints healthy · no failed builds". Otherwise it is a grouped breakdown of the problem rows, such as "2 down · 1 failed build", and the doc comment requires it to account "for EVERY problem so the parts sum to the indicator count".

The doc comment says the function is "Shared by the mobile hero and the desktop top-bar pill". In the current tree its only caller is `src/components/OverviewTab.tsx`, which passes the result to `BigIndicator` as `sublabel`. The inputs are typed by `IndicatorState` from Overview Projections and `Row` from Row Model. The function reads only `Row.statusWord`.

The module also holds a private table, `SUBLABEL_PHRASE`, which maps a problem row's status word to a function that formats a count into a phrase.

## Behavioral Requirements

### Signature and purity

- **sublabel-signature**: `buildSublabel` MUST take `state: IndicatorState`, `healthyCount: number`, `servicesLength: number` and `problems: Row[]`, and MUST return a `string`.
- **sublabel-pure**: `buildSublabel` MUST have no side effects. It MUST NOT mutate `problems` or any row, and MUST NOT perform I/O, log, or read global state.
- **sublabel-synchronous**: `buildSublabel` MUST return its result synchronously. The module runs on single-threaded JavaScript, so calls cannot interleave.
- **sublabel-no-throw**: For inputs that match the declared types, `buildSublabel` MUST NOT throw. No path in the function raises an error.

### Clear board (`state === "ok"`)

- **ok-ignores-problems**: When `state` is `"ok"`, the result MUST NOT depend on `problems`, even if the array is non-empty.
- **ok-all-healthy**: When `state` is `"ok"` and `healthyCount === servicesLength`, the function MUST return `` `${healthyCount}/${servicesLength} endpoints healthy · no failed builds` ``.
- **ok-not-all-healthy**: When `state` is `"ok"` and `healthyCount !== servicesLength`, the function MUST return `` `${servicesLength} endpoints monitored · no failed builds` `` and MUST NOT print a fraction. The source comment explains why: while the board is operational, a non-healthy endpoint is a transient blip or an unprobed endpoint, and "4/5 healthy" would contradict "ALL SYSTEMS OPERATIONAL".
- **ok-strict-equality**: The all-healthy test MUST be strict numeric equality (`===`). Any other relationship, including `healthyCount > servicesLength`, MUST take the "monitored" branch.

### Problem breakdown (`state` is `"warn"` or `"down"`)

- **breakdown-group-by-status-word**: For any `state` other than `"ok"`, the function MUST count `problems` grouped by exact `statusWord`. Matching is case-sensitive and whitespace-sensitive.
- **breakdown-ignores-counts-args**: For any `state` other than `"ok"`, the result MUST NOT depend on `healthyCount` or `servicesLength`.
- **breakdown-phrase-down**: A group of `n` rows with status word `"down"` MUST render as `` `${n} down` ``. This phrase has no plural form.
- **breakdown-phrase-degraded**: A group of `n` rows with status word `"degraded"` MUST render as `` `${n} degraded` ``. This phrase has no plural form.
- **breakdown-phrase-build-failed**: A group with status word `"build failed"` MUST render as `"1 failed build"` when `n === 1`, and as `` `${n} failed builds` `` for every other `n`.
- **breakdown-phrase-deploy-failed**: A group with status word `"deploy failed"` MUST render as `"1 failed deploy"` when `n === 1`, and as `` `${n} failed deploys` `` otherwise.
- **breakdown-phrase-deployment-failed**: A group with status word `"deployment failed"` MUST render as `"1 stale deploy"` when `n === 1`, and as `` `${n} stale deploys` `` otherwise. The status word is relabelled as "stale", not "failed".
- **breakdown-phrase-building**: A group with status word `"building"` MUST render as `"1 stuck build"` when `n === 1`, and as `` `${n} stuck builds` `` otherwise. The source comment gives the reason: "a building row only reaches Problems when stuck".
- **breakdown-phrase-platform-unreachable**: A group with status word `"platform unreachable"` MUST render as `"1 platform unreachable"` when `n === 1`, and as `` `${n} platforms unreachable` `` otherwise.
- **breakdown-mapped-order**: Mapped phrases MUST appear in the fixed table order `down`, `degraded`, `build failed`, `deploy failed`, `deployment failed`, `building`, `platform unreachable`, whatever order the rows arrive in.
- **breakdown-unmapped-verbatim**: A status word with no entry in `SUBLABEL_PHRASE` MUST render as `` `${n} ${statusWord}` ``, using the word verbatim with no pluralization.
- **breakdown-unmapped-after-mapped**: Unmapped groups MUST appear after all mapped phrases, in the order each word first occurs in `problems`.
- **breakdown-no-zero-groups**: Only status words that occur at least once in `problems` MUST produce a phrase. The function MUST NOT emit a zero-count phrase.
- **breakdown-separator**: Phrases MUST be joined with `" · "` (space, U+00B7 MIDDLE DOT, space), with no leading or trailing separator.
- **breakdown-sums-to-problem-count**: The counts in the phrases MUST add up to `problems.length`, so every problem row is counted exactly once.
- **breakdown-empty-problems**: For any `state` other than `"ok"` with an empty `problems`, the function MUST return the empty string `""`.

### Caller preconditions

- **caller-pairs-state-and-problems**: The function MUST trust the caller's pairing of `state` with `problems` and MUST NOT re-derive the state. The "sum to the indicator count" guarantee in the doc comment holds only when the caller passes the same problem set the indicator counted. `OverviewTab` pairs `indicator.state` with its `problems` rows.
- **caller-counts-services**: `healthyCount` and `servicesLength` are caller-computed. `OverviewTab` passes the number of env-filtered services with `status === "healthy"` and the length of that filtered list. The function does not validate them.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `state` | `IndicatorState` (`"ok" \| "warn" \| "down"`) | none (required) | Chooses the clear-board line (`"ok"`) or the problem breakdown (anything else). |
| `healthyCount` | `number` | none (required) | Number of endpoints reporting healthy; used only when `state` is `"ok"`. |
| `servicesLength` | `number` | none (required) | Number of endpoints monitored; used only when `state` is `"ok"`. |
| `problems` | `Row[]` | none (required) | The problem rows; only `statusWord` is read, and only when `state` is not `"ok"`. |
| `SUBLABEL_PHRASE` | `Record<string, (n: number) => string>` | seven compiled-in entries | Private map from status word to phrase formatter; not configurable by callers. |

The module reads no environment variables or settings keys and takes no injected dependencies. It imports only types.

## Localization

Every string the function returns is hardcoded English, with no localization layer. Pluralization is a binary `n === 1` test that appends `s` (or, for platforms, swaps in "platforms"). The `down`, `degraded` and unmapped phrases are never pluralized. The separator is a literal `" · "`.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; literal) | `{healthy}/{total} endpoints healthy · no failed builds` | Clear board, every endpoint healthy |
| (none; literal) | `{total} endpoints monitored · no failed builds` | Clear board, not every endpoint healthy |
| (none; literal) | `{n} down` | Breakdown, `down` rows |
| (none; literal) | `{n} degraded` | Breakdown, `degraded` rows |
| (none; literal) | `{n} failed build` / `{n} failed builds` | Breakdown, `build failed` rows |
| (none; literal) | `{n} failed deploy` / `{n} failed deploys` | Breakdown, `deploy failed` rows |
| (none; literal) | `{n} stale deploy` / `{n} stale deploys` | Breakdown, `deployment failed` rows |
| (none; literal) | `{n} stuck build` / `{n} stuck builds` | Breakdown, `building` rows |
| (none; literal) | `{n} platform unreachable` / `{n} platforms unreachable` | Breakdown, `platform unreachable` rows |
| (none; literal) | `{n} {statusWord}` | Breakdown, any unmapped status word (the word comes from the row) |
| (none; literal) | ` · ` | Separator between phrases |

