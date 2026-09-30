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
  ecosystemServerBagsApi,
  type EcosystemServerBag,
  type EcosystemServerBagCreate,
  type EcosystemServerBagUpdate,
} from "@agentic-toolkit/data/ecosystem-config";
import {
  bagFormBlockedReason,
  duplicateBagKeyMessage,
  isBagFormDirty,
  BAG_KEY_REQUIRED_MESSAGE,
  INVALID_JSON_MESSAGE,
} from "./dialog-state";
import { errorMessage } from "@agenticdevelopertoolkit/ui/lib/errors";
import { useAction } from "@agenticdevelopertoolkit/ui/hooks/useAction";
import { DataTable, type DataTableColumn } from "@agenticdevelopertoolkit/ui/components/data-table";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Textarea } from "@agenticdevelopertoolkit/ui/components/textarea";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
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
 * The empty list, hoisted to module scope: `bagsQuery.data ?? []` would otherwise mint a
 * fresh array on every render while the query is pending, re-running the memos keyed on it.
 */
const NO_BAGS: EcosystemServerBag[] = [];

/** Compact one-line JSON preview for a table cell / filter match. */
function preview(value: unknown): string {
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

/**
 * Per-product SERVER BAGS pane, scoped to one ecosystem — the per-ecosystem analogue of the admin
 * site's GLOBAL server-bags page. Arbitrary key → JSON config values this product's backend reads at
 * runtime. New/Edit dialog carries a JSON textarea (validated with JSON.parse); create = POST (409
 * on a duplicate key), edit = PUT (key immutable); the trash confirms via AlertModal. react-query
 * owns the list; every mutation invalidates the bags query key.
 */
export function ServerBagsPane({
  ecosystemId,
  help,
}: {
  ecosystemId?: string;
  /** Unused: the breadcrumb names the pane (kept for the ScopedPane prop shape). */
  title?: ReactNode;
  help?: ReactNode;
}) {
  const queryClient = useQueryClient();
  const queryKey = ["ecosystem-server-bags", ecosystemId] as const;

  const bagsQuery = useQuery({
    queryKey,
    queryFn: () => ecosystemServerBagsApi.get(ecosystemId!),
    enabled: !!ecosystemId,
  });

  // Publishes no topic list of its own: the Configuration list one component up owns the spinner,
  // and this report is the only way a read down here reaches it. See `useReportBusy`.
  useReportBusy(bagsQuery.isFetching);

  const createMutation = useMutation({
    mutationFn: (body: EcosystemServerBagCreate) =>
      ecosystemServerBagsApi.create(ecosystemId!, body),
    onSuccess: () => queryClient.invalidateQueries({ queryKey }),
  });
  const updateMutation = useMutation({
    mutationFn: ({ key, body }: { key: string; body: EcosystemServerBagUpdate }) =>
      ecosystemServerBagsApi.update(ecosystemId!, key, body),
    onSuccess: () => queryClient.invalidateQueries({ queryKey }),
  });
  const deleteMutation = useMutation({
    mutationFn: (key: string) => ecosystemServerBagsApi.delete(ecosystemId!, key),
    onSuccess: () => queryClient.invalidateQueries({ queryKey }),
  });

  const [filter, setFilter] = useState("");
  const [creating, setCreating] = useState(false);
  const [editing, setEditing] = useState<EcosystemServerBag | null>(null);
  const [dialogDirty, setDialogDirty] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState<EcosystemServerBag | null>(null);
  // Delete busy/error kept LOCAL so opening a different row's confirm clears a prior failure.
  const [deleteBusy, setDeleteBusy] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);

  useReportSettingsDirty("ecosystem-server-bags", dialogDirty);

  const allBags = bagsQuery.data ?? NO_BAGS;
  // Precompute each bag's JSON preview ONCE per data change (not per render / per keystroke): the
  // filter and the value column both read it, and JSON.stringify over large values isn't free.
  const previews = useMemo(
    () => new Map(allBags.map((b) => [b.key, preview(b.value)])),
    [allBags],
  );
  const query = filter.trim().toLowerCase();
  const visibleBags = useMemo(
    () =>
      query
        ? allBags.filter(
            (b) =>
              b.key.toLowerCase().includes(query) ||
              b.description.toLowerCase().includes(query) ||
              (previews.get(b.key) ?? "").toLowerCase().includes(query),
          )
        : allBags,
    [allBags, previews, query],
  );

  function openDelete(bag: EcosystemServerBag) {
    setDeleteError(null);
    setConfirmDelete(bag);
  }

  async function runDelete(bag: EcosystemServerBag) {
    setDeleteBusy(true);
    setDeleteError(null);
    try {
      await deleteMutation.mutateAsync(bag.key);
      setConfirmDelete(null);
    } catch (e) {
      setDeleteError(errorMessage(e)); // failure keeps the modal open with its error
    } finally {
      setDeleteBusy(false);
    }
  }

  const columns: DataTableColumn<EcosystemServerBag>[] = [
    {
      key: "key",
      header: "Key",
      width: "18rem",
      render: (bag) => (
        <span className="block truncate font-mono text-sm text-apt-text" title={bag.key}>
          {bag.key}
        </span>
      ),
    },
    {
      key: "value",
      header: "Value",
      // minmax(0,1fr): flex to the remaining width but allow shrinking so the JSON preview truncates.
      width: "minmax(0,1fr)",
      render: (bag) => {
        const text = previews.get(bag.key) ?? preview(bag.value);
        return (
          <span className="block truncate font-mono text-xs text-apt-text-muted" title={text}>
            {text}
          </span>
        );
      },
    },
    {
      key: "description",
      header: "Description",
      width: "16rem",
      render: (bag) => (
        <span className="block truncate text-sm text-apt-text-muted" title={bag.description}>
          {bag.description || "—"}
        </span>
      ),
    },
    {
      key: "actions",
      header: "",
      width: "6rem",
      align: "end",
      resizable: false,
      render: (bag) => (
        <div className="flex items-center justify-end gap-1">
          <Button
            variant="ghost"
            size="icon-sm"
            aria-label={`Edit ${bag.key}`}
            onClick={() => setEditing(bag)}
          >
            <Pencil />
          </Button>
          <Button
            variant="destructive-ghost"
            size="icon-sm"
            aria-label={`Delete ${bag.key}`}
            onClick={() => openDelete(bag)}
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
      api={{ path: "/ecosystem/server-bag/{id}", pathValues: { id: ecosystemId }, title: "Server bags API" }}
      bodyClassName="px-6 py-6"
    >
      <div className="space-y-6">
        {/* Filter field first, then the create affordance (right-justified via ml-auto). */}
        <div className="flex items-center gap-2">
          <Input
            type="search"
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            placeholder="Filter bags…"
            aria-label="Filter server bags by key, value, or description"
            className="max-w-xs"
          />
          <Button variant="ghost" size="sm" className="ml-auto" onClick={() => setCreating(true)}>
            <Plus data-icon="inline-start" />
            New bag
          </Button>
        </div>

        {bagsQuery.isError && (
          <Alert variant="error">
            <TriangleAlert />
            <AlertTitle>Couldn&apos;t load the server bags</AlertTitle>
            <AlertDescription>{errorMessage(bagsQuery.error)}</AlertDescription>
          </Alert>
        )}

        <DataTable<EcosystemServerBag>
          columns={columns}
          rows={visibleBags}
          getRowId={(bag) => bag.key}
          loading={bagsQuery.isPending}
          emptyLabel={
            query && allBags.length > 0
              ? "No bags match your filter."
              : "No server bags yet."
          }
          ariaLabel="Server bags"
        />
      </div>

      <BagDialog
        // A fresh key per target remounts the form, so its draft resets between opens.
        key={editing ? `edit:${editing.key}` : creating ? "create" : "closed"}
        open={creating || editing !== null}
        bag={editing}
        existingKeys={allBags.map((b) => b.key)}
        onCreate={(body) => createMutation.mutateAsync(body)}
        onUpdate={(key, body) => updateMutation.mutateAsync({ key, body })}
        onClose={() => {
          setCreating(false);
          setEditing(null);
        }}
        onDirtyChange={setDialogDirty}
      />

      <AlertModal
        open={confirmDelete !== null}
        destructive
        title="Delete server bag?"
        description={
          <>
            {confirmDelete
              ? `“${confirmDelete.key}” will be removed. Anything reading it falls back to its default.`
              : ""}
            {/* `DialogErrorText` — the shared nestable error line; see its docstring for why
                `ErrorText`'s `<p>` cannot go inside `DialogDescription`. */}
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
export function BagDialog({
  open,
  bag,
  existingKeys,
  onCreate,
  onUpdate,
  onClose,
  onDirtyChange,
}: {
  open: boolean;
  /** The bag being edited, or null in create mode. */
  bag: EcosystemServerBag | null;
  /** Keys already taken — a client-side pre-check before the server's 409. */
  existingKeys: string[];
  onCreate: (body: EcosystemServerBagCreate) => Promise<unknown>;
  onUpdate: (key: string, body: EcosystemServerBagUpdate) => Promise<unknown>;
  onClose: () => void;
  /** Reports whether the form holds unsaved input, so the settings overlay can warn. */
  onDirtyChange: (dirty: boolean) => void;
}) {
  const save = useAction();
  const editingMode = bag !== null;

  const initial = useMemo(
    () => ({
      key: bag?.key ?? "",
      valueText: bag ? JSON.stringify(bag.value, null, 2) : "",
      description: bag?.description ?? "",
    }),
    [bag],
  );

  const [key, setKey] = useState(initial.key);
  const [valueText, setValueText] = useState(initial.valueText);
  const [description, setDescription] = useState(initial.description);
  const formRef = useRef<HTMLFormElement>(null);

  // The gate — dirty check, blocking reason and every message string — lives in
  // @agentic-toolkit/adh/settings-dialogs, shared with admin's server-bags page, which renders the same
  // dialog against the same endpoint. It used to be an inline copy here, byte-equivalent and kept
  // that way by hand: measured over there, unmeasured here.
  const form = { key, valueText, description };
  const dirty = isBagFormDirty(form, initial);
  useEffect(() => onDirtyChange(open && dirty), [open, dirty, onDirtyChange]);
  // Why Save can't fire (null = nothing blocking). Save's own gate is `dirty && no reason`;
  // `save.busy` is applied at each button rather than folded in here.
  const blockedReason = bagFormBlockedReason(form, { editingMode, existingKeys });
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
      let value: unknown;
      try {
        value = JSON.parse(valueText);
      } catch {
        throw new Error(INVALID_JSON_MESSAGE);
      }
      if (bag) {
        await onUpdate(bag.key, { value, description: description.trim() });
      } else {
        const trimmedKey = key.trim();
        if (!trimmedKey) throw new Error(BAG_KEY_REQUIRED_MESSAGE);
        if (existingKeys.includes(trimmedKey)) {
          throw new Error(duplicateBagKeyMessage(trimmedKey));
        }
        await onCreate({ key: trimmedKey, value, description: description.trim() });
      }
      onClose();
    });
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !next && close()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{editingMode ? "Edit server bag" : "New server bag"}</DialogTitle>
          <DialogDescription>
            {editingMode
              ? "Update the JSON value or description. A bag's key is fixed once created."
              : "An arbitrary key → JSON config value this product's backend reads at runtime."}
          </DialogDescription>
        </DialogHeader>
        <form ref={formRef} onSubmit={handleSubmit} className="flex flex-col gap-4">
          <Field label="Key">
            <Input
              value={key}
              onChange={(e) => setKey(e.target.value)}
              placeholder="e.g. onboarding_config"
              className="font-mono"
              disabled={editingMode}
            />
          </Field>
          <Field label="Value (JSON)">
            <Textarea
              value={valueText}
              onChange={(e) => setValueText(e.target.value)}
              placeholder={'e.g. { "maxItems": 20 }'}
              className="min-h-40 font-mono text-sm"
              rows={8}
              spellCheck={false}
            />
          </Field>
          <Field label="Description">
            <Input
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="What does this configure? (optional)"
            />
          </Field>
          {save.error ? (
            <ErrorText error={save.error} />
          ) : (
            // Why Save is grey — shown from the FIRST frame, not gated on `dirty`. A create
            // surface opens already blocked (an empty value box is not valid JSON), and the
            // requirement it is blocked ON is exactly what the user came here to supply, so
            // stating it up front is instruction, not scolding.
            //
            // An EDIT usually opens quiet, but not because edit surfaces are EXEMPT:
            // `bagFormBlockedReason` parses `valueText` BEFORE it looks at `editingMode`, so an
            // edit is silent exactly when the loaded bag round-trips
            // (`JSON.parse(JSON.stringify(value))`). That holds for every value this endpoint
            // can return today — the column is NOT NULL jsonb and the create body rejects a
            // missing `value` — but the bag's `value` is typed `unknown`, and for a bag with NO
            // value `JSON.stringify` returns the non-string `undefined`, the parse throws, and
            // this line names the reason on an untouched dialog. That is CORRECT, not a
            // regression: Save really is blocked there (handleSubmit would throw the same
            // sentence), and the removed `&& dirty` term was hiding it.
            // `bagDialogState.test.ts` pins the case.
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
