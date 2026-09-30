"use client";

import type { ReactNode } from "react";

import { SaveCancelButtons } from "./master-detail/SaveCancelButtons";

/**
 * @deprecated Build the pane on {@link DetailsPane} instead: its one header bar carries Save /
 * Cancel together with the title, the API button and the help, and its sections register with
 * `useDetailsSection` (or a `useSettingsDraft` given a `section`). Kept exported only for the
 * panes not yet moved onto it.
 *
 * The recessed action bar for single-record settings panes (Profile, Account, a realm's
 * gamification config) — same look as the master/detail toolbar (it shares the
 * SaveCancelButtons pair), just Cancel + Save right-aligned. `status` shows an inline
 * saved/error message on the left. Cancel is enabled whenever there are edits to discard
 * (`dirty`).
 *
 * Here rather than in a host because a single-record pane is exactly what a feature package
 * ships: it sits next to SaveCancelButtons, which it is a layout around, and the second host
 * to need one (the gamification site) would otherwise have copied thirty lines whose only
 * interesting content is which side the buttons go on.
 */
export function EditActionBar({
  dirty,
  canSave,
  saving = false,
  onCancel,
  onSave,
  status,
}: {
  dirty: boolean;
  canSave: boolean;
  saving?: boolean;
  onCancel: () => void;
  onSave: () => void;
  status?: ReactNode;
}) {
  return (
    <div
      role="toolbar"
      aria-label="Editing actions"
      className="flex items-center gap-1 border-y border-apt-border bg-apt-bg px-6 py-2"
    >
      {/* The status cell is a LIVE REGION, and it is one here rather than at each call site.
          Every caller passes the same ternary — a red save error, else a muted "Saved." — and
          none of them was announced: the error span mounts after the failure, so marking the
          span itself `role="alert"` is the arrangement that works least often (a live region
          has to be in the DOM before its content changes). This cell always renders, so the
          swap inside it is what gets read. `status` (polite) rather than `alert` because the
          same node carries the success message, and an assertive "Saved." interrupts. */}
      <div role="status" className="min-w-0 flex-1 truncate text-sm">
        {status}
      </div>
      <SaveCancelButtons
        canCancel={dirty}
        canSave={canSave}
        saving={saving}
        onCancel={onCancel}
        onSave={onSave}
      />
    </div>
  );
}
