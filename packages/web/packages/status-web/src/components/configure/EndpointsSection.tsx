"use client";
import { type ReactElement, useCallback, useMemo, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { Globe, TriangleAlert } from "lucide-react";
import { Button } from "@agentic-toolkit/ui/components/button";
import { Input } from "@agentic-toolkit/ui/components/input";
import { Select } from "@agentic-toolkit/ui/components/select";
import { Switch } from "@agentic-toolkit/ui/components/switch";
import { Checkbox } from "@agentic-toolkit/ui/components/checkbox";
import { Label } from "@agentic-toolkit/ui/components/label";
import { Field, FieldGroup, type TopicLevel } from "@agentic-toolkit/ui/blocks";
import { cn } from "@agentic-toolkit/ui/lib/utils";
import * as api from "../../api/monitored-sites";
import { type SiteGroupView, type SiteView, type EndpointView } from "../../api/monitored-sites";
import type { EndpointConfigStatus } from "@agentic-toolkit/deploy-platform/engine";
import { hostEnv } from "@agentic-toolkit/deploy-platform/canon";
// The classifiers are this app's wrappers (they fold in the paused-monitor opt-out).
import { endpointConfigStatus, endpointUnconfigured } from "../../lib/config-status";
import { PLATFORM_NONE, allPlatformKeys, platformFilterOptions } from "../../lib/platform-filter";
import { platformCanon } from "../../lib/deploy-view";
import { platformIcon } from "../../lib/platform-icon";
import { platformLabel } from "../../lib/deploy-display";
import { hostOf } from "../../lib/url";
import { slugify } from "../../lib/slug";
import { useDeployProjects } from "../../hooks/use-deploy-projects";
import { useSettingsEntityLevel } from "../settings-level";
import { ProjectBrowser } from "./ProjectBrowser";
import { useEditorMutations } from "./use-editor-mutations";
import { useDraftForSelection } from "./use-draft-for-selection";
import { EntityEditorShell, SectionPlaceholder, rosterEmptyLabel, rosterOverviewHelp, type RosterLoadState } from "./section-chrome";
import { AutoConfigureButton } from "../AutoConfigureButton";
import { MultiSelectFilter } from "../MultiSelectFilter";

// ── Sites-list pop filters ────────────────────────────────────────────────────
// The config-status axis the second filter selects on (configured / unconfigured /
// ignored), mirroring the Platforms view's STATUS_OPTS. Derived from this list so
// the "all" reset can never silently omit a status.
const STATUS_OPTS: { key: EndpointConfigStatus; label: string }[] = [
  { key: "configured", label: "configured" },
  { key: "unconfigured", label: "unconfigured" },
  { key: "ignored", label: "ignored" },
];
const allStatuses = (): Set<EndpointConfigStatus> => new Set(STATUS_OPTS.map((o) => o.key));


// The platform filter's `PLATFORM_NONE`, "all" set, and option rows live in
// `@/lib/platform-filter` so they're unit-tested and the known platforms (incl.
// railway) are always offered even when no site uses them yet.

// A monitored Site, in this editor's model, IS one thing: a URL (its DNS name),
// the deploy project that serves it, and how it's health-checked. There is no
// separate "site" picker — the Site row is derived 1:1 from the URL's host. The
// environment (production / staging / testing) is inferred from the host's leading
// label, and `kind` is always a plain HTTP check.
const KIND = "http";

/** Environment implied by a URL — `staging.x.com` → staging, plain apex → production.
 *  Empty string when the URL has no parseable host (e.g. the `https://` placeholder),
 *  so the UI can show a dash rather than a misleading "production". */
function envOf(url: string): string {
  let host = "";
  try {
    host = new URL(url).hostname;
  } catch {
    host = "";
  }
  return host ? hostEnv(host) : "";
}

/** The list/label form of a site's URL. The host alone collides when two
 *  endpoints share a host (different path), so include the path to tell them
 *  apart. */
function siteUrlLabel(url: string): string {
  const host = hostOf(url);
  if (!host) return url || "(no url)";
  try {
    const path = new URL(url).pathname;
    return path && path !== "/" ? host + path : host;
  } catch {
    return host;
  }
}

/** The name of the group a site belongs to ("—" when unresolvable). */
function groupOfSite(sites: SiteView[], groups: SiteGroupView[], siteId: string): string {
  const site = sites.find((s) => s.id === siteId);
  return groups.find((g) => g.id === site?.groupId)?.name ?? "—";
}

/** A working copy of a site's editable fields (URL + group + wiring + checks). */
interface Draft {
  groupId: string; // the group this site belongs to (movable)
  siteId: string; // the existing site row (edit only; "" while creating)
  url: string;
  platform: string | null;
  deployProject: string | null;
  ignoreProjectWarning: boolean;
  expectedStatus: number;
  expectBody: string | null;
  dnsCheckA: boolean;
  dnsCheckAaaa: boolean;
  dnsCheckCname: boolean;
  checkIntervalSeconds: number;
  isActive: boolean;
}

// Schema defaults so a fresh site matches the DB.
function blankDraft(groupId: string): Draft {
  return {
    groupId,
    siteId: "",
    url: "https://",
    platform: null,
    deployProject: null,
    ignoreProjectWarning: false,
    expectedStatus: 200,
    expectBody: null,
    dnsCheckA: true,
    dnsCheckAaaa: true,
    dnsCheckCname: true,
    checkIntervalSeconds: 60,
    isActive: true,
  };
}

function draftFromEndpoint(e: EndpointView, groupId: string): Draft {
  return {
    groupId,
    siteId: e.siteId,
    url: e.url,
    platform: e.platform,
    deployProject: e.deployProject,
    ignoreProjectWarning: e.ignoreProjectWarning,
    expectedStatus: e.expectedStatus,
    expectBody: e.expectBody,
    dnsCheckA: e.dnsCheckA,
    dnsCheckAaaa: e.dnsCheckAaaa,
    dnsCheckCname: e.dnsCheckCname,
    checkIntervalSeconds: e.checkIntervalSeconds,
    isActive: e.isActive,
  };
}

/**
 * The "Sites" section — publishes ONE list item per monitored site (its URL) as
 * the board hierarchy's entity level (`/settings/sites/<id>`), with the filter
 * toolbar (AutoConfigure + text/platform/status filters) pinned in the level's
 * headerSlot. The leaf edits a single site: the URL it watches, the group it
 * sits under, the deploy project that serves it (via "Set Platform Project"),
 * which DNS record checks run, and how it's polled. Creating a site auto-creates
 * its 1:1 backing row from the URL's host; the environment is derived from that
 * host, not chosen.
 */
export function EndpointsSection({
  groups,
  sites,
  endpoints,
  onChanged,
  selectedId,
  onNavigate,
  load,
}: {
  groups: SiteGroupView[];
  sites: SiteView[];
  endpoints: EndpointView[];
  onChanged: () => Promise<void>;
  /** How the shared config read is doing, so an empty rail can say WHY it is empty. */
  load: RosterLoadState;
  /** URL-selected endpoint id (`/settings/sites/<id>`), owned by the board level. */
  selectedId: string | null;
  onNavigate: (id: string | null) => void;
}): ReactElement {
  const [creating, setCreating] = useState(false);
  const [filter, setFilter] = useState("");
  // Two pop filters over the list, AND-composed with the text filter. Both default to
  // every option selected (= show all) and reuse the shared MultiSelectFilter, so the
  // popover/trigger/row styling matches the Platforms view's status filter exactly.
  // The toggles are useCallbacks because they render inside the PUBLISHED level's
  // headerSlot — a fresh identity per render would rebuild the level every render
  // and ping-pong setState with BoardShell (React #185).
  const [platformFilter, setPlatformFilter] = useState<Set<string>>(allPlatformKeys);
  const [statusFilter, setStatusFilter] = useState<Set<EndpointConfigStatus>>(allStatuses);
  const togglePlatform = useCallback(
    (k: string): void =>
      setPlatformFilter((prev) => {
        const next = new Set(prev);
        if (next.has(k)) next.delete(k);
        else next.add(k);
        return next;
      }),
    [],
  );
  const toggleStatus = useCallback(
    (k: EndpointConfigStatus): void =>
      setStatusFilter((prev) => {
        const next = new Set(prev);
        if (next.has(k)) next.delete(k);
        else next.add(k);
        return next;
      }),
    [],
  );
  const setAllPlatforms = useCallback((all: boolean): void => setPlatformFilter(all ? allPlatformKeys() : new Set()), []);
  const setAllStatuses = useCallback((all: boolean): void => setStatusFilter(all ? allStatuses() : new Set()), []);
  const { busy, error, setError, run } = useEditorMutations();
  const { data: deployData } = useDeployProjects();
  const queryClient = useQueryClient();

  const siteById = (id: string): SiteView | undefined => sites.find((s) => s.id === id);

  const current = !creating && selectedId ? (endpoints.find((e) => e.id === selectedId) ?? null) : null;
  const currentSite = current ? siteById(current.siteId) ?? null : null;

  const { draft, setDraft, discardDraft } = useDraftForSelection<EndpointView, Draft>({
    selectedId,
    current,
    creating,
    initial: () => blankDraft(groups[0]?.id ?? ""),
    load: (e) => draftFromEndpoint(e, siteById(e.siteId)?.groupId ?? groups[0]?.id ?? ""),
  });
  const patch = (p: Partial<Draft>): void => setDraft((d) => ({ ...d, ...p }));

  // The platform filter always offers the known platforms (incl. railway) in a stable
  // order, then any unknown value present, then a "no platform" trailer when any site
  // is unwired — see `platformFilterOptions`.
  const platformOptions = useMemo(() => platformFilterOptions(endpoints), [endpoints]);

  // Publish the (filtered) roster as the hierarchy's entity level; the editor is
  // the leaf. The filter toolbar rides the level's headerSlot, pinned under the
  // level title. Items are computed inside the memo: a site is listed only when
  // it passes ALL three filters — text, platform, and config status; each filter
  // is OR-within (any selected option matches), AND-across. Per-keystroke level
  // republish is event-driven, so it can't loop.
  const level = useMemo<TopicLevel>(() => {
    const needle = filter.trim().toLowerCase();
    const visible = endpoints.filter((e) => {
      const matchesText = !needle || `${e.url} ${groupOfSite(sites, groups, e.siteId)}`.toLowerCase().includes(needle);
      return matchesText && platformFilter.has(e.platform ?? PLATFORM_NONE) && statusFilter.has(endpointConfigStatus(e));
    });
    return {
      id: "roster-sites",
      title: "Sites",
      // Site rows are long (URL + group · env on ONE line) — widen the rail well past
      // the 240px default so the host and its filters both fit. Still drag-resizable.
      width: 440,
      items: visible.map((e) => ({
        id: e.id,
        label: siteUrlLabel(e.url),
        sublabel: `${groupOfSite(sites, groups, e.siteId)} · ${e.environment ?? envOf(e.url)}`,
        icon: platformIcon(e.platform) ?? <Globe size={16} aria-hidden />,
        trailing: endpointUnconfigured(e) ? (
          <span title="no deploy project configured" aria-label="no deploy project configured" className="text-xs text-apt-gold">
            ⚠
          </span>
        ) : undefined,
      })),
      selectedId: creating ? null : selectedId,
      onSelect: (id) => {
        setError(null);
        setCreating(false);
        onNavigate(id);
      },
      onClear: () => {
        setError(null);
        setCreating(false);
        onNavigate(null);
      },
      onNew: () => {
        setError(null);
        setCreating(true);
        discardDraft();
        setDraft(blankDraft(groups[0]?.id ?? ""));
        onNavigate(null);
      },
      newLabel: "New site",
      newActive: creating,
      emptyLabel: endpoints.length === 0 ? rosterEmptyLabel("sites", load) : "Nothing matches.",
      // The nudge is the ONLY thing the package renders beside an empty frontier list,
      // so it is where a failed load has to speak — ConfigPanel's error line sits in the
      // detail pane the nudge replaces.
      overviewHelp: rosterOverviewHelp(load, "Pick a site to edit its URL, group, environment and deploy wiring."),
      // Auto Configure rides the level's TITLE row (next to +), per the shared recipe;
      // the filters get a header row to themselves.
      titleActions: <AutoConfigureButton />,
      // ONE filter header: [platform ▾] [status ▾] [filter text], left-to-right. The
      // text input flex-grows to fill; each filter is a compact pop-menu.
      headerSlot: (
        <div className="flex flex-wrap items-center gap-2 px-2 py-1.5" role="toolbar" aria-label="Site filters">
          <MultiSelectFilter
            popoverLabel="Platform filter"
            triggerNoun="platform"
            options={platformOptions}
            isSelected={(k) => platformFilter.has(k)}
            onToggle={togglePlatform}
            optionAriaLabel={(label) => `platform ${label}`}
            onSetAll={setAllPlatforms}
            allAriaLabel="all platforms"
            menuMinWidth={160}
            disabled={platformOptions.length === 0}
          />
          <MultiSelectFilter
            popoverLabel="Configured filter"
            triggerNoun="status"
            options={STATUS_OPTS}
            isSelected={(k) => statusFilter.has(k as EndpointConfigStatus)}
            onToggle={(k) => toggleStatus(k as EndpointConfigStatus)}
            optionAriaLabel={(label) => `status ${label}`}
            onSetAll={setAllStatuses}
            allAriaLabel="all statuses"
            menuMinWidth={160}
          />
          <Input
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            placeholder={`Filter ${endpoints.length} sites…`}
            aria-label="Filter sites"
            // Focuses whenever the list opens (the input re-mounts each time the entity
            // level re-enters the stack); a keystroke republish reuses the same element,
            // so it never steals focus.
            autoFocus
            className="h-8 min-w-0 flex-1 text-[0.8rem]"
          />
        </div>
      ),
    };
  }, [
    endpoints,
    sites,
    groups,
    filter,
    platformFilter,
    statusFilter,
    platformOptions,
    load,
    selectedId,
    creating,
    onNavigate,
    setError,
    setDraft,
    discardDraft,
    togglePlatform,
    toggleStatus,
    setAllPlatforms,
    setAllStatuses,
  ]);
  useSettingsEntityLevel(level);

  const derivedEnv = envOf(draft.url);

  // The wiring/polling fields written by both create and update. `environment` is
  // derived from the URL (never hand-entered); a NEW site is a plain HTTP check, but
  // an EDIT preserves the row's existing `kind` so toggling an unrelated field never
  // silently downgrades a legacy health/admin/custom endpoint to `http` (which would
  // drop its health-JSON probe and flip its "unconfigured" warning on).
  const writeFields = (env: string, kind: string): Partial<Omit<EndpointView, "id" | "siteId">> => ({
    kind,
    environment: env,
    platform: draft.platform,
    deployProject: draft.deployProject,
    ignoreProjectWarning: draft.ignoreProjectWarning,
    expectedStatus: draft.expectedStatus,
    expectBody: draft.expectBody,
    dnsCheckA: draft.dnsCheckA,
    dnsCheckAaaa: draft.dnsCheckAaaa,
    dnsCheckCname: draft.dnsCheckCname,
    checkIntervalSeconds: draft.checkIntervalSeconds,
    isActive: draft.isActive,
  });

  // Dirty: a new site needs a real URL + a group; an existing one needs a changed
  // field or a group move.
  const endpointChanged =
    !!current &&
    (draft.url !== current.url ||
      draft.platform !== current.platform ||
      draft.deployProject !== current.deployProject ||
      draft.ignoreProjectWarning !== current.ignoreProjectWarning ||
      draft.expectedStatus !== current.expectedStatus ||
      draft.expectBody !== current.expectBody ||
      draft.dnsCheckA !== current.dnsCheckA ||
      draft.dnsCheckAaaa !== current.dnsCheckAaaa ||
      draft.dnsCheckCname !== current.dnsCheckCname ||
      draft.checkIntervalSeconds !== current.checkIntervalSeconds ||
      draft.isActive !== current.isActive);
  const groupChanged = !!currentSite && draft.groupId !== currentSite.groupId;
  const dirty = creating
    ? draft.url.trim() !== "" && draft.url.trim() !== "https://" && draft.groupId !== ""
    : endpointChanged || groupChanged;

  function save(): void {
    void run(async () => {
      const url = draft.url.trim();
      const host = hostOf(url);
      const env = envOf(url) || "production";
      if (creating) {
        // Each monitored site is 1:1 with its URL — create its backing site row from
        // the host (its DNS name), then the endpoint under it.
        const site = await api.createSite({ name: host, slug: slugify(host), groupId: draft.groupId });
        const created = await api.createEndpoint(site.id, { url, ...writeFields(env, KIND) });
        await onChanged();
        // Navigating to the created id hydrates the draft from the REAL created
        // row (its resolved ids) via the render-phase load, NOT the stale props.
        setCreating(false);
        onNavigate(created.id);
      } else if (current && currentSite) {
        // Keep the 1:1 site row in step with its URL/group, but only rename a site
        // that this endpoint solely owns — never clobber a legacy site that still
        // stacks several endpoints.
        const onlyEndpoint = endpoints.filter((e) => e.siteId === current.siteId).length === 1;
        const sitePatch: { name?: string; slug?: string; groupId?: string } = {};
        if (draft.groupId && draft.groupId !== currentSite.groupId) sitePatch.groupId = draft.groupId;
        if (onlyEndpoint && currentSite.name !== host) {
          sitePatch.name = host;
          sitePatch.slug = slugify(host);
        }
        if (Object.keys(sitePatch).length > 0) await api.updateSite(current.siteId, sitePatch);
        await api.updateEndpoint(current.id, { url, ...writeFields(env, current.kind) });
        await onChanged();
      }
    });
  }

  function del(): void {
    if (!current) return;
    void run(async () => {
      // The backend deletes the endpoint and, atomically, its site when that leaves
      // the site empty (1:1 site→endpoint is the norm; multi-endpoint sites keep their
      // remaining endpoints). Decided server-side from fresh state, so a stale client
      // endpoint list can't cascade-delete a healthy sibling.
      await api.deleteEndpoint(current.id);
      await onChanged();
      // The backend purged the retired endpoint's history/issues in-request, but the
      // board's ["live"] cache still holds them — refetch the live snapshot so
      // Activity/Problems drop the gone site now, not on the next (up to 60s) poll.
      void queryClient.refetchQueries({ queryKey: ["live"] });
      onNavigate(null);
    });
  }

  // The editor's live warning reflects the DRAFT, so wiring / unchecking "Automatically
  // Configure" / switching monitoring off hide it immediately — through the SAME
  // classifier every other surface uses, never a second rule written out here.
  const draftUnconfigured = endpointUnconfigured({
    kind: KIND,
    ignoreProjectWarning: draft.ignoreProjectWarning,
    isActive: draft.isActive,
    platform: draft.platform,
    deployProject: draft.deployProject,
  });
  // Missing wiring, regardless of whether anyone is being warned about it — what makes
  // the "why isn't this flagged?" reason worth stating.
  const wiringGap = !draft.platform || !draft.deployProject;

  // The wired project's live domain (for the read-only project link), matched from
  // the deploy-projects snapshot by canonical platform + name.
  const wiredProject =
    draft.platform && draft.deployProject
      ? (deployData?.projects ?? []).find((p) => platformCanon(p.platform) === draft.platform && p.projectName === draft.deployProject) ?? null
      : null;

  if (!creating && !current) {
    return <SectionPlaceholder>Select a site to edit, or add a new one.</SectionPlaceholder>;
  }
  return (
    <EntityEditorShell
      onCancel={() => {
        setError(null);
        setCreating(false);
        discardDraft();
        onNavigate(null);
      }}
      onSave={save}
      canSave={dirty && !busy}
      saving={busy}
      onDelete={del}
      canDelete={current !== null}
      deleteConfirm={current ? { title: `Delete the site "${siteUrlLabel(current.url)}"?` } : null}
      error={error}
    >
      <div className="flex max-w-2xl flex-col gap-3 p-4">
        <FieldGroup title="Config">
          <Field label="URL">
            <Input value={draft.url} onChange={(e) => patch({ url: e.target.value })} placeholder="https://example.com" aria-label="URL" />
          </Field>

          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <Field label="Group">
              <Select value={draft.groupId} onChange={(e) => patch({ groupId: e.target.value })} aria-label="Group">
                {groups.length === 0 && <option value="">— no groups —</option>}
                {groups.map((g) => (
                  <option key={g.id} value={g.id}>{g.name}</option>
                ))}
              </Select>
            </Field>
            <Field label="Environment">
              <div
                aria-label="Environment (inferred from URL)"
                className="flex min-h-9 items-center gap-2 rounded-md border border-apt-border bg-apt-surface px-3 py-2 font-mono text-[0.8rem] text-apt-text"
              >
                {derivedEnv || "—"}
                <span className="text-[0.68rem] text-apt-text-dim">— inferred from the URL</span>
              </div>
            </Field>
          </div>

          {/* The site's MASTER switch, deliberately here rather than beside the poll
              settings: everything below — DNS checks, polling, the health check — is a
              detail of monitoring that only happens while this is on. It was previously
              the last row of "Polling" ("Active — health-check this site"), which read as
              one poll option among several when it in fact governs all of them, and left
              no place to say what a paused site is exempt from. Off = paused, NOT
              unconfigured: the site keeps its wiring, its deploy project stays claimed,
              and Auto Configure leaves it alone in both directions. */}
          <Label className="flex items-start gap-2">
            <Checkbox
              checked={draft.isActive}
              onCheckedChange={(checked) => patch({ isActive: checked === true })}
              aria-label="Monitoring enabled"
              className="mt-0.5"
            />
            <span className="flex flex-col gap-0.5">
              <span className="font-mono text-[0.8rem] text-apt-text-muted">Monitoring enabled</span>
              <span className="font-mono text-[0.7rem] leading-snug text-apt-text-dim">
                Off — this site is paused: no checks run, and Auto Configure ignores it (its platform project stays claimed).
              </span>
            </span>
          </Label>
        </FieldGroup>

        {/* Deploy-project wiring — read-only display + the picker + an ignore toggle. */}
        <FieldGroup
          title="Platform project"
          trailing={
            draftUnconfigured ? (
              <span className="flex items-center gap-1 font-mono text-[0.7rem] text-apt-orange">
                <TriangleAlert className="size-3.5" aria-label="no deploy project configured" /> not configured
              </span>
            ) : wiringGap ? (
              // Unwired but NOT flagged — say which opt-out silenced it. "Nothing is
              // wrong here" and "you switched this off" look identical otherwise, and
              // that is precisely the gap an operator can't diagnose from the card.
              <span className="font-mono text-[0.7rem] text-apt-text-muted">
                {draft.isActive ? "not auto-configured" : "monitoring off"}
              </span>
            ) : undefined
          }
        >
          <Field label="Project">
            {draft.deployProject ? (
              <div className="flex min-h-9 flex-wrap items-center gap-2 rounded-md border border-apt-border bg-apt-surface px-3 py-2 font-mono text-[0.8rem]">
                {wiredProject?.domain ? (
                  <a href={`https://${wiredProject.domain}`} target="_blank" rel="noreferrer" className="break-all text-apt-blue no-underline hover:underline">
                    {draft.deployProject}
                  </a>
                ) : (
                  <span className="break-all text-apt-text">{draft.deployProject}</span>
                )}
                {draft.platform && (
                  <span className="rounded border border-apt-border px-1.5 py-0.5 text-[0.6rem] uppercase tracking-[0.05em] text-apt-text-muted">
                    {platformLabel(draft.platform)}
                  </span>
                )}
              </div>
            ) : (
              <div className="flex min-h-9 items-center rounded-md border border-dashed border-apt-border bg-apt-surface px-3 py-2 font-mono text-[0.8rem] text-apt-text-dim">
                No platform project set.
              </div>
            )}
          </Field>
          <div className="flex flex-wrap items-center gap-2">
            <ProjectBrowser
              endpoint={{ url: draft.url, environment: derivedEnv }}
              onPick={(platform, project) => patch({ platform, deployProject: project })}
            />
            {draft.deployProject && (
              <Button type="button" variant="ghost" size="sm" onClick={() => patch({ platform: null, deployProject: null })}>
                Clear
              </Button>
            )}
          </div>
          {/* Was an "Ignore" / "Restore warning" button, whose label named the SIDE EFFECT
              (a warning appearing) rather than the setting, and whose two captions read as
              two different controls. It is one persistent choice — whether Auto Configure
              may look at this site — so it is one checkbox, stated positively and showing
              its current value at rest. Checked ⇔ `ignoreProjectWarning` false. Inert while
              monitoring is off (a paused site is out of the conversation either way), so
              disabled rather than left there looking effective. */}
          <Label className="flex items-start gap-2">
            <Checkbox
              checked={!draft.ignoreProjectWarning}
              onCheckedChange={(checked) => patch({ ignoreProjectWarning: checked !== true })}
              disabled={!draft.isActive}
              aria-label="Automatically Configure"
              className="mt-0.5"
            />
            <span className="flex flex-col gap-0.5">
              <span className={cn("font-mono text-[0.8rem]", draft.isActive ? "text-apt-text-muted" : "text-apt-text-dim")}>
                Automatically Configure
              </span>
              <span className="font-mono text-[0.7rem] leading-snug text-apt-text-dim">
                {draft.isActive
                  ? "Let Auto Configure wire this site to the platform project serving it, and warn while it has none."
                  : "Monitoring is off — Auto Configure already ignores this site."}
              </span>
            </span>
          </Label>
        </FieldGroup>

        {/* DNS checks — which record types the probe resolves to confirm the host is live. */}
        <FieldGroup
          title="DNS checks"
          trailing={
            // "Monitoring enabled" governs this section, so say so where the settings are:
            // switches left in their ON position with nothing running behind them are the
            // exact confusion the master switch was moved up to Config to end.
            !draft.isActive ? (
              <span className="font-mono text-[0.7rem] text-apt-text-muted">monitoring off</span>
            ) : !draft.dnsCheckA && !draft.dnsCheckAaaa && !draft.dnsCheckCname ? (
              <span className="font-mono text-[0.7rem] text-apt-text-muted">resolution check off</span>
            ) : undefined
          }
        >
          <p className="font-mono text-[0.7rem] leading-snug text-apt-text-dim">
            The host passes DNS if it resolves via any enabled record type. Turn all off to skip the DNS check.
          </p>
          <div className="flex flex-col gap-2.5">
            <Label className="flex items-center gap-2">
              <Switch checked={draft.dnsCheckA} onCheckedChange={(checked) => patch({ dnsCheckA: checked })} aria-label="Check A record" />
              <span className="font-mono text-[0.8rem] text-apt-text-muted">A record <span className="text-apt-text-dim">(IPv4)</span></span>
            </Label>
            <Label className="flex items-center gap-2">
              <Switch checked={draft.dnsCheckAaaa} onCheckedChange={(checked) => patch({ dnsCheckAaaa: checked })} aria-label="Check AAAA record" />
              <span className="font-mono text-[0.8rem] text-apt-text-muted">AAAA record <span className="text-apt-text-dim">(IPv6)</span></span>
            </Label>
            <Label className="flex items-center gap-2">
              <Switch checked={draft.dnsCheckCname} onCheckedChange={(checked) => patch({ dnsCheckCname: checked })} aria-label="Check CNAME record" />
              <span className="font-mono text-[0.8rem] text-apt-text-muted">CNAME record</span>
            </Label>
          </div>
        </FieldGroup>

        <FieldGroup
          title="Polling"
          trailing={!draft.isActive ? <span className="font-mono text-[0.7rem] text-apt-text-muted">monitoring off</span> : undefined}
        >
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <Field label="Expected status">
              <Input type="number" value={draft.expectedStatus} onChange={(e) => patch({ expectedStatus: Number(e.target.value) || 0 })} aria-label="Expected status" />
            </Field>
            <Field label="Check interval (seconds)">
              <Input type="number" value={draft.checkIntervalSeconds} onChange={(e) => patch({ checkIntervalSeconds: Number(e.target.value) || 0 })} aria-label="Check interval" />
            </Field>
            <Field label="Expect body contains (optional)">
              <Input value={draft.expectBody ?? ""} placeholder="e.g. a string the page must contain" onChange={(e) => patch({ expectBody: e.target.value || null })} aria-label="Expect body contains" />
            </Field>
          </div>
          {/* No "Active" toggle here any more — it was the same `isActive` field as
              Config ▸ "Monitoring enabled", which governs this whole section. */}
        </FieldGroup>
      </div>
    </EntityEditorShell>
  );
}
