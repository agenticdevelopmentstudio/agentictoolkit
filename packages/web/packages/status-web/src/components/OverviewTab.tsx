"use client";
import { type ReactElement, useCallback, useMemo, useState } from "react";
import { Activity, AlertTriangle, BarChart3 } from "lucide-react";
import { InfoPanel } from "@agentic-toolkit/ui/blocks";
import { useLiveSnapshot } from "../hooks/use-live-snapshot";
import { useBoard } from "../hooks/use-board";
import { useActivityHistory } from "../hooks/use-activity-history";
import { useUptime } from "../hooks/use-uptime";
import { useIntegrations } from "../hooks/use-integrations";
import { useMediaQuery } from "../hooks/use-media-query";
import { useEnvFilter } from "../hooks/use-env-filter";
import { useActivityTtl } from "../hooks/use-activity-ttl";
import { useNow } from "../hooks/use-now";
import { useBuildProgress } from "../hooks/use-build-progress";
import { problemToRow, activityToRow, type Row } from "../lib/row-model";
import type { ActivityRow } from "../lib/board-types";
import { indicatorFromProblems, INDICATOR_STATE } from "../lib/overview";
import { overallUptimePercent } from "../lib/uptime";
import { buildSublabel } from "../lib/status-sublabel";
import { shortSha } from "../lib/format";
import { ISSUE_SOURCES, type IssueSource } from "../lib/issue-sources";
import { BigIndicator } from "./BigIndicator";
import { OverviewStats, StatsGear, DEFAULT_SPAN, type Span } from "./OverviewStats";
import { SelfCheckBanner } from "./SelfCheckBanner";
import { DegradedBanner } from "./DegradedBanner";
import { UnconfiguredProjectsBanner } from "./UnconfiguredProjectsBanner";
import { StaleMonitorsBanner } from "./StaleMonitorsBanner";
import { ActivityPanel } from "./ActivityPanel";
import { BuildProgressBar } from "./BuildProgressBar";
import { NextCheckCountdown } from "./NextCheckCountdown";
import { RefreshIconButton } from "./RefreshIconButton";
import { StatusSign } from "./StatusSign";
import { StatusDot } from "./StatusDot";
import { ErrorsCard, TrafficCard } from "./TelemetrySections";

import { COLORS, PALETTE } from "../lib/colors";
const mono = "var(--mono,ui-monospace,monospace)";

function centered(children: ReactElement | string, color: string): ReactElement {
  return (
    <div style={{ flex: 1, display: "flex", alignItems: "center", justifyContent: "center", color, fontFamily: mono, fontSize: 14 }}>
      {children}
    </div>
  );
}

/** The stop-sign panel shown when the live poll is down / monitoring nothing. */
function OfflinePanel({ detail }: { detail?: string | null }): ReactElement {
  return (
    <InfoPanel title="Monitored sites" icon={<AlertTriangle size={15} color={PALETTE.red} />} scroll flex="1 1 0">
      <div style={{ height: "100%", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 14, textAlign: "center", padding: 24 }}>
        <StatusSign state="down" size={96} />
        <div style={{ fontSize: 22, fontWeight: 700, letterSpacing: "0.05em", color: PALETTE.red }}>Status monitoring offline</div>
        {detail && <div style={{ fontFamily: mono, fontSize: 12.5, color: PALETTE.muted, maxWidth: "48ch" }}>{detail}</div>}
      </div>
    </InfoPanel>
  );
}

/**
 * The panel shown whenever the board can't back a current claim — `useBoard` hands back
 * a null board for EVERY cause, which `BoardUnavailableReason` enumerates and this
 * comment deliberately does not: four separate rounds have added a cause and left a
 * count behind here saying "all three", and a comment that has to be re-counted every
 * time the union grows is a comment that will be false again (constraint 8, item C4).
 * Deliberately NOT `StatusSign` — `StatusSign`'s three states
 * (ok/warn/down) are all VERDICTS the server rendered, and an unreadable board is the
 * absence of a verdict, not a `down` one. `StatusDot status="unknown"` is the glyph
 * this codebase already uses for exactly that (StatusHeader's pill). Rendering
 * green/"operational" or an empty "no problems" list here would be a false claim of
 * health from having NO data, not from having checked anything — this panel exists so
 * that can never happen.
 */
function UnknownBoardPanel({ detail }: { detail?: string | null }): ReactElement {
  return (
    <InfoPanel title="Monitored sites" icon={<AlertTriangle size={15} color={PALETTE.amber} />} scroll flex="1 1 0">
      <div style={{ height: "100%", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 14, textAlign: "center", padding: 24 }}>
        <StatusDot status="unknown" size={96} decorative />
        <div style={{ fontSize: 22, fontWeight: 700, letterSpacing: "0.05em", color: PALETTE.amber }}>Status unknown — board unavailable</div>
        <div style={{ fontFamily: mono, fontSize: 12.5, color: PALETTE.muted, maxWidth: "48ch" }}>
          {detail ?? "the status board could not be read — check the monitor's connection to its own API"}
        </div>
      </div>
    </InfoPanel>
  );
}

export function OverviewTab(): ReactElement {
  // The live transport: polls /api/live for the connection-health flags and the
  // fields the board doesn't carry (snapshot, monitorVersion, configDegraded). The
  // board is the ONE source for problems/activity/indicator — it is fetched and
  // rendered, never derived or persisted client-side. The DB is not consulted for
  // anything on this board except the uptime stat (a stats read) and the self-check
  // banner.
  const store = useLiveSnapshot();
  const { board, reason: boardReason, error: boardError } = useBoard();
  const uptimeQuery = useUptime(90);
  // The monitor's own health — a failed/degraded self-check surfaces here on the
  // default wallboard (not just the Details tab) so a broken monitor can't hide.
  const integrationsQuery = useIntegrations();
  // iPhone/mobile: stack the panes vertically as full-viewport scroll-snap pages.
  const isMobile = useMediaQuery("(max-width: 760px)");
  // Coarse 30s clock — drives TTL/stuck derivations without per-second re-renders.
  const nowMs = useNow();

  // Recent Activity hides canceled deploys by default; its gear opts them in.
  const [showCanceled, setShowCanceled] = useState(false);
  // Stats time span (uptime% + response chart) — set from the Stats gear.
  const [span, setSpan] = useState<Span>(DEFAULT_SPAN);

  // How long activity stays in the list (persisted; default 1h, "never" = keep).
  // Applied here (the view), so changing it is instant.
  const { ttlMin, ttlMs, setTtl } = useActivityTtl();

  // Clear/age-out is a UI affordance on Activity only — component state, NOT
  // persisted. A clear watermark that survived a reload would be exactly the
  // durable client state that let a fixed problem hide, in the opposite direction.
  // A Problem cannot be cleared at all: it's derived, so it would return on the
  // next read, and hiding it would be a lie.
  const [clearedBefore, setClearedBefore] = useState(0);

  // History is fetchable only when age-out is `never` AND nothing has been cleared.
  // Both rules fall out of the SAME display filter rather than being switches the reader
  // has to keep in sync: under any TTL every row this could fetch is older than the
  // window, and after a Clear every row it could fetch is older than the watermark
  // (`clearedBefore` is `Date.now()`, and history is by definition older than the live
  // window's oldest row). Either way a page would be filtered straight back out — which
  // is not merely waste: the pane's auto-fill keeps firing while `shown` is under its
  // threshold, so the budget would spend itself pulling 1500 rows the reader just
  // pressed a button to hide.
  const historyDisabledReason: "age-out" | "cleared" | undefined =
    ttlMs != null ? "age-out" : clearedBefore > 0 ? "cleared" : undefined;
  const historyEnabled = historyDisabledReason === undefined;
  const liveActivityRaw = useMemo(() => board?.activity ?? [], [board]);
  const history = useActivityHistory({ enabled: historyEnabled, live: liveActivityRaw });

  const shell = {
    display: "flex",
    flexDirection: "column" as const,
    flex: 1,
    minHeight: 0,
    width: "100%",
    background: PALETTE.bg,
    color: PALETTE.text,
    fontFamily: mono,
    fontSize: 14,
  };

  // Environment filter (persisted, SHARED by both activity panels' gears and the
  // indicator): keep a row when all envs are selected, the row is env-agnostic
  // (no environment), or its environment is selected. Env-agnostic rows (e.g. a
  // platform-wide outage) must never be hidden by an env filter.
  const { envs, all: allEnvNames, toggle: toggleEnv } = useEnvFilter();
  const allEnvs = envs.size === allEnvNames.length;
  const keep = useCallback(
    (x: { environment?: string | null }): boolean => allEnvs || x.environment == null || envs.has(x.environment),
    [allEnvs, envs],
  );

  // Memoized: this component re-renders on every board/store notify AND every 30s
  // clock tick — only re-derive rows when the inputs actually change. The two
  // lists deliberately OVERLAP (a live failure is both a problem — still wrong —
  // and activity — it just happened): the server already keeps them as two
  // separate lists, so there is no splitSections here any more.
  //
  // `activity` (the pane's rows) is loaded history + the live page, run through one
  // filter pipeline so a history row is never a special case for the reader.
  //
  // The clock is a dep only while age-out is ON. With it set to "never" the TTL filter
  // reads `ttlMs == null` and never looks at `nowMs`, so keeping the raw clock in the deps
  // would re-walk the whole feed — history pages included — every 30 seconds to produce a
  // byte-identical array.
  const ttlNowMs = ttlMs == null ? 0 : nowMs;
  const { problems, activity: activityAll, feed } = useMemo(() => {
    const problemRows = (board?.problems ?? []).filter(keep).map(problemToRow);
    const pipeline = (rows: ActivityRow[]): Row[] =>
      rows
        .filter(keep)
        .filter((a) => Date.parse(a.at) > clearedBefore)
        .filter((a) => ttlMs == null || ttlNowMs - Date.parse(a.at) <= ttlMs)
        .map(activityToRow);
    // History rows enter the SAME pipeline the live page runs through, so every display
    // filter (env, cleared, age-out) applies to them identically — a history row is never
    // a special case for the reader.
    //
    // The live page WINS every id it carries. History holds both paged-back rows and the
    // rows the live window SHED as it slid (see `useActivityHistory`), so an id can
    // legitimately be in both — a row can re-enter the window when the board's own read
    // moves — and the live copy is the server's current reading of that fact while the
    // kept one may be a frame or a thousand frames old.
    //
    // Then sorted, rather than trusting the concatenation to be in order. It normally is —
    // whatever the live window sheds is older than everything it kept — but "normally" is
    // load-bearing for the whole feed's reading order, and one row removed from the middle
    // (an orphan sweep dropping a deleted project's deployments) would otherwise render
    // permanently out of place with nothing to put it back.
    const live = board?.activity ?? [];
    const seen = new Set(live.map((a) => a.id));
    const feed = [...history.rows.filter((a) => !seen.has(a.id)), ...live].sort((a, b) =>
      a.at === b.at ? (a.id === b.id ? 0 : a.id < b.id ? -1 : 1) : a.at < b.at ? -1 : 1,
    );
    const activityRows = pipeline(feed);
    // `feed` goes out UNFILTERED as well: the controls that decide what the reader is
    // even offered (Clear, the Sources list) have to see the whole record, not the view.
    return { problems: problemRows, activity: activityRows, feed };
  }, [board, history.rows, keep, clearedBefore, ttlMs, ttlNowMs]);
  // Unfiltered (all envs) takes the server's answer verbatim, so the common case
  // can never disagree with it; an env-filtered view re-derives the sign over just
  // the problems it's showing.
  const indicator = useMemo(() => {
    // `board` is null whenever it can't back a current claim, whatever the cause
    // (`BoardUnavailableReason` is the list; re-spelling it here is how this comment
    // came to say "all three" two causes ago). Every one of them returns early below —
    // the Loading gate, the blind panel, or the `!board` panel — before this value is
    // ever rendered. This fallback only gives the hook SOMETHING to return meanwhile;
    // it must never reach the screen as a claimed "0 problems, ok".
    if (!board) return { state: "ok" as const, count: 0 };
    return allEnvs
      ? { state: INDICATOR_STATE[board.indicator], count: board.problems.length }
      : indicatorFromProblems(board.problems.filter(keep));
  }, [board, allEnvs, keep]);
  // Build-cohort progress over the env-filtered activity — matches the Recent
  // Activity view it sits in, so a filtered-out env's build isn't counted.
  //
  // Deliberately the LIVE window only, unlike `hasClearable`/`allSources`/`hasCanceled`
  // below. The bar reports builds IN FLIGHT RIGHT NOW; every history row is older than
  // the live window's oldest row, so a build found there either finished long ago or is
  // a stuck cohort the live window would still be carrying. Feeding history in would
  // resurrect long-dead cohorts into a "currently building" readout.
  const envActivity = useMemo(() => (board?.activity ?? []).filter(keep), [board, keep]);
  const buildProgress = useBuildProgress(envActivity);
  // Clear empties the WHOLE activity record (every env), so enable it whenever the feed
  // holds anything the watermark hasn't already hidden — not just what the current env
  // filter shows. Live problems count: Clear drops their ROWS from the record even
  // though the problems themselves stay listed.
  //
  // Over `feed`, not `board.activity`, for the same reason `hasCanceled` reads the whole
  // feed: the pane renders live AND paged-in history, so reading the live window alone
  // greys the button out over a pane full of rows after a quiet 24h — and leaves it
  // enabled after a Clear whose only remaining content is history it will not touch.
  const hasClearable = useMemo(
    () => feed.some((a) => Date.parse(a.at) > clearedBefore),
    [feed, clearedBefore],
  );
  // Every source present ANYWHERE on the board — problems AND activity, ignoring the
  // env/text filters — so each panel's source filter lists them all and sources don't
  // vanish when the env filter hides them. Deliberately the union of BOTH lists, not
  // activity alone: an activity-only union let a single-platform activity feed (e.g.
  // one vercel deploy) hide the Sources section from BOTH panels even while an http
  // problem sat right there in Problems — Pre-Task-13 this was derived over every item,
  // and Fix Round 2 restores that (item 1's coordinator-authorized override of the
  // original brief's activity-only Step 8).
  //
  // Activity's half is the whole `feed`, history included: a source that appears only in
  // paged-in rows would otherwise be missing from the list that toggles it, and when the
  // live window holds a single platform `sourceFilterActive` (`allSources.length > 1`)
  // would drop the Sources control entirely from a pane visibly showing several.
  const allSources = useMemo<IssueSource[]>(() => {
    const present = new Set<IssueSource>();
    for (const p of board?.problems ?? []) present.add(p.source);
    for (const a of feed) if (a.source) present.add(a.source);
    return ISSUE_SOURCES.filter((s) => present.has(s));
  }, [board, feed]);

  // Canceled deploys are noise by default; the Recent Activity gear opts them in. Read
  // over `activityAll` — the WHOLE feed, loaded history included. Reading `liveActivity`
  // alone kept the checkbox from flickering as pages arrived, but at the cost of hiding
  // rows with no affordance to reveal them: a canceled row that exists only in paged-in
  // history is filtered out below while the one control that would show it isn't offered.
  const isCanceled = (r: Row): boolean => r.statusWord === "canceled";
  const hasCanceled = activityAll.some(isCanceled);
  const activity = showCanceled ? activityAll : activityAll.filter((r) => !isCanceled(r));

  const uptimePercent = overallUptimePercent(uptimeQuery.data?.services ?? []);

  // Before anything is known — no snapshot, poll not failed, or the board's own
  // first-ever fetch is still in flight — there is genuinely nothing to show yet.
  // (A board still `null` after loading has settled falls through to the `!board`
  // panel below, not this one — that case has an answer: "unreadable".) `reason` is
  // the hook's ONE loading signal; it is null exactly when `board` is non-null, so
  // this reads only for a board that hasn't landed yet.
  if ((!store.snapshot && !store.offline) || boardReason === "loading") {
    return (
      <div style={shell}>
        <SelfCheckBanner data={integrationsQuery.data} />
        <UnconfiguredProjectsBanner />
        {centered("Loading…", PALETTE.muted)}
      </div>
    );
  }

  // A snapshot that monitored NOTHING must never read green — "0/0 healthy" is
  // blindness, not health (store.blind). Treated exactly like the poll failing.
  const blind = store.blind;

  const services = (store.snapshot?.services ?? []).filter((s) => keep({ environment: s.environment || null }));
  const healthyCount = services.filter((s) => s.status === "healthy").length;
  const sublabel = buildSublabel(indicator.state, healthyCount, services.length, problems);

  // Only the `blind` panel below reads this now — a transient live-feed outage no
  // longer tears the board down (BoardShell's ConnectionOverlay covers it calmly),
  // so the OfflinePanel is reserved for the real config fault of nothing to watch.
  const blindDetail = "no endpoints configured — the monitor has nothing to watch (check the shipped config)";

  // Shared props for both promoted activity panels.
  const env = { envs, allEnvs: allEnvNames, onToggleEnv: toggleEnv, allSources, envFiltered: !allEnvs };

  const problemsPanel = (flex: string, maxHeight?: string): ReactElement => (
    <ActivityPanel kind="problems" icon={<AlertTriangle size={15} color={PALETTE.amber} />} title="Problems" rows={problems} flex={flex} maxHeight={maxHeight} {...env} />
  );
  const activityPanel = (flex: string): ReactElement => (
    <ActivityPanel
      kind="activity"
      icon={<Activity size={15} color={PALETTE.green} />}
      title="Recent Activity"
      rows={activity}
      flex={flex}
      {...env}
      showCanceled={showCanceled}
      onShowCanceledChange={setShowCanceled}
      canceledAvailable={hasCanceled}
      ttlMin={ttlMin}
      onTtlChange={setTtl}
      onClear={() => setClearedBefore(Date.now())}
      clearDisabled={!hasClearable}
      // History paging — undefined (not a no-op function) whenever it's disabled, so
      // ActivityPanel's own `onLoadOlder != null` gate reads it as "can't page back"
      // rather than silently calling a hook that would no-op anyway.
      onLoadOlder={historyEnabled ? history.loadOlder : undefined}
      historyLoading={history.loading}
      historyExhausted={history.exhausted}
      onScrollGesture={history.resetAutoBudget}
      historyBudgetSpent={history.autoBudgetSpent}
      historyError={history.error}
      historyDisabledReason={historyDisabledReason}
      center={
        <div style={{ display: "flex", alignItems: "center", gap: 12, minWidth: 0 }}>
          <BuildProgressBar progress={buildProgress} />
          {/* The poll utility controls — next-check countdown + refresh — centered in
              the Recent Activity header. The half-width panel can't fit the countdown
              AND the build-progress bar, so the countdown stands down while a build
              cohort is active (the bar takes the centre) and stands down again when the
              PANEL is narrow (.adh-panel-optional container query); the compact refresh
              icon always stays, which is what the narrowing buys room for. */}
          <div style={{ display: "flex", alignItems: "center", gap: 10, flexShrink: 0 }}>
            {/* .adh-panel-optional sets display:inline-flex + align-items in CSS (not inline)
                so the container query can hide it without !important. */}
            {!buildProgress.visible && (
              <span className="adh-panel-optional">
                <NextCheckCountdown nextPollAt={store.nextPollAt} polling={store.polling} />
              </span>
            )}
            <RefreshIconButton onRefresh={store.refresh} refreshing={store.polling} />
            {/* The commit the MONITOR ITSELF is running (from the snapshot) — so a
                status-site deploy that failed or never restarted is visible right
                here as an old sha, instead of being invisible from the board. */}
            {store.snapshot?.monitorVersion && (
              <span
                className="adh-panel-optional"
                title={`monitor running commit ${store.snapshot.monitorVersion}`}
                style={{ fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 11, color: PALETTE.dim, whiteSpace: "nowrap" }}
              >
                {shortSha(store.snapshot.monitorVersion)}
              </span>
            )}
          </div>
        </div>
      }
    />
  );

  const banners = (
    <>
      <SelfCheckBanner data={integrationsQuery.data} />
      <UnconfiguredProjectsBanner />
      <StaleMonitorsBanner />
      {store.snapshot?.configDegraded && (
        <DegradedBanner
          reason={store.snapshot.configReason}
          detail="Live checks are running against the built-in endpoint list; Configure edits are unavailable."
        />
      )}
    </>
  );

  // One stop-sign layout, two different panels — extracted so the guards below can be
  // ordered freely without duplicating the shell around each verdict.
  const stopSign = (panel: ReactElement): ReactElement => (
    <div style={shell}>
      {banners}
      <div style={{ flex: 1, minHeight: 0, overflowY: "auto", display: "flex", flexDirection: "column" }}>
        <div style={{ flex: 1, minHeight: 0, display: "flex", padding: "16px 18px", overflow: "hidden" }}>
          {panel}
        </div>
        <div style={{ flexShrink: 0, display: "flex", flexDirection: "column", gap: 16, padding: 16 }}>
          <ErrorsCard />
          <TrafficCard />
        </div>
      </div>
    </div>
  );

  // Monitoring NOTHING (blind) means we can't truthfully claim ANY status: a single
  // stop-sign panel instead of the lists. A transient live-feed outage is NOT handled
  // here — it falls through to the normal board, over which BoardShell lays the calm
  // reconnect overlay. Telemetry is a decoupled source, so keep Errors/Traffic visible.
  //
  // Fix Round 2 item C3 — this is checked BEFORE `!board` when, and only when, the board's
  // sole complaint is that it rests on no observation (`no-data`). A roster with no
  // endpoints produces exactly that: nothing to observe means nothing observed, means
  // `dataAsOfMs === null`, means a null board — so ordering `!board` first made
  // `blindDetail` unreachable for precisely the roster it was written for, and a fresh
  // install was told to go debug a monitor that was working perfectly. "No observations
  // yet" and "observations stopped arriving" are different states and must not render
  // alike (constraint 2, in its converse direction). Every OTHER null-board cause still
  // wins over `blind` below, because an unreadable, stale or frozen board is a stronger
  // "we don't know" than a live-snapshot fact and must not be masked by a config message.
  if (blind && (board !== null || boardReason === "no-data")) {
    return stopSign(<OfflinePanel detail={blindDetail} />);
  }

  // The board cannot back a current claim, for any of the reasons `BoardUnavailableReason`
  // lists (Fix Round 3 item 1: `useBoard` folds them all into
  // `board === null` in ONE place, so this branch can't be skipped by forgetting to also
  // ask whether a present board is still current — a permanently-500ing `/api/board` used
  // to leave React Query's last GOOD board on screen forever, which was the exact same
  // false claim as never having loaded, just arriving slower). Never fall through to the
  // normal panels here: `board?.problems ?? []` would silently read as "zero problems"
  // and `indicatorFromProblems([])` as "ok", i.e. a false "ALL SYSTEMS OPERATIONAL" claim
  // from having no CURRENT data, not from having checked anything. `boardReason` only
  // changes the wording of the detail line below — a human can tell "never refreshed"
  // from "the fetch failed", but a caller that only checks `!board` can't get that
  // distinction wrong, because they all land in this one branch.
  if (!board) {
    // Each cause gets the words that are TRUE for it. "has not refreshed" is exactly
    // wrong for a wedged monitor — that board is refreshing, on time, over facts that
    // stopped moving — and sending a reader to check the API connection when the API is
    // answering fine is worse than saying nothing. `no-data` reaches here only when there
    // ARE endpoints to watch (the blind branch above took the other case), so it is the
    // honest "the first cycle hasn't finished — or hasn't run".
    const detail =
      boardReason === "stale"
        ? "the status board has not refreshed — check the monitor's connection to its own API"
        : boardReason === "frozen"
          ? "the status board is refreshing, but nothing behind it is — no new observation has been recorded, so nothing on screen can be trusted as current (check the monitor process)"
          : boardReason === "no-data"
            ? "the monitor has endpoints to watch but has not recorded a single observation yet — nothing on screen can be trusted as current until its first cycle completes (check the monitor process)"
            : (boardError?.message ?? null);
    return stopSign(<UnknownBoardPanel detail={detail} />);
  }

  // iPhone/mobile: hero + activity (Problems over Recent Activity) + telemetry,
  // each a full-viewport scroll-snap page.
  if (isMobile) {
    return (
      <div style={shell}>
        {banners}
        <div className="adh-snap-scroll">
          <section className="adh-snap-pane adh-snap-hero">
            <BigIndicator state={indicator.state} count={indicator.count} sublabel={sublabel} extra={<OverviewStats uptimePercent={uptimePercent} span={span} onSpanChange={setSpan} />} />
            <div className="adh-snap-hint" aria-hidden>scroll for details ↓</div>
          </section>
          <section className="adh-snap-pane" style={{ display: "flex", flexDirection: "column", gap: 12, padding: 12 }}>
            {problemsPanel("0 1 auto", "45%")}
            {activityPanel("1 1 0")}
          </section>
          <section className="adh-snap-pane" style={{ overflowY: "auto", display: "flex", flexDirection: "column", gap: 16, padding: 16 }}>
            <ErrorsCard />
            <TrafficCard />
          </section>
        </div>
      </div>
    );
  }

  // Desktop: the two promoted activity panels (Problems | Recent Activity) fill
  // the main area, with the Stats / Errors / Traffic cards in a right rail.
  return (
    <div style={shell}>
      {banners}
      <div style={{ flex: 1, minHeight: 0, display: "flex", alignItems: "stretch", gap: 16, padding: "16px 18px", overflow: "hidden" }}>
        <div style={{ flex: 1, minWidth: 0, minHeight: 0, display: "flex", gap: 12, overflow: "hidden" }}>
          {problemsPanel("1 1 0")}
          {activityPanel("1 1 0")}
        </div>
        <div style={{ flex: "0 0 30%", minHeight: 0, display: "flex", flexDirection: "column", gap: 16, overflowY: "auto" }}>
          <InfoPanel title="Stats" icon={<BarChart3 size={15} color={COLORS.gold} />} actions={<StatsGear span={span} onSpanChange={setSpan} />}>
            <OverviewStats uptimePercent={uptimePercent} layout="card" span={span} onSpanChange={setSpan} />
          </InfoPanel>
          <ErrorsCard />
          <TrafficCard />
        </div>
      </div>
    </div>
  );
}
