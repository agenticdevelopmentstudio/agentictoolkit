"use client";
import { type PointerEvent as ReactPointerEvent, type ReactElement, type ReactNode, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { X } from "lucide-react";
import { Button } from "@agentic-toolkit/ui/components/button";
import { Input } from "@agentic-toolkit/ui/components/input";
import { Select } from "@agentic-toolkit/ui/components/select";
import { cn } from "@agentic-toolkit/ui/lib/utils";
import { useDeployProjects, type DeployProject } from "../../hooks/use-deploy-projects";
import { uniqueByProject } from "../../lib/project-key";
import { useNow } from "../../hooks/use-now";
import { platformCanon } from "../../lib/deploy-view";
import { platformLabel, deployStatusColor } from "../../lib/deploy-display";
import { PALETTE } from "../../lib/colors";
import { hostOf } from "../../lib/url";
import { timeAgo } from "../../lib/time-ago";

// Platforms, in display order. The chooser is a popup menu listing EVERY known
// platform, so a provider with no synced projects yet (e.g. railway before its first
// deploy lands) is still selectable rather than silently dropped from the menu.
const PROVIDER_ORDER = ["vercel", "railway", "cloudflare-pages"] as const;

const groupHead = "px-1 pt-0.5 pb-[3px] font-mono text-[0.62rem] uppercase tracking-[0.08em] text-apt-text-dim";
const fieldCap = "font-mono text-[0.62rem] uppercase tracking-[0.08em] text-apt-text-dim";

const STOP_TOKENS = new Set(["www", "com", "ai", "io", "net", "org", "studio", "app", "dev", "co"]);
const ENV_TOKENS = new Set(["production", "staging", "testing", "prod", "preview"]);

/**
 * Best-guess project for an endpoint — token overlap between the endpoint's url
 * host (+ env) and each project name across ALL providers. e.g. the docs staging
 * endpoint (staging.docs.…) suggests `docs-staging`. Returns null if nothing scores.
 */
export function suggestProject(endpoint: { url: string; environment: string | null }, projects: DeployProject[]): DeployProject | null {
  const host = hostOf(endpoint.url ?? "").toLowerCase();
  if (!host) return null;
  const hostTokens = host.split(".").filter((l) => l && !STOP_TOKENS.has(l) && !ENV_TOKENS.has(l));
  const env = (endpoint.environment ?? "").toLowerCase();
  let best: DeployProject | null = null;
  let bestScore = 0;
  for (const p of projects) {
    const pTokens = p.projectName.toLowerCase().split(/[-_.]/).filter(Boolean);
    let score = 0;
    for (const ht of hostTokens) {
      for (const pt of pTokens) {
        if (ht === pt) score += 3;
        else if (ht.length > 2 && pt.length > 2 && (ht.includes(pt) || pt.includes(ht))) score += 1;
      }
    }
    if (env && (pTokens.includes(env) || p.environments.includes(env))) score += 1;
    if (score > bestScore) { bestScore = score; best = p; }
  }
  return bestScore >= 3 ? best : null;
}

const projKey = (p: DeployProject): string => `${p.platform}|${p.projectName}`;

/** LEFT-column entry — project name + a "wired" dot. */
function ListItem({ p, selected, onSelect }: { p: DeployProject; selected: boolean; onSelect: (p: DeployProject) => void }): ReactElement {
  return (
    <button
      type="button"
      onClick={() => onSelect(p)}
      className={cn(
        "flex w-full items-center justify-between gap-1.5 rounded-md px-2 py-1.5 text-left font-mono text-xs transition-colors outline-none",
        selected ? "bg-apt-surface-2 text-apt-text" : "text-apt-text-muted hover:bg-apt-surface-2/50 hover:text-apt-text",
      )}
    >
      <span className="truncate">{p.projectName}</span>
      {p.wired && <span title="already wired to an endpoint" className="shrink-0 text-[0.5rem] text-apt-green">●</span>}
    </button>
  );
}

/** A small uppercase status/platform pill, tinted by a (data-driven) colour. */
function Pill({ text, color }: { text: string; color: string }): ReactElement {
  return (
    <span
      className="inline-flex items-center whitespace-nowrap rounded border px-1.5 py-0.5 text-[0.52rem] uppercase tracking-[0.05em]"
      style={{ borderColor: `color-mix(in srgb, ${color} 27%, transparent)`, color }}
    >
      {text}
    </span>
  );
}

/** One label/value row in the detail pane. */
function InfoRow({ label, value }: { label: string; value: ReactElement | string | null }): ReactElement {
  return (
    <div className="flex flex-col gap-1">
      <span className={fieldCap}>{label}</span>
      <span className="font-mono text-[0.78rem] leading-snug break-all text-apt-text">{value || <span className="text-apt-text-dim">—</span>}</span>
    </div>
  );
}

const extLink = "text-apt-blue no-underline hover:underline";

/** RIGHT-column detail pane — the selected project's config info (read-only; the
 *  modal footer's OK button confirms the choice). */
function InfoPanel({ p, nowMs }: { p: DeployProject; nowMs: number }): ReactElement {
  return (
    <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto p-4">
      <div className="flex flex-col gap-2">
        <span className="text-[0.94rem] leading-tight font-semibold break-all text-apt-text">{p.projectName}</span>
        <div className="flex flex-wrap gap-1.5">
          <Pill text={platformLabel(p.platform)} color={PALETTE.blue} />
          {p.wired && <Pill text="● wired" color={PALETTE.green} />}
          {p.latestStatus && <Pill text={p.latestStatus} color={deployStatusColor(p.latestStatus)} />}
        </div>
      </div>
      <div className="flex flex-col gap-3.5">
        <InfoRow label="Configured domain" value={p.domain ? <a href={`https://${p.domain}`} target="_blank" rel="noreferrer" className={extLink}>{p.domain}</a> : null} />
        <InfoRow label="Git repo" value={p.gitRepo ? <a href={`https://github.com/${p.gitRepo}`} target="_blank" rel="noreferrer" className={extLink}>{p.gitRepo}</a> : null} />
        <div className="flex flex-wrap gap-7">
          <InfoRow label="Git branch" value={p.gitBranch} />
          <InfoRow label="Framework" value={p.framework} />
        </div>
        <InfoRow label="Deployment root dir" value={p.rootDirectory} />
        <InfoRow label="Environments" value={p.environments.join(", ")} />
        <InfoRow
          label="Last deploy"
          value={
            <span>
              {p.latestStatus ? <span style={{ color: deployStatusColor(p.latestStatus) }}>{p.latestStatus}</span> : "—"}
              {` · ${p.deployCount} deploy${p.deployCount === 1 ? "" : "s"}`}
              {p.latestAt ? ` · ${timeAgo(p.latestAt, nowMs)} ago` : ""}
            </span>
          }
        />
      </div>
    </div>
  );
}

// The picker's size persists across opens within the session, so a size you drag to
// sticks instead of resetting. Default is a comfortable "nice big".
let savedBox = { w: 740, h: 600 };

/**
 * Pick the deploy project that builds a monitored URL — a "Set Platform Project"
 * button (or a custom `renderTrigger`) that opens a resizable modal: a platform
 * chooser at the top, then EVERY project on the chosen platform in a searchable
 * list with the selected project's config beside it. The footer's OK wires the
 * endpoint's platform + project via `onPick`; Cancel (or Escape) discards. The
 * dialog does NOT dismiss on an outside click — only Cancel / OK / Escape close it.
 */
export function ProjectBrowser({
  endpoint,
  onPick,
  renderTrigger,
}: {
  endpoint: { url: string; environment: string | null };
  onPick: (platform: string, project: string) => void;
  /** Custom trigger; receives an `open` callback. Defaults to a shared button. */
  renderTrigger?: (open: () => void) => ReactNode;
}): ReactElement {
  const { data, refetch } = useDeployProjects();
  // Wiring an endpoint to a project is env-agnostic (the endpoint supplies the
  // environment), so collapse Railway's per-environment entries to one row per project —
  // the picker (and its "Environments" detail) shows the project once, not once per env.
  const allProjects = useMemo(() => uniqueByProject(data?.projects ?? []), [data?.projects]);
  const nowMs = useNow();
  // Memoized so the O(projects) token scan doesn't re-run on every `useNow` tick
  // (this component re-renders ~1/s while mounted).
  const suggested = useMemo(() => suggestProject(endpoint, allProjects), [endpoint.url, endpoint.environment, allProjects]);

  const [open, setOpen] = useState(false);
  const [platform, setPlatform] = useState<string | null>(null); // null → derive from suggestion
  const [selKey, setSelKey] = useState<string | null>(null);
  const [q, setQ] = useState("");
  const [box, setBox] = useState({ left: 0, top: 0, w: savedBox.w, h: savedBox.h });
  const dialogRef = useRef<HTMLDivElement>(null);

  // The menu lists EVERY known platform, plus any unknown one already present in the
  // data, so railway-before-first-deploy (0 projects) is still selectable.
  const countForPlatform = (pl: string): number => allProjects.filter((p) => p.platform === pl).length;
  const platformOptions: string[] = [
    ...PROVIDER_ORDER,
    ...[...new Set(allProjects.map((p) => p.platform))].filter((pl) => !(PROVIDER_ORDER as readonly string[]).includes(pl)),
  ];
  // Derive (don't store) the active platform so it's right the moment projects load,
  // even if the panel opened before `useDeployProjects` resolved: honor an explicit
  // pick, else the suggested project's platform, else the first platform that actually
  // has projects (so an empty one isn't shown by default), else just the first option.
  const firstPresent = platformOptions.find((pl) => countForPlatform(pl) > 0);
  const effectivePlatform =
    (platform && platformOptions.includes(platform) ? platform : null) ??
    (suggested && platformOptions.includes(suggested.platform) ? suggested.platform : null) ??
    firstPresent ??
    platformOptions[0] ??
    "";

  const platformProjects = allProjects.filter((p) => p.platform === effectivePlatform);
  const needle = q.trim().toLowerCase();
  const filtered = needle
    ? platformProjects.filter((p) => `${p.projectName} ${p.gitRepo ?? ""} ${p.domain ?? ""}`.toLowerCase().includes(needle))
    : platformProjects;

  // Derive the effective selection: the user's pick if still on this platform, else
  // the suggested match (when on this platform), else the first project.
  const effectiveKey =
    selKey && platformProjects.some((p) => projKey(p) === selKey)
      ? selKey
      : suggested && suggested.platform === effectivePlatform
        ? projKey(suggested)
        : platformProjects[0]
          ? projKey(platformProjects[0])
          : null;
  const selected = platformProjects.find((p) => projKey(p) === effectiveKey) ?? null;

  const reset = useCallback((): void => {
    setPlatform(null);
    setSelKey(null);
    setQ("");
  }, []);
  const close = useCallback((): void => { setOpen(false); reset(); }, [reset]);

  // Open CENTERED (both axes) at the last-used size (sticky), clamped to the viewport.
  function openPanel(): void {
    reset();
    // Re-scan the providers EVERY time the picker comes up — a project created since the
    // last open must show. react-query then caches the result for this open; `refetch`
    // bypasses staleTime, so opening twice in a minute still re-scans (never serves the
    // 60s-stale list other consumers reuse).
    void refetch();
    const w = Math.min(savedBox.w, Math.round(window.innerWidth * 0.94));
    const h = Math.min(savedBox.h, Math.round(window.innerHeight * 0.88));
    setBox({ w, h, left: Math.max(12, Math.round((window.innerWidth - w) / 2)), top: Math.max(12, Math.round((window.innerHeight - h) / 2)) });
    setOpen(true);
  }

  function confirm(): void {
    if (!selected) return;
    onPick(platformCanon(selected.platform), selected.projectName);
    close();
  }

  // Modal keyboard handling: Escape closes, Tab is trapped inside the dialog, and
  // focus is restored to the trigger on close (the autoFocused search field takes
  // initial focus). Required for an aria-modal dialog — browsers don't enforce it.
  useEffect(() => {
    if (!open) return;
    const prevFocus = document.activeElement as HTMLElement | null;
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === "Escape") { close(); return; }
      if (e.key === "Tab" && dialogRef.current) {
        const f = dialogRef.current.querySelectorAll<HTMLElement>(
          'a[href], button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])',
        );
        if (f.length === 0) return;
        const first = f[0]!;
        const last = f[f.length - 1]!;
        if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
        else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
      }
    };
    window.addEventListener("keydown", onKey);
    return () => {
      window.removeEventListener("keydown", onKey);
      prevFocus?.focus();
    };
  }, [open, close]);

  // Drag the bottom-right grip to resize. Top-left stays anchored so the grip tracks
  // the cursor; min/max keep it usable and on-screen.
  function startResize(e: ReactPointerEvent): void {
    e.preventDefault();
    const sx = e.clientX, sy = e.clientY, sw = box.w, sh = box.h, { left, top } = box;
    const move = (ev: PointerEvent): void => {
      const w = Math.max(560, Math.min(window.innerWidth - left - 12, sw + ev.clientX - sx));
      const h = Math.max(420, Math.min(window.innerHeight - top - 12, sh + ev.clientY - sy));
      savedBox = { w, h }; // remember the size for the next open
      setBox({ left, top, w, h });
    };
    const up = (): void => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up); };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  }

  return (
    <>
      {renderTrigger ? (
        renderTrigger(openPanel)
      ) : (
        <Button type="button" variant="outline" size="sm" aria-label="Set platform project" onClick={openPanel}>
          Set Platform Project
        </Button>
      )}
      {open && createPortal(
        <div className="fixed inset-0 z-[200]">
          {/* Scrim only — clicking it does NOT dismiss (deliberate: avoids losing a
              half-made choice). Cancel / OK / Escape are the only ways out. */}
          <div aria-hidden className="absolute inset-0 bg-black/55" />
          <div
            ref={dialogRef}
            role="dialog"
            aria-modal="true"
            aria-label="Set platform project"
            className="fixed flex flex-col overflow-hidden rounded-[10px] border border-apt-border bg-apt-bg font-mono text-apt-text shadow-2xl outline-none"
            style={{ left: box.left, top: box.top, width: box.w, height: box.h }}
          >
            {/* TOOLBAR — title + platform chooser + close */}
            <div className="shrink-0 border-b border-apt-border bg-apt-surface">
              <div className="flex items-center justify-between gap-2 px-3.5 pt-2.5">
                <span className="text-[0.8rem] font-semibold tracking-[0.02em]">Set platform project</span>
                <Button type="button" variant="ghost" size="icon-sm" aria-label="Close" onClick={close}>
                  <X className="size-4" />
                </Button>
              </div>
              <div className="flex flex-wrap items-center gap-2 px-3.5 pt-2 pb-2.5">
                <label htmlFor="pb-platform" className={fieldCap}>Platform</label>
                {/* A popup menu over EVERY known platform (not only those with projects),
                    so a provider with nothing synced yet — e.g. railway before its first
                    deploy — stays selectable. Switching it re-filters the project list below. */}
                <Select
                  id="pb-platform"
                  aria-label="Platform"
                  value={effectivePlatform}
                  onChange={(e) => { setPlatform(e.target.value); setSelKey(null); setQ(""); }}
                  className="h-8 w-auto min-w-[190px] text-[0.78rem]"
                >
                  {platformOptions.map((pl) => (
                    <option key={pl} value={pl}>
                      {platformLabel(pl)} · {countForPlatform(pl)}
                    </option>
                  ))}
                </Select>
              </div>
            </div>
            {/* BODY — searchable single-platform list (left) + detail (right) */}
            <div className="flex min-h-0 w-full flex-1">
              <div className="flex w-[232px] shrink-0 flex-col border-r border-apt-border min-h-0">
                <div className="p-2">
                  <Input autoFocus value={q} onChange={(e) => setQ(e.target.value)} placeholder={`Search ${platformProjects.length} projects…`} aria-label="Search projects" className="h-8 text-sm" />
                </div>
                <div className="flex min-h-0 flex-1 flex-col gap-px overflow-y-auto px-2 pb-2">
                  {platformProjects.length === 0 && <span className={cn(fieldCap, "p-1.5")}>No projects on this platform yet — they appear after the first sync.</span>}
                  {platformProjects.length > 0 && (
                    <div className={groupHead}>{platformLabel(effectivePlatform)} · {filtered.length}</div>
                  )}
                  {filtered.map((p, i) => (
                    <ListItem key={`${projKey(p)}:${i}`} p={p} selected={effectiveKey === projKey(p)} onSelect={(x) => setSelKey(projKey(x))} />
                  ))}
                  {platformProjects.length > 0 && filtered.length === 0 && <span className={cn(fieldCap, "p-1.5")}>No match.</span>}
                </div>
              </div>
              <div className="flex min-h-0 min-w-0 flex-1 flex-col">
                {selected ? <InfoPanel p={selected} nowMs={nowMs} /> : <div className={cn(fieldCap, "p-4")}>Select a project to wire it to this site.</div>}
              </div>
            </div>
            {/* FOOTER — Cancel / OK. Extra right padding clears the resize grip. */}
            <div className="flex shrink-0 items-center justify-end gap-2 border-t border-apt-border bg-apt-surface py-2.5 pr-6 pl-3">
              <Button type="button" variant="ghost" size="sm" onClick={close}>Cancel</Button>
              <Button
                type="button"
                variant="outline"
                size="sm"
                disabled={!selected}
                className="border-apt-green/40 bg-apt-green/15 font-semibold text-apt-green hover:bg-apt-green/25"
                onClick={confirm}
              >
                OK
              </Button>
            </div>
            {/* RESIZE GRIP */}
            <div
              onPointerDown={startResize}
              title="Drag to resize"
              aria-hidden
              className="absolute right-0 bottom-0 h-[18px] w-[18px] cursor-nwse-resize text-center text-[11px] leading-[18px] text-apt-text-dim select-none"
            >
              ⤡
            </div>
          </div>
        </div>,
        document.body,
      )}
    </>
  );
}
