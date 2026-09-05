import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { SITE_BUILD, isSiteId } from "../registry.js";

// The three build fields live in `SITE_BUILD`, a side table below the `</gen:sites>`
// close marker in `registry.ts` — NOT on `SiteDef`/`SITES`. `<adh-tools>/sites/scripts/scaffold-sites.py`'s
// `patch_registry()` regenerates the `<gen:sites>` region wholesale from a fixed template that
// has no notion of these fields, so a field written on a `SITES` entry inside that region is
// silently dropped on the next scaffold run. Deriving the flagged sets from `SITE_BUILD` (rather
// than hand-listing them again) is what keeps these assertions from drifting out of step with
// the source of truth.

describe("site build fields", () => {
  it("keeps build fields out of the scaffold-managed region", () => {
    const src = readFileSync(
      fileURLToPath(new URL("../registry.ts", import.meta.url)),
      "utf8",
    );
    const open = src.indexOf("<gen:sites>");
    const close = src.indexOf("</gen:sites>");
    expect(open).toBeGreaterThan(-1);
    expect(close).toBeGreaterThan(open);
    const managed = src.slice(open, close);
    for (const field of ["legacyHomePaths", "extraRedirects", "requiresBackendUrl", "handRolledConfig"]) {
      expect(managed).not.toContain(field);
    }
  });

  it("marks exactly the eight registry-owned legacy-home-path sites", () => {
    const flagged = Object.entries(SITE_BUILD)
      .filter(([, cfg]) => cfg?.legacyHomePaths)
      .map(([id]) => id)
      .sort();
    expect(flagged).toEqual(
      ["dashboards", "ecosystems", "knowledgebases", "narratives", "personabuilder", "projects", "research", "teamregistry"].sort(),
    );
  });

  // cookbook and hub must NOT appear: they are the exempt pair, and a well-meaning
  // implementer materializing their derived redirects into static data is the specific
  // regression this pins.
  it("gives extraRedirects to exactly help and personaregistry", () => {
    const withRedirects = Object.entries(SITE_BUILD)
      .filter(([, cfg]) => (cfg?.extraRedirects ?? []).length > 0)
      .map(([id]) => id)
      .sort();
    expect(withRedirects).toEqual(["help", "personaregistry"]);
  });

  // Hand-copied out of `frontend/src/sites/help/next.config.ts:14-27` (10 entries, all
  // `permanent: true` — the destinations are template literals over
  // `const HELP = "https://help.agenticdeveloperhub.com"` there, spelled out as plain
  // strings here). Read off the source file rather than the registry, so this test is an
  // independent statement of the truth rather than an echo of what was written, and pins
  // the actual source/destination strings rather than just their count.
  it("pins help's exact redirect entries", () => {
    expect(SITE_BUILD.help?.extraRedirects).toEqual([
      { source: "/api", destination: "https://help.agenticdeveloperhub.com/rest-api", permanent: true },
      { source: "/docs", destination: "https://help.agenticdeveloperhub.com/quickstart", permanent: true },
      { source: "/docs/quickstart", destination: "https://help.agenticdeveloperhub.com/quickstart", permanent: true },
      { source: "/docs/hub-features", destination: "https://help.agenticdeveloperhub.com/hub", permanent: true },
      { source: "/docs/api", destination: "https://help.agenticdeveloperhub.com/rest-api", permanent: true },
      { source: "/docs/mcp", destination: "https://help.agenticdeveloperhub.com/mcp", permanent: true },
      { source: "/docs/errors", destination: "https://help.agenticdeveloperhub.com/reference/errors", permanent: true },
      { source: "/docs/webhooks", destination: "https://help.agenticdeveloperhub.com/reference/webhooks", permanent: true },
      { source: "/docs/changelog", destination: "https://help.agenticdeveloperhub.com/reference/changelog", permanent: true },
      { source: "/docs/oauth/:step*", destination: "https://help.agenticdeveloperhub.com/quickstart/oauth/:step*", permanent: true },
    ]);
  });

  // Hand-copied out of `frontend/src/sites/personaregistry/next.config.ts` (3 entries, all
  // `permanent: false` — a 308 would outlive a later change to that URL grammar).
  it("pins personaregistry's exact redirect entries", () => {
    expect(SITE_BUILD.personaregistry?.extraRedirects).toEqual([
      { source: "/persona/:path+", destination: "/:path+", permanent: false },
      { source: "/user/:path+", destination: "/:path+", permanent: false },
      { source: "/org/:path+", destination: "/:path+", permanent: false },
    ]);
  });

  // The five sites that fail a hosted build with no API_BACKEND_URL. Asserting the exact
  // SET, not "bitbag is true", is what makes this catch the regression that matters — a
  // sixth site quietly gaining the flag fails its own deploy, and a site quietly losing it
  // deploys a proxy that 502s on every call.
  //
  // `projects` and `narratives` joined the set as a fix, not as a widening: both used to
  // carry a site-local `src/lib/backend-url.ts` that asserted the var unconditionally at
  // config load. Moving them onto the shared template deleted that file, and with it the
  // assertion — so both would have deployed exactly the 502-on-every-call proxy this test
  // exists to prevent. The flag is where that assertion lives now.
  //
  // `billing` is the fifth, and it is a widening — a DELIBERATE one, which is the only kind
  // this test can be updated for. agenticdeveloperbilling.com made no authenticated backend
  // call while its pane was a placeholder; it now reads offers, accounts and Stripe prices,
  // so it belongs with the four and not with the 37 marketing sites that call nothing. If
  // this assertion ever fails for a site nobody meant to add, the fix is the registry, not
  // this line.
  it("marks exactly the five backend-fronting sites as requiring a backend url", () => {
    const flagged = Object.entries(SITE_BUILD)
      .filter(([, cfg]) => cfg?.requiresBackendUrl)
      .map(([id]) => id)
      .sort();
    expect(flagged).toEqual(["billing", "bitbag", "narratives", "personaregistry", "projects"]);
  });

  // The six sites that keep a hand-written next.config.ts (Task 6a / A1, A3). Asserting
  // the exact set — not just "bitbag is true" — is what catches a seventh site quietly
  // gaining the flag (probe-auth-fleet's A4 re-point would stop checking its BFF) or one of
  // the six quietly losing it (the probe would wrongly demand the uniform rewrite text).
  // `learntruefacts` was a seventh until it left the fleet on 2026-08-14; `bitbag` stays
  // on the list even though its source moved to its own repo on 2026-08-15, because the
  // flag describes the config that site's build uses, not which checkout holds it.
  it("marks exactly the six hand-rolled sites", () => {
    const flagged = Object.entries(SITE_BUILD)
      .filter(([, cfg]) => cfg?.handRolledConfig)
      .map(([id]) => id)
      .sort();
    expect(flagged).toEqual(["admin", "bitbag", "cookbook", "hub", "hub-help", "status"].sort());
  });

  it("isSiteId accepts a real id and rejects a directory that is not a site", () => {
    expect(isSiteId("hub")).toBe(true);
    expect(isSiteId("node_modules")).toBe(false);
    expect(isSiteId("")).toBe(false);
  });
});
