import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { runIntegrationsCheck, _resetSelfCheckStability } from "../src/monitor/integrations";
import { CONFIRM_WINDOW_MS } from "../src/monitor/self-check-stability";
import { _resetCfAccountCache } from "@agentic-toolkit/deploy-platform/providers";
import { freshDb as bootDb } from "./helpers/db";
import { testConfig } from "./helpers/config";

// Provider env so every check is "configured" and proceeds to its outbound probe.
// CLOUDFLARE_ACCOUNT_ID is set so account resolution short-circuits with NO network
// (see resolveCfAccountId) — the only fetches are the ones these tests stub.
const PROVIDER_ENV = [
  "VERCEL_API_TOKEN",
  "VERCEL_TEAM_ID",
  "CLOUDFLARE_API_TOKEN",
  "CLOUDFLARE_ACCOUNT_ID",
  "RAILWAY_API_TOKEN",
];

// Telemetry providers stay UNSET here so their checks take the no-network warn
// path — otherwise a GlitchTip/PostHog fetch would fall through to the stub's
// railway branch and skew the retry accounting.
const TELEMETRY_ENV = [
  "GLITCHTIP_URL",
  "GLITCHTIP_API_TOKEN",
  "GLITCHTIP_ORG",
  "POSTHOG_HOST",
  "POSTHOG_API_KEY",
  "POSTHOG_PROJECT_ID",
];

/** The exact shape Node's fetch throws when our 6s AbortController fires. */
function abortError(): Error {
  const e = new Error("This operation was aborted");
  e.name = "AbortError";
  return e;
}

function host(url: string): "v" | "c" | "r" {
  if (url.includes("api.vercel.com")) return "v";
  if (url.includes("api.cloudflare.com")) return "c";
  return "r"; // backboard.railway.app
}

function okResponse(url: string): Response {
  const h = host(url);
  if (h === "v") return new Response(JSON.stringify({ user: {} }), { status: 200 });
  if (h === "c") return Response.json({ success: true, result: [{ id: "w1" }] });
  return Response.json({ data: { projects: { edges: [] } } });
}

describe("runIntegrationsCheck — transient blips retry before going red", () => {
  const saved: Record<string, string | undefined> = {};
  beforeEach(() => {
    for (const k of [...PROVIDER_ENV, ...TELEMETRY_ENV]) saved[k] = process.env[k];
    for (const k of TELEMETRY_ENV) delete process.env[k];
    process.env.VERCEL_API_TOKEN = "v-token";
    process.env.VERCEL_TEAM_ID = "team";
    process.env.CLOUDFLARE_API_TOKEN = "cf-token";
    process.env.CLOUDFLARE_ACCOUNT_ID = "acct";
    process.env.RAILWAY_API_TOKEN = "r-token";
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    _resetCfAccountCache();
    _resetSelfCheckStability();
    for (const k of [...PROVIDER_ENV, ...TELEMETRY_ENV]) {
      if (saved[k] === undefined) delete process.env[k];
      else process.env[k] = saved[k];
    }
  });

  it("recovers a provider that fails once then succeeds — no false red banner", async () => {
    const seen: Record<string, number> = {};
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: string | URL | Request) => {
        const url = typeof input === "string" ? input : input.toString();
        const h = host(url);
        seen[h] = (seen[h] ?? 0) + 1;
        if (seen[h] === 1) throw abortError(); // first attempt: momentary blip
        return okResponse(url); // retry: healthy
      }),
    );
    const db = await bootDb();
    const { checks, overall } = await runIntegrationsCheck(db, testConfig());
    const by = (id: string) => checks.find((c) => c.id === id);
    expect(by("vercel")?.state).toBe("ok");
    expect(by("railway")?.state).toBe("ok");
    expect(by("cloudflare")?.ok).toBe(true);
    expect(overall).not.toBe("error");
  });

  it("does NOT go red on the first run of hard failures — suppressed pending confirmation", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        throw abortError();
      }),
    );
    const db = await bootDb();
    const { checks, overall } = await runIntegrationsCheck(db, testConfig());
    const by = (id: string) => checks.find((c) => c.id === id);
    expect(by("vercel")?.state).toBe("ok");
    expect(by("vercel")?.detail).toBe("recheck pending — This operation was aborted");
    expect(by("railway")?.state).toBe("ok");
    expect(by("cloudflare")?.state).toBe("ok");
    // The unreachable detail now carries the underlying cause in parentheses.
    expect(by("cloudflare")?.detail).toBe("recheck pending — workers/scripts unreachable (This operation was aborted)");
    expect(overall).not.toBe("error");
  });

  it("confirms a persistent all-provider outage but correlates it as monitor-side — amber, not red", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        throw abortError();
      }),
    );
    const db = await bootDb();
    const t0 = Date.now();
    await runIntegrationsCheck(db, testConfig(), t0);
    const { checks, overall } = await runIntegrationsCheck(db, testConfig(), t0 + CONFIRM_WINDOW_MS + 1_000);
    const by = (id: string) => checks.find((c) => c.id === id);
    for (const id of ["vercel", "cloudflare", "railway"]) {
      expect(by(id)?.state).toBe("warn");
      expect(by(id)?.correlated).toBe(true);
    }
    const connectivity = by("connectivity");
    expect(connectivity?.state).toBe("warn");
    expect(connectivity?.detail).toContain("3 providers unreachable at once");
    expect(overall).toBe("warn"); // never red for a correlated (monitor-side) outage
  });

  it("confirms a SINGLE persistently-unreachable provider as a real red error", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: string | URL | Request) => {
        const url = typeof input === "string" ? input : input.toString();
        if (host(url) === "v") throw abortError(); // only Vercel is down
        return okResponse(url);
      }),
    );
    const db = await bootDb();
    const t0 = Date.now();
    await runIntegrationsCheck(db, testConfig(), t0);
    const { checks } = await runIntegrationsCheck(db, testConfig(), t0 + CONFIRM_WINDOW_MS + 1_000);
    const by = (id: string) => checks.find((c) => c.id === id);
    expect(by("vercel")?.state).toBe("error");
    expect(by("vercel")?.correlated).toBeUndefined();
    expect(by("railway")?.state).toBe("ok");
    expect(checks.some((c) => c.id === "connectivity")).toBe(false);
  });

  it("does NOT retry a real HTTP response (401 token-invalid surfaces immediately)", async () => {
    const calls = vi.fn(async (input: string | URL | Request) => {
      const url = typeof input === "string" ? input : input.toString();
      if (host(url) === "v") return new Response("nope", { status: 401 });
      return okResponse(url);
    });
    vi.stubGlobal("fetch", calls);
    const db = await bootDb();
    const { checks } = await runIntegrationsCheck(db, testConfig());
    const by = (id: string) => checks.find((c) => c.id === id);
    expect(by("vercel")?.state).toBe("error");
    expect(by("vercel")?.detail).toContain("token invalid");
    // exactly one Vercel call — a 401 is a real state, not a transient blip
    const vercelCalls = calls.mock.calls.filter(
      ([input]) => host(typeof input === "string" ? input : String(input)) === "v",
    ).length;
    expect(vercelCalls).toBe(1);
  });
});
