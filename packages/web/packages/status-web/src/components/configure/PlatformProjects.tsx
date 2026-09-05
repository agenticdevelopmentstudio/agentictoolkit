"use client";
import { type ReactElement, useRef, useState } from "react";
import { Button } from "@agentic-toolkit/ui/components/button";
import { cn } from "@agentic-toolkit/ui/lib/utils";
import * as api from "../../api/monitored-sites";
import { useDeployProjects, type DeployProject } from "../../hooks/use-deploy-projects";
import { platformCanon } from "../../lib/deploy-view";
import { platformLabel } from "../../lib/deploy-display";
import { runMatch, type NotedAdd } from "../../lib/auto-configure";
import { indexLiveProjects, partitionPending, projectStatus, type ProjectStatus } from "@agentic-toolkit/deploy-platform/engine";
import { uniqueByProject } from "../../lib/project-key";
import { msg } from "../../lib/err";
import { MultiSelectFilter } from "../MultiSelectFilter";

const projLink = "adh-projlink truncate font-mono";

/** A row's identity in this list. Railway enumerates one entry PER environment, so the key
 *  (and the per-row busy state) must include the environment or the three adh-backend rows
 *  would collide. Non-Railway entries have a null environment, so this is just the project. */
const rowKey = (p: DeployProject): string => `${p.projectName}|${p.environment ?? ""}`;

/** The run's notes as ONE inline line: the first named in full, the rest counted — the
 *  same shape the skip line uses, so a notice can't grow into a log dump in this slot. */
function noticeLine(notes: NotedAdd[]): string | null {
  const first = notes[0];
  if (!first) return null;
  return `${first.project}: ${first.note}${notes.length > 1 ? ` (+${notes.length - 1} more)` : ""}`;
}

// The three mutually-exclusive states a deploy project can be in — the axis the
// list's pop filter selects on. `ProjectStatus` (and the `projectStatus()` that
// derives it) live in the shared config-status model so this filter and the
// banner/badges classify projects identically.
type ProjStatus = ProjectStatus;
const STATUS_OPTS: { key: ProjStatus; label: string }[] = [
  { key: "monitored", label: "monitored" },
  { key: "ignored", label: "ignored" },
  { key: "unmonitored", label: "not monitored" },
];

/** Every status selected — the filter's default + the "all" reset. Derived from
 *  STATUS_OPTS so a new status can't be silently left out of "all". */
const allStatuses = (): Set<ProjStatus> => new Set(STATUS_OPTS.map((o) => o.key));

/** Multi-select pop filter over the project list's monitored / ignored / not-monitored axis. */
function ProjectStatusFilter({ selected, onToggle, onSetAll }: { selected: Set<ProjStatus>; onToggle: (s: ProjStatus) => void; onSetAll: (all: boolean) => void }): ReactElement {
  return (
    <MultiSelectFilter
      popoverLabel="Status filter"
      triggerNoun="show"
      options={STATUS_OPTS}
      isSelected={(k) => selected.has(k as ProjStatus)}
      onToggle={(k) => onToggle(k as ProjStatus)}
      optionAriaLabel={(label) => `show ${label}`}
      onSetAll={onSetAll}
      allAriaLabel="show all"
      menuMinWidth={170}
    />
  );
}

/** The per-platform project list shown under the platform config: wired ✓, or Match / Ignore. */
export function PlatformProjects({ platform, onChanged }: { platform: string; onChanged: () => Promise<void> }): ReactElement {
  const { data, refetch } = useDeployProjects();
  const [busy, setBusy] = useState<string | null>(null); // projectName / "__all__" / null
  const [error, setError] = useState<string | null>(null);
  // A match that SUCCEEDED with something the operator has to be told (today: a monitor
  // taken over from a project the platform no longer has). Separate from `error` on
  // purpose — it worked, and colouring a success red is its own kind of wrong.
  const [notice, setNotice] = useState<string | null>(null);
  // "Match all" is sequential (one wiring request per project), so it reports how many
  // of the batch are done as it goes.
  const [progress, setProgress] = useState<{ done: number; total: number } | null>(null);
  // A ref guard (not `busy`) so two activations in the same tick can't both pass
  // before React commits setBusy and disables the button — a second match would
  // double-fire the wiring request. Mirrors AutoConfigureProvider.
  const addingRef = useRef(false);

  // The list's status filter (monitored / ignored / not-monitored). Defaults to
  // all three selected; the visible list narrows to whichever are checked.
  const [statusFilter, setStatusFilter] = useState<Set<ProjStatus>>(allStatuses);
  function toggleStatus(s: ProjStatus): void {
    setStatusFilter((prev) => {
      const next = new Set(prev);
      if (next.has(s)) next.delete(s);
      else next.add(s);
      return next;
    });
  }
  const setAllStatuses = (all: boolean): void => setStatusFilter(all ? allStatuses() : new Set<ProjStatus>());

  const canon = platformCanon(platform);
  // Every project the platforms STILL have — built from the UNFILTERED enumeration on
  // purpose. It is what lets a match repair an endpoint still wired to a project's OLD
  // name (after a rename, or a migration to another platform) instead of refusing it as a
  // conflict on every single run. `verifiedPlatforms` comes from the same response: only
  // the platforms the server listed live and in full may have an absence read as "gone",
  // and an older backend that doesn't send it repairs nothing rather than guessing.
  const liveProjects = indexLiveProjects(data?.projects ?? [], data?.verifiedPlatforms ?? []);
  const projects = (data?.projects ?? []).filter((p) => platformCanon(p.platform) === canon);
  // Every unconfigured project (Match or Ignore each). "Match all" only acts on the
  // domain-backed ones — a no-domain project has no host to match a site against.
  // Shared with the banner provider so the per-platform counts can't drift from it.
  const { pending, addable: addableAll } = partitionPending(projects);
  // The list as narrowed by the status filter. Match all / Ignore all act on the
  // unmonitored (`pending`) set, so they're only coherent when that group is
  // actually shown — gating on this keeps the bulk buttons from acting on rows the
  // filter has hidden (an enabled "Match all (5)" over an empty/filtered list).
  const visible = projects.filter((p) => statusFilter.has(projectStatus(p)));
  const showingUnmonitored = statusFilter.has("unmonitored");

  // refetch() refreshes this platform's deploy-projects; onChanged refreshes the
  // shared configure-data query (the Sites list + its no-project warnings).
  async function settle(): Promise<void> {
    await Promise.all([refetch(), onChanged()]);
  }

  async function addOne(p: DeployProject): Promise<void> {
    if (addingRef.current) return;
    addingRef.current = true;
    setBusy(rowKey(p)); setError(null); setNotice(null);
    try {
      // Same shared runner as "Match all" / the banner — one project's batch.
      const { skipped, notes } = await runMatch([p], { liveProjects });
      const first = skipped[0];
      if (first) setError(`${first.project}: ${first.reason}`);
      setNotice(noticeLine(notes));
      await settle();
    } catch (e) {
      // Don't clobber a skip message a refetch failure rode in after; surface both.
      setError((prev) => (prev ? `${prev}; refresh failed — ${msg(e)}` : `Match failed — ${msg(e)}`));
    } finally { addingRef.current = false; setBusy(null); }
  }
  async function addAll(): Promise<void> {
    if (addingRef.current) return;
    addingRef.current = true;
    setBusy("__all__"); setError(null); setNotice(null);
    setProgress({ done: 0, total: addableAll.length });
    try {
      // The shared runner is what the banner's "Auto Configure" also uses, so the
      // two entry points match projects identically.
      const { added, skipped, notes } = await runMatch(addableAll, {
        liveProjects,
        onProgress: (done, total) => setProgress({ done, total }),
      });
      setNotice(noticeLine(notes));
      if (skipped.length) {
        const first = skipped[0]!;
        setError(`Matched ${added}; ${skipped.length} unmatched — ${first.project}: ${first.reason}${skipped.length > 1 ? ` (+${skipped.length - 1} more)` : ""}`);
      }
      await settle();
    } catch (e) {
      // Keep the skip summary if we have one, and append the refetch failure rather
      // than silently dropping it.
      setError((prev) => (prev ? `${prev}; refresh failed — ${msg(e)}` : `Match all failed — ${msg(e)}`));
    } finally { addingRef.current = false; setBusy(null); setProgress(null); }
  }
  // Ignore is project-level (the ignored table has no environment), so ignoring one of a
  // Railway project's env rows ignores the whole project — its sibling rows flip together.
  async function ignore(p: DeployProject): Promise<void> {
    setBusy(rowKey(p)); setError(null);
    try { await api.ignoreProject(platformCanon(p.platform), p.projectName); await settle(); }
    catch (e) { setError(`Ignore failed — ${msg(e)}`); } finally { setBusy(null); }
  }
  async function unignore(p: DeployProject): Promise<void> {
    setBusy(rowKey(p)); setError(null);
    try { await api.unignoreProject(platformCanon(p.platform), p.projectName); await settle(); }
    catch (e) { setError(`Un-ignore failed — ${msg(e)}`); } finally { setBusy(null); }
  }
  // Bulk-dismiss every unconfigured project on this platform (one request). Collapsed to
  // one row per project — ignore is project-level, so a project's per-env entries are one
  // ignore, not one each.
  async function ignoreAll(): Promise<void> {
    if (pending.length === 0) return;
    setBusy("__ignore_all__"); setError(null);
    try {
      await api.ignoreProjects(uniqueByProject(pending).map((p) => ({ platform: platformCanon(p.platform), projectName: p.projectName })));
      await settle();
    } catch (e) { setError(`Ignore all failed — ${msg(e)}`); } finally { setBusy(null); }
  }

  const working = busy !== null;

  return (
    <div className="mt-1 flex min-h-0 flex-1 flex-col gap-2 border-t border-apt-border pt-3.5">
      <div className="flex shrink-0 items-center gap-2.5">
        <span className="font-mono text-[0.7rem] uppercase tracking-wider text-apt-text-muted">
          Projects on {platformLabel(canon)} · {projects.length}
        </span>
        {projects.length > 0 && (
          <ProjectStatusFilter selected={statusFilter} onToggle={toggleStatus} onSetAll={setAllStatuses} />
        )}
        <Button
          size="xs"
          variant="outline"
          className="ml-auto border-apt-green/40 text-apt-green hover:bg-apt-green/10"
          title={showingUnmonitored ? "wire every domain-backed project to the site that already monitors it" : `show "not monitored" to match projects`}
          disabled={working || addableAll.length === 0 || !showingUnmonitored}
          onClick={() => void addAll()}
        >
          {busy === "__all__" ? `Matching ${progress?.done ?? 0}/${progress?.total ?? addableAll.length}…` : `Match all (${addableAll.length})`}
        </Button>
        <Button
          size="xs"
          variant="outline"
          title={showingUnmonitored ? "dismiss every unconfigured project on this platform from the warning" : `show "not monitored" to ignore projects`}
          disabled={working || pending.length === 0 || !showingUnmonitored}
          onClick={() => void ignoreAll()}
        >
          {busy === "__ignore_all__" ? "Ignoring…" : `Ignore all (${pending.length})`}
        </Button>
      </div>

      {/* Determinate progress while "Match all" works through the batch sequentially. */}
      {busy === "__all__" && progress && progress.total > 0 && (
        <div
          className="h-1 w-full shrink-0 overflow-hidden rounded-full bg-apt-surface-2"
          role="progressbar"
          aria-label="adding all projects"
          aria-valuemin={0}
          aria-valuemax={progress.total}
          aria-valuenow={progress.done}
        >
          <div
            className="h-full rounded-full bg-apt-green transition-[width] duration-200"
            style={{ width: `${(progress.done / progress.total) * 100}%` }}
          />
        </div>
      )}

      {error && <span className="font-mono text-[0.7rem] text-apt-red">{error}</span>}
      {notice && <span className="font-mono text-[0.7rem] text-apt-text-muted">{notice}</span>}

      {projects.length === 0 ? (
        <span className="font-mono text-[0.7rem] uppercase tracking-wider text-apt-text-dim">
          No projects seen on this platform yet — they appear after the first sync.
        </span>
      ) : visible.length === 0 ? (
        <span className="font-mono text-[0.7rem] uppercase tracking-wider text-apt-text-dim">
          No projects match this filter.
        </span>
      ) : (
        <div className="flex min-h-0 flex-1 flex-col gap-px overflow-y-auto rounded-md border border-apt-border bg-apt-bg p-1">
          {visible.map((p) => {
            const acting = busy === rowKey(p);
            const st = projectStatus(p);
            const nameColor = st === "monitored" ? "text-apt-text" : st === "ignored" ? "text-apt-text-dim" : "text-apt-text-muted";
            return (
              <div key={rowKey(p)} className="flex items-center gap-2 rounded px-2 py-1.5">
                {/* Two lines: project name (+ env tag, so a Railway project's per-environment
                    rows are distinct), then its live domain — both link to the live site. */}
                <div className="flex min-w-0 flex-1 flex-col gap-px">
                  <span className="flex min-w-0 items-baseline gap-1.5">
                    {p.domain ? (
                      <a className={cn(projLink, "text-xs", nameColor)} href={`https://${p.domain}`} target="_blank" rel="noopener noreferrer" title={`open https://${p.domain}`}>
                        {p.projectName}
                      </a>
                    ) : (
                      <span className={cn("truncate font-mono text-xs", nameColor)}>{p.projectName}</span>
                    )}
                    {p.environment && (
                      <span className="shrink-0 font-mono text-[0.6rem] uppercase tracking-wider text-apt-text-dim">{p.environment}</span>
                    )}
                  </span>
                  {p.domain && (
                    <a className={cn(projLink, "text-[0.66rem] text-apt-text-dim")} href={`https://${p.domain}`} target="_blank" rel="noopener noreferrer" title={`open https://${p.domain}`}>
                      {p.domain}
                    </a>
                  )}
                </div>
                {st === "monitored" ? (
                  <span title="monitored" className="shrink-0 font-mono text-[0.72rem] text-apt-green">✓ monitored</span>
                ) : st === "ignored" ? (
                  <>
                    <span className="shrink-0 font-mono text-[0.7rem] text-apt-text-dim">ignored</span>
                    <Button size="xs" variant="outline" disabled={working} onClick={() => void unignore(p)}>Un-ignore</Button>
                  </>
                ) : (
                  <>
                    {/* No domain → nothing to match a site against (Match wires by domain). */}
                    {!p.domain && (
                      <span title="no domain — nothing to match a site against" className="shrink-0 font-mono text-[0.66rem] text-apt-text-dim">no domain</span>
                    )}
                    <Button size="xs" variant="outline" className="border-apt-green/40 text-apt-green hover:bg-apt-green/10" disabled={working || !p.domain} onClick={() => void addOne(p)}>
                      {acting ? "…" : "Match"}
                    </Button>
                    <Button size="xs" variant="outline" disabled={working} onClick={() => void ignore(p)}>Ignore</Button>
                  </>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
