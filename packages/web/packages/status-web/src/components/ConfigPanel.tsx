"use client";
import { type ReactElement, useCallback, useEffect, useMemo, useState } from "react";
import { Cloud, Folder, RefreshCw } from "lucide-react";
import { useQueryClient } from "@tanstack/react-query";
import {
  readStoredAppearance,
  writeStoredAppearance,
  type ReduceMotionPref,
} from "@agentic-toolkit/themes/appearance";
import { Input } from "@agentic-toolkit/ui/components/input";
import { Select } from "@agentic-toolkit/ui/components/select";
import { Switch } from "@agentic-toolkit/ui/components/switch";
import { Label } from "@agentic-toolkit/ui/components/label";
import { Badge } from "@agentic-toolkit/ui/components/badge";
import { Field, ListHeader, type TopicLevel } from "@agentic-toolkit/ui/blocks";
import * as api from "../api/monitored-sites";
import { PLATFORMS, type SiteGroupView, type SiteView, type IntegrationView, type EndpointView } from "../api/monitored-sites";
import { slugify } from "../lib/slug";
import { plural } from "../lib/format";
import { msg } from "../lib/err";
import { useConfigStatus } from "../hooks/use-config-status";
import { armFreshDeployProjectsFetch } from "../hooks/use-deploy-projects";
import { AutoConfigureButton } from "./AutoConfigureButton";
import { type RosterTopic } from "./board-views";
import { useSettingsEntityLevel } from "./settings-level";
import { platformCanon } from "../lib/deploy-view";
import { platformIcon } from "../lib/platform-icon";
import { EndpointsSection } from "./configure/EndpointsSection";
import { PlatformProjects } from "./configure/PlatformProjects";
import { UsersSection } from "./configure/UsersSection";
import { TokensSection } from "./configure/TokensSection";
import { PeersSection } from "./configure/PeersSection";
import { useEditorMutations } from "./configure/use-editor-mutations";
import { useDraftForSelection } from "./configure/use-draft-for-selection";
import {
  EntityEditorShell,
  SectionErrorText,
  SectionPlaceholder,
  rosterEmptyLabel,
  rosterOverviewHelp,
  type RosterLoadState,
} from "./configure/section-chrome";

const NO_GROUPS: SiteGroupView[] = [];
const NO_SITES: SiteView[] = [];
const NO_INTEGRATIONS: IntegrationView[] = [];
const NO_ENDPOINTS: EndpointView[] = [];

// Blank drafts (module scope so the published levels' useMemos can call them
// from onNew without taking an unstable render-scoped function as a dep).
const blankGroup = (): { name: string; slug: string; retentionDays: number } => ({ name: "", slug: "", retentionDays: 90 });
const blankIntegration = (): { platform: string; label: string; teamId: string; accountId: string; tokenEnvVar: string; isActive: boolean } => ({
  platform: "vercel",
  label: "",
  teamId: "",
  accountId: "",
  tokenEnvVar: "",
  isActive: true,
});

// ── Groups ──────────────────────────────────────────────────────────────────
function GroupsSection({
  groups,
  onChanged,
  selectedId,
  onNavigate,
  load,
}: {
  groups: SiteGroupView[];
  onChanged: () => Promise<void>;
  /** How the shared config read is doing, so an empty rail can say WHY it is empty. */
  load: RosterLoadState;
  /** URL-selected group id (`/settings/groups/<id>`), owned by the board level. */
  selectedId: string | null;
  onNavigate: (id: string | null) => void;
}): ReactElement {
  const [creating, setCreating] = useState(false);
  const { busy, error, setError, run } = useEditorMutations();
  const queryClient = useQueryClient();

  const current = !creating && selectedId ? (groups.find((g) => g.id === selectedId) ?? null) : null;

  const { draft, setDraft, discardDraft } = useDraftForSelection({
    selectedId,
    current,
    creating,
    initial: blankGroup,
    load: (g) => ({ name: g.name, slug: g.slug, retentionDays: g.retentionDays }),
  });

  const dirty = creating
    ? draft.name.trim() !== "" || draft.slug.trim() !== ""
    : !!current && (draft.name !== current.name || draft.slug !== current.slug || draft.retentionDays !== current.retentionDays);

  function save(): void {
    const body = { name: draft.name.trim(), slug: draft.slug.trim() || slugify(draft.name), retentionDays: draft.retentionDays };
    void run(async () => {
      if (creating) {
        const g = await api.createGroup(body);
        await onChanged();
        setCreating(false);
        onNavigate(g.id);
      } else if (current) {
        await api.updateGroup(current.id, body);
        await onChanged();
      }
    });
  }
  function del(): void {
    if (!current) return;
    void run(async () => {
      await api.deleteGroup(current.id);
      await onChanged();
      // The backend purged every deleted-group endpoint's history/issues in-request; the
      // board's ["live"] cache still holds them — refetch so Activity/Problems drop the
      // gone sites now, not on the next (up to 60s) poll.
      void queryClient.refetchQueries({ queryKey: ["live"] });
      onNavigate(null);
    });
  }

  // Publish the roster as the hierarchy's entity level; the editor is the leaf.
  const level = useMemo<TopicLevel>(
    () => ({
      id: "roster-groups",
      title: "Groups",
      items: groups.map((g) => ({
        id: g.id,
        label: g.name,
        sublabel: `${g.slug} · ${g.retentionDays}d`,
        icon: <Folder size={16} aria-hidden />,
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
        setDraft(blankGroup());
        onNavigate(null);
      },
      newLabel: "New group",
      newActive: creating,
      emptyLabel: rosterEmptyLabel("groups", load),
      overviewHelp: rosterOverviewHelp(load, "Pick a group to edit its name and retention window."),
    }),
    [groups, load, selectedId, creating, onNavigate, setError, setDraft, discardDraft],
  );
  useSettingsEntityLevel(level);

  if (!creating && !current) {
    return <SectionPlaceholder>Select a group to edit, or create a new one.</SectionPlaceholder>;
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
      deleteConfirm={
        current
          ? {
              title: `Delete group "${current.name}"?`,
              description: "All of its sites and endpoints are deleted with it.",
            }
          : null
      }
      error={error}
    >
      <div className="flex max-w-md flex-col gap-3 p-4">
        <Field label="Name">
          <Input value={draft.name} onChange={(e) => setDraft((d) => ({ ...d, name: e.target.value }))} aria-label="Group name" />
        </Field>
        <Field label="Slug">
          <Input value={draft.slug} placeholder={slugify(draft.name)} onChange={(e) => setDraft((d) => ({ ...d, slug: e.target.value }))} aria-label="Group slug" />
        </Field>
        <Field label="Retention (days)" className="max-w-40">
          <Input type="number" value={draft.retentionDays} onChange={(e) => setDraft((d) => ({ ...d, retentionDays: Number(e.target.value) || 0 }))} aria-label="Retention days" />
        </Field>
      </div>
    </EntityEditorShell>
  );
}

// ── Platforms (deploy integrations) ─────────────────────────────────────────
function PlatformsSection({
  integrations,
  onChanged,
  unmonitoredByPlatform,
  selectedId,
  onNavigate,
  load,
}: {
  integrations: IntegrationView[];
  onChanged: () => Promise<void>;
  /** How the shared config read is doing, so an empty rail can say WHY it is empty. */
  load: RosterLoadState;
  unmonitoredByPlatform: Map<string, number>;
  /** URL-selected integration id (`/settings/platforms/<id>`), owned by the board level. */
  selectedId: string | null;
  onNavigate: (id: string | null) => void;
}): ReactElement {
  const qc = useQueryClient();
  const [creating, setCreating] = useState(false);
  const [rosterFilter, setRosterFilter] = useState("");
  const [refreshing, setRefreshing] = useState(false);
  // The refresh button lives in the always-visible roster headerSlot, so its errors get
  // their OWN surface there (below) — not the editor channel, which only mounts once a row
  // is selected/being created and would swallow a failure clicked with nothing selected.
  const [refreshError, setRefreshError] = useState<string | null>(null);
  const { busy, error, setError, run } = useEditorMutations();
  // Arm the deploy-projects latch, then let `onChanged` (reload) invalidate the query: the
  // always-mounted observer refetches ONCE with `?fresh=1` through React Query — no manual
  // cache seed, no redundant non-fresh refetch racing it. Surface a failure through the
  // header's own `refreshError` line, keeping the spinner in `refreshing`.
  async function refreshProjects(): Promise<void> {
    setRefreshing(true);
    setRefreshError(null);
    try {
      armFreshDeployProjectsFetch();
      await onChanged();
      // `onChanged` (reload) never rejects — invalidateQueries swallows query-fn errors and
      // refetch resolves with an error result — so read the query state directly to surface
      // a failed deploy-projects re-read (the fresh latch stays armed for the retry).
      const dp = qc.getQueryState(["deploy-projects"]);
      if (dp?.status === "error") throw dp.error ?? new Error("deploy-projects refresh failed");
      // `reload`'s other half — refetch() re-reads `["configure-data"]` (the integrations
      // roster this button refreshes) but resolves with an error RESULT rather than rejecting,
      // so surface a failed integrations re-read the same way.
      const cd = qc.getQueryState(["configure-data"]);
      if (cd?.status === "error") throw cd.error ?? new Error("configuration refresh failed");
    } catch (e) {
      setRefreshError(msg(e));
    } finally {
      setRefreshing(false);
    }
  }

  const current = !creating && selectedId ? (integrations.find((i) => i.id === selectedId) ?? null) : null;

  const { draft, setDraft, discardDraft } = useDraftForSelection({
    selectedId,
    current,
    creating,
    initial: blankIntegration,
    load: (i) => ({
      platform: i.platform,
      label: i.label,
      teamId: String(i.config?.teamId ?? ""),
      accountId: String(i.config?.accountId ?? ""),
      tokenEnvVar: i.tokenEnvVar ?? "",
      isActive: i.isActive,
    }),
  });

  const dirty = creating
    ? draft.label.trim() !== ""
    : !!current &&
      (draft.platform !== current.platform ||
        draft.label !== current.label ||
        draft.tokenEnvVar !== (current.tokenEnvVar ?? "") ||
        draft.isActive !== current.isActive ||
        draft.teamId !== String(current.config?.teamId ?? "") ||
        draft.accountId !== String(current.config?.accountId ?? ""));

  function buildConfig(): Record<string, unknown> {
    if (draft.platform === "vercel") return { teamId: draft.teamId || null };
    if (draft.platform === "cloudflare") return { accountId: draft.accountId || null };
    return {};
  }
  function save(): void {
    const body = { platform: draft.platform, label: draft.label.trim(), config: buildConfig(), tokenEnvVar: draft.tokenEnvVar || null, isActive: draft.isActive };
    void run(async () => {
      if (creating) {
        const i = await api.createIntegration(body);
        await onChanged();
        setCreating(false);
        onNavigate(i.id);
      } else if (current) {
        await api.updateIntegration(current.id, body);
        await onChanged();
      }
    });
  }
  function del(): void {
    if (!current) return;
    void run(async () => {
      await api.deleteIntegration(current.id);
      await onChanged();
      onNavigate(null);
    });
  }

  // Publish the roster as the hierarchy's entity level; the editor is the leaf.
  // Each row keeps its ⚠ N badge = unmonitored deploy projects, from the shared
  // model's per-platform tally (keyed by canonical platform). Passed down from
  // ConfigPanel's one useConfigStatus() — memoized on query data there, so it's
  // an identity-stable useMemo dep.
  const level = useMemo<TopicLevel>(
    () => {
      const needle = rosterFilter.trim().toLowerCase();
      const visible = integrations.filter((i) => !needle || `${i.label} ${i.platform}`.toLowerCase().includes(needle));
      return {
        id: "roster-platforms",
        title: "Platforms",
        items: visible.map((i) => {
          const unconfigured = unmonitoredByPlatform.get(platformCanon(i.platform)) ?? 0;
          const warnTitle = `${plural(unconfigured, "project site")} not yet monitored`;
          return {
            id: i.id,
            label: i.label,
            sublabel: `${i.platform}${i.isActive ? "" : " · off"}`,
            icon: platformIcon(i.platform) ?? <Cloud size={16} aria-hidden />,
            trailing:
              unconfigured > 0 ? (
                <Badge variant="accent" title={warnTitle} aria-label={warnTitle}>
                  ⚠ {unconfigured}
                </Badge>
              ) : undefined,
          };
        }),
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
          setDraft(blankIntegration());
          onNavigate(null);
        },
        newLabel: "New platform",
        newActive: creating,
        emptyLabel: integrations.length === 0 ? rosterEmptyLabel("platforms", load) : "Nothing matches.",
        overviewHelp: rosterOverviewHelp(load, "Pick a platform to edit its credentials and monitored projects."),
        // Auto-configure lives in the headerSlot (not titleActions: the HMDV level
        // header centers the title under titleActions and the two overlap on this
        // narrow level) on its own row (not in the ListHeader actions row, which is
        // too narrow to share with the search field).
        headerSlot: (
          <>
            <ListHeader
              ariaLabel="Platform filters"
              search={{ value: rosterFilter, onChange: setRosterFilter, placeholder: "Filter platforms…", grow: true }}
              actions={
                <button
                  type="button"
                  className="rounded border border-apt-border px-1.5 py-1 text-apt-text-muted hover:text-apt-text disabled:opacity-50"
                  title="Refresh platform projects"
                  aria-label="Refresh platform projects"
                  disabled={refreshing}
                  onClick={() => void refreshProjects()}
                >
                  <RefreshCw size={14} aria-hidden className={refreshing ? "animate-spin" : undefined} />
                </button>
              }
            />
            <AutoConfigureButton className="w-full" />
            {refreshError && <SectionErrorText>{refreshError}</SectionErrorText>}
          </>
        ),
      };
    },
    [integrations, load, unmonitoredByPlatform, selectedId, creating, onNavigate, setError, setDraft, discardDraft, rosterFilter, refreshing, refreshError],
  );
  useSettingsEntityLevel(level);

  if (!creating && !current) {
    return <SectionPlaceholder>Select a platform integration to edit, or create a new one.</SectionPlaceholder>;
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
      deleteConfirm={current ? { title: `Delete the ${current.platform} integration "${current.label}"?` } : null}
      error={error}
    >
      <div className="flex h-full min-h-0 flex-col gap-3 p-4">
        <div className="flex max-w-xl shrink-0 flex-col gap-3">
          <Field label="Platform">
            <Select value={draft.platform} onChange={(e) => setDraft((d) => ({ ...d, platform: e.target.value }))} aria-label="Platform">
              {PLATFORMS.map((p) => (
                <option key={p} value={p}>{p}</option>
              ))}
            </Select>
          </Field>
          <Field label="Label">
            <Input value={draft.label} onChange={(e) => setDraft((d) => ({ ...d, label: e.target.value }))} aria-label="Label" />
          </Field>
          {draft.platform === "vercel" && (
            <Field label="Team ID">
              <Input value={draft.teamId} onChange={(e) => setDraft((d) => ({ ...d, teamId: e.target.value }))} aria-label="Team ID" />
            </Field>
          )}
          {draft.platform === "cloudflare" && (
            <Field label="Account ID">
              <Input value={draft.accountId} onChange={(e) => setDraft((d) => ({ ...d, accountId: e.target.value }))} aria-label="Account ID" />
            </Field>
          )}
          <Field label="API token — env var (secret; not stored in the DB while unauthenticated)">
            <Input value={draft.tokenEnvVar} placeholder="e.g. VERCEL_API_TOKEN" onChange={(e) => setDraft((d) => ({ ...d, tokenEnvVar: e.target.value }))} aria-label="Token env var" />
          </Field>
          <Label className="flex items-center gap-2">
            <Switch checked={draft.isActive} onCheckedChange={(checked) => setDraft((d) => ({ ...d, isActive: checked }))} />
            <span className="font-mono text-[0.8rem] text-apt-text-muted">Active</span>
          </Label>
        </div>
        {/* The platform's projects — wire (Add) or exempt (Ignore) the ones not yet monitored.
            Keyed by platform so switching the Platform select remounts it (resetting its
            own busy/error state) instead of carrying a stale in-flight state across. */}
        <PlatformProjects key={draft.platform} platform={draft.platform} onChanged={onChanged} />
      </div>
    </EntityEditorShell>
  );
}

// ── Appearance ────────────────────────────────────────────────────────────────

/** Apply the reduce-motion preference to <html>: `auto` leaves the attribute off
 *  (nothing gated — this site deliberately ignores the OS media query), `on`/`off`
 *  pin it. Shared storage (`adh:appearance`) + attribute contract with the
 *  toolkit themes, so the hub's Appearance settings and this toggle agree. */
function applyReduceMotion(value: ReduceMotionPref): void {
  if (value === "auto") delete document.documentElement.dataset.reduceMotion;
  else document.documentElement.dataset.reduceMotion = value;
}

export function AppearanceSection({ fontScale, onFontScaleChange }: { fontScale: number; onFontScaleChange: (value: number) => void }): ReactElement {
  const [reduceMotion, setReduceMotion] = useState<ReduceMotionPref>(() =>
    typeof window === "undefined" ? "auto" : readStoredAppearance().reduceMotion,
  );
  useEffect(() => {
    applyReduceMotion(reduceMotion);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- apply the stored pref once on mount
  }, []);
  function onReduceMotionChange(value: ReduceMotionPref): void {
    setReduceMotion(value);
    writeStoredAppearance({ ...readStoredAppearance(), reduceMotion: value });
    applyReduceMotion(value);
  }
  return (
    <div className="flex min-h-0 flex-1 flex-col gap-5 p-4">
      <div>
        <h2 className="font-mono text-sm font-semibold text-apt-text">Appearance</h2>
        <p className="mt-0.5 font-mono text-[12px] text-apt-text-muted">Display preferences for this wallboard, stored in your browser.</p>
      </div>
      <div className="max-w-[360px]">
        <div className="mb-1.5 flex items-baseline justify-between">
          <span className="font-mono text-[12.5px] text-apt-text">Font size</span>
          <span className="font-mono text-[11px] text-apt-text-muted">{Math.round(fontScale * 100)}%</span>
        </div>
        <input
          className="adh-range"
          type="range"
          min={0.8}
          max={1.5}
          step={0.05}
          value={fontScale}
          aria-label="Font size"
          onChange={(e) => onFontScaleChange(parseFloat(e.target.value))}
          style={{ width: "100%" }}
        />
      </div>
      <div className="max-w-[360px]">
        <div className="mb-1.5 flex items-baseline justify-between">
          <span className="font-mono text-[12.5px] text-apt-text">Reduce animation</span>
        </div>
        <select
          className="w-full rounded border border-apt-border bg-apt-bg px-2 py-1 font-mono text-[12.5px] text-apt-text"
          value={reduceMotion}
          aria-label="Reduce animation"
          onChange={(e) => onReduceMotionChange(e.target.value as ReduceMotionPref)}
        >
          <option value="auto">Auto</option>
          <option value="on">On — skip animations</option>
          <option value="off">Off — always animate</option>
        </select>
        <p className="mt-1 font-mono text-[11px] text-apt-text-muted">
          On skips hide/show animations (e.g. the details-pane disclosure).
        </p>
      </div>
    </div>
  );
}

/**
 * The config-roster leaf pane. Roster NAVIGATION lives in the board hierarchy — the
 * rosters are SECTIONS under the Settings topic (the 2nd level), and each roster
 * publishes its ENTITY LIST as the 3rd level (deep-linked at `/settings/<section>/<id>`) —
 * so this panel renders just the ACTIVE roster's leaf (the entity editor). Data comes from
 * one ["configure-data"] query; mutations call `reload` to refetch it (+ the
 * deploy-projects aggregate the warnings use). Appearance is NOT here — it's the one
 * non-roster Settings section, rendered directly by BoardShell.
 */
export function ConfigPanel({
  active,
  section,
  entityId,
  onNavigateEntity,
}: {
  active: boolean;
  /** The URL-selected roster section (role-validated by BoardShell), or null for none. */
  section: RosterTopic | null;
  /** The URL-selected entity id (`/settings/<section>/<id>`), or null. */
  entityId: string | null;
  /** Navigate the entity segment (null clears it). */
  onNavigateEntity: (id: string | null) => void;
}): ReactElement {
  // While the pane is hidden (KeptPane keeps it mounted off a roster section), keep the
  // LAST roster rendered so its unsaved draft survives the round trip — the reason this
  // pane is kept mounted at all. Render-phase derived state.
  const [lastSection, setLastSection] = useState<RosterTopic | null>(null);
  if (section !== null && section !== lastSection) setLastSection(section);
  const activeSection = active ? section : lastSection;

  const { status, configure: data, error, isLoading, refetch } = useConfigStatus();
  // STABLE empty fallbacks — a fresh `[]` per render would churn the identity of
  // the published entity level (its useMemo deps) every render while the config
  // query loads, ping-ponging setState with BoardShell (React #185).
  const groups: SiteGroupView[] = data?.groups ?? NO_GROUPS;
  const sites: SiteView[] = data?.sites ?? NO_SITES;
  const integrations: IntegrationView[] = data?.integrations ?? NO_INTEGRATIONS;
  const endpoints: EndpointView[] = data?.endpoints ?? NO_ENDPOINTS;
  const err = error instanceof Error ? error.message : error ? "Failed to load config." : null;
  // ONE load state for every roster: the rail is the only surface a user can see while
  // nothing is selected, so it — not just the (nudge-covered) detail pane — has to carry
  // the verdict. See `rosterEmptyLabel`.
  // Memoized: the rosters publish their level from a `useMemo` that now depends on this,
  // and a fresh object per render would churn the level's identity every render — the
  // setState ping-pong with BoardShell (React #185) the stable `NO_*` fallbacks above
  // exist to avoid.
  const load: RosterLoadState = useMemo(() => ({ error: err, isLoading }), [err, isLoading]);
  const queryClient = useQueryClient();
  // Deleting a group/site cascades its endpoints, which can drop a project's only
  // wiring → the Platforms ✓ + Overview banner must refresh too.
  const reload = useCallback(async (): Promise<void> => {
    await Promise.all([refetch(), queryClient.invalidateQueries({ queryKey: ["deploy-projects"] })]);
  }, [refetch, queryClient]);

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      {err && <SectionErrorText>{err}</SectionErrorText>}
      {activeSection === null && <SectionPlaceholder>Select a section from the list.</SectionPlaceholder>}
      {activeSection === "groups" && <GroupsSection groups={groups} load={load} onChanged={reload} selectedId={entityId} onNavigate={onNavigateEntity} />}
      {activeSection === "sites" && <EndpointsSection groups={groups} sites={sites} endpoints={endpoints} load={load} onChanged={reload} selectedId={entityId} onNavigate={onNavigateEntity} />}
      {activeSection === "platforms" && <PlatformsSection integrations={integrations} load={load} onChanged={reload} unmonitoredByPlatform={status.unmonitoredByPlatform} selectedId={entityId} onNavigate={onNavigateEntity} />}
      {activeSection === "peers" && <PeersSection selectedId={entityId} onNavigate={onNavigateEntity} />}
      {activeSection === "users" && <UsersSection selectedId={entityId} onNavigate={onNavigateEntity} />}
      {activeSection === "tokens" && <TokensSection selectedId={entityId} onNavigate={onNavigateEntity} />}
    </div>
  );
}
