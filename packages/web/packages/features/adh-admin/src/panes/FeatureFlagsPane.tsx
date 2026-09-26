"use client";

import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { Pencil, Plus, ToggleLeft, ToggleRight, Trash2 } from "lucide-react";
import {
  useAdminFlags,
  useCreateFlag,
  useUpdateFlag,
  useDeleteFlag,
  type FeatureFlag,
  type UpdateFlagBody,
} from "../api/admin";
import {
  duplicateFlagKeyMessage,
  flagFormBlockedReason,
  isFlagFormDirty,
  FLAG_KEY_REQUIRED_MESSAGE,
} from "@agentic-toolkit/adh/settings-dialogs";
import { useAction } from "@agenticdevelopertoolkit/ui/hooks/useAction";
import { Badge } from "@agenticdevelopertoolkit/ui/components/badge";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Checkbox } from "@agenticdevelopertoolkit/ui/components/checkbox";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@agenticdevelopertoolkit/ui/components/dialog";
import { DialogActions } from "@agenticdevelopertoolkit/ui/components/dialog-actions";
import { UnsavedChangesGuard } from "@agenticdevelopertoolkit/ui/components/unsaved-changes-guard";
import { Field } from "@agenticdevelopertoolkit/ui/blocks/field";
import { ProgressModal } from "@agenticdevelopertoolkit/ui/blocks";
import { ApiButton } from "@agentic-toolkit/api-explorer";
import {
  EditableList,
  TypeToConfirmDialog,
  useBatchRun,
  useEditableList,
  type EditableListColumn,
} from "../components/editable-list";

/**
 * Feature flags — the site-wide on/off toggles, and the five things an admin does to a set of them.
 *
 * Everything that acts lives in the BAR. This page used to edit in place: every row carried its
 * own enabled checkbox, two click-to-type cells and a commit/delete control, which is the model
 * the shared list replaces — a row's own checkbox beside the selection checkbox is two ticks that
 * mean different things in one column, and "turn these six off" was six separate commits instead
 * of one selection and one button. Nothing is per-row now: New and Edit open the same dialog, and
 * Enable, Disable and Delete each run over the selection.
 */

/** Module-level so the runs below aren't handed a new key on every render. */
const FLAGS_KEY = ["admin", "flags"];

/** The word an operator has to type to delete flags. Deliberately not a key and not the count. */
const DELETE_WORD = "delete";

/** The two words the State column sorts, searches and filters by. */
function stateLabel(flag: FeatureFlag): string {
  return flag.enabled ? "Enabled" : "Disabled";
}

export function FeatureFlagsPane() {
  const router = useRouter();
  const { data, isLoading, error } = useAdminFlags();
  const updateFlag = useUpdateFlag();
  const deleteFlag = useDeleteFlag();

  /** What the dialog is pointed at: a row to edit, `null` for a create, absent when closed. */
  const [editing, setEditing] = useState<{ flag: FeatureFlag | null } | null>(null);
  const [dialogDirty, setDialogDirty] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);

  const toggleRun = useBatchRun({ invalidateKey: FLAGS_KEY, successMessage: "saved" });
  const deleteRun = useBatchRun({ invalidateKey: FLAGS_KEY, successMessage: "deleted" });

  const columns = useMemo<EditableListColumn<FeatureFlag>[]>(
    () => [
      {
        key: "key",
        header: "Key",
        // No fixed width: the table measures this column and locks it to its widest cell, so the
        // longest key always shows in full. A hard-coded width can't do that — keys grow, and
        // `mono` is a THEME font, so the same 20 characters are a different number of pixels in
        // each theme.
        value: (flag) => flag.key,
        render: (flag) => <span className="font-mono text-sm text-apt-text">{flag.key}</span>,
      },
      {
        key: "description",
        header: "Description",
        // minmax(0,1fr): takes the remaining width but may shrink, so a long description
        // truncates rather than pushing the State column off the end.
        width: "minmax(0,1fr)",
        value: (flag) => flag.description ?? "",
        render: (flag) => (
          <span className="block truncate text-sm text-apt-text-muted" title={flag.description}>
            {flag.description || "—"}
          </span>
        ),
      },
      {
        key: "enabled",
        header: "State",
        width: "7rem",
        // Sorted and searched by the WORDS, so the free-text box finds "enabled" and the column
        // sorts into two blocks rather than by a boolean nobody can read.
        value: stateLabel,
        render: (flag) => (
          <Badge variant={flag.enabled ? "success" : "neutral"}>{stateLabel(flag)}</Badge>
        ),
      },
    ],
    [],
  );

  const facets = useMemo(
    () => [{ id: "state", label: "State", valuesOf: (flag: FeatureFlag) => [stateLabel(flag)] }],
    [],
  );

  const list = useEditableList<FeatureFlag>({
    rows: data,
    getRowId: (flag) => String(flag.id),
    columns,
    facets,
    initialSort: { key: "key", dir: "asc" },
  });

  const selected = list.selectedRows;
  const allKeys = useMemo(() => list.allRows.map((f) => f.key), [list.allRows]);

  /**
   * Set `enabled` across the selection, skipping the rows that already hold that value.
   *
   * Skipping is not an optimisation: a run reporting that it "saved" nine flags when it changed
   * two states a number the operator cannot act on, and each no-op PUT is a real write to a table
   * every app on the site reads.
   */
  const setEnabled = (enabled: boolean) => {
    const changing = selected.filter((flag) => flag.enabled !== enabled);
    void toggleRun.run(
      changing.map((flag) => ({ id: String(flag.id), label: flag.key })),
      (item) => updateFlag.mutateAsync({ id: Number(item.id), changes: { enabled } }),
    );
  };

  /** Would this button change anything? A button that can only write no-ops is a dead button. */
  const wouldChange = (enabled: boolean) => selected.some((flag) => flag.enabled !== enabled);

  return (
    <div>
      <div className="mb-6 flex items-center justify-between gap-2">
        <h1 className="text-2xl font-bold text-apt-text">Feature Flags</h1>
        <ApiButton
          endpoint={{ method: "GET", path: "/system/feature-flags" }}
          title="Feature flags API"
        />
      </div>

      <p className="mb-6 max-w-2xl text-sm text-apt-text-muted">
        Site-wide toggles — every app reads the same value. A product&apos;s own per-ecosystem
        flags live in that ecosystem&apos;s settings, not here.
      </p>

      <EditableList<FeatureFlag>
        list={list}
        ariaLabel="Feature flags"
        loading={isLoading}
        error={error}
        errorTitle="Couldn't load feature flags"
        columnWidthsKey="admin-feature-flags"
        describeRow={(flag) => flag.key}
        searchPlaceholder="Key or description"
        emptyLabel="No feature flags yet."
        emptyFilteredLabel="No flags match these filters."
        actions={
          <>
            <Button size="sm" variant="ghost" onClick={() => setEditing({ flag: null })}>
              <Plus data-icon="inline-start" />
              New Feature Flag
            </Button>
            {/* Edit takes exactly one row, and says so by being dead for any other count: the
                dialog shows one key and one description, and there is no honest way to point it at
                four. Every action that DOES generalise across a selection is a button of its
                own. */}
            <Button
              size="sm"
              variant="ghost"
              disabled={selected.length !== 1}
              onClick={() => setEditing({ flag: selected[0]! })}
            >
              <Pencil data-icon="inline-start" />
              Edit
            </Button>
            <Button
              size="sm"
              variant="ghost"
              disabled={!wouldChange(true)}
              onClick={() => setEnabled(true)}
            >
              <ToggleRight data-icon="inline-start" />
              Enable
            </Button>
            <Button
              size="sm"
              variant="ghost"
              disabled={!wouldChange(false)}
              onClick={() => setEnabled(false)}
            >
              <ToggleLeft data-icon="inline-start" />
              Disable
            </Button>
            <Button
              size="sm"
              variant="destructive-ghost"
              disabled={selected.length === 0}
              onClick={() => setConfirmDelete(true)}
            >
              <Trash2 data-icon="inline-start" />
              Delete
            </Button>
          </>
        }
      />

      {/* ── Delete ─────────────────────────────────────────────────────────
          Typed, not clicked. A flag is read by every app on the site, so deleting one changes code
          paths nobody on this page can see. The word is typed once for the whole selection, and
          the keys are named in the description because those are what have to be read. */}
      <TypeToConfirmDialog
        open={confirmDelete}
        title={selected.length === 1 ? "Delete this flag?" : `Delete ${selected.length} flags?`}
        description={
          <>
            Permanently deletes{" "}
            <span className="font-mono text-apt-text">{selected.map((f) => f.key).join(", ")}</span>
            . Anything still reading a deleted flag falls back to its own default.
          </>
        }
        confirmValue={DELETE_WORD}
        valueNoun="word"
        confirmLabel="Delete"
        onCancel={() => setConfirmDelete(false)}
        onConfirm={() => {
          setConfirmDelete(false);
          void deleteRun.run(
            selected.map((flag) => ({ id: String(flag.id), label: flag.key })),
            (item) => deleteFlag.mutateAsync(Number(item.id)),
          );
        }}
      />

      <ProgressModal
        open={deleteRun.state.running || deleteRun.state.finished}
        title="Deleting flags"
        description="Each flag is deleted on its own; a failure leaves the earlier deletions in place."
        total={deleteRun.state.total}
        done={deleteRun.state.done}
        currentLabel={deleteRun.state.currentLabel}
        error={deleteRun.state.error}
        results={deleteRun.state.results}
        finished={deleteRun.state.finished}
        onContinue={deleteRun.continueRun}
        onStop={deleteRun.stop}
        onClose={() => {
          deleteRun.reset();
          list.clearSelection();
        }}
      />

      <ProgressModal
        open={toggleRun.state.running || toggleRun.state.finished}
        title="Saving flags"
        description="A flag already in the requested state is left alone."
        total={toggleRun.state.total}
        done={toggleRun.state.done}
        currentLabel={toggleRun.state.currentLabel}
        error={toggleRun.state.error}
        results={toggleRun.state.results}
        finished={toggleRun.state.finished}
        onContinue={toggleRun.continueRun}
        onStop={toggleRun.stop}
        onClose={() => toggleRun.reset()}
      />

      {/* Leaving the page loses a half-typed flag — the only draft this page still holds now that
          the rows themselves are no longer editable. Same-origin hops navigate client-side. */}
      <UnsavedChangesGuard when={dialogDirty} onNavigate={(href) => router.push(href)} />

      <FlagDialog
        // Keyed by the row it is pointed at, so aiming the dialog at a different flag rebuilds its
        // state instead of carrying the previous row's typing across.
        key={editing?.flag?.id ?? "new"}
        open={editing !== null}
        flag={editing?.flag ?? null}
        existingKeys={allKeys}
        onClose={() => setEditing(null)}
        onDirtyChange={setDialogDirty}
      />
    </div>
  );
}

// Exported (not just used locally) so a test can render it in isolation and `vi.mock` the
// `useCreateFlag`/`useUpdateFlag` module boundary — see `FlagDialog.test.tsx`.
export function FlagDialog({
  open,
  flag,
  existingKeys,
  onClose,
  onDirtyChange,
}: {
  open: boolean;
  /** The row being edited, or `null` to create one. */
  flag: FeatureFlag | null;
  /** Every key in the list — the edited row's own is dropped below. */
  existingKeys: string[];
  onClose: () => void;
  /** Reports whether the form holds unsaved input, so the page's guard covers it. */
  onDirtyChange: (dirty: boolean) => void;
}) {
  const createFlag = useCreateFlag();
  const updateFlag = useUpdateFlag();
  const save = useAction();

  const initial = useMemo(
    () => ({
      key: flag?.key ?? "",
      description: flag?.description ?? "",
      enabled: flag?.enabled ?? false,
    }),
    [flag],
  );

  const [key, setKey] = useState(initial.key);
  const [description, setDescription] = useState(initial.description);
  const [enabled, setEnabled] = useState(initial.enabled);
  const formRef = useRef<HTMLFormElement>(null);
  // Focus when the input ATTACHES (dialog open) — the autoFocus prop is banned by
  // jsx-a11y/no-autofocus; a stable callback ref never re-steals focus on re-render.
  const focusOnAttach = useCallback((el: HTMLInputElement | null) => {
    el?.focus();
  }, []);

  // Every key EXCEPT this row's own: a flag is not a collision with itself, and counting it would
  // grey Save out on an untouched form and blame a name the operator never typed.
  const otherKeys = useMemo(
    () => existingKeys.filter((k) => k !== flag?.key),
    [existingKeys, flag],
  );

  const form = { key, description, enabled };
  const dirty = isFlagFormDirty(form, initial);
  // Reported whether or not the dialog is OPEN. Closing keeps the draft, so a shut dialog holding
  // unsaved input is exactly the case the navigation guard exists for — gating on `open` would let
  // the operator walk away from typed values the moment they pressed Cancel.
  useEffect(() => onDirtyChange(dirty), [dirty, onDirtyChange]);
  // Why Save can't fire (null = nothing blocking). `editingMode` in the shared gate means "the key
  // is FIXED, so there is nothing to check", which describes hub's edit dialog, where the key
  // input is disabled. THIS dialog keeps the key editable in both modes — renaming a system flag
  // is something the admin page has always been able to do — so the blank and collision checks
  // apply throughout, against the OTHER rows' keys.
  const blockedReason = flagFormBlockedReason(form, {
    editingMode: false,
    existingKeys: otherKeys,
  });
  const canSave = dirty && blockedReason === null;

  // Closing keeps the typed draft (this dialog stays mounted as long as the page does), so
  // reopening the same row restores it; only a successful save clears it. Blocked mid-save.
  function close() {
    if (save.busy) return;
    onClose();
  }

  function handleSubmit(e: FormEvent) {
    e.preventDefault();
    void save.run(async () => {
      // Both throws are captured by useAction. They mirror `blockedReason` exactly (same source),
      // so the sentence beside the disabled Save is the one a click would have produced.
      const trimmedKey = key.trim();
      if (!trimmedKey) throw new Error(FLAG_KEY_REQUIRED_MESSAGE);
      if (otherKeys.includes(trimmedKey)) throw new Error(duplicateFlagKeyMessage(trimmedKey));

      if (flag) {
        // Only what CHANGED. The PUT is a patch, so sending every field would write back a
        // description someone else edited while this dialog sat open.
        const changes: UpdateFlagBody = {};
        if (trimmedKey !== initial.key) changes.key = trimmedKey;
        if (description.trim() !== initial.description.trim()) {
          changes.description = description.trim();
        }
        if (enabled !== initial.enabled) changes.enabled = enabled;
        await updateFlag.mutateAsync({ id: flag.id, changes });
      } else {
        await createFlag.mutateAsync({
          key: trimmedKey,
          enabled,
          description: description.trim() || undefined,
        });
      }
      onClose();
    });
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !next && close()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{flag ? "Edit feature flag" : "New feature flag"}</DialogTitle>
          <DialogDescription>
            Flags are global — every site reads the same value.
          </DialogDescription>
        </DialogHeader>
        <form ref={formRef} onSubmit={handleSubmit} className="flex flex-col gap-4">
          <Field label="Feature flag" error={save.error}>
            <Input
              placeholder="e.g. dark_mode"
              value={key}
              onChange={(e) => setKey(e.target.value)}
              className="font-mono"
              ref={focusOnAttach}
            />
          </Field>
          <Field label="Description">
            <Input
              placeholder="What does this flag gate? (optional)"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
          </Field>
          <Label htmlFor="flag-dialog-enabled" className="font-normal">
            <Checkbox
              id="flag-dialog-enabled"
              checked={enabled}
              onCheckedChange={(checked) => setEnabled(checked === true)}
            />{" "}
            Enabled
          </Label>
          {/* Why Save is grey — shown from the FIRST frame, not gated on `dirty`. A create opens
              already blocked, on a requirement ("a key is required") that is precisely what the
              user came here to supply, so stating it up front is instruction rather than scolding;
              without it the dialog opens on a dead Save with nothing explaining it. Suppressed
              while `save.error` is showing so the two never argue. */}
          {!save.error && blockedReason && (
            <p className="text-sm text-apt-text-muted" role="status">
              {blockedReason}
            </p>
          )}
          {/* A submit button is what lets Enter submit a multi-input form; hidden because the
              visible confirm lives in DialogActions and calls form.requestSubmit(). Both paths run
              handleSubmit. It must carry the same disabled state as the visible confirm — being
              the form's implicit default button, Enter in any text field submits THIS button
              regardless of `hidden`/`display:none`; only `disabled` stops it. That includes
              `save.busy`: DialogActions drops the visible confirm while saving, leaving THIS the
              only reachable submit path, so without the busy term Enter mid-save fires a second
              write. */}
          <button
            type="submit"
            className="hidden"
            aria-hidden
            tabIndex={-1}
            disabled={!canSave || save.busy}
          />
        </form>
        <DialogActions
          cancelLabel="Cancel"
          onCancel={close}
          confirmLabel="Save"
          onConfirm={() => formRef.current?.requestSubmit()}
          busy={save.busy}
          confirmDisabled={!canSave}
          focusOnMount={false}
        />
      </DialogContent>
    </Dialog>
  );
}
