import { describe, it, expect } from "vitest";
import { deriveBoard } from "../src/board/derive";
import {
  ERROR_JUDGED_LEVELS,
  ERROR_RECENT_MS,
  errorProblems,
  errorsTarget,
  monitoredTargets,
  parseErrorsTarget,
} from "../src/board/derive-problems";
import type { BoardFacts, ErrorFact, IssueEvent, PlatformFact } from "../src/board/types";

// The GlitchTip rule: application errors as Problems. Pure unit tests, because
// `errorProblems` is pure — `nowMs` is a parameter and there is no IO.
//
// What this rule is FOR is the one thing no other rule on this board can see: code that is
// broken while its host is perfectly reachable. Every other signal here asks whether a
// thing RESPONDS. So the tests that matter are the ones about what it declines to judge —
// a rule that says "red" for every diagnostic GlitchTip ever grouped is a rule that gets
// the board ignored, which costs more than the signal is worth.

const NOW = Date.parse("2026-08-18T12:00:00.000Z");

function err(over: Partial<ErrorFact> = {}): ErrorFact {
  return {
    issueKey: "gt-1",
    project: "adh",
    title: "TypeError: undefined is not a function",
    culprit: "app/page.tsx",
    level: "error",
    count: 7,
    userCount: 3,
    firstSeenMs: NOW - 6 * 3600_000,
    lastSeenMs: NOW - 60_000,
    permalink: "https://glitchtip.example/issues/1",
    ...over,
  };
}

function facts(over: Partial<BoardFacts> = {}): BoardFacts {
  return {
    roster: [], probeIntervalMs: 60_000, deploys: [], inFlightDeploys: [], deployEvents: [],
    endpoints: [], platforms: [], staleProd: [], ledger: [], issueEvents: [],
    liveVercelProjects: [],
    errors: [], errorsConfigured: true, errorProjectAllowlist: null,
    ...over,
  };
}

describe("errorProblems — what it judges", () => {
  it("opens ONE problem per GlitchTip project, whatever the issue count", () => {
    const p = errorProblems(
      facts({ errors: [err({ issueKey: "a" }), err({ issueKey: "b" }), err({ issueKey: "c" })] }),
      NOW,
    );
    expect(p).toHaveLength(1);
    expect(p[0]).toMatchObject({ target: "errors|adh", source: "glitchtip", name: "adh", state: "erroring" });
    expect(p[0]!.detail).toContain("3 unresolved errors");
  });

  it("separates projects, one row each", () => {
    const p = errorProblems(
      facts({ errors: [err({ issueKey: "a", project: "adh" }), err({ issueKey: "b", project: "games" })] }),
      NOW,
    );
    expect(p.map((x) => x.target).sort()).toEqual(["errors|adh", "errors|games"]);
  });

  it("says 'error' singular for one", () => {
    expect(errorProblems(facts({ errors: [err()] }), NOW)[0]!.detail).toContain("1 unresolved error ");
  });

  // A null level means "we do not know how bad this is", which must not read as "bad".
  it.each([["warning"], ["info"], ["debug"], ["notice"]])("ignores level %s", (level) => {
    expect(errorProblems(facts({ errors: [err({ level })] }), NOW)).toEqual([]);
  });

  it("ignores an issue with no level at all", () => {
    expect(errorProblems(facts({ errors: [err({ level: null })] }), NOW)).toEqual([]);
  });

  it("judges error and fatal, case-insensitively", () => {
    for (const level of ["error", "ERROR", "Fatal"]) {
      expect(errorProblems(facts({ errors: [err({ level })] }), NOW)).toHaveLength(1);
    }
    expect([...ERROR_JUDGED_LEVELS]).toEqual(["error", "fatal"]);
  });

  // Without the recency gate the rule reads GlitchTip's BACKLOG rather than the fleet's
  // health: an issue nobody clicked "resolve" on in March is still `is:unresolved` today.
  it("ignores an issue that has not fired inside the recency window", () => {
    const stale = err({ lastSeenMs: NOW - ERROR_RECENT_MS - 1 });
    expect(errorProblems(facts({ errors: [stale] }), NOW)).toEqual([]);
  });

  it("judges an issue that fired exactly at the window edge", () => {
    const edge = err({ lastSeenMs: NOW - ERROR_RECENT_MS });
    expect(errorProblems(facts({ errors: [edge] }), NOW)).toHaveLength(1);
  });

  it("ignores an issue with no lastSeen — it cannot show it is current", () => {
    expect(errorProblems(facts({ errors: [err({ lastSeenMs: null })] }), NOW)).toEqual([]);
  });

  it("drops the whole project when every one of its issues is filtered out", () => {
    const facts_ = facts({ errors: [err({ level: "warning" }), err({ issueKey: "b", lastSeenMs: null })] });
    expect(errorProblems(facts_, NOW)).toEqual([]);
  });
});

describe("errorProblems — severity", () => {
  it("is minor for ordinary errors: the site is serving", () => {
    expect(errorProblems(facts({ errors: [err()] }), NOW)[0]!.severity).toBe("minor");
  });

  it("is major when any issue in the project is fatal", () => {
    const p = errorProblems(facts({ errors: [err({ issueKey: "a" }), err({ issueKey: "b", level: "fatal" })] }), NOW);
    expect(p[0]!.severity).toBe("major");
  });

  // `indicatorFor` maps critical → "outage". An app throwing is not the fleet being down,
  // and this rule must never be able to say it is.
  it("is never critical, so it can never take the board to outage", () => {
    const board = deriveBoard(facts({ errors: [err({ level: "fatal", count: 10_000 })] }), NOW);
    expect(board.problems.every((p) => p.severity !== "critical")).toBe(true);
    expect(board.indicator).toBe("degraded");
  });
});

describe("errorProblems — the headline and the error block", () => {
  it("shows the highest-count issue's title and links its permalink", () => {
    const p = errorProblems(
      facts({
        errors: [
          err({ issueKey: "a", count: 3, title: "quiet one", permalink: "https://gt/a" }),
          err({ issueKey: "b", count: 900, title: "the loud one", permalink: "https://gt/b" }),
        ],
      }),
      NOW,
    );
    expect(p[0]!.detail).toContain("the loud one");
    expect(p[0]!.sourceUrl).toBe("https://gt/b");
  });

  // A winner that flapped between two equally-frequent issues would rewrite the ledger row
  // and republish the board every cycle, forever — `applyBoardToLedger` rewrites detail and
  // sourceUrl on every pass. The tie-break is what stops that.
  it("breaks a count tie on issueKey, in either input order", () => {
    const a = err({ issueKey: "aaa", count: 5, title: "A" });
    const b = err({ issueKey: "bbb", count: 5, title: "B" });
    expect(errorProblems(facts({ errors: [a, b] }), NOW)[0]!.detail).toContain("A");
    expect(errorProblems(facts({ errors: [b, a] }), NOW)[0]!.detail).toContain("A");
  });

  it("puts the worst five in errorText, worst first, and no more than five", () => {
    const errors = [10, 50, 30, 40, 20, 5, 1].map((count, i) =>
      err({ issueKey: `k${i}`, count, title: `t${count}` }),
    );
    const lines = errorProblems(facts({ errors }), NOW)[0]!.errorText!.split("\n");
    expect(lines).toHaveLength(5);
    expect(lines[0]).toBe("50× t50");
    expect(lines[4]).toBe("10× t10");
  });

  it("clips a runaway title instead of pasting a stack trace into the row", () => {
    const long = "E".repeat(500);
    const detail = errorProblems(facts({ errors: [err({ title: long })] }), NOW)[0]!.detail!;
    expect(detail.length).toBeLessThan(200);
    expect(detail).toContain("…");
  });

  it("carries no deploy metadata — a grouped issue has no commit and no branch", () => {
    expect(errorProblems(facts({ errors: [err()] }), NOW)[0]).toMatchObject({
      branch: null, commitHash: null, commitMessage: null, commitRepo: null,
      environment: null, statusCode: null, liveUrl: null,
    });
  });
});

describe("errorProblems — onset", () => {
  it("dates the problem from the earliest first-seen still counted", () => {
    const old = NOW - 20 * 3600_000;
    const p = errorProblems(
      facts({ errors: [err({ issueKey: "a", firstSeenMs: NOW - 3600_000 }), err({ issueKey: "b", firstSeenMs: old })] }),
      NOW,
    );
    expect(p[0]!.since).toBe(new Date(old).toISOString());
  });

  it("prefers the ledger's onset when it is older, so the problem ages instead of resetting", () => {
    const ledgerOnset = NOW - 72 * 3600_000;
    const p = errorProblems(
      facts({
        errors: [err()],
        ledger: [{ target: "errors|adh", openedAtMs: ledgerOnset }],
      }),
      NOW,
    );
    expect(p[0]!.since).toBe(new Date(ledgerOnset).toISOString());
  });

  it("falls back to now when nothing carries a first-seen", () => {
    const p = errorProblems(facts({ errors: [err({ firstSeenMs: null })] }), NOW);
    expect(p[0]!.since).toBe(new Date(NOW).toISOString());
  });
});

describe("errorProblems — the configuration gate", () => {
  // `collectTelemetry` skips the poll entirely when GlitchTip is unconfigured, so the rows
  // FREEZE rather than emptying. Judging them would pin a Problem open that nothing left in
  // the system could ever close.
  it("judges nothing when GlitchTip is not configured", () => {
    expect(errorProblems(facts({ errors: [err()], errorsConfigured: false }), NOW)).toEqual([]);
  });

  it("drops the watch set at the same moment, so the frozen row closes silently", () => {
    const f = facts({
      errors: [err()],
      ledger: [{ target: "errors|adh", openedAtMs: NOW - 3600_000 }],
      errorsConfigured: false,
    });
    expect(monitoredTargets(f)).not.toContain("errors|adh");
  });
});

describe("errorProblems — the watch set", () => {
  const open = (target: string) => ({ target, openedAtMs: NOW - 3600_000 });

  it("watches a project that is erroring right now", () => {
    expect(monitoredTargets(facts({ errors: [err()] }))).toContain("errors|adh");
  });

  // THE case the watch set exists for. A target missing from `monitoredTargets` closes as
  // `unmonitored`, which never alerts — so if the set were only "what is erroring now", the
  // errors CLEARING would be the one outcome on-call never heard about. The open ledger row
  // is still present on the cycle that closes it (`applyBoardToLedger` runs after the fold),
  // and that is what keeps the target watched exactly long enough to close as `recovered`.
  it("watches a project whose errors have all cleared, so recovery alerts", () => {
    const f = facts({ errors: [], ledger: [open("errors|adh")] });
    expect(errorProblems(f, NOW)).toEqual([]);
    expect(monitoredTargets(f)).toContain("errors|adh");
  });

  it("watches a project whose only issues were filtered out as warnings", () => {
    const f = facts({ errors: [err({ level: "warning" })], ledger: [open("errors|adh")] });
    expect(errorProblems(f, NOW)).toEqual([]);
    expect(monitoredTargets(f)).toContain("errors|adh");
  });

  // The set is the two sources UNIONED, never the ledger alone: a project erroring for the
  // first time has no ledger row yet, and its brand-new issue must not be born unmonitored.
  it("watches both the erroring projects and the open rows at once", () => {
    const f = facts({ errors: [err({ project: "games" })], ledger: [open("errors|adh")] });
    expect(monitoredTargets(f)).toContain("errors|games");
    expect(monitoredTargets(f)).toContain("errors|adh");
  });

  // Once the row is CLOSED it leaves `facts.ledger` (which is `resolved_at is null`), and a
  // project that stopped erroring stops being watched. That is the point of reading the open
  // rows rather than every project the errors table has ever held: the set stays bounded.
  it("stops watching a project once its row is closed and its errors are gone", () => {
    expect(monitoredTargets(facts())).not.toContain("errors|adh");
  });

  // `monitoredTargets` is walked for EVERY open ledger row, so it must not mistake a deploy
  // or endpoint target for an error one — claiming it here would be harmless, but the same
  // parse decides `issueKind`, and there it would mislabel the Activity row.
  it("claims only error targets out of the open ledger", () => {
    const f = facts({ ledger: [open("vercel|prj_0aB|"), open("ep-1"), open("platform-health|vercel")] });
    expect(monitoredTargets(f).filter((t) => t.startsWith("errors|"))).toEqual([]);
  });
});

describe("the errors target spelling", () => {
  it("round-trips", () => {
    expect(errorsTarget("adh")).toBe("errors|adh");
    expect(parseErrorsTarget(errorsTarget("adh"))).toBe("adh");
  });

  // The ledger permits exactly ONE open row per target (`uniq_open_issue_per_target`), so
  // an error target that could collide with a site's own outage row would mean one of the
  // two silently losing its insert — and which one won would depend on fold order.
  it.each([
    ["ep-1"],                          // a bare endpoint id
    ["vercel|prj_0aB|"],               // a deploy target
    ["railway|adh-backend|production"],
    ["platform-health|vercel"],
    [""],
  ])("does not claim %s", (target) => {
    expect(parseErrorsTarget(target)).toBeNull();
  });
});

describe("deriveBoard folds the rule in", () => {
  it("puts an error problem on the board next to the others, not instead of them", () => {
    const board = deriveBoard(facts({ errors: [err()] }), NOW);
    expect(board.problems.map((p) => p.target)).toContain("errors|adh");
    expect(board.monitoredTargets).toContain("errors|adh");
    expect(board.indicator).toBe("degraded");
  });

  // The board is pure by construction and the suite pins it — a rule that sorted
  // non-deterministically would break every deep-equal assertion downstream.
  it("is deep-equal for the same facts", () => {
    const f = facts({
      errors: [err({ issueKey: "a", count: 5 }), err({ issueKey: "b", count: 5 }), err({ issueKey: "c", project: "games" })],
    });
    expect(deriveBoard(f, NOW)).toEqual(deriveBoard(f, NOW));
  });

  it("emits no error rows at all when GlitchTip is unconfigured", () => {
    const board = deriveBoard(facts({ errors: [err()], errorsConfigured: false }), NOW);
    expect(board.problems).toEqual([]);
    expect(board.monitoredTargets).not.toContain("errors|adh");
    expect(board.indicator).toBe("operational");
  });
});

describe("an error issue event in Recent Activity", () => {
  function event(over: Partial<IssueEvent> = {}): IssueEvent {
    return {
      id: 1, target: "errors|adh", source: "glitchtip", name: "adh", environment: null,
      state: "erroring", severity: "minor", detail: "4 unresolved errors · boom",
      sourceUrl: "https://gt/1", liveUrl: null,
      commitHash: null, commitMessage: null, commitRepo: null,
      openedAtMs: NOW - 3600_000, resolvedAtMs: null, resolvedReason: null, ...over,
    };
  }

  // `issueKind`'s last branch is a catch-all, not a default: anything it has not been
  // taught falls into "deploy". `deployCounts` (web/src/lib/overview.ts) then tallies
  // `kind === "deploy" && tone === "bad"` into the FAILED-BUILDS KPI — so an unread error
  // event would report a GlitchTip issue as a broken build on the overview strip.
  it("is a platform row, never a deploy row", () => {
    const rows = deriveBoard(facts({ issueEvents: [event()] }), NOW).activity;
    const row = rows.find((r) => r.target === "errors|adh");
    expect(row?.kind).toBe("platform");
  });

  it("speaks the same word the Problems pane does", () => {
    const rows = deriveBoard(facts({ issueEvents: [event()] }), NOW).activity;
    expect(rows.find((r) => r.target === "errors|adh")?.verb).toBe("app errors");
  });

  it("records the recovery", () => {
    const rows = deriveBoard(
      facts({ issueEvents: [event({ resolvedAtMs: NOW - 60_000, resolvedReason: "recovered" })] }),
      NOW,
    ).activity;
    const resolved = rows.find((r) => r.verb.includes("resolved"));
    expect(resolved).toMatchObject({ kind: "platform", tone: "good", verb: "[app errors] resolved" });
  });
});


describe("errorProblems — the ownership gate", () => {
  // Every OTHER rule on this board is gated by ownership: `issue-sources.ts` says it
  // outright — a project no site monitors is never enumerated, so it can never mint a
  // Problem. Errors have no site to hang that on, because the poll is ORGANIZATION-wide
  // (`/api/0/organizations/<org>/issues/`). `GLITCHTIP_PROJECTS` is the substitute gate.
  it("judges only the allowlisted projects when an allowlist is set", () => {
    const p = errorProblems(
      facts({
        errors: [err({ issueKey: "a", project: "adh" }), err({ issueKey: "b", project: "someones-scratch-app" })],
        errorProjectAllowlist: ["adh"],
      }),
      NOW,
    );
    expect(p.map((x) => x.target)).toEqual(["errors|adh"]);
  });

  it("judges every project when no allowlist is set", () => {
    const p = errorProblems(
      facts({ errors: [err({ issueKey: "a", project: "adh" }), err({ issueKey: "b", project: "games" })] }),
      NOW,
    );
    expect(p.map((x) => x.target).sort()).toEqual(["errors|adh", "errors|games"]);
  });

  // The two halves must agree EXACTLY. A project the fold refuses to judge but still
  // watches has an open row nothing can ever close; one it judges but does not watch
  // closes as `unmonitored` — the silent close — while it is still erroring.
  it("keeps the watch set and the judgement on the same projects", () => {
    const f = facts({
      errors: [err({ issueKey: "a", project: "adh" }), err({ issueKey: "b", project: "scratch" })],
      errorProjectAllowlist: ["adh"],
    });
    const watched = monitoredTargets(f).filter((t) => t.startsWith("errors|"));
    expect(watched).toEqual(["errors|adh"]);
    expect(errorProblems(f, NOW).map((x) => x.target)).toEqual(watched);
  });

  // An open row for a project that has just been REMOVED from the allowlist still has to
  // be closable — it comes off the ledger, not off the errors list.
  it("still watches an open row whose project has left the allowlist", () => {
    const f = facts({
      errors: [err({ project: "scratch" })],
      ledger: [{ target: "errors|scratch", openedAtMs: NOW - 3600_000 }],
      errorProjectAllowlist: ["adh"],
    });
    expect(errorProblems(f, NOW)).toEqual([]);
    expect(monitoredTargets(f)).toContain("errors|scratch");
  });
});

describe("errorProblems — the onset it reports", () => {
  // GlitchTip's `firstSeen` is ALL-TIME, and `upsert` never refreshes it. A low-frequency
  // exception first seen months ago that is still unresolved would date TODAY's incident to
  // then — and `byRecency` sorts oldest-first, so that row would pin itself above a real
  // outage two minutes old and tell every reader the fleet has been degraded for months.
  it("never reports an onset older than the window it judges by", () => {
    const p = errorProblems(
      facts({ errors: [err({ firstSeenMs: NOW - 400 * 24 * 3600_000, lastSeenMs: NOW - 60_000 })] }),
      NOW,
    );
    expect(Date.parse(p[0]!.since!)).toBe(NOW - ERROR_RECENT_MS);
  });

  it("reports a real onset INSIDE the window unchanged", () => {
    const onsetMs = NOW - 3 * 3600_000;
    const p = errorProblems(facts({ errors: [err({ firstSeenMs: onsetMs })] }), NOW);
    expect(p[0]!.since).toBe(new Date(onsetMs).toISOString());
  });
});

describe("errorProblems — when GlitchTip itself is unreachable", () => {
  const gt = (over: Partial<PlatformFact> = {}): PlatformFact => ({
    source: "glitchtip", configured: true, ok: false, streak: 5, sampledAtMs: NOW - 60_000, ...over,
  });
  // Stale by the recency rule: nothing has refreshed it because nothing could.
  const stale = () => err({ lastSeenMs: NOW - ERROR_RECENT_MS - 60_000 });

  // A failed poll persists NOTHING, so from the `errors` table alone an outage looks
  // exactly like a fleet that stopped erroring: every `lastSeen` just stops advancing.
  // Left alone, the recency rule would drop every row a day later, `errorProblems` would
  // return nothing, and `applyBoardToLedger` would close the row as `recovered` — an
  // all-clear for errors nobody has been able to observe since yesterday.
  it("freezes the rows instead of expiring them into a false recovery", () => {
    const p = errorProblems(facts({ errors: [stale()], platforms: [gt()] }), NOW);
    expect(p.map((x) => x.target)).toEqual(["errors|adh"]);
  });

  it("expires them normally once GlitchTip is reachable again", () => {
    expect(errorProblems(facts({ errors: [stale()], platforms: [gt({ ok: true })] }), NOW)).toEqual([]);
  });

  it("expires them when GlitchTip has no observation row at all", () => {
    expect(errorProblems(facts({ errors: [stale()], platforms: [] }), NOW)).toEqual([]);
  });

  // The freeze suspends RECENCY, never the level filter — a frozen warning is still a
  // warning, and the rule's whole claim is that it judges errors.
  it("still refuses a warning while frozen", () => {
    const f = facts({ errors: [stale(), err({ issueKey: "w", level: "warning" })], platforms: [gt()] });
    expect(errorProblems(f, NOW)[0]!.detail).toContain("1 unresolved error");
  });

  // An UNCONFIGURED GlitchTip is not an unreachable one — `errorsConfigured` already
  // silences the rule, and a stale `configured:false` row must not pin anything open.
  it("does not freeze on an unconfigured observation row", () => {
    const f = facts({ errors: [stale()], platforms: [gt({ configured: false })] });
    expect(errorProblems(f, NOW)).toEqual([]);
  });
});

describe("the errors target spelling — a project that is not a slug", () => {
  // `glitchtip.ts` falls back from the project's `slug` to its free-form `name`, so the
  // segment is NOT safe by construction. An unescaped separator would mint a target that
  // parses back into a different string: the fold would re-derive a key that never matches
  // the ledger row it just wrote, opening a fresh row every cycle against
  // `uniq_open_issue_per_target` and never being able to close the old one.
  it.each([
    ["adh|prod"],
    ["a|b|c"],
    ["Some Team's App"],
  ])("round-trips %s", (project) => {
    expect(parseErrorsTarget(errorsTarget(project))).toBe(project);
  });

  it("cannot be confused with a deploy target by escaping alone", () => {
    expect(parseErrorsTarget("vercel|prj_0aB|")).toBeNull();
  });

  it("keeps the fold and the watch set on ONE key for such a project", () => {
    const f = facts({ errors: [err({ project: "adh|prod" })] });
    const target = errorProblems(f, NOW)[0]!.target;
    expect(monitoredTargets(f)).toContain(target);
  });
});

describe("errorProblems — order independence", () => {
  // The deep-equal test above feeds the SAME array twice, so it cannot see a tie-break
  // that depends on input order. `facts.errors` arrives ordered by `last_seen` at SECOND
  // resolution, so a burst genuinely can arrive in either order — and the top issue picks
  // the headline, so an order-dependent tie-break would flip the detail (and with it the
  // ledger row and every SSE repaint) with nothing upstream having changed.
  it("picks the same top issue whichever way the tied set arrives", () => {
    const errs = [
      err({ issueKey: "a", count: 9, title: "A boom" }),
      err({ issueKey: "b", count: 9, title: "B boom" }),
      err({ issueKey: "c", count: 9, title: "C boom" }),
    ];
    const forward = errorProblems(facts({ errors: errs }), NOW);
    const reversed = errorProblems(facts({ errors: [...errs].reverse() }), NOW);
    expect(reversed).toEqual(forward);
  });
});

describe("an error incident keeps its trail in Recent Activity", () => {
  // Error targets are the only kind whose watch-set membership is EPHEMERAL: endpoint,
  // deploy and platform-health targets are re-derived from the roster and config every
  // cycle, so they are watched whether or not anything is wrong. An error target is
  // derived from what is erroring NOW plus what is open in the ledger — and one cycle
  // after the row closed, both are gone. `deriveActivity` drops any event whose target is
  // not watched, so the whole incident would vanish from the feed the moment it ended.
  it("watches a closed incident's target for as long as its events are in the window", () => {
    const f = facts({
      issueEvents: [
        {
          id: 1, target: "errors|adh", source: "glitchtip", name: "adh", environment: null,
          state: "erroring", severity: "minor", detail: "4 unresolved errors",
          sourceUrl: null, liveUrl: null, commitHash: null, commitMessage: null, commitRepo: null,
          openedAtMs: NOW - 3600_000, resolvedAtMs: NOW - 60_000, resolvedReason: "recovered",
        },
      ],
    });
    expect(monitoredTargets(f)).toContain("errors|adh");
    const rows = deriveBoard(f, NOW).activity.filter((r) => r.target === "errors|adh");
    expect(rows.map((r) => r.verb)).toContain("[app errors] resolved");
  });

  // Additive only — it must not resurrect the JUDGEMENT, or a project that recovered
  // would re-open every cycle for as long as its event stayed in the window.
  it("mints no problem from an event alone", () => {
    const f = facts({
      issueEvents: [
        {
          id: 1, target: "errors|adh", source: "glitchtip", name: "adh", environment: null,
          state: "erroring", severity: "minor", detail: "4 unresolved errors",
          sourceUrl: null, liveUrl: null, commitHash: null, commitMessage: null, commitRepo: null,
          openedAtMs: NOW - 3600_000, resolvedAtMs: NOW - 60_000, resolvedReason: "recovered",
        },
      ],
    });
    expect(errorProblems(f, NOW)).toEqual([]);
  });
});
