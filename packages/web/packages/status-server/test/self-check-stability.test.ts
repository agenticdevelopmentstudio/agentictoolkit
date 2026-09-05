import { describe, it, expect } from "vitest";
import {
  createSelfCheckStabilizer,
  CONFIRM_WINDOW_MS,
  CORRELATED_MIN,
} from "../src/monitor/self-check-stability";
import type { IntegrationCheck } from "../src/monitor/types";

const unreachable = (id: string): IntegrationCheck => ({
  id,
  label: id,
  configured: true,
  ok: false,
  state: "error",
  detail: "This operation was aborted",
  unreachable: true,
});

const reachable = (id: string): IntegrationCheck => ({
  id,
  label: id,
  configured: true,
  ok: true,
  state: "ok",
  detail: "reachable",
});

const httpError = (id: string): IntegrationCheck => ({
  id,
  label: id,
  configured: true,
  ok: false,
  state: "error",
  detail: "HTTP 401 — token invalid",
});

const T0 = 1_000_000;
const LATER = T0 + CONFIRM_WINDOW_MS + 1_000; // comfortably past the window

describe("createSelfCheckStabilizer", () => {
  it("suppresses a first-run unreachable failure (blip stays off the bar)", () => {
    const s = createSelfCheckStabilizer();
    const [check] = s.stabilize([unreachable("vercel")], T0);
    expect(check.state).toBe("ok");
    expect(check.ok).toBe(true);
    expect(check.detail).toBe("recheck pending — This operation was aborted");
  });

  it("keeps suppressing while the failure has not spanned the confirmation window", () => {
    const s = createSelfCheckStabilizer();
    s.stabilize([unreachable("vercel")], T0);
    // Second run seconds later — run count met, wall-clock persistence not.
    const [check] = s.stabilize([unreachable("vercel")], T0 + 5_000);
    expect(check.state).toBe("ok");
  });

  it("confirms a single provider that stays unreachable across runs AND the window — red", () => {
    const s = createSelfCheckStabilizer();
    s.stabilize([unreachable("vercel"), reachable("railway")], T0);
    const checks = s.stabilize([unreachable("vercel"), reachable("railway")], LATER);
    const vercel = checks.find((c) => c.id === "vercel")!;
    expect(vercel.state).toBe("error");
    expect(vercel.correlated).toBeUndefined();
    // One provider alone is a provider problem, not connectivity — no synthetic check.
    expect(checks.some((c) => c.id === "connectivity")).toBe(false);
  });

  it("a good run resets the streak — fail/recover/fail is two separate blips", () => {
    const s = createSelfCheckStabilizer();
    s.stabilize([unreachable("vercel")], T0);
    s.stabilize([reachable("vercel")], T0 + 60_000);
    const [check] = s.stabilize([unreachable("vercel")], LATER + 60_000);
    expect(check.state).toBe("ok"); // fresh streak — suppressed again
  });

  it("correlates simultaneous confirmed failures as monitor-side — amber, one Connectivity chip", () => {
    const s = createSelfCheckStabilizer();
    const both = [unreachable("cloudflare"), unreachable("posthog")];
    s.stabilize(both, T0);
    const checks = s.stabilize(both, LATER);
    const cf = checks.find((c) => c.id === "cloudflare")!;
    const ph = checks.find((c) => c.id === "posthog")!;
    expect(cf.state).toBe("warn");
    expect(cf.correlated).toBe(true);
    expect(ph.state).toBe("warn");
    expect(ph.correlated).toBe(true);
    const connectivity = checks.find((c) => c.id === "connectivity")!;
    expect(connectivity.state).toBe("warn");
    expect(connectivity.detail).toContain(`${CORRELATED_MIN} providers unreachable at once`);
  });

  it("passes real HTTP errors through untouched — token-invalid surfaces immediately", () => {
    const s = createSelfCheckStabilizer();
    const [check] = s.stabilize([httpError("vercel")], T0);
    expect(check.state).toBe("error");
    expect(check.detail).toBe("HTTP 401 — token invalid");
  });

  it("passes warn-level checks (missing env, freshness) through untouched", () => {
    const s = createSelfCheckStabilizer();
    const warn: IntegrationCheck = {
      id: "cron",
      label: "Stats freshness",
      configured: true,
      ok: false,
      state: "warn",
      detail: "first poll pending — no checks yet",
    };
    const [check] = s.stabilize([warn], T0);
    expect(check).toEqual(warn);
  });
});
