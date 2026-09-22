"use client";

import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type KeyboardEvent, type ReactElement } from "react";
import { HierarchicalDetailView, ListHeader, type TopicLevel, type TopicDetailItem } from "@agenticdevelopertoolkit/ui/blocks";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@agenticdevelopertoolkit/ui/components/dialog";
import { DialogActions } from "@agenticdevelopertoolkit/ui/components/dialog-actions";
import { AlertModal } from "@agenticdevelopertoolkit/ui/components/alert-modal";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import type { CatalogFeature } from "@agentic-toolkit/data/ecosystems";

/**
 * The FEATURE PICKER: what an ecosystem gets provisioned with.
 *
 * An ecosystem is a container that starts EMPTY, so this dialog is how anything at all
 * gets into it. Pick several features, confirm, and the backend provisions each one's
 * artifacts in a single transaction.
 *
 * Built on the shared stack rather than a bespoke list because the picker is a
 * list-plus-details surface and `HierarchicalDetailView` already is one — its `checkable`
 * mode gives the checkboxes, `headerSlot` gives the filter field, and its detail pane
 * gives the description + subscription line. The one thing it does NOT give is keyboard
 * navigation of the rows (the rail has no key handling at all), which is why the arrow /
 * space handling below is written here.
 *
 * Purely presentational: it holds the filter text, the ticks and the confirm, and hands
 * the chosen keys back. Fetching the catalog and POSTing the batch belong to the caller.
 */
export interface FeaturePickerDialogProps {
  open: boolean;
  /**
   * Every feature in the catalog. Rendered alphabetically by label, whatever order this is in, with
   * the `comingSoon` ones last under a "Coming soon" divider, their checkboxes disabled.
   */
  catalog: CatalogFeature[];
  /**
   * Keys the ecosystem ALREADY has (active or still provisioning). Rendered ticked and
   * marked "Added", and their tick cannot be cleared — this dialog adds, it never removes.
   * They are excluded from the "Add N" count for the same reason.
   */
  alreadyProvisioned?: ReadonlySet<string>;
  /** The add is in flight — the footer shows a spinner and the dialog cannot be dismissed. */
  busy?: boolean;
  /** A failed add, shown under the list. The ticks survive so the user can simply retry. */
  error?: string | null;
  /** Confirmed. Receives only the NEWLY ticked keys, in catalog order. */
  onAdd: (keys: string[]) => void;
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
  busy = false,
  error = null,
  onAdd,
  onCancel,
}: FeaturePickerDialogProps): ReactElement {
  const provisioned = alreadyProvisioned ?? EMPTY;

  const [query, setQuery] = useState("");
  // The rows the user has ticked THIS visit — never includes an already-provisioned key.
  const [picked, setPicked] = useState<ReadonlySet<string>>(EMPTY);
  // The row whose description the detail pane is showing. Also the arrow keys' cursor:
  // one concept, because a keyboard cursor that did not drive the details pane would be a
  // second highlight on the same list meaning something else.
  const [activeId, setActiveId] = useState<string | null>(null);
  const [confirming, setConfirming] = useState(false);

  // A fresh open is a fresh pick — nothing carries over from the last time the dialog ran.
  useEffect(() => {
    if (!open) return;
    setQuery("");
    setPicked(EMPTY);
    setActiveId(null);
    setConfirming(false);
  }, [open]);

  const visible = useMemo(() => visibleFeatures(catalog, query), [catalog, query]);
  const byKey = useMemo(() => new Map(catalog.map((f) => [f.key, f])), [catalog]);

  // The order the backend is asked for is the CATALOG's, not the click order: the batch is a
  // set, and a stable order makes the request reproducible.
  const pickedKeys = useMemo(
    () => catalog.filter((f) => picked.has(f.key) && !f.comingSoon).map((f) => f.key),
    [catalog, picked],
  );

  const toggle = useCallback(
    (key: string) => {
      if (provisioned.has(key)) return; // already there — the tick is a statement, not a control
      if (byKey.get(key)?.comingSoon) return; // not built — nothing to provision
      setPicked((prev) => {
        const next = new Set(prev);
        if (!next.delete(key)) next.add(key);
        return next;
      });
    },
    [provisioned, byKey],
  );

  // Ticked = picked ∪ already-provisioned. The provisioned ones read as ticked because they
  // ARE in the ecosystem; `toggle` is what makes them immovable.
  const checkedIds = useMemo(() => {
    const s = new Set(picked);
    for (const key of provisioned) s.add(key);
    return s;
  }, [picked, provisioned]);

  const items: TopicDetailItem[] = useMemo(
    () =>
      visible.map((f, i) => {
        const next = visible[i + 1];
        return {
          id: f.key,
          label: f.label,
          trailing: provisioned.has(f.key) ? <AddedMark /> : undefined,
          // Already in the ecosystem, or not built yet: the tick is DISABLED — this dialog adds
          // only what exists, and never removes — while the row stays selectable so its details
          // can still be read.
          checkDisabled: provisioned.has(f.key) || !!f.comingSoon,
          // The last available row carries the divider that opens the coming-soon group.
          ...(!f.comingSoon && next?.comingSoon ? { dividerAfter: true, dividerLabel: "Coming soon" } : {}),
        };
      }),
    [visible, provisioned],
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

  const openConfirm = useCallback(() => {
    if (pickedKeys.length === 0 || busy) return;
    setConfirming(true);
  }, [pickedKeys.length, busy]);

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
    emptyLabel: query.trim() ? "No features match" : "No features",
    overview: true,
    overviewHelp: "Tick the features to add to this ecosystem.",
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
  const boxRef = useRef<HTMLDivElement>(null);
  const [boxHeight, setBoxHeight] = useState<number | null>(null);
  useLayoutEffect(() => {
    if (!open || query.trim() || catalog.length === 0) return;
    const box = boxRef.current;
    const scroller = box && findScroller(box);
    const content = scroller?.firstElementChild as HTMLElement | null | undefined;
    if (!box || !scroller || !content) return;
    const pad = parseFloat(getComputedStyle(scroller).paddingTop) + parseFloat(getComputedStyle(scroller).paddingBottom);
    const needed = box.offsetHeight - scroller.clientHeight + content.offsetHeight + pad;
    setBoxHeight((prev) => (prev != null && Math.abs(prev - needed) < 1 ? prev : needed));
  }, [open, query, catalog.length, items]);

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
            <DialogTitle>Add features</DialogTitle>
            <DialogDescription>
              An ecosystem starts empty. Adding a feature provisions everything it needs.
            </DialogDescription>
          </DialogHeader>

          {/* HTDV sizes itself with `flex-1`, so its container has to be a flex column — in a plain
                block it resolves to height 0, and its own overflow clip then hides the list
                entirely. Its height is the measured one above (26rem until the first measure);
                `min-h-0` lets the dialog's `max-h` shrink it to fit the window. */}
          <div
            ref={boxRef}
            className="flex min-h-0 shrink flex-col overflow-hidden rounded-lg border border-apt-border"
            style={{ height: boxHeight ?? "26rem" }}
          >
            <HierarchicalDetailView
              levels={[level]}
              showBreadcrumb={false}
              layoutMode="wide"
              manualCollapse={false}
              minDetailWidth="18rem"
            >
              <FeatureDetail feature={active} added={active ? provisioned.has(active.key) : false} />
            </HierarchicalDetailView>
          </div>

          <ErrorText error={error} />

          <DialogActions
            cancelLabel="Cancel"
            onCancel={onCancel}
            confirmLabel={pickedKeys.length > 0 ? `Add ${pickedKeys.length}` : "Add"}
            onConfirm={openConfirm}
            confirmDisabled={pickedKeys.length === 0}
            busy={busy}
            // The filter field autofocuses and owns the keyboard — the footer must not take
            // focus off it on mount, or the first keystroke goes to a button.
            focusOnMount={false}
          />
        </DialogContent>
      </Dialog>

      <AlertModal
        open={confirming}
        title={`Add ${pickedKeys.length} ${pickedKeys.length === 1 ? "feature" : "features"}?`}
        description={pickedKeys.map((k) => byKey.get(k)?.label ?? k).join(", ")}
        confirmLabel="Add"
        cancelLabel="Cancel"
        busy={busy}
        onConfirm={() => {
          setConfirming(false);
          onAdd(pickedKeys);
        }}
        onCancel={() => setConfirming(false)}
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

function AddedMark(): ReactElement {
  return <span className="text-[0.6875rem] tracking-wide text-apt-text-muted uppercase">Added</span>;
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
 */
function FeatureDetail({
  feature,
  added,
}: {
  feature: CatalogFeature | undefined;
  added: boolean;
}): ReactElement | null {
  if (!feature) return null;
  return (
    <div className="flex flex-col gap-4 p-5">
      <div className="flex items-baseline gap-3">
        <h3 className="text-base font-semibold text-apt-text">{feature.label}</h3>
        {added && <AddedMark />}
        {feature.comingSoon && <ComingSoonMark />}
      </div>
      <p className="text-sm text-apt-text-dim">{feature.description}</p>
      {feature.featureSite && (
        <p className="text-sm text-apt-text-dim">
          Comes with a site of its own, published outside this ecosystem.
        </p>
      )}
      <p className="text-sm text-apt-text-muted">
        Subscription Level Required: {feature.subscriptionTier}
      </p>
    </div>
  );
}
