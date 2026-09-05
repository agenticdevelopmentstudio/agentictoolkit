import { eq, isNull } from "drizzle-orm";
import type { Db } from "../libsql/client";
import { issues } from "../libsql/schema";
import { notifyIssueAlert } from "./alerts";
import type { IssueSource } from "./issue-sources";
import type { Board } from "../board/types";

// ---------------------------------------------------------------------------
// The LEDGER. `issues` is no longer where a Problem is decided — `deriveBoard` is
// (src/board/). This file only RECORDS the board's verdict, because the table keeps
// three things a derived board cannot: alert dedup (the uniq_open_issue_per_target
// partial unique index), the onset time a problem started, and 90 days of resolved
// history. Every verdict rule that used to live here now lives in the fold.
// ---------------------------------------------------------------------------

type OpenRow = typeof issues.$inferSelect;

/**
 * All currently-open issues, grouped by target, OLDEST FIRST — so `[0]` is the CANONICAL
 * row (the one carrying the true onset) and anything after it is a shadow.
 *
 * The DB partial unique index (`uniq_open_issue_per_target`) is supposed to keep each list
 * at one entry, and this returns every row anyway because DROPPING the extras is what let
 * them rot: a shadow the writer never saw was never updated and never resolved, so it sat
 * open forever, kept `GET /issues` claiming a problem the board had long since cleared,
 * and — being invisible — could not be cleaned up by the very cycle whose job that is. The
 * index has been violated in practice (pre-migration rows, manual backfills), and a
 * defence that hides the damage instead of repairing it is not a defence.
 *
 * ONE snapshot per apply — `applyBoardToLedger` below takes it once and decides
 * open/update/resolve for every target against it, instead of re-scanning `issues` per
 * row. Exported only so the tests can assert the ledger through the same view the writer
 * uses.
 */
export async function openByTarget(db: Db): Promise<Map<string, OpenRow[]>> {
  const rows = await db
    .select()
    .from(issues)
    .where(isNull(issues.resolvedAt))
    // `id` breaks the tie so two rows opened in the same millisecond still pick the same
    // canonical row on every read — an arbitrary canonical row is an arbitrary onset.
    .orderBy(issues.openedAt, issues.id);
  const map = new Map<string, OpenRow[]>();
  for (const r of rows) {
    const list = map.get(r.target);
    if (list) list.push(r);
    else map.set(r.target, [r]);
  }
  return map;
}

interface OpenInput {
  target: string;
  source: IssueSource;
  name: string;
  environment: string | null;
  severity: string;
  state: string;
  statusCode: number | null;
  detail: string | null;
  sourceUrl: string | null;
  liveUrl: string | null;
  // Commit behind a deploy-failure issue (deploy sources only); http/dns/stale
  // omit these, so they default to null.
  commitHash?: string | null;
  commitMessage?: string | null;
  commitRepo?: string | null;
}

async function openIssue(db: Db, v: OpenInput): Promise<void> {
  // onConflictDoNothing guards the partial unique index against a race.
  await db.insert(issues).values(v).onConflictDoNothing();
  notifyIssueAlert({ kind: 'opened', target: v.target, name: v.name, environment: v.environment, state: v.state, detail: v.detail });
}

async function updateIssue(
  db: Db,
  id: number,
  v: Pick<
    OpenInput,
    "source" | "name" | "environment" | "severity" | "state" | "statusCode" | "detail" | "sourceUrl" | "liveUrl" | "commitHash" | "commitMessage" | "commitRepo"
  >,
): Promise<void> {
  // Refresh the links AND the commit too: an open issue's observation-derived
  // fields must track the latest deploy (e.g. a Railway deploy's source now
  // points at the project dashboard, or a re-run with a newer commit), not stay
  // frozen at whatever the issue was first opened with.
  //
  // `environment` and `name` are two more of those fields, not identity: the board DERIVES
  // both from the roster entry and the deploy row (`ownedDeployTarget`), while the TARGET
  // is minted from the provider id. So a row opened under an older env derivation keeps the
  // wrong tier on its badge, and a row opened before an upstream RENAME goes on naming a
  // project nothing answers to — in both cases for as long as it stays open, because an
  // open row is updated and never re-opened, and nothing short of a hand-written UPDATE
  // would clear it.
  await db
    .update(issues)
    .set({
      source: v.source,
      name: v.name,
      environment: v.environment,
      severity: v.severity,
      state: v.state,
      statusCode: v.statusCode,
      detail: v.detail,
      sourceUrl: v.sourceUrl,
      liveUrl: v.liveUrl,
      commitHash: v.commitHash ?? null,
      commitMessage: v.commitMessage ?? null,
      commitRepo: v.commitRepo ?? null,
      updatedAt: new Date(),
    })
    .where(eq(issues.id, id));
}

/**
 * Close an issue. `reason` decides whether on-call hears about it:
 *
 *  - `"recovered"` — the thing we were watching came back. That is the alert
 *    worth sending, the counterpart of openIssue's.
 *  - `"unmonitored"` — the issue is being closed because the operator stopped
 *    monitoring the target (a provider token removed, a project un-wired), NOT
 *    because it recovered. Alerting "✅ resolved" here tells on-call an outage
 *    cleared when it did not — it may still be burning. Stay silent.
 *  - `"duplicate"` — a SHADOW row for a target that already has a canonical open
 *    row (see `openByTarget`). Not an observation about the world at all, just the
 *    ledger repairing itself, so it says nothing to anyone. `readIssueEvents`
 *    (`board/facts.ts`) narrows every unknown reason to null, which drops these
 *    out of the activity feed too — an activity row per repaired duplicate would
 *    be the same false claim as alerting on one.
 *
 * Making the reason an explicit argument (rather than leaving it to whichever
 * call site remembers to bypass this function) is what keeps them apart: the
 * endpoint prune still closes its rows with a raw update, and the deleted
 * applyPlatformIssues used to route a token-removal through the alerting path
 * because nothing forced it to state its reason.
 */
async function resolveIssue(
  db: Db,
  cur: OpenRow,
  reason: "recovered" | "unmonitored" | "duplicate",
): Promise<void> {
  await db
    .update(issues)
    .set({ resolvedAt: new Date(), resolvedReason: reason, updatedAt: new Date() })
    .where(eq(issues.id, cur.id));
  if (reason !== "recovered") return;
  notifyIssueAlert({ kind: 'resolved', target: cur.target, name: cur.name, environment: cur.environment, state: cur.state, detail: cur.detail });
}

/**
 * Retire every SHADOW row for a target — `rows[1..]`, where `rows` came from
 * `openByTarget` oldest-first, so the canonical row is untouched.
 *
 * Called on BOTH ledger paths (a target the board still flags, and one it has stopped
 * flagging) because a shadow is stale either way: only the canonical row is updated and
 * only the canonical row is resolved, so a shadow left alone is an open issue nothing will
 * ever touch again. Repairing on the update path in particular is what keeps a duplicate
 * from outliving a problem that never resolves.
 *
 * Silent by construction — `resolveIssue`'s `"duplicate"` reason never alerts — because
 * this is bookkeeping, not an observation. A warning per row so a violated unique index
 * leaves a trail rather than being quietly papered over.
 */
async function closeShadows(db: Db, rows: OpenRow[]): Promise<void> {
  for (const dup of rows.slice(1)) {
    await resolveIssue(db, dup, "duplicate");
    console.warn(
      `[ledger] retired duplicate open issue #${dup.id} for ${dup.target} — uniq_open_issue_per_target should have prevented it`,
    );
  }
}

/** One row's write failed. Log the target and keep going — see `applyBoardToLedger`'s
 *  per-row fail-soft note for why one bad row must not take the cycle tail down. */
function logLedgerFailure(target: string, err: unknown): void {
  console.error(
    `[ledger] write failed for ${target} — skipped, the next cycle re-derives it: ${err instanceof Error ? err.message : String(err)}`,
  );
}

// ---------------------------------------------------------------------------
// ONE-TIME EFFECT on the first cycle after this ships. Expected, and deliberately neither
// migrated nor suppressed. The OLD deploy target was a hand-rolled literal,
// `${platform}|${projectName}|${environment ?? ""}`; the new one is
// `boardTargetKey(owner.platform, entryIdentity(owner), d.environment)`. FOUR independent
// differences fall out of that, and one live row can hit several at once:
//
//   1. PROJECT NAME → PROVIDER ID. `entryIdentity` is `providerProjectId ?? projectName`
//      (`board/derive-problems.ts:23`), and `learnDeployProjectIds` (`sync.ts:674`)
//      backfills `deploy_project_id` on every full sync — so every already-wired endpoint
//      that has learned its id respells its target WHOLESALE:
//        `vercel|hub-help-testing|production` → `vercel|prj_0aB…|`
//      This is the biggest family by row count, and it is why the change is not merely
//      "the environment segment was dropped".
//   2. PLATFORM CANONICALISATION. `boardTargetKey` runs `platformCanon`
//      (`board/target-key.ts:26`); the old literal used the raw provider string:
//        `cloudflare-pages|temporal-web|` → `cloudflare|temporal-web|`
//   3. ENVIRONMENT SEGMENT BLANKED for every platform except Railway
//      (`board/target-key.ts:28`) — a domain fact, argued in `boardTargetKey`'s own doc:
//        `vercel|hub-help-testing|production` → `vercel|hub-help-testing|`
//        `crunchy|adh-prod|<ANY environment>` → `crunchy|adh-prod|`
//   4. RAILWAY ENVIRONMENT CASE-FOLDED. Railway keeps its segment, but lower-cased, where
//      the old key carried the provider's raw casing:
//        `railway|adh-backend|Production` → `railway|adh-backend|production`
//
// Staleness changed SHAPE rather than spelling: `vercel-stale|<name>` now speaks the
// deploy target's own key (`vercel|<id-or-name>|`), which is what lets `deriveBoard`
// suppress a stale row behind a failed-deploy row for the same project.
//
// Unchanged: HTTP targets (the bare endpoint id) and `platform-health|<source>`.
//
// What an operator SEES, both halves of it:
//   • The CLOSE is silent. An old-spelled target is not in `monitoredTargets`, so it
//     resolves as `unmonitored` and pages nobody — the correct reading, because we did not
//     observe a recovery.
//   • The REOPEN ALERTS. `openIssue` notifies UNCONDITIONALLY, so the first full cycle
//     after this ships fires one `opened` page per currently-open deploy and stale-prod
//     issue, in a single batch, nearly all of them duplicates of alerts already sent. That
//     is a one-time burst on the deploy, not a new outage — and on-call should be told to
//     expect it. The new row's `since` also falls back to its deploy's own timestamp, so a
//     still-burning problem shows a fresh onset once.
//
// Deliberately NOT a data migration (weighed and rejected: it buys one field, one time,
// and owes a correctness argument per family above) and deliberately NOT one-shot alert
// suppression (machinery that exists for a single event, can only ever be exercised once,
// and whose failure mode is swallowing a real page). So: a doubled target in the resolved
// history and a burst of `opened` alerts around this deploy are intended, not corruption.
//
// A SECOND ONE-TIME EFFECT, of the same family and settled the same way: the env badge on
// an already-RESOLVED incident. `derive-activity.ts` reads an issue row's `environment`
// off this ledger, and only OPEN rows are refreshed (`updateIssue`, every cycle) — a
// resolved row keeps whatever was last written to it. Rows resolved BEFORE the tier fix
// shipped therefore still carry Vercel's promotion target, so a resolved testing incident
// wears a PROD badge while the live Problem beside it, derived fresh, correctly says
// testing. Bounded and self-clearing: an issue event leaves Recent Activity at
// ACTIVITY_WINDOW_MS (24h), so every visible badge is correct one day after the deploy,
// and no row can acquire a stale env afterwards. Same verdict as above — not worth a
// migration, and not worth teaching the fold to re-derive history it was not asked to
// rewrite. (Note which way that cuts: `updateIssue` refreshing `environment` and `name`
// at all is a deliberate choice that the ledger's copy tracks CURRENT truth rather than
// open-time truth. Resolved rows are the one place it cannot, because nothing writes
// them again.)
// ---------------------------------------------------------------------------

/**
 * Write the board's verdict into the ledger. The board decides; this only RECORDS —
 * which is the whole point of demoting `issues` from truth to a ledger. It keeps three
 * things the derived board cannot: alert dedup (via uniq_open_issue_per_target), the
 * onset time a problem started, and 90 days of resolved history.
 *
 * Resolution compares the FULL target string. The old `issueOrphaned` compared only the
 * project segment for deploy targets, so a Railway target whose environment left config
 * survived every sweep and stayed open forever.
 *
 * No `nowMs` parameter, deliberately. The rule that makes the clock a parameter is about
 * `deriveBoard`, which must be PURE so the regression suite can drive it. This is the
 * opposite kind of function — it exists to write rows — and its three primitives each
 * stamp `new Date()` themselves, as they have at every call site they ever had. Taking a
 * `nowMs` it cannot hand to any of them would document a guarantee it does not make.
 *
 * PER-ROW FAIL-SOFT. One target's write is caught, logged and skipped, and the returned
 * counts report only what actually landed. Each of the four recorders this replaced caught
 * per-row (`076fe254b:issues.ts:335,449,551,636`), and folding them into one loop without
 * that isolation moved the blast radius rather than removing it: an exception here escapes
 * `runCycle`, and `runMonitorCycle` rethrows past its `finally`, skipping `fetchPeers`,
 * `collectTelemetry`, `runMaintenance`, `maybeSnapshotDb` and `pingHeartbeat`
 * (`cycle-runner.ts:24-45`). Retention pruning not running is what previously drove the
 * per-tick cost past the container's CPU quota. On a config route the same throw turns an
 * already-committed DELETE into an unfixable 500. The board is DERIVED, so anything
 * skipped is re-derived and rewritten on the next cycle — dropping one row is recoverable,
 * dropping the cycle tail is not.
 */
export async function applyBoardToLedger(
  db: Db,
  board: Board,
): Promise<{ opened: number; updated: number; resolved: number; resolvedTargets: string[] }> {
  const open = await openByTarget(db);
  const live = new Map(board.problems.map((p) => [p.target, p]));
  let opened = 0;
  let updated = 0;

  for (const [target, p] of live) {
    const rows = open.get(target) ?? [];
    const cur = rows[0];
    try {
      if (!cur) {
        await openIssue(db, {
          target, source: p.source, name: p.name, environment: p.environment,
          severity: p.severity, state: p.state, statusCode: p.statusCode, detail: p.detail,
          sourceUrl: p.sourceUrl, liveUrl: p.liveUrl, commitHash: p.commitHash,
          commitMessage: p.commitMessage, commitRepo: p.commitRepo,
        });
        opened++;
      } else {
        await updateIssue(db, cur.id, {
          source: p.source, name: p.name, environment: p.environment, severity: p.severity, state: p.state, statusCode: p.statusCode,
          detail: p.detail, sourceUrl: p.sourceUrl, liveUrl: p.liveUrl,
          commitHash: p.commitHash, commitMessage: p.commitMessage, commitRepo: p.commitRepo,
        });
        await closeShadows(db, rows);
        updated++;
      }
    } catch (err) {
      logLedgerFailure(target, err);
    }
  }

  // Closing a row is TWO different events and they must not be flattened. A target the
  // board still watches but no longer flags RECOVERED — alert. A target the board no
  // longer watches at all (site deleted, project renamed, monitoring switched off) is
  // UNMONITORED — close it silently, because we did not observe a recovery and the
  // outage may still be burning. `resolveIssue` takes the reason precisely so a call
  // site cannot route a de-configuration through the alerting path by forgetting.
  const watched = new Set(board.monitoredTargets);
  const stale = [...open.keys()].filter((t) => !live.has(t));
  // Only what actually closed. Reporting `stale.length` would tell an operator (and
  // `POST /board/reconcile`'s caller) that a row was retired when its write threw.
  const resolvedTargets: string[] = [];
  for (const t of stale) {
    const rows = open.get(t) ?? [];
    const cur = rows[0];
    if (!cur) continue;
    try {
      // The canonical row closes with the real reason and may alert; its shadows close
      // silently, so a duplicated target cannot page on-call twice for one recovery.
      await resolveIssue(db, cur, watched.has(t) ? "recovered" : "unmonitored");
      resolvedTargets.push(t);
      await closeShadows(db, rows);
    } catch (err) {
      logLedgerFailure(t, err);
    }
  }
  return { opened, updated, resolved: resolvedTargets.length, resolvedTargets };
}
