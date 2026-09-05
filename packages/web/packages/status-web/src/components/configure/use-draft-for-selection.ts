"use client";
import { useCallback, useState, type Dispatch, type SetStateAction } from "react";

/**
 * Render-phase draft hydration keyed on the URL-selected id (React's derived-
 * state pattern), shared by every Settings entity editor. When the selection
 * changes AND its row exists, the draft loads from the row — so a background
 * refetch never clobbers in-progress edits, and a deep-link hard reload
 * hydrates once the query lands (the load WAITS for the row).
 *
 * Deliberately does NOT react to the selection going null: the board clears
 * the entity segment whenever the user leaves Settings, and resetting then
 * would wipe the unsaved draft that KeptPane exists to preserve. An explicit
 * discard (Cancel / starting a create) calls `discardDraft()` so the next
 * selection of the same row rehydrates fresh instead of resurfacing abandoned
 * edits.
 */
export function useDraftForSelection<Row, D>({
  selectedId,
  current,
  creating = false,
  initial,
  load,
}: {
  /** URL-selected entity id, owned by the board level. */
  selectedId: string | null;
  /** The selected row once its query has it (null while loading / none). */
  current: Row | null;
  /** While true (a create is underway) hydration is suspended. */
  creating?: boolean;
  /** The blank draft (state initializer — evaluated once). */
  initial: () => D;
  /** Build the draft from a row. */
  load: (row: Row) => D;
}): {
  draft: D;
  setDraft: Dispatch<SetStateAction<D>>;
  /** Forget which row the draft was loaded from — the next selection (even of
   *  the same id) rehydrates from its row. Call on explicit discards. */
  discardDraft: () => void;
} {
  const [draft, setDraft] = useState<D>(initial);
  const [loadedFor, setLoadedFor] = useState<string | null>(null);
  if (!creating && current && selectedId !== loadedFor) {
    setLoadedFor(selectedId);
    setDraft(load(current));
  }
  const discardDraft = useCallback((): void => setLoadedFor(null), []);
  return { draft, setDraft, discardDraft };
}
