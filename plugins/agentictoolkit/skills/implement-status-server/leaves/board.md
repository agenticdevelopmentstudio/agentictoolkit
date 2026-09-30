<!-- leaf: implement-status-server/board · source: status-server-board.md -->

**Rules** (cite as `implement-status-server/board#<slug>`):

- `segment-escaping` MUST
- `segment-unescaping` MUST
- `board-target-minting` MUST
- `railway-environment-segment` MUST
- `board-target-parsing` MUST
- `deploy-identity` MUST
- `deploy-ownership-gate` MUST
- `roster-target-indexing` MUST
- `vanished-vercel-narrowing` MUST
- `roster-entry-matching` MUST
- `owned-deploy-target-gate` MUST
- `owned-deploy-environment` MUST
- `crunchy-always-visible` MUST
- `roster-deploy-projects-grain` MUST
- `owns-deploy-project` MUST

# Status Server Board

## Overview

This is the status backend's board fold: eight files under `src/board/`
that reduce every monitoring fact the status site has — provider deploy
polls and webhooks, HTTP/DNS probes, provider platform-health samples,
GlitchTip error groups, the operator's roster configuration, and the
ledger's open-row onsets — into one `Board` value. `types.ts` defines the
fact and output shapes (`BoardFacts`, `Problem`, `ActivityRow`, `Board`) and
the module's constants. `target-key.ts` mints and parses the one canonical
spelling of a deploy target (`boardTargetKey`/`parseBoardTarget`), with
percent-escaping so the mint-parse round trip is total. `ownership.ts`
resolves which roster entry, if any, owns a deploy row or project
(`matchRosterEntry`, `ownedDeployTarget`, `rosterDeployProjects`), matching
by provider id first and project name second. `derive-problems.ts` judges
the five Problem families (deploy, endpoint, platform, stale-prod, error)
and computes `monitoredTargets`, the authoritative "currently watched" set.
`derive-activity.ts` derives the Activity feed as the union of deploy and
issue events (`deriveActivity`), the overall `indicatorFor`, and the
cursor-paginated `pageActivity`. `derive.ts` is the top-level fold,
`deriveBoard`, that combines all of the above into one `Board`.
`facts.ts` is the fold's read-side orchestration (`readBoardFacts`,
`readActivityPage`, `createActivityPageReader`) — the only file in
`src/board/` that touches `Storage`. `reconcile.ts` is the single
reconciliation entrypoint, `reconcileBoardLedger`, that reads facts, folds
them, writes the ledger diff, and flushes alerts, safe to call repeatedly
and from multiple callers. Every derivation function is pure: `nowMs` is a
parameter, there is no IO, and calling one twice with the same facts gives
a deep-equal result — the property the regression suite in
`test/board-regressions.test.ts` pins directly.

## Behavioral Requirements

### Target Keys (target-key.ts)

- **segment-escaping**: `escapeSegment` MUST replace every `%` with `%25`
  before replacing every `|` with `%7C` — escaping the escape character
  first is what keeps the mapping injective.
- **segment-unescaping**: `unescapeSegment` MUST invert `escapeSegment` in
  one left-to-right regex pass (matching `%25` or `%7C` and substituting
  `%` or `|` respectively), never as two sequential global replaces, so
  unescaping `%7C` cannot re-create a literal `%25` that then gets
  misread as a separator.
- **board-target-minting**: `boardTargetKey(platform, id, environment)`
  MUST return `null` when `platformCanon(platform)` is falsy or `id` is
  falsy, and otherwise MUST return `${canonicalPlatform}|${escapeSegment(id)}|${escapeSegment(env)}`
  — always exactly three pipe-separated segments.
- **railway-environment-segment**: `boardTargetKey` MUST populate the
  environment segment, lowercased, only when the canonical platform is
  `"railway"`; for every other platform the segment MUST be the empty
  string, so one non-Railway project collapses to one target regardless
  of environment.
- **board-target-parsing**: `parseBoardTarget` MUST return `null` unless
  the input splits on `|` into exactly three parts with a non-empty
  platform and a non-empty id, and otherwise MUST return
  `{ platform, id: unescapeSegment(id), environment: unescapeSegment(environment ?? "") }`.

### Ownership (ownership.ts)

- **deploy-identity**: `entryIdentity` MUST return the roster entry's
  `providerProjectId` when present, else its `projectName`.
- **deploy-ownership-gate**: a roster entry MUST own a deploy target or
  deploy project (via `rosterTargets`, `rosterDeployProjects`,
  `ownedDeployTarget`) only while it is `isActive`, has `monitorDeploys`
  on, and does not have `ignoreProjectWarning` set.
- **roster-target-indexing**: `rosterTargets` MUST index every
  deploy-owning roster entry twice — under `boardTargetKey` keyed by its
  provider id (when it has one) and under `boardTargetKey` keyed by its
  project name — so a Railway entry's index keys stay environment-scoped
  exactly as the target keys themselves are.
- **vanished-vercel-narrowing**: `rosterTargets` MUST compute
  `vanishedVercel` from `dropVanishedVercelProjects` applied to
  `rosterDeployProjects`' Vercel/Railway/Cloudflare name sets against the
  live Vercel project mirror, and MUST narrow nothing (return an empty
  `vanishedVercel`) when that mirror is empty or would vanish every owned
  Vercel project at once.
- **roster-entry-matching**: `matchRosterEntry` MUST try a provider-id
  match first and a project-name match second, and MUST reject (return
  `null` rather than the name match) when both the deploy row and the
  matched-by-name entry carry a `providerProjectId` and the two disagree.
- **owned-deploy-target-gate**: `ownedDeployTarget` MUST return `null` for
  a row that is not a real-environment deploy row (per
  `isRealEnvDeployRow`), for a Vercel row whose project name is in
  `vanishedVercel`, or for a row no roster entry owns and whose platform
  does not canonicalize to `"crunchy"`.
- **owned-deploy-environment**: `ownedDeployTarget` MUST derive its
  returned `env` by calling `deployEnv(d.platform, d.projectName,
  d.environment, d.branch)` on every row it accepts, never by caching a
  tier per target — the same project's older and newer rows MAY legitimately
  carry different tiers when its production branch was repointed.
- **crunchy-always-visible**: a deploy row whose platform canonicalizes to
  `"crunchy"` MUST be ownable (target minted from the row's own platform
  and project name) even when no roster entry claims it.
- **roster-deploy-projects-grain**: `rosterDeployProjects` MUST record
  both the provider-id and project-name spellings of every deploy-owning
  entry, bucketed by canonical platform and environment-free.
- **owns-deploy-project**: `ownsDeployProject` MUST return `true`
  unconditionally for a Crunchy row, and otherwise MUST return `true` only
  when the row's provider id or project name appears in the matching
  canonical-platform bucket `rosterDeployProjects` produced.

