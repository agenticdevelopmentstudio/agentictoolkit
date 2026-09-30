"use client";

import { useCallback, useMemo, useState, type ReactElement, type ReactNode } from "react";
import { deepestSelectedLevel, type TopicLevel } from "@agenticdevelopertoolkit/ui/blocks";
import { AlertModal } from "@agenticdevelopertoolkit/ui/components/alert-modal";

/**
 * The HOST side of the stack. Everything a rail host owes {@link RailHostRegistry} beyond plain
 * registration lives here, once, because there are two hosts — {@link StandaloneRailHost} and the
 * hub's WorkspaceChromeProvider — and every line they were each keeping a copy of is a line that
 * can drift between a feature site's /home and the same feature inside the hub shell. The user-
 * facing alert copy is the sharpest case: two literals, one product, no way to notice they had
 * diverged short of opening both.
 *
 * Publishers use `rail-host.tsx`'s hooks (`useStackPop`, `useReportMissing`, `useReportBusy`);
 * hosts use these.
 */

/**
 * Pop the stack's LEAF: clear the deepest level that currently has a selection, backing the user
 * out to that list with nothing chosen. Ancestors are kept, and it is a no-op when nothing is
 * selected anywhere.
 *
 * It reads `deepestSelectedLevel`, the same frontier math the view's Back reads, so a pop and a
 * Back can never disagree about which list is the leaf.
 *
 * Deliberately UNGUARDED — it does not consult the host's exit guard. Its callers are the missing-
 * item acknowledgement below (already gated on nothing being dirty) and a pane popping itself,
 * both of which have decided to leave. Routing it through the guard would put a Discard/Stay
 * prompt in front of a pane whose target no longer exists.
 *
 * Returns whether it actually popped, so a caller that has to keep the user moving can tell the
 * no-op case apart and handle it itself. Assignable to the registry's `() => void` member as-is;
 * a publisher calling {@link useStackPop} sees nothing of this.
 */
export function useHostPopStack(levels: TopicLevel[]): () => boolean {
  return useCallback(() => {
    const at = deepestSelectedLevel(levels);
    if (at < 0) return false;
    levels[at]?.onClear();
    return true;
  }, [levels]);
}

export interface HostBusyReports {
  /** The {@link RailHostRegistry} member. Give it straight to the registry. */
  reportBusy: (id: string, levelId: string, busy: boolean) => void;
  /** The stack to RENDER: the levels handed in, with `busy` raised on each one some pane is
   *  currently reading under. Render this instead of the raw merge — a host that kept rendering
   *  the merge would collect the reports and show nothing. */
  levels: TopicLevel[];
}

/**
 * The host's answer to a pane that reads but publishes no level of its own: raise `busy` on the
 * list whose detail area that pane occupies, so the spinner appears in front of THAT list's title.
 *
 * Folded here rather than at the publisher, because the publisher is the wrong component to know:
 * the level belongs to an ancestor, and the pane doing the reading is the only one that knows a
 * read is in flight. The report crosses that gap; this closes it.
 *
 * A level that already declares `busy` itself is left exactly as it is — one spinner per list, and
 * a publisher that holds its own read stays the authority on it.
 */
export function useHostBusyReports(levels: TopicLevel[]): HostBusyReports {
  // Reporter id → the level it is reading under. A Map and not a Set of level ids: two panes can
  // be reading at once, and the first to finish must not clear the second's spinner.
  const [reading, setReading] = useState<ReadonlyMap<string, string>>(new Map());

  const reportBusy = useCallback((id: string, levelId: string, busy: boolean) => {
    setReading((prev) => {
      if (busy ? prev.get(id) === levelId : !prev.has(id)) return prev;
      const next = new Map(prev);
      if (busy) next.set(id, levelId);
      else next.delete(id);
      return next;
    });
  }, []);

  const withBusy = useMemo(() => {
    // The common case by far — nobody is reading — returns the array UNCHANGED, identity included,
    // so a host that folds this in cannot make its stack look new on every render.
    if (reading.size === 0) return levels;
    const busyLevels = new Set(reading.values());
    return levels.map((l) => (l.busy || !busyLevels.has(l.id) ? l : { ...l, busy: true }));
  }, [levels, reading]);

  return { reportBusy, levels: withBusy };
}

export interface HostMissingAlert {
  /** The {@link RailHostRegistry} member. Give it straight to the registry. */
  reportMissing: (id: string, missing: boolean) => void;
  /** Mount this once, anywhere inside the host's provider. It renders nothing until a pane
   *  reports, and it carries its own acknowledgement — there is no second thing to wire, and so
   *  no way for a host to mount the alert and forget the pop. */
  missingAlert: ReactElement;
}

/**
 * The host's answer to a pane discovering its item is gone from the server: tell the user in the
 * platform's own alert, then back them out to the parent list.
 *
 * One mount per host rather than per feature, because a per-feature alert is a per-feature
 * omission — invisible until the rare case fires, at which point the user is stuck in a pane whose
 * subject no longer exists.
 *
 * @param popStack What to run on acknowledgement — {@link useHostPopStack}'s result. Typed by its
 *   `boolean`, not as `() => void`: a void-returning parameter accepts the same function at the
 *   call site and then makes its answer unreadable in here, and the answer is what tells the no-op
 *   pop apart from the real one.
 * @param suppressed Hold the alert back (pass `guards.size > 0`). Acknowledging pops the stack,
 *   and popping out from under an unsaved editor would discard the user's work in order to tell
 *   them the work's target is gone. The report is NOT withdrawn by suppression, so the alert
 *   appears the moment that editor is saved or discarded.
 */
export function useHostMissingAlert(
  popStack: () => boolean,
  suppressed: boolean,
): HostMissingAlert {
  // Which items panes have reported gone. A Set, not a boolean: two panes can be on screen at
  // once, and the second one withdrawing must not clear the first one's report.
  const [missing, setMissing] = useState<ReadonlySet<string>>(new Set());

  const reportMissing = useCallback((id: string, isMissing: boolean) => {
    setMissing((prev) => {
      if (prev.has(id) === isMissing) return prev;
      const next = new Set(prev);
      if (isMissing) next.add(id);
      else next.delete(id);
      return next;
    });
  }, []);

  const acknowledge = useCallback(() => {
    // Clear the Set ONLY when the pop had nothing to clear. The normal path pops the leaf, which
    // unmounts the pane that reported and lets its own `useReportMissing` cleanup withdraw exactly
    // its own id. Clearing here as well would also drop a SECOND pane's still-true report — and
    // that pane never re-reports, because its `isMissing` has not changed and the effect that
    // publishes it does not re-run — so the alert for its item would be lost for good.
    //
    // The no-op pop is the case that needs the clear: a single-record topic (published with
    // `useStackLevel(null)`, or a root pane with nothing selected above it) has no selection to
    // back out of and therefore nothing that will unmount. Without this, `missing` would stay
    // non-empty and the alert would re-open on the very next render, with no way past it.
    if (!popStack()) setMissing(new Set());
  }, [popStack]);

  const missingAlert = (
    <AlertModal
      open={missing.size > 0 && !suppressed}
      title="That item is no longer there"
      description="It was moved or deleted on the server since you last loaded it. Returning you to the list."
      onConfirm={acknowledge}
      // Acknowledging NAVIGATES (it pops the stack), so the button has to be the only way through:
      // in alert mode every dismissal gesture routes to `onConfirm`, and pressing Escape to make a
      // dialog go away would move the user out of the pane instead. See {@link AlertModal.dismissible}.
      dismissible={false}
    />
  );

  return { reportMissing, missingAlert };
}

