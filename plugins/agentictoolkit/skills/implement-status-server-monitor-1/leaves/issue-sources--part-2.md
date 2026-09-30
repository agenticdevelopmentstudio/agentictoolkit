<!-- leaf: implement-status-server-monitor-1/issue-sources--part-2 · source: status-server-monitor-issue-sources.md -->

# Status Server Monitor Issue Sources — continued (part 2)

**Rules** (cite as `implement-status-server-monitor-1/issue-sources--part-2#<slug>`):

- `issue-source-values` MUST
- `glitchtip-distinct-signal` MUST
- `source-label-completeness` MUST
- `issue-sources-canonical-order` MUST
- `integration-platform-source-mapping` MUST
- `integration-platform-source-normalization` MUST
- `integration-platform-source-unmapped` MUST
- `cloudflare-spelling-not-a-cast` MUST
- `cloudflare-both-spellings-accepted` MUST
- `http-is-bad-definition` MUST
- `deploy-is-bad-definition` MUST
- `deploy-is-bad-excludes-canceled` MUST
- `deploy-is-bad-newest-outcome-precondition` MUST
- `stuck-deploy-threshold-value` MUST
- `deploy-is-stuck-definition` MUST
- `deploy-is-stuck-excludes-queued` MUST
- `deploy-is-resolving-definition` MUST
- `platform-unreachable-poll-threshold-value` MUST
- `platform-streak-shape` MUST
- `next-platform-streak-increment` MUST
- `next-platform-streak-reset` MUST
- `next-platform-streak-bad-threshold` MUST
- `next-platform-streak-default-threshold` MUST
- `next-platform-streak-single-transient-blip-debounced` MUST
- `configured-deploy-targets-shape` MUST
- `drop-vanished-computes-set-difference` MUST
- `drop-vanished-empty-live-guard` MUST
- `drop-vanished-whole-fleet-guard` MUST
- `drop-vanished-partial-narrowing` MUST
- `drop-vanished-vercel-only-scope` MUST

## Behavioral Requirements

### Issue Source Vocabulary

- **issue-source-values**: `IssueSource` MUST be exactly one of `"dns"`, `"http"`, `"glitchtip"`, `"vercel"`, `"cloudflare-pages"`, `"railway"`, or `"crunchy"`.
- **glitchtip-distinct-signal**: `"glitchtip"` MUST be treated as answering a different question from every other `IssueSource` — per the type's own doc comment, the other sources answer "is the thing reachable" while `glitchtip` answers "is the thing THROWING" — so a site MAY be reported healthy by every other source while a `glitchtip`-sourced Problem is open at the same time.
- **source-label-completeness**: `SOURCE_LABEL` MUST supply exactly one display string for every `IssueSource` member: `dns` → `"DNS"`, `http` → `"HTTP"`, `glitchtip` → `"GlitchTip"`, `vercel` → `"Vercel"`, `cloudflare-pages` → `"Cloudflare"`, `railway` → `"Railway"`, `crunchy` → `"Crunchy Bridge"`.
- **issue-sources-canonical-order**: `ISSUE_SOURCES` MUST list all seven `IssueSource` values in exactly this order: `dns`, `http`, `glitchtip`, `vercel`, `cloudflare-pages`, `railway`, `crunchy` — the order the source filter UI renders them in.

### Deploy Integration → Health Source Mapping

- **integration-platform-source-mapping**: `platformHealthSource` MUST map the normalized integration-platform string `"vercel"` to `"vercel"`, `"cloudflare"` to `"cloudflare-pages"`, `"cloudflare-pages"` to `"cloudflare-pages"`, `"railway"` to `"railway"`, and `"crunchy"` to `"crunchy"`.
- **integration-platform-source-normalization**: `platformHealthSource` MUST normalize its `integrationPlatform` argument by trimming whitespace and lowercasing before the lookup, and MUST treat a `null` argument identically to an empty string (both normalize to `""`).
- **integration-platform-source-unmapped**: `platformHealthSource` MUST return `null` for any normalized string not in the five listed above — including `""`, `"dns"`, `"http"`, `"glitchtip"`, and any unrecognized platform string — because those platforms are never polled for platform-level reachability.
- **cloudflare-spelling-not-a-cast**: `platformHealthSource` MUST resolve the mapping through the `INTEGRATION_PLATFORM_SOURCE` lookup table rather than a type cast of its input, because per the source's own doc comment the deploy-integration config vocabulary (`"cloudflare"`, from the vendored provider-connection config reader) and the `IssueSource`/`platform_health_state.source` vocabulary (`"cloudflare-pages"`) disagree about that one platform's spelling — a cast would compile, run, and silently produce no match for exactly that platform.
- **cloudflare-both-spellings-accepted**: `platformHealthSource` MUST accept both `"cloudflare"` and `"cloudflare-pages"` as input and MUST map both to the single output `"cloudflare-pages"`, because a deploy integration's `platform` column accepts either spelling as a free string at creation time (`createIntegration`, external to this file, in `libsql/stores/config-store.ts`).

### HTTP Verdict

- **http-is-bad-definition**: `httpIsBad(status)` MUST return `true` if and only if `status` is `"down"` or `"degraded"`, and MUST return `false` for `"healthy"`.

### Deploy Verdict

- **deploy-is-bad-definition**: `deployIsBad(status)` MUST return `true` if and only if `status` is `"failed"`, and MUST return `false` for every other `DeployStatus` value (`"success"`, `"building"`, `"queued"`, `"canceled"`, `"unknown"`).
- **deploy-is-bad-excludes-canceled**: `deployIsBad` MUST NOT treat `"canceled"` as bad, because per the function's own doc comment a canceled build is the ABSENCE of a verdict, not a good one — Vercel's Ignored Build Step cancels a deployment for every site a commit did not touch, making `"canceled"` the ordinary newest state of a low-churn site; judging it as bad would both pin an open Problem open forever and hide a later real failure that lands after it.
- **deploy-is-bad-newest-outcome-precondition**: callers of `deployIsBad` MUST feed it the newest deploy row that reached a verdict — per the function's own doc comment, this is the caller's obligation (documented at the call site as `HAS_OUTCOME` filtering, external to this file), not something `deployIsBad` itself can enforce, because it receives only a single `DeployStatus` value with no row ordering context.
- **stuck-deploy-threshold-value**: `STUCK_DEPLOY_MS` MUST be exactly `1,800,000` (30 minutes expressed as `30 * 60 * 1000`).
- **deploy-is-stuck-definition**: `deployIsStuck(status, ageMs)` MUST return `true` if and only if `status` is `"building"` AND `ageMs` is greater than or equal to `STUCK_DEPLOY_MS`.
- **deploy-is-stuck-excludes-queued**: `deployIsStuck` MUST return `false` for `status === "queued"` regardless of `ageMs`, because per the function's own doc comment a long-queued deploy is almost always an INTENTIONAL hold (a Railway deploy awaiting approval, a Vercel build gated by the Ignored Build Step or concurrency limits) rather than a wedge, and flagging those paged on-call for deploys that were working as designed.
- **deploy-is-resolving-definition**: `deployIsResolving(status)` MUST return `true` if and only if `status` is `"success"`, and MUST return `false` for every other `DeployStatus` value.

### Platform-Unreachable Streak

- **platform-unreachable-poll-threshold-value**: `PLATFORM_UNREACHABLE_POLLS` MUST be exactly `2`.
- **platform-streak-shape**: A `PlatformStreak` value MUST carry exactly two fields: `streak: number` (the new consecutive-failure count to persist) and `bad: boolean` (whether the platform-health issue should be open this cycle).
- **next-platform-streak-increment**: `nextPlatformStreak(prevStreak, failing, threshold)` MUST return `streak: prevStreak + 1` when `failing` is `true`.
- **next-platform-streak-reset**: `nextPlatformStreak` MUST return `streak: 0` when `failing` is `false`, regardless of `prevStreak` — per the function's own doc comment, a single reachable poll clears the streak immediately; recovery is deliberately NOT debounced the way a failure is.
- **next-platform-streak-bad-threshold**: `nextPlatformStreak` MUST return `bad: true` if and only if `failing` is `true` AND the resulting `streak` is greater than or equal to `threshold`; it MUST return `bad: false` whenever `failing` is `false`, even if the passed-in `prevStreak` already met or exceeded `threshold`.
- **next-platform-streak-default-threshold**: `nextPlatformStreak` MUST default its `threshold` parameter to `PLATFORM_UNREACHABLE_POLLS` when the caller omits it.
- **next-platform-streak-single-transient-blip-debounced**: `nextPlatformStreak` MUST NOT report `bad: true` for a single failing poll following an all-reachable history (`prevStreak: 0`, `failing: true` → `streak: 1`, `bad: false` at the default threshold of `2`) — per the module's own doc comment on `PLATFORM_UNREACHABLE_POLLS`, this debounces a one-off transient API blip (a `429` or a timeout) that would otherwise open and immediately auto-resolve an "unreachable" issue within a single poll cycle.

### Vanished Vercel Project Narrowing

- **configured-deploy-targets-shape**: A `ConfiguredDeployTargets` value MUST carry exactly three fields — `vercel`, `railway`, and `cloudflare`, each a `ReadonlySet<string>` — keyed by canonical platform (Cloudflare's `cloudflare-pages` config spelling folds to `cloudflare` at this boundary).
- **drop-vanished-computes-set-difference**: `dropVanishedVercelProjects(configured, liveVercelProjects)` MUST compute `vanished` as every member of `configured.vercel` that is NOT a member of `liveVercelProjects`, and MUST leave the `railway` and `cloudflare` fields of the returned `configured` untouched in every case.
- **drop-vanished-empty-live-guard**: `dropVanishedVercelProjects` MUST return `vanished: []` and the unmodified `configured` when `liveVercelProjects.size === 0`, narrowing nothing — per the function's own doc comment, an empty live set is indistinguishable from "the account read came back empty because the token was rescoped" and MUST NOT be read as "every project was deleted".
- **drop-vanished-whole-fleet-guard**: `dropVanishedVercelProjects` MUST return `vanished: []` and the unmodified `configured` when every member of `configured.vercel` is absent from `liveVercelProjects` (i.e. `vanished.length === configured.vercel.size` and `configured.vercel.size > 0`) — per the function's own doc comment, a non-empty live read naming none of the configured projects is indistinguishable from a re-scoped token or a project transfer, and MUST NOT be read as a real mass deletion.
- **drop-vanished-partial-narrowing**: `dropVanishedVercelProjects` MUST, when `vanished` is non-empty and smaller than `configured.vercel.size`, return `vanished` populated with exactly the missing project names AND a `configured.vercel` narrowed to exclude them.
- **drop-vanished-vercel-only-scope**: `dropVanishedVercelProjects` MUST narrow only the `vercel` field; per the function's own doc comment, Railway and Cloudflare projects are polled live on every enumeration and so have no equivalent staleness problem, and this function has no Railway/Cloudflare counterpart.

