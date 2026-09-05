import { describe, it, expect } from "vitest";
import { deriveBoard } from "../src/board/derive";
import type { BoardFacts, DeployFact, EndpointFact, RosterEntry } from "../src/board/types";
import { PLATFORM_UNREACHABLE_POLLS } from "../src/monitor/issue-sources";

const NOW = Date.UTC(2026, 7, 2, 12, 0, 0);

function entry(over: Partial<RosterEntry> = {}): RosterEntry {
  return {
    endpointId: "ep-1", label: "Hub Help", platform: "vercel", providerProjectId: null,
    projectName: "hub-help-testing", environment: "production", isActive: true,
    monitorHttp: true, monitorDeploys: true, ignoreProjectWarning: false,
    url: "https://testing.help.example.com", ...over,
  };
}
// Every ActivityRow id carries its fact's primary key, because the page cursor is the
// (time, id) PAIR and timestamps are whole seconds. A shared default would mint
// byte-identical ids here and hide exactly the collision that id is there to prevent.
let deploySeq = 0;
function failedDeploy(over: Partial<DeployFact> = {}): DeployFact {
  return {
    deploymentId: `dpl_${++deploySeq}`,
    platform: "vercel", providerProjectId: null, projectName: "hub-help-testing",
    environment: "production", branch: null, buildPhase: "failed", deployPhase: "none",
    createdAtMs: NOW - 60_000, commitHash: "abc1234", commitMessage: "wip",
    commitRepo: "adh", sourceUrl: null, liveUrl: null, errorText: null, ...over,
  };
}
function downProbe(over: Partial<EndpointFact> = {}): EndpointFact {
  return { endpointId: "ep-1", status: "down", statusCode: 503, dnsOk: true, checkedAtMs: NOW, badSinceMs: NOW - 60_000, ...over };
}
function facts(over: Partial<BoardFacts> = {}): BoardFacts {
  return {
    roster: [entry()], probeIntervalMs: 60_000, deploys: [], inFlightDeploys: [], deployEvents: [],
    endpoints: [], platforms: [], staleProd: [],
    ledger: [], issueEvents: [], liveVercelProjects: ["hub-help-testing"],
    errors: [], errorsConfigured: true, errorProjectAllowlist: null, ...over,
  };
}

describe("REQUIREMENT A — turning monitoring off removes the problem", () => {
  it("15. monitorDeploys=false removes a failed-deploy problem", () => {
    const on = deriveBoard(facts({ deploys: [failedDeploy()] }), NOW);
    expect(on.problems).toHaveLength(1);
    const off = deriveBoard(facts({ roster: [entry({ monitorDeploys: false })], deploys: [failedDeploy()] }), NOW);
    expect(off.problems).toEqual([]);
  });

  it("16. isActive=false removes EVERY problem for that site at once", () => {
    const f = facts({ roster: [entry({ isActive: false })], deploys: [failedDeploy()], endpoints: [downProbe()] });
    expect(deriveBoard(f, NOW).problems).toEqual([]);
  });

  it("17. turning deploys off leaves the HTTP problem standing — the switches are independent", () => {
    const f = facts({ roster: [entry({ monitorDeploys: false })], deploys: [failedDeploy()], endpoints: [downProbe()] });
    const p = deriveBoard(f, NOW).problems;
    expect(p).toHaveLength(1);
    expect(p[0].state).toBe("down");
  });

  it("18a. monitorDeploys=false removes a STALE-PROD problem too", () => {
    // staleProdProblems reaches the Requirement A gate only through the shared
    // `rosterTargets` helper, and nothing else in this file exercises that path. A change
    // that routed stale-prod around the helper would drop Requirement A for it — a site
    // whose deploy monitoring was switched off would keep an unclearable stale row — with
    // every other case in this file still green.
    const staleProd = [{
      platform: "vercel", providerProjectId: null, projectName: "hub-help-testing",
      environment: "production", branch: null, detail: "production deploy is 3 builds behind",
      sourceUrl: null, liveUrl: null,
    }];
    expect(deriveBoard(facts({ staleProd }), NOW).problems.map((p) => p.state)).toEqual(["stale"]);
    const off = deriveBoard(facts({ roster: [entry({ monitorDeploys: false })], staleProd }), NOW);
    expect(off.problems).toEqual([]);
  });

  it("18. turning a switch back ON restores the problem — the board is a projection, not a log", () => {
    const target = "vercel|hub-help-testing|";
    const off = deriveBoard(facts({ roster: [entry({ monitorDeploys: false })], deploys: [failedDeploy()] }), NOW);
    expect(off.problems.some((p) => p.target === target)).toBe(false);
    const on = deriveBoard(facts({ roster: [entry({ monitorDeploys: true })], deploys: [failedDeploy()] }), NOW);
    expect(on.problems.some((p) => p.target === target)).toBe(true);
  });
});

describe("platform health", () => {
  it("an unreachable provider under the streak threshold is not a problem", () => {
    const f = facts({ platforms: [{ source: "vercel", configured: true, ok: false, streak: PLATFORM_UNREACHABLE_POLLS - 1, sampledAtMs: NOW }] });
    expect(deriveBoard(f, NOW).problems).toEqual([]);
  });

  it("an unreachable provider at the threshold IS a problem", () => {
    const f = facts({ platforms: [{ source: "vercel", configured: true, ok: false, streak: PLATFORM_UNREACHABLE_POLLS, sampledAtMs: NOW }] });
    const p = deriveBoard(f, NOW).problems;
    expect(p).toHaveLength(1);
    // TWO segments and `minor` — the spelling and severity `applyPlatformIssues` already
    // writes. A third segment would orphan every live row; `major` would repaint a
    // monitor-side blind spot as a red customer-facing outage.
    expect(p[0]).toMatchObject({ target: "platform-health|vercel", state: "unreachable", severity: "minor" });
  });

  // An unreachable provider API is a monitor-side blind spot — no build, no ref, no
  // provider error of its own. Nulls stated outright so the pane's Git tab and error block
  // are off by the server's decision rather than by a producer's omission.
  it("a platform-health problem carries neither a branch nor an errorText", () => {
    const f = facts({ platforms: [{ source: "vercel", configured: true, ok: false, streak: PLATFORM_UNREACHABLE_POLLS, sampledAtMs: NOW }] });
    expect(deriveBoard(f, NOW).problems[0]).toMatchObject({ branch: null, errorText: null });
  });

  it("a provider we do not poll is never a problem", () => {
    const f = facts({ platforms: [{ source: "crunchy", configured: false, ok: false, streak: 99, sampledAtMs: NOW }] });
    expect(deriveBoard(f, NOW).problems).toEqual([]);
  });
});

describe("Vercel production staleness", () => {
  it("a stale PRODUCTION project is a MAJOR problem, detail untouched", () => {
    const f = facts({
      roster: [entry({ projectName: "hub-help" })],
      liveVercelProjects: ["hub-help"],
      staleProd: [{ platform: "vercel", providerProjectId: null, projectName: "hub-help",
        environment: "production", branch: null, detail: "production deploy is 3 builds behind", sourceUrl: null, liveUrl: null }],
    });
    const p = deriveBoard(f, NOW).problems;
    expect(p).toHaveLength(1);
    expect(p[0]).toMatchObject({
      state: "stale",
      severity: "major",
      environment: "production",
      detail: "production deploy is 3 builds behind",
    });
  });

  it("a stale TESTING project is downgraded to minor, and its detail no longer claims production", () => {
    // `hub-help-testing` — the default fixture project — ends in `-testing`, so
    // `deployEnv` reads its environment from the NAME, not from `s.environment`
    // (deliberately set to "production" here to prove the override wins).
    const f = facts({
      staleProd: [{ platform: "vercel", providerProjectId: null, projectName: "hub-help-testing",
        environment: "production", branch: null, detail: "production deploy is 3 builds behind", sourceUrl: null, liveUrl: null }],
    });
    const p = deriveBoard(f, NOW).problems;
    expect(p).toHaveLength(1);
    expect(p[0].severity).toBe("minor");
    expect(p[0].environment).toBe("testing");
    expect(p[0].detail).not.toMatch(/\bproduction\b/);
  });

  // The same branch-first rule the deploy producers now follow, asked of a PROJECT: a
  // stale-prod fact describes a project rather than a build, so its evidence is the
  // project's CONFIGURED production branch (`deploy_project_meta.git_branch`). `hub-help`
  // has no tier suffix, so before this the name rule called it production and its
  // staleness paged as a MAJOR production incident.
  it("reads a stale project's tier off its configured production BRANCH, not its name", () => {
    const f = facts({
      roster: [entry({ projectName: "hub-help" })],
      liveVercelProjects: ["hub-help"],
      staleProd: [{ platform: "vercel", providerProjectId: null, projectName: "hub-help",
        environment: "production", branch: "prepared",
        detail: "production deploy is 3 builds behind", sourceUrl: null, liveUrl: null }],
    });
    const p = deriveBoard(f, NOW).problems;
    expect(p).toHaveLength(1);
    expect(p[0].environment).toBe("testing");
    // Severity and the detail rewrite both key off the SAME derived env, so correcting the
    // tier necessarily downgrades this from a production incident and stops the detail
    // claiming "production" — the two consequences of getting the env right.
    expect(p[0].severity).toBe("minor");
    expect(p[0].detail).not.toMatch(/\bproduction\b/);
  });

  // A stale-prod row is a verdict about a PROJECT: nothing failed to build, so there is no
  // provider error to show, but the project's configured production branch is exactly the
  // provenance an operator wants in the pane's Git tab — it names the ref that was supposed
  // to be serving. The same field, asked of a project rather than of a build.
  it("a stale project's problem carries its configured production branch and no errorText", () => {
    const f = facts({
      roster: [entry({ projectName: "hub-help" })],
      liveVercelProjects: ["hub-help"],
      staleProd: [{ platform: "vercel", providerProjectId: null, projectName: "hub-help",
        environment: "production", branch: "production",
        detail: "production deploy is 3 builds behind", sourceUrl: null, liveUrl: null }],
    });
    const p = deriveBoard(f, NOW).problems;
    expect(p).toHaveLength(1);
    expect(p[0]!.branch).toBe("production");
    expect(p[0]!.errorText).toBeNull();
  });

  it("staleness is SUPPRESSED when the same target already has a failed-deploy problem", () => {
    const f = facts({
      deploys: [failedDeploy()],
      staleProd: [{ platform: "vercel", providerProjectId: null, projectName: "hub-help-testing",
        environment: "production", branch: null, detail: "live deploy errored", sourceUrl: null, liveUrl: null }],
    });
    const p = deriveBoard(f, NOW).problems;
    expect(p).toHaveLength(1);
    expect(p[0].state).toBe("failed");
  });

  it("a stale project no roster entry owns is invisible", () => {
    const f = facts({
      roster: [],
      staleProd: [{ platform: "vercel", providerProjectId: null, projectName: "orphan",
        environment: "production", branch: null, detail: "x", sourceUrl: null, liveUrl: null }],
    });
    expect(deriveBoard(f, NOW).problems).toEqual([]);
  });
});

// A project DELETED at Vercel keeps its roster wiring until an operator clears it, so the
// ownership gate still admits its rows. The `deploy_project_meta` mirror is the only thing
// that knows it is gone, and it has to reach BOTH Vercel rules: the webhook door dropped
// its own deleted-project check on the grounds that the fold does this now, and the fold
// was applying it to staleness only. Every provider retry then reopened — and paged for —
// the failure the cycle had just resolved as "unmonitored".
describe("a project deleted at Vercel is off the board, deploy rules included", () => {
  const ghostRoster = [entry({ endpointId: "ep-1" }), entry({ endpointId: "ep-2", projectName: "ghost", label: "Ghost" })];

  it("narrows the FAILED-DEPLOY problem of a vanished project, keeping the live one", () => {
    const f = facts({
      roster: ghostRoster,
      deploys: [failedDeploy({ projectName: "hub-help-testing" }), failedDeploy({ projectName: "ghost" })],
      liveVercelProjects: ["hub-help-testing"],
    });
    expect(deriveBoard(f, NOW).problems.map((p) => p.target)).toEqual(["vercel|hub-help-testing|"]);
  });

  it("narrows nothing on an EMPTY read — a bad token must not silence the fleet", () => {
    const f = facts({
      roster: ghostRoster,
      deploys: [failedDeploy({ projectName: "hub-help-testing" }), failedDeploy({ projectName: "ghost" })],
      liveVercelProjects: [],
    });
    expect(deriveBoard(f, NOW).problems.map((p) => p.target).sort())
      .toEqual(["vercel|ghost|", "vercel|hub-help-testing|"]);
  });

  it("narrows nothing when EVERY owned project is missing — that is a scope change, not mass deletion", () => {
    const f = facts({
      roster: ghostRoster,
      deploys: [failedDeploy({ projectName: "hub-help-testing" }), failedDeploy({ projectName: "ghost" })],
      liveVercelProjects: ["somebody-elses-project"],
    });
    expect(deriveBoard(f, NOW).problems.map((p) => p.target).sort())
      .toEqual(["vercel|ghost|", "vercel|hub-help-testing|"]);
  });
});

describe("Crunchy has no HTTP host, but must still be WATCHED", () => {
  // No roster entry ever owns a crunchy cluster — it has no HTTP host — yet
  // deployProblems always judges it (issue-sources.ts's crunchy carve-out). If
  // monitoredTargets omitted it, Task 12's ledger writer would read a genuine
  // recovery as "no longer monitored" and close the issue silently instead of
  // paging on-call that the outage cleared.
  function crunchyDeploy(over: Partial<DeployFact> = {}): DeployFact {
    return {
      deploymentId: `dpl_${++deploySeq}`,
      platform: "crunchy", providerProjectId: null, projectName: "prod-cluster",
      environment: null, branch: null, buildPhase: null, deployPhase: "failed",
      createdAtMs: NOW - 60_000, commitHash: null, commitMessage: null,
      commitRepo: null, errorText: null, sourceUrl: null, liveUrl: null, ...over,
    };
  }
  const TARGET = "crunchy|prod-cluster|";

  it("a failed cluster is a Problem, and its target is watched", () => {
    const board = deriveBoard(facts({ roster: [], deploys: [crunchyDeploy()] }), NOW);
    expect(board.problems.map((p) => p.target)).toEqual([TARGET]);
    expect(board.monitoredTargets).toContain(TARGET);
  });

  it("a healthy cluster has no Problem but is STILL watched — the case the ledger writer resolves", () => {
    const board = deriveBoard(facts({ roster: [], deploys: [crunchyDeploy({ deployPhase: "deployed" })] }), NOW);
    expect(board.problems).toEqual([]);
    expect(board.monitoredTargets).toContain(TARGET);
  });

  it("a cluster a roster entry DOES claim is watched under the OWNER's spelling", () => {
    // `monitoredTargets` used to short-circuit every crunchy row to its own `projectName`
    // key BEFORE asking who owns it, while `deployProblems` minted the target from the
    // owner's identity. With an id on the entry the two spellings differ, so the Problem
    // opened under `crunchy|cl_9|` and `applyBoardToLedger` closed it as UNMONITORED on the
    // next sweep — the exact silent-close this whole file is about, and invisible to every
    // other case here because the unowned crunchy path (above) agrees either way.
    const owner = entry({
      endpointId: "ep-pg", label: "Prod PG", platform: "crunchy",
      providerProjectId: "cl_9", projectName: "prod-cluster", environment: null,
      monitorHttp: false,
    });
    const board = deriveBoard(facts({ roster: [owner], deploys: [crunchyDeploy()] }), NOW);
    expect(board.problems.map((p) => p.target)).toEqual(["crunchy|cl_9|"]);
    expect(board.monitoredTargets).toContain("crunchy|cl_9|");
    // And NOT under the row's own name — a second spelling of one target is the defect.
    expect(board.monitoredTargets).not.toContain(TARGET);
  });
});

describe("THE INVARIANT: every Problem's target is a monitored target", () => {
  // `monitoredTargets` (derive-problems.ts:376) RE-DERIVES the same keys the four problem
  // producers mint. Nothing forces the two sides to agree — they agree because someone
  // kept them in step by hand. Break either side and the failure is silent and total: a
  // problem whose target is missing from `monitoredTargets` is closed by
  // `applyBoardToLedger` as `unmonitored` instead of `recovered`, so on-call is never told
  // the outage cleared, and every test in this file still passes. The Crunchy block above
  // pins ONE case of this; this pins the rule.
  it("holds across all four problem families at once", () => {
    const f = facts({
      roster: [
        // 1+2. deploy + HTTP, from one entry matched by NAME.
        entry(),
        // 4. staleness, from a SECOND entry matched by PROVIDER ID — `entryIdentity` mints
        //    the target from `providerProjectId ?? projectName`, which is the spelling most
        //    likely to drift away from `monitoredTargets` (it is the id-adoption path).
        entry({ endpointId: "ep-2", label: "Hub", projectName: "hub-help", providerProjectId: "prj_hubhelp" }),
      ],
      deploys: [failedDeploy()],
      endpoints: [downProbe()],
      // 3. a provider API we cannot reach, past the debounce.
      platforms: [{ source: "railway", configured: true, ok: false, streak: PLATFORM_UNREACHABLE_POLLS, sampledAtMs: NOW }],
      staleProd: [{ platform: "vercel", providerProjectId: "prj_hubhelp", projectName: "hub-help",
        environment: "production", branch: null, detail: "production deploy is 3 builds behind", sourceUrl: null, liveUrl: null }],
      liveVercelProjects: ["hub-help-testing", "hub-help"],
    });
    const board = deriveBoard(f, NOW);

    // Not vacuous: all four families really are present, one row each.
    expect(board.problems.map((p) => p.state).sort()).toEqual(["down", "failed", "stale", "unreachable"]);
    const watched = new Set(board.monitoredTargets);
    const unwatched = board.problems.filter((p) => !watched.has(p.target)).map((p) => p.target);
    expect(unwatched).toEqual([]);
  });
});

describe("deriveBoard shape", () => {
  it("is pure — same facts and same nowMs give a deep-equal board", () => {
    const f = facts({ deploys: [failedDeploy()], endpoints: [downProbe()] });
    expect(deriveBoard(f, NOW)).toEqual(deriveBoard(f, NOW));
  });

  it("stamps generatedAt from nowMs, never from the wall clock", () => {
    expect(deriveBoard(facts(), NOW).generatedAt).toBe(new Date(NOW).toISOString());
  });

  it("publishes what it is WATCHING, so a close can tell recovery from de-configuration", () => {
    const f = facts({ deploys: [failedDeploy({ buildPhase: "built", deployPhase: "deployed" })] });
    expect(deriveBoard(f, NOW).monitoredTargets).toEqual(["ep-1", "vercel|hub-help-testing|"]);
  });

  it("watches nothing for a site whose master switch is off", () => {
    expect(deriveBoard(facts({ roster: [entry({ isActive: false })] }), NOW).monitoredTargets).toEqual([]);
  });

  // A Vercel project DELETED upstream, with the site still wired to it. This is the whole
  // reason the account mirror is a fact: the project can never build again, so its last
  // failure can never be superseded and the Problem is unclearable — every provider retry
  // re-opens and re-pages it. `routes/hooks.ts` documented the narrowing as the fold's job
  // while the fold did not do it; `deployProblems` was the ONE surface that never applied
  // it, and it is the surface that pages.
  //
  // BOTH halves are asserted because they fail differently. Missing from `problems` alone
  // is not enough: if the target stayed in `monitoredTargets`, `applyBoardToLedger` would
  // close the open row as RECOVERED and alert on-call that a build passed. It has to be
  // absent from both, so the close is the silent `unmonitored` one.
  describe("a Vercel project deleted upstream", () => {
    const gone = () => facts({
      roster: [entry(), entry({ endpointId: "ep-2", projectName: "ghost", monitorHttp: false })],
      deploys: [failedDeploy(), failedDeploy({ projectName: "ghost" })],
      liveVercelProjects: ["hub-help-testing"],
    });

    it("derives no Problem for it, while its live sibling keeps one", () => {
      expect(deriveBoard(gone(), NOW).problems.map((p) => p.target)).toEqual(["vercel|hub-help-testing|"]);
    });

    it("stops being WATCHED, so its open row closes silently instead of paging a recovery", () => {
      expect(deriveBoard(gone(), NOW).monitoredTargets).toEqual(["ep-1", "vercel|hub-help-testing|"]);
    });

    it("keeps its HTTP monitoring — the site is still up, only its deploy target is gone", () => {
      const f = facts({
        roster: [entry(), entry({ endpointId: "ep-2", projectName: "ghost" })],
        liveVercelProjects: ["hub-help-testing"],
      });
      expect(deriveBoard(f, NOW).monitoredTargets).toEqual(["ep-1", "ep-2", "vercel|hub-help-testing|"]);
    });
  });

  it("sorts problems oldest-first, breaking ties on target", () => {
    const f = facts({
      roster: [entry({ endpointId: "ep-1" }), entry({ endpointId: "ep-2", projectName: "other-site", label: "Other" })],
      deploys: [
        failedDeploy({ projectName: "hub-help-testing", createdAtMs: NOW - 3600_000 }),
        failedDeploy({ projectName: "other-site", createdAtMs: NOW - 60_000 }),
      ],
      // Both projects still exist at Vercel. A name missing from the mirror is a DELETED
      // project, whose Problem `ownedDeployTarget` now drops — so without this the second
      // one is narrowed away and the failure reads as a sorting bug. The subject here is
      // tie-breaking.
      liveVercelProjects: ["hub-help-testing", "other-site"],
    });
    expect(deriveBoard(f, NOW).problems.map((p) => p.target)).toEqual([
      "vercel|hub-help-testing|",
      "vercel|other-site|",
    ]);
  });
});
