"use client";
import {
  type ReactElement, type ReactNode, type KeyboardEvent, type WheelEvent, type TouchEvent,
  useCallback, useEffect, useMemo, useRef, useState,
} from "react";
import { InfoPanel } from "@agentic-toolkit/ui/blocks";
import { type Row, rowToStatusRowProps, rowSearchText, rowsToText } from "../lib/row-model";
import { ISSUE_SOURCES, SOURCE_LABEL, isIssueSource, type IssueSource } from "../lib/issue-sources";
import { matchesQuery } from "../lib/filter";
import { useSourceFilter } from "../hooks/use-source-filter";
import { useNow } from "../hooks/use-now";
import { useFollowNewItems } from "../hooks/use-follow-new-items";
import { ACTIVITY_TTL_OPTIONS_MIN, DEFAULT_ACTIVITY_TTL_MS, type ActivityTtl } from "../hooks/use-activity-ttl";
import { COLORS, PALETTE, envColor } from "../lib/colors";
import { StatusRow } from "./StatusRow";
import { ActivityDetails } from "./ActivityDetails";
import { rowToDetailProps, rowDetailToText } from "../lib/row-detail";
import { stepIndex } from "@agentic-toolkit/ui/lib/step-index";
import { ResizableSplit } from "@agentic-toolkit/ui/components/resizable-split";
import { StatusSign } from "./StatusSign";
import { CopyButton } from "@agentic-toolkit/ui/components/copy-button";
import { Input } from "@agentic-toolkit/ui/components/input";
import { Eraser } from "lucide-react";
import { cn } from "@agentic-toolkit/ui/lib/utils";
import { OptionsGear, OptionSection, OptionDivider, optionRow } from "./OptionsGear";

const mono = "var(--mono,ui-monospace,monospace)";
const emptyStyle = { fontFamily: mono, fontSize: 13, color: PALETTE.dim, padding: "4px 2px" } as const;

/** Distance from the TOP (older end) at which the pane asks for the next page. */
const SCROLL_BACK_THRESHOLD_PX = 200;

/**
 * The shortest gap between two budget grants from a raw input gesture.
 *
 * One trackpad flick is dozens of `wheel` events and inertial scrolling keeps them coming
 * for a second after the finger lifts; a touch-drag is the same. Granting a budget on each
 * of them makes MAX_AUTOPAGE_FETCHES unenforceable on the primary input device — the very
 * thing that is supposed to stop a filter matching nothing from dragging 90 days of history
 * across the wire. Collapsing a burst into ONE grant keeps the intended meaning: one grant
 * per gesture, whether the gesture is an edge crossing or a reader parked at the top and
 * still pushing.
 */
const GESTURE_REARM_MS = 400;

/** Below this many rows AFTER every filter, the pane keeps pulling older pages on its own
 *  (bounded by the caller's auto-page budget). It lives HERE, not in the caller, because
 *  this is where the count that matters exists: the caller can see its own env/cleared/
 *  age-out filters but not this panel's source filter or its free-text search, which are
 *  precisely the filters most likely to empty the pane. */
const MIN_FILLED_ROWS = 30;

/** The default activity age-out window (minutes) — used to detect an off-default
 *  ttl. Derived from the store's source of truth so the two can't drift. */
const DEFAULT_TTL_MIN = DEFAULT_ACTIVITY_TTL_MS / 60_000;

export interface ActivityPanelProps {
  /** "problems" never tails or carries activity-only controls; "activity" does. */
  kind: "problems" | "activity";
  icon: ReactNode;
  title: string;
  /** Already env-filtered rows for this panel. */
  rows: Row[];
  /** Shared environment filter (edited from BOTH panels' gears + the indicator). */
  envs: Set<string>;
  allEnvs: readonly string[];
  onToggleEnv: (env: string) => void;
  /** Every source present in the store (NOT just this panel's filtered rows) so the
   *  source filter lists them all, even when the env filter hides a source's rows. */
  allSources: readonly IssueSource[];
  /** True when some environments are unchecked — changes the empty-state copy. */
  envFiltered: boolean;
  /** Side-by-side ("1 1 0") vs stacked sizing handled by the caller via flex. */
  flex?: string;
  maxHeight?: string;
  /** Show the dim count after the title (Problems yes, Recent Activity no). */
  showCount?: boolean;
  /** Centered header slot (the build progress bar, for Recent Activity). */
  center?: ReactNode;
  // Recent Activity only ----------------------------------------------------
  showCanceled?: boolean;
  onShowCanceledChange?: (v: boolean) => void;
  canceledAvailable?: boolean;
  ttlMin?: ActivityTtl;
  onTtlChange?: (v: ActivityTtl) => void;
  onClear?: () => void;
  /** Disable Clear — true when the store holds nothing but live problems (Clear
   *  removes the WHOLE record, across envs, so this can't key off the filtered view). */
  clearDisabled?: boolean;
  // History paging — Recent Activity only; absent/undefined on Problems, which never
  // pages back. -----------------------------------------------------------
  /** Ask the caller for the next older page. Safe to call repeatedly while a fetch is
   *  already in flight — the hook that backs it latches on its own. */
  onLoadOlder?: () => void;
  /** A page is currently in flight. */
  historyLoading?: boolean;
  /** The server reported no facts older than the last loaded page. */
  historyExhausted?: boolean;
  /** A fresh scroll-back gesture — the caller resets the auto-page budget on this. Fired
   *  on the false→true edge into the threshold zone, and on a wheel/touch inside it; see
   *  the handlers for why those two and nothing else. */
  onScrollGesture?: () => void;
  /** The auto-continue budget (Task 6's `MAX_AUTOPAGE_FETCHES`) is spent and history
   *  is not yet exhausted — a filter matching almost nothing could otherwise dead-end
   *  the pane silently. */
  historyBudgetSpent?: boolean;
  /** The last page FAILED. Never conflated with `historyExhausted`: one says there is
   *  nothing older, the other says we don't know. */
  historyError?: boolean;
  /** WHY paging back is turned off, or undefined when it isn't. The pane says so where
   *  the older rows would have been, because the alternative is a feature that ships
   *  dark: age-out defaults to 1 hour, so out of the box scrolling back does nothing and
   *  nothing on screen explains it. One field rather than a boolean per cause — the two
   *  reasons are mutually exclusive states of one thing, and splitting them would let a
   *  render show both lines or neither. */
  historyDisabledReason?: "age-out" | "cleared";
}

/**
 * One promoted activity panel — Problems or Recent Activity — as its own
 * InfoPanel. The header carries the icon, the title, a copy button (copies the
 * shown rows), an optional centered progress bar, and on the right a filter box
 * and an options gear (sources + environments, plus show-canceled and age-out
 * for Recent Activity). Each panel owns its own text + source filters; the
 * environment filter is shared. Recent Activity tails to the newest row.
 */
export function ActivityPanel({
  kind,
  icon,
  title,
  rows,
  envs,
  allEnvs,
  onToggleEnv,
  allSources,
  envFiltered,
  flex = "1 1 0",
  maxHeight,
  showCount = false,
  center,
  showCanceled = false,
  onShowCanceledChange,
  canceledAvailable = false,
  ttlMin = null,
  onTtlChange,
  onClear,
  clearDisabled,
  onLoadOlder,
  historyLoading = false,
  historyExhausted = false,
  onScrollGesture,
  historyBudgetSpent = false,
  historyError = false,
  historyDisabledReason,
}: ActivityPanelProps): ReactElement {
  const [q, setQ] = useState("");
  const { sources, toggleSource } = useSourceFilter();
  const nowMs = useNow();

  // The source filter is inert when only one source exists anywhere — applying it
  // then would hide rows the user can't get back, so bypass it unless it's active.
  const sourceFilterActive = allSources.length > 1;
  const shown = useMemo(() => {
    const matches = (r: Row): boolean =>
      (!sourceFilterActive || !r.platform || (isIssueSource(r.platform) && sources.has(r.platform))) &&
      matchesQuery(rowSearchText(r), q);
    return rows.filter(matches);
  }, [rows, q, sources, sourceFilterActive, nowMs]);

  const [selectedKey, setSelectedKey] = useState<string | null>(null);
  // The selected row: the tracked key when still shown, else the LAST shown row (so the
  // details pane is never blank and arrow-keys always have an anchor). Last, not first,
  // because the feed reads oldest-first — the newest row is the one an operator opened
  // the board for, and it is the same row the tail scrolls to.
  const selected = useMemo(
    () => shown.find((r) => r.key === selectedKey) ?? shown.at(-1) ?? null,
    [shown, selectedKey],
  );
  // Stable ids so the filter input can point aria-activedescendant at the active row
  // and the keyboard handler can scroll it into view. Prefixed with `kind` so the two
  // panels on the page don't collide.
  const listboxId = `adh-listbox-${kind}`;
  const optionId = (key: string): string => `adh-opt-${kind}-${key}`;
  // ↑/↓ move the selection through the shown rows — active whether focus is in the
  // filter box OR on the list itself (clicking a row focuses the list; see onSelect).
  const onArrowNav = (e: KeyboardEvent<HTMLElement>): void => {
    if (e.key !== "ArrowDown" && e.key !== "ArrowUp") return;
    if (shown.length === 0) return;
    e.preventDefault();
    const cur = shown.findIndex((r) => r.key === selected?.key);
    const next = stepIndex(shown.length, cur, e.key);
    if (next >= 0) {
      const key = shown[next]!.key;
      setSelectedKey(key);
      // Only keyboard nav scrolls the selection into view — the initial auto-select
      // must NOT, or it would fight Recent Activity's tail-to-newest on load.
      document.getElementById(optionId(key))?.scrollIntoView({ block: "nearest" });
    }
  };

  const bodyRef = useRef<HTMLDivElement>(null);
  const tail = kind === "activity";

  // Only Recent Activity pages back; Problems is derived state with no history to page
  // through, and passing it onLoadOlder at all would be a caller bug — the check is
  // kept here too so the panel itself refuses to page even if it happens.
  const canPageBack = kind === "activity" && onLoadOlder != null;
  // Was the viewport already inside the threshold zone on the PREVIOUS scroll event —
  // tracked so `onScrollGesture` (which resets the auto-page budget) fires only on the
  // false→true EDGE into the zone, not on every scroll event while the reader rests
  // near the top. `onLoadOlder` itself is safe to call on every event inside the zone
  // (the hook behind it latches on its own in-flight fetch and its cursor), but a
  // BUDGET refreshed by the very events it's meant to bound isn't a budget at all: a
  // prepended history page moves `scrollTop` itself (`useFollowNewItems` writes it in
  // its layout effect when the reader is scrolled away from the tail), which fires
  // another scroll event, which would re-arm the budget again if this fired on every
  // event — the pane would then walk back through the ENTIRE 90 days of history while
  // the reader sits still. Gating on the edge means one budget grant per gesture.
  const wasNear = useRef(false);
  const handleScroll = useCallback(() => {
    const el = bodyRef.current;
    if (!el || !canPageBack) return;
    // Older is UPWARD: the feed reads oldest-first with the newest at the bottom.
    const near = el.scrollTop <= SCROLL_BACK_THRESHOLD_PX;
    if (near) {
      if (!wasNear.current) onScrollGesture?.();
      onLoadOlder?.();
    }
    wasNear.current = near;
  }, [canPageBack, onLoadOlder, onScrollGesture]);

  // The OTHER way into the budget, and the reason the edge above can't be the only one: a
  // reader who scrolls to the very top and keeps pushing never leaves the zone, so the
  // edge never fires again and "scroll again to load more history" names a gesture that
  // cannot be performed. A raw INPUT event is the missing signal — unlike `scroll`, none of
  // them is ever synthesized by a `scrollTop` write, so the prepended-page feedback loop
  // the edge gate exists to stop still cannot reach the budget through here.
  //
  // The throttle is what keeps this a budget: without it one flick's worth of `wheel`
  // events re-arms it dozens of times and MAX_AUTOPAGE_FETCHES never binds. `onLoadOlder`
  // itself is left unthrottled — it latches on its own in-flight fetch, and inside the
  // zone every call is a call the reader asked for.
  const lastRearm = useRef(0);
  const rearmAndLoad = useCallback(() => {
    const el = bodyRef.current;
    if (!el || !canPageBack) return;
    if (el.scrollTop > SCROLL_BACK_THRESHOLD_PX) return;
    const now = Date.now();
    if (now - lastRearm.current >= GESTURE_REARM_MS) {
      lastRearm.current = now;
      onScrollGesture?.();
    }
    onLoadOlder?.();
  }, [canPageBack, onLoadOlder, onScrollGesture]);

  // Direction matters: older is UPWARD, so only an upward push is a request for more
  // history. Wheeling DOWN is the reader moving forward through the page that just
  // arrived — treating that as "give me more" is the opposite of what they did.
  const handleWheel = useCallback(
    (e: WheelEvent<HTMLElement>) => {
      if (e.deltaY >= 0) return;
      rearmAndLoad();
    },
    [rearmAndLoad],
  );

  // Touch has no deltaY, so the direction comes from the finger: dragging DOWN the screen
  // pulls the content down, which moves the viewport UP — towards older.
  const lastTouchY = useRef<number | null>(null);
  const handleTouchStart = useCallback((e: TouchEvent<HTMLElement>) => {
    lastTouchY.current = e.touches[0]?.clientY ?? null;
  }, []);
  const handleTouchMove = useCallback(
    (e: TouchEvent<HTMLElement>) => {
      const y = e.touches[0]?.clientY ?? null;
      const prev = lastTouchY.current;
      lastTouchY.current = y;
      if (y == null || prev == null || y <= prev) return;
      rearmAndLoad();
    },
    [rearmAndLoad],
  );

  // Keyboard and scrollbar readers need a way in too, or "scroll again to load more
  // history" names a gesture they cannot perform: the edge gate skips them (they are
  // already parked inside the zone) and wheel/touch are devices they aren't using, so a
  // spent budget — and a failed page's "scroll to retry" — is a permanent dead end for
  // them. The key handler defers to the next frame because the browser scrolls AFTER the
  // keydown, and the threshold has to be read against where the pane ends up.
  const handleKeyDown = useCallback(
    (e: KeyboardEvent<HTMLElement>) => {
      onArrowNav(e);
      if (!canPageBack) return;
      if (e.key !== "Home" && e.key !== "PageUp" && e.key !== "ArrowUp") return;
      requestAnimationFrame(() => rearmAndLoad());
    },
    [onArrowNav, canPageBack, rearmAndLoad],
  );

  // Keep pulling older pages while the list the reader can actually SEE is too short to
  // fill the pane — so an active filter that leaves the live page nearly empty pages its
  // way to something rather than sitting on a blank pane until the reader scrolls. Gated
  // on `shown`, the count after the source filter and the text search, which is why this
  // lives here rather than in the caller. `onLoadOlder` no-ops past the auto-page budget,
  // so this cannot outrun it; a FAILED page stops it, or it would hammer a broken endpoint
  // for as long as the pane stayed under the threshold.
  useEffect(() => {
    if (!canPageBack || historyLoading || historyExhausted || historyError) return;
    if (shown.length >= MIN_FILLED_ROWS) return;
    onLoadOlder?.();
  }, [canPageBack, historyLoading, historyExhausted, historyError, shown.length, onLoadOlder]);
  // Recent Activity tails to the BOTTOM, because that is where its newest row is:
  // `rows` arrives in the order `/api/board` emits it, and the server sorts activity
  // oldest-first (`derive-activity.ts` sorts ascending by `at`, ties broken by id).
  // So `shown[shown.length - 1]` is the NEWEST row and `shown[0]` is the OLDEST — a
  // log that reads forwards, with the freshest deploy arriving under the reader's eyes
  // at the tail.
  //
  // `count` is passed so an insert anywhere in the order still re-fires the tail,
  // not just a change at an end. Problems renders top-anchored and doesn't tail —
  // pass a constant 0 count (like PaneShell's follow=false) so the hook never
  // re-fires on a poll and yanks the reader's scroll; native scroll-anchoring
  // keeps their place. Problems still passes edge "bottom" alongside it, but only
  // nominally: with constant keys and count 0 the hook never fires there, so the edge
  // it names costs nothing — it stays in step with the shared oldest-first order
  // rather than claiming a second one.
  useFollowNewItems(
    bodyRef,
    "bottom",
    tail && shown.length ? shown[shown.length - 1]!.key : null,
    tail && shown.length ? shown[0]!.key : null,
    tail ? shown.length : 0,
  );

  // --- options gear: changed-from-default count + hover synopsis ------------
  // Show EVERY source in the store (in canonical order), not just this panel's
  // currently-displayed rows — so the choices don't come and go with the env filter.
  const sourceOptions = ISSUE_SOURCES.filter((s) => allSources.includes(s));
  const sourcesActive = sourceOptions.length > 1;
  const deselectedSources = sourcesActive ? sourceOptions.filter((s) => !sources.has(s)).length : 0;
  const deselectedEnvs = allEnvs.filter((e) => !envs.has(e)).length;
  const ttlChanged = kind === "activity" && ttlMin !== DEFAULT_TTL_MIN ? 1 : 0;
  const canceledChanged = kind === "activity" && showCanceled ? 1 : 0;
  const changedCount = deselectedSources + deselectedEnvs + ttlChanged + canceledChanged;

  const envSummary = deselectedEnvs === 0 ? "all" : allEnvs.filter((e) => envs.has(e)).join(", ") || "none";
  const summaryLines = [
    sourcesActive ? `Sources: ${sourceOptions.length - deselectedSources}/${sourceOptions.length}` : null,
    `Environments: ${envSummary}`,
    kind === "activity" ? `Show canceled: ${showCanceled ? "on" : "off"}` : null,
    kind === "activity" ? `Age out: ${ttlMin == null ? "off" : `${ttlMin}m`}` : null,
  ].filter(Boolean);

  const gearContent = (close: () => void): ReactNode => (
    <div style={{ display: "flex", flexDirection: "column", gap: 2, minWidth: 0 }}>
      {sourcesActive && (
        <OptionSection title="Sources">
          {sourceOptions.map((s) => {
            const on = sources.has(s);
            return (
              <label key={s} style={optionRow(on)}>
                <input className="adh-check" type="checkbox" checked={on} onChange={() => toggleSource(s)} aria-label={`source ${SOURCE_LABEL[s]}`} />
                {SOURCE_LABEL[s]}
              </label>
            );
          })}
        </OptionSection>
      )}
      {sourcesActive && <OptionDivider />}
      <OptionSection title="Environments">
        {allEnvs.map((env) => {
          const on = envs.has(env);
          return (
            <label key={env} style={{ ...optionRow(on), color: on ? envColor(env) : PALETTE.dim }}>
              <input className="adh-check" type="checkbox" checked={on} onChange={() => onToggleEnv(env)} aria-label={env} />
              {env}
            </label>
          );
        })}
      </OptionSection>
      {kind === "activity" && (
        <>
          <OptionDivider />
          <OptionSection title="Activity">
            <label style={optionRow(showCanceled)}>
              <input
                className="adh-check"
                type="checkbox"
                checked={showCanceled && canceledAvailable}
                disabled={!canceledAvailable}
                onChange={(e) => onShowCanceledChange?.(e.target.checked)}
                aria-label="show canceled deployments"
              />
              show canceled
            </label>
          </OptionSection>
          <OptionDivider />
          <OptionSection title="Age out activity after">
            {ACTIVITY_TTL_OPTIONS_MIN.map((m) => (
              <label key={m} style={optionRow(ttlMin === m)}>
                <input
                  className="adh-check"
                  type="radio"
                  name={`ttl-${title}`}
                  checked={ttlMin === m}
                  onChange={() => {
                    onTtlChange?.(m);
                    close();
                  }}
                  aria-label={`age out activity after ${m} minutes`}
                />
                {m} min
              </label>
            ))}
            <label style={optionRow(ttlMin == null)}>
              <input
                className="adh-check"
                type="radio"
                name={`ttl-${title}`}
                checked={ttlMin == null}
                onChange={() => {
                  onTtlChange?.(null);
                  close();
                }}
                aria-label="keep activity (never age out)"
              />
              never
            </label>
          </OptionSection>
        </>
      )}
    </div>
  );

  // Copy the SHOWN rows; hide the button when there's nothing to copy.
  const copy = shown.length > 0 ? <CopyButton getText={() => rowsToText(shown, nowMs)} label={`copy ${title}`} /> : undefined;
  // Clear removes the whole record (every env), so its enabled state keys off the
  // store-wide presence (clearDisabled), not the env-filtered view.
  const clearOff = clearDisabled ?? rows.length === 0;

  const actions = (
    <>
      {kind === "activity" && onClear && (
        <button
          type="button"
          onClick={onClear}
          disabled={clearOff}
          aria-label="clear activity"
          title="clear activity (live problems are kept)"
          className="adh-panel-clear"
          style={{
            appearance: "none",
            background: COLORS.surfaceDeep,
            border: `1px solid ${COLORS.border}`,
            borderRadius: 6,
            color: clearOff ? PALETTE.dim : PALETTE.muted,
            cursor: clearOff ? "not-allowed" : "pointer",
            fontFamily: mono,
            fontSize: 11,
            whiteSpace: "nowrap",
            padding: "4px 8px",
            flexShrink: 0,
          }}
        >
          {/* The word is the affordance when the panel has room for it; on a narrow
              panel it compacts to the eraser glyph (container query) so the filter box
              and the options gear keep theirs. aria-label/title carry the meaning in
              both states, so the icon-only form loses nothing but the pixels. */}
          <Eraser aria-hidden size={12} className="adh-panel-clear__icon" />
          <span className="adh-panel-clear__label">clear</span>
        </button>
      )}
      {/* adh-panel-filter: the one elastic control in the header — a narrow panel
          shrinks it (container query in globals.css) so the gear beside it and the
          refresh icon in the centre slot stay inside the panel. */}
      <div className="adh-panel-filter relative w-[120px] shrink-0">
        <Input
          type="text"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          onKeyDown={onArrowNav}
          placeholder="filter…"
          aria-label={`filter ${title}`}
          role="combobox"
          aria-controls={listboxId}
          aria-expanded={shown.length > 0}
          aria-activedescendant={selected ? optionId(selected.key) : undefined}
          disabled={rows.length === 0}
          spellCheck={false}
          autoComplete="off"
          className={cn("h-7 text-xs", q && "pr-6")}
        />
        {/* Clear (×) — shown whenever the field has content, even while disabled, so
            a stale query left behind when the box greys out is always clearable. */}
        {q && (
          <button
            type="button"
            aria-label={`clear filter ${title}`}
            onClick={() => setQ("")}
            className="absolute top-1/2 right-1 flex size-4 -translate-y-1/2 items-center justify-center rounded text-apt-text-muted hover:text-apt-text"
          >
            ×
          </button>
        )}
      </div>
      <OptionsGear changedCount={changedCount} summary={summaryLines.join("\n")} label={`${title} options`}>
        {gearContent}
      </OptionsGear>
    </>
  );

  // Problems, when truly empty, gets a big centered green check (not a text line).
  const allClear = kind === "problems" && rows.length === 0;
  const emptyText =
    rows.length === 0
      ? envFiltered
        ? "No activity in the selected environments…"
        : "No recent build, deploy, or availability changes…"
      : "no matches";

  // The scroll-back status line, and the one place it may live: ABOVE the scroll
  // container, never inside it. Inside, it was a child of the element `useFollowNewItems`
  // measures — invisible to that hook's deps (which are derived from `shown` alone), so it
  // appeared and vanished with no scroll compensation while `overflowAnchor` was off; and
  // `measureAnchor` could pick it as the reader's anchor row, after which it unmounted and
  // the fallback under-compensated by exactly one line. Out here it is also no longer a
  // non-option child of a `role="listbox"`, which is what the `role="presentation"` it
  // used to carry was papering over.
  //
  // One line at most, in priority order: loading, then the error (never conflated with
  // exhausted — one says nothing is older, the other says we don't know), then exhausted,
  // then budget-spent, then the age-out explanation. A page arriving just as the budget
  // trips still reads "loading" rather than flashing "scroll again" first.
  const historyStatus =
    kind !== "activity" ? null : historyLoading ? (
      "loading older activity…"
    ) : historyError ? (
      "couldn't load older activity — scroll to retry"
    ) : historyExhausted ? (
      "beginning of recorded activity"
    ) : historyBudgetSpent ? (
      "scroll again to load more history"
    ) : historyDisabledReason === "age-out" ? (
      "older activity is hidden by age-out — set it to “never” to scroll further back"
    ) : historyDisabledReason === "cleared" ? (
      "activity was cleared — reload to scroll back through older activity"
    ) : null;

  const listPane = (
    <div style={{ height: "100%", display: "flex", flexDirection: "column", minHeight: 0 }}>
      {historyStatus !== null && <div style={{ ...emptyStyle, padding: "8px 12px 0" }}>{historyStatus}</div>}
      <div
        ref={bodyRef}
        id={listboxId}
        role="listbox"
        aria-label={title}
        // Focusable so arrow-nav works after a click, not only from the filter box.
        // aria-activedescendant marks the active row (no container outline needed).
        tabIndex={0}
        aria-activedescendant={selected ? optionId(selected.key) : undefined}
        onKeyDown={handleKeyDown}
        onScroll={handleScroll}
        onWheel={handleWheel}
        onTouchStart={handleTouchStart}
        onTouchMove={handleTouchMove}
        // A mousedown inside the zone is the scrollbar-dragging reader's equivalent of a
        // wheel tick: a deliberate act the browser never synthesizes.
        onMouseDown={rearmAndLoad}
        data-testid={kind === "activity" ? "activity-list" : "problems-list"}
        style={{
          flex: 1,
          minHeight: 0,
          overflowY: "auto",
          padding: "8px 10px 10px",
          outline: "none",
          // While this panel TAILS, useFollowNewItems owns the scroll position: it holds a
          // scrolled-away reader's row itself, measuring that row's own shift. The browser's
          // native scroll anchoring answers the same question, so leaving it on would give
          // the pane two producers of one number — they compound into a double shift, and
          // an assertion about where the reader ended up can't tell which one put them
          // there (e2e/activity-tail.spec.ts says so at the assertion). Problems does NOT
          // tail: the hook is inert there (constant keys, count 0 — it never re-fires), so
          // native anchoring is the ONLY thing keeping a reader's place and must stay on.
          overflowAnchor: tail ? "none" : undefined,
        }}
      >
        {/* Rows are the listbox's ONLY children — no status line, no per-row wrapper. Both
            would give the listbox non-option children, the structure `role="option"` and
            `aria-activedescendant` depend on, and both would sit inside the element
            `useFollowNewItems` measures. An e2e spec needs no wrapper anyway: `optionId(r.key)`
            is already a unique per-row DOM id it can select on. */}
        {shown.map((r) => (
          <StatusRow
            key={r.key}
            id={optionId(r.key)}
            {...rowToStatusRowProps(r, nowMs)}
            // Problems each carry a copy button (before the status word) that yields the
            // full labeled diagnostics block — the same text the details pane copies —
            // so a problem's logs/links/commit can be grabbed without selecting it.
            copyGetText={kind === "problems" ? () => rowDetailToText(rowToDetailProps(r)) : undefined}
            selected={selected?.key === r.key}
            // Focus the list on select so ↑/↓ immediately drive the selection.
            onSelect={() => {
              setSelectedKey(r.key);
              bodyRef.current?.focus({ preventScroll: true });
            }}
          />
        ))}
        {/* Inside the scroll container, so an empty FILTERED list still leaves the pane —
            and with it the scroll container, the gesture handlers and the status line above
            — mounted. See the render below. */}
        {shown.length === 0 && (
          <div role="presentation" style={emptyStyle}>
            {emptyText}
          </div>
        )}
      </div>
    </div>
  );
  const selectedDetail = selected ? rowToDetailProps(selected) : null;
  // The copy-diagnostics button lives inside the card (on the reason/problem line).
  const detailsPane = (
    <div style={{ height: "100%", overflowY: "auto", padding: "8px 12px" }}>
      {selected && selectedDetail ? (
        // Keyed per row so the card's uncontrolled Tabs reset to overview on every
        // selection — without it, "git info" chosen on one row leaks to the next.
        <ActivityDetails key={selected.key} detail={selectedDetail} />
      ) : (
        <div style={emptyStyle}>Select a row to see details…</div>
      )}
    </div>
  );

  return (
    <InfoPanel
      // Size container for the header's container queries — the header has to react
      // to how wide THIS panel is, which on a three-column board is nothing like how
      // wide the viewport is.
      className="adh-panel-cq"
      icon={icon}
      title={title}
      titleAfter={copy}
      count={showCount ? shown.length : undefined}
      center={center}
      actions={actions}
      scroll
      flex={flex}
      maxHeight={maxHeight}
      bodyPadding="0"
    >
      {allClear ? (
        <div style={{ height: "100%", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 12, textAlign: "center", padding: 24 }}>
          <StatusSign state="ok" size={76} />
          <div style={{ fontFamily: mono, fontSize: 13, fontWeight: 600, color: PALETTE.green }}>No problems</div>
          <div style={{ fontFamily: mono, fontSize: 12, color: PALETTE.dim }}>all monitored sites are healthy</div>
        </div>
      ) : (rows.length === 0 || shown.length === 0) && !canPageBack && historyStatus === null ? (
        // An empty pane that CAN page back keeps `listPane` instead of this centered
        // state. Swapping it out destroyed the scroll container — and with it the only
        // route to another page (the gesture handlers), the status line saying why the
        // pane is empty, and any chance of the auto-fill rule being seen to work. Empty
        // is exactly when a reader most needs to be able to reach for more history.
        //
        // `historyStatus` keeps it mounted too, and paging back is exactly when it is
        // NULL: with age-out on, `canPageBack` is false and the only line that explains
        // WHY there is no history — "older activity is hidden by age-out" — lives inside
        // `listPane`. Falling through to the centered state made that line unreachable in
        // the one state where the setting is invisible from what's on screen. `listPane`
        // renders `emptyText` inside its own scroll container, so nothing is lost.
        <div style={{ padding: "8px 16px" }}><div style={emptyStyle}>{emptyText}</div></div>
      ) : (
        <ResizableSplit
          className="h-full"
          storageKey={`adh-status-split-${kind}`}
          defaultRatio={0.6}
          top={listPane}
          bottom={detailsPane}
          header="Details"
          bottomLabel="Details"
        />
      )}
    </InfoPanel>
  );
}
