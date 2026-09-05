import type { BuildPhase, DeployPhase } from "../monitor/deploy-status";
import { commitFirstLine } from "../monitor/format";
import type { IssueSource } from "../monitor/issue-sources";
import { monitoredTargets, parseErrorsTarget, parsePlatformHealthTarget } from "./derive-problems";
import { ownedDeployTarget, rosterTargets, type RosterIndex } from "./ownership";
import { ACTIVITY_WINDOW_MS, MAX_ACTIVITY_ROWS } from "./types";
import type {
  ActivityCursor, ActivityKind, ActivityPage, ActivityRow, ActivityTone, BoardFacts, Indicator,
  IssueEvent, Problem,
} from "./types";

// The row vocabulary, server-side. The BOARD's rows are spelled here and the client
// renders what arrives — the server decides what a row SAYS for the same reason it
// decides whether the row exists.
//
// These four maps are the ONLY copy, and module-private to keep it that way. The client
// used to hold a byte-identical duplicate for `deploymentToRows`, which spelled a
// Deployments tab straight from raw /live deployments; that function lost its last caller
// when the board moved server-side, so both it and the duplicate are gone. A deploy row's
// words are the server's now, for the same reason its existence is. (`ISSUE_VERB` below is
// the one that still has a client counterpart, and is exported for exactly that reason.)
const BUILD_VERB: Record<BuildPhase, string> = {
  queued: "queued",
  building: "building",
  built: "built",
  failed: "build failed",
  canceled: "canceled",
  // The backend expired an in-flight phase it could not re-confirm for hours — an
  // ABSENCE of a verdict, shown muted. This is also why activity does not re-run the
  // client's old 10-minute "unconfirmed" demotion: `expireUnconfirmedDeploys` already
  // writes that state into the DB, so the fold reads it instead of racing it.
  unknown: "outcome unknown",
};
const BUILD_TONE: Record<BuildPhase, ActivityTone> = {
  queued: "progress", building: "progress", built: "good",
  failed: "bad", canceled: "neutral", unknown: "stale",
};
const DEPLOY_VERB: Record<Exclude<DeployPhase, "none">, string> = {
  deploying: "deploying", deployed: "deployed", failed: "deploy failed", unknown: "outcome unknown",
};
const DEPLOY_TONE: Record<Exclude<DeployPhase, "none">, ActivityTone> = {
  deploying: "progress", deployed: "good", failed: "bad", unknown: "stale",
};

/**
 * The observed bad state → the word the pane shows. Shipping the raw enum instead would
 * regress five states at once: "failed" reads as a generic failure rather than a deploy
 * one, and "unreachable" loses the fact that it is the MONITOR that is blind, not the
 * site that is down.
 *
 * The client's `STATE_LABEL` (`web/src/lib/row-model.ts`) is a byte-identical copy and is
 * PERMANENT. An earlier version of this comment said Task 13 would delete it "when it
 * deletes the last thing that reads it" — it did not, and could not: `problemToRow` still
 * reads it, and `problemToRow` renders the Problems list. A `Problem` carries no verb (an
 * `ActivityRow` does), so the client spells that pane's word from `p.state` itself. Both
 * panes describe the same incident, so the two maps must agree word for word —
 * `row-vocabulary-parity.test.ts` is what makes them.
 */
export const ISSUE_VERB: Record<string, string> = {
  down: "down",
  degraded: "degraded",
  failed: "deploy failed",
  stuck: "deploy stuck",
  // "stale" = the live production deployment is behind/errored while newer builds sit
  // ahead of it unpromoted — i.e. the deployment itself has failed.
  stale: "deployment failed",
  // "unreachable" = the deploy provider's own API could not be polled, so we are blind
  // to that platform's deploys. A monitor-side problem, not a deploy's.
  unreachable: "platform unreachable",
  // "erroring" = the app is THROWING while its host answers normally. Deliberately not
  // "errors": every other word here is a state the thing is IN, and the distinction this
  // row exists to make is that a reachable site can still be broken.
  erroring: "app errors",
};

/**
 * Which pane vocabulary an issue event speaks. `IssueSource` has no `platform-health`
 * member — a platform-health issue's SOURCE is the platform itself, and only its TARGET
 * says what kind of thing it is (`platform-health|<source>`, `issues.ts:611`). So the
 * target is what this reads, and everything else is a probe (http/dns) or a deploy.
 *
 * AN ERRORS TARGET HAS TO BE READ HERE TOO, and the reason is the trailing `: "deploy"`.
 * That branch is not a default so much as a catch-all, so any source it has not been
 * taught lands in it — and `deployCounts` (`web/src/lib/overview.ts`) tallies
 * `kind === "deploy" && tone === "bad"` into the FAILED-BUILDS KPI. An unread
 * `errors|<project>` event would therefore report a GlitchTip issue as a failed
 * deployment on the overview strip.
 *
 * It joins `platform` rather than earning a fourth `ActivityKind`: the axis this type
 * names is which PANE VOCABULARY a row speaks, and an error tracker speaks the same one a
 * provider-health row does — a fleet-wide signal about the machinery, not a build and not
 * a probe of one site. A fourth member would have to be mirrored in
 * `web/src/lib/board-types.ts`, pass the parity test, and be taught to three client folds,
 * all to render identically to `platform`.
 */
function issueKind(e: IssueEvent): ActivityKind {
  if (parsePlatformHealthTarget(e.target) !== null) return "platform";
  if (parseErrorsTarget(e.target) !== null) return "platform";
  return e.source === "http" || e.source === "dns" ? "probe" : "deploy";
}

/**
 * A deployment's two activity rows, named by the ONLY thing about that deployment that
 * cannot change: its provider id (the `deployments` primary key) and which of its two
 * lifecycles the row reports.
 *
 * NOTHING MUTABLE MAY ENTER THIS ID. The id used to carry the target and `createdAtMs`
 * too, and both of those are corrected in place by `upsertDeployments`:
 *
 *   - `created_at` is `min(excluded.created_at, created_at)` — deliberately so. A webhook
 *     seeds the row with the EVENT's emission time; the next poll lowers it to the
 *     provider's true creation time. Nothing bounds that drop: `toValidDate` checks only
 *     that the provider's value is a finite date, and a queued or retried deployment can
 *     be emitted HOURS after it was created.
 *   - `branch` and `project_name` are COALESCE'd / renamed the same way, and both feed
 *     `ownedDeployTarget`, so the target moves too.
 *
 * When a correction landed, the same deployment minted a SECOND id. Server-side that is
 * invisible — there is only ever one row per deployment in the fold's output — but the
 * CLIENT keys the feed by id, and `useActivityHistory` treats an id that leaves
 * `board.activity` as a row the live window SHED and keeps it for the life of the tab
 * (`mergeRows` never replaces one). So the pre-correction copy became immortal, frozen at
 * whatever phase it carried at that instant — `queued` or `building` — and sorted BELOW
 * its own `built`/`deployed` rows, because the stale copy holds the later, uncorrected
 * timestamp. No board refetch could clear it: the ⟳ button replaces `board.activity`, and
 * the zombie does not live there. That is the "several sites stuck on building hours
 * after they went green" report.
 *
 * The step stays spelled `build`/`deploy` and stays LAST, because the feed's tie-break at
 * one timestamp is a plain string compare over the whole id: with the rest of the id
 * shared, `build` < `deploy` keeps a deployment's build row above its deploy row — and
 * that shared `deploy:<id>:` prefix now also keeps the pair adjacent whatever the project
 * is called.
 */
function deployRowId(deploymentId: string, step: "build" | "deploy"): string {
  return `deploy:${deploymentId}:${step}`;
}

/**
 * An issue's row id. Unlike a deployment's, this one KEEPS its timestamp, and deliberately:
 * `issues.opened_at` is written once at open and never updated, and `resolved_at` once at
 * resolution — neither is ever corrected the way `deployments.created_at` is — so nothing
 * here can move under a rendered row. `target` likewise comes from the issue itself, not
 * from a mutable deploy-project mapping. The timestamp also does real work: one issue
 * emits an open row and a resolve row at DIFFERENT instants, so the step word alone would
 * not distinguish them the way it does for a deployment's two rows.
 */
function issueRowId(e: IssueEvent, step: "opened" | "resolved", atMs: number): string {
  return `issue:${e.target}:${step}:${atMs}:${e.id}`;
}

/**
 * Activity is a RECORD OF EVENTS, not the complement of the Problems list. A failed
 * deploy appears in BOTH: it is a problem (it is still broken) and it is activity (it
 * happened). Treating the two as disjoint is regression c40b87542 — a build that failed
 * "migrated out" of the feed into Problems and the feed went empty exactly when the
 * fleet was busiest.
 *
 * The feed is the union of two event streams, per the spec's §Activity: every deployment
 * in the window (`facts.deployEvents` — the LOG, not `facts.deploys`/`inFlightDeploys`,
 * which are the current state per target and would collapse a busy day into one row per
 * site), and every issue opened or resolved in the window.
 *
 * `kind` is the event's own kind and is never recomputed from `tone` (defect #1: the old
 * client store re-derived kind from tone at activity-store.ts:322, so a neutral deploy
 * became a probe row).
 */
export function deriveActivity(
  facts: BoardFacts,
  nowMs: number,
  index?: RosterIndex,
  monitoredIn?: ReadonlySet<string>,
  /**
   * The inclusive floor for an event's timestamp. Defaults to the board's 24h window,
   * which is what every live read wants. A HISTORY page passes its own floor (0 for
   * "whatever the cursor query returned"), so the same fold serves both windows and
   * there is still exactly one derivation of what happened. `nowMs` is otherwise unused
   * here — it existed only to compute this.
   */
  fromMs?: number,
  /**
   * How many rows the fold may return. Defaults to `MAX_ACTIVITY_ROWS`, the live feed's
   * cap. A HISTORY page passes `Infinity`: its input is already bounded by the three SQL
   * `limit`s beneath it, and capping HERE would shed the very oldest candidates — the end
   * `pageActivity` is walking towards — before the pager ever sees them, so the pager's
   * `trimmed` test would read false while up to five sixths of the page had been thrown
   * away, and it would then report the end of history with no cursor left to reach them.
   */
  cap?: number,
): ActivityRow[] {
  const idx = index ?? rosterTargets(facts.roster, facts.liveVercelProjects);
  const cutoff = fromMs ?? nowMs - ACTIVITY_WINDOW_MS;
  const rows: ActivityRow[] = [];
  // Targets the feed already carries a FAILED deploy row for, so a same-target issue
  // OPENING is not duplicated. Only a BAD-toned deploy row may claim a target: a `built`
  // row says the opposite of a `stale` issue and a `deploying` row says something
  // different from a `stuck` issue, so neither may suppress the issue that represents it.
  const deployFailureRecorded = new Set<string>();

  for (const d of facts.deployEvents) {
    // The same gate `deployProblems` applies, for the same reasons — shared via
    // `ownedDeployTarget` so Problems and Activity can never disagree about which
    // deployments exist.
    const owned = ownedDeployTarget(d, idx);
    if (!owned) continue;
    const { owner, target, env } = owned;

    const buildTone = d.buildPhase ? BUILD_TONE[d.buildPhase] : null;
    const deployTone = d.deployPhase === "none" ? null : DEPLOY_TONE[d.deployPhase];
    if (buildTone === "bad" || deployTone === "bad") deployFailureRecorded.add(target);

    // Below the floor, so this deployment's own rows belong to an OLDER page — but its
    // failure still has to suppress the issue that opened for it a second later, which
    // may well be ABOVE the floor. The set is therefore built from every deploy fact the
    // read returned, and only the row PUSH is gated. On the live path this changes
    // nothing (`readBoardFacts` reads exactly the window the fold cuts at); on a history
    // page it is what stops one incident rendering as a deploy row on page N+1 AND an
    // issue row on page N, which the cursor makes impossible for either page to notice.
    if (d.createdAtMs < cutoff) continue;

    const base = {
      kind: "deploy" as const,
      target,
      // The RAW platform, not the canonicalized one — same spelling `Problem.source` uses
      // (`derive-problems.ts:182`): `IssueSource` carries the literal `"cloudflare-pages"`,
      // and `platformCanon` folds that to `"cloudflare"`, which is not a member of the type.
      source: d.platform as IssueSource,
      name: owner?.projectName ?? d.projectName,
      // The LOGICAL TIER from `ownedDeployTarget`, never `d.environment` — that column is
      // the provider's promotion target, and every Vercel project's is "production".
      environment: env,
      detail: commitFirstLine(d.commitMessage),
      sourceUrl: d.sourceUrl,
      liveUrl: d.liveUrl,
      commitHash: d.commitHash,
      commitMessage: d.commitMessage,
      commitRepo: d.commitRepo,
      // The RAW branch, alongside the tier `env` derived from it — the details pane shows
      // the ref itself, which the tier word cannot be read back into.
      branch: d.branch,
      errorText: d.errorText,
      at: new Date(d.createdAtMs).toISOString(),
    };

    // A deployment is TWO events, and the pane has always shown them as two lines: the
    // build, and — once it got that far — the deploy. Collapsing them would drop the
    // distinction between "built but never promoted" and "deployed", which is exactly
    // what the `stale` Vercel problem is about.
    //
    // `buildPhase` is nullable (`schema.ts:68`) because some sources have no build step at
    // all — `crunchyPhases` returns `{ buildPhase: null, deployPhase: ... }`, a cluster's
    // health wearing a deploy row's clothes. No build happened, so no build row.
    if (d.buildPhase && buildTone) {
      // One spelling of the step, read by both the id and the field, so the two can never
      // drift into naming different halves of the same deployment.
      const step = "build" as const;
      rows.push({
        ...base,
        id: deployRowId(d.deploymentId, step),
        step,
        verb: BUILD_VERB[d.buildPhase],
        tone: buildTone,
      });
    }
    if (d.deployPhase !== "none" && deployTone) {
      const step = "deploy" as const;
      rows.push({
        ...base,
        id: deployRowId(d.deploymentId, step),
        step,
        verb: DEPLOY_VERB[d.deployPhase],
        tone: deployTone,
      });
    }
  }

  // Requirement A, on this half too: an endpoint, project, or platform we no longer
  // watch contributes nothing to either pane. `monitoredTargets` mints its deploy keys
  // exactly as the loop above does, so the two halves cannot disagree about a target's
  // spelling either.
  const monitored = monitoredIn ?? new Set(monitoredTargets(facts, idx));

  for (const e of facts.issueEvents) {
    if (!monitored.has(e.target)) continue;

    const base = {
      kind: issueKind(e),
      step: null,
      target: e.target,
      // The issue's own source — a probe's `http`/`dns`, or the platform for a
      // platform-health row. Both `issueKind` (one line above) and `Problem.source`
      // read this same field; Activity must not disagree with Problems about it.
      source: e.source,
      name: e.name,
      environment: e.environment,
      detail: e.detail,
      sourceUrl: e.sourceUrl,
      liveUrl: e.liveUrl,
      commitHash: e.commitHash,
      commitMessage: e.commitMessage,
      commitRepo: e.commitRepo,
      // An incident is not a build: there is no ref it came from and no provider text
      // explaining it. Stated rather than omitted, so the pane renders nothing on purpose.
      branch: null,
      errorText: null,
    };

    // An issue opening is suppressed only when the feed already carries a FAILED deploy
    // row for the same target: the provider's event and the incident we opened for it
    // are one thing that happened, a second apart, and the deploy row is the richer of
    // the two. A `built`/`deploying` (not-bad) deploy row must NOT suppress a `stale` or
    // `stuck` issue — that row says the opposite of what the issue is reporting. An
    // http/dns issue (whose target is an endpoint id, never a deploy target) and a
    // stale-prod issue on a project that did not deploy both keep their row: nothing else
    // in the feed represents them.
    if (e.openedAtMs >= cutoff && !deployFailureRecorded.has(e.target)) {
      rows.push({
        ...base,
        id: issueRowId(e, "opened", e.openedAtMs),
        verb: ISSUE_VERB[e.state] ?? e.state,
        // The client's exact expression (`row-model.ts:252`): a minor severity stays
        // amber, never red. "unreachable" is a monitor-side warning today and must not
        // ship as an outage.
        tone: e.severity === "minor" ? "progress" : "bad",
        at: new Date(e.openedAtMs).toISOString(),
      });
    }

    // Only a RECOVERED close. `unmonitored` means the target stopped being watched and
    // nothing was observed to recover; saying "[failed] resolved" there would tell an
    // operator the build passed while it may still be burning. `null` is a row resolved
    // before the reason column existed — unknown, so claim nothing.
    if (e.resolvedAtMs !== null && e.resolvedAtMs >= cutoff && e.resolvedReason === "recovered") {
      rows.push({
        ...base,
        id: issueRowId(e, "resolved", e.resolvedAtMs),
        verb: `[${ISSUE_VERB[e.state] ?? e.state}] resolved`,
        tone: "good",
        at: new Date(e.resolvedAtMs).toISOString(),
      });
    }
  }

  // Oldest first, and within one timestamp the build row sorts before its deploy row: the
  // whole feed reads top-to-bottom in the order things actually happened, and the newest
  // row lands at the BOTTOM, where the pane tails. (Both comparisons now run the same
  // direction — the tie-break used to be the only chronological thing in a newest-first
  // list, so a single deployment read forwards inside a feed that read backwards.)
  rows.sort((a, b) => (a.at === b.at ? (a.id === b.id ? 0 : a.id < b.id ? -1 : 1) : a.at < b.at ? -1 : 1));
  // Shed from the FRONT, not the back — the front is the oldest end now. Keeping the first
  // MAX_ACTIVITY_ROWS here would drop every recent row and serve a feed of pure history.
  // A history page passes `cap: Infinity` (see the parameter): shedding the oldest end is
  // exactly wrong when the oldest end is what the reader is scrolling towards.
  return rows.slice(-(cap ?? MAX_ACTIVITY_ROWS));
}

/**
 * The single overall indicator. Three rules, in order — no fourth interpretation
 * anywhere else in the system.
 */
export function indicatorFor(problems: Problem[]): Indicator {
  if (problems.length === 0) return "operational";
  if (problems.some((p) => p.severity === "critical")) return "outage";
  return "degraded";
}

/**
 * A cursor id minted before deploy rows were renamed to `deploy:<deploymentId>:<step>`.
 * The old grammar was `deploy:<target>:<step>:<atMs>:<deploymentId>` — five or more
 * colon-separated parts against the current three, and provider deployment ids contain no
 * colon, so the two are cleanly separable.
 *
 * A client can hold one across a server deploy: `cursorRef` lives for the life of the tab
 * (`use-activity-history.ts`), so the first page it requests afterwards carries the dead
 * shape. Comparing it byte-wise against current ids is undefined — whether the tie group
 * at that instant is re-served or SKIPPED comes down to which platform prefix sorts where
 * — and skipping is unrecoverable, because the cursor only ever moves backward.
 *
 * DELETABLE once no tab predating that deploy can still be open.
 */
function isRetiredDeployRowId(id: string): boolean {
  return id.startsWith("deploy:") && id.split(":").length > 3;
}

/** Total order over the feed: event time, then id. Matches `deriveActivity`'s own sort. */
function beforeCursor(r: ActivityRow, c: ActivityCursor): boolean {
  const atMs = Date.parse(r.at);
  if (atMs !== c.atMs) return atMs < c.atMs;
  // Incomparable id → serve the whole tie group at this instant rather than guess. That
  // costs the client rows it may already hold, which `mergeRows` collapses by id, and it
  // cannot loop: the next cursor is minted from the oldest row KEPT, in the live grammar.
  if (isRetiredDeployRowId(c.id)) return true;
  return r.id < c.id;
}

/**
 * Take one page of already-derived rows, ending strictly before `cursor`.
 *
 * `sourcesExhausted` says whether the SQL beneath this returned fewer rows than it asked
 * for — i.e. there is provably nothing older. It is the ONLY thing that may report the end
 * of history: a page that merely filled its limit says nothing about what lies behind it.
 *
 * The next cursor is the oldest row KEPT, never the oldest row fetched. Over-fetching (a
 * deployment row expanding into two output rows, or one source outrunning the other) then
 * costs a re-read of the trimmed tail on the next page, which is correct, rather than a
 * gap, which is silent.
 *
 * `floorMs` is the oldest instant the SQL beneath this read COMPLETELY — the newest of the
 * per-source floors, so below it at least one source still has unread rows. It is what a
 * page that kept nothing steps back to; see the empty branch.
 */
export function pageActivity(
  derived: ActivityRow[],
  cursor: ActivityCursor | null,
  limit: number,
  sourcesExhausted: boolean,
  floorMs: number | null = null,
): ActivityPage {
  const eligible = cursor == null ? derived : derived.filter((r) => beforeCursor(r, cursor));
  const sorted = [...eligible].sort((a, b) =>
    a.at === b.at ? (a.id === b.id ? 0 : a.id < b.id ? -1 : 1) : a.at < b.at ? -1 : 1,
  );
  const rows = sorted.slice(-limit);

  // Nothing was keepable. Two ways to get here, and NEITHER is the end of history:
  //
  //  - the fold dropped everything SQL returned (a run of issues on targets the roster no
  //    longer watches — `issues` is a ledger and retains those rows), or
  //  - every row we saw sorts at or after the cursor.
  //
  // `sourcesExhausted` is still the only thing allowed to report the end. It used to share
  // that authority with `derived.length === 0`, which is the FIRST case above and says
  // nothing whatever about what lies behind the window.
  //
  // Progress is measured against `floorMs`, the oldest instant this page read completely,
  // NOT against the cursor: a full page of unowned issues would otherwise cost one round
  // trip per tick of history. That instant is CONSUMED — every row in it was read and none
  // survived — so the next cursor excludes it whole, which is exactly what the empty-id
  // sentinel says: no real row id is empty, so `r.id < ""` is false for everything at that
  // instant. `readSourcePage` is what makes "read completely" true; without it the floor
  // could name a second the LIMIT cut through, and excluding it would strand the
  // remainder. `cursor` is necessarily non-null here: with no cursor every row is
  // eligible, so a non-empty input would have kept something.
  //
  // The step must NARROW, or the reader is pinned on one page forever — so the floor is
  // used only when it does. A floor older than the cursor always narrows; a floor ON the
  // cursor's own instant narrows only while the cursor still carried a real id, because
  // replacing that id with the sentinel drops the rest of the instant. Anything else
  // (including no floor at all) steps off the cursor's own instant instead.
  if (rows.length === 0) {
    if (sourcesExhausted || cursor == null) return { rows: [], nextCursor: null };
    const stepped =
      floorMs != null && (floorMs < cursor.atMs || (floorMs === cursor.atMs && cursor.id !== ""))
        ? floorMs
        : cursor.atMs - 1;
    return { rows: [], nextCursor: { atMs: stepped, id: "" } };
  }

  const trimmed = rows.length < sorted.length;
  const oldestKept = rows[0]!;
  const nextCursor =
    sourcesExhausted && !trimmed ? null : { atMs: Date.parse(oldestKept.at), id: oldestKept.id };
  return { rows, nextCursor };
}
