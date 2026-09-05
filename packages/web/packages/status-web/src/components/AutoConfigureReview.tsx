"use client";
import { type ReactElement, useMemo, useState } from "react";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@agentic-toolkit/ui/components/dialog";
import { Button } from "@agentic-toolkit/ui/components/button";
import { Select } from "@agentic-toolkit/ui/components/select";
import { Checkbox } from "@agentic-toolkit/ui/components/checkbox";
import { PLATFORM_ORDER, platformCanon } from "../lib/deploy-view";
import { platformLabel } from "../lib/deploy-display";
import { projectKeyOf } from "../lib/project-key";

/** A discovered (not-yet-monitored) deploy project, as the review modal needs it. */
export interface ReviewProject {
  /** The raw enumerated platform (vercel | railway | cloudflare-pages). */
  platform: string;
  projectName: string;
  /** Representative custom domain, or null when the project exposes none. */
  domain: string | null;
}

interface GroupOption {
  id: string;
  name: string;
}

export interface AutoConfigureReviewProps {
  projects: ReviewProject[];
  groups: GroupOption[];
  busy: boolean;
  progress: { done: number; total: number } | null;
  /** Apply: ignore the checked projects, configure the rest. New sites land in
   *  `newSiteGroupId` — as a FALLBACK (a site whose domain family another group already
   *  owns joins that group instead) unless `forceGroup`, which makes it authoritative. */
  onApply: (ignoreKeys: Set<string>, newSiteGroupId: string, forceGroup: boolean) => void;
  onCancel: () => void;
}

/** Section sort index for a CANONICAL platform, sharing deploy-view's PLATFORM_ORDER
 *  (raw keys) so the review modal orders sections identically to every other
 *  platform-grouped surface. Unknown platforms sort last. */
const sortIndex = (canon: string): number => {
  const i = PLATFORM_ORDER.findIndex((p) => platformCanon(p) === canon);
  return i === -1 ? PLATFORM_ORDER.length : i;
};

/** Group projects by canonical platform, ordered by the shared PLATFORM_ORDER. */
function bySection(projects: ReviewProject[]): { platform: string; items: ReviewProject[] }[] {
  const groups = new Map<string, ReviewProject[]>();
  for (const p of projects) {
    const canon = platformCanon(p.platform);
    const arr = groups.get(canon);
    if (arr) arr.push(p);
    else groups.set(canon, [p]);
  }
  return [...groups.entries()]
    .map(([platform, items]) => ({ platform, items }))
    .sort((a, b) => sortIndex(a.platform) - sortIndex(b.platform) || a.platform.localeCompare(b.platform));
}

/**
 * The "Review discovered projects" dialog the global Auto Configure action opens once
 * it finds unmonitored deploy projects. Lists them grouped by platform, each with an
 * ignore checkbox + a per-platform "ignore all", so the operator can prune a large
 * batch (the many Railway infra projects) before the rest are configured. Applying
 * persists the checked projects to the ignore list and configures the rest. Built on
 * the shared @agentic-toolkit/ui Dialog (which owns focus-trap + Escape + focus restore).
 */
export function AutoConfigureReview({ projects, groups, busy, progress, onApply, onCancel }: AutoConfigureReviewProps): ReactElement {
  const [ignore, setIgnore] = useState<Set<string>>(() => new Set());
  const [groupId, setGroupId] = useState<string>(() => {
    const other = groups.find((g) => g.name.toLowerCase() === "other products");
    return other?.id ?? groups[0]?.id ?? "";
  });
  // Off by default: grouping a new site with its domain family is what makes it "match the
  // existing sites", which is the whole point of the action. On, for a board whose groups
  // aren't per-product — where the family rule would file a production site under Testing.
  const [forceGroup, setForceGroup] = useState(false);

  const sections = useMemo(() => bySection(projects), [projects]);
  const ignoring = ignore.size;
  const configuring = useMemo(
    () => projects.filter((p) => !ignore.has(projectKeyOf(p)) && !!p.domain).length,
    [projects, ignore],
  );

  const setIgnored = (keys: string[], on: boolean): void =>
    setIgnore((prev) => {
      const next = new Set(prev);
      for (const k of keys) {
        if (on) next.add(k);
        else next.delete(k);
      }
      return next;
    });

  const primaryLabel = busy
    ? progress && progress.total > 0
      ? `Configuring ${progress.done}/${progress.total}…`
      : "Working…"
    : configuring > 0
      ? `Configure ${configuring}`
      : ignoring > 0
        ? `Ignore ${ignoring}`
        : "Configure";
  const primaryDisabled = busy || (configuring === 0 && ignoring === 0);

  return (
    <Dialog
      open
      onOpenChange={(open) => {
        if (!open && !busy) onCancel();
      }}
    >
      <DialogContent showClose={!busy} className="max-w-2xl font-mono">
        <DialogHeader>
          <DialogTitle className="text-apt-gold">⚙ Review discovered projects</DialogTitle>
          <DialogDescription>
            {projects.length} {projects.length === 1 ? "project isn't" : "projects aren't"} monitored yet. Check the ones to
            ignore — the rest are configured (matched to a site, or a new site is created).
          </DialogDescription>
        </DialogHeader>

        <div className="-mx-2 max-h-[50vh] overflow-y-auto px-2">
          {sections.map(({ platform, items }) => {
            const allIgnored = items.every((p) => ignore.has(projectKeyOf(p)));
            return (
              <div key={platform} className="mb-3">
                <div className="flex items-center justify-between px-1 py-1.5">
                  <span className="text-[11px] font-semibold uppercase tracking-wider text-apt-text-dim">
                    {platformLabel(platform)} · {items.length}
                  </span>
                  <label className="flex cursor-pointer items-center gap-2 text-[11px] text-apt-text-muted">
                    <Checkbox
                      checked={allIgnored}
                      onCheckedChange={(c) => setIgnored(items.map(projectKeyOf), c === true)}
                      disabled={busy}
                      aria-label={`ignore all ${platformLabel(platform)} projects`}
                    />
                    ignore all
                  </label>
                </div>
                {items.map((p) => {
                  const k = projectKeyOf(p);
                  const on = ignore.has(k);
                  return (
                    <label key={k} className="flex items-center gap-2 rounded px-2 py-1.5 text-xs hover:bg-apt-surface">
                      <Checkbox
                        checked={on}
                        onCheckedChange={(c) => setIgnored([k], c === true)}
                        disabled={busy}
                        aria-label={`ignore ${p.projectName}`}
                      />
                      <span className={on ? "font-semibold text-apt-text-dim line-through" : "font-semibold text-apt-text"}>
                        {p.projectName}
                      </span>
                      <span className={`ml-auto text-[11px] ${p.domain ? "text-apt-text-muted" : "text-apt-text-dim"}`}>
                        {p.domain ?? "no domain"}
                      </span>
                    </label>
                  );
                })}
              </div>
            );
          })}
        </div>

        <DialogFooter className="flex-col items-stretch gap-2 sm:flex-col sm:items-stretch">
          <label className="flex flex-wrap items-center gap-2 text-xs text-apt-text-muted">
            New sites →
            <Select
              value={groupId}
              onChange={(e) => setGroupId(e.target.value)}
              disabled={busy}
              aria-label="fallback group for newly created sites"
              className="w-auto"
            >
              {groups.map((g) => (
                <option key={g.id} value={g.id}>
                  {g.name}
                </option>
              ))}
            </Select>
          </label>
          {/* The selector alone doesn't decide every case — a new site whose domain family a
              group already owns joins THAT group — so the rule is a control, not a footnote:
              an operator who disagrees with the override can turn it off, and the label always
              says which way it is currently set. */}
          <label className="flex cursor-pointer items-center gap-2 text-[11px] text-apt-text-dim">
            <Checkbox
              checked={forceGroup}
              onCheckedChange={(c) => setForceGroup(c === true)}
              disabled={busy}
              aria-label="always use the selected group for new sites"
            />
            {forceGroup ? "always this group, even if another owns the domain" : "unless a group already owns the domain"}
          </label>
          <div className="flex items-center justify-between gap-3">
            <span className="text-[11px] text-apt-text-dim">
              Ignoring {ignoring} · Configuring {configuring}
            </span>
            <div className="flex gap-2">
              <Button type="button" variant="ghost" size="sm" disabled={busy} onClick={onCancel}>
                Cancel
              </Button>
              <Button
                type="button"
                variant="outline"
                size="sm"
                disabled={primaryDisabled}
                onClick={() => onApply(ignore, groupId, forceGroup)}
                className="border-apt-gold/50 text-apt-gold hover:bg-apt-gold/10"
              >
                {primaryLabel}
              </Button>
            </div>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
