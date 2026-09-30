"use client";

import { useEffect, useMemo, useRef, useState, type FormEvent, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { Plus, Pencil, Trash2 } from "lucide-react";
import {
  useServerBags,
  useCreateBag,
  useUpdateBag,
  useDeleteBag,
  type ServerBag,
} from "../api/admin";
import {
  bagFormBlockedReason,
  duplicateBagKeyMessage,
  isBagFormDirty,
  BAG_KEY_REQUIRED_MESSAGE,
  INVALID_JSON_MESSAGE,
} from "@agentic-toolkit/adh/settings-dialogs";
import { useAction } from "@agenticdevelopertoolkit/ui/hooks/useAction";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Textarea } from "@agenticdevelopertoolkit/ui/components/textarea";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@agenticdevelopertoolkit/ui/components/dialog";
import { DialogActions } from "@agenticdevelopertoolkit/ui/components/dialog-actions";
import { UnsavedChangesGuard } from "@agenticdevelopertoolkit/ui/components/unsaved-changes-guard";
import { UnsavedChangesAlert } from "@agenticdevelopertoolkit/ui/components/unsaved-changes-alert";
import { Field } from "@agenticdevelopertoolkit/ui/blocks/field";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { ProgressModal } from "@agenticdevelopertoolkit/ui/blocks";
import { FeatureTitle } from "@agentic-toolkit/resource";
import {
  EditableList,
  TypeToConfirmDialog,
  useBatchRun,
  useEditableList,
  type EditableListColumn,
} from "../components/editable-list";

/**
 * Has the stored bag changed under an open dialog? Compared on what a save would OVERWRITE — the
 * JSON document and the description — and not on `updatedAt`, which a no-op write also moves.
 */
function sameStoredBag(a: ServerBag, b: ServerBag): boolean {
  return (
    JSON.stringify(a.value) === JSON.stringify(b.value) &&
    (a.description ?? "") === (b.description ?? "")
  );
}

const BAG_CHANGED_MESSAGE =
  "This server bag changed since you opened it. Close and reopen it to edit the current value — saving now would overwrite someone else's change.";

/** Compact one-line JSON preview for a table cell / a search match. */
function preview(value: unknown): string {
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

/** Module-level so the delete run isn't handed a new key on every render. */
const BAGS_KEY = ["admin", "server-bags"];

/** The word an operator has to type to delete bags. */
const DELETE_WORD = "delete";

/**
 * Server bags — the global key → JSON store, on the shared editable list.
 *
 * Edit and Delete were a pencil and a trash in every row; they are bar buttons over the selection
 * now, which is the whole rule this list exists to enforce. Delete gained the typed word on the
 * way: a bag is read by the backend at runtime, so removing one changes behaviour nobody on this
 * page can see, and a confirm button one reflex away from the trash that opened it was never a
 * gate.
 */
export function ServerBagsPane({ help }: { help?: ReactNode } = {}) {
  const router = useRouter();
  const { data, isLoading, error } = useServerBags();
  const deleteBag = useDeleteBag();

  const [creating, setCreating] = useState(false);
  const [editing, setEditing] = useState<ServerBag | null>(null);
  const [dialogDirty, setDialogDirty] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);

  const deleteRun = useBatchRun({ invalidateKey: BAGS_KEY, successMessage: "deleted" });

  // Precompute each bag's JSON preview once per data change (not per render / per keystroke): the
  // search and the value column both read it, and JSON.stringify over large values isn't free.
  const previews = useMemo(
    () => new Map((data ?? []).map((b) => [b.key, preview(b.value)])),
    [data],
  );

  const columns = useMemo<EditableListColumn<ServerBag>[]>(
    () => [
      {
        key: "key",
        header: "Key",
        width: "18rem",
        value: (bag) => bag.key,
        render: (bag) => (
          <span className="block truncate font-mono text-sm text-apt-text" title={bag.key}>
            {bag.key}
          </span>
        ),
      },
      {
        key: "value",
        header: "Value",
        // minmax(0,1fr): flex to the remaining width but allow shrinking below the content so the
        // single-line JSON preview can truncate instead of stretching the column.
        width: "minmax(0,1fr)",
        // Searched and sorted by the same preview string the cell shows — which is what makes the
        // search box able to find a bag by something INSIDE its JSON.
        value: (bag) => previews.get(bag.key) ?? preview(bag.value),
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
        value: (bag) => bag.description,
        render: (bag) => (
          <span className="block truncate text-sm text-apt-text-muted" title={bag.description}>
            {bag.description || "—"}
          </span>
        ),
      },
    ],
    [previews],
  );

  const list = useEditableList<ServerBag>({
    rows: data,
    getRowId: (bag) => bag.key,
    columns,
    initialSort: { key: "key", dir: "asc" },
  });

  const selected = list.selectedRows;
  const allKeys = useMemo(() => list.allRows.map((b) => b.key), [list.allRows]);
  /**
   * The row as it stands in the CURRENT list, for the key the dialog is editing.
   *
   * `editing` is a snapshot taken when the dialog opened, and a server bag is a global document
   * every site reads: a background refetch can bring a newer value while the operator is typing,
   * and the PATCH replaces the whole JSON blob with no version check of any kind. Without this the
   * second admin to press Save silently erases the first one's change. Compared at submit time
   * rather than remounted at refetch time — remounting would throw away the draft, which is the
   * other way to lose an edit.
   */
  const editingLatest = useMemo(
    () => (editing ? (list.allRows.find((b) => b.key === editing.key) ?? null) : null),
    [editing, list.allRows],
  );

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <FeatureTitle
        title="Server Bags"
        api={{ method: "GET", path: "/system/server-bag", pathValues: {}, title: "Server bag API" }}
        help={help}
      />
      <div className="flex min-h-0 min-w-0 flex-1 flex-col overflow-y-auto px-6 pb-8 pt-2">
        <p className="mb-6 max-w-2xl text-sm text-apt-text-muted">
          Global key → JSON configuration values read by the backend at runtime. Every site reads
          the same store; a value is arbitrary JSON. Distinct from Settings, which are typed
          per-user and per-ecosystem policy.
        </p>

        <EditableList<ServerBag>
          list={list}
          ariaLabel="Server bags"
          loading={isLoading}
          error={error}
          errorTitle="Couldn't load the server bag"
          columnWidthsKey="admin-server-bags"
          // The key IS the row id, so the table's guess skips it and reads whatever string comes
          // next. Named here instead — the key is the only thing on the row that is unique.
          describeRow={(bag) => bag.key}
          searchPlaceholder="Key, value or description"
          emptyLabel="No server bags yet."
          emptyFilteredLabel="No bags match these filters."
          actions={
            <>
              <Button size="sm" variant="ghost" onClick={() => setCreating(true)}>
                <Plus data-icon="inline-start" />
                New Server Bag
              </Button>
              {/* One row, or nothing: the dialog edits one key and one JSON document. */}
              <Button
                size="sm"
                variant="ghost"
                disabled={selected.length !== 1}
                onClick={() => setEditing(selected[0]!)}
              >
                <Pencil data-icon="inline-start" />
                Edit
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

        <UnsavedChangesGuard when={dialogDirty} onNavigate={(href) => router.push(href)} />

        <BagDialog
          // A fresh key per target remounts the form, so its draft resets between opens.
          key={editing ? `edit:${editing.key}` : creating ? "create" : "closed"}
          open={creating || editing !== null}
          bag={editing}
          latest={editingLatest}
          existingKeys={allKeys}
          onClose={() => {
            setCreating(false);
            setEditing(null);
          }}
          onDirtyChange={setDialogDirty}
        />

        <TypeToConfirmDialog
          open={confirmDelete}
          title={selected.length === 1 ? "Delete this bag?" : `Delete ${selected.length} bags?`}
          description={
            <>
              Permanently deletes{" "}
              <span className="font-mono text-apt-text">{selected.map((b) => b.key).join(", ")}</span>
              . Anything reading a deleted bag falls back to its own default.
            </>
          }
          confirmValue={DELETE_WORD}
          valueNoun="word"
          confirmLabel="Delete"
          onCancel={() => setConfirmDelete(false)}
          onConfirm={() => {
            setConfirmDelete(false);
            void deleteRun.run(
              selected.map((bag) => ({ id: bag.key, label: bag.key })),
              (item) => deleteBag.mutateAsync(item.id),
            );
          }}
        />

        <ProgressModal
          open={deleteRun.state.running || deleteRun.state.finished}
          title="Deleting server bags"
          description="Each bag is deleted on its own; a failure leaves the earlier deletions in place."
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
      </div>
    </div>
  );
}

// Exported (not just used locally) so a test can render it in isolation and
// `vi.mock` the `useCreateBag`/`useUpdateBag` module boundary — see
// `BagDialog.test.tsx`.
export function BagDialog({
  open,
  bag,
  latest,
  existingKeys,
  onClose,
  onDirtyChange,
}: {
  open: boolean;
  /** The bag being edited, or null in create mode. */
  bag: ServerBag | null;
  /**
   * The same bag as it stands in the list right now, or null while creating.
   *
   * `bag` is what the operator OPENED; this is what the server has. When they differ, saving would
   * overwrite an edit nobody in this browser has seen.
   */
  latest: ServerBag | null;
  /** Keys already taken — a create must not collide (surfaced before the 409). */
  existingKeys: string[];
  onClose: () => void;
  /** Reports whether the form holds unsaved input, so the page's guard covers it. */
  onDirtyChange: (dirty: boolean) => void;
}) {
  const createBag = useCreateBag();
  const updateBag = useUpdateBag();
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
        // OPTIMISTIC CONCURRENCY, such as this surface can have. `PATCH /system-config/:key` takes
        // whatever it is sent and has no version column to check against, so the only place the
        // conflict can be caught is here — and catching it matters more than usual because a
        // server bag is one document read by every site, and the PATCH replaces its whole JSON.
        // A `latest` of null means the row has left the list entirely, which the save's own 404
        // will report more accurately than a guess here would.
        if (latest && !sameStoredBag(latest, bag)) {
          throw new Error(BAG_CHANGED_MESSAGE);
        }
        await updateBag.mutateAsync({
          key: bag.key,
          changes: { value, description: description.trim() },
        });
      } else {
        const trimmedKey = key.trim();
        if (!trimmedKey) throw new Error(BAG_KEY_REQUIRED_MESSAGE);
        if (existingKeys.includes(trimmedKey)) {
          throw new Error(duplicateBagKeyMessage(trimmedKey));
        }
        await createBag.mutateAsync({
          key: trimmedKey,
          value,
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
          <DialogTitle>{editingMode ? "Edit server bag" : "New server bag"}</DialogTitle>
          <DialogDescription>
            {editingMode
              ? "Update the JSON value or description. A bag's key is fixed once created."
              : "Server bags are global — every site reads the same value."}
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
            // can return today — the column is NOT NULL jsonb — but `ServerBag["value"]` is
            // typed `unknown`, and for a bag with NO value `JSON.stringify` returns the
            // non-string `undefined`, the parse throws, and this line names the reason on an
            // untouched dialog. That is CORRECT, not a regression: Save really is blocked there
            // (handleSubmit would throw the same sentence), and the removed `&& dirty` term was
            // hiding it. `bagDialogState.test.ts` pins the case.
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
              `display:none`; only `disabled` stops it. That includes `save.busy`: DialogActions
              drops the visible confirm while saving, leaving THIS the only reachable submit
              path, so without the busy term Enter mid-save fires a second write. */}
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
