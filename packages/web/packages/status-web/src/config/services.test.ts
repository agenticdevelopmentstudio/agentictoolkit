import { describe, it, expect } from "vitest";
import { ACTIVE_SERVICES, ENV_ORDER } from "./services";

describe("services config", () => {
  it("has unique slugs", () => {
    const slugs = ACTIVE_SERVICES.map((s) => s.slug);
    expect(new Set(slugs).size).toBe(slugs.length);
  });
  it("derives env-prefixed hosts", () => {
    const staging = ACTIVE_SERVICES.find((s) => s.slug === "adh-app-staging");
    expect(staging?.url).toBe("https://staging.agenticdeveloperhub.com");
  });
  it("backend uses the health path", () => {
    const be = ACTIVE_SERVICES.find((s) => s.slug === "adh-backend-production");
    expect(be?.url).toBe("https://backend.agenticdeveloperhub.com/health");
    expect(be?.kind).toBe("health");
  });
  it("docs has no testing env", () => {
    expect(ACTIVE_SERVICES.some((s) => s.slug === "adh-docs-testing")).toBe(false);
  });
  it("monitors the status site (production + staging) on vercel", () => {
    const prod = ACTIVE_SERVICES.find((s) => s.slug === "adh-status-production");
    expect(prod?.url).toBe("https://status.agenticdeveloperhub.com");
    const staging = ACTIVE_SERVICES.find((s) => s.slug === "adh-status-staging");
    expect(staging?.url).toBe("https://staging.status.agenticdeveloperhub.com");
    // No testing env for status.
    expect(ACTIVE_SERVICES.some((s) => s.slug === "adh-status-testing")).toBe(false);
  });

  // (Deploy-project mapping is gone — ACTIVE_SERVICES is just a seed now, and
  // deploys correlate to endpoints by live host; see deploy-view.test.ts.)

  // Supplementary production-only checks: the Scalar apidocs frontend and the
  // data-API /health probe, both on the hub apex.
  it("monitors the apidocs + data-API hosts (production-only)", () => {
    const docs = ACTIVE_SERVICES.find((s) => s.slug === "storage-apidocs-production");
    expect(docs?.url).toBe("https://apidocs.agenticdeveloperhub.com");
    expect(docs?.kind).toBe("frontend");

    const api = ACTIVE_SERVICES.find((s) => s.slug === "storage-api-production");
    expect(api?.url).toBe("https://api.agenticdeveloperhub.com/health");
    expect(api?.kind).toBe("health");

    // storage-mcp was a duplicate of adh-mcp (same host) and was removed.
    expect(ACTIVE_SERVICES.some((s) => s.slug === "storage-mcp-production")).toBe(false);

    // Production-only — no staging/testing variants of these hosts yet.
    for (const base of ["storage-apidocs", "storage-api"]) {
      expect(ACTIVE_SERVICES.some((s) => s.slug === `${base}-staging`)).toBe(false);
      expect(ACTIVE_SERVICES.some((s) => s.slug === `${base}-testing`)).toBe(false);
    }

    // Originals kept untouched.
    for (const slug of ["adh-api-production", "adh-mcp-production", "adh-backend-production"]) {
      expect(ACTIVE_SERVICES.some((s) => s.slug === slug)).toBe(true);
    }
  });

  // ENV_ORDER
  it("ENV_ORDER is production, staging, testing", () => {
    expect(ENV_ORDER).toEqual(["production", "staging", "testing"]);
  });
});
