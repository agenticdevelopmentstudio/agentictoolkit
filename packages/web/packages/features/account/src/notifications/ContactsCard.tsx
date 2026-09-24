"use client";

import { useMemo, useState, type FormEvent, type ReactElement, type ReactNode } from "react";
import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Mail, Phone } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@agenticdevelopertoolkit/ui/components/dialog";
import { AlertModal } from "@agenticdevelopertoolkit/ui/components/alert-modal";
import { UnsavedChangesAlert } from "@agenticdevelopertoolkit/ui/components/unsaved-changes-alert";
import {
  EditableList,
  Field,
  useEditableList,
  type EditableListColumn,
} from "@agenticdevelopertoolkit/ui/blocks";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { Badge } from "@agenticdevelopertoolkit/ui/components/badge";
import { DialogErrorText, ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import {
  addContact,
  confirmContactVerification,
  deleteContact,
  listContacts,
  startContactVerification,
  type ContactMethod,
} from "../api/account";
import { extractErrorMessage } from "@agentic-toolkit/auth/client";
import {
  DetailSection,
  ListBarActions,
  useBulkRemove,
  useReportSettingsDirty,
} from "@agentic-toolkit/resource";

const CONTACTS_KEY = ["account", "contacts"] as const;

function typeLabel(contact: ContactMethod): string {
  return contact.type === "email" ? "Email" : "Phone";
}

/** The primary email is the account's sign-in address — the server refuses to delete it, so the
 *  bar never offers to. */
function isRemovable(contact: ContactMethod): boolean {
  return !(contact.isPrimary && contact.type === "email");
}

/**
 * A row's verification state, and the one verb that stays IN the row: verifying it. It cannot
 * move to the bar with Add and Remove, because the code the user types belongs to exactly one
 * contact — a bar-level "Verify" over a selection would have no single field to read.
 *
 * The code itself is entered in a DIALOG, not inline. The inline form (field + Verify + Resend)
 * was wider than the Status column, so the table truncated it — Verify and Resend were clipped out
 * of reach on an ordinary laptop width — and its field had no visible label, only an aria-label,
 * so a sighted user saw a bare "123456" box with nothing saying what code or where it went. The
 * cell now holds only the badge and one button, which fits; the dialog has room for a real label.
 * Its own component so each row keeps its own dialog state across re-renders.
 */
function ContactStatusCell({
  contact,
  onChanged,
}: {
  contact: ContactMethod;
  onChanged: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [code, setCode] = useState("");

  const start = useMutation({
    mutationFn: () => startContactVerification(contact.id),
    onSuccess: () => setOpen(true),
  });
  const confirm = useMutation({
    mutationFn: () => confirmContactVerification(contact.id, code.trim()),
    onSuccess: () => {
      close();
      onChanged();
    },
  });

  function close() {
    setOpen(false);
    setCode("");
    confirm.reset();
  }

  if (contact.verified) return <Badge variant="success">Verified</Badge>;

  return (
    <div className="flex min-w-0 items-center gap-2">
      <Badge variant="orange">Unverified</Badge>
      <Button
        size="sm"
        variant="outline"
        aria-label={`Send code to ${contact.value}`}
        // Sending first, THEN opening: the dialog asks for a code, so it must not appear before
        // one is on its way. A send that fails says so here, in the row it was pressed in.
        onClick={() => start.mutate()}
        disabled={start.isPending}
      >
        {start.isPending && !open ? "Sending…" : "Send code"}
      </Button>
      {start.isError && !open && (
        <ErrorText
          error={extractErrorMessage(start.error, "Couldn’t send a code.")}
          className="truncate text-xs"
        />
      )}

      <Dialog open={open} onOpenChange={(o) => { if (!o && !confirm.isPending) close(); }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Verify {contact.type === "email" ? "email" : "phone"}</DialogTitle>
          </DialogHeader>
          <form
            className="flex flex-col gap-4"
            onSubmit={(e: FormEvent) => {
              e.preventDefault();
              if (confirm.isPending || code.trim() === "") return;
              confirm.mutate();
            }}
          >
            {/* `Field` wraps the input in its Label, so the caption IS the field's accessible
                name — seen and announced as one string. */}
            <Field label={`Enter the 6-digit code we sent to ${contact.value}`}>
              <Input
                id={`code-${contact.id}`}
                value={code}
                onChange={(e) => setCode(e.target.value)}
                inputMode="numeric"
                autoComplete="one-time-code"
                placeholder="123456"
                className="w-32 font-mono"
                autoFocus
                required
              />
            </Field>
            {start.isError && (
              <DialogErrorText error={extractErrorMessage(start.error, "Couldn’t send a code.")} />
            )}
            {confirm.isError && (
              <DialogErrorText error={extractErrorMessage(confirm.error, "That code didn’t match.")} />
            )}
            <DialogFooter>
              <Button
                type="button"
                size="sm"
                variant="ghost"
                onClick={() => start.mutate()}
                disabled={start.isPending || confirm.isPending}
                className="sm:mr-auto"
              >
                {start.isPending ? "Sending…" : "Resend"}
              </Button>
              <Button type="button" size="sm" variant="ghost" onClick={close} disabled={confirm.isPending}>
                Cancel
              </Button>
              <Button type="submit" size="sm" disabled={confirm.isPending || code.trim() === ""}>
                {confirm.isPending ? "Verifying…" : "Verify"}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  );
}

export interface ContactsCardProps {
  /** Optional per-row control, drawn in a "Visibility" column. Receives the ContactMethod so
   *  callers can render per-contact controls (e.g. a PrivacyLevelSelect in the Settings
   *  Contact info panel). It stays in the row because a privacy tier means nothing across a
   *  selection. */
  rowExtra?: (contact: ContactMethod) => ReactNode;
  /** When true, suppresses the "Contact methods" DetailSection heading so the topic's
   *  FeatureTitle (rendered by the settings registry) serves as the heading instead — the
   *  Contacts topic IS this list, and a second "Contact methods" under it just repeats it. */
  hideSectionTitle?: boolean;
}

export function ContactsCard({ rowExtra, hideSectionTitle = false }: ContactsCardProps = {}): ReactElement {
  const qc = useQueryClient();
  const { data, isLoading, error } = useQuery({
    queryKey: CONTACTS_KEY,
    queryFn: listContacts,
  });
  const invalidate = () => qc.invalidateQueries({ queryKey: CONTACTS_KEY });

  const [adding, setAdding] = useState(false);
  const [type, setType] = useState<"email" | "phone">("email");
  const [value, setValue] = useState("");
  // The unsaved-changes alert raised by a close attempt on a typed address.
  const [confirmingClose, setConfirmingClose] = useState(false);

  // The address itself is the typed work; `type` is a two-option selector with a default, so
  // flipping it loses nothing and arming the guard on it would prompt on a free exit. Withdraws
  // when `add` succeeds, since that clears the field. Same key shape as the sibling
  // PreferencesCard on these surfaces — one card, one report.
  const typed = value.trim() !== "";
  useReportSettingsDirty("notification-contacts", typed);

  const add = useMutation({
    mutationFn: () => addContact({ type, value: value.trim() }),
    onSuccess: () => {
      invalidate();
      closeAdd();
    },
  });

  // The rows the bar's Remove was pressed for — every ticked contact, not one row's trash can. A
  // partial failure keeps the confirm open on just the contacts still there; the re-read runs
  // either way, so the table never keeps showing one that is gone.
  const remove = useBulkRemove<ContactMethod>({
    getId: (c) => c.id,
    remove: deleteContact,
    onSettled: () => void invalidate(),
    onDone: () => list.clearSelection(),
    errorMessage: (err) => extractErrorMessage(err, "Couldn’t remove this contact."),
  });

  function openAdd() {
    setType("email");
    setValue("");
    add.reset();
    setAdding(true);
  }

  function closeAdd() {
    setAdding(false);
    // Cleared on close, not on open only: the dirty report reads `value`, and a dialog closed
    // over a typed address must stop reporting it the moment the user chose to discard it.
    setValue("");
  }

  /** Every way OUT of the dialog — Escape, the ×, Cancel. Asks before throwing a typed address away. */
  function requestCloseAdd() {
    if (add.isPending) return;
    if (typed) {
      setConfirmingClose(true);
      return;
    }
    closeAdd();
  }

  // ── Table ──────────────────────────────────────────────────────────────────

  // The same table admin's Users page draws. Add and Remove live on the BAR; the two controls a
  // row keeps — its verification step and its visibility — are each about that one contact.
  const columns: EditableListColumn<ContactMethod>[] = useMemo(() => {
    const cols: EditableListColumn<ContactMethod>[] = [
      {
        key: "type",
        header: "Type",
        width: "7rem",
        value: typeLabel,
        render: (c) => {
          const Icon = c.type === "email" ? Mail : Phone;
          return (
            <span className="flex items-center gap-2 text-apt-text">
              <Icon className="size-4 shrink-0 text-apt-text-muted" aria-hidden />
              {typeLabel(c)}
            </span>
          );
        },
      },
      {
        key: "value",
        header: "Value",
        value: (c) => c.value,
        render: (c) => (
          <span className="flex min-w-0 items-center gap-2">
            <span className="truncate font-mono text-sm text-apt-text">{c.value}</span>
            {c.isPrimary && <Badge variant="accent">Primary</Badge>}
          </span>
        ),
      },
      {
        key: "status",
        header: "Status",
        // Sized for its widest content — the Unverified badge beside Send code — so the button is
        // never truncated out of reach.
        width: "14rem",
        value: (c) => (c.verified ? "Verified" : "Unverified"),
        searchable: false,
        render: (c) => <ContactStatusCell contact={c} onChanged={invalidate} />,
      },
    ];
    if (rowExtra) {
      cols.push({
        key: "visibility",
        header: "Visibility",
        width: "10rem",
        resizable: false,
        render: (c) => rowExtra(c),
      });
    }
    return cols;
    // `invalidate` closes over the stable query client only.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rowExtra]);

  const list = useEditableList<ContactMethod>({
    rows: isLoading ? undefined : data,
    getRowId: (c) => c.id,
    columns,
  });
  const selected = list.selectedRows;
  const removable = selected.filter(isRemovable);

  const table = (
    <div className="flex flex-col gap-3">
      <p className="text-sm text-apt-text-muted">
        Add and verify the emails and phone numbers we can reach you on. A verified phone unlocks
        SMS notifications and 2-factor authentication.
      </p>
      <EditableList
        list={list}
        ariaLabel="Contact methods"
        loading={isLoading}
        error={error}
        errorTitle="Couldn’t load your contacts"
        columnWidthsKey="settings-contact-methods"
        describeRow={(c) => c.value}
        searchPlaceholder="Email or phone"
        emptyLabel="No contacts yet. Add an email or phone number."
        emptyFilteredLabel="No contacts match this search."
        actions={
          <ListBarActions
            noun="contact method"
            // Counts only what CAN go: a selection holding just the primary email leaves Remove
            // dark rather than opening a confirm for a delete the server will refuse.
            selectedCount={removable.length}
            onAdd={openAdd}
            onDelete={() => remove.open(removable)}
            deleteLabel="Remove"
          />
        }
      />
    </div>
  );

  return (
    <>
      {hideSectionTitle ? table : <DetailSection title="Contact methods">{table}</DetailSection>}

      <Dialog open={adding} onOpenChange={(open) => { if (!open) requestCloseAdd(); }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Add contact method</DialogTitle>
          </DialogHeader>
          <form
            className="flex flex-col gap-4"
            onSubmit={(e: FormEvent) => {
              e.preventDefault();
              if (add.isPending || !typed) return;
              add.mutate();
            }}
          >
            <Field label="Type">
              <Select
                id="add-type"
                value={type}
                onChange={(e) => setType(e.target.value as "email" | "phone")}
                className="w-28"
              >
                <option value="email">Email</option>
                <option value="phone">Phone</option>
              </Select>
            </Field>
            <Field label={type === "email" ? "Email address" : "Phone number (E.164)"}>
              {/* This field holds the READER'S own address, not a record's — it is
                  where their verification codes will be sent — so it is one of the few
                  in the fleet that genuinely wants the browser to offer to fill it.
                  Naming the standard token is the whole of that request: `Input` opts a
                  field out only while it names none, so this both restores autofill here
                  and states why, in the one attribute a browser already reads. The token
                  follows the Type select, because a field that says `email` while showing
                  a phone number offers the wrong thing. */}
              <Input
                id="add-value"
                value={value}
                autoComplete={type === "email" ? "email" : "tel"}
                onChange={(e) => setValue(e.target.value)}
                placeholder={type === "email" ? "you@example.com" : "+15555550123"}
                required
              />
            </Field>
            {type === "phone" && (
              <p className="text-xs leading-relaxed text-apt-text-dim">
                By adding a phone number you agree to receive verification and account-security
                text messages from Agentic Developer Hub. Msg &amp; data rates may apply; message
                frequency varies. Reply STOP to unsubscribe, HELP for help. See our{" "}
                <Link href="/privacy" className="underline hover:text-apt-text-muted">
                  Privacy Policy
                </Link>{" "}
                and{" "}
                <Link href="/terms" className="underline hover:text-apt-text-muted">
                  Terms
                </Link>
                .
              </p>
            )}
            {add.isError && (
              <DialogErrorText error={extractErrorMessage(add.error, "Couldn’t add that contact.")} />
            )}
            <DialogFooter>
              <Button type="button" variant="ghost" size="sm" onClick={requestCloseAdd} disabled={add.isPending}>
                Cancel
              </Button>
              <Button type="submit" size="sm" disabled={add.isPending || !typed}>
                {add.isPending ? "Adding…" : "Add"}
              </Button>
            </DialogFooter>
          </form>
          {/* Discard calls `closeAdd()` directly, NOT `requestCloseAdd()`: routing back through
              the gate would re-test `typed` — still true — and re-raise the alert forever. */}
          <UnsavedChangesAlert
            open={confirmingClose}
            onDiscard={() => {
              setConfirmingClose(false);
              closeAdd();
            }}
            onStay={() => setConfirmingClose(false)}
          />
        </DialogContent>
      </Dialog>

      {/* Remove confirm — for every ticked, removable row the bar's Remove was pressed with. */}
      <AlertModal
        open={remove.targets != null}
        tone="error"
        title={
          remove.targets && remove.targets.length > 1
            ? `Remove ${remove.targets.length} contact methods?`
            : "Remove contact method?"
        }
        description={
          remove.targets ? (
            <>
              <span>
                Remove {remove.targets.map((c) => c.value).join(", ")}? Notifications will no
                longer be sent there.
                {/* Asked of the SELECTION, not by comparing counts: after a partial failure the
                    confirm narrows to the failed rows, and a count comparison would then claim a
                    primary email was held back when none was ticked. */}
                {selected.some((c) => !isRemovable(c)) &&
                  " Your primary email stays — it is the address you sign in with."}
              </span>
              <DialogErrorText error={remove.error} />
            </>
          ) : undefined
        }
        confirmLabel="Remove"
        confirmVariant="destructive"
        cancelLabel="Cancel"
        busy={remove.pending}
        onConfirm={remove.confirm}
        onCancel={remove.cancel}
      />
    </>
  );
}
