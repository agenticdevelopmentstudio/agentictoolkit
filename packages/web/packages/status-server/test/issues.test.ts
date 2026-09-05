import { describe, it, expect, vi } from 'vitest';
import { eq, isNull, sql } from 'drizzle-orm';
import {
  deployments,
  issues,
  monitoredEndpoints,
  monitoredSites,
  platformHealthState,
  siteGroups,
  vercelProdState,
} from '../src/libsql/schema';
import { createIntegration, deleteIntegration } from '../src/storage/config-store';
import { applyBoardToLedger, openByTarget } from '../src/monitor/issues';
import { notifyIssueAlert } from '../src/monitor/alerts';

// The alert assertions below need the module stubbed — `notifyIssueAlert` lives in
// `src/monitor/alerts`, which `alerts.int.test.ts` exercises for real.
vi.mock('../src/monitor/alerts', () => ({ notifyIssueAlert: vi.fn(), flushAlerts: vi.fn() }));
const alertMock = vi.mocked(notifyIssueAlert);
import {
  dropVanishedVercelProjects,
  PLATFORM_UNREACHABLE_POLLS,
  type ConfiguredDeployTargets,
} from '../src/monitor/issue-sources';
import { boardTargetKey, reconcileBoardLedger } from '../src/board';
import type { Board, Problem } from '../src/board';
import { recordPlatformObservations, recordVercelProdStates } from '../src/monitor/observations';
import { freshDb } from './helpers/db';
import { testConfig } from './helpers/config';

type TestDb = Awaited<ReturnType<typeof freshDb>>;

/**
 * A board carrying exactly these problems and watching exactly these targets. The two
 * lists are independent on purpose: `applyBoardToLedger` closes a row differently
 * depending on whether its target is still WATCHED (a recovery, which alerts) or gone
 * (unmonitored, which stays silent).
 */
function board(problems: Problem[], monitoredTargets: string[]): Board {
  return {
    generatedAt: new Date(3000).toISOString(),
    // The ledger writer never reads the data clock — it records the verdict the board
    // already made. Stated anyway so the shape is a real Board, not a partial one.
    dataAsOfMs: 3000, probeIntervalMs: 60_000, activityFromMs: 0,
    indicator: problems.length > 0 ? 'degraded' : 'operational',
    problems,
    activity: [],
    monitoredTargets,
  };
}

/** An endpoint Problem for target 'svc'. An endpoint target is the endpoint's BARE id
 *  (`board/types.ts`), so this one is deliberately not `boardTargetKey` output. */
function httpProblem(over: Partial<Problem> = {}): Problem {
  return {
    target: 'svc',
    source: 'http',
    name: 'My Service',
    environment: 'production',
    severity: 'major',
    state: 'down',
    statusCode: 503,
    detail: 'HTTP 503',
    sourceUrl: 'https://svc.example.com',
    liveUrl: 'https://svc.example.com',
    commitHash: null,
    commitMessage: null,
    commitRepo: null,
    branch: null,
    errorText: null,
    since: new Date(2000).toISOString(),
    ...over,
  };
}

async function insertOpen(db: TestDb, target: string, source: string) {
  await db.insert(issues).values({ target, source, name: target, severity: 'major', state: 'down' });
}

const openRows = (db: TestDb) => db.select().from(issues).where(isNull(issues.resolvedAt));

describe('the HTTP ledger row (the board decides, the ledger records)', () => {
  // The VERDICT half of this block — down → a Problem, healthy → none, a DNS failure →
  // `source: "dns"` — belongs to `endpointProblems` now and is asserted over the fold in
  // `test/board-endpoint.test.ts`. What is still this file's is the LEDGER half: what the
  // board's verdict does to the `issues` table.

  it('opens a row for a down service and resolves it on recovery', async () => {
    const db = await freshDb();

    // 1) DOWN → exactly one OPEN row for target 'svc'.
    await applyBoardToLedger(db, board([httpProblem()], ['svc']));

    const opened = await openRows(db);
    expect(opened).toHaveLength(1);
    expect(opened[0]!.target).toBe('svc');
    expect(opened[0]!.state).toBe('down');
    expect(opened[0]!.source).toBe('http');
    expect(opened[0]!.resolvedAt).toBeNull();
    const openedId = opened[0]!.id;

    // 2) Healthy → the board derives no Problem, but still WATCHES 'svc'.
    await applyBoardToLedger(db, board([], ['svc']));

    expect(await openRows(db)).toHaveLength(0);
    const all = await db.select().from(issues);
    expect(all).toHaveLength(1); // recovery resolves the existing row, doesn't add one
    expect(all[0]!.id).toBe(openedId);
    expect(all[0]!.resolvedAt).not.toBeNull();
    // resolveIssue's whole reason for taking a `reason` argument: a `recovered` close is
    // the only kind the Activity feed may report as a "[state] resolved" row.
    expect(all[0]!.resolvedReason).toBe('recovered');
  });

  it('keeps ONE open row per target across repeated bad boards', async () => {
    const db = await freshDb();

    await applyBoardToLedger(db, board([httpProblem({ state: 'down', statusCode: 503 })], ['svc']));
    // A second bad cycle UPDATES the open row (severity/state/detail) — never a second
    // open row (the uniq_open_issue_per_target invariant).
    const res = await applyBoardToLedger(
      db,
      board([httpProblem({ state: 'degraded', statusCode: null, detail: 'slow: 1200ms' })], ['svc']),
    );
    expect(res).toMatchObject({ opened: 0, updated: 1, resolved: 0 });

    const open = await openRows(db);
    expect(open).toHaveLength(1);
    expect(open[0]!.state).toBe('degraded'); // updated in place
    expect(open[0]!.detail).toBe('slow: 1200ms');
  });

  it("records the Problem's own source, so a DNS failure lands as a dns row", async () => {
    const db = await freshDb();
    // `endpointProblems` is what classifies `dnsOk: false` as source 'dns'; the ledger's
    // job is to WRITE that verdict, never to re-derive it from the state word.
    await applyBoardToLedger(db, board([httpProblem({ source: 'dns' })], ['svc']));
    const open = await openRows(db);
    expect(open).toHaveLength(1);
    expect(open[0]!.source).toBe('dns');
  });
});

/**
 * The owned-project sets this narrowing consumes. They used to be built here by
 * `siteOwnedDeployTargets`, which is gone: ownership is resolved once, id-first, in
 * `src/board/ownership.ts` (`rosterDeployProjects`), and asserted in
 * `test/board-ownership.test.ts`. `dropVanishedVercelProjects` takes the RESULT of that,
 * so the literal here is exactly what the caller now hands it.
 */
function ownedProjects(
  over: Partial<Record<keyof ConfiguredDeployTargets, string[]>>,
): ConfiguredDeployTargets {
  return {
    vercel: new Set(over.vercel ?? []),
    railway: new Set(over.railway ?? []),
    cloudflare: new Set(over.cloudflare ?? []),
  };
}

describe('dropVanishedVercelProjects (a project deleted upstream owns nothing)', () => {
  it('drops the Vercel projects the account no longer has, and reports them', () => {
    const owned = ownedProjects({
      vercel: ['web-prod', 'docs-old'],
      railway: ['adh-backend'],
      cloudflare: ['temporal-web'],
    });

    const { configured, vanished } = dropVanishedVercelProjects(owned, new Set(['web-prod']));

    expect(vanished).toEqual(['docs-old']);
    expect([...configured.vercel]).toEqual(['web-prod']);
    // Vercel ONLY: Railway/Cloudflare are polled live every cycle, so they have no
    // equivalent staleness and must never be narrowed by a Vercel read.
    expect([...configured.railway]).toEqual(['adh-backend']);
    expect([...configured.cloudflare]).toEqual(['temporal-web']);
  });

  it('changes nothing when every owned project still exists', () => {
    const owned = ownedProjects({ vercel: ['web-prod'] });
    const out = dropVanishedVercelProjects(owned, new Set(['web-prod', 'unrelated']));
    expect(out.vanished).toEqual([]);
    expect(out.configured).toBe(owned); // untouched, not a rebuilt copy
  });

  it('narrows NOTHING on an empty live set — that reads as a broken/rescoped token, not a wiped account', () => {
    // The dangerous input: an "authoritative" read that returned no projects at all. Acting
    // on it would DELETE every Vercel monitor on the board (the cycle retires whatever
    // `vanished` names); declining leaves the operator Problems they can see.
    const owned = ownedProjects({ vercel: ['web-prod', 'docs-old'] });
    const out = dropVanishedVercelProjects(owned, new Set());
    expect(out.vanished).toEqual([]);
    expect(out.configured).toBe(owned);
  });

  it('narrows NOTHING when EVERY owned project is missing — a complete read of the WRONG scope', () => {
    // The read succeeded and returned projects, so the emptiness guard above passes: this is
    // what a re-scoped token or a changed VERCEL_TEAM_ID looks like. Every monitored name is
    // absent, which is indistinguishable from "the whole account was deleted" — and one of
    // those two readings costs the operator every monitor they have.
    const owned = ownedProjects({ vercel: ['web-prod', 'docs-old'] });
    const out = dropVanishedVercelProjects(owned, new Set(['someone-elses-project']));
    expect(out.vanished).toEqual([]);
    expect(out.configured).toBe(owned);
  });

  it('still acts when SOME owned projects survive — the guard is all-or-nothing, not a mute', () => {
    const owned = ownedProjects({ vercel: ['web-prod', 'docs-old'] });
    const out = dropVanishedVercelProjects(owned, new Set(['web-prod']));
    expect(out.vanished).toEqual(['docs-old']);
    expect([...out.configured.vercel]).toEqual(['web-prod']);
  });
});

describe('the orphan sweep is now membership in monitoredTargets', () => {
  // What `reconcileOrphanedIssues` used to answer with its own second spelling of a target
  // key and six differently-shaped config slices. The board already knows what it watches,
  // so "is this Problem still real" is a consequence of the fold. The old exemptions are
  // not special cases any more — an exempt target is simply IN `monitoredTargets` — but
  // each one is a shipped regression, so each keeps a case.

  it('resolves an issue whose endpoint is no longer monitored, keeps the live one', async () => {
    const db = await freshDb();
    await insertOpen(db, 'gone', 'dns');
    await insertOpen(db, 'live', 'dns');

    // The board still watches 'live' and still derives its problem; 'gone' appears in
    // neither list, which is the only thing the sweep consults.
    await applyBoardToLedger(db, board([httpProblem({ target: 'live', source: 'dns' })], ['live']));

    expect((await openRows(db)).map((r) => r.target)).toEqual(['live']);
  });

  it('exempts platform-health issues (provider-level, not a site)', async () => {
    const db = await freshDb();
    await insertOpen(db, 'platform-health|vercel', 'vercel');
    // No sites AT ALL, but Vercel is configured and has failed enough consecutive polls
    // to be a Problem — so `monitoredTargets` carries its target and the row survives.
    // The old sweep needed a hardcoded prefix exemption to get here.
    for (let i = 0; i < PLATFORM_UNREACHABLE_POLLS; i++) {
      await recordPlatformObservations(db, [{ source: 'vercel', configured: true, reachable: false }]);
    }
    await reconcileBoardLedger(db, testConfig());
    expect((await openRows(db)).map((r) => r.target)).toEqual(['platform-health|vercel']);
  });

  it('exempts crunchy deploy targets (platform-owned, always-configured; not site-bound)', async () => {
    const db = await freshDb();
    // A cluster has no HTTP host, so no roster entry can ever own one — it is watched and
    // judged with no site behind it. `boardTargetKey` leaves the env segment empty for
    // every platform but Railway, so the target is `crunchy|adh-testing|`.
    const target = boardTargetKey('crunchy', 'adh-testing', 'testing')!;
    await insertOpen(db, target, 'crunchy');
    await db.insert(deployments).values({
      id: 'cr_1', platform: 'crunchy', projectName: 'adh-testing', environment: 'testing',
      buildPhase: 'failed', deployPhase: 'none', createdAt: new Date(),
    });
    await reconcileBoardLedger(db, testConfig()); // no sites at all
    expect((await openRows(db)).map((r) => r.target)).toEqual([target]); // survives, not resolved
  });

  it('keys resolution on the TARGET string, never on the source column (corruption-robust)', async () => {
    const db = await freshDb();
    // A deploy issue for a watched project whose source got mislabeled 'http'. The old
    // sweep classified the row by SHAPE precisely to survive this; the new one never reads
    // the column at all — the full target string is the whole key.
    await insertOpen(db, 'vercel|web-prod|', 'http');
    await applyBoardToLedger(
      db,
      board(
        [httpProblem({ target: 'vercel|web-prod|', source: 'vercel', state: 'failed' })],
        ['vercel|web-prod|'],
      ),
    );
    expect((await openRows(db)).map((r) => r.target)).toEqual(['vercel|web-prod|']);
  });

  it('resolves a deploy issue for a project no site owns', async () => {
    const db = await freshDb();
    await insertOpen(db, 'vercel|ghost|', 'vercel');
    await applyBoardToLedger(db, board([], ['vercel|real|']));
    expect(await openRows(db)).toHaveLength(0);
  });

  it('keeps a deploy issue for a project a site owns (canonical platform match)', async () => {
    const db = await freshDb();
    // `boardTargetKey` canonicalises `cloudflare-pages` → `cloudflare`, so a site wired to
    // the raw platform string and the ledger row for it agree on one spelling. Minting the
    // watched target here rather than writing the literal is what pins that.
    const target = boardTargetKey('cloudflare-pages', 'temporal-web', null)!;
    expect(target).toBe('cloudflare|temporal-web|');
    await insertOpen(db, target, 'cloudflare-pages');
    await applyBoardToLedger(
      db,
      board([httpProblem({ target, source: 'cloudflare-pages', state: 'failed' })], [target]),
    );
    expect(await openRows(db)).toHaveLength(1);
  });

  it('resolves a vercel-stale issue for a project no site owns', async () => {
    const db = await freshDb();
    // `vercel-stale|<project>` is the pre-Task-12 spelling: staleness is now a `vercel|X|`
    // Problem like any other, so a surviving row of the old shape can never be in
    // `monitoredTargets` and closes on the first sweep — SILENTLY, because we never
    // observed it recover. That one-time close is intended, and is why no migration
    // respells these rows.
    await insertOpen(db, 'vercel-stale|ghost', 'vercel');
    await applyBoardToLedger(db, board([], ['vercel|real|']));
    const all = await db.select().from(issues);
    expect(all[0]!.resolvedAt).not.toBeNull();
    expect(all[0]!.resolvedReason).toBe('unmonitored');
  });

  it('resolves the Problems of a WIRED project that vanished upstream — and touches no config', async () => {
    const db = await freshDb();
    // The stuck state from the field: a site still wired to a Vercel project that was
    // deleted, whose last failed build kept its Problem open with no way to clear it.
    // `staleProdProblems` / `monitoredTargets` narrow the roster against the live project
    // list, so a vanished project contributes no watched target — the sweep FOLLOWS from
    // the fold instead of being a second rule kept in step by hand.
    await insertOpen(db, 'vercel|docs-old|', 'vercel');
    await insertOpen(db, 'vercel-stale|docs-old', 'vercel');
    await insertOpen(db, 'docs', 'http');

    // The endpoint's own problem is still derived and its target still watched, alongside
    // the surviving sibling project. Neither `docs-old` target is watched any more.
    await applyBoardToLedger(db, board([httpProblem({ target: 'docs' })], ['docs', 'vercel|web-prod|']));

    // Both deploy Problems are gone from the board, while the endpoint's OWN down issue
    // stays: the ledger judges issue targets, never config. Retiring the monitor that
    // owned the vanished project is a separate step the cycle takes (retireUnclaimedMonitors
    // in monitor/sync) — keeping it out of here is what lets this run on every cycle.
    expect((await openRows(db)).map((r) => r.target)).toEqual(['docs']);
    // Resolved, not deleted: the incidents stay in history.
    expect(await db.select().from(issues)).toHaveLength(3);
  });
});

describe('Vercel production staleness — the mirror is the fact, and a null link is UNRESOLVED', () => {
  async function seedVercelSite(db: TestDb) {
    // `staleProdProblems` only speaks for a project some roster entry OWNS, so unlike the
    // ledger cases above this one genuinely needs a site: without it the fold derives
    // nothing and every assertion below would pass vacuously.
    await db.insert(siteGroups).values({ id: 'grp-1', name: 'Hub', slug: 'hub' });
    await db.insert(monitoredSites).values({ id: 'site-1', siteGroupId: 'grp-1', name: 'Web', slug: 'web' });
    await db.insert(monitoredEndpoints).values({
      id: 'ep-1', siteId: 'site-1', url: 'https://web-prod.example.com',
      platform: 'vercel', deployProject: 'web-prod', environment: 'production', isActive: true,
    });
  }
  const stale = (over: Partial<{ stale: boolean; detail: string | null; sourceUrl: string | null; liveUrl: string | null }> = {}) => ({
    projectName: 'web-prod', stale: true, detail: 'live production is behind',
    sourceUrl: null, liveUrl: null, ...over,
  });

  it("does NOT resolve a stale issue when its project is absent from this cycle's read (transient/paginated API)", async () => {
    const db = await freshDb();
    await seedVercelSite(db);
    await recordVercelProdStates(db, [stale()]);
    await reconcileBoardLedger(db, testConfig());
    expect((await openRows(db)).map((r) => r.target)).toEqual(['vercel|web-prod|']);

    // The next read does not mention the project at all. The old [#8] sweep resolved on
    // absence → it flapped open/resolved every cycle. An empty read now deletes nothing
    // from the mirror, the fold still reads a stale row, and the ledger row stays open.
    await recordVercelProdStates(db, []);
    await reconcileBoardLedger(db, testConfig());
    expect((await openRows(db)).map((r) => r.target)).toEqual(['vercel|web-prod|']);
  });

  it('still resolves a stale issue when the project IS reported and is no longer stale', async () => {
    const db = await freshDb();
    await seedVercelSite(db);
    await recordVercelProdStates(db, [stale()]);
    await reconcileBoardLedger(db, testConfig());
    expect(await openRows(db)).toHaveLength(1);

    await recordVercelProdStates(db, [stale({ stale: false, detail: null })]);
    await reconcileBoardLedger(db, testConfig());
    expect(await openRows(db)).toHaveLength(0);
    // Still WATCHED — the site is wired, it just stopped being stale. That is a recovery.
    expect((await db.select().from(issues))[0]!.resolvedReason).toBe('recovered');
  });

  it('keeps the existing sourceUrl/liveUrl when this cycle could not resolve them', async () => {
    const db = await freshDb();
    // Both links are best-effort decoration resolved on a budget: fetchTeamSlug returns
    // null when the poll ran out of time, and liveUrl only lands once an endpoint matches.
    // A cycle's null means "didn't resolve", NEVER "no longer exists" — writing it through
    // blanked the operator's only route to the failing build's log, on exactly the issue
    // telling them to go look at it. The rule lives in the MIRROR the board reads, so this
    // asserts against `recordVercelProdStates` rather than against the ledger writer.
    await recordVercelProdStates(db, [
      stale({ sourceUrl: 'https://vercel.com/acme/web-prod/dpl_1', liveUrl: 'https://web-prod.example.com' }),
    ]);
    await recordVercelProdStates(db, [stale()]); // both links null this cycle
    const [row] = await db.select().from(vercelProdState);
    expect(row!.sourceUrl).toBe('https://vercel.com/acme/web-prod/dpl_1');
    expect(row!.liveUrl).toBe('https://web-prod.example.com');

    // ...and a link that DID resolve still wins over the stored one.
    await recordVercelProdStates(db, [stale({ sourceUrl: 'https://vercel.com/acme/web-prod/dpl_2' })]);
    const [after] = await db.select().from(vercelProdState);
    expect(after!.sourceUrl).toBe('https://vercel.com/acme/web-prod/dpl_2');
    expect(after!.liveUrl).toBe('https://web-prod.example.com'); // untouched by a null
  });
});

describe('a retry in flight must not close the failure it is retrying', () => {
  async function seedVercelSite(db: TestDb) {
    await db.insert(siteGroups).values({ id: 'grp-1', name: 'Hub', slug: 'hub' });
    await db.insert(monitoredSites).values({ id: 'site-1', siteGroupId: 'grp-1', name: 'Web', slug: 'web' });
    await db.insert(monitoredEndpoints).values({
      id: 'ep-1', siteId: 'site-1', url: 'https://web-prod.example.com',
      platform: 'vercel', deployProject: 'web-prod', environment: 'production', isActive: true,
      monitorHttp: false,
    });
  }
  type DeployRow = typeof deployments.$inferInsert;
  const row = (over: Partial<DeployRow> & Pick<DeployRow, 'id' | 'createdAt'>): DeployRow => ({
    platform: 'vercel', projectName: 'web-prod', environment: 'production',
    deployPhase: 'none', ...over,
  });

  /**
   * The clock this case is stamped against, and the one every `reconcileBoardLedger` call
   * below derives at. Both halves matter and neither is decoration.
   *
   * The rows here used to be stamped `new Date(1000)` / `new Date(2000)` — two seconds
   * after the epoch — while the reconcile derived at the real `Date.now()`. That made the
   * in-flight retry ~57 YEARS old, far past `STUCK_DEPLOY_MS`. Against the code this case
   * exists to pin (the merged single-list selection), the retry won the group, was judged
   * `stuck`, and emitted a Problem for the SAME target — so the ledger row was `updateIssue`d
   * rather than closed, and all four assertions held WITHOUT the fix. A retry is minutes
   * old, not decades; stamping it that way is what makes this case able to fail.
   */
  const NOW = Date.now();

  it('leaves the ledger row OPEN and pages nobody while the fix is still building', async () => {
    const db = await freshDb();
    await seedVercelSite(db);
    await db.insert(deployments).values(
      row({ id: 'dpl_bad', buildPhase: 'failed', createdAt: new Date(NOW - 10 * 60_000) }),
    );
    await reconcileBoardLedger(db, testConfig(), { nowMs: NOW });
    const [opened] = await openRows(db);
    expect(opened!.target).toBe('vercel|web-prod|');

    // The fix is pushed two minutes ago — newest row for the target, and nowhere near
    // `STUCK_DEPLOY_MS`, so `stuck` cannot stand in for the failure. It used to win
    // `max(created_at)` outright, emptying the Problems list and closing this row as
    // `recovered` while production still served the broken build.
    alertMock.mockClear();
    await db.insert(deployments).values(
      row({ id: 'dpl_fix', buildPhase: 'building', createdAt: new Date(NOW - 2 * 60_000) }),
    );
    await reconcileBoardLedger(db, testConfig(), { nowMs: NOW });

    const all = await db.select().from(issues);
    expect(all).toHaveLength(1);
    expect(all[0]!.id).toBe(opened!.id);      // same row, not reopened
    expect(all[0]!.resolvedAt).toBeNull();    // still open
    expect(all[0]!.state).toBe('failed');     // as the FAILURE, not as a stuck build
    expect(alertMock).not.toHaveBeenCalled(); // and nobody was told it recovered

    // The retry LANDS. That is the observation that closes it, and it alerts.
    await db.update(deployments)
      .set({ buildPhase: 'built', deployPhase: 'deployed', createdAt: new Date(NOW - 60_000) })
      .where(eq(deployments.id, 'dpl_fix'));
    await reconcileBoardLedger(db, testConfig(), { nowMs: NOW });
    const after = await db.select().from(issues);
    expect(after[0]!.resolvedAt).not.toBeNull();
    expect(after[0]!.resolvedReason).toBe('recovered');
    expect(alertMock).toHaveBeenCalledTimes(1);
  });
});

describe('platform-unreachable debounce', () => {
  // The streak itself — one failed poll advances it by ONE, and PLATFORM_UNREACHABLE_POLLS
  // failures are required before a Problem exists — belongs to `recordPlatformObservations`
  // and is asserted in `test/observations.test.ts`. What is the LEDGER's is WHY a row closed.

  it('closing an issue because the platform stopped being CONFIGURED persists resolvedReason "unmonitored", not "recovered"', async () => {
    const db = await freshDb();
    for (let i = 0; i < PLATFORM_UNREACHABLE_POLLS; i++) {
      await recordPlatformObservations(db, [{ source: 'vercel', configured: true, reachable: false }]);
    }
    await reconcileBoardLedger(db, testConfig());
    expect(await openRows(db)).toHaveLength(1);

    // The operator pulls the token: not configured. Nothing recovered — we simply
    // stopped looking, and the provider may still be down. Only "recovered" closes may
    // become an Activity "[state] resolved" row, so this MUST persist as "unmonitored".
    await recordPlatformObservations(db, [{ source: 'vercel', configured: false, reachable: false }]);
    await reconcileBoardLedger(db, testConfig());

    const all = await db.select().from(issues);
    expect(all).toHaveLength(1);
    expect(all[0]!.resolvedAt).not.toBeNull();
    expect(all[0]!.resolvedReason).toBe('unmonitored');
  });

  it('a platform that came BACK closes as recovered — still configured, so still watched', async () => {
    const db = await freshDb();
    for (let i = 0; i < PLATFORM_UNREACHABLE_POLLS; i++) {
      await recordPlatformObservations(db, [{ source: 'vercel', configured: true, reachable: false }]);
    }
    await reconcileBoardLedger(db, testConfig());
    await recordPlatformObservations(db, [{ source: 'vercel', configured: true, reachable: true }]);
    await reconcileBoardLedger(db, testConfig());

    const all = await db.select().from(issues);
    expect(all).toHaveLength(1);
    expect(all[0]!.resolvedReason).toBe('recovered');
  });

  /**
   * DELETING THE INTEGRATION IS THE OPERATOR SAYING THE PLATFORM IS GONE — Requirement A
   * ("turning off any monitoring switch removes the site from Problems") for platform
   * health, the way it already holds for the endpoint switches.
   *
   * Three call sites (`DELETE /config/integrations/:id`, the `delete_platform` MCP tool)
   * follow `deleteIntegration` with `reconcileBoardLedger(db, testConfig())` and document it as retiring
   * rows that "can no longer be re-derived". That was false while the delete touched only
   * `deploy_integrations`: `platformProblems` reads `platform_health_state.configured`,
   * which nothing outside a monitor cycle rewrote, so the Problem re-derived unchanged and
   * the row sat open. These cases are written through the STORE (not the route) because
   * the store is where the fix has to live for both call sites to get it.
   */
  it('deleting the integration un-configures the platform, so the reconcile closes its row as unmonitored', async () => {
    const db = await freshDb();
    const integration = await createIntegration(db, { platform: 'cloudflare', label: 'Cloudflare' });
    for (let i = 0; i < PLATFORM_UNREACHABLE_POLLS; i++) {
      await recordPlatformObservations(db, [{ source: 'cloudflare-pages', configured: true, reachable: false }]);
    }
    await reconcileBoardLedger(db, testConfig());
    expect(await openRows(db)).toHaveLength(1);

    // Cloudflare deliberately: the integration row spells it `cloudflare` and the health
    // row spells it `cloudflare-pages`, so a cast between the two vocabularies would pass
    // every other platform and silently skip this one.
    await deleteIntegration(db, integration.id);
    const [health] = await db.select().from(platformHealthState);
    expect(health!.configured).toBe(false);
    // The monitor's heartbeat is NOT restamped by a config mutation — that column feeds
    // `Board.dataAsOfMs`, and a write that is not a cycle must never refresh it.
    expect(health!.updatedAt.getTime()).toBeLessThanOrEqual(Date.now());

    await reconcileBoardLedger(db, testConfig());
    const all = await db.select().from(issues);
    expect(all).toHaveLength(1);
    expect(all[0]!.resolvedAt).not.toBeNull();
    // NOT "recovered": we did not observe Cloudflare come back, we stopped looking.
    expect(all[0]!.resolvedReason).toBe('unmonitored');
  });

  it('leaves the platform configured while ANOTHER active integration still speaks for it', async () => {
    const db = await freshDb();
    const first = await createIntegration(db, { platform: 'vercel', label: 'Vercel (team A)' });
    await createIntegration(db, { platform: 'vercel', label: 'Vercel (team B)' });
    for (let i = 0; i < PLATFORM_UNREACHABLE_POLLS; i++) {
      await recordPlatformObservations(db, [{ source: 'vercel', configured: true, reachable: false }]);
    }
    await reconcileBoardLedger(db, testConfig());
    expect(await openRows(db)).toHaveLength(1);

    // Un-configuring here would silence a platform we ARE still polling — an absence of
    // data reported as health, in the direction that hides a real outage.
    await deleteIntegration(db, first.id);
    const [health] = await db.select().from(platformHealthState);
    expect(health!.configured).toBe(true);
    await reconcileBoardLedger(db, testConfig());
    expect(await openRows(db)).toHaveLength(1);
  });

  it('an INACTIVE leftover integration does not keep the platform configured', async () => {
    const db = await freshDb();
    const live = await createIntegration(db, { platform: 'vercel', label: 'Vercel' });
    await createIntegration(db, { platform: 'vercel', label: 'Vercel (retired)', isActive: false });
    for (let i = 0; i < PLATFORM_UNREACHABLE_POLLS; i++) {
      await recordPlatformObservations(db, [{ source: 'vercel', configured: true, reachable: false }]);
    }
    await reconcileBoardLedger(db, testConfig());

    // `providerConnFromConfig` reads ACTIVE rows only, so an inactive one polls nothing
    // and cannot be the reason we still call the platform configured.
    await deleteIntegration(db, live.id);
    const [health] = await db.select().from(platformHealthState);
    expect(health!.configured).toBe(false);
    await reconcileBoardLedger(db, testConfig());
    const all = await db.select().from(issues);
    expect(all[0]!.resolvedReason).toBe('unmonitored');
  });
});

describe("applyBoardToLedger", () => {
  it("opens a ledger row for a new problem", async () => {
    const db = await freshDb();
    const board = { generatedAt: new Date(3000).toISOString(), dataAsOfMs: 3000, probeIntervalMs: 60_000, activityFromMs: 0, indicator: "degraded" as const, activity: [],
      monitoredTargets: ["vercel|hub-help-testing|"],
      problems: [{ target: "vercel|hub-help-testing|", source: "vercel" as const, name: "hub-help-testing",
        environment: "production", severity: "major" as const, state: "failed", statusCode: null,
        detail: "wip", sourceUrl: null, liveUrl: null, commitHash: "a", commitMessage: "wip",
        commitRepo: "adh", branch: null, errorText: null, since: new Date(2000).toISOString() }] };
    expect(await applyBoardToLedger(db, board)).toMatchObject({ opened: 1, resolved: 0 });
    const rows = await db.select().from(issues);
    expect(rows).toHaveLength(1);
    expect(rows[0]!.resolvedAt).toBeNull();
  });

  it("is idempotent — re-applying the same board opens nothing new", async () => {
    const db = await freshDb();
    const board = { generatedAt: new Date(3000).toISOString(), dataAsOfMs: 3000, probeIntervalMs: 60_000, activityFromMs: 0, indicator: "degraded" as const, activity: [],
      monitoredTargets: ["vercel|hub-help-testing|"],
      problems: [{ target: "vercel|hub-help-testing|", source: "vercel" as const, name: "hub-help-testing",
        environment: "production", severity: "major" as const, state: "failed", statusCode: null,
        detail: "wip", sourceUrl: null, liveUrl: null, commitHash: "a", commitMessage: "wip",
        commitRepo: "adh", branch: null, errorText: null, since: new Date(2000).toISOString() }] };
    await applyBoardToLedger(db, board);
    expect(await applyBoardToLedger(db, board)).toMatchObject({ opened: 0 });
    expect(await db.select().from(issues)).toHaveLength(1);
  });

  // A row opened while the board still trusted Vercel's promotion target carries
  // `environment: "production"` for a project whose logical tier is testing, and an open row
  // is UPDATED, never re-opened — so without this the wrong badge outlives the fix on every
  // issue already in the ledger, and only a hand-written UPDATE would clear it. `environment`
  // is derived from the platform + project name, exactly like the links and the commit that
  // `updateIssue` already refreshes for this reason.
  it("refreshes an open row's environment, so a re-derived tier is not frozen at open time", async () => {
    const db = await freshDb();
    await db.insert(issues).values({ target: "vercel|hub-help-testing|", source: "vercel",
      name: "hub-help-testing", environment: "production", severity: "major", state: "failed",
      openedAt: new Date(2000) });
    const board = { generatedAt: new Date(3000).toISOString(), dataAsOfMs: 3000, probeIntervalMs: 60_000, activityFromMs: 0, indicator: "degraded" as const, activity: [],
      monitoredTargets: ["vercel|hub-help-testing|"],
      problems: [{ target: "vercel|hub-help-testing|", source: "vercel" as const, name: "hub-help-testing",
        environment: "testing", severity: "major" as const, state: "failed", statusCode: null,
        detail: "wip", sourceUrl: null, liveUrl: null, commitHash: "a", commitMessage: "wip",
        commitRepo: "adh", branch: null, errorText: null, since: new Date(2000).toISOString() }] };
    expect(await applyBoardToLedger(db, board)).toMatchObject({ opened: 0, updated: 1 });
    expect((await db.select().from(issues))[0]!.environment).toBe("testing");
  });

  // The same argument as the environment above, for the field right next to it. `name` is
  // `owner?.projectName ?? d.projectName` — an observation off the roster, not part of the
  // target — and the target is minted from the provider ID precisely so a RENAME upstream
  // keeps the same row. Leave `name` frozen and that row goes on naming the project by a
  // name nothing answers to, on the board and in every alert body, until it resolves.
  it("refreshes an open row's NAME too, so an upstream rename is not frozen at open time", async () => {
    const db = await freshDb();
    await db.insert(issues).values({ target: "vercel|prj_abc|", source: "vercel",
      name: "hub-web", environment: "production", severity: "major", state: "failed",
      openedAt: new Date(2000) });
    const board = { generatedAt: new Date(3000).toISOString(), dataAsOfMs: 3000, probeIntervalMs: 60_000, activityFromMs: 0, indicator: "degraded" as const, activity: [],
      monitoredTargets: ["vercel|prj_abc|"],
      problems: [{ target: "vercel|prj_abc|", source: "vercel" as const, name: "hub-web-v2",
        environment: "production", severity: "major" as const, state: "failed", statusCode: null,
        detail: "wip", sourceUrl: null, liveUrl: null, commitHash: "a", commitMessage: "wip",
        commitRepo: "adh", branch: null, errorText: null, since: new Date(2000).toISOString() }] };
    expect(await applyBoardToLedger(db, board)).toMatchObject({ opened: 0, updated: 1 });
    expect((await db.select().from(issues))[0]!.name).toBe("hub-web-v2");
  });

  it("resolves a ledger row the board no longer derives", async () => {
    const db = await freshDb();
    await db.insert(issues).values({ target: "vercel|hub-help-testing|", source: "vercel",
      name: "hub-help-testing", severity: "major", state: "failed", openedAt: new Date(2000) });
    // Still WATCHED, just no longer failing — a genuine recovery, so this one alerts.
    const recovered = { generatedAt: new Date(3000).toISOString(), dataAsOfMs: 3000, probeIntervalMs: 60_000, activityFromMs: 0, indicator: "operational" as const,
      problems: [], activity: [], monitoredTargets: ["vercel|hub-help-testing|"] };
    expect(await applyBoardToLedger(db, recovered)).toMatchObject({ resolved: 1 });
    expect((await db.select().from(issues))[0]!.resolvedAt).not.toBeNull();
  });

  it("isolates a failed write — one bad target must not cost the cycle its tail", async () => {
    const db = await freshDb();
    const quiet = vi.spyOn(console, 'error').mockImplementation(() => {});
    try {
      // Make the FIRST insert throw and let the rest through. Without per-row isolation the
      // throw escapes `runCycle`, `runMonitorCycle` rethrows past its `finally`, and
      // `fetchPeers` / `collectTelemetry` / `runMaintenance` / `maybeSnapshotDb` /
      // `pingHeartbeat` never run (`cycle-runner.ts:24-45`) — retention pruning silently
      // stopping is what drove the per-tick cost past the container's CPU quota. On a
      // config route the same throw 500s a DELETE that already committed.
      const realInsert = db.insert.bind(db);
      let inserts = 0;
      db.insert = ((...args: Parameters<TestDb['insert']>) => {
        if (++inserts === 1) throw new Error('disk I/O error');
        return realInsert(...args);
      }) as unknown as TestDb['insert'];

      const res = await applyBoardToLedger(
        db,
        board([httpProblem({ target: 'ep-1' }), httpProblem({ target: 'ep-2', name: 'Two' })], ['ep-1', 'ep-2']),
      );

      // The survivor is written, and the count reports what LANDED — not what was attempted.
      expect(res.opened).toBe(1);
      expect((await openRows(db)).map((r) => r.target)).toEqual(['ep-2']);
      expect(quiet).toHaveBeenCalledTimes(1);
    } finally {
      quiet.mockRestore();
    }
  });

  it("counts only the rows that actually closed", async () => {
    const db = await freshDb();
    const quiet = vi.spyOn(console, 'error').mockImplementation(() => {});
    try {
      await insertOpen(db, 'ep-1', 'http');
      await insertOpen(db, 'ep-2', 'http');
      const realUpdate = db.update.bind(db);
      let updates = 0;
      db.update = ((...args: Parameters<TestDb['update']>) => {
        if (++updates === 1) throw new Error('disk I/O error');
        return realUpdate(...args);
      }) as unknown as TestDb['update'];

      // Both targets are stale (no problems), but only one close survives. `resolved` and
      // `resolvedTargets` must describe reality — `POST /board/reconcile` shows them to an
      // operator, and "retired 2" over a row still open is a lie they cannot see through.
      const res = await applyBoardToLedger(db, board([], []));
      expect(res.resolved).toBe(1);
      expect(res.resolvedTargets).toEqual(['ep-2']);
      expect((await openRows(db)).map((r) => r.target)).toEqual(['ep-1']);
    } finally {
      quiet.mockRestore();
    }
  });
});

describe("issueOrphaned — the whole target, not just the project", () => {
  it("orphans a Railway target whose ENVIRONMENT left config", async () => {
    const db = await freshDb();
    await db.insert(issues).values({ target: "railway|adh-backend|scratch1", source: "railway",
      name: "adh-backend", severity: "major", state: "failed", openedAt: new Date(2000) });
    // The board watches the PRODUCTION env of the same project but not scratch1. The old
    // issueOrphaned compared only `parts[1]` ("adh-backend") and so declared this target
    // still configured, leaving it open forever.
    const empty = { generatedAt: new Date(3000).toISOString(), dataAsOfMs: 3000, probeIntervalMs: 60_000, activityFromMs: 0, indicator: "operational" as const,
      problems: [], activity: [], monitoredTargets: ["railway|adh-backend|production"] };
    await applyBoardToLedger(db, empty);
    expect((await db.select().from(issues))[0]!.resolvedAt).not.toBeNull();
  });

  it("closes a de-configured target SILENTLY, but a recovered one alerts", async () => {
    const db = await freshDb();
    alertMock.mockClear();

    // Watched and no longer failing → a real recovery → alert.
    await db.insert(issues).values({ target: "vercel|watched|", source: "vercel", name: "watched",
      severity: "major", state: "failed", openedAt: new Date(2000) });
    await applyBoardToLedger(db, { generatedAt: new Date(3000).toISOString(), dataAsOfMs: 3000, probeIntervalMs: 60_000, activityFromMs: 0,
      indicator: "operational" as const, problems: [], activity: [],
      monitoredTargets: ["vercel|watched|"] });
    expect(alertMock).toHaveBeenCalledTimes(1);

    // No longer watched → we never observed a recovery → stay silent.
    alertMock.mockClear();
    await db.insert(issues).values({ target: "vercel|gone|", source: "vercel", name: "gone",
      severity: "major", state: "failed", openedAt: new Date(2000) });
    await applyBoardToLedger(db, { generatedAt: new Date(4000).toISOString(), dataAsOfMs: 4000, probeIntervalMs: 60_000, activityFromMs: 0,
      indicator: "operational" as const, problems: [], activity: [], monitoredTargets: [] });
    expect(alertMock).not.toHaveBeenCalled();
  });
});

describe("reconcileBoardLedger — empty-roster policy", () => {
  it("skips the sweep on an empty roster when the caller only OBSERVED the emptiness", async () => {
    const db = await freshDb();
    await db.insert(issues).values({
      target: "vercel|a|", source: "vercel", name: "a",
      severity: "major", state: "failed", openedAt: new Date(),
    });
    const r = await reconcileBoardLedger(db, testConfig(), { skipOnEmptyRoster: true });
    expect(r).toMatchObject({ resolved: 0, skipped: true });
    expect((await db.select().from(issues))[0]!.resolvedAt).toBeNull();
  });

  it("sweeps an empty roster by default — deleting the last site must retire its issues", async () => {
    const db = await freshDb();
    await db.insert(issues).values({
      target: "vercel|a|", source: "vercel", name: "a",
      severity: "major", state: "failed", openedAt: new Date(),
    });
    const r = await reconcileBoardLedger(db, testConfig());
    expect(r).toMatchObject({ resolved: 1, skipped: false });
    expect((await db.select().from(issues))[0]!.resolvedAt).not.toBeNull();
  });
});

// ---------------------------------------------------------------------------
// SHADOW ROWS. `uniq_open_issue_per_target` is meant to make a second open row for one
// target impossible, and it has failed to in practice (rows predating the index, manual
// backfills). The writer used to see only the FIRST row per target, which meant a shadow
// was never updated, never resolved, and stayed open forever behind a problem the board
// had long since cleared. Both specs drop the index to manufacture the state it normally
// prevents — the only way to reach the code path that repairs it.
// ---------------------------------------------------------------------------
describe("duplicate open rows (a violated uniq_open_issue_per_target)", () => {
  const TARGET = "svc";

  async function dbWithTwoOpenRows(): Promise<TestDb> {
    const db = await freshDb();
    await db.run(sql`drop index uniq_open_issue_per_target`);
    // Deliberately inserted NEWEST first, so a writer taking DB order rather than
    // `openedAt` would pick the wrong canonical row and report the wrong onset.
    await db.insert(issues).values([
      { target: TARGET, source: "http", name: "My Service", severity: "major",
        state: "down", detail: "shadow", openedAt: new Date(9000) },
      { target: TARGET, source: "http", name: "My Service", severity: "major",
        state: "down", detail: "canonical", openedAt: new Date(2000) },
    ]);
    alertMock.mockClear();
    return db;
  }

  const resolvedAlerts = () => alertMock.mock.calls.filter((c) => c[0]!.kind === "resolved");

  it("openByTarget keeps every row, oldest first", async () => {
    const db = await dbWithTwoOpenRows();
    const rows = (await openByTarget(db)).get(TARGET)!;
    expect(rows.map((r) => r.detail)).toEqual(["canonical", "shadow"]);
  });

  it("a still-failing target updates the canonical row and retires the shadow", async () => {
    const db = await dbWithTwoOpenRows();
    const b = board([httpProblem({ detail: "still down" })], [TARGET]);
    expect(await applyBoardToLedger(db, b)).toMatchObject({ opened: 0, updated: 1 });

    const rows = await db.select().from(issues).orderBy(issues.openedAt);
    expect(rows.map((r) => [r.detail, r.resolvedReason])).toEqual([
      ["still down", null],
      ["shadow", "duplicate"],
    ]);
    // Retiring a shadow is bookkeeping, not an observation — it must never alert.
    expect(resolvedAlerts()).toHaveLength(0);
  });

  it("a recovered target closes BOTH rows and alerts exactly once", async () => {
    const db = await dbWithTwoOpenRows();
    expect(await applyBoardToLedger(db, board([], [TARGET]))).toMatchObject({ resolved: 1 });

    const rows = await db.select().from(issues).orderBy(issues.openedAt);
    expect(rows.every((r) => r.resolvedAt !== null)).toBe(true);
    expect(rows.map((r) => r.resolvedReason)).toEqual(["recovered", "duplicate"]);
    expect(resolvedAlerts()).toHaveLength(1);
  });
});
