"use client";

import { useCallback, useMemo, useRef, useState } from "react";
import { useDetailsSection } from "./details-pane";

/**
 * The draft half of a hand-rolled settings pane: a local copy of a loaded record that a
 * background refetch must not clobber, and that a partial save must diff against the right
 * thing.
 *
 * `useMasterDetailForm` does not fit these panes — it is for ONE list-shaped resource, and a
 * settings pane composes whatever it composes (a realm config; a realm config plus a game row;
 * a single `mode` field). What every one of them needs is identical, though, and getting it
 * right by hand twice produced two different sets of bugs, so it lives here once:
 *
 * **1. A refetch must not overwrite an edit — and must not be MISTAKEN for one.** The obvious
 * guard is "keep the draft while `draft !== loaded`", and it is wrong in a way that only shows
 * up once caching is in play. When the server's copy changes underneath an UNEDITED pane, that
 * comparison is true for a reason that has nothing to do with the user: the draft still holds
 * the previous server value. The pane then pins the stale value, raises a save bar nobody asked
 * for, and offers to write yesterday's config back. So the guard here is whether the USER has
 * touched the draft (`edited`), which is a fact only this hook's own setter can produce — not a
 * value comparison that cannot tell an edit from a stale copy.
 *
 * The re-seed is likewise driven by the LOADED record moving (`lastSeeded`) rather than by the
 * draft differing from it, and that distinction is what makes `commit` safe: a pane commits the
 * save's own response, and for however many renders it takes the cache to catch up, `loaded` is
 * still the pre-save record. Reseeding on "draft differs" would undo the save on the very next
 * render and flash the old values back.
 *
 * **2. A partial body must diff against what the user actually saw.** Panes that send only
 * changed fields need a base for that diff, and the loaded record is the wrong one once it has
 * moved: field-by-field against a moved base, an untouched field whose SERVER value changed
 * reads as an edit, and the save quietly writes the user's stale copy over somebody else's
 * newer one. `seed` is the snapshot the current draft was seeded from and it does not move while
 * the draft is dirty, so `draft.x !== seed.x` is true only where this user changed something.
 *
 * `dirty` still compares the draft to the LOADED record, because that is the question the save
 * bar asks: is there anything here the server does not already have?
 *
 * @param loaded The record as last read from the server, or null while it is still loading.
 * @param toDraft Projects a loaded record into the pane's draft shape. Must be pure.
 * @param isEqual Draft equality for `dirty`. Defaults to a JSON comparison, which is what these
 *   panes were each doing by hand; pass one when the draft holds values JSON cannot compare.
 */
export interface SettingsDraft<L, D> {
  /** The editable copy, or null until `loaded` first arrives. */
  draft: D | null;
  /** Merge into the draft and mark it edited. Every user-facing control writes through this. */
  patch: (next: Partial<D>) => void;
  /** Replace the draft wholesale and mark it edited — for controls that recompute it. */
  replace: (next: D) => void;
  /** What `draft` was seeded from: the base a partial save diffs against. Null until seeded. */
  seed: D | null;
  /** `loaded` projected through `toDraft`, or null while loading — what `dirty` compares to. */
  baseline: D | null;
  /** The draft differs from the server's copy: the save bar's question. */
  dirty: boolean;
  /** Re-seed from a record the pane just wrote (a save's own response), clearing `edited`. */
  commit: (record: L) => void;
  /** Throw the edit away and re-seed from `loaded`. */
  reset: () => void;
}

/**
 * How a draft saves, for the enclosing {@link DetailsPane}'s one bar. Given to
 * {@link useSettingsDraft}, the draft registers ITSELF as a section of that pane — `dirty` and
 * `reset` are the draft's own — so a pane built from drafts needs no wiring of its own.
 */
export interface SettingsDraftSection {
  /** Persist the draft; throw to stop the pane's save and report the failure. */
  save: () => Promise<void>;
  /** The draft may be saved as it stands. Defaults to true. */
  canSave?: boolean;
  /** Why it cannot, shown under the pane's bar while the draft is dirty. */
  blockedReason?: string | null;
}

export function useSettingsDraft<L, D>(
  loaded: L | null | undefined,
  toDraft: (loaded: L) => D,
  isEqual: (a: D, b: D) => boolean = (a, b) => JSON.stringify(a) === JSON.stringify(b),
  /** Register this draft with the enclosing DetailsPane (a no-op outside one). */
  section?: SettingsDraftSection,
): SettingsDraft<L, D> {
  const [draft, setDraft] = useState<D | null>(null);
  const [seed, setSeed] = useState<D | null>(null);
  // Neither is state: nothing renders from them, and both are read inside the seeding path
  // below, where a state value would be a render behind.
  const edited = useRef(false);
  // The projection of the record this draft was last seeded from, so the seeding test can ask
  // "did the SERVER's copy move" instead of "does the draft differ" — see (1) in the doc.
  const lastSeeded = useRef<D | null>(null);

  const baseline = useMemo(
    () => (loaded == null ? null : toDraft(loaded)),
    // `toDraft` is required to be pure, and panes declare it inline; depending on its identity
    // would re-project on every render for no gain.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [loaded],
  );

  // Seeding happens DURING render rather than in an effect, so the first paint after a load
  // already shows the record instead of a "Loading…" frame the data is available for. It is the
  // `setState`-while-rendering pattern React documents for exactly this ("adjusting state when a
  // prop changes"): the write is guarded by a comparison, so it converges in one extra pass.
  if (baseline !== null) {
    const moved = lastSeeded.current === null || !isEqual(baseline, lastSeeded.current);
    if (draft === null || (!edited.current && moved)) {
      lastSeeded.current = baseline;
      setDraft(baseline);
      setSeed(baseline);
    }
  }

  const dirty = draft !== null && baseline !== null && !isEqual(draft, baseline);

  const patch = useCallback((next: Partial<D>) => {
    edited.current = true;
    setDraft((prev) => (prev === null ? prev : { ...prev, ...next }));
  }, []);

  const replace = useCallback((next: D) => {
    edited.current = true;
    setDraft(next);
  }, []);

  const commit = useCallback(
    (record: L) => {
      edited.current = false;
      const next = toDraft(record);
      setDraft(next);
      setSeed(next);
    },
    // Same reasoning as `baseline`.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [],
  );

  const reset = useCallback(() => {
    edited.current = false;
    lastSeeded.current = baseline;
    setDraft(baseline);
    setSeed(baseline);
  }, [baseline]);

  useDetailsSection(
    section
      ? {
          dirty,
          canSave: section.canSave ?? true,
          blockedReason: section.blockedReason,
          save: section.save,
          reset,
        }
      : null,
  );

  return { draft, patch, replace, seed, baseline, dirty, commit, reset };
}
