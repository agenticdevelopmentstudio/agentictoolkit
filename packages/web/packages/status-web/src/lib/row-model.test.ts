import { describe, it, expect } from "vitest";
import type { DeploymentDTO } from "../types";
import type { Problem, ActivityRow } from "./board-types";
import { ISSUE_SOURCES, isIssueSource } from "./issue-sources";
import {
  problemToRow,
  activityToRow,
  rowToStatusRowProps,
  rowSearchText,
  commitUrlOf,
  deployDtoUnconfirmed,
  unconfirmedWindowMs,
  UNCONFIRMED_AFTER_MS,
  type Row,
} from "./row-model";

function deploy(overrides: Partial<DeploymentDTO>): DeploymentDTO {
  return {
    id: "vc_1",
    platform: "vercel",
    projectName: "adh",
    status: "success",
    buildPhase: "built",
    deployPhase: "none",
    environment: "production",
    tier: "production",
    commitHash: "abc1234def",
    commitMessage: "test commit\nsecond line",
    branch: "main",
    commitRepo: null,
    url: "https://x.vercel.app",
    errorText: null,
    liveHost: null,
    createdAt: "2026-06-04T18:00:00.000Z",
    ...overrides,
  };
}

function problem(o: Partial<Problem>): Problem {
  return {
    target: "adh-app-production",
    source: "http",
    name: "App",
    environment: "production",
    severity: "major",
    state: "down",
    since: "2026-06-04T18:00:00.000Z",
    statusCode: 503,
    detail: "HTTP 503",
    sourceUrl: "https://x",
    liveUrl: "https://x",
    commitHash: null,
    commitMessage: null,
    commitRepo: null,
    branch: null,
    errorText: null,
    ...o,
  };
}

describe("problemToRow", () => {
  it("maps a deploy problem: source word, severity→tone, recorded links pass through", () => {
    const r = problemToRow(
      problem({
        source: "vercel",
        state: "failed",
        name: "adh",
        sourceUrl: "https://vercel.com/team/adh",
        liveUrl: "https://app.example.com",
      }),
    );
    expect(r.source).toBe("vercel");
    expect(r.platform).toBe("vercel");
    expect(r.statusWord).toBe("deploy failed");
    expect(r.tone).toBe("bad"); // major → bad (red, bold)
    // Links are the values recorded on the problem (the server stamps them).
    expect(r.sourceUrl).toBe("https://vercel.com/team/adh");
    expect(r.liveUrl).toBe("https://app.example.com");
    expect(r.at).toBe("2026-06-04T18:00:00.000Z"); // since
  });

  it("renders the commit on a deploy problem (sha + GitHub link + first line)", () => {
    const r = problemToRow(
      problem({
        source: "vercel",
        state: "failed",
        name: "adh",
        commitHash: "abc1234def",
        commitRepo: "example-org/example-app",
        commitMessage: "fix the thing\nbody text",
      }),
    );
    expect(r.sha).toBe("abc1234");
    expect(r.commitUrl).toBe("https://github.com/example-org/example-app/commit/abc1234def");
    expect(r.message).toBe("fix the thing");
  });

  it("shows the commit on a railway problem (the poller now reports a usable commit)", () => {
    const r = problemToRow(
      problem({
        source: "railway",
        state: "failed",
        name: "adh-backend",
        commitHash: "abc1234def",
        commitRepo: "example-org/example-app",
        commitMessage: "fix the thing\nbody text",
      }),
    );
    expect(r.sha).toBe("abc1234");
    expect(r.commitUrl).toBe("https://github.com/example-org/example-app/commit/abc1234def");
    expect(r.message).toBe("fix the thing");
  });

  it("keeps the recorded links for endpoint (http/dns) problems — no deploy links apply", () => {
    const r = problemToRow(problem({ source: "http", sourceUrl: "https://app.example.com", liveUrl: "https://app.example.com" }));
    expect(r.sourceUrl).toBe("https://app.example.com");
    expect(r.liveUrl).toBe("https://app.example.com");
    expect(r.sha).toBeNull();
    expect(r.commitUrl).toBeNull();
  });

  it("suppresses a bare sha when the commit has a hash but no repo (nothing to link to)", () => {
    const r = problemToRow(problem({ source: "vercel", state: "failed", commitHash: "abc1234def", commitRepo: null, commitMessage: "fix the thing\nbody" }));
    expect(r.commitUrl).toBeNull();
    expect(r.sha).toBeNull(); // no repo → no linkable sha: don't render a non-clickable hash
    expect(r.message).toBe("fix the thing"); // the message still shows on its own
  });

  it("labels a stuck deploy problem distinctly from a failed one", () => {
    expect(problemToRow(problem({ source: "vercel", state: "stuck" })).statusWord).toBe("deploy stuck");
  });

  it("a minor (degraded) problem is amber/progress; others are red/bad", () => {
    expect(problemToRow(problem({ severity: "minor", state: "degraded" })).tone).toBe("progress");
    expect(problemToRow(problem({ severity: "major" })).tone).toBe("bad");
  });

  it("keeps the full commit body on the row while message stays the subject", () => {
    const r = problemToRow(
      problem({
        source: "vercel",
        state: "failed",
        commitHash: "abc1234def",
        commitRepo: "o/r",
        commitMessage: "fix the thing\n\nbody line 1\nbody line 2",
      }),
    );
    expect(r.message).toBe("fix the thing");
    expect(r.commitBody).toBe("fix the thing\n\nbody line 1\nbody line 2");
  });

  it("carries the branch and the provider errorText onto the row — the details pane reads both", () => {
    // `rowToDetail` maps them straight through to the Git tab and the error block, so a row
    // that drops them here renders two empty panes with nothing to say why.
    const r = problemToRow(
      problem({ source: "vercel", state: "failed", branch: "prepared", errorText: "next build exited 1" }),
    );
    expect(r.branch).toBe("prepared");
    expect(r.errorText).toBe("next build exited 1");
  });

  it("renders the server's word and tone verbatim however old the row is (C3)", () => {
    // A Problem's state/severity is already the server's verdict (derive-problems.ts), so
    // NOTHING client-side may re-judge it. There used to be a second, client-side
    // freshness clock here that demoted an aged in-flight row to "last seen building";
    // it is gone, and this pins that: 30 days on, the row still says what the server said.
    const r = problemToRow(problem({ source: "vercel", state: "failed", since: "2026-06-04T18:00:00.000Z" }));
    const nowMs = Date.parse(r.at) + 30 * 86_400_000; // 30 days later
    const props = rowToStatusRowProps(r, nowMs);
    expect(props.statusWord).toBe(r.statusWord);
    expect(props.statusColor).toBe("var(--color-apt-red)"); // the `bad` tone, undemoted
  });
});

describe("activityToRow", () => {
  function activity(o: Partial<ActivityRow>): ActivityRow {
    return {
      id: "a1",
      kind: "deploy",
      step: "build",
      source: null,
      tone: "good",
      verb: "built",
      target: "vercel|adh123|",
      name: "adh",
      environment: "production",
      detail: null,
      sourceUrl: null,
      liveUrl: null,
      commitHash: null,
      commitMessage: null,
      commitRepo: null,
      branch: null,
      errorText: null,
      at: "2026-06-04T18:00:00.000Z",
      ...o,
    };
  }

  // Fix Round 2 item 1: `Row.platform`/`Row.source` now come straight off the wire
  // (`ActivityRow.source`), never parsed from `a.target` — the server already knows the
  // row's provider/probe and there is no reason for the client to re-derive it. One case
  // per kind proves the direct pass-through.

  it("deploy kind: platform/source come directly from a.source, verb/tone pass through verbatim", () => {
    const r = activityToRow(activity({ kind: "deploy", source: "vercel", target: "vercel|adh123|", verb: "deployed", tone: "good" }));
    expect(r.platform).toBe("vercel");
    expect(r.source).toBe("vercel");
    expect(r.statusWord).toBe("deployed");
    expect(r.tone).toBe("good");
  });

  it("probe kind: platform/source is the issue's own a.source (http/dns) — exactly the predicate StatusRow/row-detail use for isEndpoint", () => {
    const r = activityToRow(activity({ kind: "probe", step: null, source: "http", target: "adh-app-production", verb: "down", tone: "bad" }));
    expect(r.platform).toBe("http");
    expect(r.source).toBe("http");
    expect(r.statusWord).toBe("down");
    expect(r.tone).toBe("bad");
    // Before this fix `r.platform` was always null for a probe row (there is no platform
    // segment in an endpoint's bare target to parse) — isEndpoint (StatusRow.tsx:86,
    // row-detail.ts:82: `platform === "http" || platform === "dns"`) could never be true
    // for a probe row, so an endpoint row rendered with deploy-row chrome.
    expect(r.platform === "http" || r.platform === "dns").toBe(true);
  });

  it("probe kind (dns): platform/source is 'dns', also satisfying isEndpoint", () => {
    const r = activityToRow(activity({ kind: "probe", step: null, source: "dns", target: "adh-app-production", verb: "down", tone: "bad" }));
    expect(r.platform).toBe("dns");
    expect(r.platform === "http" || r.platform === "dns").toBe(true);
  });

  it("platform kind: platform/source come directly from a.source — platform-health rows carry the provider itself, not a parsed target segment", () => {
    const r = activityToRow(
      activity({ kind: "platform", step: null, source: "cloudflare-pages", target: "platform-health|cloudflare-pages", verb: "unreachable", tone: "bad" }),
    );
    expect(r.platform).toBe("cloudflare-pages");
    expect(r.source).toBe("cloudflare-pages");
  });

  it("falls back to the row's kind only when the server genuinely couldn't attribute a source (should not happen in practice)", () => {
    const r = activityToRow(activity({ kind: "deploy", source: null, target: "vercel|adh123|" }));
    expect(r.platform).toBeNull();
    expect(r.source).toBe("deploy");
  });

  it("a cloudflare-pages row's source arrives already un-canonicalised, so it survives the source filter's default seed (C2 regression, restored via item 1)", () => {
    // boardTargetKey canonicalises "cloudflare-pages" down to "cloudflare" in the
    // TARGET; ActivityRow.source never goes through boardTargetKey at all
    // (derive-activity.ts:110 stamps the deploy's raw `d.platform`), so there is no
    // un-canonicalisation left to do client-side — the row is simply passed through.
    const r = activityToRow(activity({ kind: "deploy", source: "cloudflare-pages", target: "cloudflare|proj123|", verb: "deployed", tone: "good" }));
    expect(r.platform).toBe("cloudflare-pages");
    expect(r.source).toBe("cloudflare-pages");
    expect(isIssueSource(r.platform!)).toBe(true);
    // useSourceFilter's default seed selects every ISSUE_SOURCES member.
    expect(new Set(ISSUE_SOURCES).has(r.platform as (typeof ISSUE_SOURCES)[number])).toBe(true);
  });

  it("carries the branch and the provider errorText onto the row, same as a problem does", () => {
    const r = activityToRow(activity({ branch: "staging", errorText: "next build exited 1" }));
    expect(r.branch).toBe("staging");
    expect(r.errorText).toBe("next build exited 1");
  });

  it("never re-demotes an activity row, however old — the server's verb/tone stand (C3 regression)", () => {
    // The server's own unconfirmed window is hours; the client's was a 10-minute floor.
    // An activity row's tone/verb is already the server's verdict (derive-activity.ts,
    // which expires an unconfirmed phase to verb "unknown" / tone "stale" itself) — so a
    // client-side re-demotion after 10 minutes could only be a second, disagreeing
    // opinion about the same fact. There is no longer any code that could form one; this
    // pins that an hour-old "building" still renders as the server spelled it.
    const at = "2026-06-04T18:00:00.000Z";
    const r = activityToRow(activity({ verb: "building", tone: "progress", at }));
    const nowMs = Date.parse(at) + 3600_000; // an hour later
    expect(rowToStatusRowProps(r, nowMs)).toMatchObject({
      statusWord: "building",
      statusColor: "var(--color-apt-gold)", // the `progress` tone, not muted "stale"
    });
  });
});

describe("rowToStatusRowProps (the one adapter every pane uses)", () => {
  function row(o: Partial<Row>): Row {
    return {
      key: "k",
      source: "vercel",
      platform: "vercel",
      name: "adh",
      environment: "production",
      statusWord: "deployed",
      tone: "good",
      sha: null,
      commitUrl: null,
      message: null,
      detail: null,
      at: "2026-06-04T18:00:00.000Z",
      sourceUrl: null,
      liveUrl: null,
      ...o,
    };
  }
  const now = new Date("2026-06-04T18:01:00.000Z").getTime();

  it("derives color + bold weight from the row's tone", () => {
    expect(rowToStatusRowProps(row({ tone: "good" }), now)).toMatchObject({ statusColor: "var(--color-apt-green)", statusBold: false });
    expect(rowToStatusRowProps(row({ tone: "bad" }), now)).toMatchObject({ statusColor: "var(--color-apt-red)", statusBold: true });
    expect(rowToStatusRowProps(row({ tone: "progress" }), now)).toMatchObject({ statusColor: "var(--color-apt-gold)", statusBold: false });
  });

  it("passes the links through and computes a relative time label", () => {
    const p = rowToStatusRowProps(row({ liveUrl: "https://live", sourceUrl: "https://src" }), now);
    expect(p).toMatchObject({ liveUrl: "https://live", sourceUrl: "https://src" });
    expect(typeof p.timeLabel).toBe("string");
  });
});

describe("rowSearchText", () => {
  it("includes name, env, status word, detail, and the full commit message (subject + body)", () => {
    const r = problemToRow(problem({ name: "adh", source: "vercel", state: "failed", commitMessage: "broke login\nbody" }));
    const text = rowSearchText(r);
    expect(text).toContain("adh");
    expect(text).toContain("production");
    expect(text).toContain("deploy failed");
    expect(text).toContain("broke login");
    // The full body is searchable now, not just the subject line.
    expect(text).toContain("body");
  });

  it("searches the SAME word the row renders — a stale row is spelled by the server, not re-worded here", () => {
    // The word the filter matches and the word on screen are now the one field, which is
    // the point: they cannot disagree. A phase the server gave up on arrives already
    // spelled "unknown" with tone "stale" (derive-activity.ts) — the client neither
    // prepends "last seen " nor knows how to.
    const at = "2026-06-04T18:00:00.000Z";
    const row: Row = {
      key: "build:x", source: "vercel", platform: "vercel", name: "adh", environment: "production",
      statusWord: "unknown", tone: "stale", sha: null, commitUrl: null, message: null,
      detail: null, at, sourceUrl: null, liveUrl: null,
    };
    expect(rowSearchText(row)).toContain("unknown");
    expect(rowToStatusRowProps(row, Date.parse(at)).statusWord).toBe("unknown");
  });
});

describe("commitUrlOf", () => {
  it("builds a GitHub commit url from owner/name + sha, else null", () => {
    expect(commitUrlOf("o/r", "deadbeef")).toBe("https://github.com/o/r/commit/deadbeef");
    expect(commitUrlOf(null, "deadbeef")).toBeNull();
    expect(commitUrlOf("o/r", null)).toBeNull();
  });
});

describe("unconfirmedWindowMs (cadence-scaled demotion window)", () => {
  it("is the floor when the probe is fast or unknown, and 5× the interval when slow", () => {
    expect(unconfirmedWindowMs(undefined)).toBe(UNCONFIRMED_AFTER_MS);
    expect(unconfirmedWindowMs(60_000)).toBe(UNCONFIRMED_AFTER_MS); // 5×60s=5min < 10min floor
    expect(unconfirmedWindowMs(5 * 60_000)).toBe(25 * 60_000); // 5×5min = 25min > floor
  });
});

// The ONLY freshness clock left in the client. The Row-side twin this used to sit beside
// is gone: a Row arrives already judged (the server expires an unconfirmed phase to verb
// "unknown" / tone "stale" in derive-activity.ts), whereas a DeploymentDTO is raw provider
// state the panels render directly, so it still needs judging here.
describe("deployDtoUnconfirmed (DTO-side demotion, for DeployList / summarizeByPlatform)", () => {
  const confirmed = "2026-06-04T18:00:00.000Z";
  const confirmedMs = Date.parse(confirmed);

  it("demotes an in-flight deploy whose phase outlived its confirmation", () => {
    const d = deploy({ status: "building", buildPhase: "building", deployPhase: "none", phaseConfirmedAt: confirmed });
    expect(deployDtoUnconfirmed(d, confirmedMs + UNCONFIRMED_AFTER_MS - 1)).toBe(false);
    expect(deployDtoUnconfirmed(d, confirmedMs + UNCONFIRMED_AFTER_MS + 1)).toBe(true);
  });

  it("never demotes a terminal (settled) deploy, however old", () => {
    const d = deploy({ status: "success", buildPhase: "built", deployPhase: "deployed", phaseConfirmedAt: confirmed });
    expect(deployDtoUnconfirmed(d, confirmedMs + 30 * 86_400_000)).toBe(false);
  });

  it("fails CLOSED on an unparseable clock, and falls back to createdAt when no phaseConfirmedAt", () => {
    const noClock = deploy({ status: "building", buildPhase: "building", deployPhase: "none", createdAt: confirmed });
    delete (noClock as { phaseConfirmedAt?: string }).phaseConfirmedAt;
    expect(deployDtoUnconfirmed(noClock, confirmedMs + UNCONFIRMED_AFTER_MS + 1)).toBe(true);
    const broken = deploy({ status: "building", buildPhase: "building", deployPhase: "none", createdAt: "nope" });
    delete (broken as { phaseConfirmedAt?: string }).phaseConfirmedAt;
    expect(deployDtoUnconfirmed(broken, confirmedMs)).toBe(true);
  });

  it("honors the cadence-scaled window over the floor", () => {
    // A SLOWER backend probe widens the window, so a deploy re-confirmed on that slower
    // cadence is not false-demoted at the 10-minute floor — only past its own threshold.
    const d = deploy({ status: "building", buildPhase: "building", deployPhase: "none", phaseConfirmedAt: confirmed });
    const slow = 6 * 60_000; // 5× = 30min
    expect(deployDtoUnconfirmed(d, confirmedMs + UNCONFIRMED_AFTER_MS + 1, slow)).toBe(false);
    expect(deployDtoUnconfirmed(d, confirmedMs + 30 * 60_000 + 1, slow)).toBe(true);
  });
});
