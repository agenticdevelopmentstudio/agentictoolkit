"use client";
import { useMemo, type ReactElement } from "react";
import { useConfigStatus } from "../hooks/use-config-status";
import { useStatusUser } from "../hooks/useStatusUser";
import type { DeployProject } from "../hooks/use-deploy-projects";
import { platformColor, platformGlyph, platformLabel } from "../lib/deploy-display";
import { hostOf } from "../lib/url";
import { plural } from "../lib/format";
import { COLORS, PALETTE } from "../lib/colors";
import { AutoConfigureButton } from "./AutoConfigureButton";
import { Popover, PopoverTrigger, PopoverContent } from "@agentic-toolkit/ui/components/popover";
import { BANNER_MONO, bannerBarStyle, bannerTriggerClass } from "./banner-bar";

const mono = BANNER_MONO;

/**
 * Top-of-page warning whenever ANYTHING needs configuration — driven entirely by
 * the shared `useConfigStatus` model, the SAME model the Settings ▸ Sites badge and
 * the Platforms badges read. So the front page can never say "all clear" while the
 * Settings sections show ⚠ (the bug this banner used to have: it only counted unmonitored
 * deploy PROJECTS and was blind to unconfigured SITES).
 *
 * Two gaps, one banner:
 *  • Sites not configured — monitored endpoints with no deploy-project wiring.
 *  • Projects not monitored — deploy projects no endpoint covers (and not ignored).
 * The popover lists exactly which, so it reconciles with the Config page item-for-item.
 */
export function UnconfiguredProjectsBanner(): ReactElement | null {
  // ADMIN ONLY, and gated on the ROLE rather than on the render below: every read behind
  // `useConfigStatus` is a `/config/*` fetch, which configRoutes answers with 403 for
  // anyone but an admin. Ungated, a viewer or a not-yet-approved `pending` account gets a
  // permanent amber "couldn't load configuration status" bar — the failure branch below
  // firing on a permission answer, not on a broken backend — and it is shown to exactly
  // the people who have no way to act on it. `undefined` (the beat before the session
  // resolves) is a non-admin here, so the banner appears once the role does, rather than
  // flashing an error while auth loads.
  const isAdmin = useStatusUser()?.role === "admin";
  const { status, configure, error } = useConfigStatus({ enabled: isAdmin });
  const { unconfiguredSites, unmonitoredProjects, counts } = status;

  // Derive the display structures once per data change — a `useMemo` BEFORE the
  // early return so an unrelated parent re-render doesn't rebuild Maps/sorts.
  const derived = useMemo(() => {
    const siteName = new Map((configure?.sites ?? []).map((s) => [s.id, s.name] as const));
    const byPlatform = new Map<string, DeployProject[]>();
    for (const p of unmonitoredProjects) {
      const list = byPlatform.get(p.platform) ?? [];
      list.push(p);
      byPlatform.set(p.platform, list);
    }
    const projectGroups = [...byPlatform.entries()].sort((a, b) => a[0].localeCompare(b[0]));
    const clauses: string[] = [];
    if (counts.sites > 0) clauses.push(`${plural(counts.sites, "site")} not configured`);
    if (counts.projects > 0) clauses.push(`${plural(counts.projects, "project")} not monitored`);
    return { siteName, projectGroups, headline: clauses.join(" · ") };
  }, [configure?.sites, unmonitoredProjects, counts.sites, counts.projects]);

  // Parking the observer above is not on its own enough to hide the banner: the
  // ["configure-data"] cache is shared and outlives a session change, so a viewer signing
  // in after an admin in the same tab would render the admin's counts from cache. Say it
  // outright instead. (After the hooks, never before — the two above must run every
  // render.)
  if (!isAdmin) return null;

  // No gaps → stay silent, UNLESS the status data failed to load: then say so
  // rather than imply "all clear" (a failed deploy-projects fetch reads as 0).
  if (counts.total === 0) {
    return error ? (
      <div style={bannerBarStyle("amber")}>
        <span style={{ fontFamily: mono, fontSize: 11.5, fontWeight: 700, color: PALETTE.amber }}>
          ⚠ couldn’t load configuration status — counts may be incomplete
        </span>
      </div>
    ) : null;
  }

  const { siteName, projectGroups, headline } = derived;

  return (
    <div style={bannerBarStyle("amber")}>
      <AutoConfigureButton />
      <Popover>
        <PopoverTrigger aria-label="Show everything that needs configuration" className={bannerTriggerClass("amber")}>
          ⚠ CONFIGURE: {headline}
          <span aria-hidden style={{ opacity: 0.7 }}>▾</span>
        </PopoverTrigger>
        <PopoverContent align="start" sideOffset={6} className="w-auto p-1.5" style={{ minWidth: 280, maxWidth: 440 }}>
          <div style={{ maxHeight: 360, overflowY: "auto", display: "flex", flexDirection: "column", gap: 10 }}>
            {unconfiguredSites.length > 0 && (
              <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
                <div style={{ fontFamily: mono, fontSize: 10, fontWeight: 700, letterSpacing: "0.06em", color: PALETTE.amber, padding: "2px 6px" }}>
                  ⚠ SITES NOT CONFIGURED · {unconfiguredSites.length}
                </div>
                {unconfiguredSites.map((e) => {
                  const host = hostOf(e.url) || e.url;
                  return (
                    <div key={e.id} style={{ display: "flex", flexDirection: "column", padding: "3px 6px 3px 18px" }}>
                      <a className="adh-projlink" href={e.url} target="_blank" rel="noopener noreferrer" title={`open ${e.url}`} style={{ fontFamily: mono, fontSize: 12, color: PALETTE.text }}>
                        {siteName.get(e.siteId) ?? host}
                      </a>
                      <span style={{ fontFamily: mono, fontSize: 10.5, color: COLORS.textFaint }}>
                        {host}{e.environment ? ` · ${e.environment}` : ""} — no deploy project
                      </span>
                    </div>
                  );
                })}
              </div>
            )}
            {projectGroups.map(([platform, list]) => {
              const hue = platformColor(platform);
              return (
                <div key={platform} style={{ display: "flex", flexDirection: "column", gap: 2 }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 6, fontFamily: mono, fontSize: 10, fontWeight: 700, letterSpacing: "0.06em", color: hue, padding: "2px 6px" }}>
                    <span aria-hidden>{platformGlyph(platform)}</span>
                    {platformLabel(platform)} · {list.length} not monitored
                  </div>
                  {list.map((p) => (
                    // Railway enumerates one entry per environment, so key + display carry
                    // the env — a project's staging row can show "not monitored" while its
                    // production row is already wired.
                    <div key={`${p.projectName}|${p.environment ?? ""}`} style={{ display: "flex", flexDirection: "column", padding: "3px 6px 3px 18px" }}>
                      {p.domain ? (
                        <a className="adh-projlink" href={`https://${p.domain}`} target="_blank" rel="noopener noreferrer" title={`open https://${p.domain}`} style={{ fontFamily: mono, fontSize: 12, color: PALETTE.text }}>
                          {p.projectName}
                        </a>
                      ) : (
                        <span style={{ fontFamily: mono, fontSize: 12, color: COLORS.textSoft }}>{p.projectName}</span>
                      )}
                      <span style={{ fontFamily: mono, fontSize: 10.5, color: COLORS.textFaint }}>
                        {p.domain ?? "no domain"}{p.environment ? ` · ${p.environment}` : ""}
                      </span>
                    </div>
                  ))}
                </div>
              );
            })}
          </div>
        </PopoverContent>
      </Popover>
      <span style={{ fontFamily: mono, fontSize: 11.5, color: PALETTE.amber }}>open Settings ▸ Sites to fix each, or Settings ▸ Platforms to Match / Ignore</span>
    </div>
  );
}
