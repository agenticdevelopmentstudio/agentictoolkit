import { describe, it, expect, beforeEach } from "vitest";
import { deriveActivity, indicatorFor } from "../src/board/derive-activity";
import { deriveBoard } from "../src/board/derive";
import { ACTIVITY_WINDOW_MS, MAX_ACTIVITY_ROWS } from "../src/board/types";
import type { BoardFacts, DeployFact, IssueEvent, PlatformFact, Problem, RosterEntry } from "../src/board/types";

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
//
// Zero-padded and reset per test for the same reason the ids exist: rows that tie on time
// are ordered by id as a STRING, so an unpadded run inverts at `dpl_9` > `dpl_10` and a
// test asserting order would depend on how many deploys every test before it happened to
// mint. Padding makes the string order the mint order; the reset makes it start from 1.
let deploySeq = 0;
let issueSeq = 0;
beforeEach(() => {
  deploySeq = 0;
  issueSeq = 0;
});
function deploy(over: Partial<DeployFact> = {}): DeployFact {
  return {
    deploymentId: `dpl_${String(++deploySeq).padStart(4, "0")}`,
    platform: "vercel", providerProjectId: null, projectName: "hub-help-testing",
    environment: "production", branch: null, buildPhase: "built", deployPhase: "deployed",
    createdAtMs: NOW - 60_000, commitHash: "abc1234", commitMessage: "fix: thing\n\nbody",
    commitRepo: "adh", sourceUrl: null, liveUrl: null, errorText: null, ...over,
  };
}
function issue(over: Partial<IssueEvent> = {}): IssueEvent {
  return {
    id: ++issueSeq,
    target: "ep-1", source: "http", name: "Hub Help", environment: "production",
    state: "down", severity: "critical", detail: "HTTP 503", sourceUrl: null, liveUrl: null,
    commitHash: null, commitMessage: null, commitRepo: null,
    openedAtMs: NOW - 3600_000, resolvedAtMs: null, resolvedReason: null, ...over,
  };
}
function platform(over: Partial<PlatformFact> = {}): PlatformFact {
  return { source: "vercel", configured: true, ok: false, streak: 5, sampledAtMs: NOW, ...over };
}
function facts(over: Partial<BoardFacts> = {}): BoardFacts {
  return {
    roster: [entry()], probeIntervalMs: 60_000, deploys: [], inFlightDeploys: [], deployEvents: [],
    endpoints: [], platforms: [],
    staleProd: [], ledger: [], issueEvents: [], liveVercelProjects: ["hub-help-testing"],
    errors: [], errorsConfigured: true, errorProjectAllowlist: null,
    ...over,
  };
}
function problem(over: Partial<Problem> = {}): Problem {
  return {
    target: "vercel|x|", source: "vercel", name: "x", environment: "production",
    severity: "major", state: "failed", statusCode: null, detail: null, sourceUrl: null,
    liveUrl: null, commitHash: null, commitMessage: null, commitRepo: null,
    branch: null, errorText: null,
    since: new Date(NOW).toISOString(), ...over,
  };
}

describe("deriveActivity — deployments", () => {
  it("records a successful deployment as its two lifecycle rows, build first", () => {
    const rows = deriveActivity(facts({ deployEvents: [deploy()] }), NOW);
    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatchObject({ kind: "deploy", step: "build", verb: "built", tone: "good", name: "hub-help-testing", source: "vercel" });
    expect(rows[1]).toMatchObject({ kind: "deploy", step: "deploy", verb: "deployed", tone: "good", source: "vercel" });
  });

  // An env badge names the project's LOGICAL TIER, never Vercel's promotion target. EVERY
  // Vercel project has its own production target — `hub-help-testing`'s target is
  // "production" — so passing the stored column through paints every testing/staging deploy
  // PROD. `deployEnv` reads the tier off the project name, and `staleProdProblems`
  // (derive-problems.ts) has always applied it; this pane has to agree with it.
  it("labels a Vercel row with its LOGICAL tier, not Vercel's production target", () => {
    const rows = deriveActivity(facts({ deployEvents: [deploy()] }), NOW);
    expect(rows.map((r) => r.environment)).toEqual(["testing", "testing"]);
  });

  // The BRANCH is the tier signal that cannot be wrong, and this is the case neither of
  // the other two can reach: a project serving testing whose NAME carries no `-testing`
  // suffix. Vercel's target says "production" (it says that for every project) and
  // `envFromProject("hub")` says "production" too — both defaults, both wrong. The branch
  // it built from says `prepared`, and `prepared` is what deploys testing.
  it("reads a Vercel row's tier off the BRANCH when the project name carries no suffix", () => {
    const f = facts({
      roster: [entry({ projectName: "hub" })],
      deployEvents: [deploy({ projectName: "hub", branch: "prepared" })],
      liveVercelProjects: ["hub"],
    });
    expect(deriveActivity(f, NOW).map((r) => r.environment)).toEqual(["testing", "testing"]);
  });

  it("lets the branch OVERRIDE a project name that disagrees with it", () => {
    // A `-testing` project building `production` is a misconfiguration; the branch is the
    // thing that knows. Preferring the name would paint it TESTING and hide the fact.
    const f = facts({ deployEvents: [deploy({ branch: "production" })] });
    expect(deriveActivity(f, NOW).map((r) => r.environment)).toEqual(["production", "production"]);
  });

  it("falls back to the project name for a branch that deploys nothing", () => {
    // `main` is absent from the branch map on purpose, so it supplies no evidence and the
    // older name rule decides — which for `hub-help-testing` is still right.
    const f = facts({ deployEvents: [deploy({ branch: "main" })] });
    expect(deriveActivity(f, NOW).map((r) => r.environment)).toEqual(["testing", "testing"]);
  });

  it("leaves a genuine production project alone", () => {
    const f = facts({
      roster: [entry({ projectName: "hub" })],
      deployEvents: [deploy({ projectName: "hub" })],
      liveVercelProjects: ["hub"],
    });
    expect(deriveActivity(f, NOW).map((r) => r.environment)).toEqual(["production", "production"]);
  });

  // The other half of the `deployEnv` rule: Railway reports the REAL environment name, so a
  // Railway row is trusted and must NOT be collapsed to production by a project name that
  // carries no tier suffix.
  it("keeps a Railway row's reported environment, which has no tier suffix to read", () => {
    const f = facts({
      roster: [entry({ platform: "railway", projectName: "adh-backend", environment: "testing" })],
      deployEvents: [deploy({ platform: "railway", projectName: "adh-backend", environment: "testing" })],
    });
    expect(deriveActivity(f, NOW).map((r) => r.environment)).toEqual(["testing", "testing"]);
  });

  // The details pane has a Git tab and a provider-error block, and BOTH read fields the
  // wire has to carry: nothing downstream can reconstruct a branch or a build log tail
  // from the row's other columns. They travel on every deploy row, not just failed ones —
  // the branch is as true of a green build as of a red one, and gating the pair on tone
  // would make the pane's contents depend on the outcome rather than on the event.
  it("carries the deploy's BRANCH and provider errorText onto both lifecycle rows", () => {
    const f = facts({
      deployEvents: [deploy({ branch: "prepared", errorText: "[buildStep] next build exited 1" })],
    });
    const rows = deriveActivity(f, NOW);
    expect(rows).toHaveLength(2);
    for (const r of rows) {
      expect(r.branch).toBe("prepared");
      expect(r.errorText).toBe("[buildStep] next build exited 1");
    }
  });

  it("Fix Round 2 item 1: a deploy row's source is the deploy's own RAW platform, never boardTargetKey's canonicalised one", () => {
    // "cloudflare-pages", not "cloudflare" — the same convention Problem.source already
    // uses (derive-problems.ts:182), and the regression row-model.test.ts:212 pins on
    // the client side once the row arrives with this field populated.
    const f = facts({
      roster: [entry({ platform: "cloudflare-pages", projectName: "cf-app" })],
      deployEvents: [deploy({ platform: "cloudflare-pages", projectName: "cf-app" })],
    });
    const rows = deriveActivity(f, NOW);
    expect(rows).toHaveLength(2);
    expect(rows[0]?.source).toBe("cloudflare-pages");
    expect(rows[1]?.source).toBe("cloudflare-pages");
  });

  it("emits only a build row when the deployment never reached its deploy phase", () => {
    const rows = deriveActivity(facts({ deployEvents: [deploy({ buildPhase: "building", deployPhase: "none" })] }), NOW);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ step: "build", verb: "building", tone: "progress" });
  });

  it("carries the verb and tone the pane renders, so the client derives neither", () => {
    const at = (over: Partial<DeployFact>) => deriveActivity(facts({ deployEvents: [deploy(over)] }), NOW)[0];
    expect(at({ buildPhase: "failed", deployPhase: "none" })).toMatchObject({ verb: "build failed", tone: "bad" });
    expect(at({ buildPhase: "canceled", deployPhase: "none" })).toMatchObject({ verb: "canceled", tone: "neutral" });
    expect(at({ buildPhase: "queued", deployPhase: "none" })).toMatchObject({ verb: "queued", tone: "progress" });
    // An expired phase is an ABSENCE of a verdict, shown muted — not a failure.
    expect(at({ buildPhase: "unknown", deployPhase: "none" })).toMatchObject({ verb: "outcome unknown", tone: "stale" });
    expect(deriveActivity(facts({ deployEvents: [deploy({ buildPhase: "built", deployPhase: "failed" })] }), NOW)[1])
      .toMatchObject({ step: "deploy", verb: "deploy failed", tone: "bad" });
  });

  it("keeps EVERY deployment in the window, not just the newest per target", () => {
    const f = facts({
      deployEvents: [
        deploy({ createdAtMs: NOW - 60_000 }),
        deploy({ createdAtMs: NOW - 3600_000, buildPhase: "failed", deployPhase: "none" }),
        deploy({ createdAtMs: NOW - 7200_000 }),
      ],
    });
    // 2 + 1 + 2. A log, not one row per target — this is what `deployEvents` is FOR.
    expect(deriveActivity(f, NOW)).toHaveLength(5);
  });

  it("REGRESSION c40b87542: a FAILED deploy stays in Activity even though it is also a Problem", () => {
    const failed = deploy({ buildPhase: "failed", deployPhase: "none" });
    const board = deriveBoard(facts({ deploys: [failed], deployEvents: [failed] }), NOW);
    expect(board.problems).toHaveLength(1);
    expect(board.activity).toHaveLength(1);
    expect(board.activity[0]).toMatchObject({ kind: "deploy", tone: "bad" });
  });

  it("keeps `kind` as the event's own kind, never recomputed from tone", () => {
    const f = facts({ deployEvents: [deploy({ buildPhase: "failed", deployPhase: "none" })] });
    const rows = deriveActivity(f, NOW);
    expect(rows).toHaveLength(1);
    expect(rows.every((r) => r.kind === "deploy")).toBe(true);
  });

  it("shows only the first line of the commit message as detail", () => {
    expect(deriveActivity(facts({ deployEvents: [deploy()] }), NOW)[0].detail).toBe("fix: thing");
  });

  it("drops events older than the 24-hour window", () => {
    const f = facts({ deployEvents: [deploy({ createdAtMs: NOW - ACTIVITY_WINDOW_MS - 1 })] });
    expect(deriveActivity(f, NOW)).toEqual([]);
  });

  it("keeps an event exactly at the window edge", () => {
    const f = facts({ deployEvents: [deploy({ createdAtMs: NOW - ACTIVITY_WINDOW_MS })] });
    expect(deriveActivity(f, NOW)).toHaveLength(2);
  });

  it("caps the feed at MAX_ACTIVITY_ROWS, keeping the newest", () => {
    const deploys = Array.from({ length: MAX_ACTIVITY_ROWS + 50 }, (_, i) =>
      deploy({ projectName: `site-${i}`, createdAtMs: NOW - i * 1000 }));
    const roster = deploys.map((d, i) => entry({ endpointId: `ep-${i + 1}`, projectName: d.projectName }));
    const rows = deriveActivity(facts({ roster, deployEvents: deploys }), NOW);
    expect(rows).toHaveLength(MAX_ACTIVITY_ROWS);
    // The feed reads oldest→newest, so the cap has to shed from the FRONT: `site-0` is the
    // newest deployment and belongs at the tail. Slicing the first N here would keep the
    // oldest 300 and drop every row an operator is actually watching.
    expect(rows.at(-1)!.name).toBe("site-0");
  });

  it("orders oldest first", () => {
    const f = facts({
      roster: [entry({ endpointId: "ep-1" }), entry({ endpointId: "ep-2", projectName: "b" })],
      deployEvents: [deploy({ createdAtMs: NOW - 3600_000 }), deploy({ projectName: "b", createdAtMs: NOW - 60_000 })],
      // Both projects still exist at Vercel — a name missing from the mirror is a DELETED
      // project, and the feed drops it (`ownedDeployTarget`).
      liveVercelProjects: ["hub-help-testing", "b"],
    });
    // Two rows per deployment, oldest deployment first, build before deploy within each —
    // the whole feed now reads in the order things actually happened, top to bottom.
    expect(deriveActivity(f, NOW).map((r) => `${r.name}:${r.step}`))
      .toEqual(["hub-help-testing:build", "hub-help-testing:deploy", "b:build", "b:deploy"]);
  });

  it("gives every deploy row a stable unique id — `deploy:<deploymentId>:<step>`", () => {
    const f = facts({
      roster: [entry({ endpointId: "ep-1" }), entry({ endpointId: "ep-2", projectName: "b" })],
      deployEvents: [
        deploy({ deploymentId: "dpl_a" }),
        deploy({ projectName: "b", deploymentId: "dpl_b" }),
      ],
      liveVercelProjects: ["hub-help-testing", "b"],
    });
    // Both deploys share one createdAtMs, so id order (not time) breaks the tie — and the
    // id now leads with the DEPLOYMENT, so a deployment's two rows stay adjacent whatever
    // its project is called.
    expect(deriveActivity(f, NOW).map((r) => r.id)).toEqual([
      "deploy:dpl_a:build",
      "deploy:dpl_a:deploy",
      "deploy:dpl_b:build",
      "deploy:dpl_b:deploy",
    ]);
  });

  // The id must survive every CORRECTION `upsertDeployments` makes to the row it names.
  // `created_at` is mutable on purpose: a webhook seeds the row with the event's emission
  // time and the next poll lowers it to the provider's true creation time
  // (`created_at = min(excluded.created_at, created_at)`, sync.ts) — by however far the
  // two disagree, which for a queued or retried deployment is hours, not seconds.
  // `branch` and `project_name` move the same way (COALESCE / rename), and both feed
  // `ownedDeployTarget`.
  //
  // Minting the id from any of them made ONE deployment mint a SECOND id the moment a
  // correction landed. The client is where that bites: the old id vanishes from
  // `board.activity`, `useActivityHistory`'s shed-absorption keeps every vanished id
  // forever, and `mergeRows` never replaces one — so the pane kept rendering the phase
  // the row carried at the instant of the correction. That is the board reading
  // "queued"/"building" hours after the build was green, sorted BELOW its own
  // "built"/"deployed" rows (the stale copy holds the later, uncorrected timestamp), with
  // no board refetch able to clear it.
  it("keeps a deployment's row ids fixed when created_at is corrected", () => {
    const seeded = facts({
      deployEvents: [
        deploy({ deploymentId: "dpl_x", createdAtMs: NOW - 58_000, buildPhase: "building", deployPhase: "none" }),
      ],
    });
    const corrected = facts({
      deployEvents: [
        deploy({ deploymentId: "dpl_x", createdAtMs: NOW - 60_000, buildPhase: "built", deployPhase: "deployed" }),
      ],
    });
    expect(deriveActivity(seeded, NOW).map((r) => r.id)).toEqual(["deploy:dpl_x:build"]);
    expect(deriveActivity(corrected, NOW).map((r) => r.id)).toEqual([
      "deploy:dpl_x:build",
      "deploy:dpl_x:deploy",
    ]);
  });

  // The other two mutable inputs, and the reason `target` was never safe to mint from
  // either: `project_name` is overwritten outright when a Vercel project is renamed
  // (`project_name = excluded.project_name`) and `branch` is COALESCE'd in when a later
  // payload finally carries one — and `ownedDeployTarget` folds both into the target. A
  // rename therefore used to clone the deployment under a second id, with the pre-rename
  // copy going immortal on the client exactly as the created_at clone did.
  it("keeps a deployment's row ids fixed across a project rename and a late-arriving branch", () => {
    const roster = [
      entry({ endpointId: "ep-old", projectName: "hub-help-testing", url: "https://testing.help.example.com" }),
      entry({ endpointId: "ep-new", projectName: "hub-help-staging", url: "https://staging.help.example.com" }),
    ];
    const liveVercelProjects = ["hub-help-testing", "hub-help-staging"];
    const before = deriveActivity(facts({
      roster, liveVercelProjects,
      deployEvents: [deploy({ deploymentId: "dpl_r", projectName: "hub-help-testing", branch: null })],
    }), NOW);
    const after = deriveActivity(facts({
      roster, liveVercelProjects,
      deployEvents: [deploy({ deploymentId: "dpl_r", projectName: "hub-help-staging", branch: "main" })],
    }), NOW);

    expect(before.map((r) => r.id)).toEqual(["deploy:dpl_r:build", "deploy:dpl_r:deploy"]);
    expect(after.map((r) => r.id)).toEqual(before.map((r) => r.id));
    // …and the rename really did move what the retired id was minted from, so the
    // assertion above is not passing on an unchanged fixture.
    expect(after.map((r) => r.target)).not.toEqual(before.map((r) => r.target));
    expect(after.map((r) => r.branch)).toEqual(["main", "main"]);
  });

  // The id is half of the page cursor, and two deployments of one project routinely share
  // the other half: `boardTargetKey` collapses every environment of a non-railway project
  // onto ONE target, and `createdAtMs` is stored as whole seconds. The deployment id is
  // the `deployments` primary key, so it is the only part of the row id that can separate
  // them — mint from anything else and the twins share an id, `beforeCursor` excludes both
  // (`X < X` is false) so one is unreachable by any page, and the client's id-keyed merge
  // drops the other.
  //
  // Asserted as the exact ORDERED list rather than as a set of four: distinctness alone is
  // satisfied by an order the pager cannot walk, and it is the order — each deployment's
  // build immediately above its own deploy — that the cursor and the client both read.
  it("keeps two deployments of ONE project in ONE second distinct, and totally ordered", () => {
    const f = facts({
      roster: [entry({ endpointId: "ep-1" })],
      deployEvents: [
        deploy({ deploymentId: "dpl_main", branch: "main" }),
        deploy({ deploymentId: "dpl_stg", branch: "staging" }),
      ],
      liveVercelProjects: ["hub-help-testing"],
    });
    expect(deriveActivity(f, NOW).map((r) => r.id)).toEqual([
      "deploy:dpl_main:build",
      "deploy:dpl_main:deploy",
      "deploy:dpl_stg:build",
      "deploy:dpl_stg:deploy",
    ]);
  });

  it("keeps two issue events on ONE target in ONE second distinct", () => {
    const f = facts({
      roster: [entry({ endpointId: "ep-1" })],
      issueEvents: [
        issue({ id: 1, source: "http", state: "down" }),
        issue({ id: 2, source: "dns", state: "dns-fail" }),
      ],
    });
    const ids = deriveActivity(f, NOW).map((r) => r.id);
    expect(ids).toHaveLength(2);
    expect(new Set(ids).size).toBe(2);
  });

  it("REQUIREMENT A: an unmonitored site contributes no activity either", () => {
    const f = facts({ roster: [entry({ isActive: false })], deployEvents: [deploy()] });
    expect(deriveActivity(f, NOW)).toEqual([]);
  });

  it("a Vercel PREVIEW row never enters the feed, exactly as it never becomes a Problem", () => {
    const f = facts({ deployEvents: [deploy({ environment: "" }), deploy({ environment: null })] });
    expect(deriveActivity(f, NOW)).toEqual([]);
  });

  it("a CRUNCHY cluster has no roster entry and is recorded anyway", () => {
    const f = facts({
      roster: [],
      deployEvents: [deploy({ platform: "crunchy", projectName: "prod-cluster", environment: "production", buildPhase: null, deployPhase: "failed" })],
    });
    const rows = deriveActivity(f, NOW);
    // No build phase → no build row; the cluster's health wears a deploy row's clothes.
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ kind: "deploy", step: "deploy", verb: "deploy failed", tone: "bad", target: "crunchy|prod-cluster|" });
  });
});

describe("deriveActivity — issue events", () => {
  it("records an http issue opening as a PROBE row", () => {
    const rows = deriveActivity(facts({ issueEvents: [issue()] }), NOW);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ kind: "probe", step: null, verb: "down", tone: "bad", target: "ep-1", source: "http" });
  });

  // An `IssueEvent` records an incident, not a build: there is no ref it was built from
  // and no provider build log behind it. Explicit nulls rather than absent fields, so the
  // pane's Git tab and error block are OFF because the server said so — not because a
  // field happened to be missing from this producer.
  it("an issue row carries a null branch and a null errorText — an incident is not a build", () => {
    const rows = deriveActivity(facts({ issueEvents: [issue()] }), NOW);
    expect(rows[0]).toMatchObject({ branch: null, errorText: null });
  });

  it("Fix Round 2 item 1: a probe row's source is the issue's own source, dns included", () => {
    const rows = deriveActivity(facts({ issueEvents: [issue({ source: "dns" })] }), NOW);
    expect(rows[0]).toMatchObject({ kind: "probe", source: "dns" });
  });

  it("records a platform-health issue as a PLATFORM row — the TARGET says so, not the source", () => {
    const f = facts({
      platforms: [platform()],
      issueEvents: [issue({ target: "platform-health|vercel", source: "vercel", state: "unreachable" })],
    });
    expect(deriveActivity(f, NOW)[0]).toMatchObject({ kind: "platform", verb: "platform unreachable", source: "vercel" });
  });

  it("emits `[state] resolved` for a RECOVERED close", () => {
    const f = facts({ issueEvents: [issue({ resolvedAtMs: NOW - 60_000, resolvedReason: "recovered" })] });
    const rows = deriveActivity(f, NOW);
    expect(rows).toHaveLength(2);
    // The recovery is the newer of the issue's two halves, so it sits at the TAIL.
    expect(rows.at(-1)).toMatchObject({ verb: "[down] resolved", tone: "good", kind: "probe" });
  });

  it("emits NOTHING for an UNMONITORED close — nobody observed a recovery", () => {
    const f = facts({ issueEvents: [issue({ resolvedAtMs: NOW - 60_000, resolvedReason: "unmonitored" })] });
    expect(deriveActivity(f, NOW).map((r) => r.verb)).toEqual(["down"]);
  });

  it("emits nothing for a close whose reason predates the column", () => {
    const f = facts({ issueEvents: [issue({ resolvedAtMs: NOW - 60_000, resolvedReason: null })] });
    expect(deriveActivity(f, NOW).map((r) => r.verb)).toEqual(["down"]);
  });

  it("windows each half of an issue independently", () => {
    // Opened long ago, recovered just now: only the recovery is in the window.
    const f = facts({
      issueEvents: [issue({ openedAtMs: NOW - ACTIVITY_WINDOW_MS - 1, resolvedAtMs: NOW - 60_000, resolvedReason: "recovered" })],
    });
    expect(deriveActivity(f, NOW).map((r) => r.verb)).toEqual(["[down] resolved"]);
  });

  it("suppresses an issue opening the feed already records as a deploy row", () => {
    const failed = deploy({ buildPhase: "failed", deployPhase: "none" });
    const f = facts({
      deployEvents: [failed],
      issueEvents: [issue({ target: "vercel|hub-help-testing|", source: "vercel", state: "failed", openedAtMs: NOW - 59_000 })],
    });
    // The build-failed row IS the record of that event; a second "failed" row is noise.
    expect(deriveActivity(f, NOW).map((r) => r.verb)).toEqual(["build failed"]);
  });

  it("FIX 1: a BUILT (not-bad) deploy row does NOT suppress a STALE issue on the same target", () => {
    // `stale`'s precondition IS a `built`/`deployPhase: none` row — a newer build that was
    // never promoted. Only a BAD deploy row may claim a target, so both must appear.
    const f = facts({
      deployEvents: [deploy({ buildPhase: "built", deployPhase: "none" })],
      issueEvents: [issue({ target: "vercel|hub-help-testing|", source: "vercel", state: "stale", severity: "major", openedAtMs: NOW - 59_000 })],
    });
    // Chronological: the build at NOW-60s, then the issue opened at NOW-59s.
    expect(deriveActivity(f, NOW).map((r) => r.verb)).toEqual(["built", "deployment failed"]);
  });

  it("FIX 1: a DEPLOYING (not-bad) deploy row does NOT suppress a STUCK issue on the same target", () => {
    const f = facts({
      deployEvents: [deploy({ buildPhase: "built", deployPhase: "deploying" })],
      issueEvents: [issue({ target: "vercel|hub-help-testing|", source: "vercel", state: "stuck", severity: "major", openedAtMs: NOW - 59_000 })],
    });
    expect(deriveActivity(f, NOW).map((r) => r.verb)).toEqual(["built", "deploying", "deploy stuck"]);
  });

  it("keeps a STALE-prod opening, which no deploy row represents", () => {
    const f = facts({
      deployEvents: [],
      issueEvents: [issue({ target: "vercel|hub-help-testing|", source: "vercel", state: "stale", openedAtMs: NOW - 60_000 })],
    });
    expect(deriveActivity(f, NOW).map((r) => r.verb)).toEqual(["deployment failed"]);
  });

  it("still emits the RESOLVED row for a target that has a FAILED deploy row — only openings are suppressed", () => {
    const failed = deploy({ buildPhase: "failed", deployPhase: "none" });
    const f = facts({
      deployEvents: [failed],
      issueEvents: [issue({
        target: "vercel|hub-help-testing|", source: "vercel", state: "failed",
        openedAtMs: NOW - 59_000, resolvedAtMs: NOW - 58_000, resolvedReason: "recovered",
      })],
    });
    expect(deriveActivity(f, NOW).map((r) => r.verb)).toEqual(["build failed", "[deploy failed] resolved"]);
  });

  it("pins the ISSUE_VERB mapping — the word the pane shows for each observed state", () => {
    const at = (state: string) => deriveActivity(facts({ issueEvents: [issue({ state, severity: "major" })] }), NOW)[0].verb;
    expect(at("down")).toBe("down");
    expect(at("degraded")).toBe("degraded");
    expect(at("failed")).toBe("deploy failed");
    expect(at("stuck")).toBe("deploy stuck");
    expect(at("stale")).toBe("deployment failed");
    expect(at("unreachable")).toBe("platform unreachable");
  });

  it("a MINOR severity paints progress, not bad — an amber warning must not ship red", () => {
    const rows = deriveActivity(facts({ issueEvents: [issue({ severity: "minor" })] }), NOW);
    expect(rows[0]).toMatchObject({ tone: "progress" });
  });

  it("REQUIREMENT A: an inactive roster entry suppresses its endpoint's issue rows — both opened and resolved", () => {
    const f = facts({
      roster: [entry({ isActive: false })],
      issueEvents: [issue({ resolvedAtMs: NOW - 60_000, resolvedReason: "recovered" })],
    });
    expect(deriveActivity(f, NOW)).toEqual([]);
  });

  it("REQUIREMENT A: an unconfigured platform suppresses its platform-health issue rows", () => {
    const f = facts({
      platforms: [platform({ configured: false })],
      issueEvents: [issue({ target: "platform-health|vercel", source: "vercel", state: "unreachable" })],
    });
    expect(deriveActivity(f, NOW)).toEqual([]);
  });
});

describe("deriveActivity — explicit window floor", () => {
  it("drops rows older than the default 24h floor when fromMs is omitted", () => {
    const old = deploy({ createdAtMs: NOW - ACTIVITY_WINDOW_MS - 60_000 });
    expect(deriveActivity(facts({ deployEvents: [old] }), NOW)).toHaveLength(0);
  });

  it("keeps rows older than 24h when an explicit fromMs allows them", () => {
    const old = deploy({ createdAtMs: NOW - 40 * 24 * 60 * 60 * 1000 });
    const rows = deriveActivity(facts({ deployEvents: [old] }), NOW, undefined, undefined, 0);
    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatchObject({ step: "build", verb: "built" });
  });

  it("applies fromMs to issue rows too, both halves", () => {
    const e = issue({
      openedAtMs: NOW - 40 * 24 * 60 * 60 * 1000,
      resolvedAtMs: NOW - 39 * 24 * 60 * 60 * 1000,
      resolvedReason: "recovered",
    });
    expect(deriveActivity(facts({ issueEvents: [e] }), NOW)).toHaveLength(0);
    const rows = deriveActivity(facts({ issueEvents: [e] }), NOW, undefined, undefined, 0);
    expect(rows.map((r) => r.verb)).toEqual(["down", "[down] resolved"]);
  });
});

describe("indicatorFor", () => {
  it("operational when there are no problems", () => {
    expect(indicatorFor([])).toBe("operational");
  });
  it("degraded when the worst problem is major or minor", () => {
    expect(indicatorFor([problem({ severity: "minor" })])).toBe("degraded");
    expect(indicatorFor([problem({ severity: "major" })])).toBe("degraded");
  });
  it("outage when any problem is critical", () => {
    expect(indicatorFor([problem({ severity: "major" }), problem({ severity: "critical" })])).toBe("outage");
  });
});
