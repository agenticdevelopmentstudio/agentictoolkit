<!-- leaf: implement-status-server-monitor-1/issue-sources--part-4 · source: status-server-monitor-issue-sources.md -->

# Status Server Monitor Issue Sources — continued (part 4)

**Rules** (cite as `implement-status-server-monitor-1/issue-sources--part-4#<slug>`):

- `decision` SHOULD (`mirror-parity-guard`, SHOULD) — the hand-mirrored client copy of IssueSource/SOURCE_LABEL/ISSUE_SOURCES at status-web/src/lib/issue-sources.ts SHOULD …

## Design Decisions

- **Decision**: resolve the deploy-integration `platform` string to an `IssueSource` through the `INTEGRATION_PLATFORM_SOURCE` lookup table (`platformHealthSource`) rather than a type cast, and accept both `"cloudflare"` and `"cloudflare-pages"` as valid input.
  **Rationale**: stated directly in the source comment — the config-side vocabulary and the health/`IssueSource` vocabulary disagree about exactly one platform's spelling, so a cast would compile, run, and silently produce no match for Cloudflare specifically; both spellings are accepted because `createIntegration` (external, in `libsql/stores/config-store.ts`) takes the platform as a free string, so either one may already be stored.
  **Approved**: pending
- **Decision**: give `deployIsBad` no opinion on `"canceled"` at all — neither good nor bad — rather than treating a canceled build as either a resolved Problem or an open one.
  **Rationale**: stated directly in the source comment — Vercel's Ignored Build Step cancels a deployment for every site a commit did not touch, making `"canceled"` the ordinary newest state of a low-churn site; judging it as bad would pin an open Problem open forever, and judging it as good would let a canceled retry mask a real failure on the row it superseded. The precondition this places on every caller — feed `deployIsBad` only the newest row that reached a verdict — is enforced entirely outside this file, by the `HAS_OUTCOME` row filter callers apply before selecting a row to judge.
  **Approved**: pending
- **Decision**: exempt `"queued"` from `deployIsStuck` entirely, flagging only `"building"` past `STUCK_DEPLOY_MS`.
  **Rationale**: stated directly in the source comment — a long-queued deploy is almost always an intentional hold (a Railway deploy awaiting approval, a Vercel build gated by concurrency limits), and flagging those paged on-call for deploys that were working as designed; only an actively-building deploy that never lands is treated as wedged.
  **Approved**: pending
- **Decision**: give `nextPlatformStreak` a `bad` field that only the debounce logic computes, while its sole caller (`observation-store.ts`'s `recordObservations`) reads only the `streak` half and discards `bad`.
  **Rationale**: stated directly in the caller's own source comment — the threshold decision belongs to `board/derive-problems.ts`'s `platformProblems`, which re-checks the PERSISTED `streak` against `PLATFORM_UNREACHABLE_POLLS` itself on every board read; the recorder's only job is advancing and persisting the count. `nextPlatformStreak` computes `bad` anyway so the function's contract is self-contained and independently testable, even though today's single caller does not consume it.
  **Approved**: pending
- **Decision**: `dropVanishedVercelProjects` declines to narrow (returns `vanished: []`) both when the live read is empty AND when it would remove every configured project, rather than trusting either read at face value.
  **Rationale**: stated directly in the source comment as two independently load-bearing guards — an empty live set is indistinguishable from a read that came back empty because the token was rescoped, not because the account was emptied; and a non-empty read naming none of the configured projects is indistinguishable from a re-scoped token or a project transfer returning a complete list of somebody else's projects. Both decline the narrowing rather than the underlying deletion, so the cost of a false guard is a board that keeps showing deploy Problems for a project that really was deleted — judged, per the same comment, as far cheaper than silently losing every monitor for the fleet in one bad read.
  **Approved**: pending
- **Decision** (`mirror-parity-guard`, SHOULD): the hand-mirrored client copy of `IssueSource`/`SOURCE_LABEL`/`ISSUE_SOURCES` at `status-web/src/lib/issue-sources.ts` SHOULD gain a cross-package parity test analogous to `deploy-status-parity.test.ts`, which performs this same role for the sibling `deploy-status.ts` module.
  **Rationale**: the client file's own doc comment names the exact failure mode of an unguarded drift — "a source the server can emit and the client has never heard of renders `undefined` in the filter and the badge" — but, unlike `deploy-status.ts`, no test in either package currently asserts the two copies agree; `status-web/src/lib/issue-sources.test.ts` only asserts the client copy's own internal consistency (every `ISSUE_SOURCES` member has a truthy label), never that it matches this file. This is an absent safeguard for a documented risk, not a defect in this file's own behavior, so it is recorded here as a deviation-with-rationale rather than a source-fidelity gap.
  **Approved**: pending
