"use client";

import {
  useEffect,
  useMemo,
  useRef,
  useState,
  type FormEvent,
  type ReactNode,
} from "react";
import { Plus, Pencil, Trash2, TriangleAlert } from "lucide-react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ecosystemFeatureFlagsApi,
  type EcosystemFeatureFlag,
  type EcosystemFeatureFlagCreate,
  type EcosystemFeatureFlagUpdate,
} from "@agentic-toolkit/data/ecosystem-config";
import {
  duplicateFlagKeyMessage,
  flagFormBlockedReason,
  isFlagFormDirty,
  FLAG_KEY_REQUIRED_MESSAGE,
} from "./dialog-state";
import { errorMessage } from "@agenticdevelopertoolkit/ui/lib/errors";
import { useAction } from "@agenticdevelopertoolkit/ui/hooks/useAction";
import { DataTable, type DataTableColumn } from "@agenticdevelopertoolkit/ui/components/data-table";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Checkbox } from "@agenticdevelopertoolkit/ui/components/checkbox";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { Alert, AlertTitle, AlertDescription } from "@agenticdevelopertoolkit/ui/components/alert";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@agenticdevelopertoolkit/ui/components/dialog";
import { DialogActions } from "@agenticdevelopertoolkit/ui/components/dialog-actions";
import { AlertModal } from "@agenticdevelopertoolkit/ui/components/alert-modal";
import { UnsavedChangesAlert } from "@agenticdevelopertoolkit/ui/components/unsaved-changes-alert";
import { Field } from "@agenticdevelopertoolkit/ui/blocks/field";
import { DialogErrorText, ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { DetailsPane, useReportBusy, useReportSettingsDirty } from "@agentic-toolkit/resource";

/**
 * The empty list, hoisted to module scope: `flagsQuery.data ?? []` would otherwise mint a
 * fresh array on every render while the query is pending, re-running the memo keyed on it.
 */
const NO_FLAGS: EcosystemFeatureFlag[] = [];

/**
 * Per-product FEATURE FLAGS pane, scoped to one ecosystem — the per-ecosystem analogue of the admin
 * site's GLOBAL feature-flags page. Named on/off toggles this product's apps read: a row's checkbox
 * writes the toggle straight through (update by key); the pencil opens a create/edit dialog (create
 * = POST with a 409 on a duplicate key; edit = PUT, key immutable); the trash confirms via
 * AlertModal. react-query owns the list; every mutation invalidates the flags query key.
 */
export function FeatureFlagsPane({
  ecosystemId,
  help,
}: {
  ecosystemId?: string;
  /** Unused: the breadcrumb names the pane (kept for the ScopedPane prop shape). */
  title?: ReactNode;
  help?: ReactNode;
}) {
  const queryClient = useQueryClient();
  const queryKey = ["ecosystem-feature-flags", ecosystemId] as const;

  const flagsQuery = useQuery({
    queryKey,
    queryFn: () => ecosystemFeatureFlagsApi.get(ecosystemId!),
    enabled: !!ecosystemId,
  });

  // This pane publishes no topic list, so the read above has nowhere of its own to show itself —
  // the Configuration list one component up owns the spinner, and reporting is how the read gets
  // there. The table's own `loading` below is not a substitute: it is `isPending`, false on every
  // revisit.
  useReportBusy(flagsQuery.isFetching);

  const createMutation = useMutation({
    mutationFn: (body: EcosystemFeatureFlagCreate) =>
      ecosystemFeatureFlagsApi.create(ecosystemId!, body),
    onSuccess: () => queryClient.invalidateQueries({ queryKey }),
  });
  const updateMutation = useMutation({
    mutationFn: ({ key, body }: { key: string; body: EcosystemFeatureFlagUpdate }) =>
      ecosystemFeatureFlagsApi.update(ecosystemId!, key, body),
    onSuccess: () => queryClient.invalidateQueries({ queryKey }),
  });
  const deleteMutation = useMutation({
    mutationFn: (key: string) => ecosystemFeatureFlagsApi.delete(ecosystemId!, key),
    onSuccess: () => queryClient.invalidateQueries({ queryKey }),
  });

  const [filter, setFilter] = useState("");
  const [creating, setCreating] = useState(false);
  const [editing, setEditing] = useState<EcosystemFeatureFlag | null>(null);
  const [dialogDirty, setDialogDirty] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState<EcosystemFeatureFlag | null>(null);
  // Delete busy/error kept LOCAL (not useAction) so opening a different row's confirm clears a prior
  // failure — a shared action error would otherwise linger under the next delete modal.
  const [deleteBusy, setDeleteBusy] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);

  // Report unsaved dialog input to the settings overlay so a close can warn before discarding it
  // (a no-op outside a SettingsDirtyProvider) — same wiring as the other settings panes.
  useReportSettingsDirty("ecosystem-feature-flags", dialogDirty);

  // The list is already alphabetized by the api layer; `allFlags` feeds lookups + the collision
  // guard, `visibleFlags` is the filtered projection the table shows.
  const allFlags = flagsQuery.data ?? NO_FLAGS;
  const query = filter.trim().toLowerCase();
  const visibleFlags = useMemo(
    () =>
      query
        ? allFlags.filter(
            (f) =>
              f.key.toLowerCase().includes(query) ||
              f.description.toLowerCase().includes(query),
          )
        : allFlags,
    [allFlags, query],
  );

  function openDelete(flag: EcosystemFeatureFlag) {
    setDeleteError(null);
    setConfirmDelete(flag);
  }

  async function runDelete(flag: EcosystemFeatureFlag) {
    setDeleteBusy(true);
    setDeleteError(null);
    try {
      await deleteMutation.mutateAsync(flag.key);
      setConfirmDelete(null);
    } catch (e) {
      setDeleteError(errorMessage(e)); // failure keeps the modal open with its error
    } finally {
      setDeleteBusy(false);
    }
  }

  const columns: DataTableColumn<EcosystemFeatureFlag>[] = [
    {
      key: "enabled",
      header: "Enabled",
      width: "6rem",
      render: (flag) => (
        <Checkbox
          aria-label={`Enabled — ${flag.key}`}
          checked={flag.enabled}
          onCheckedChange={(checked) =>
            updateMutation.mutate({ key: flag.key, body: { enabled: checked === true } })
          }
        />
      ),
    },
    {
      key: "key",
      header: "Key",
      width: "20rem",
      render: (flag) => (
        <span className="block truncate font-mono text-sm text-apt-text" title={flag.key}>
          {flag.key}
        </span>
      ),
    },
    {
      key: "description",
      header: "Description",
      width: "minmax(0,1fr)",
      render: (flag) => (
        <span className="block truncate text-sm text-apt-text-muted" title={flag.description}>
          {flag.description || "—"}
        </span>
      ),
    },
    {
      key: "actions",
      header: "",
      width: "6rem",
      align: "end",
      resizable: false,
      render: (flag) => (
        <div className="flex items-center justify-end gap-1">
          <Button
            variant="ghost"
            size="icon-sm"
            aria-label={`Edit ${flag.key}`}
            onClick={() => setEditing(flag)}
          >
            <Pencil />
          </Button>
          <Button
            variant="destructive-ghost"
            size="icon-sm"
            aria-label={`Delete ${flag.key}`}
            onClick={() => openDelete(flag)}
          >
            <Trash2 />
          </Button>
        </div>
      ),
    },
  ];

  if (!ecosystemId) {
    return (
      <div className="min-h-0 flex-1 overflow-y-auto px-6 py-6">
        <p className="text-sm text-apt-text-muted">No product selected.</p>
      </div>
    );
  }

  return (
    // The shared details pane: its header carries this list's API button and "?" help.
    <DetailsPane
      help={help}
      api={{ path: "/ecosystem/feature-flags/{id}", pathValues: { id: ecosystemId }, title: "Feature flags API" }}
      bodyClassName="px-6 py-6"
    >
      <div className="space-y-6">
        {/* Filter field first, then the create affordance (right-justified via ml-auto). */}
        <div className="flex items-center gap-2">
          <Input
            type="search"
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            placeholder="Filter flags…"
            aria-label="Filter feature flags by key or description"
            className="max-w-xs"
          />
          <Button variant="ghost" size="sm" className="ml-auto" onClick={() => setCreating(true)}>
            <Plus data-icon="inline-start" />
            New flag
          </Button>
        </div>

        {flagsQuery.isError && (
          <Alert variant="error">
            <TriangleAlert />
            <AlertTitle>Couldn&apos;t load the feature flags</AlertTitle>
            <AlertDescription>{errorMessage(flagsQuery.error)}</AlertDescription>
          </Alert>
        )}

        {updateMutation.isError && !creating && editing === null && (
          <Alert variant="error">
            <TriangleAlert />
            <AlertTitle>Couldn&apos;t save the change</AlertTitle>
            <AlertDescription>{errorMessage(updateMutation.error)}</AlertDescription>
          </Alert>
        )}

        <DataTable<EcosystemFeatureFlag>
          columns={columns}
          rows={visibleFlags}
          getRowId={(flag) => flag.key}
          loading={flagsQuery.isPending}
          emptyLabel={
            query && allFlags.length > 0
              ? "No flags match your filter."
              : "No feature flags yet."
          }
          ariaLabel="Feature flags"
        />
      </div>

      <FlagDialog
        // A fresh key per target remounts the form, so its draft resets between opens.
        key={editing ? `edit:${editing.key}` : creating ? "create" : "closed"}
        open={creating || editing !== null}
        flag={editing}
        existingKeys={allFlags.map((f) => f.key)}
        onCreate={(body) => createMutation.mutateAsync(body)}
        onUpdate={(key, body) => updateMutation.mutateAsync({ key, body })}
        onClose={() => {
          setCreating(false);
          setEditing(null);
          // Clear any dialog-save error so it can't resurface as a page-level toggle alert.
          createMutation.reset();
          updateMutation.reset();
        }}
        onDirtyChange={setDialogDirty}
      />

      <AlertModal
        open={confirmDelete !== null}
        destructive
        title="Delete feature flag?"
        description={
          <>
            {confirmDelete
              ? `“${confirmDelete.key}” will be removed. Anything reading it falls back to its default.`
              : ""}
            {/* `DialogErrorText`, not `ErrorText`: Base UI renders `DialogDescription` as a
                `<p>`, and `ErrorText`'s own `<p role="alert">` cannot legally nest inside one.
                Its docstring holds the reasoning for the `role` this treatment keeps. */}
            <DialogErrorText error={deleteError} />
          </>
        }
        confirmLabel="Delete"
        onConfirm={() => confirmDelete && runDelete(confirmDelete)}
        cancelLabel="Cancel"
        onCancel={() => {
          setConfirmDelete(null);
          setDeleteError(null);
        }}
        busy={deleteBusy}
      />
    </DetailsPane>
  );
}

// Exported so it can be rendered directly in tests without standing up the whole
// pane's react-query wiring — `onCreate`/`onUpdate` are plain callback props, so
// the dialog itself needs no QueryClientProvider.
export function FlagDialog({
  open,
  flag,
  existingKeys,
  onCreate,
  onUpdate,
  onClose,
  onDirtyChange,
}: {
  open: boolean;
  /** The flag being edited, or null in create mode. */
  flag: EcosystemFeatureFlag | null;
  /** Keys already taken — a client-side pre-check before the server's 409. */
  existingKeys: string[];
  onCreate: (body: EcosystemFeatureFlagCreate) => Promise<unknown>;
  onUpdate: (key: string, body: EcosystemFeatureFlagUpdate) => Promise<unknown>;
  onClose: () => void;
  /** Reports whether the form holds unsaved input, so the settings overlay can warn. */
  onDirtyChange: (dirty: boolean) => void;
}) {
  const save = useAction();
  const editingMode = flag !== null;

  const initial = useMemo(
    () => ({
      key: flag?.key ?? "",
      enabled: flag?.enabled ?? false,
      description: flag?.description ?? "",
    }),
    [flag],
  );

  const [key, setKey] = useState(initial.key);
  const [enabled, setEnabled] = useState(initial.enabled);
  const [description, setDescription] = useState(initial.description);
  const formRef = useRef<HTMLFormElement>(null);

  // The gate — dirty check, blocking reason and every message string — lives in
  // @agentic-toolkit/adh/settings-dialogs, shared with admin's feature-flags page, which renders the
  // same create dialog against the same endpoint. It used to be an inline copy here, and the
  // copies had already diverged: admin's had no collision check at all.
  const form = { key, description, enabled };
  const dirty = isFlagFormDirty(form, initial);
  useEffect(() => onDirtyChange(open && dirty), [open, dirty, onDirtyChange]);
  // Why Save can't fire (null = nothing blocking). Save's own gate is `dirty && no reason`;
  // `save.busy` is applied at each button rather than folded in here.
  const blockedReason = flagFormBlockedReason(form, { editingMode, existingKeys });
  const canSave = dirty && blockedReason === null;

  const [confirmingClose, setConfirmingClose] = useState(false);

  // Escape, the backdrop, the × and Cancel all land here. A dirty draft asks first;
  // the post-save path calls onClose() directly and is deliberately not gated.
  function close() {
    if (save.busy) return;
    if (dirty) {
      setConfirmingClose(true);
      return;
    }
    onClose();
  }

  function handleSubmit(e: FormEvent) {
    e.preventDefault();
    void save.run(async () => {
      if (flag) {
        await onUpdate(flag.key, { enabled, description: description.trim() });
      } else {
        const trimmedKey = key.trim();
        if (!trimmedKey) throw new Error(FLAG_KEY_REQUIRED_MESSAGE);
        if (existingKeys.includes(trimmedKey)) {
          throw new Error(duplicateFlagKeyMessage(trimmedKey));
        }
        await onCreate({ key: trimmedKey, enabled, description: description.trim() });
      }
      onClose();
    });
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !next && close()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{editingMode ? "Edit feature flag" : "New feature flag"}</DialogTitle>
          <DialogDescription>
            {editingMode
              ? "Update whether the flag is on and its description. A flag's key is fixed once created."
              : "A named on/off toggle this product's apps can read."}
          </DialogDescription>
        </DialogHeader>
        <form ref={formRef} onSubmit={handleSubmit} className="flex flex-col gap-4">
          <Field label="Key">
            <Input
              value={key}
              onChange={(e) => setKey(e.target.value)}
              placeholder="e.g. dark_mode"
              className="font-mono"
              disabled={editingMode}
            />
          </Field>
          <Field label="Description">
            <Input
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="What does this flag gate? (optional)"
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
          {save.error ? (
            <ErrorText error={save.error} />
          ) : (
            // Why Save is grey — shown from the FIRST frame, not gated on `dirty`. A create
            // surface opens already blocked, on a requirement ("a key is required") that is
            // precisely what the user came here to supply, so stating it up front is
            // instruction rather than scolding — and without it the dialog opens on a dead
            // Save with nothing explaining it. (An EDIT opens on a loaded, valid flag, where
            // `blockedReason` is null, so it stays quiet without a `dirty` term.)
            blockedReason && (
              <p className="text-sm text-apt-text-muted" role="status">
                {blockedReason}
              </p>
            )
          )}
          {/* A submit button is what lets Enter submit the form; hidden because the visible
              confirm lives in DialogActions and calls form.requestSubmit(). It must carry the
              same disabled state as the visible confirm — being the form's implicit default
              button, Enter in any text field submits THIS button regardless of `hidden`/
              `display:none`; only `disabled` stops it. The `save.busy` term is NOT redundant
              with DialogActions' own busy handling: DialogActions hides its whole action row
              mid-save, which leaves this button the only reachable submit path exactly when a
              second write must not fire. */}
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
        <UnsavedChangesAlert
          open={confirmingClose}
          onDiscard={() => {
            setConfirmingClose(false);
            onClose();
          }}
          onStay={() => setConfirmingClose(false)}
        />
      </DialogContent>
    </Dialog>
  );
}
