"use client";

import type { ReactNode } from "react";
import { Plus, Trash2 } from "lucide-react";

import { AlertModal } from "@agenticdevelopertoolkit/ui/components/alert-modal";
import { cn } from "@agenticdevelopertoolkit/ui/lib/utils";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Separator } from "@agenticdevelopertoolkit/ui/components/separator";
import { SaveCancelButtons } from "./SaveCancelButtons";
import { HelpPopover } from "../HelpPopover";
import { ToolbarPortal } from "../rail-host";

export interface MasterDetailItem {
  id: string;
  label: string;
  sublabel?: string;
}

/**
 * Actions for the top button bar. When provided, the layout renders the bar
 * (Create | Cancel Save … Delete) and the detail must NOT render its own
 * footer/buttons — these drive create/save/cancel/delete instead. The consumer
 * (pane) owns the form draft + dirty/validity state and computes the can* flags.
 */
export interface MasterDetailActions {
  onCreate: () => void;
  createLabel?: string;
  onCancel: () => void;
  canCancel: boolean;
  onSave: () => void;
  canSave: boolean;
  /** Why Save is disabled, or null when nothing is blocking it — rendered beside the button so a
   *  grey Save always says why. Supplied by useMasterDetailForm from the same `validate` that
   *  computes `canSave`; optional so hand-built bars that have no reason to give can omit it. */
  blockedReason?: string | null;
  saving?: boolean;
  onDelete: () => void;
  canDelete: boolean;
  /** Delete-confirm modal, owned by useMasterDetailForm: a non-null `deletePrompt`
   *  opens the shared AlertModal; the rest drive its actions. Optional so the few
   *  hand-built action bars without delete can omit them. */
  deletePrompt?: string | null;
  onConfirmDelete?: () => void;
  onCancelDelete?: () => void;
  deleting?: boolean;
}

function ItemList({
  items,
  selectedId,
  onSelect,
  emptyLabel,
}: {
  items: MasterDetailItem[];
  selectedId: string | null;
  onSelect: (id: string) => void;
  emptyLabel: string;
}) {
  if (items.length === 0) {
    return <p className="px-1 py-2 text-sm text-apt-text-muted">{emptyLabel}</p>;
  }
  return (
    <ul className="flex flex-col gap-1">
      {items.map((item) => {
        const active = item.id === selectedId;
        return (
          <li key={item.id}>
            <button
              type="button"
              onClick={() => onSelect(item.id)}
              aria-current={active ? "true" : undefined}
              className={cn(
                "w-full rounded-md border border-l-2 px-3 py-2 text-left transition-colors",
                active
                  ? "border-apt-border border-l-apt-gold bg-apt-surface-2 text-apt-text"
                  : "border-transparent text-apt-text-muted hover:bg-apt-surface-2/50 hover:text-apt-text",
              )}
            >
              <span className="block truncate text-sm font-medium">{item.label}</span>
              {item.sublabel && (
                <span className="block truncate text-xs text-apt-text-muted">{item.sublabel}</span>
              )}
            </button>
          </li>
        );
      })}
    </ul>
  );
}

/** Feature title row that sits above the button bar: the feature name in the
 * accent color on the left, the "?" help on the far right. */
export function FeatureTitle({
  title,
  trailing,
  help,
}: {
  title: ReactNode;
  /** Optional trailing affordance (e.g. an <ApiButton>), left of the "?" help. */
  trailing?: ReactNode;
  help?: ReactNode;
}) {
  return (
    <div className="flex items-center justify-between gap-4 px-6 pt-8 pb-2">
      <h2 className="font-mono text-sm font-medium tracking-wide text-apt-gold">
        {title}
      </h2>
      <div className="flex items-center gap-2">
        {trailing}
        {help && (
          <HelpPopover>
            {help}
          </HelpPopover>
        )}
      </div>
    </div>
  );
}

/** The recessed master/detail action bar (Create … Delete │ Cancel Save).
 * Exported so single-record editors (e.g. the ecosystem Settings pane) can show
 * the same bar without the master list. */
export function ButtonBar({
  actions,
  showCreate = true,
  showDelete = true,
  title,
  trailing,
  help,
  hoist = true,
}: {
  actions: MasterDetailActions;
  /** Hide the leading "New …" button — e.g. single-record Settings panes where
   *  creation happens through the resource view's top-bar "New …" button instead. */
  showCreate?: boolean;
  /** Hide the Delete button — e.g. resource Settings panes where deletion lives
   *  in the entity pane's own Danger section instead. */
  showDelete?: boolean;
  /** Centered title naming the details pane's contents (the bar may have no buttons). */
  title?: ReactNode;
  /** Optional trailing affordance on the right (before "?"), e.g. an <ApiButton>
   *  for the record being edited. Generic slot — the pane owns what goes here. */
  trailing?: ReactNode;
  /** Help text for the right-justified "?" — describes the pane's contents. */
  help?: ReactNode;
  /**
   * Send the bar to the host's full-width toolbar slot. Default, and right for a bar that acts
   * on THE PANE.
   *
   * Pass `false` for a master/detail nested inside another pane's detail. There is one slot, and
   * a nested bar hoisted into it lands beside the outer pane's own bar — two toolbars stacked in
   * the page header, the inner one naming buttons that act on a list scrolled somewhere below,
   * and no way to tell from looking which Delete deletes what. That was invisible while the
   * standalone host published no slot at all (`ToolbarPortal` fell back to rendering inline, so
   * BOTH bars stayed where they were declared); the moment the slot became real it was the first
   * thing on screen.
   */
  hoist?: boolean;
}) {
  const {
    onCreate,
    createLabel = "New",
    onCancel,
    canCancel,
    onSave,
    canSave,
    blockedReason = null,
    saving = false,
    onDelete,
    canDelete,
    deletePrompt,
    onConfirmDelete,
    onCancelDelete,
    deleting = false,
  } = actions;
  // [New]  ⟷  [Delete] │ [Cancel] [Save] — all borderless "[icon] title".
  // A recessed (darker) strip with top + bottom borders reads as a distinct bar,
  // set off from the tab row above (via the FeatureTabs gap) and the topic|details
  // below (the bottom border + the lighter panel behind them).
  const bar = (
    <div
      role="toolbar"
      aria-label="Editing actions"
      // `w-full min-w-0` because this is no longer always a block child of the pane. Portalled
      // into the host's toolbar slot it is a FLEX ITEM, and a flex item sizes to its content: the
      // recessed strip stopped short of the window, its `border-y` ended mid-air, and the
      // absolutely-centred `title` — centred on the BAR — sat left of the page it names. Full
      // width is what it always had inline, so this asks for it rather than inheriting it.
      className="relative flex min-h-[2.75rem] w-full min-w-0 items-center gap-1 border-y border-apt-border bg-apt-bg px-6 py-2"
    >
      {showCreate && (
        <>
          <Button variant="ghost" size="sm" onClick={onCreate}>
            <Plus data-icon="inline-start" />
            {createLabel}
          </Button>
          <div className="mx-1 h-5 w-px bg-apt-border" aria-hidden />
        </>
      )}
      {showDelete && (
        <Button
          variant="destructive-ghost"
          size="sm"
          onClick={onDelete}
          disabled={!canDelete}
        >
          <Trash2 data-icon="inline-start" />
          Delete
        </Button>
      )}
      {/* Centered title naming the pane's contents — absolutely centred so it stays put
          regardless of the left/right buttons; pointer-events-none so it never blocks them. */}
      {title && (
        <h2 className="pointer-events-none absolute left-1/2 max-w-[60%] -translate-x-1/2 truncate font-mono text-sm font-medium tracking-wide text-apt-gold">
          {title}
        </h2>
      )}
      <div className="flex-1" />
      <SaveCancelButtons
        canCancel={canCancel}
        canSave={canSave}
        saving={saving}
        onCancel={onCancel}
        onSave={onSave}
      />
      {trailing && <div className="ml-1 flex items-center">{trailing}</div>}
      {help && (
        <HelpPopover triggerClassName="ml-1">
          {help}
        </HelpPopover>
      )}
    </div>
  );
  // Why Save is grey, from the FIRST frame — not gated on `dirty`. The detail below shows only
  // `form.error`, which `save()` alone sets and `canSave` keeps unreachable by click, so without this
  // every master/detail create opens on a dead Save with no explanation anywhere on screen. An EDIT
  // opens on a loaded, valid row where `blockedReason` is null, so it stays quiet on its own.
  //
  // Its OWN line under the bar, not a span inside it: the bar's title is absolutely centred, so an
  // in-flow span left of Save painted straight over any title long enough to reach it — the team
  // pane's "Use reverse-domain form…" sat on top of "Settings (… Participants Team)" and neither
  // could be read (Mike, 2026-09-24). Right-aligned so it reads as Save's caption; wraps rather
  // than truncates, because a clipped reason is the one piece of text here the user needs whole.
  const strip = (
    <div className="flex w-full min-w-0 flex-col">
      {bar}
      {blockedReason && (
        <p
          role="status"
          className="border-b border-apt-border bg-apt-bg px-6 py-1 text-right text-xs text-apt-text-muted"
        >
          {blockedReason}
        </p>
      )}
    </div>
  );
  // The bar hoists to the host's full-width strip above the rails whenever there is a host to
  // hoist into — the hub's workspace chrome and, since the toolbar slot became real there, the
  // standalone rail host too. With no host at all (a legacy route, a test that stubs the registry)
  // `ToolbarPortal` falls back to rendering inline, which is also what `hoist={false}` asks for
  // deliberately — see the prop.
  return (
    <>
      {hoist ? <ToolbarPortal>{strip}</ToolbarPortal> : strip}
      {/* Shared confirm modal for delete — replaces the old native confirm(). */}
      <AlertModal
        open={deletePrompt != null}
        tone="error"
        title="Confirm deletion"
        description={deletePrompt ?? undefined}
        confirmLabel="Delete"
        confirmVariant="destructive"
        cancelLabel="Cancel"
        busy={deleting}
        onConfirm={() => onConfirmDelete?.()}
        onCancel={() => onCancelDelete?.()}
      />
    </>
  );
}

/**
 * Two-pane master/detail shell. With `actions`, it renders the new design: a top
 * button bar, a dark-gray panel, and a full-height divider between the topic list
 * and the details. Without `actions` it renders the legacy layout (rail with its
 * own New button; the detail supplies its own footer) — kept for features not yet
 * migrated to the button bar.
 */
export function MasterDetailLayout({
  items,
  selectedId,
  onSelect,
  onNew,
  newLabel = "New",
  emptyLabel = "Nothing here yet.",
  actions,
  title,
  trailing,
  help,
  nested = false,
  children,
}: {
  items: MasterDetailItem[];
  selectedId: string | null;
  onSelect: (id: string) => void;
  onNew?: () => void;
  newLabel?: string;
  emptyLabel?: string;
  actions?: MasterDetailActions;
  /** Feature title shown (accent-colored) in a row above the button bar. */
  title?: ReactNode;
  /** Optional trailing affordance on the button bar (e.g. an <ApiButton>). */
  trailing?: ReactNode;
  /** Optional "?" help; shown on the far right of the title row. */
  help?: ReactNode;
  /** This layout sits INSIDE another pane's detail, so its bar stays with its own list rather
   *  than hoisting into the host's one toolbar slot — see {@link ButtonBar}'s `hoist`. */
  nested?: boolean;
  children: ReactNode;
}) {
  if (actions) {
    // Fills its container's height; the topic|details divider (the aside's
    // right border) therefore runs full height. The gray panel background lives
    // on the whole content column (.settings-content), not here.
    return (
      // Toolbar sits flush above the topic|details; it's pushed down (gap above,
      // in FeatureTabs) so the bar's BOTTOM edge lands on the nav divider, with
      // the topic|details beginning right below it.
      <div className="flex min-h-0 min-w-0 flex-1 flex-col">
        <ButtonBar
          actions={actions}
          title={title}
          trailing={trailing}
          help={help}
          hoist={!nested}
        />
        <div className="grid min-h-0 min-w-0 flex-1 grid-cols-1 grid-rows-[minmax(0,1fr)] md:grid-cols-[220px_minmax(0,1fr)]">
          <aside className="overflow-y-auto border-b border-apt-border px-6 py-4 md:border-r md:border-b-0">
            <ItemList
              items={items}
              selectedId={selectedId}
              onSelect={onSelect}
              emptyLabel={emptyLabel}
            />
          </aside>
          <section className="flex min-w-0 flex-col gap-6 overflow-y-auto px-6 py-4">
            {children}
          </section>
        </div>
      </div>
    );
  }

  return (
    <div className="grid min-h-[440px] grid-cols-1 gap-6 md:grid-cols-[220px_1fr]">
      <aside className="flex flex-col gap-3 md:border-r md:border-apt-border md:pr-6">
        {onNew && (
          <Button variant="outline" size="sm" className="justify-start" onClick={onNew}>
            <Plus data-icon="inline-start" />
            {newLabel}
          </Button>
        )}
        <ItemList
          items={items}
          selectedId={selectedId}
          onSelect={onSelect}
          emptyLabel={emptyLabel}
        />
      </aside>
      <section className="flex min-w-0 flex-col gap-6">{children}</section>
    </div>
  );
}

/** A titled block inside the detail pane, with an optional right-aligned action. */
export function DetailSection({
  title,
  action,
  children,
}: {
  title: string;
  action?: ReactNode;
  children: ReactNode;
}) {
  return (
    <section className="flex flex-col gap-4">
      <div className="flex min-h-8 items-center justify-between gap-3">
        <h3 className="text-sm font-semibold tracking-wide text-apt-text uppercase">{title}</h3>
        {action}
      </div>
      {children}
    </section>
  );
}

/** Footer with a dirty indicator and Cancel/Save actions. Legacy (pre button bar). */
export function DetailFooter({
  dirty,
  saving = false,
  onCancel,
  onSave,
  saveLabel = "Save",
  leading,
}: {
  dirty: boolean;
  saving?: boolean;
  onCancel: () => void;
  onSave: () => void;
  saveLabel?: string;
  leading?: ReactNode;
}) {
  return (
    <div className="mt-auto flex flex-col gap-4">
      <Separator />
      <div className="flex flex-wrap items-center justify-between gap-3">
        <span className="text-sm text-apt-text-muted">
          {dirty ? "You have unsaved changes." : "All changes saved."}
        </span>
        <div className="flex items-center gap-2">
          {leading}
          <Button variant="outline" onClick={onCancel} disabled={saving || !dirty}>
            Cancel
          </Button>
          <Button onClick={onSave} disabled={saving || !dirty}>
            {saving ? "Saving…" : saveLabel}
          </Button>
        </div>
      </div>
    </div>
  );
}
