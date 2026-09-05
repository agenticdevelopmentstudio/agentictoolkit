"use client";
import { type ReactElement, type ReactNode, useCallback, useEffect, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { HierarchicalDetailView, type TopicLevel, type TopicDetailItem } from "@agentic-toolkit/ui/blocks";
import { Badge } from "@agentic-toolkit/ui/components/badge";
import { cn } from "@agentic-toolkit/ui/lib/utils";
import { useRefreshAll } from "../hooks/use-refresh-all";
import { usePortfolioIndicator } from "../hooks/use-portfolio-indicator";
import { useConfigStatus } from "../hooks/use-config-status";
import { useStatusUser } from "../hooks/useStatusUser";
import { useLiveSnapshot } from "../hooks/use-live-snapshot";
import { plural } from "../lib/format";
import { headlineFor } from "../lib/overview";
import {
  BOARD_VIEWS,
  entityIdFromPath,
  isRosterTopic,
  sectionFromPath,
  topicFromPath,
  visibleSettingsSections,
} from "./board-views";
import { SettingsLevelProvider } from "./settings-level";
import { OverviewTab } from "./OverviewTab";
import { Dashboard } from "./Dashboard";
import { FleetView } from "./FleetView";
import { SnapshotStaleBanner } from "./SnapshotStaleBanner";
import { ConnectionOverlay } from "@agentic-toolkit/ui/components/connection-overlay";
import { ConfigPanel, AppearanceSection } from "./ConfigPanel";
import { StatusDot } from "./StatusDot";
import { StatusSign } from "./StatusSign";

const mono = "var(--mono,ui-monospace,monospace)";

const FONT_SCALE_KEY = "adh-font-scale";
const MIN_SCALE = 0.8;
const MAX_SCALE = 1.5;

// The rail's topic list, derived from the single board-views source of truth. Every topic
// is role-independent, so this is module scope — the gate lives on the Settings sections.
const TOPICS: TopicDetailItem[] = BOARD_VIEWS.map((v) => ({
  id: v.id,
  label: v.label,
  icon: v.icon,
  dividerAfter: v.dividerAfter,
}));

/** The `/home` landing — the stack's no-selection state. Shows the same
 *  whole-portfolio headline as the header pill (both via usePortfolioIndicator, so
 *  the "unknown" rule never diverges), centred (the sanctioned empty-state
 *  exception to left-justified). */
function BoardHome(): ReactElement {
  const { pillKey, count } = usePortfolioIndicator();
  const headline = pillKey === "unknown" ? "Status unknown" : headlineFor(pillKey, count);
  return (
    <div
      style={{
        flex: 1,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        gap: 20,
        padding: "8vh 24px",
        textAlign: "center",
        color: "var(--color-apt-text)",
      }}
    >
      {pillKey === "unknown" ? (
        <StatusDot status="unknown" size={28} />
      ) : (
        <StatusSign state={pillKey} count={count} size={56} />
      )}
      <h1 style={{ fontFamily: mono, fontSize: 20, fontWeight: 600, margin: 0 }}>{headline}</h1>
      <p style={{ margin: 0, fontSize: 14, opacity: 0.65 }}>Pick a view from the list to get started.</p>
    </div>
  );
}

/** A leaf panel kept MOUNTED once visited (display:none when inactive) so it
 *  retains its state across section switches — used for the config rosters, whose
 *  editors hold an unsaved draft. Overview/Details/Fleet deliberately do NOT use
 *  this (they mount only while active), so their live feeds re-initialise on return —
 *  e.g. Recent Activity re-tails to the newest row rather than staying scrolled
 *  wherever it was when items arrived off-screen. */
function KeptPane({ show, children }: { show: boolean; children: ReactNode }): ReactElement {
  return <div className={cn("min-h-0 flex-1 flex-col", show ? "flex" : "hidden")}>{children}</div>;
}

/**
 * The board: ONE HierarchicalTopicDetail at the root of the site whose first topic list
 * is Overview / Details / Fleet / …divider… / Settings.
 *
 * Settings opens the hierarchy's SECOND level — its sections, alphabetically: API tokens,
 * Appearance, Fleet peers, Groups, Platforms, Sites, Users. Appearance is a leaf (the
 * display preferences); every other section is a config ROSTER that publishes its entity
 * list up via SettingsLevelProvider as the THIRD level, with the entity editor as the leaf.
 *
 * Selection is deep-linked: each topic is a root URL segment, a section is
 * `/settings/<section>`, a roster entity is `/settings/<section>/<id>`; `/home` is the
 * cleared landing. Rendered from the (board) route-group LAYOUT so it persists across
 * navigations.
 *
 * WHICH hierarchical view this renders is NOT decided here. Providers mounts the shared
 * `HierarchicalDetailViewFlag`, which is the platform's single answer for every site
 * (currently HTDV-only — HMDV is shelved). This board once nested its OWN
 * `HierarchicalDetailViewProvider` fed by a per-browser "view style" preference, which
 * silently overrode that flag (the nearer provider wins) and left the wallboard rendering
 * HMDV — including the auto-collapse mode and its toggle, parked out of HTDV in the same
 * week — long after the rest of the platform had moved off it. Change the view for every
 * site in HierarchicalDetailViewFlag, never by re-mounting a provider below it.
 */
export function BoardShell({ children }: { children: ReactNode }): ReactElement {
  const router = useRouter();
  const path = (usePathname() ?? "/").replace(/\/+$/, "");
  const topic = topicFromPath(path);
  const entityId = entityIdFromPath(path);

  // Refresh every dataset on one shared 60s tick — no staggered, mismatched state.
  useRefreshAll(60_000);

  // The live feed's connection health drives a calm overlay (below) over the
  // Overview/Details board when the backend is unreachable — a redeploy blip should
  // read as "deploying", not tear the panels down into the alarming red stop sign.
  // `blind` (no endpoints configured) is a real config fault, not a transient outage,
  // so it's excluded here and still handled by OverviewTab's OfflinePanel.
  const liveStore = useLiveSnapshot();
  // `disconnected` (not `offline`) stays asserted through in-flight re-reads, so the
  // overlay doesn't strobe as the fallback poll retries under it.
  const showConnectionOverlay =
    liveStore.disconnected && !liveStore.blind && (topic === "overview" || topic === "details");

  // Wallboard font scale, persisted; the Settings ▸ Appearance leaf adjusts it. Applied
  // to the leaf panels via CSS zoom (keeps layout proportional), as the wallboard always
  // has.
  const [fontScale, setFontScale] = useState(1);
  useEffect(() => {
    try {
      const saved = localStorage.getItem(FONT_SCALE_KEY);
      if (saved !== null) {
        const n = parseFloat(saved);
        if (Number.isFinite(n) && n >= MIN_SCALE && n <= MAX_SCALE) setFontScale(n);
      }
    } catch {
      // localStorage unavailable — use default
    }
  }, []);
  const updateFontScale = useCallback((n: number): void => {
    setFontScale(n);
    try {
      localStorage.setItem(FONT_SCALE_KEY, String(n));
    } catch {
      // ignore
    }
  }, []);

  // Role gate (Appearance for everyone; every roster admin-only, matching the server's
  // own `requireAdmin`) from the board-views SSoT. A deep link to a section this role
  // can't see falls back to "nothing selected".
  const user = useStatusUser();
  const visibleSections = visibleSettingsSections(user?.role);
  const section = sectionFromPath(path);
  const effectiveSection = section && visibleSections.some((s) => s.id === section) ? section : null;
  const isRoster = isRosterTopic(effectiveSection);

  // The config rosters hold an unsaved draft, so once ANY roster section is visited the
  // shared ConfigPanel stays mounted (hidden when inactive) to preserve it across section
  // switches. Render-phase state adjust (React's derived-state pattern) so it mounts in
  // the same pass it's first shown.
  const [rosterSeen, setRosterSeen] = useState(false);
  if (isRoster && !rosterSeen) setRosterSeen(true);

  // The Sites section carries the same ⚠ unconfigured-sites count the Overview banner
  // shows (one shared model, so they can't disagree), and the rail's Settings row carries
  // the same count as a rollup so the signal stays ambient from Overview/Details/Fleet —
  // the rosters are two levels down now, and a config gap nobody navigates to is a config
  // gap nobody fixes.
  //
  // The gate is the ROLE gate only. Narrowing it to `topic === "settings"` as well buys
  // nothing — ConfigPanel (kept mounted once a roster is seen) and the Overview banner
  // both hold their own always-enabled observer on ["configure-data"], and react-query's
  // `isDisabled()` (what use-refresh-all's 60s tick tests) is false while ANY observer is
  // enabled — while it does cost a cold fetch, so the badge pops in a beat late on a deep
  // link straight into Settings.
  const canSeeRosters = visibleSections.some((s) => isRosterTopic(s.id));
  const { status } = useConfigStatus({ enabled: canSeeRosters });
  const unconfiguredSites = status.counts.sites;
  const warnBadge =
    unconfiguredSites > 0 ? (
      <Badge
        variant="accent"
        title={`${plural(unconfiguredSites, "site")} not configured`}
        aria-label={`${plural(unconfiguredSites, "site")} not configured`}
      >
        ⚠ {unconfiguredSites}
      </Badge>
    ) : undefined;

  // Pure-intent selection (the package decides when each fires): select → that topic's
  // URL; clear (re-click / breadcrumb root) → /home. `overview: false` keeps the /home
  // landing (BoardHome) instead of the select nudge — the root has its own real landing.
  // No exit guard — the roster ConfigPanel stays mounted, so its draft is never discarded
  // by a topic switch.
  const level: TopicLevel = {
    id: "views",
    title: "Status",
    // Same identity as the module-scope list while there is nothing to flag; only a live
    // warning re-maps it. `blocked` rides along with the Badge because `trailing` is
    // dropped in the collapsed / covered icon strips — the amber dot survives them.
    items: warnBadge
      ? TOPICS.map((t) => (t.id === "settings" ? { ...t, trailing: warnBadge, blocked: true } : t))
      : TOPICS,
    selectedId: topic,
    overview: false,
    onSelect: (id) => router.push(`/${id}`),
    onClear: () => router.push("/home"),
  };

  // Settings' sections are the SECOND topic level (`/settings/<section>`), not a nav
  // column inside the pane — the whole board is one hierarchy. `railLabel` names this
  // list distinctly so it is addressable next to the root rail (both default to
  // "Topic list").
  const settingsLevel: TopicLevel = {
    id: "settings-sections",
    title: "Settings",
    railLabel: "Settings sections",
    itemNoun: "section",
    items: visibleSections.map((s) => {
      const warn = s.id === "sites" && unconfiguredSites > 0;
      const warnTitle = warn ? `${plural(unconfiguredSites, "site")} not configured` : undefined;
      return {
        id: s.id,
        label: s.label,
        icon: s.icon,
        trailing: warn ? (
          <Badge variant="accent" title={warnTitle} aria-label={warnTitle}>
            ⚠ {unconfiguredSites}
          </Badge>
        ) : undefined,
        // Same pairing as the rail's Settings row: `trailing` is dropped in the collapsed
        // and covered icon strips, so the warning only survives them as `blocked`'s dot.
        blocked: warn,
      };
    }),
    selectedId: effectiveSection,
    onSelect: (id) => router.push(`/settings/${id}`),
    onClear: () => router.push("/settings"),
  };

  // The active roster section's ENTITY LIST (Groups/Sites/… rosters), published up via
  // SettingsLevelProvider, is the hierarchy's THIRD level. Selection deep-links at
  // `/settings/<section>/<id>`; the entity editor is the leaf.
  const [entityLevel, setEntityLevel] = useState<TopicLevel | null>(null);
  const navigateEntity = useCallback(
    (id: string | null) => {
      if (!isRosterTopic(effectiveSection)) return;
      router.push(id ? `/settings/${effectiveSection}/${encodeURIComponent(id)}` : `/settings/${effectiveSection}`);
    },
    [router, effectiveSection],
  );

  // Name the open roster's rail after the roster itself. The package leaves `railLabel`
  // opt-in (defaulting it to `title` would rename every rail on the fleet at once), and
  // without it this stack renders TWO landmarks called "Topic list" — the board's views
  // and the section's entities — which is one landmark too many to jump between by name.
  // Done here rather than per-roster in ConfigPanel so every roster gets it from one line.
  const namedEntityLevel: TopicLevel | null = entityLevel
    ? { ...entityLevel, railLabel: entityLevel.railLabel ?? entityLevel.title }
    : null;

  const levels =
    topic === "settings"
      ? [level, settingsLevel, ...(isRoster && namedEntityLevel ? [namedEntityLevel] : [])]
      : [level];

  return (
    <HierarchicalDetailView levels={levels} rootLabel="Status" minDetailWidth="20rem">
      <div style={{ zoom: fontScale, position: "relative" }} className="flex min-h-0 w-full flex-1 flex-col">
        {/* Board-wide: a wedged / never-redeployed poller freezes EVERY view, so the
            "monitoring paused" warning rides above the topic content, not just Overview.
            "Content" is the limit, and Settings widened it: this whole subtree is the
            package's DETAIL pane, and a level that is the frontier with nothing selected
            renders its select nudge INSTEAD of the detail (`overview`, on by default) —
            so bare /settings and a roster with no entity chosen show the nudge and no
            banner. Only the root level opts out (it has BoardHome to show); the package
            is explicit that the opt-out is for a pane already holding a real editor, not
            a way to hang extra chrome under an unselected frontier. */}
        <SnapshotStaleBanner />
        {topic === null && <BoardHome />}
        {/* Overview/Details/Fleet/Appearance mount only while active (Overview/Details/Fleet
            re-init their live feeds on return; Appearance re-reads localStorage). The config
            rosters share one ConfigPanel kept mounted once seen to hold drafts. */}
        {topic === "overview" && (
          <div className="flex min-h-0 flex-1 flex-col">
            <OverviewTab />
          </div>
        )}
        {topic === "details" && (
          <div className="flex min-h-0 flex-1 flex-col">
            <Dashboard />
          </div>
        )}
        {topic === "fleet" && (
          <div className="flex min-h-0 flex-1 flex-col">
            <FleetView />
          </div>
        )}
        {topic === "settings" && effectiveSection === "appearance" && (
          <div className="flex min-h-0 flex-1 flex-col">
            <AppearanceSection fontScale={fontScale} onFontScaleChange={updateFontScale} />
          </div>
        )}
        {rosterSeen && (
          <KeptPane show={isRoster}>
            <SettingsLevelProvider onPublish={setEntityLevel}>
              <ConfigPanel
                active={isRoster}
                // Both props come off the SAME path parse, so they have to be gated
                // together: `entityIdFromPath` reads the raw URL and ignores the role
                // gate, so an ungated `entityId` hands a hidden section's entity id to
                // whichever roster the kept-mounted panel last showed (deep-link
                // `/settings/users/<id>` as a non-admin, or as an admin during the beat
                // before the role loads, and the id lands in Sites).
                section={isRosterTopic(effectiveSection) ? effectiveSection : null}
                entityId={isRoster ? entityId : null}
                onNavigateEntity={navigateEntity}
              />
            </SettingsLevelProvider>
          </KeptPane>
        )}
        {/* The routed (board) pages render nothing — the panels above are the leaf content. */}
        {children}
        {/* Calm reconnect overlay OVER the current board (Overview/Details only) when the
            backend is unreachable — obscures the panels rather than rearranging them. */}
        <ConnectionOverlay
          active={showConnectionOverlay}
          onRetry={liveStore.reconnect}
          detail={liveStore.offlineDetail}
        />
      </div>
    </HierarchicalDetailView>
  );
}
