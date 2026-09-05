import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { createClient } from "@libsql/client";
import { drizzle } from "drizzle-orm/libsql";
import { migrate } from "drizzle-orm/libsql/migrator";
import * as schema from "../src/libsql/schema";
import { runIntegrationsCheck } from "../src/monitor/integrations";
import type { Db } from "../src/libsql/client";
import { MIGRATIONS_FOLDER } from '../src/libsql/client';
import { testConfig } from "./helpers/config";

// The telemetry providers configured; the deploy providers UNSET so the ONLY
// outbound fetches this test makes are the GlitchTip + PostHog reachability probes.
const TELEMETRY_ENV: Record<string, string> = {
  GLITCHTIP_URL: "https://errors.example.com",
  GLITCHTIP_API_TOKEN: "gt-token",
  GLITCHTIP_ORG: "acme",
  POSTHOG_HOST: "https://ph.example.com",
  POSTHOG_API_KEY: "ph-key",
  POSTHOG_PROJECT_ID: "42",
};
const PROVIDER_ENV = ["VERCEL_API_TOKEN", "VERCEL_TEAM_ID", "CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID", "RAILWAY_API_TOKEN"];

async function bootDb(): Promise<Db> {
  const db: Db = drizzle(createClient({ url: ":memory:" }), { schema });
  await migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });
  return db;
}

describe("runIntegrationsCheck — telemetry providers (GlitchTip / PostHog)", () => {
  const saved: Record<string, string | undefined> = {};
  const keys = [...PROVIDER_ENV, ...Object.keys(TELEMETRY_ENV)];
  beforeEach(() => {
    for (const k of keys) saved[k] = process.env[k];
    for (const k of PROVIDER_ENV) delete process.env[k];
    for (const [k, v] of Object.entries(TELEMETRY_ENV)) process.env[k] = v;
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    for (const k of keys) {
      if (saved[k] === undefined) delete process.env[k];
      else process.env[k] = saved[k];
    }
  });

  function stub(handler: (url: string) => Response): void {
    vi.stubGlobal("fetch", vi.fn(async (input: string | URL | Request) => handler(typeof input === "string" ? input : input.toString())));
  }

  it("reports both reachable (ok) on a 200 from the authed probe", async () => {
    stub(() => new Response("{}", { status: 200 }));
    const db = await bootDb();
    const { checks } = await runIntegrationsCheck(db, testConfig());
    const by = (id: string) => checks.find((c) => c.id === id);
    expect(by("glitchtip")?.state).toBe("ok");
    expect(by("glitchtip")?.detail).toBe("reachable");
    expect(by("posthog")?.state).toBe("ok");
    expect(by("posthog")?.detail).toBe("reachable");
  });

  it("probes GlitchTip org-metadata (not the heavy issues query) and PostHog's real query API", async () => {
    const urls: string[] = [];
    stub((url) => {
      urls.push(url);
      return new Response("{}", { status: 200 });
    });
    const db = await bootDb();
    await runIntegrationsCheck(db, testConfig());
    // GlitchTip: cheap org metadata, not /issues/. PostHog: the SAME query API the
    // analytics band uses (the personal key 403s on project-metadata), not /projects/42/.
    expect(urls).toContain("https://errors.example.com/api/0/organizations/acme/");
    expect(urls).toContain("https://ph.example.com/api/projects/42/query/");
  });

  it("marks a provider error (red) on a 401 — an invalid token/key surfaces immediately", async () => {
    stub((url) => (url.includes("errors.example.com") ? new Response("nope", { status: 401 }) : new Response("{}", { status: 200 })));
    const db = await bootDb();
    const { checks } = await runIntegrationsCheck(db, testConfig());
    const by = (id: string) => checks.find((c) => c.id === id);
    expect(by("glitchtip")?.state).toBe("error");
    expect(by("glitchtip")?.detail).toContain("token invalid");
    expect(by("posthog")?.state).toBe("ok");
  });
});
