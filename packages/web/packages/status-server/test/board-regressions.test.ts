import { describe, it, expect } from "vitest";
import { deriveBoard } from "../src/board/derive";
import { DEGRADED_CONFIRM_MS } from "../src/board/types";
import { PLATFORM_UNREACHABLE_POLLS } from "../src/monitor/issue-sources";
import type {
  BoardFacts, DeployFact, EndpointFact, RosterEntry, StaleProdFact,
} from "../src/board/types";

const NOW = Date.UTC(2026, 7, 2, 12, 0, 0);

function entry(over: Partial<RosterEntry> = {}): RosterEntry {
  return {
    endpointId: "ep-1", label: "Hub Help (testing)", platform: "vercel", providerProjectId: null,
    projectName: "hub-help-testing", environment: "production", isActive: true,
    monitorHttp: true, monitorDeploys: true, ignoreProjectWarning: false,
    url: "https://testing.help.example.com", ...over,
  };
}
// Every ActivityRow id carries its fact's primary key, because the page cursor is the
// (time, id) PAIR and timestamps are whole seconds. A shared default would mint
// byte-identical ids here and hide exactly the collision that id is there to prevent.
let deploySeq = 0;
function deploy(over: Partial<DeployFact> = {}): DeployFact {
  return {
    deploymentId: `dpl_${++deploySeq}`,
    platform: "vercel", providerProjectId: null, projectName: "hub-help-testing",
    environment: "production", branch: null, buildPhase: "built", deployPhase: "deployed",
    createdAtMs: NOW - 60_000, commitHash: "abc1234", commitMessage: "fix: thing",
    commitRepo: "adh", errorText: null, sourceUrl: null, liveUrl: null, ...over,
  };
}
function stale(over: Partial<StaleProdFact> = {}): StaleProdFact {
  return {
    platform: "vercel", providerProjectId: null, projectName: "hub-help-testing",
    environment: "production", branch: null, detail: "production deploy is 3 builds behind",
    sourceUrl: null, liveUrl: null, ...over,
  };
}
function facts(over: Partial<BoardFacts> = {}): BoardFacts {
  return {
    roster: [entry()], probeIntervalMs: 60_000, deploys: [], inFlightDeploys: [], deployEvents: [],
    endpoints: [], platforms: [],
    staleProd: [], ledger: [], issueEvents: [], liveVercelProjects: ["hub-help-testing"],
    errors: [], errorsConfigured: true, errorProjectAllowlist: null, ...over,
  };
}

describe("regressions", () => {
  it("THE BUG THAT STARTED THIS: hub-help-testing builds and deploys fine, so it is NOT a problem", () => {
    const f = facts({
      deploys: [deploy({ buildPhase: "built", deployPhase: "deployed" })],
      endpoints: [{ endpointId: "ep-1", status: "healthy", statusCode: 200, dnsOk: true, checkedAtMs: NOW, badSinceMs: null }],
      ledger: [{ target: "vercel|hub-help-testing|", openedAtMs: NOW - 86_400_000 }],
    });
    expect(deriveBoard(f, NOW).problems).toEqual([]);
  });

  it("bc2e21d0f — a DELETED site's problems vanish with it, ownership is a filter not a decoration", () => {
    const f = facts({ roster: [], deploys: [deploy({ buildPhase: "failed", deployPhase: "none" })] });
    expect(deriveBoard(f, NOW).problems).toEqual([]);
  });

  it("843a46d93 — an EMPTY roster means 'serves nothing', so nothing is a problem", () => {
    const f = facts({
      roster: [],
      deploys: [deploy({ buildPhase: "failed", deployPhase: "none" })],
      endpoints: [{ endpointId: "ep-1", status: "down", statusCode: 503, dnsOk: true, checkedAtMs: NOW, badSinceMs: NOW - 3600_000 }],
      platforms: [{ source: "vercel", configured: true, ok: true, streak: 0, sampledAtMs: NOW }],
    });
    const board = deriveBoard(f, NOW);
    expect(board.problems).toEqual([]);
    expect(board.indicator).toBe("operational");
  });

  it("1c407fa06 — a PAUSED monitor is configured but contributes nothing", () => {
    const f = facts({
      roster: [entry({ isActive: false })],
      deploys: [deploy({ buildPhase: "failed", deployPhase: "none" })],
    });
    expect(deriveBoard(f, NOW).problems).toEqual([]);
  });

  it("a project RENAMED in config leaves no wedged problem under the old name", () => {
    const f = facts({
      roster: [entry({ projectName: "adh-backend" })],
      deploys: [
        deploy({ projectName: "agentic-developer-hub-backend", buildPhase: "failed", deployPhase: "none" }),
        deploy({ projectName: "adh-backend", buildPhase: "built", deployPhase: "deployed" }),
      ],
    });
    expect(deriveBoard(f, NOW).problems).toEqual([]);
  });

  // The vanished-project guard lives in `staleProdProblems` and NOWHERE else, so these
  // three must feed `staleProd` to reach it. Asserting on a plain failed deploy instead
  // would pass no matter what `liveVercelProjects` said — a test that never runs the rule
  // it is named for.
  it("a Vercel read that returns NOTHING does not silence the fleet — an empty read is not mass deletion", () => {
    const f = facts({ staleProd: [stale()], liveVercelProjects: [] });
    expect(deriveBoard(f, NOW).problems.map((p) => p.state)).toEqual(["stale"]);
  });

  it("an ALL-vanished Vercel read is equally untrusted — narrowing everything away is the same failure", () => {
    const f = facts({ staleProd: [stale()], liveVercelProjects: ["some-unrelated-project"] });
    expect(deriveBoard(f, NOW).problems.map((p) => p.state)).toEqual(["stale"]);
  });

  it("a PARTIAL vanish IS trusted: the deleted project's row goes, its live sibling's stays", () => {
    // Without this the guard could degenerate into "never narrow" and still pass the two
    // above — a deleted project would then keep its row forever.
    const f = facts({
      roster: [entry(), entry({ endpointId: "ep-2", projectName: "hub-docs-testing" })],
      staleProd: [stale(), stale({ projectName: "hub-docs-testing" })],
      liveVercelProjects: ["hub-docs-testing"],
    });
    expect(deriveBoard(f, NOW).problems.map((p) => p.name)).toEqual(["hub-docs-testing"]);
  });

  it("f21284e26/9fe25b304 — the PLATFORM debounce is applied exactly once, at the threshold", () => {
    // The client re-implemented the server's debounce on top of it, so a real outage had
    // to fail 2x2 polls before anyone saw it. One home for the rule means the threshold is
    // crossed exactly at the threshold.
    const platform = (streak: number) =>
      facts({ platforms: [{ source: "vercel" as const, configured: true, ok: false, streak, sampledAtMs: NOW }] });
    expect(deriveBoard(platform(PLATFORM_UNREACHABLE_POLLS - 1), NOW).problems).toEqual([]);
    expect(deriveBoard(platform(PLATFORM_UNREACHABLE_POLLS), NOW).problems.map((p) => p.state))
      .toEqual(["unreachable"]);
  });

  it("f21284e26/9fe25b304 — the DEGRADED debounce fires at DEGRADED_CONFIRM_MS, not at twice it", () => {
    const degraded = (badForMs: number): EndpointFact => ({
      endpointId: "ep-1", status: "degraded", statusCode: 500, dnsOk: true,
      checkedAtMs: NOW, badSinceMs: NOW - badForMs,
    });
    expect(deriveBoard(facts({ endpoints: [degraded(DEGRADED_CONFIRM_MS - 1)] }), NOW).problems).toEqual([]);
    expect(deriveBoard(facts({ endpoints: [degraded(DEGRADED_CONFIRM_MS)] }), NOW).problems.map((p) => p.state))
      .toEqual(["degraded"]);
    // A doubled window would still be silent here. It must not be.
    expect(deriveBoard(facts({ endpoints: [degraded(2 * DEGRADED_CONFIRM_MS - 1)] }), NOW).problems)
      .toHaveLength(1);
  });

  it("the board is READ-ONLY over its facts — deriving twice does not mutate them", () => {
    const f = facts({ deploys: [deploy({ buildPhase: "failed", deployPhase: "none" })] });
    const snapshot = JSON.parse(JSON.stringify(f));
    deriveBoard(f, NOW);
    deriveBoard(f, NOW);
    expect(JSON.parse(JSON.stringify(f))).toEqual(snapshot);
  });

  it("a fixed problem clears on the very next derivation — no durable client state to sweep", () => {
    const broken = facts({ deploys: [deploy({ buildPhase: "failed", deployPhase: "none", createdAtMs: NOW - 7200_000 })] });
    expect(deriveBoard(broken, NOW).problems).toHaveLength(1);
    const fixed = facts({
      deploys: [deploy({ buildPhase: "built", deployPhase: "deployed", createdAtMs: NOW - 60_000 })],
      ledger: [{ target: "vercel|hub-help-testing|", openedAtMs: NOW - 7200_000 }],
    });
    expect(deriveBoard(fixed, NOW).problems).toEqual([]);
  });

  it("a stale LEDGER row never resurrects a problem the facts do not support", () => {
    const f = facts({
      deploys: [deploy({ buildPhase: "built", deployPhase: "deployed" })],
      ledger: [
        { target: "vercel|hub-help-testing|", openedAtMs: NOW - 86_400_000 },
        { target: "vercel|some-site-deleted-last-year|", openedAtMs: NOW - 86_400_000 },
      ],
    });
    expect(deriveBoard(f, NOW).problems).toEqual([]);
  });

  it("REQUIREMENT A, through the whole fold: monitorHttp=false clears a DOWN site's problem", () => {
    const down: EndpointFact = { endpointId: "ep-1", status: "down", statusCode: 503, dnsOk: true, checkedAtMs: NOW, badSinceMs: NOW - 3600_000 };
    expect(deriveBoard(facts({ endpoints: [down] }), NOW).problems).toHaveLength(1);
    const off = facts({ roster: [entry({ monitorHttp: false })], endpoints: [down] });
    const board = deriveBoard(off, NOW);
    expect(board.problems).toEqual([]);
    expect(board.indicator).toBe("operational");
  });
});

/**
 * `since` is the EARLIER of the two onsets the fold has — the ledger's write time and the
 * observation's own start. Each is wrong alone and in the OPPOSITE direction, so a rule
 * that always prefers one of them is wrong half the time; only the three cases together
 * pin the rule down. Written against the whole fold, because the helper is shared by all
 * four Problem sources and the bug it fixes was only ever visible in the output.
 */
describe("a Problem's `since`", () => {
  const down: EndpointFact = {
    endpointId: "ep-1", status: "down", statusCode: 503, dnsOk: true,
    checkedAtMs: NOW, badSinceMs: NOW - 3600_000,
  };

  it("takes the LEDGER's onset when the ledger is earlier — the probe's badSince is not the start", () => {
    // The regression guarded here: the fallback order silently inverting, so every endpoint
    // problem re-aged itself to the newest bad probe.
    const onset = NOW - 5 * 86_400_000;
    const f = facts({ endpoints: [down], ledger: [{ target: "ep-1", openedAtMs: onset }] });
    expect(deriveBoard(f, NOW).problems[0]?.since).toBe(new Date(onset).toISOString());
  });

  it("takes the OBSERVED onset when the ledger is later — a re-opened row is not a new outage", () => {
    // A target respelled by a deploy closes every open row and re-opens it under the new
    // key, stamping openedAt = now. Preferring the ledger would render a site that has been
    // down for five days as "down 1m ago" on the first cycle after every such deploy.
    const badSince = NOW - 5 * 86_400_000;
    const f = facts({
      endpoints: [{ ...down, badSinceMs: badSince }],
      ledger: [{ target: "ep-1", openedAtMs: NOW - 60_000 }],
    });
    expect(deriveBoard(f, NOW).problems[0]?.since).toBe(new Date(badSince).toISOString());
  });

  it("does NOT reset when a broken target fails AGAIN — successive failures are one outage", () => {
    // This is the case the ledger exists for. Each new failed build carries a newer
    // createdAtMs, so the observed onset alone would keep sliding forward and a target
    // broken since Monday would report itself broken for a minute after every retry.
    const onset = NOW - 3 * 3600_000;
    const f = facts({
      deploys: [deploy({ buildPhase: "failed", deployPhase: "none", createdAtMs: NOW - 60_000 })],
      ledger: [{ target: "vercel|hub-help-testing|", openedAtMs: onset }],
    });
    const [problem] = deriveBoard(f, NOW).problems;
    expect(problem?.state).toBe("failed");
    expect(problem?.since).toBe(new Date(onset).toISOString());
  });
});

/**
 * `dataAsOfMs` is the DATA clock. `generatedAt` is the DERIVATION clock, and the whole
 * point of the field is that the two come apart when the monitor wedges: the facts freeze
 * at last-known-healthy, `problems` empties, and the board keeps stamping a fresh
 * `generatedAt` over dead data forever. Every case here is written against the whole fold,
 * because a data clock computed anywhere but from the facts the fold actually consumed
 * would still pass a unit test of the helper alone.
 */
describe("the board's DATA clock", () => {
  it("does NOT move when the facts are frozen and only the derivation clock advances", () => {
    // THE wedged-monitor case. `generatedAt` must move (the read really did happen) and
    // `dataAsOfMs` must not (nothing was observed). A data clock that read `nowMs` — or
    // defaulted to it on any path — would tie here and the guard would be decorative.
    const frozen = facts({
      endpoints: [{ endpointId: "ep-1", status: "healthy", statusCode: 200, dnsOk: true, checkedAtMs: NOW - 7200_000, badSinceMs: null }],
      platforms: [{ source: "vercel", configured: true, ok: true, streak: 0, sampledAtMs: NOW - 7200_000 }],
    });
    const first = deriveBoard(frozen, NOW);
    const later = deriveBoard(frozen, NOW + 6 * 3600_000);
    expect(first.dataAsOfMs).toBe(NOW - 7200_000);
    expect(later.dataAsOfMs).toBe(NOW - 7200_000);
    expect(later.generatedAt).not.toBe(first.generatedAt);
    // And the indicator alone still says everything is fine — which is exactly why the
    // clock has to be on the wire for the client to fold in.
    expect(later.indicator).toBe("operational");
  });

  it("is null when the board rests on no observation at all — absence is not health", () => {
    const board = deriveBoard(facts(), NOW);
    expect(board.dataAsOfMs).toBeNull();
    expect(board.problems).toEqual([]);
  });

  it("takes the NEWEST observation across the two families that prove a cycle ran", () => {
    // Either family alone is silent in some real state — a fleet of pure-Railway services
    // has no HTTP probe at all — so the clock is the max over both, not either one.
    const f = facts({
      endpoints: [{ endpointId: "ep-1", status: "healthy", statusCode: 200, dnsOk: true, checkedAtMs: NOW - 3600_000, badSinceMs: null }],
      platforms: [{ source: "vercel", configured: true, ok: true, streak: 0, sampledAtMs: NOW - 120_000 }],
    });
    expect(deriveBoard(f, NOW).dataAsOfMs).toBe(NOW - 120_000);
    // ...and the other way round, so this is a max and not "whichever family is listed
    // last happens to win".
    const g = facts({
      endpoints: [{ endpointId: "ep-1", status: "healthy", statusCode: 200, dnsOk: true, checkedAtMs: NOW - 60_000, badSinceMs: null }],
      platforms: [{ source: "vercel", configured: true, ok: true, streak: 0, sampledAtMs: NOW - 3600_000 }],
    });
    expect(deriveBoard(g, NOW).dataAsOfMs).toBe(NOW - 60_000);
  });

  it("is NOT moved by a deploy row — a webhook carries the PROVIDER's clock, not ours", () => {
    // THE case the field exists for, through the door that stayed open. The monitor is
    // wedged at T0 and Hono keeps serving, so `routes/hooks.ts` keeps writing Vercel /
    // Railway webhook rows (stamped by the provider) and reconciling the ledger itself.
    // If any deploy family fed this clock, that one webhook would report the board as
    // freshly observed while every probe and platform sample had been frozen for two
    // hours — `problems` stuck at last-known-healthy, the client's freshness guard never
    // firing, `operational` served over dead data. A deploy row is evidence a PROVIDER
    // did something; only a fact the monitor writes on its own cadence is evidence that
    // we are still looking.
    const frozenAt = NOW - 7200_000;
    const f = facts({
      endpoints: [{ endpointId: "ep-1", status: "healthy", statusCode: 200, dnsOk: true, checkedAtMs: frozenAt, badSinceMs: null }],
      platforms: [{ source: "vercel", configured: true, ok: true, streak: 0, sampledAtMs: frozenAt }],
      // All three deploy families, every one of them stamped RIGHT NOW.
      deploys: [deploy({ createdAtMs: NOW })],
      inFlightDeploys: [deploy({ buildPhase: "building", deployPhase: "none", createdAtMs: NOW })],
      deployEvents: [deploy({ createdAtMs: NOW })],
    });
    const board = deriveBoard(f, NOW);
    expect(board.dataAsOfMs).toBe(frozenAt);
    // And the reading the client would otherwise get: the board looks perfectly healthy.
    expect(board.indicator).toBe("operational");
  });

  it("is null when the ONLY observations are deploy rows — a provider clock is no clock", () => {
    // The degenerate shape of the same rule. Nothing here was written by a cycle, so the
    // board rests on no observation at all and must say so rather than name a time.
    const f = facts({
      deploys: [deploy({ createdAtMs: NOW })],
      deployEvents: [deploy({ createdAtMs: NOW })],
    });
    expect(deriveBoard(f, NOW).dataAsOfMs).toBeNull();
  });

  it("is NOT refreshed by the ledger — the board's own writes cannot certify its freshness", () => {
    // `ledger`/`issueEvents` are what `applyBoardToLedger` wrote back last cycle. Counting
    // them would let a wedged monitor's last verdict keep the clock looking alive.
    const f = facts({
      ledger: [{ target: "vercel|hub-help-testing|", openedAtMs: NOW }],
      issueEvents: [{
        id: 1,
        target: "vercel|hub-help-testing|", source: "vercel", name: "hub-help-testing",
        environment: "production", state: "failed", severity: "major", detail: null,
        sourceUrl: null, liveUrl: null, commitHash: null, commitMessage: null, commitRepo: null,
        openedAtMs: NOW, resolvedAtMs: null, resolvedReason: null,
      }],
    });
    expect(deriveBoard(f, NOW).dataAsOfMs).toBeNull();
  });
});
