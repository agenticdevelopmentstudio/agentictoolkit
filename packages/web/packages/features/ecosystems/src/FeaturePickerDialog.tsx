"use client";

import { useCallback, useEffect, useLayoutEffect, useMemo, useState, type KeyboardEvent, type ReactElement } from "react";
import { HierarchicalDetailView, ListHeader, type TopicLevel, type TopicDetailItem } from "@agenticdevelopertoolkit/ui/blocks";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@agenticdevelopertoolkit/ui/components/dialog";
import { DialogActions } from "@agenticdevelopertoolkit/ui/components/dialog-actions";
import { AlertModal } from "@agenticdevelopertoolkit/ui/components/alert-modal";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { Badge } from "@agenticdevelopertoolkit/ui/components/badge";
import {
  featuresAddedWith,
  neededBy,
  neededByMessage,
  requiredClosure,
  type CatalogFeature,
  type FeatureChange,
} from "@agentic-toolkit/data/ecosystems";

/**
 * The FEATURE PICKER ("Manage features"): what an ecosystem has.
 *
 * An ecosystem is a container that starts EMPTY, so this dialog is how anything at all
 * gets into it — and how it comes back out. Ticked rows are what the ecosystem has: tick a
 * row to add that feature, untick one it already has to remove it, confirm once for both.
 * Removing HIDES and DISABLES the feature (its REST routes and MCP tools refuse) and keeps
 * every row of its data; adding it back brings all of it back. The confirm says so.
 *
 * Built on the shared stack rather than a bespoke list because the picker is a
 * list-plus-details surface and `HierarchicalDetailView` already is one — its `checkable`
 * mode gives the checkboxes, `headerSlot` gives the filter field, and its detail pane
 * gives the description + subscription line. The one thing it does NOT give is keyboard
 * navigation of the rows (the rail has no key handling at all), which is why the arrow /
 * space handling below is written here.
 *
 * Purely presentational: it holds the filter text, the ticks and the confirm, and hands
 * the change back. Fetching the catalog and applying the change belong to the caller.
 */
export interface FeaturePickerDialogProps {
  open: boolean;
  /**
   * Every feature in the catalog. Rendered alphabetically by label, whatever order this is in, with
   * the `comingSoon` ones last under a "Coming soon" divider, their checkboxes disabled — all but
   * one the ecosystem already holds, which can still be unticked (never ticked), since this picker
   * is the only way to take a feature off. For the same reason a caller may add rows the catalog
   * no longer lists for features still held (`ManageFeaturesDialog` does).
   */
  catalog: CatalogFeature[];
  /**
   * Keys the ecosystem ALREADY has (active or still provisioning). Rendered ticked; unticking
   * one queues its removal.
   */
  alreadyProvisioned?: ReadonlySet<string>;
  /**
   * The held keys whose provisioning has not finished (a subset of `alreadyProvisioned`). Each
   * row gets a "Provisioning" badge and its details say so: a feature stuck there is otherwise a
   * ticked box indistinguishable from one that works.
   */
  provisioning?: ReadonlySet<string>;
  /**
   * Features THIS ecosystem may not add, keyed to the sentence that says why — from the feature
   * manager (`useEcosystemFeatures().unavailable`), which reads it from the server: a client
   * ecosystem cannot hold Organizations. Each row's tick is disabled and its details give the
   * reason; like a coming-soon row, one the ecosystem already holds can still be unticked.
   * Nothing brings one in as another feature's requirement either.
   */
  unavailable?: ReadonlyMap<string, string>;
  /** The change is in flight — the footer shows a spinner and the dialog cannot be dismissed. */
  busy?: boolean;
  /**
   * The lists this works from (the catalog, `alreadyProvisioned`) are still being read. Ticks and
   * Apply wait for them — a change computed before `alreadyProvisioned` arrives would re-add what
   * the ecosystem already holds — but unlike `busy` the dialog stays dismissable. A read has no
   * timeout: passed as `busy`, a hung or offline one left no way out of the dialog but a reload.
   */
  loading?: boolean;
  /** A failed change, shown under the list. The ticks survive so the user can simply retry. */
  error?: string | null;
  /**
   * A failed READ of what the ecosystem holds, shown under the list ALONGSIDE `error` rather than
   * instead of it: one slot for both meant a failed apply behind a failed refresh said only one of
   * the two things that went wrong. Whether ticks may proceed is `loading`'s call, not this one's.
   */
  loadError?: string | null;
  /**
   * The catalog failed to load. Without this the dialog has nothing to distinguish from — an
   * empty `catalog` prop looks exactly like a catalog that is still loading or genuinely empty,
   * so it would sit on "No features" forever instead of saying the fetch failed.
   */
  catalogError?: string | null;
  /** Confirmed. `add` is the newly ticked keys, `remove` the provisioned keys unticked — each in
   *  catalog order. At least one of the two is non-empty. */
  onApply: (change: FeatureChange) => void;
  onCancel: () => void;
}


/**
 * Alphabetical by label, then filtered on label + description — what the rail lists. The
 * coming-soon features follow the rest as their own alphabetical group, under the divider.
 */
function visibleFeatures(catalog: CatalogFeature[], query: string): CatalogFeature[] {
  const sorted = [...catalog].sort(
    (a, b) => Number(!!a.comingSoon) - Number(!!b.comingSoon) || a.label.localeCompare(b.label),
  );
  const q = query.trim().toLowerCase();
  if (!q) return sorted;
  return sorted.filter(
    (f) => f.label.toLowerCase().includes(q) || f.description.toLowerCase().includes(q),
  );
}

export function FeaturePickerDialog({
  open,
  catalog,
  alreadyProvisioned,
  provisioning: provisioningKeys,
  unavailable: unavailableKeys,
  busy = false,
  loading = false,
  error = null,
  loadError = null,
  catalogError = null,
  onApply,
  onCancel,
}: FeaturePickerDialogProps): ReactElement {
  const provisioned = alreadyProvisioned ?? EMPTY;
  const stillProvisioning = provisioningKeys ?? EMPTY;
  const unavailable = unavailableKeys ?? EMPTY_REASONS;

  const [query, setQuery] = useState("");
  // The TARGET state per row the user has touched this visit: key -> desired on/off. A row not
  // in the map just follows `provisioned`. This is deliberately NOT an XOR-against-provisioned
  // set (what it used to be): `alreadyProvisioned` refetches mid-visit — after a partial apply
  // failure, most visibly — and XOR against a NEW list inverts intent, since membership in the
  // set no longer means what it meant when the user clicked. A stored target survives that
  // refetch untouched: "add" still means add, "remove" still means remove, whatever the
  // ecosystem now reports.
  const [desired, setDesired] = useState<ReadonlyMap<string, boolean>>(EMPTY_MAP);
  // The row whose description the detail pane is showing. Also the arrow keys' cursor:
  // one concept, because a keyboard cursor that did not drive the details pane would be a
  // second highlight on the same list meaning something else.
  const [activeId, setActiveId] = useState<string | null>(null);
  const [confirming, setConfirming] = useState(false);
  // A blocked tick-off: the feature just clicked, and the features (from `catalog`) still on
  // that need it. Non-null opens the refusal alert; `toggle` never mutates `desired` while it
  // does, so the row stays checked with nothing else to undo.
  const [blockedBy, setBlockedBy] = useState<{ feature: CatalogFeature; blockers: CatalogFeature[] } | null>(null);
  // The row currently hovered / currently focused, tracked separately since either alone must
  // show the "Needed by" row's floating hint (a mouse leaving a still-focused row must not hide
  // it). Driven by delegated `focus`/`blur`/`mouseover`/`mouseout` on the box below rather than a
  // handler on the marker itself: the marker is deliberately NOT a focusable element (see the
  // `items` memo), so it has nothing of its own to attach a listener to — the row's own button
  // is the only thing a keyboard user ever reaches, so that is what has to open the hint.
  const [hoveredRowKey, setHoveredRowKey] = useState<string | null>(null);
  const [focusedRowKey, setFocusedRowKey] = useState<string | null>(null);

  // A fresh open is a fresh pick — nothing carries over from the last time the dialog ran.
  useEffect(() => {
    if (!open) return;
    setQuery("");
    setDesired(EMPTY_MAP);
    setActiveId(null);
    setConfirming(false);
    setBlockedBy(null);
  }, [open]);

  const visible = useMemo(() => visibleFeatures(catalog, query), [catalog, query]);
  const byKey = useMemo(() => new Map(catalog.map((f) => [f.key, f])), [catalog]);
  // A key that may not be ticked ON: not built, or not for this ecosystem. One already held is
  // never refused — this picker is the only way to take a feature off, so its tick stays live.
  const cannotAdd = useCallback(
    (key: string) => !provisioned.has(key) && (!!byKey.get(key)?.comingSoon || unavailable.has(key)),
    [provisioned, byKey, unavailable],
  );

  /** What the row shows RIGHT NOW: the user's touched target, else the ecosystem's own state. */
  const desiredOn = useCallback((key: string) => desired.get(key) ?? provisioned.has(key), [desired, provisioned]);

  // The order the backend is asked for is the CATALOG's, not the click order: each batch is a
  // set, and a stable order makes the request reproducible. A key is a change only when its
  // TARGET differs from what the ecosystem currently has — not merely because it was clicked
  // (clicking a row back to its original state must drop it from the change, not add it twice).
  const change: FeatureChange = useMemo(() => {
    const add: string[] = [];
    const remove: string[] = [];
    for (const f of catalog) {
      if (cannotAdd(f.key)) continue; // a held one may still come OFF
      const on = desiredOn(f.key);
      if (on === provisioned.has(f.key)) continue;
      (on ? add : remove).push(f.key);
    }
    return { add, remove };
  }, [catalog, desiredOn, provisioned, cannotAdd]);
  const changeCount = change.add.length + change.remove.length;

  // Turning a feature ON also turns on everything its `requiresFeatures` closure needs —
  // skipping any comingSoon step of that closure, which cannot be provisioned and so can
  // never legitimately be a requirement in a real catalog, but a defensive skip here means a
  // catalog bug does not throw. Turning one OFF is refused, with nothing touched, while some
  // ON feature still needs it (`neededBy`); the caller finds out via `blockedBy`.
  const toggle = useCallback(
    (key: string) => {
      if (loading) return; // a tick against a list still loading would be read against the wrong baseline
      // Not built, or not for this ecosystem — nothing to provision. One the ecosystem already
      // holds is the exception: it can be unticked (and ticked back, which only cancels that removal).
      if (cannotAdd(key)) return;

      const turningOn = !desiredOn(key);

      if (!turningOn) {
        const blockers = neededBy(key, catalog, desiredOn);
        if (blockers.length > 0) {
          const feature = byKey.get(key);
          if (feature) setBlockedBy({ feature, blockers });
          return;
        }
      }

      const keys = turningOn ? featuresAddedWith(key, catalog, cannotAdd) : [key];

      setDesired((prev) => {
        const next = new Map(prev);
        for (const k of keys) {
          // Back to the ecosystem's own state: drop it rather than storing a no-op target, so a
          // click-then-click-back leaves no residue and the map only ever holds real changes.
          if (turningOn === provisioned.has(k)) next.delete(k);
          else next.set(k, turningOn);
        }
        return next;
      });
    },
    [loading, byKey, provisioned, desiredOn, catalog, cannotAdd],
  );

  const checkedIds = useMemo(() => {
    const s = new Set<string>();
    for (const f of catalog) if (desiredOn(f.key)) s.add(f.key);
    return s;
  }, [catalog, desiredOn]);

  // Every catalog key's currently-ON blockers, keyed once for the whole catalog rather than
  // recomputed per row: `neededBy` walks the whole requirement graph (`requiredClosure` for
  // every ON feature), so calling it once per VISIBLE row inside the `items` memo below would
  // redo that walk up to once per row per render. Fine at today's catalog size (a few dozen
  // features, re-walked only on a catalog/tick change, not on every keystroke — filtering
  // narrows `visible`, not this), so this is a one-time-per-change map rather than a hot loop
  // guard: build it if the catalog ever grows enough for that to matter.
  const neededByKey = useMemo(() => {
    const map = new Map<string, CatalogFeature[]>();
    for (const f of catalog) {
      if (!desiredOn(f.key)) continue;
      for (const dep of requiredClosure(f.key, catalog)) {
        // Same self-exclusion as `neededBy` in feature-requirements.ts (data/ecosystems): a cyclic catalog's
        // `requiredClosure` can include the feature's own key, and a feature is never "needed
        // by" itself.
        if (dep === f.key) continue;
        const blockers = map.get(dep);
        if (blockers) blockers.push(f);
        else map.set(dep, [f]);
      }
    }
    return map;
  }, [catalog, desiredOn]);

  const items: TopicDetailItem[] = useMemo(
    () =>
      visible.map((f, i) => {
        const next = visible[i + 1];
        // Currently-ON features (per the user's own touches this visit) that need this row —
        // empty for one nothing depends on, and for one that is itself off (nothing needs an
        // off feature).
        const blockers = neededByKey.get(f.key) ?? [];
        const trailing: ReactElement[] = [];
        if (stillProvisioning.has(f.key)) {
          trailing.push(
            <Badge key="provisioning" variant="orange">
              Provisioning
            </Badge>,
          );
        }
        if (blockers.length > 0) {
          const labels = blockers.map((b) => b.label).join(", ");
          // NOT a `Tooltip`/`TooltipTrigger`: that would put a second focusable element inside
          // the row's own button (topic-detail.tsx renders `trailing` there), which a keyboard
          // user tabbing through the list could never reach. Instead:
          //  - the count badge is `aria-hidden` and purely visual;
          //  - a plain (non-focusable) sr-only span carries the real words, folded into the
          //    ROW's own accessible name (this file doesn't render — and so can't attach
          //    `aria-describedby` to — the row's `<button>` itself; this is the same technique
          //    the shared rail already uses for `item.blocked`'s ", needs attention" text, and
          //    it reaches the same outcome: a screen reader announces "Needed by X" the moment
          //    the row, which is already focusable and already reachable, gets focus);
          //  - the floating hint bubble is plain, `aria-hidden`, decorative text, shown only
          //    while THIS row is hovered or focused (`hoveredRowKey/focusedRowKey`, set from
          //    delegated events on the box below) — a sighted mouse or keyboard user gets the
          //    same visual affordance a tooltip would have given, without a second control.
          trailing.push(
            <span key="needed-by" className="relative inline-flex items-center">
              <Badge variant="neutral" aria-hidden="true">{`Needed by ${blockers.length}`}</Badge>
              <span className="sr-only">{`Needed by ${labels}`}</span>
              {(f.key === hoveredRowKey || f.key === focusedRowKey) && (
                <span
                  aria-hidden="true"
                  data-slot="tooltip-content"
                  className="pointer-events-none absolute bottom-full left-1/2 z-50 mb-1.5 w-max max-w-56 -translate-x-1/2 rounded-md border border-apt-border bg-apt-surface-2 px-2.5 py-1.5 text-xs text-apt-text shadow-md"
                >
                  {labels}
                </span>
              )}
            </span>,
          );
        }
        return {
          id: f.key,
          label: f.label,
          // Not built yet, or not for this ecosystem: the tick is DISABLED, while the row stays
          // selectable so its details (and why) can still be read. Unless the ecosystem already
          // holds it: this picker is the only way to take a feature off, so a held one keeps its
          // tick live for unticking.
          checkDisabled: cannotAdd(f.key),
          ...(trailing.length > 0 ? { trailing: <>{trailing}</> } : {}),
          // The last available row carries the divider that opens the coming-soon group.
          ...(!f.comingSoon && next?.comingSoon ? { dividerAfter: true, dividerLabel: "Coming soon" } : {}),
        };
      }),
    [visible, cannotAdd, stillProvisioning, neededByKey, hoveredRowKey, focusedRowKey],
  );

  // Keep the cursor on a row that still exists: filtering the active row away would otherwise
  // leave the detail pane describing something the list no longer shows.
  useEffect(() => {
    if (activeId != null && visible.some((f) => f.key === activeId)) return;
    setActiveId(visible.length > 0 ? visible[0]!.key : null);
  }, [visible, activeId]);

  const move = useCallback(
    (delta: number) => {
      if (visible.length === 0) return;
      const at = visible.findIndex((f) => f.key === activeId);
      const next = at === -1 ? 0 : Math.min(visible.length - 1, Math.max(0, at + delta));
      setActiveId(visible[next]!.key);
    },
    [visible, activeId],
  );

  // `loading` is checked here as well as on the Apply button: Enter reaches this without going
  // through the button's disabled state.
  const openConfirm = useCallback(() => {
    if (changeCount === 0 || busy || loading) return;
    setConfirming(true);
  }, [changeCount, busy, loading]);

  /**
   * The picker's keyboard, wired on the filter row because that is where focus lives: the
   * user types to narrow the list and never leaves the field, so the arrows, Space and
   * Return have to work from there. Keydown bubbles out of the `<input>`, so one handler on
   * the wrapper covers the whole header.
   *
   * SPACE CANNOT TYPE A SPACE HERE. It toggles the cursor row instead, which is the
   * requested behaviour and is worth stating plainly: a multi-word filter must be typed
   * without its space ("codereview" still matches nothing, "code" matches). The trade is
   * deliberate — a filter over 35 single-phrase feature names rarely needs a space, while a
   * hand that never leaves the field needs a toggle key.
   *
   * Escape is NOT handled here: Base-UI's dialog owns it, and handling it in both places
   * would cancel twice.
   */
  const onHeaderKeyDown = useCallback(
    (e: KeyboardEvent<HTMLDivElement>) => {
      if (busy || confirming) return;
      if (e.key === "ArrowDown") {
        e.preventDefault();
        move(1);
      } else if (e.key === "ArrowUp") {
        e.preventDefault();
        move(-1);
      } else if (e.key === " ") {
        e.preventDefault();
        if (activeId != null) toggle(activeId);
      } else if (e.key === "Enter") {
        // An IME commits its candidate on Enter too (`isComposing`, and `keyCode === 229` for
        // the browsers that report a synthetic code instead of setting the flag). That keystroke
        // is confirming the TYPED TEXT, not the picker — treating it as "confirm" would open the
        // apply dialog out from under someone still composing a filter.
        if (e.nativeEvent.isComposing || e.keyCode === 229) return;
        e.preventDefault();
        openConfirm();
      }
    },
    [busy, confirming, move, activeId, toggle, openConfirm],
  );

  const level: TopicLevel = {
    // Unique across the app on purpose. HTDV keys its per-surface memory (the pin, the hover
    // reveal, the detail crossfade) by the ROOT level's id, and `surfaceScope` — the prop that
    // would namespace it — is HTDV's alone, absent from the switch's prop type. A root id no
    // other surface uses is the same guarantee without it.
    id: "feature-picker",
    title: "Features",
    railLabel: "Features",
    items,
    selectedId: activeId,
    onSelect: (id) => setActiveId(id),
    // Re-clicking the cursor row must not empty the detail pane: there is exactly one level
    // here, so "cleared" would just be a picker showing nothing about anything.
    onClear: () => {},
    checkable: true,
    checkedIds,
    onToggleChecked: toggle,
    hideItemIcons: true,
    itemNoun: "feature",
    emptyLabel: loading ? "Loading…" : query.trim() ? "No features match" : "No features",
    overview: true,
    overviewHelp: "Tick a feature to add it to this ecosystem; untick one to remove it.",
    width: 280,
    headerSlot: (
      <div onKeyDown={onHeaderKeyDown}>
        <ListHeader
          ariaLabel="Filter features"
          search={{
            value: query,
            onChange: setQuery,
            label: "Filter features",
            placeholder: "Filter features…",
            autoFocus: true,
            grow: true,
          }}
        />
      </div>
    ),
  };

  const active = activeId != null ? byKey.get(activeId) : undefined;

  // The list box is exactly as tall as the WHOLE catalog needs, and no taller; the dialog's own
  // `max-h` then shrinks it to the window when that does not fit, and the list scrolls. Measured
  // rather than computed from a row height, because the rows' height belongs to the shared rail,
  // not to this file. Only an unfiltered list is measured: filtering must not make the dialog jump.
  //
  // The box is held in STATE, not a ref: the dialog's portal mounts its content a render after
  // `open` flips, so an effect keyed on `open` alone runs while the box is still absent. That went
  // unseen while the catalog always arrived after the dialog opened — its arrival re-ran the
  // measure — and surfaced once the rail began reading the same catalog, so it is cached by then.
  const [box, setBox] = useState<HTMLDivElement | null>(null);
  const [boxHeight, setBoxHeight] = useState<number | null>(null);
  useLayoutEffect(() => {
    if (!open || query.trim() || catalog.length === 0) return;
    const scroller = box && findScroller(box);
    const content = scroller?.firstElementChild as HTMLElement | null | undefined;
    if (!box || !scroller || !content) return;
    const pad = parseFloat(getComputedStyle(scroller).paddingTop) + parseFloat(getComputedStyle(scroller).paddingBottom);
    const needed = box.offsetHeight - scroller.clientHeight + content.offsetHeight + pad;
    setBoxHeight((prev) => (prev != null && Math.abs(prev - needed) < 1 ? prev : needed));
  }, [open, query, catalog.length, items, box]);

  // Which VISIBLE row (by catalog key) an event target — the thing itself, or a `relatedTarget`
  // gaining focus / the pointer's next element — landed in, via the row's own `data-htd-row`
  // marker (every real row carries exactly one, in the same order as `visible`; the coming-soon
  // divider does not). `null` for anything outside a row, which is exactly what the box's own
  // `focus`/`blur`/`mouseover`/`mouseout` handlers below want: focus or the pointer having left
  // every row clears the hint.
  const rowKeyFromTarget = useCallback(
    (target: EventTarget | null): string | null => {
      if (!box || !(target instanceof Element)) return null;
      const row = target.closest<HTMLElement>("[data-htd-row]");
      if (!row || !box.contains(row)) return null;
      const rows = box.querySelectorAll<HTMLElement>("[data-htd-row]");
      const index = Array.prototype.indexOf.call(rows, row);
      return index === -1 ? null : (visible[index]?.key ?? null);
    },
    [box, visible],
  );

  return (
    <>
      <Dialog
        open={open}
        onOpenChange={(next) => {
          if (!next && !busy) onCancel();
        }}
      >
        <DialogContent className="flex max-h-[calc(100dvh-2rem)] max-w-4xl flex-col" showClose={!busy}>
          <DialogHeader>
            <DialogTitle>Manage features</DialogTitle>
            <DialogDescription>
              An ecosystem starts empty. Adding a feature provisions everything it needs; removing
              one turns it off and keeps its data.
            </DialogDescription>
          </DialogHeader>

          {/* HTDV sizes itself with `flex-1`, so its container has to be a flex column — in a plain
                block it resolves to height 0, and its own overflow clip then hides the list
                entirely. Its height is the measured one above (26rem until the first measure);
                `min-h-0` lets the dialog's `max-h` shrink it to fit the window. */}
          <div
            ref={setBox}
            className="flex min-h-0 shrink flex-col overflow-hidden rounded-lg border border-apt-border"
            style={{ height: boxHeight ?? "26rem" }}
            // Delegated rather than attached to the marker itself (which is deliberately not
            // focusable — see the `items` memo): a native `focus`/`blur` does not bubble, but
            // React's `onFocus`/`onBlur` map to `focusin`/`focusout`, which do, so a single pair
            // of listeners here sees every row's focus without the rail exposing a per-row hook.
            onFocus={(e) => setFocusedRowKey(rowKeyFromTarget(e.target))}
            onBlur={(e) => setFocusedRowKey(rowKeyFromTarget(e.relatedTarget))}
            onMouseOver={(e) => setHoveredRowKey(rowKeyFromTarget(e.target))}
            onMouseOut={(e) => setHoveredRowKey(rowKeyFromTarget(e.relatedTarget))}
          >
            {catalogError ? (
              // The catalog never arrived — `catalog` is `[]` exactly as it is while still
              // loading, so without this the dialog sits on "No features" forever instead of
              // saying the fetch failed. Same box, so the dialog doesn't jump.
              <div className="flex flex-1 items-center justify-center p-6 text-center">
                <ErrorText error={catalogError} />
              </div>
            ) : (
              <HierarchicalDetailView
                levels={[level]}
                showBreadcrumb={false}
                layoutMode="wide"
                manualCollapse={false}
                minDetailWidth="18rem"
              >
                <FeatureDetail
                  feature={active}
                  provisioning={active != null && stillProvisioning.has(active.key)}
                  unavailableReason={
                    active != null && !provisioned.has(active.key) ? unavailable.get(active.key) : undefined
                  }
                />
              </HierarchicalDetailView>
            )}
          </div>

          <ErrorText error={loadError} />
          <ErrorText error={error} />

          <DialogActions
            cancelLabel="Cancel"
            onCancel={onCancel}
            confirmLabel="Apply"
            onConfirm={openConfirm}
            confirmDisabled={changeCount === 0 || loading}
            busy={busy}
            // The filter field autofocuses and owns the keyboard — the footer must not take
            // focus off it on mount, or the first keystroke goes to a button.
            focusOnMount={false}
          />
        </DialogContent>
      </Dialog>

      <AlertModal
        open={confirming}
        title={confirmTitle(change)}
        description={<ChangeSummary change={change} labelOf={(k) => byKey.get(k)?.label ?? k} />}
        confirmLabel={change.remove.length > 0 ? "Remove" : "Add"}
        cancelLabel="Cancel"
        // A removal is the consequential half: red, and no Enter-to-confirm.
        destructive={change.remove.length > 0}
        busy={busy}
        onConfirm={() => {
          setConfirming(false);
          onApply(change);
        }}
        onCancel={() => setConfirming(false)}
      />

      <AlertModal
        open={blockedBy != null}
        title={`Can't remove ${blockedBy?.feature.label ?? "this feature"}`}
        description={neededByMessage((blockedBy?.blockers ?? []).map((f) => f.label))}
        confirmLabel="OK"
        onConfirm={() => setBlockedBy(null)}
      />
    </>
  );
}

/** The list column's scroll region: the descendant that scrolls vertically. */
function findScroller(root: HTMLElement): HTMLElement | null {
  for (const el of root.querySelectorAll<HTMLElement>("*")) {
    const oy = getComputedStyle(el).overflowY;
    if ((oy === "auto" || oy === "scroll") && el.querySelector('[role="checkbox"], input[type="checkbox"], button')) return el;
  }
  return null;
}

/** One shared empty set, so a default prop and a cleared state are the same identity. */
const EMPTY: ReadonlySet<string> = new Set<string>();
/** One shared empty map, for the same reason — the initial and post-open-reset `desired`. */
const EMPTY_MAP: ReadonlyMap<string, boolean> = new Map<string, boolean>();
const EMPTY_REASONS: ReadonlyMap<string, string> = new Map<string, string>();

function plural(n: number): string {
  return `${n} ${n === 1 ? "feature" : "features"}`;
}

function confirmTitle({ add, remove }: FeatureChange): string {
  if (remove.length === 0) return `Add ${plural(add.length)}?`;
  if (add.length === 0) return `Remove ${plural(remove.length)}?`;
  return `Add ${plural(add.length)} and remove ${plural(remove.length)}?`;
}

/** The confirm's body: what is added, what is removed, and what removing actually does. Spans,
 *  not paragraphs: AlertModal renders its description INSIDE a `<p>`, which may hold no block. */
function ChangeSummary({
  change,
  labelOf,
}: {
  change: FeatureChange;
  labelOf: (key: string) => string;
}): ReactElement {
  return (
    <span className="flex flex-col gap-2">
      {change.add.length > 0 && <span>Add: {change.add.map(labelOf).join(", ")}</span>}
      {change.remove.length > 0 && (
        <>
          <span>Remove: {change.remove.map(labelOf).join(", ")}</span>
          <span>
            A removed feature is hidden and turned off for this ecosystem, including over the REST
            and MCP APIs. Its data is kept, and adding the feature back restores it.
          </span>
        </>
      )}
    </span>
  );
}

function ComingSoonMark(): ReactElement {
  return <span className="text-[0.6875rem] tracking-wide text-apt-text-muted uppercase">Coming soon</span>;
}

/**
 * The details pane: what the cursor row IS, and what it costs.
 *
 * The subscription line is a PLACEHOLDER end to end — the backend serves `Free` for every
 * feature and nothing enforces it. It is rendered anyway because the picker is where the
 * gate will be explained, and a line that appears later changes the layout people learned.
 * The one row without it is a stand-in for a held feature the catalog no longer offers
 * (`ManageFeaturesDialog`), which has no tier: "Subscription Level Required:" followed by
 * nothing would say less than no line at all.
 */
function FeatureDetail({
  feature,
  provisioning,
  unavailableReason,
}: {
  feature: CatalogFeature | undefined;
  /** Held, but its provisioning has not finished. */
  provisioning: boolean;
  /** Why this ecosystem may not add it — set only for a feature it does not already hold. */
  unavailableReason?: string;
}): ReactElement | null {
  if (!feature) return null;
  return (
    <div className="flex flex-col gap-4 p-5">
      <div className="flex items-baseline gap-3">
        <h3 className="text-base font-semibold text-apt-text">{feature.label}</h3>
        {feature.comingSoon && <ComingSoonMark />}
        {provisioning && <Badge variant="orange">Provisioning</Badge>}
      </div>
      <p className="text-sm text-apt-text-dim">{feature.description}</p>
      {unavailableReason && <p className="text-sm text-apt-text">{unavailableReason}</p>}
      {provisioning && (
        <p className="text-sm text-apt-text-dim">
          Still being set up for this ecosystem — it opens once provisioning finishes. Untick it to
          remove it.
        </p>
      )}
      {feature.featureSite && (
        <p className="text-sm text-apt-text-dim">
          Comes with a site of its own, published outside this ecosystem.
        </p>
      )}
      {feature.subscriptionTier && (
        <p className="text-sm text-apt-text-muted">
          Subscription Level Required: {feature.subscriptionTier}
        </p>
      )}
    </div>
  );
}
