"use client";
import { useState, type ReactElement, type ReactNode } from "react";
import { ButtonBar } from "@agentic-toolkit/ui/blocks";
import { AlertModal } from "@agentic-toolkit/ui/components/alert-modal";

/** The centered no-selection state every Settings section (and the panel host)
 *  shows in its leaf — one home for the styling. */
export function SectionPlaceholder({ children }: { children: ReactNode }): ReactElement {
  return (
    <div className="flex flex-1 items-center justify-center p-8 text-center font-mono text-sm text-apt-text-dim">
      {children}
    </div>
  );
}

/** How the shared `["configure-data"]` read is doing, as the roster levels need to
 *  render it. Threaded from ConfigPanel — the ONE component that holds the query — down
 *  to each roster so all of them say the same thing about the same load. */
export interface RosterLoadState {
  /** The query's error sentence, or null when it loaded (or is still loading). */
  error: string | null;
  isLoading: boolean;
}

/**
 * The rail's empty-list line, told apart by WHY the list is empty.
 *
 * A roster level is the hierarchy's frontier, and an unselected frontier renders the
 * package's select-nudge INSTEAD of the detail pane (`overview`, on by default) — so
 * ConfigPanel's `SectionErrorText` is unreachable at `/settings/<section>` until a row is
 * picked, which an empty list makes impossible. That left ONE user-visible string for
 * three different states, and it read "No sites yet." while the fetch was failing: a
 * loading failure was indistinguishable from a genuinely empty roster, and from a
 * configured fleet the browser simply never received.
 */
export function rosterEmptyLabel(noun: string, load: RosterLoadState): string {
  if (load.error) return `Couldn't load ${noun}.`;
  if (load.isLoading) return `Loading ${noun}…`;
  return `No ${noun} yet.`;
}

/** The nudge's blurb — the one slot the package still renders with an EMPTY list, and
 *  therefore the only place a failed roster load can say what went wrong. */
export function rosterOverviewHelp(load: RosterLoadState, blurb: ReactNode): ReactNode {
  return load.error ? <span className="text-apt-red">{load.error}</span> : blurb;
}

/** The inline mutation/query error line rendered under a section's button bar. */
export function SectionErrorText({ children }: { children: ReactNode }): ReactElement {
  return <div className="px-3.5 py-2 font-mono text-xs text-apt-red">{children}</div>;
}

/**
 * The shared shell of a Settings entity editor's leaf: the Cancel/Save/Delete
 * ButtonBar (creation lives on the LEVEL's "+ New", so the bar never shows one),
 * the error line, then the section's form. The consumer owns save/delete/dirty;
 * the shell owns the chrome — including the destructive-delete confirmation
 * (the shared AlertModal, not a browser confirm) — so the four sections can't
 * drift on any of it. `onDelete` runs only after the user confirms.
 */
export function EntityEditorShell({
  onCancel,
  onSave,
  canSave,
  saving,
  onDelete,
  canDelete,
  deleteConfirm,
  error,
  children,
}: {
  onCancel: () => void;
  onSave: () => void;
  canSave: boolean;
  saving: boolean;
  /** The CONFIRMED delete action — invoked after the modal's Delete. */
  onDelete: () => void;
  canDelete: boolean;
  /** What the confirm dialog asks. Null while nothing deletable is selected
   *  (Delete is disabled then, so the dialog can never open). */
  deleteConfirm: { title: string; description?: ReactNode } | null;
  error: string | null;
  children: ReactNode;
}): ReactElement {
  // Snapshot the delete TARGET (title + description + the confirmed action) when the dialog
  // OPENS, so a background selection change while it is open can't retarget the confirm to a
  // different entity than the one it named — `onDelete` closes over the row selected at open
  // time, so capturing it here pins the confirm to that row.
  const [pending, setPending] = useState<{ title: string; description?: ReactNode; run: () => void } | null>(null);
  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <ButtonBar
        showCreate={false}
        actions={{
          onCancel,
          canCancel: true,
          onSave,
          canSave,
          saving,
          onDelete: () => {
            if (deleteConfirm) setPending({ ...deleteConfirm, run: onDelete });
          },
          canDelete,
        }}
      />
      {error && <SectionErrorText>{error}</SectionErrorText>}
      {children}
      {pending && (
        <AlertModal
          open
          title={pending.title}
          description={pending.description}
          tone="error"
          destructive
          confirmLabel="Delete"
          cancelLabel="Cancel"
          onConfirm={() => {
            const run = pending.run;
            setPending(null);
            run();
          }}
          onCancel={() => setPending(null)}
        />
      )}
    </div>
  );
}
