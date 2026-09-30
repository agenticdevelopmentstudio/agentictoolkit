<!-- leaf: implement-status-server/board--part-4 · source: status-server-board.md -->

# Status Server Board — continued (part 4)

**Rules** (cite as `implement-status-server/board--part-4#<slug>`):

- `end-user-pii` MAY — none of the fact shapes in types.ts carry end-user personal data (no email, no name, no IP address); commit messages, …

## Privacy

- **Data handled**: deploy metadata (provider platform, project name, branch, commit hash/message/repo, provider error text, source/live URLs) already persisted upstream; HTTP/DNS probe results; provider platform-health samples; GlitchTip error-group summaries (issue title, culprit, level, counts, first/last-seen times, permalink) already persisted upstream; roster configuration (endpoint id, label, platform, project identity, monitoring switches, probed URL).
- **Storage / transmission / retention**: none of these files decide storage, transmission, or retention themselves — `facts.ts` only reads what other modules (`storage.board.*`, `storage.health.*`, `storage.deploy.*`) already persisted, and `reconcile.ts` writes back only the derived `Board`'s Problem/ledger state through `applyBoardToLedger`, a port implemented elsewhere.
- **End-user PII**: none of the fact shapes in `types.ts` carry end-user personal data (no email, no name, no IP address); commit messages, error titles, and culprit strings are free-form text from connected providers and MAY incidentally contain arbitrary text, but these files apply no PII-specific handling to them — they pass the fields through unchanged.

## Platform Notes

- **TypeScript / Node (source)**: the fold is implemented as a set of pure functions over plain interfaces (`BoardFacts`, `Problem`, `ActivityRow`, `Board`) with no classes and no shared mutable state; `Map`/`Set` do the per-derivation indexing (`rosterTargets`, `onsetMap`, `collapseByTarget`), and every constant (`ACTIVITY_WINDOW_MS`, `DEGRADED_CONFIRM_MS`, etc.) is a plain exported `const`.
- **Swift (SwiftUI/AppKit/UIKit hosts)**: model `BoardFacts`, `Problem`, `ActivityRow`, and `Board` as `Equatable` `struct`s (value semantics make the purity/deep-equal contract free), the fold as a free function or a `static func` taking `facts` and `now: Date` explicitly, and the per-target indexing with `Dictionary`/`Set` exactly as the source's `Map`/`RosterIndex` does; keep `nowMs` (or a `Date`) an explicit parameter rather than reading `Date()` inside the fold, so XCTest can assert a deep-equal result the same way `test/board-regressions.test.ts` does.
- **Kotlin (Jetpack Compose hosts)**: model the same shapes as immutable `data class`es (structural `equals`/`hashCode` come for free, matching the deep-equal purity contract), the fold as a top-level function or an object method taking `facts: BoardFacts` and `nowMs: Long` explicitly, and the indexing with `Map`/`Set` from `kotlin.collections`.
- **C# / WinUI 3 (.NET / Windows App SDK hosts)**: model the shapes as immutable C# `record` types (e.g. `record Board(string GeneratedAt, long? DataAsOfMs, IReadOnlyList<Problem> Problems, ...)`, using `System.Collections.Immutable.ImmutableArray<T>` for the `Problems`/`Activity` lists so equality is structural), the fold as a `static` method on a plain class taking `BoardFacts facts` and `long nowMs` explicitly, and the per-target indexing with `System.Collections.Generic.Dictionary<TKey,TValue>`/`HashSet<T>`; if the derived `Board` crosses a process boundary to a UI layer, serialize it with `System.Text.Json` rather than hand-rolling a second shape.
- **Web client**: the client is documented in the source comments as holding byte-identical copies of exactly two pieces of this vocabulary — `ISSUE_VERB` (exported here for that reason) and the `STATE_LABEL` map described in `derive-activity.ts`'s comment on `ISSUE_VERB` — and a parity test (`row-vocabulary-parity.test.ts`, referenced in that comment) is what is meant to keep the two in sync; a client host porting this recipe should keep that parity test rather than letting the two vocabularies drift.

## Design Decisions

- **Decision**: keep `deployProblems`' concluded and in-flight deploy lists
  separate, and judge a retry's in-flight row only for `stuck`, rather
  than collapsing both lists to one "latest row per target" before
  judging.
  **Rationale**: the source comment states this directly — collapsing was
  the regression this code replaces: a retry's `BUILDING` row would win,
  the target would look neither failed nor stuck, `applyBoardToLedger`
  would read the resulting silence as a recovery, and on-call would be
  paged that a build passed while production still served the broken one.
  **Approved**: pending
- **Decision**: mint a deployment's Activity row ids from only its
  immutable provider id and lifecycle step
  (`deploy:<deploymentId>:<step>`), never from its target, timestamp,
  branch, or project name.
  **Rationale**: the source comment explains that `created_at`, `branch`,
  and `project_name` are all corrected in place by `upsertDeployments`; an
  id built from any of them would mint a second id for the same
  deployment once corrected, and the client's `useActivityHistory` keeps
  an id that leaves the live window forever — the "several sites stuck on
  building hours after they went green" defect the comment describes.
  **Approved**: pending
- **Decision**: derive `Board.dataAsOfMs` from only health-check
  (`checkedAtMs`) and platform-sample (`sampledAtMs`) observations,
  explicitly excluding deploy facts, ledger entries, and stale-prod facts.
  **Rationale**: the source comment explains each exclusion is deliberate
  — a deploy row carries the provider's own clock and can be written by a
  webhook on the API thread while the monitor process is wedged, which
  would refresh this clock without a monitor cycle having run; the ledger
  is the board's own output, so counting it would let the board's writes
  certify its own freshness; `staleProd` carries no observation timestamp
  at all. Every exclusion is chosen so the clock can only read older than
  reality, never fresher.
  **Approved**: pending
- **Decision**: suppress an issue-opened Activity row for a target only
  when the feed already carries a *bad-toned* deploy row for that target
  — never a not-bad (`built`/`deploying`) one.
  **Rationale**: the source comment (labeled "FIX 1" in the regression
  suite) states that a not-bad deploy row says the opposite of a `stale`
  or `stuck` issue on the same target, so it must not be allowed to
  silence the issue that is reporting the actual problem.
  **Approved**: pending
- **Decision**: freeze `errorProblems`' recency test — judging
  already-counted issues indefinitely rather than letting them age out —
  while GlitchTip's own platform-health fact is `configured` and not
  `ok`.
  **Rationale**: the source comment explains the alternative directly: a
  failed GlitchTip poll persists nothing, so every row's `lastSeen`
  simply stops advancing; without the freeze, exactly `ERROR_RECENT_MS`
  after the outage began every error row would silently expire and
  `applyBoardToLedger` would close the open row as `"recovered"` — an
  all-clear page for errors nobody has been able to observe for a day.
  **Approved**: pending
