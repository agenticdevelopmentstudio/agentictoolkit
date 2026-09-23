"use client";

import { useCallback, useEffect, useLayoutEffect, useMemo, useState, type KeyboardEvent, type ReactElement } from "react";
import { HierarchicalDetailView, ListHeader, type TopicLevel, type TopicDetailItem } from "@agenticdevelopertoolkit/ui/blocks";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@agenticdevelopertoolkit/ui/components/dialog";
import { DialogActions } from "@agenticdevelopertoolkit/ui/components/dialog-actions";
import { AlertModal } from "@agenticdevelopertoolkit/ui/components/alert-modal";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import type { CatalogFeature, FeatureChange } from "@agentic-toolkit/data/ecosystems";

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
   * the `comingSoon` ones last under a "Coming soon" divider, their checkboxes disabled.
   */
  catalog: CatalogFeature[];
  /**
   * Keys the ecosystem ALREADY has (active or still provisioning). Rendered ticked; unticking
   * one queues its removal.
   */
  alreadyProvisioned?: ReadonlySet<string>;
  /** The change is in flight — the footer shows a spinner and the dialog cannot be dismissed. */
  busy?: boolean;
  /** A failed change, shown under the list. The ticks survive so the user can simply retry. */
  error?: string | null;
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
  busy = false,
  error = null,
  onApply,
  onCancel,
}: FeaturePickerDialogProps): ReactElement {
  const provisioned = alreadyProvisioned ?? EMPTY;

  const [query, setQuery] = useState("");
  // The rows the user has FLIPPED this visit. A row is ticked when it is provisioned XOR flipped,
  // so a provisioned key here is a removal and any other key an add — and the ecosystem's list can
  // arrive after the dialog opens without clobbering what the user already did.
  const [flipped, setFlipped] = useState<ReadonlySet<string>>(EMPTY);
  // The row whose description the detail pane is showing. Also the arrow keys' cursor:
  // one concept, because a keyboard cursor that did not drive the details pane would be a
  // second highlight on the same list meaning something else.
  const [activeId, setActiveId] = useState<string | null>(null);
  const [confirming, setConfirming] = useState(false);

  // A fresh open is a fresh pick — nothing carries over from the last time the dialog ran.
  useEffect(() => {
    if (!open) return;
    setQuery("");
    setFlipped(EMPTY);
    setActiveId(null);
    setConfirming(false);
  }, [open]);

  const visible = useMemo(() => visibleFeatures(catalog, query), [catalog, query]);
  const byKey = useMemo(() => new Map(catalog.map((f) => [f.key, f])), [catalog]);

  // The order the backend is asked for is the CATALOG's, not the click order: each batch is a
  // set, and a stable order makes the request reproducible.
  const change: FeatureChange = useMemo(() => {
    const flippedKeys = catalog.filter((f) => flipped.has(f.key) && !f.comingSoon).map((f) => f.key);
    return {
      add: flippedKeys.filter((k) => !provisioned.has(k)),
      remove: flippedKeys.filter((k) => provisioned.has(k)),
    };
  }, [catalog, flipped, provisioned]);
  const changeCount = change.add.length + change.remove.length;

  const toggle = useCallback(
    (key: string) => {
      if (byKey.get(key)?.comingSoon) return; // not built — nothing to provision
      setFlipped((prev) => {
        const next = new Set(prev);
        if (!next.delete(key)) next.add(key);
        return next;
      });
    },
    [byKey],
  );

  const checkedIds = useMemo(() => {
    const s = new Set<string>();
    for (const f of catalog) if (provisioned.has(f.key) !== flipped.has(f.key)) s.add(f.key);
    return s;
  }, [catalog, flipped, provisioned]);

  const items: TopicDetailItem[] = useMemo(
    () =>
      visible.map((f, i) => {
        const next = visible[i + 1];
        return {
          id: f.key,
          label: f.label,
          // Not built yet: the tick is DISABLED, while the row stays selectable so its details
          // can still be read.
          checkDisabled: !!f.comingSoon,
          // The last available row carries the divider that opens the coming-soon group.
          ...(!f.comingSoon && next?.comingSoon ? { dividerAfter: true, dividerLabel: "Coming soon" } : {}),
        };
      }),
    [visible],
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
    if (changeCount === 0 || busy) return;
    setConfirming(true);
  }, [changeCount, busy]);

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
          >
            <HierarchicalDetailView
              levels={[level]}
              showBreadcrumb={false}
              layoutMode="wide"
              manualCollapse={false}
              minDetailWidth="18rem"
            >
              <FeatureDetail feature={active} />
            </HierarchicalDetailView>
          </div>

          <ErrorText error={error} />

          <DialogActions
            cancelLabel="Cancel"
            onCancel={onCancel}
            confirmLabel="Apply"
            onConfirm={openConfirm}
            confirmDisabled={changeCount === 0}
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
 */
function FeatureDetail({ feature }: { feature: CatalogFeature | undefined }): ReactElement | null {
  if (!feature) return null;
  return (
    <div className="flex flex-col gap-4 p-5">
      <div className="flex items-baseline gap-3">
        <h3 className="text-base font-semibold text-apt-text">{feature.label}</h3>
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
