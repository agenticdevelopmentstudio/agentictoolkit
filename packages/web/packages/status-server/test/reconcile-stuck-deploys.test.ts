import { describe, it, expect, afterEach, vi } from "vitest";
import { createClient } from "@libsql/client";
import { drizzle } from "drizzle-orm/libsql";
import { migrate } from "drizzle-orm/libsql/migrator";
import { eq } from "drizzle-orm";
import * as schema from "../src/libsql/schema";
import { deployments } from "../src/libsql/schema";
import type { Db } from "../src/libsql/client";
import {
  reconcileVanishedDeploys,
  expireUnconfirmedDeploys,
  RECONCILE_STALE_MS,
  RECONCILE_BACKOFF_BASE_MS,
  EXPIRE_UNCONFIRMED_MS,
  _resetReconcileBackoff,
} from "../src/monitor/reconcile-stuck-deploys";
import { isInFlight } from "../src/monitor/deploy-status";
import { noteRateLimited, rateLimitedUntil, _resetProviderCooldowns } from "@agentic-toolkit/deploy-platform/cooldown";
import type { ProviderConn } from "@agentic-toolkit/deploy-platform/conn";
import { MIGRATIONS_FOLDER } from '../src/libsql/client';

async function bootDb(): Promise<Db> {
  const db: Db = drizzle(createClient({ url: ":memory:" }), { schema });
  await migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });
  return db;
}

const CONN: ProviderConn = {
  vercel: { token: "v-token", teamId: "team" },
  railway: { token: "r-token" },
  cloudflare: { token: null, accountId: null },
  crunchy: { token: null },
} as unknown as ProviderConn;

const NOW = Date.now();

function row(over: Partial<typeof deployments.$inferInsert>): typeof deployments.$inferInsert {
  return {
    id: "vc_x",
    platform: "vercel",
    projectName: "olylo",
    buildPhase: "building",
    deployPhase: "none",
    environment: "production",
    createdAt: new Date(NOW - 60 * 60_000),
    fetchedAt: new Date(NOW - RECONCILE_STALE_MS - 60_000), // stale → vanished
    ...over,
  };
}

afterEach(() => {
  vi.unstubAllGlobals();
  // Both registries are module state and would otherwise leak between tests.
  _resetReconcileBackoff();
  _resetProviderCooldowns();
});

describe("isInFlight", () => {
  it("flags building/queued builds and in-progress deploys; terminal states are not in flight", () => {
    expect(isInFlight("building", "none")).toBe(true);
    expect(isInFlight("queued", "none")).toBe(true);
    expect(isInFlight("built", "deploying")).toBe(true);
    expect(isInFlight("built", "deployed")).toBe(false);
    expect(isInFlight("failed", "none")).toBe(false);
    expect(isInFlight(null, "deployed")).toBe(false);
  });
});

describe("reconcileVanishedDeploys", () => {
  it("terminalizes a vanished building Vercel deploy from its by-id state", async () => {
    const db = await bootDb();
    await db.insert(deployments).values(row({ id: "vc_gone" }));
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        Response.json({ readyState: "READY", readySubstate: "PROMOTED", target: "production" }),
      ),
    );
    await reconcileVanishedDeploys(db, CONN);
    const [after] = await db.select().from(deployments).where(eq(deployments.id, "vc_gone"));
    expect(after.buildPhase).toBe("built");
    expect(after.deployPhase).toBe("deployed");
  });

  it("leaves a FRESH in-flight row alone — the poll window still covers it", async () => {
    const db = await bootDb();
    await db.insert(deployments).values(row({ id: "vc_fresh", fetchedAt: new Date(NOW) }));
    const fetchSpy = vi.fn();
    vi.stubGlobal("fetch", fetchSpy);
    await reconcileVanishedDeploys(db, CONN);
    expect(fetchSpy).not.toHaveBeenCalled();
    const [after] = await db.select().from(deployments).where(eq(deployments.id, "vc_fresh"));
    expect(after.buildPhase).toBe("building");
  });

  it("a still-building deploy just gets its fetched_at bumped (natural backoff)", async () => {
    const db = await bootDb();
    await db.insert(deployments).values(row({ id: "vc_slow" }));
    vi.stubGlobal("fetch", vi.fn(async () => Response.json({ readyState: "BUILDING" })));
    await reconcileVanishedDeploys(db, CONN);
    const [after] = await db.select().from(deployments).where(eq(deployments.id, "vc_slow"));
    expect(after.buildPhase).toBe("building");
    expect(after.fetchedAt.getTime()).toBeGreaterThan(NOW - RECONCILE_STALE_MS);
  });

  it("a TRANSIENT by-id failure (500) leaves the row untouched for a later cycle", async () => {
    const db = await bootDb();
    const stale = row({ id: "vc_err" });
    await db.insert(deployments).values(stale);
    vi.stubGlobal("fetch", vi.fn(async () => new Response("nope", { status: 500 })));
    await reconcileVanishedDeploys(db, CONN);
    const [after] = await db.select().from(deployments).where(eq(deployments.id, "vc_err"));
    expect(after.buildPhase).toBe("building");
    // Second precision — the timestamp column stores unix seconds.
    expect(Math.floor(after.fetchedAt.getTime() / 1000)).toBe(Math.floor(stale.fetchedAt!.getTime() / 1000));
  });

  it("a provider-DELETED Vercel deploy (404) terminalizes as canceled — it must not hog the cap forever", async () => {
    const db = await bootDb();
    await db.insert(deployments).values(row({ id: "vc_deleted" }));
    vi.stubGlobal("fetch", vi.fn(async () => new Response("not found", { status: 404 })));
    await reconcileVanishedDeploys(db, CONN);
    const [after] = await db.select().from(deployments).where(eq(deployments.id, "vc_deleted"));
    expect(after.buildPhase).toBe("canceled");
    expect(after.deployPhase).toBe("none");
    expect(after.fetchedAt.getTime()).toBeGreaterThan(NOW - RECONCILE_STALE_MS);
  });

  it("a provider-DELETED Railway deployment (data.deployment null) terminalizes as canceled", async () => {
    const db = await bootDb();
    await db.insert(deployments).values(row({ id: "ry_deleted", platform: "railway" }));
    vi.stubGlobal("fetch", vi.fn(async () => Response.json({ data: { deployment: null } })));
    await reconcileVanishedDeploys(db, CONN);
    const [after] = await db.select().from(deployments).where(eq(deployments.id, "ry_deleted"));
    expect(after.buildPhase).toBe("canceled");
    expect(after.deployPhase).toBe("none");
  });

  it("a GONE deploy collapses ONLY the in-flight lifecycle: a built+deploying row keeps `built`", async () => {
    // Regression: the gone-branch used to overwrite BOTH phases to canceled/none, erasing
    // a settled build verdict when only the DEPLOY was still in flight.
    const db = await bootDb();
    await db.insert(deployments).values(
      row({ id: "vc_gone_rolling", buildPhase: "built", deployPhase: "deploying" }),
    );
    vi.stubGlobal("fetch", vi.fn(async () => new Response("not found", { status: 404 })));
    await reconcileVanishedDeploys(db, CONN);
    const [after] = await db.select().from(deployments).where(eq(deployments.id, "vc_gone_rolling"));
    expect(after.buildPhase).toBe("built"); // settled build verdict preserved
    expect(after.deployPhase).toBe("none"); // only the in-flight deploy collapsed
  });

  it("a Railway GraphQL ERROR response (no data) is transient — row untouched", async () => {
    const db = await bootDb();
    await db.insert(deployments).values(row({ id: "ry_err", platform: "railway" }));
    vi.stubGlobal("fetch", vi.fn(async () => Response.json({ errors: [{ message: "rate limited" }] })));
    await reconcileVanishedDeploys(db, CONN);
    const [after] = await db.select().from(deployments).where(eq(deployments.id, "ry_err"));
    expect(after.buildPhase).toBe("building");
  });

  it("reconciles a vanished Railway deployment via its GraphQL status", async () => {
    const db = await bootDb();
    await db.insert(deployments).values(row({ id: "ry_gone", platform: "railway" }));
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => Response.json({ data: { deployment: { status: "SUCCESS" } } })),
    );
    await reconcileVanishedDeploys(db, CONN);
    const [after] = await db.select().from(deployments).where(eq(deployments.id, "ry_gone"));
    expect(after.buildPhase).toBe("built");
    expect(after.deployPhase).toBe("deployed");
  });

  it("terminal rows are never candidates", async () => {
    const db = await bootDb();
    await db.insert(deployments).values(row({ id: "vc_done", buildPhase: "built", deployPhase: "deployed" }));
    const fetchSpy = vi.fn();
    vi.stubGlobal("fetch", fetchSpy);
    await reconcileVanishedDeploys(db, CONN);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("a failing row is PARKED after one attempt (backoff) so it can't hog the cap every tick", async () => {
    const db = await bootDb();
    await db.insert(deployments).values(row({ id: "vc_perma" }));
    const fetchSpy = vi.fn(async () => new Response("forbidden", { status: 403 }));
    vi.stubGlobal("fetch", fetchSpy);
    await reconcileVanishedDeploys(db, CONN); // fails → parks the row
    await reconcileVanishedDeploys(db, CONN); // still parked → no second fetch
    expect(fetchSpy).toHaveBeenCalledTimes(1);
    expect(RECONCILE_BACKOFF_BASE_MS).toBeGreaterThan(0);
  });

  it("a parked failing row does not starve OTHER stale rows (no head-of-line blocking)", async () => {
    const db = await bootDb();
    // The failing row is NEWER, so newest-first selection sees it first.
    await db.insert(deployments).values(row({ id: "vc_perma", createdAt: new Date(NOW - 10 * 60_000) }));
    await db.insert(deployments).values(row({ id: "vc_older", createdAt: new Date(NOW - 50 * 60_000) }));
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string) =>
        String(url).includes("perma")
          ? new Response("forbidden", { status: 403 })
          : Response.json({ readyState: "READY", readySubstate: null, target: null }),
      ),
    );
    await reconcileVanishedDeploys(db, CONN); // perma fails+parks; older heals same pass
    const [older] = await db.select().from(deployments).where(eq(deployments.id, "vc_older"));
    expect(older.buildPhase).toBe("built");
    const [perma] = await db.select().from(deployments).where(eq(deployments.id, "vc_perma"));
    expect(perma.buildPhase).toBe("building"); // untouched, parked for retry later
  });

  it("fills the per-cycle cap with failing rows, then serves an older stale row on the NEXT pass", async () => {
    const db = await bootDb();
    // MORE than the per-cycle cap (10) of NEWER failing rows. A naive newest-first cap
    // would fetch only these every tick and never reach the older row beneath them; the
    // SQL parked-id exclusion frees the cap on the next pass. (The 2-row test above can't
    // exercise this — it never fills the cap.)
    for (let i = 0; i < 12; i++) {
      await db.insert(deployments).values(row({ id: `vc_perma_${i}`, createdAt: new Date(NOW - (10 + i) * 60_000) }));
    }
    await db.insert(deployments).values(row({ id: "vc_older", createdAt: new Date(NOW - 6 * 60 * 60_000) }));
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string) =>
        String(url).includes("older")
          ? Response.json({ readyState: "READY", readySubstate: null, target: null })
          : new Response("forbidden", { status: 403 }),
      ),
    );
    // Pass 1: the cap fills with the newest failing rows; they fail and park. Older not reached.
    await reconcileVanishedDeploys(db, CONN);
    expect((await db.select().from(deployments).where(eq(deployments.id, "vc_older")))[0]!.buildPhase).toBe("building");
    // Pass 2: parked ids are excluded IN SQL, so the older row now fits the cap and heals.
    await reconcileVanishedDeploys(db, CONN);
    expect((await db.select().from(deployments).where(eq(deployments.id, "vc_older")))[0]!.buildPhase).toBe("built");
  });

  it("honors the shared provider cooldown: a throttled provider is not fetched at all", async () => {
    const db = await bootDb();
    await db.insert(deployments).values(row({ id: "vc_cooling" }));
    noteRateLimited("vercel");
    const fetchSpy = vi.fn();
    vi.stubGlobal("fetch", fetchSpy);
    await reconcileVanishedDeploys(db, CONN);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("registers a 429 in the shared cooldown instead of hammering next tick", async () => {
    const db = await bootDb();
    await db.insert(deployments).values(row({ id: "vc_429" }));
    vi.stubGlobal("fetch", vi.fn(async () => new Response("slow down", { status: 429 })));
    await reconcileVanishedDeploys(db, CONN);
    expect(rateLimitedUntil("vercel")).not.toBeNull();
    const [after] = await db.select().from(deployments).where(eq(deployments.id, "vc_429"));
    expect(after.buildPhase).toBe("building"); // untouched — retried after the cooldown
  });
});

describe("expireUnconfirmedDeploys", () => {
  const expired = new Date(NOW - EXPIRE_UNCONFIRMED_MS - 60_000);

  it("collapses an in-flight phase nothing confirmed for the expiry window to terminal `unknown`", async () => {
    const db = await bootDb();
    await db.insert(deployments).values(row({ id: "vc_zombie", fetchedAt: expired }));
    await expireUnconfirmedDeploys(db);
    const [after] = await db.select().from(deployments).where(eq(deployments.id, "vc_zombie"));
    expect(after.buildPhase).toBe("unknown");
    expect(after.deployPhase).toBe("none"); // was never in flight — untouched
    expect(isInFlight(after.buildPhase, after.deployPhase)).toBe(false);
  });

  it("collapses ONLY the in-flight lifecycle: a finished build with a wedged deploy keeps `built`", async () => {
    const db = await bootDb();
    await db.insert(deployments).values(
      row({ id: "vc_rolling", buildPhase: "built", deployPhase: "deploying", fetchedAt: expired }),
    );
    await expireUnconfirmedDeploys(db);
    const [after] = await db.select().from(deployments).where(eq(deployments.id, "vc_rolling"));
    expect(after.buildPhase).toBe("built");
    expect(after.deployPhase).toBe("unknown");
  });

  it("clears zombies OLDER than the reconcile window — the rows nothing else can ever fix", async () => {
    const db = await bootDb();
    await db.insert(deployments).values(
      row({ id: "vc_ancient", createdAt: new Date(NOW - 20 * 86_400_000), fetchedAt: expired }),
    );
    await expireUnconfirmedDeploys(db);
    const [after] = await db.select().from(deployments).where(eq(deployments.id, "vc_ancient"));
    expect(after.buildPhase).toBe("unknown");
  });

  it("leaves rows the healers are still confirming (fresh fetched_at) and terminal rows alone", async () => {
    const db = await bootDb();
    await db.insert(deployments).values(row({ id: "vc_live", fetchedAt: new Date(NOW - 60_000) }));
    await db.insert(deployments).values(
      row({ id: "vc_settled", buildPhase: "built", deployPhase: "deployed", fetchedAt: expired }),
    );
    await expireUnconfirmedDeploys(db);
    const [live] = await db.select().from(deployments).where(eq(deployments.id, "vc_live"));
    expect(live.buildPhase).toBe("building");
    const [settled] = await db.select().from(deployments).where(eq(deployments.id, "vc_settled"));
    expect(settled.buildPhase).toBe("built");
    expect(settled.deployPhase).toBe("deployed");
  });
});
