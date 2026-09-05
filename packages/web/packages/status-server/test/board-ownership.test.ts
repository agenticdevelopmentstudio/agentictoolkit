import { describe, it, expect } from "vitest";
import {
  entryIdentity,
  matchRosterEntry,
  ownedDeployTarget,
  ownsDeployProject,
  rosterDeployProjects,
  rosterTargets,
} from "../src/board";
import type { DeployFact, RosterEntry } from "../src/board";

/**
 * THE OWNERSHIP RULE — one answer to "who owns this deploy row", shared by the fold and
 * by every surface outside it (the webhook door, the Deployments tab, the live-host stamp).
 *
 * The defect these cases pin: those surfaces used to re-ask the question by project NAME
 * while the fold answered it provider-id-first, so the first upstream RENAME made them
 * disagree — the board showed a Problem whose webhook was dropped at the door, whose rows
 * the tab refused to list, and whose `liveHost` was nulled.
 *
 * Two granularities are asserted separately because the difference is deliberate:
 * TARGET (`matchRosterEntry` / `ownedDeployTarget`) is environment-scoped for Railway;
 * PROJECT (`rosterDeployProjects` / `ownsDeployProject`) is environment-free.
 */

function entry(over: Partial<RosterEntry> = {}): RosterEntry {
  return {
    endpointId: "ep-1",
    label: "Hub",
    platform: "vercel",
    providerProjectId: null,
    projectName: "hub-web",
    environment: "production",
    isActive: true,
    monitorHttp: true,
    monitorDeploys: true,
    ignoreProjectWarning: false,
    url: "https://hub.example.com",
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
    projectName: "hub-web",
    environment: "production",
    branch: null,
    buildPhase: "failed",
    deployPhase: "none",
    createdAtMs: 1000,
    commitHash: null,
    commitMessage: null,
    commitRepo: null,
    errorText: null,
    sourceUrl: null,
    liveUrl: null,
    ...over,
  };
}

// The account mirror defaults to EMPTY, which `dropVanishedVercelProjects` reads as
// narrow-nothing — so every case below asserts the ownership rule alone, and the one
// describe block that cares passes a mirror explicitly.
const targetsOf = (roster: RosterEntry[], liveVercel: Iterable<string> = []) =>
  rosterTargets(roster, liveVercel);

describe("matchRosterEntry (identity: provider id first, name second)", () => {
  it("still resolves a project RENAMED upstream, through its provider id", () => {
    // The roster knows the project by its id and its OLD name; the provider now reports a
    // new name. Matching on name alone is what stranded the rename.
    const roster = [entry({ providerProjectId: "prj_abc", projectName: "hub-web" })];
    const index = targetsOf(roster);
    const { byId, byName } = index;
    const renamed = deploy({ providerProjectId: "prj_abc", projectName: "hub-web-v2" });

    expect(matchRosterEntry(renamed, byId, byName)?.endpointId).toBe("ep-1");
    // And the target key comes from the ENTRY, so the rename does not mint a second
    // spelling of the same target.
    // `env` is the LOGICAL TIER, read off the project NAME by `deployEnv` — so it follows the
    // rename to `hub-web-v2` while the target keeps the entry's identity. Neither is the raw
    // `environment` column, which is Vercel's promotion target and says "production" here.
    expect(ownedDeployTarget(renamed, index)).toEqual({
      owner: roster[0],
      target: "vercel|prj_abc|",
      env: "production",
    });
  });

  it("falls back to the project NAME for a platform we have not adopted ids for", () => {
    const roster = [entry({ providerProjectId: null, projectName: "hub-web" })];
    const { byId, byName } = targetsOf(roster);
    expect(matchRosterEntry(deploy(), byId, byName)?.endpointId).toBe("ep-1");
    expect(entryIdentity(roster[0]!)).toBe("hub-web");
  });

  it("prefers the id over a name that belongs to a DIFFERENT endpoint", () => {
    const roster = [
      entry({ endpointId: "by-id", providerProjectId: "prj_abc", projectName: "old-name" }),
      entry({ endpointId: "by-name", providerProjectId: null, projectName: "new-name" }),
    ];
    const { byId, byName } = targetsOf(roster);
    const row = deploy({ providerProjectId: "prj_abc", projectName: "new-name" });
    expect(matchRosterEntry(row, byId, byName)?.endpointId).toBe("by-id");
  });

  it("matches nothing when no live entry claims the project", () => {
    const index = targetsOf([entry({ projectName: "someone-else" })]);
    expect(matchRosterEntry(deploy(), index.byId, index.byName)).toBeNull();
    expect(ownedDeployTarget(deploy(), index)).toBeNull();
  });

  it("refuses the name fallback when both sides carry ids that DISAGREE", () => {
    // The name index carries id-bearing entries too (it must: rows written before
    // `learnDeployProjectIds` armed the id have only a name to match on). Without the
    // conflict test, a project renamed upstream keeps squatting its old name: entry E
    // holds `prj_A` + the stale name `web`, someone creates a NEW project also called
    // `web`, and E adopts the new project's rows — filing its failures under
    // `vercel|prj_A|`, a Problem against a project that never built, while the real
    // owner shows nothing.
    const roster = [entry({ providerProjectId: "prj_A", projectName: "web" })];
    const index = targetsOf(roster);
    const otherProject = deploy({ providerProjectId: "prj_B", projectName: "web" });
    expect(matchRosterEntry(otherProject, index.byId, index.byName)).toBeNull();
    expect(ownedDeployTarget(otherProject, index)).toBeNull();
  });

  it("still adopts a row whose id the entry has not learned yet", () => {
    // Only a CONFLICT rejects. An entry with NO id answers for a row that has one — that
    // is the pre-adoption path every platform passes through — and a row with no id still
    // matches by name.
    const roster = [entry({ providerProjectId: null, projectName: "web" })];
    const { byId, byName } = targetsOf(roster);
    expect(matchRosterEntry(deploy({ providerProjectId: "prj_B", projectName: "web" }), byId, byName)?.endpointId)
      .toBe("ep-1");
    const withId = targetsOf([entry({ providerProjectId: "prj_A", projectName: "web" })]);
    expect(matchRosterEntry(deploy({ providerProjectId: null, projectName: "web" }), withId.byId, withId.byName)
      ?.endpointId).toBe("ep-1");
  });
});

describe("Requirement A: a monitoring switch turned off removes the target from EVERY surface", () => {
  const off: [string, Partial<RosterEntry>][] = [
    ["isActive", { isActive: false }],
    ["monitorDeploys", { monitorDeploys: false }],
    ["ignoreProjectWarning", { ignoreProjectWarning: true }],
  ];

  for (const [label, over] of off) {
    it(`${label} → the entry owns neither the target nor the project`, () => {
      const roster = [entry({ providerProjectId: "prj_abc", ...over })];
      const index = targetsOf(roster);
      expect(matchRosterEntry(deploy({ providerProjectId: "prj_abc" }), index.byId, index.byName)).toBeNull();
      expect(ownedDeployTarget(deploy({ providerProjectId: "prj_abc" }), index)).toBeNull();
      // The webhook door and the Deployments tab ask the project question — the switch has
      // to reach them too, or a monitor the operator turned off keeps admitting writes.
      expect(
        ownsDeployProject(deploy({ providerProjectId: "prj_abc" }), rosterDeployProjects(roster)),
      ).toBe(false);
    });
  }
});

describe("Railway: TARGET ownership is environment-scoped, PROJECT ownership is not", () => {
  const roster = [
    entry({
      endpointId: "rw-prod",
      platform: "railway",
      projectName: "adh-backend",
      environment: "production",
    }),
  ];

  it("a deploy for a SIBLING environment does not match the production entry", () => {
    const index = targetsOf(roster);
    const staging = deploy({ platform: "railway", projectName: "adh-backend", environment: "staging" });
    expect(matchRosterEntry(staging, index.byId, index.byName)).toBeNull();
    const prod = deploy({ platform: "railway", projectName: "adh-backend", environment: "production" });
    expect(ownedDeployTarget(prod, index)?.target).toBe("railway|adh-backend|production");
  });

  it("but the PROJECT is monitored either way — the webhook door must not drop the sibling", () => {
    // `deployments.environment` for Railway is the Railway environment NAME, while the
    // endpoint's `environment` is an ADH tier. Applying the target rule at the door would
    // silently discard every Railway event whose two spellings differ.
    const projects = rosterDeployProjects(roster);
    for (const env of ["production", "staging", "pr-42", null]) {
      expect(
        ownsDeployProject({ platform: "railway", projectName: "adh-backend", environment: env }, projects),
      ).toBe(true);
    }
  });

  it("two environments of one Railway project occupy DISTINCT target keys", () => {
    const both = [
      roster[0]!,
      entry({ endpointId: "rw-stg", platform: "railway", projectName: "adh-backend", environment: "staging" }),
    ];
    const { byName } = targetsOf(both);
    expect([...byName.keys()].sort()).toEqual([
      "railway|adh-backend|production",
      "railway|adh-backend|staging",
    ]);
  });
});

describe("crunchy is owned by nobody and visible always", () => {
  // A Crunchy cluster has no HTTP host, so no roster entry can ever be wired to one.
  // Without the carve-out the fold derives no crunchy Problem and `applyBoardToLedger`
  // would resolve every open crunchy issue on its first sweep.
  it("mints a target from the row itself against an EMPTY roster", () => {
    const index = targetsOf([]);
    const row = deploy({ platform: "crunchy", projectName: "adh-pg", environment: "production" });
    // Non-Vercel, so `env` is the environment the platform itself reported.
    expect(ownedDeployTarget(row, index)).toEqual({ owner: null, target: "crunchy|adh-pg|", env: "production" });
    expect(ownsDeployProject(row, rosterDeployProjects([]))).toBe(true);
  });
});

describe("ownedDeployTarget drops what is not a deployment of a live environment", () => {
  it("a Vercel PREVIEW row (no environment) is invisible even when the project is owned", () => {
    const roster = [entry()];
    const index = targetsOf(roster);
    expect(ownedDeployTarget(deploy({ environment: null }), index)).toBeNull();
    expect(ownedDeployTarget(deploy({ environment: "" }), index)).toBeNull();
    // The Deployments tab has always LISTED preview builds, so the project gate must not
    // inherit that narrowing.
    expect(ownsDeployProject(deploy({ environment: null }), rosterDeployProjects(roster))).toBe(true);
  });

  it("a Vercel project DELETED upstream is invisible, even though a live site still wires it", () => {
    // The site is still pointed at `ghost`, so the roster owns it and every gate above
    // passes — but the project no longer exists at Vercel, so its last failed build can
    // never be superseded by a success. Serving it pins an unclearable Problem and every
    // provider retry re-opens and re-pages it. The account mirror is the only thing that
    // knows, which is why it is an argument rather than a lookup.
    const roster = [entry({ endpointId: "live", projectName: "live-project" }),
                    entry({ endpointId: "ghost", projectName: "ghost-project" })];
    const index = targetsOf(roster, ["live-project"]);

    expect(index.vanishedVercel).toEqual(new Set(["ghost-project"]));
    expect(ownedDeployTarget(deploy({ projectName: "ghost-project" }), index)).toBeNull();
    expect(ownedDeployTarget(deploy({ projectName: "live-project" }), index)?.target)
      .toBe("vercel|live-project|");
  });

  it("narrows NOTHING when the mirror is empty, or when it would delete the whole fleet", () => {
    // Both guards are `dropVanishedVercelProjects`'; asserted here because this is where
    // the fold now reads them. An unreadable account and a wiped one are indistinguishable,
    // and silencing the entire fleet is the worse of the two mistakes.
    const roster = [entry({ projectName: "hub-web" })];
    expect(targetsOf(roster, []).vanishedVercel.size).toBe(0);
    expect(targetsOf(roster, ["something-else-entirely"]).vanishedVercel.size).toBe(0);
    expect(ownedDeployTarget(deploy(), targetsOf(roster, []))?.target).toBe("vercel|hub-web|");
  });

  it("narrows by PLATFORM too — a Railway project sharing a vanished Vercel name survives", () => {
    // `vanishedVercel` is a set of NAMES, and the mirror it comes from lists Vercel
    // projects only. Checking it without the platform test would let a deleted Vercel
    // project silence a live Railway one that merely shares its name.
    const roster = [
      entry({ endpointId: "vc-live", projectName: "hub-web" }),
      entry({ endpointId: "vc-ghost", projectName: "shared-name" }),
      entry({ endpointId: "rw", platform: "railway", projectName: "shared-name" }),
    ];
    const index = targetsOf(roster, ["hub-web"]);

    expect(index.vanishedVercel).toEqual(new Set(["shared-name"]));
    expect(ownedDeployTarget(deploy({ projectName: "shared-name" }), index)).toBeNull();
    const rw = deploy({ platform: "railway", projectName: "shared-name", environment: "production" });
    expect(ownedDeployTarget(rw, index)?.target).toBe("railway|shared-name|production");
  });
});

describe("rosterDeployProjects (the project granularity)", () => {
  it("records BOTH spellings per canonical platform, and canonicalises cloudflare-pages", () => {
    const projects = rosterDeployProjects([
      entry({ providerProjectId: "prj_abc", projectName: "hub-web" }),
      entry({ endpointId: "e2", platform: "railway", projectName: "adh-backend" }),
      entry({ endpointId: "e3", platform: "cloudflare-pages", projectName: "temporal-web" }),
      entry({ endpointId: "e4", platform: "cloudflare", projectName: "temporal-admin" }),
      entry({ endpointId: "e5", platform: null, projectName: "orphan" }), // unwired → ignored
      entry({ endpointId: "e6", projectName: null }), // no project → contributes no name
    ]);

    expect([...(projects.get("vercel")?.ids ?? [])]).toEqual(["prj_abc"]);
    expect([...(projects.get("vercel")?.names ?? [])]).toEqual(["hub-web"]);
    expect([...(projects.get("railway")?.names ?? [])]).toEqual(["adh-backend"]);
    expect([...(projects.get("cloudflare")?.names ?? [])].sort()).toEqual([
      "temporal-admin",
      "temporal-web",
    ]);
    expect(projects.has("orphan")).toBe(false);
  });

  it("resolves a renamed project by id here too, so the door agrees with the board", () => {
    const projects = rosterDeployProjects([entry({ providerProjectId: "prj_abc", projectName: "hub-web" })]);
    expect(ownsDeployProject(deploy({ providerProjectId: "prj_abc", projectName: "hub-web-v2" }), projects)).toBe(true);
    // An unrelated project is still not ours — this gate is what keeps a non-site project
    // from manufacturing a phantom row.
    expect(ownsDeployProject(deploy({ projectName: "somebody-elses" }), projects)).toBe(false);
  });

  it("returns false for a platform that canonicalises to nothing", () => {
    const projects = rosterDeployProjects([entry()]);
    expect(ownsDeployProject({ platform: null, projectName: "hub-web", environment: null }, projects)).toBe(false);
  });
});
