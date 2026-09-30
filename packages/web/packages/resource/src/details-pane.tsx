"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useId,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";

import { cn } from "@agenticdevelopertoolkit/ui/lib/utils";
import { ButtonBar, type MasterDetailActions } from "./master-detail/MasterDetailLayout";
import type { RecordAffordanceProps } from "./record-affordance";
import { useRailExitGuard } from "./rail-host";
import { useReportSettingsDirty } from "./settings-dirty";

/**
 * One editable part of a {@link DetailsPane} — a card, a form, a list's pending edits. A section
 * reports its own edit state and hands over how to save and how to discard; the pane's ONE bar
 * decides what Save and Cancel do with all of them.
 */
export interface DetailsSection {
  /** The section holds edits the server does not have. */
  dirty: boolean;
  /** Those edits may be saved as they stand (validation passes). Read only while `dirty`. */
  canSave: boolean;
  /** Why this section's edits cannot be saved, shown under the bar while it is dirty. */
  blockedReason?: string | null;
  /** Persist this section's edits. Throw (an Error, ideally) to stop the save and report it. */
  save: () => Promise<void>;
  /** Throw this section's edits away. */
  reset: () => void;
}

/** What a section publishes to render state — the functions stay in a ref. */
interface SectionState {
  dirty: boolean;
  canSave: boolean;
  blockedReason: string | null;
}

interface DetailsScope {
  publish: (id: string, state: SectionState | null) => void;
  fns: Map<string, { current: DetailsSection }>;
}

const DetailsScopeContext = createContext<DetailsScope | null>(null);

/**
 * Register one section with the enclosing {@link DetailsPane}'s edit scope, for as long as it is
 * mounted. Outside a DetailsPane (or with `null`) it does nothing, so a section component renders
 * unchanged on a surface that has no pane around it.
 *
 * Sections save in the order they first mounted — top to bottom, as the user reads them.
 */
export function useDetailsSection(section: DetailsSection | null): void {
  const scope = useContext(DetailsScopeContext);
  const id = useId();
  // The latest callbacks, read at click time — so a section may pass fresh closures every render
  // without re-publishing (and re-rendering the pane) for each one.
  const ref = useRef<DetailsSection | null>(section);
  ref.current = section;
  const present = section !== null;
  const dirty = section?.dirty ?? false;
  const canSave = section?.canSave ?? false;
  const blockedReason = section?.blockedReason ?? null;

  useEffect(() => {
    if (!scope || !present) return;
    scope.fns.set(id, ref as { current: DetailsSection });
    return () => {
      scope.fns.delete(id);
      scope.publish(id, null);
    };
  }, [scope, id, present]);

  useEffect(() => {
    if (!scope || !present) return;
    scope.publish(id, { dirty, canSave, blockedReason });
  }, [scope, id, present, dirty, canSave, blockedReason]);
}

/**
 * Whether this component renders inside a {@link DetailsPane}. For a pane that is sometimes a
 * section of a bigger pane and sometimes a topic of its own: inside one it registers with that
 * pane's bar; standing alone it draws the pane itself.
 */
export function useInDetailsPane(): boolean {
  return useContext(DetailsScopeContext) !== null;
}

type SaveStatus =
  | { kind: "idle" }
  | { kind: "saving" }
  | { kind: "saved" }
  | { kind: "error"; message: string };

/**
 * The shared starting point for every details pane: ONE header bar — the title, Save / Cancel,
 * the API button and the "?" help on the far right — over a body that scrolls in place. The pane
 * fills its container and never grows it: a long form scrolls inside the body instead of
 * resizing the pane under the user.
 *
 * **The edit scope.** Everything editable inside registers with {@link useDetailsSection} (or,
 * for a {@link useSettingsDraft} draft, by passing it a `section`). The bar's Save is live when
 * any section is dirty and every dirty section can save; it saves the dirty sections one after
 * another, stopping at the first failure; Cancel discards every section. The saving / saved /
 * error line is a live region under the bar, so it is announced.
 *
 * **List panes.** A pane that edits rows of a list (New / Delete) passes the bar it already has —
 * `useMasterDetailForm`'s `actions` — and that bar is used as-is; sections are then not consulted.
 */
export function DetailsPane({
  title,
  help,
  api,
  actions,
  section,
  hoist = true,
  showApi = true,
  showCreate = actions !== undefined,
  showDelete = actions !== undefined,
  trailing,
  bodyClassName,
  children,
}: {
  /** Names the pane's contents — centred in the bar. */
  title?: ReactNode;
  /** The "?" help on the far right of the bar. */
  help?: ReactNode;
  /** The endpoint this pane is about, for the bar's API button; omit for a view without one (the
   *  button is then drawn disabled, saying so). */
  api?: RecordAffordanceProps | null;
  /** A list pane's own bar (`useMasterDetailForm().actions`), used as-is — New / Delete / Save /
   *  Cancel then act on its rows and registered sections are not consulted. */
  actions?: MasterDetailActions;
  /** The pane's own section, for a component that renders the pane itself — its
   *  {@link useDetailsSection} call would sit outside the pane's scope. Registered first, ahead of
   *  any section inside the body. */
  section?: DetailsSection | null;
  /** Send the bar to the host's toolbar slot (default). `false` for a pane nested in another. */
  hoist?: boolean;
  /** Draw the API button (default). `false` only where an enclosing header already draws the
   *  pane's API button — two in one view would be a duplicate. */
  showApi?: boolean;
  /** Draw the bar's New (default: when `actions` is given). `false` for a list pane whose creators
   *  live on the list's own toolbar. */
  showCreate?: boolean;
  /** Draw the bar's Delete (default: when `actions` is given). `false` for a pane that deletes from
   *  a danger zone in its body — a bar Delete would be a second button naming the same action. */
  showDelete?: boolean;
  /** A non-API control on the bar, left of the API button. */
  trailing?: ReactNode;
  /** Replaces the body's default padding / gap. The body always scrolls. */
  bodyClassName?: string;
  children: ReactNode;
}) {
  const [sections, setSections] = useState<ReadonlyMap<string, SectionState>>(() => new Map());
  const fns = useRef(new Map<string, { current: DetailsSection }>()).current;
  const [status, setStatus] = useState<SaveStatus>({ kind: "idle" });
  // Set synchronously on click: two clicks inside one commit both see `saving === false` in
  // render state, and the latch is what keeps the second from starting a second write.
  const savingRef = useRef(false);

  const publish = useCallback((id: string, state: SectionState | null) => {
    setSections((prev) => {
      const had = prev.get(id);
      if (state === null ? !had : had && sameState(had, state)) return prev;
      const next = new Map(prev);
      if (state === null) next.delete(id);
      else next.set(id, state);
      return next;
    });
  }, []);
  const scope = useMemo<DetailsScope>(() => ({ publish, fns }), [publish, fns]);

  const dirtyStates = [...sections.values()].filter((s) => s.dirty);
  const anyDirty = dirtyStates.length > 0;
  const saving = status.kind === "saving";
  const canSave = anyDirty && dirtyStates.every((s) => s.canSave) && !saving;
  const blockedReason = dirtyStates.find((s) => !s.canSave && s.blockedReason)?.blockedReason ?? null;

  // An edit after a save supersedes its "Saved." line — a clean pane turning dirty, not the frame
  // or two after a save in which the sections have not yet published that they are clean.
  const wasDirty = useRef(anyDirty);
  useEffect(() => {
    if (anyDirty && !wasDirty.current) setStatus((s) => (s.kind === "saved" ? { kind: "idle" } : s));
    wasDirty.current = anyDirty;
  }, [anyDirty]);

  const save = useCallback(async () => {
    // Dirty sections, in registration (mount) order — read from the published state via the map
    // the scope keeps, since `fns` preserves the order sections first mounted.
    const ids = [...fns.keys()].filter((id) => sections.get(id)?.dirty);
    if (ids.length === 0 || savingRef.current) return;
    savingRef.current = true;
    setStatus({ kind: "saving" });
    try {
      for (const id of ids) await fns.get(id)?.current.save();
      setStatus({ kind: "saved" });
    } catch (err) {
      setStatus({ kind: "error", message: err instanceof Error ? err.message : "Save failed." });
    } finally {
      savingRef.current = false;
    }
  }, [fns, sections]);

  const cancel = useCallback(() => {
    for (const ref of fns.values()) ref.current.reset();
    setStatus({ kind: "idle" });
  }, [fns]);

  const paneId = useId();
  useReportSettingsDirty(`details-pane:${paneId}`, !actions && anyDirty);
  useRailExitGuard(!actions && anyDirty ? { isDirty: () => true } : null);

  const barActions: MasterDetailActions = actions ?? {
    onCreate: () => {},
    onCancel: cancel,
    canCancel: anyDirty && !saving,
    onSave: () => void save(),
    canSave,
    blockedReason,
    saving,
    onDelete: () => {},
    canDelete: false,
  };

  const statusLine =
    status.kind === "saving" ? (
      "Saving…"
    ) : status.kind === "saved" ? (
      "Saved."
    ) : status.kind === "error" ? (
      <span className="text-apt-red">{status.message}</span>
    ) : undefined;

  return (
    <DetailsScopeContext.Provider value={scope}>
      <div data-slot="details-pane" className="flex min-h-0 min-w-0 flex-1 flex-col">
        {section !== undefined && <OwnSection section={section} />}
        <ButtonBar
          actions={barActions}
          showCreate={showCreate}
          showDelete={showDelete}
          title={title}
          trailing={trailing}
          api={api}
          showApi={showApi}
          status={actions ? undefined : (statusLine ?? null)}
          help={help}
          hoist={hoist}
        />
        <div
          data-slot="details-body"
          className={cn("flex min-h-0 min-w-0 flex-1 flex-col overflow-y-auto", bodyClassName ?? "gap-6 px-6 py-4")}
        >
          {children}
        </div>
      </div>
    </DetailsScopeContext.Provider>
  );
}

/** Registers a DetailsPane's `section` prop from inside the pane's scope. */
function OwnSection({ section }: { section: DetailsSection | null }) {
  useDetailsSection(section);
  return null;
}

function sameState(a: SectionState, b: SectionState): boolean {
  return a.dirty === b.dirty && a.canSave === b.canSave && a.blockedReason === b.blockedReason;
}
