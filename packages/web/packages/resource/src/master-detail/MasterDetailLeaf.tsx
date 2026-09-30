"use client";

import type { ReactNode } from "react";
import { TopicSelectHint } from "@agenticdevelopertoolkit/ui/blocks";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { ButtonBar, type MasterDetailActions } from "./MasterDetailLayout";
import type { RecordAffordanceProps } from "../record-affordance";

/**
 * The editor half of a DISMANTLED master/detail pane: a {@link ButtonBar} (Save / Cancel / Delete —
 * no Create, the published list level owns "New …") over the active row's editor, or — with no row
 * open — the placeholder ALONE, bar included, since every control the bar could offer acts on a
 * draft that does not exist. The list itself is published as a rail level via useMasterDetailLevel;
 * this is the leaf. Used by the status-site Groups / Sites panes so the scaffold lives in one place;
 * the sibling useMasterDetailLevel panes (Access / Users / Applications / Schemas) still inline the
 * same scaffold and can adopt this next.
 */
export function MasterDetailLeaf<TInput>({
  form,
  help,
  trailing,
  api,
  error,
  emptyTitle,
  renderDetail,
  footer,
}: {
  /** The master/detail form (only its bar + editing/draft state are needed here). */
  form: { actions: MasterDetailActions; editing: boolean; draft: TInput | null };
  /** Optional help affordance on the button bar. */
  help?: ReactNode;
  /** Optional non-API affordance on the button bar, left of the API button. */
  trailing?: ReactNode;
  /** The open row's endpoint, for the bar's API button (see {@link ButtonBar}'s `api`). */
  api?: RecordAffordanceProps | null;
  /** Optional load error, shown above the bar. */
  error?: string | null;
  /** Placeholder shown when no row is open. */
  emptyTitle: string;
  /** The row editor, rendered only while a row is open (draft guaranteed non-null). */
  renderDetail: (draft: TInput) => ReactNode;
  /** A strip pinned to the BOTTOM of the pane, below the content region and outside it, so it
   *  stays in view while the editor scrolls. Rendered only while a row is open — it is the open
   *  row's affordance (research's publish card), not the pane's. */
  footer?: ReactNode;
}) {
  const open = form.editing && form.draft;
  return (
    // `overflow-y-auto` is the LAST RESORT, and it is reachable only because the scroller below
    // now has a floor. The two go together: a floor with nowhere to overflow to is the collapse
    // this file already fixed once, and an overflow with no floor never triggers because the
    // scroller shrinks to nothing first. See the floor's note for the failure they close.
    <div className="flex min-h-0 min-w-0 flex-1 flex-col overflow-y-auto">
      <ErrorText error={error} className="px-6 pt-4" />
      {/* The bar belongs to the OPEN ROW, not to the pane. With nothing selected every control it
          can show is dead — Save/Cancel/Delete all act on a draft that does not exist, and
          `trailing` is a per-record affordance (an <ApiButton> for the row being edited). A row of
          permanently disabled controls above "Select a … to edit" is worse than no row: it
          advertises actions and then refuses them, with nothing on screen explaining why. So the
          bar renders only while a row is open, and the placeholder below stands alone. */}
      {open && (
        <ButtonBar actions={form.actions} showCreate={false} trailing={trailing} api={api} help={help} />
      )}
      {/* The pane's SCROLLER, and the only one — the `footer` sits outside it, which is what
          keeps it pinned while the editor scrolls.

          A detail that sizes itself by its content is simply scrolled here. A detail that FILLS
          (research's editor: `flex-1` all the way down) grows into this box instead, and needs
          nothing from it — a column flex container stretches a `flex-1` child on its own. What
          it does need is for this box to stay a scroller: an editor is only ever as short as its
          own minimum, and a pane shorter than that has to overflow SOMEWHERE. This used to be
          `overflow-hidden` for filling details, on the reasoning that scrolling the pane would
          carry the toolbar off screen while the author types — true while the editor fits, and
          catastrophic when it does not: with nowhere to overflow to, every box in the editor's
          chain collapsed and its fields painted over each other (measured at 768x723 and
          500x635). On a window tall enough for the editor there is no overflow and nothing
          scrolls, so nothing about the filling case changes. */}
      {/* THE FLOOR, and why the pane may scroll past it.

          `footer` is `shrink-0` and sits outside this box, so it claims its full height before
          this box gets anything — and this box, with `min-h-0` and `flex-1`, was willing to give
          up everything. That put the whole deficit of a short pane on the EDITOR and none of it
          on the publish card: measured at a 463px viewport, the card held its 145px while this
          box fell to 24px — a 24px window onto 421px of content, which is not a small editor, it
          is no editor at all. The inversion is the bug: the row's secondary affordance was rigid
          and the primary work surface was not.

          `min-h-56` inverts it back. The editor keeps a usable window, the deficit goes to the
          box that can afford it, and once floor + bar + footer exceed the pane, the LEAF scrolls
          (see its note) and the footer simply stops being pinned. That degradation is the point:
          pinned whenever the pane can afford it — which is every ordinary window — and reachable
          by scrolling when it cannot, instead of pinned at the cost of the editor. */}
      <div
        data-slot="detail-content"
        className="flex min-h-56 min-w-0 flex-1 flex-col overflow-y-auto px-6 py-4"
      >
        {open ? (
          renderDetail(form.draft as TInput)
        ) : (
          // The shared select-hint card, so this leaf's placeholder matches the stack
          // frontier's nudge and every other "pick something" pane.
          <TopicSelectHint title={emptyTitle} />
        )}
      </div>
      {open && footer && <div className="shrink-0 border-t border-apt-border px-6 py-4">{footer}</div>}
    </div>
  );
}
