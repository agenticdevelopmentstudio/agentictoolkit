import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { runIntegrationsCheck } from "../src/monitor/integrations";
import { _resetCfAccountCache } from "@agentic-toolkit/deploy-platform/providers";
import { freshDb as bootDb } from "./helpers/db";
import { testConfig } from "./helpers/config";

// Provider env vars the monitor expects. With none set, the provider checks return
// BEFORE any network call, so this test is deterministic and offline.
const PROVIDER_ENV = [
  "VERCEL_API_TOKEN",
  "VERCEL_TEAM_ID",
  "CLOUDFLARE_API_TOKEN",
  "CLOUDFLARE_ACCOUNT_ID",
  "RAILWAY_API_TOKEN",
  // Telemetry providers — unset so their checks take the missing-env (warn) path
  // BEFORE any network call, keeping this test offline+deterministic.
  "GLITCHTIP_URL",
  "GLITCHTIP_API_TOKEN",
  "GLITCHTIP_ORG",
  "POSTHOG_HOST",
  "POSTHOG_API_KEY",
  "POSTHOG_PROJECT_ID",
];

describe("runIntegrationsCheck — missing expected env", () => {
  const saved: Record<string, string | undefined> = {};
  beforeEach(() => {
    for (const k of PROVIDER_ENV) {
      saved[k] = process.env[k];
      delete process.env[k];
    }
    // This test asserts the provider checks return BEFORE any network call. Guard that
    // invariant: if a refactor makes a check fetch (e.g. with the dummy token), fail
    // loudly here instead of hitting the real Cloudflare/Vercel/Railway API in CI.
    vi.stubGlobal("fetch", () => {
      throw new Error("no network expected in the missing-env path");
    });
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    _resetCfAccountCache();
    for (const k of PROVIDER_ENV) {
      if (saved[k] === undefined) delete process.env[k];
      else process.env[k] = saved[k];
    }
  });

  it("names each provider's missing token by exact env var", async () => {
    const db = await bootDb();
    const { checks } = await runIntegrationsCheck(db, testConfig());
    const by = (id: string) => checks.find((c) => c.id === id);
    expect(by("vercel")?.missingEnv).toEqual(["VERCEL_API_TOKEN"]);
    expect(by("cloudflare")?.missingEnv).toEqual(["CLOUDFLARE_API_TOKEN"]);
    expect(by("railway")?.missingEnv).toEqual(["RAILWAY_API_TOKEN"]);
    expect(by("glitchtip")?.missingEnv).toEqual(["GLITCHTIP_URL", "GLITCHTIP_API_TOKEN", "GLITCHTIP_ORG"]);
    expect(by("glitchtip")?.state).toBe("warn");
    expect(by("posthog")?.missingEnv).toEqual(["POSTHOG_HOST", "POSTHOG_API_KEY", "POSTHOG_PROJECT_ID"]);
    expect(by("posthog")?.state).toBe("warn");
  });

  it("errors (red) when the account is neither set nor auto-discoverable", async () => {
    // Token set, no account id, and discovery fails (fetch is stubbed to throw) — this
    // is genuinely broken, so it's an error, not a soft warning.
    process.env.CLOUDFLARE_API_TOKEN = "dummy-token";
    const db = await bootDb();
    const { checks } = await runIntegrationsCheck(db, testConfig());
    const cf = checks.find((c) => c.id === "cloudflare");
    expect(cf?.missingEnv).toEqual(["CLOUDFLARE_ACCOUNT_ID"]);
    expect(cf?.state).toBe("error");
    expect(cf?.detail).toBe("CLOUDFLARE_ACCOUNT_ID not set and could not auto-discover");
  });

  it("warns (amber, recoverable) when the account auto-discovers from the token", async () => {
    // Token set, no account id, but discovery succeeds (one account) and workers/scripts
    // is reachable — wiring works, so it's a pin-it warning, not a red error.
    process.env.CLOUDFLARE_API_TOKEN = "dummy-token";
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string) =>
        url.includes("/accounts?")
          ? Response.json({ success: true, result: [{ id: "sole-acct" }] })
          : Response.json({ success: true, result: [{ id: "w1" }, { id: "w2" }] }),
      ),
    );
    const db = await bootDb();
    const { checks } = await runIntegrationsCheck(db, testConfig());
    const cf = checks.find((c) => c.id === "cloudflare");
    expect(cf?.state).toBe("warn");
    expect(cf?.ok).toBe(true);
    expect(cf?.missingEnv).toEqual(["CLOUDFLARE_ACCOUNT_ID"]);
    expect(cf?.detail).toContain("auto-discovered");
  });

  it("omits missingEnv on checks that have nothing missing (stats store)", async () => {
    const db = await bootDb();
    const { checks } = await runIntegrationsCheck(db, testConfig());
    expect(checks.find((c) => c.id === "stats")?.missingEnv).toBeUndefined();
  });
});
