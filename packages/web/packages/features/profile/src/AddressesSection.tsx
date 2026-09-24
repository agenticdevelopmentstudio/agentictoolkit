"use client";

import { useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";

import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@agenticdevelopertoolkit/ui/components/dialog";
import { AlertModal } from "@agenticdevelopertoolkit/ui/components/alert-modal";
import { DialogErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { UnsavedChangesAlert } from "@agenticdevelopertoolkit/ui/components/unsaved-changes-alert";
import {
  EditableList,
  Field,
  useEditableList,
  type EditableListColumn,
} from "@agenticdevelopertoolkit/ui/blocks";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import {
  createAddress,
  updateAddress,
  deleteAddress,
  resolvePrivacyLevel,
  addressesKey,
  type Address,
  type AddressWrite,
  type PrivacyGrant,
} from "@agentic-toolkit/data/profile";
import {
  DetailSection,
  ListBarActions,
  useBulkRemove,
  useReportSettingsDirty,
} from "@agentic-toolkit/resource";
import { PrivacyLevelControl } from "./PrivacyLevelControl";

// ── Types ──────────────────────────────────────────────────────────────────────

type DialogState =
  | { mode: "closed" }
  | { mode: "add" }
  | { mode: "edit"; address: Address };

const EMPTY_DRAFT: AddressWrite = {
  label: "",
  line1: "",
  line2: "",
  city: "",
  region: "",
  postalCode: "",
  country: "",
};

function addressSummary(a: Address): string {
  return [a.line1, a.line2, a.city, a.country].filter(Boolean).join(", ");
}

/** How a row names itself — to the row checkbox ("Select Home") and the delete confirm. The
 *  label when the user gave one, since that is the word they chose; the address otherwise,
 *  because an unlabelled row has nothing else to be told apart by. */
function describeAddress(a: Address): string {
  return a.label || addressSummary(a);
}

/** The editable fields, in one place — the diff below and `handleSave`'s body agree by
 *  construction instead of by two hand-maintained field lists. */
const ADDRESS_FIELDS = [
  "label",
  "line1",
  "line2",
  "city",
  "region",
  "postalCode",
  "country",
] as const;

/** The loaded row as a draft — the baseline an edit is diffed against. */
function draftOf(address: Address): AddressWrite {
  return {
    label: address.label,
    line1: address.line1,
    line2: address.line2,
    city: address.city,
    region: address.region,
    postalCode: address.postalCode,
    country: address.country,
  };
}

/** TRIMMED field-by-field comparison, because `handleSave` writes the trimmed values:
 *  adding surrounding whitespace changes the textbox, not the record. */
function sameAddress(a: AddressWrite, b: AddressWrite): boolean {
  return ADDRESS_FIELDS.every((k) => a[k].trim() === b[k].trim());
}

export const ADDRESS_LINE1_REQUIRED_MESSAGE = "Address line 1 is required.";

/**
 * WHY Save can't fire, or null when nothing is blocking. A reason rather than a boolean
 * because the gate DISABLES Save, which is exactly what makes `handleSave`'s own
 * `setFormError` unreachable — a greyed-out Save has to say what it is waiting on.
 */
export function addressBlockedReason(draft: AddressWrite): string | null {
  return draft.line1.trim() === "" ? ADDRESS_LINE1_REQUIRED_MESSAGE : null;
}

// ── Component ──────────────────────────────────────────────────────────────────

export interface AddressesSectionProps {
  addresses: Address[];
  isLoading: boolean;
  grants: PrivacyGrant[];
  /** When true, suppresses the "Addresses" DetailSection heading so the
   *  topic's FeatureTitle serves as the heading instead. */
  hideSectionTitle?: boolean;
  /** When set, all reads/writes target this workspace (org) owner via ?workspace=; the
   *  react-query cache key is namespaced by it so org and personal caches never collide. */
  workspaceSlug?: string;
  /** When true, hides the per-item privacy tier control (orgs have no public card). */
  hidePrivacy?: boolean;
  /** The list read's failure — handed to the table so a failed load never reads as "no addresses yet". */
  error?: unknown;
}

export function AddressesSection({
  addresses,
  isLoading,
  grants,
  hideSectionTitle = false,
  workspaceSlug,
  hidePrivacy = false,
  error,
}: AddressesSectionProps) {
  const qc = useQueryClient();
  const [dialogState, setDialogState] = useState<DialogState>({ mode: "closed" });
  const [draft, setDraft] = useState<AddressWrite>(EMPTY_DRAFT);
  const [formError, setFormError] = useState<string | null>(null);
  // The unsaved-changes alert raised by a close attempt on a dirty draft.
  const [confirmingClose, setConfirmingClose] = useState(false);

  // Personal keeps the bare key (shared with any other consumer/invalidator); an org
  // workspace namespaces its own cache slice. Shared with the reading panel — see addressesKey.
  const listKey = addressesKey(workspaceSlug);
  const wsOpts = workspaceSlug ? { workspace: workspaceSlug } : undefined;

  // ── Mutations ──────────────────────────────────────────────────────────────

  const createMutation = useMutation({
    mutationFn: (body: AddressWrite) => createAddress(body, wsOpts),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: listKey });
      closeDialog();
    },
    onError: (err: unknown) => {
      setFormError(err instanceof Error ? err.message : "Could not save. Try again.");
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, body }: { id: string; body: AddressWrite }) =>
      updateAddress(id, body, wsOpts),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: listKey });
      closeDialog();
    },
    onError: (err: unknown) => {
      setFormError(err instanceof Error ? err.message : "Could not save. Try again.");
    },
  });

  // The rows the bar's Delete was pressed for — every ticked address, not one row's trash can. A
  // partial failure keeps the confirm open on just the rows still there; the re-read runs either
  // way, so the table never keeps showing one that is gone.
  const bulkDelete = useBulkRemove<Address>({
    getId: (a) => a.id,
    remove: (id) => deleteAddress(id, wsOpts),
    onSettled: () => void qc.invalidateQueries({ queryKey: listKey }),
    onDone: () => list.clearSelection(),
    errorMessage: (err) => (err instanceof Error ? err.message : "Could not delete. Try again."),
  });

  // ── Handlers ───────────────────────────────────────────────────────────────

  function openAdd() {
    setDraft(EMPTY_DRAFT);
    setFormError(null);
    setDialogState({ mode: "add" });
  }

  function openEdit(address: Address) {
    setDraft(draftOf(address));
    setFormError(null);
    setDialogState({ mode: "edit", address });
  }

  function closeDialog() {
    setDialogState({ mode: "closed" });
    setFormError(null);
  }

  /** Every way OUT of the dialog: Escape, a backdrop click and the × all arrive here through
   *  `onOpenChange`, and so does Cancel. Asks before throwing a dirty draft away. */
  function requestCloseDialog() {
    if (isPending) return;
    if (draftDirty) {
      setConfirmingClose(true);
      return;
    }
    closeDialog();
  }

  function handleSave() {
    // Re-checked here, not only at the button: a form's DEFAULT submit (Enter in a text
    // field) reaches this handler without going through the button that carries them.
    if (isPending) return;
    const blocked = addressBlockedReason(draft);
    if (blocked) {
      setFormError(blocked);
      return;
    }
    if (!dirty) return;
    setFormError(null);
    const body: AddressWrite = {
      label: draft.label.trim(),
      line1: draft.line1.trim(),
      line2: draft.line2.trim(),
      city: draft.city.trim(),
      region: draft.region.trim(),
      postalCode: draft.postalCode.trim(),
      country: draft.country.trim(),
    };
    if (dialogState.mode === "add") {
      createMutation.mutate(body);
    } else if (dialogState.mode === "edit") {
      updateMutation.mutate({ id: dialogState.address.id, body });
    }
  }

  const isPending = createMutation.isPending || updateMutation.isPending;
  const dialogOpen = dialogState.mode !== "closed";
  const dialogTitle =
    dialogState.mode === "add" ? "Add address" : "Edit address";

  // Edit has a loaded baseline — gate Save on `dirty` too, so re-saving an untouched
  // address (a silent no-op write that still invalidates the list) isn't offered. Add has
  // no baseline to diff against, so it's exempt: filling the required field IS the change.
  const dirty =
    dialogState.mode !== "edit" || !sameAddress(draft, draftOf(dialogState.address));
  // What the CLOSE gate diffs against: the state the dialog OPENED on — the loaded row for an
  // edit, the blank draft for an add. Deliberately NOT the Save gate's `dirty` above, which is
  // unconditionally true in add mode; reusing it would raise the discard alert on every Add
  // dialog the user opens and thinks better of, which is worse than the bug it fixes.
  const draftDirty =
    dialogOpen &&
    !sameAddress(draft, dialogState.mode === "edit" ? draftOf(dialogState.address) : EMPTY_DRAFT);
  // The same draft diff, reported to the settings registry so the exits the dialog can't see for
  // itself — reload, a link click, a rail row switch — ask before discarding.
  useReportSettingsDirty("profile-addresses", draftDirty);

  const blockedReason = addressBlockedReason(draft);
  // dirty && valid ONLY — the in-flight term is applied at the button below.
  const canSave = dirty && blockedReason === null;

  // ── Table ──────────────────────────────────────────────────────────────────

  // The same table admin's Users page draws: one-line rows, sortable resizable columns, a search
  // box, and every verb on the BAR above it. No pencil and trash can per row — a verb repeated on
  // every row is two competing models (one row vs. the ticked ones). The one control a row keeps
  // is its own audience menu, which means nothing across a selection.
  const columns: EditableListColumn<Address>[] = useMemo(() => {
    const cols: EditableListColumn<Address>[] = [
      {
        key: "label",
        header: "Label",
        width: "10rem",
        value: (address) => address.label,
        render: (address) =>
          address.label ? (
            <span className="truncate font-medium text-apt-text">{address.label}</span>
          ) : (
            <span className="text-apt-text-dim">—</span>
          ),
      },
      {
        key: "address",
        header: "Address",
        value: (address) => addressSummary(address),
        render: (address) => (
          <span className="truncate text-sm text-apt-text">{addressSummary(address)}</span>
        ),
      },
      {
        key: "postalCode",
        header: "Postal code",
        width: "8rem",
        value: (address) => address.postalCode,
        render: (address) =>
          address.postalCode ? (
            <span className="truncate font-mono text-xs text-apt-text-muted">
              {address.postalCode}
            </span>
          ) : (
            <span className="text-apt-text-dim">—</span>
          ),
      },
    ];
    if (!hidePrivacy) {
      cols.push({
        key: "visibility",
        header: "Visibility",
        width: "10rem",
        resizable: false,
        render: (address) => (
          <PrivacyLevelControl
            targetTable="addresses"
            targetId={address.id}
            level={resolvePrivacyLevel(grants, "addresses", address.id)}
            ariaLabel={`Address visibility${address.label ? ` — ${address.label}` : ""}`}
          />
        ),
      });
    }
    return cols;
  }, [grants, hidePrivacy]);

  const list = useEditableList<Address>({
    rows: isLoading ? undefined : addresses,
    getRowId: (address) => address.id,
    columns,
  });
  const selected = list.selectedRows;

  const table = (
    <EditableList
      list={list}
      ariaLabel="Addresses"
      loading={isLoading}
      error={error}
      errorTitle="Couldn't load addresses"
      columnWidthsKey="settings-addresses"
      describeRow={describeAddress}
      onRowActivate={(id) => {
        const address = addresses.find((a) => a.id === id);
        if (address) openEdit(address);
      }}
      searchPlaceholder="Label, address or postal code"
      emptyLabel="No addresses yet. Add one to show it on your card."
      emptyFilteredLabel="No addresses match this search."
      actions={
        <ListBarActions
          noun="address"
          selectedCount={selected.length}
          onAdd={openAdd}
          onEdit={() => selected[0] && openEdit(selected[0])}
          onDelete={() => bulkDelete.open(selected)}
        />
      }
    />
  );

  // ── Render ─────────────────────────────────────────────────────────────────

  return (
    <>
      {hideSectionTitle ? table : <DetailSection title="Addresses">{table}</DetailSection>}

      {/* Add/Edit dialog */}
      <Dialog
        open={dialogOpen}
        onOpenChange={(open) => {
          if (!open) requestCloseDialog();
        }}
      >
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle>{dialogTitle}</DialogTitle>
          </DialogHeader>

          <form
            className="flex flex-col gap-3"
            onSubmit={(e) => { e.preventDefault(); handleSave(); }}
          >
            <Field label="Label (optional)">
              <Input
                id="address-label"
                value={draft.label}
                onChange={(e) =>
                  setDraft((d) => ({ ...d, label: e.target.value }))
                }
                placeholder="Home, Work…"
              />
            </Field>

            <Field
              label="Address line 1"
              error={formError ?? undefined}
            >
              <Input
                id="address-line1"
                value={draft.line1}
                onChange={(e) => {
                  setDraft((d) => ({ ...d, line1: e.target.value }));
                  setFormError(null);
                }}
                placeholder="123 Main St"
                aria-required="true"
                aria-invalid={formError != null}
                autoComplete="address-line1"
              />
            </Field>

            <Field label="Address line 2 (apt, suite, unit — optional)">
              <Input
                id="address-line2"
                value={draft.line2}
                onChange={(e) =>
                  setDraft((d) => ({ ...d, line2: e.target.value }))
                }
                placeholder="Apt 4B"
                autoComplete="address-line2"
              />
            </Field>

            <div className="grid grid-cols-2 gap-3">
              <Field label="City">
                <Input
                  id="address-city"
                  value={draft.city}
                  onChange={(e) =>
                    setDraft((d) => ({ ...d, city: e.target.value }))
                  }
                  placeholder="City"
                  autoComplete="address-level2"
                />
              </Field>

              <Field label="State / Region">
                <Input
                  id="address-region"
                  value={draft.region}
                  onChange={(e) =>
                    setDraft((d) => ({ ...d, region: e.target.value }))
                  }
                  placeholder="State"
                  autoComplete="address-level1"
                />
              </Field>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <Field label="Postal code">
                <Input
                  id="address-postal-code"
                  value={draft.postalCode}
                  onChange={(e) =>
                    setDraft((d) => ({ ...d, postalCode: e.target.value }))
                  }
                  placeholder="Postal code"
                  autoComplete="postal-code"
                />
              </Field>

              <Field label="Country">
                <Input
                  id="address-country"
                  value={draft.country}
                  onChange={(e) =>
                    setDraft((d) => ({ ...d, country: e.target.value }))
                  }
                  placeholder="Country"
                  autoComplete="country-name"
                />
              </Field>
            </div>

            <DialogFooter>
              {/* Say WHY Save is dark. No `dirty` term is needed to keep this quiet on an
                  untouched edit: `blockedReason` speaks only for VALIDITY, and a stored
                  address always has the line 1 it was created with. "Nothing has changed
                  yet" is self-explanatory; an unfilled required field is not. */}
              {blockedReason && (
                <p className="mr-auto text-sm text-apt-text-muted" role="status">
                  {blockedReason}
                </p>
              )}
              <Button
                type="button"
                variant="ghost"
                size="sm"
                onClick={requestCloseDialog}
                disabled={isPending}
              >
                Cancel
              </Button>
              <Button
                type="submit"
                size="sm"
                disabled={!canSave || isPending}
                className={
                  canSave && !isPending
                    ? "bg-apt-gold text-apt-bg hover:bg-apt-gold-bright"
                    : ""
                }
              >
                {isPending ? "Saving…" : "Save"}
              </Button>
            </DialogFooter>
          </form>
          {/* Discard calls `closeDialog()` directly, NOT `requestCloseDialog()`: routing back
              through the gate would re-test `draftDirty` — still true — and re-raise the alert
              forever. */}
          <UnsavedChangesAlert
            open={confirmingClose}
            onDiscard={() => {
              setConfirmingClose(false);
              closeDialog();
            }}
            onStay={() => setConfirmingClose(false)}
          />
        </DialogContent>
      </Dialog>

      {/* Delete confirm — for every ticked row the bar's Delete was pressed with. */}
      <AlertModal
        open={bulkDelete.targets != null}
        tone="error"
        title={
          bulkDelete.targets && bulkDelete.targets.length > 1
            ? `Remove ${bulkDelete.targets.length} addresses?`
            : "Remove address?"
        }
        description={
          bulkDelete.targets ? (
            <>
              <span>
                {/* "; " not ", " — an unlabelled row names itself by its summary, which is
                    itself comma-joined, so a comma list would run two addresses together. */}
                {`Remove ${bulkDelete.targets.map(describeAddress).join("; ")} from your card?`}
              </span>
              <DialogErrorText error={bulkDelete.error} />
            </>
          ) : undefined
        }
        confirmLabel="Remove"
        confirmVariant="destructive"
        cancelLabel="Cancel"
        busy={bulkDelete.pending}
        onConfirm={bulkDelete.confirm}
        onCancel={bulkDelete.cancel}
      />
    </>
  );
}
