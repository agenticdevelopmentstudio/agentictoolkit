<!-- leaf: implement-status-server-monitor-1/issues--part-3 · source: status-server-monitor-issues.md -->

# Status Server Monitor Issues — continued (part 3)

## Design Decisions

- **Decision**: keep `issues` as a ledger that only records the board's verdict, rather than letting `deriveBoard`'s output replace it outright.
  **Rationale**: stated directly in the file's own header comment — the ledger keeps three things a derived board cannot: alert dedup via `uniq_open_issue_per_target`, the onset time a problem started, and 90 days of resolved history. A purely derived board recomputed from scratch each cycle has no memory of any of the three.
  **Approved**: pending
- **Decision**: give `applyBoardToLedger` and `openByTarget` no injectable clock (`nowMs`) parameter, unlike `deriveBoard`.
  **Rationale**: the source comment draws the line explicitly — the rule that makes the clock a parameter exists for `deriveBoard`, which must be pure so the regression suite can drive it deterministically. This function exists to write rows, and each of its three storage primitives stamps its own `new Date()`; accepting a `nowMs` this function cannot hand to any of them would document a guarantee it does not make.
  **Approved**: pending
- **Decision**: compare the FULL target string when deciding staleness and watched-membership, rather than a sub-segment (e.g., just the project portion).
  **Rationale**: the source comment explains this replaced the deleted `issueOrphaned`, which compared only the project segment for deploy targets and let a Railway target whose environment left config survive every sweep, staying open forever. Comparing the whole string is what a target key with an environment segment requires.
  **Approved**: pending
- **Decision**: repair duplicate open rows (`closeShadows`) rather than assuming `uniq_open_issue_per_target` makes them impossible.
  **Rationale**: the source comment on `openByTarget` states the index "has been violated in practice (pre-migration rows, manual backfills)," and a writer that only ever saw the first row per target let a shadow rot: never updated, never resolved, invisible to the cleanup cycle whose job it was to close it. Repairing on both the still-flagged and no-longer-flagged paths, silently and via a distinct `"duplicate"` resolution reason, means a violated invariant leaves a warning trail instead of being papered over.
  **Approved**: pending
- **Decision**: place the `updated`/`resolvedTargets` accounting on opposite sides of the `closeShadows` call — `updated++` after it, `resolvedTargets.push(t)` before it.
  **Rationale**: not stated in a comment; recorded here as an observed, deliberate-looking asymmetry in the source rather than an invented explanation. Its practical effect is that a `closeShadows` failure following a successful `updateIssue` costs that target its `updated` credit even though the canonical row's update already committed, while the same failure following a successful `resolveIssue` does NOT cost the target its place in `resolvedTargets` or the `resolved` count. Both behaviors are logged via `logLedgerFailure` either way, so no signal is lost — but a consumer of the returned counts (e.g. `POST /board/reconcile`'s caller) should read `updated` as "canonical write and shadow cleanup both succeeded" and `resolved`/`resolvedTargets` as "the canonical write succeeded" (shadow cleanup for a resolved target is a best-effort bonus, not a precondition of being counted).
  **Approved**: pending
- **Decision**: accept a one-time burst of duplicate `opened` alerts, and a resolved row's `environment` badge staying stale for up to 24 hours, as the deliberate cost of the deploy-target-key migration to `boardTargetKey`, rather than writing a data migration or one-shot alert suppression.
  **Rationale**: the source's own extended comment weighs both alternatives explicitly and rejects them — a data migration "buys one field, one time, and owes a correctness argument per family," and one-shot alert suppression "can only ever be exercised once, and whose failure mode is swallowing a real page." Because an old-spelled target is absent from the new `monitoredTargets`, it closes silently as `unmonitored` (correct — no recovery was observed), and the re-derived target then opens fresh and alerts unconditionally (`open-alerts-unconditionally`) — a one-time, expected burst on the deploy that ships this change, not corruption. The resolved-row environment staleness is self-clearing within `ACTIVITY_WINDOW_MS` (24h) because only open rows are refreshed by `updateIssue`.
  **Approved**: pending
