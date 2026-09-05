import { describe, it, expect } from "vitest";
import { deployProblems } from "../src/board/derive-problems";
import type { BoardFacts, DeployFact, RosterEntry } from "../src/board/types";
import { STUCK_DEPLOY_MS } from "../src/monitor/issue-sources";

const NOW = Date.UTC(2026, 7, 2, 12, 0, 0);

function entry(over: Partial<RosterEntry> = {}): RosterEntry {
  return {
    endpointId: "ep-1",
    label: "Hub Help (testing)",
    platform: "vercel",
    providerProjectId: null,
    projectName: "hub-help-testing",
    environment: "production",
    isActive: true,
    monitorHttp: true,
    monitorDeploys: true,
    ignoreProjectWarning: false,
    url: "https://testing.help.example.com",
    ...over,
  };
}

// Every ActivityRow id carries its fact's primary key, because the page cursor is the
// (time, id) PAIR and timestamps are whole seconds. A shared default would mint
// byte-identical ids here and hide exactly the collision that id is there to prevent.
let deploySeq = 0;
function deploy(over: Partial<DeployFact> = {}): DeployFact {
  return {
    deploymentId: `dpl_${++deploySeq}`,
    platform: "vercel",
    providerProjectId: null,
    projectName: "hub-help-testing",
    environment: "production",
    branch: null,
    buildPhase: "built",
    deployPhase: "deployed",
    createdAtMs: NOW - 60_000,
    commitHash: "abc1234",
    commitMessage: "fix: the thing",
    commitRepo: "adh",
    sourceUrl: "https://vercel.com/x/y",
    liveUrl: "https://testing.help.example.com",
    errorText: null,
    ...over,
  };
}

function facts(over: Partial<BoardFacts> = {}): BoardFacts {
  return {
    roster: [entry()],
    probeIntervalMs: 60_000,
    deploys: [],
    inFlightDeploys: [],
    deployEvents: [],
    endpoints: [],
    platforms: [],
    staleProd: [],
    ledger: [],
    issueEvents: [],
    liveVercelProjects: ["hub-help-testing"],
    errors: [], errorsConfigured: true, errorProjectAllowlist: null,
    ...over,
  };
}

describe("deployProblems — verdicts", () => {
  it("1. a succeeded latest deploy is NOT a problem", () => {
    expect(deployProblems(facts({ deploys: [deploy()] }), NOW)).toEqual([]);
  });

  it("2. a failed latest deploy IS a problem", () => {
    const p = deployProblems(facts({ deploys: [deploy({ buildPhase: "failed", deployPhase: "none" })] }), NOW);
    expect(p).toHaveLength(1);
    expect(p[0]).toMatchObject({ target: "vercel|hub-help-testing|", state: "failed", severity: "major" });
  });

  // Same rule the Activity pane obeys (board-activity.test.ts) and the one
  // `staleProdProblems` has always obeyed: a Problem's environment is the project's LOGICAL
  // TIER, read off the name by `deployEnv`, not Vercel's promotion target. Every Vercel
  // project's target is "production", so trusting the column labels a failed TESTING deploy
  // as a production incident.
  it("2b. a failed deploy's environment is the project's LOGICAL tier, not Vercel's target", () => {
    const p = deployProblems(facts({ deploys: [deploy({ buildPhase: "failed", deployPhase: "none" })] }), NOW);
    expect(p[0]?.environment).toBe("testing");
  });

  // 2b reads the tier off the NAME, which only works because the fixture project happens
  // to be spelled `-testing`. The BRANCH is what answers when the name says nothing — and
  // the name's default is "production", so without this a failed testing build on a
  // plainly-named project files itself as a production incident.
  it("2d. a failed deploy's environment comes from the BRANCH when the name has no suffix", () => {
    const f = facts({
      roster: [entry({ projectName: "hub" })],
      liveVercelProjects: ["hub"],
      deploys: [deploy({ projectName: "hub", branch: "prepared", buildPhase: "failed", deployPhase: "none" })],
    });
    const p = deployProblems(f, NOW);
    expect(p).toHaveLength(1);
    expect(p[0]?.environment).toBe("testing");
  });

  // The two fields the details pane needs and cannot derive: the ref the build came from,
  // and the provider's own reason for the failure. `detail` is the commit subject, so a
  // failed row without `errorText` shows an operator WHAT was being built and never WHY it
  // burned — the one thing they opened the pane for.
  it("2e. a failed deploy Problem carries the branch and the provider's errorText", () => {
    const f = facts({
      deploys: [deploy({
        buildPhase: "failed", deployPhase: "none",
        branch: "prepared", errorText: "[buildStep] Command \"next build\" exited with 1",
      })],
    });
    const p = deployProblems(f, NOW);
    expect(p).toHaveLength(1);
    expect(p[0]?.branch).toBe("prepared");
    expect(p[0]?.errorText).toBe("[buildStep] Command \"next build\" exited with 1");
  });

  it("2c. a Railway failure keeps the environment Railway itself reported", () => {
    const f = facts({
      roster: [entry({ platform: "railway", projectName: "adh-backend", environment: "testing" })],
      deploys: [deploy({ platform: "railway", projectName: "adh-backend", environment: "testing", buildPhase: "failed", deployPhase: "none" })],
    });
    const p = deployProblems(f, NOW);
    expect(p).toHaveLength(1);
    expect(p[0]?.environment).toBe("testing");
  });

  // The old version of this test passed a single BUILT+DEPLOYED row — the `deploy()`
  // default — and asserted no problem. There was no failure in the facts at all, so it
  // asserted nothing about a failure being CLEARED and would have stayed green through
  // any regression in the collapse. Both orderings are checked now, and both rows are in
  // the facts, so the assertion actually rests on "newest wins".
  it("3. THE REGRESSION: a failure followed by a success clears the problem", () => {
    const failed = deploy({ buildPhase: "failed", deployPhase: "none", createdAtMs: NOW - 7200_000 });
    const fixed = deploy({ createdAtMs: NOW - 60_000 });
    expect(deployProblems(facts({ deploys: [failed, fixed] }), NOW)).toEqual([]);
    // Same two facts, opposite array order: the winner is the newest row, never the last
    // one SQLite happened to return.
    expect(deployProblems(facts({ deploys: [fixed, failed] }), NOW)).toEqual([]);
  });

  it("3b. a success followed by a FAILURE is a problem, whichever order the facts arrive", () => {
    const fixed = deploy({ createdAtMs: NOW - 7200_000 });
    const failed = deploy({ buildPhase: "failed", deployPhase: "none", createdAtMs: NOW - 60_000 });
    for (const deploys of [[fixed, failed], [failed, fixed]]) {
      const p = deployProblems(facts({ deploys }), NOW);
      expect(p).toHaveLength(1);
      expect(p[0].state).toBe("failed");
    }
  });

  it("4. a deploy still BUILDING is not a problem", () => {
    const f = facts({
      inFlightDeploys: [deploy({ buildPhase: "building", deployPhase: "none", createdAtMs: NOW - 60_000 })],
    });
    expect(deployProblems(f, NOW)).toEqual([]);
  });

  it("5. a deploy building past STUCK_DEPLOY_MS IS a problem", () => {
    const f = facts({
      inFlightDeploys: [deploy({ buildPhase: "building", deployPhase: "none", createdAtMs: NOW - STUCK_DEPLOY_MS - 1 })],
    });
    const p = deployProblems(f, NOW);
    expect(p).toHaveLength(1);
    expect(p[0].state).toBe("stuck");
    expect(p[0].detail).toMatch(/^stuck building · \d+m$/);
  });

  it("6. a deploy QUEUED past the threshold is NOT stuck — a hold is intentional", () => {
    const f = facts({
      inFlightDeploys: [deploy({ buildPhase: "queued", deployPhase: "none", createdAtMs: NOW - STUCK_DEPLOY_MS * 10 })],
    });
    expect(deployProblems(f, NOW)).toEqual([]);
  });

  it("7. a CANCELED deploy is not a verdict and is never a problem", () => {
    const f = facts({ deploys: [deploy({ buildPhase: "canceled", deployPhase: "none" })] });
    expect(deployProblems(f, NOW)).toEqual([]);
  });

  it("8. a target NO roster entry owns is invisible", () => {
    const f = facts({ deploys: [deploy({ projectName: "some-infra-worker", buildPhase: "failed", deployPhase: "none" })] });
    expect(deployProblems(f, NOW)).toEqual([]);
  });

  it("9. an endpoint with ignoreProjectWarning owns no target", () => {
    const f = facts({
      roster: [entry({ ignoreProjectWarning: true })],
      deploys: [deploy({ buildPhase: "failed", deployPhase: "none" })],
    });
    expect(deployProblems(f, NOW)).toEqual([]);
  });

  it("10. a Vercel PREVIEW build (environment=null) is never a problem", () => {
    const f = facts({ deploys: [deploy({ environment: null, buildPhase: "failed", deployPhase: "none" })] });
    expect(deployProblems(f, NOW)).toEqual([]);
  });

  it("11. `since` comes from the ledger when the target already has an onset", () => {
    const opened = NOW - 3 * 3600_000;
    const f = facts({
      deploys: [deploy({ buildPhase: "failed", deployPhase: "none" })],
      ledger: [{ target: "vercel|hub-help-testing|", openedAtMs: opened }],
    });
    expect(deployProblems(f, NOW)[0].since).toBe(new Date(opened).toISOString());
  });

  it("12. `since` falls back to the deploy's own time when the ledger is silent", () => {
    const at = NOW - 5 * 60_000;
    const f = facts({ deploys: [deploy({ buildPhase: "failed", deployPhase: "none", createdAtMs: at })] });
    expect(deployProblems(f, NOW)[0].since).toBe(new Date(at).toISOString());
  });

  it("13. a Railway target keeps its env, so two envs are two problems", () => {
    const f = facts({
      roster: [
        entry({ endpointId: "ep-1", platform: "railway", projectName: "adh-backend", environment: "production" }),
        entry({ endpointId: "ep-2", platform: "railway", projectName: "adh-backend", environment: "scratch1" }),
      ],
      deploys: [
        deploy({ platform: "railway", projectName: "adh-backend", environment: "production", buildPhase: "built", deployPhase: "deployed" }),
        deploy({ platform: "railway", projectName: "adh-backend", environment: "scratch1", buildPhase: "failed", deployPhase: "failed" }),
      ],
    });
    const p = deployProblems(f, NOW);
    expect(p.map((x) => x.target)).toEqual(["railway|adh-backend|scratch1"]);
  });

  it("14. a deploy matches its roster entry by PROVIDER ID when both carry one, so a rename does not double-count", () => {
    const f = facts({
      roster: [entry({ providerProjectId: "prj_abc", projectName: "hub-help-testing-renamed" })],
      deploys: [deploy({ providerProjectId: "prj_abc", projectName: "hub-help-testing", buildPhase: "failed", deployPhase: "none" })],
    });
    const p = deployProblems(f, NOW);
    expect(p).toHaveLength(1);
    expect(p[0].target).toBe("vercel|prj_abc|");
    expect(p[0].name).toBe("hub-help-testing-renamed");
  });

  // 15/16 pin the Crunchy carve-out. A cluster has no HTTP host, so NO roster entry can
  // ever own it — rule 8 ("a target no roster entry owns is invisible") would silence
  // every database alert we have, and the ledger writer would then resolve them all.
  it("15. an unhealthy Crunchy cluster IS a problem despite owning no roster entry", () => {
    const f = facts({
      roster: [],
      deploys: [deploy({ platform: "crunchy", projectName: "adh-prod", environment: "production",
        buildPhase: null, deployPhase: "failed" })],
    });
    const p = deployProblems(f, NOW);
    expect(p).toHaveLength(1);
    expect(p[0]).toMatchObject({ target: "crunchy|adh-prod|", source: "crunchy", name: "adh-prod" });
  });

  it("16. a healthy Crunchy cluster is not a problem", () => {
    const f = facts({
      roster: [],
      deploys: [deploy({ platform: "crunchy", projectName: "adh-prod", environment: "production",
        buildPhase: null, deployPhase: "deployed" })],
    });
    expect(deployProblems(f, NOW)).toEqual([]);
  });

  it("17. deactivating one Railway environment's roster entry does not silence its still-active sibling, nor does the sibling adopt the deactivated one's problem", () => {
    const roster = [
      entry({ endpointId: "ep-1", platform: "railway", projectName: "adh-backend", environment: "production" }),
      entry({ endpointId: "ep-2", platform: "railway", projectName: "adh-backend", environment: "scratch1", isActive: false }),
    ];

    // The deactivated environment's own failure is invisible: no roster entry owns it.
    const deactivated = facts({
      roster,
      deploys: [deploy({ platform: "railway", projectName: "adh-backend", environment: "scratch1", buildPhase: "failed", deployPhase: "failed" })],
    });
    expect(deployProblems(deactivated, NOW)).toEqual([]);

    // The still-active sibling's own failure is still a problem, correctly keyed to ITS env.
    const active = facts({
      roster,
      deploys: [deploy({ platform: "railway", projectName: "adh-backend", environment: "production", buildPhase: "failed", deployPhase: "failed" })],
    });
    const p = deployProblems(active, NOW);
    expect(p).toHaveLength(1);
    expect(p[0].target).toBe("railway|adh-backend|production");
  });

  it("18. a Vercel deploy with environment '' (empty string, not null) is also a preview — not just null", () => {
    const f = facts({ deploys: [deploy({ environment: "", buildPhase: "failed", deployPhase: "none" })] });
    expect(deployProblems(f, NOW)).toEqual([]);
  });
});

/**
 * A RETRY IS NOT A RECOVERY.
 *
 * The bug: `facts.deploys` was one query over conclusive-and-in-flight rows alike, so the
 * moment someone pushed a fix the retry's `BUILDING` row won `max(createdAt)`. The target
 * was then neither failed nor stuck, it silently left the Problems list, and
 * `applyBoardToLedger` — which reads "in monitoredTargets but not in problems" as a
 * recovery — closed the issue as `recovered` and paged on-call. Production was still
 * serving the broken build the whole time.
 */
describe("deployProblems — a build in flight is not a verdict", () => {
  const failed = deploy({ buildPhase: "failed", deployPhase: "none", createdAtMs: NOW - 7200_000, commitHash: "bad0bad" });
  const retry = (over: Partial<DeployFact> = {}) =>
    deploy({ buildPhase: "building", deployPhase: "none", createdAtMs: NOW - 60_000, commitHash: "fix1234", ...over });

  it("a failure with a NEWER retry still building stays exactly one problem, unchanged", () => {
    const alone = deployProblems(facts({ deploys: [failed] }), NOW);
    const retrying = deployProblems(facts({ deploys: [failed], inFlightDeploys: [retry()] }), NOW);
    expect(retrying).toHaveLength(1);
    expect(retrying[0].state).toBe("failed");
    // The problem is the SAME problem: same onset, and still the failing commit's detail
    // rather than the retry's. Anything else re-opens it in the ledger.
    expect(retrying).toEqual(alone);
    expect(retrying[0].commitHash).toBe("bad0bad");
  });

  it("the retry SUCCEEDING is what clears it — the concluded row supersedes the failure", () => {
    const fixed = deploy({ createdAtMs: NOW - 30_000, commitHash: "fix1234" });
    expect(deployProblems(facts({ deploys: [failed, fixed] }), NOW)).toEqual([]);
  });

  it("a retry that WEDGES past the threshold is stuck, even with a failed verdict behind it", () => {
    const f = facts({
      deploys: [failed],
      inFlightDeploys: [retry({ createdAtMs: NOW - STUCK_DEPLOY_MS - 1 })],
    });
    const p = deployProblems(f, NOW);
    expect(p).toHaveLength(1);
    expect(p[0].state).toBe("stuck");
    // One row per target, always — the stuck retry replaces the failure's row, it does not
    // add a second one for the same target.
    expect(p[0].target).toBe("vercel|hub-help-testing|");
  });

  it("a FIRST-EVER build that wedges is stuck, with no concluded row to fall back on", () => {
    const f = facts({ inFlightDeploys: [retry({ createdAtMs: NOW - STUCK_DEPLOY_MS - 1 })] });
    const p = deployProblems(f, NOW);
    expect(p).toHaveLength(1);
    expect(p[0].state).toBe("stuck");
  });

  // A stuck problem is spelled from the IN-FLIGHT row, not the verdict behind it, so its
  // branch and error text have to come from that row too. Reading them off `verdict` would
  // caption a wedged retry with the previous build's ref — the wrong commit's provenance
  // on the row an operator is about to go look at.
  it("a stuck problem's branch and errorText come from the wedged row, not the verdict", () => {
    const f = facts({
      deploys: [failed],
      inFlightDeploys: [retry({ createdAtMs: NOW - STUCK_DEPLOY_MS - 1, branch: "staging", errorText: null })],
    });
    const p = deployProblems(f, NOW);
    expect(p).toHaveLength(1);
    expect(p[0]!.state).toBe("stuck");
    expect(p[0]!.branch).toBe("staging");
    expect(p[0]!.errorText).toBeNull();
  });

  it("an in-flight row OLDER than the verdict is a corpse and decides nothing", () => {
    // The expirer has not swept it yet. It is older than the success that concluded the
    // target, so it must not resurrect a stuck problem.
    const fixed = deploy({ createdAtMs: NOW - 60_000 });
    const f = facts({ deploys: [fixed], inFlightDeploys: [retry({ createdAtMs: NOW - STUCK_DEPLOY_MS * 10 })] });
    expect(deployProblems(f, NOW)).toEqual([]);
  });
});

/**
 * ONE TARGET, ONE ROW. `readBoardFacts` groups by the deploy row's own columns, which
 * cannot see that a provider id and a project name are two spellings of one target — the
 * fold does the authoritative collapse.
 */
describe("deployProblems — two spellings of one target collapse to one problem", () => {
  const roster = [entry({ providerProjectId: "prj_abc", projectName: "hub-help-testing" })];
  // Post-rename rows carry the id and the NEW name; pre-adoption rows carry neither.
  const renamed = (over: Partial<DeployFact> = {}) =>
    deploy({ providerProjectId: "prj_abc", projectName: "hub-help", ...over });
  const legacy = (over: Partial<DeployFact> = {}) =>
    deploy({ providerProjectId: null, projectName: "hub-help-testing", ...over });

  it("the NEWER of the two spellings decides, whichever order the facts arrive", () => {
    const bad = legacy({ buildPhase: "failed", deployPhase: "none", createdAtMs: NOW - 7200_000 });
    const good = renamed({ createdAtMs: NOW - 60_000 });
    expect(deployProblems(facts({ roster, deploys: [bad, good] }), NOW)).toEqual([]);
    expect(deployProblems(facts({ roster, deploys: [good, bad] }), NOW)).toEqual([]);

    const staleGood = legacy({ createdAtMs: NOW - 7200_000 });
    const freshBad = renamed({ buildPhase: "failed", deployPhase: "none", createdAtMs: NOW - 60_000 });
    for (const deploys of [[staleGood, freshBad], [freshBad, staleGood]]) {
      const p = deployProblems(facts({ roster, deploys }), NOW);
      expect(p).toHaveLength(1);
      expect(p[0].target).toBe("vercel|prj_abc|");
    }
  });

  it("a tie on createdAtMs resolves the SAME way regardless of fact order", () => {
    // Two rows stamped the same millisecond. The rule (id-carrying row wins) is arbitrary;
    // that it is STABLE is not — `deriveBoard` is pure and the ledger keys on the target,
    // so a winner that flapped with SQLite's row order would flap the problem's detail.
    const withId = renamed({ buildPhase: "failed", deployPhase: "none", createdAtMs: NOW - 60_000, commitHash: "aaa1111" });
    const withoutId = legacy({ createdAtMs: NOW - 60_000, commitHash: "bbb2222" });
    const forward = deployProblems(facts({ roster, deploys: [withId, withoutId] }), NOW);
    const reverse = deployProblems(facts({ roster, deploys: [withoutId, withId] }), NOW);
    expect(forward).toEqual(reverse);
    expect(forward).toHaveLength(1);
    expect(forward[0].commitHash).toBe("aaa1111");
  });
});
