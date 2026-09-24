"use client";

import { useMemo, useState, type ReactElement, type ReactNode } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Smartphone } from "lucide-react";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Card, CardContent } from "@agenticdevelopertoolkit/ui/components/card";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { Badge } from "@agenticdevelopertoolkit/ui/components/badge";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@agenticdevelopertoolkit/ui/components/dialog";
import { AlertModal } from "@agenticdevelopertoolkit/ui/components/alert-modal";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { Spinner } from "@agenticdevelopertoolkit/ui/components/spinner";
import { DialogErrorText, ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import {
  EditableList,
  Field,
  useEditableList,
  type EditableListColumn,
} from "@agenticdevelopertoolkit/ui/blocks";
import { formatDate } from "@agenticdevelopertoolkit/ui/lib/timestamps";
import {
  DetailSection,
  ListBarActions,
  SettingsBody,
  useBulkRemove,
} from "@agentic-toolkit/resource";
import {
  confirmTotp,
  enrollTotp,
  getMfaStatus,
  listWebauthn,
  regenerateRecoveryCodes,
  registerWebauthn,
  removeTotp,
  removeWebauthn,
  setPreferredMethod,
  type MfaStatus,
  type PreferredMethod,
  type WebauthnCredential,
} from "@agentic-toolkit/auth";
import { extractErrorMessage } from "@agentic-toolkit/auth/client";

const MFA_KEY = ["account", "mfa"] as const;
const WEBAUTHN_KEY = ["account", "webauthn"] as const;

/** The one line under a section title saying what the section is for. `DetailSection` has no
 *  description slot, so every section spells it the same way here rather than each its own. */
function SectionNote({ children }: { children: ReactNode }): ReactElement {
  return <p className="text-sm text-apt-text-muted">{children}</p>;
}

/** A non-table section: `DetailSection` title over a `Card`, the shape AccountPanel's Email and
 *  Password sections take — so Security's forms sit in the same boxes as their siblings'. The
 *  passkeys table is the exception: an `EditableList` draws its own frame, and a card around it
 *  would be a box in a box. */
function FormSection({ title, children }: { title: string; children: ReactNode }): ReactElement {
  return (
    <DetailSection title={title}>
      <Card>
        <CardContent className="flex flex-col gap-3">{children}</CardContent>
      </Card>
    </DetailSection>
  );
}

function StatusRow({ on, label }: { on: boolean; label: string }): ReactElement {
  return (
    <div className="flex items-center justify-between py-1.5 text-sm">
      <span className="text-apt-text">{label}</span>
      {on ? <Badge variant="success">On</Badge> : <Badge variant="neutral">Off</Badge>}
    </div>
  );
}

function TotpSection({ status }: { status: MfaStatus }): ReactElement {
  const qc = useQueryClient();
  const [secret, setSecret] = useState<string | null>(null);
  const [code, setCode] = useState("");
  const invalidate = () => qc.invalidateQueries({ queryKey: MFA_KEY });

  const enroll = useMutation({
    mutationFn: enrollTotp,
    onSuccess: (e) => setSecret(e.secret),
  });
  const confirm = useMutation({
    mutationFn: () => confirmTotp(code.trim()),
    onSuccess: () => {
      setSecret(null);
      setCode("");
      invalidate();
    },
  });
  const remove = useMutation({ mutationFn: removeTotp, onSuccess: invalidate });

  return (
    <FormSection title="Authenticator app">
      <SectionNote>
        Use a TOTP app (1Password, Google Authenticator…) to generate sign-in codes.
      </SectionNote>
      {status.totp ? (
        <div className="flex items-center gap-3">
          <Badge variant="success">Enabled</Badge>
          <Button
            size="sm"
            variant="destructive"
            onClick={() => remove.mutate()}
            disabled={remove.isPending}
          >
            Remove
          </Button>
        </div>
      ) : secret ? (
        <div className="space-y-3">
          <p className="text-sm text-apt-text-muted">
            Add this secret to your authenticator, then enter the 6-digit code it shows.
          </p>
          <code className="block rounded-md border border-apt-border bg-apt-surface-2 px-3 py-2 font-mono text-sm tracking-widest text-apt-text">
            {secret}
          </code>
          <div className="flex items-end gap-2">
            <div className="space-y-1">
              <Label htmlFor="totp-code" className="text-xs text-apt-text-muted">
                6-digit code
              </Label>
              <Input
                id="totp-code"
                value={code}
                onChange={(e) => setCode(e.target.value)}
                inputMode="numeric"
                autoComplete="one-time-code"
                placeholder="123456"
                className="w-32 font-mono"
              />
            </div>
            <Button onClick={() => confirm.mutate()} disabled={confirm.isPending || code.trim().length === 0}>
              {confirm.isPending ? "Verifying…" : "Verify & enable"}
            </Button>
          </div>
          {confirm.isError && (
            <ErrorText error={extractErrorMessage(confirm.error, "That code didn’t match.")} className="text-xs" />
          )}
        </div>
      ) : (
        <div>
          <Button onClick={() => enroll.mutate()} disabled={enroll.isPending}>
            {enroll.isPending ? "Starting…" : "Set up authenticator"}
          </Button>
        </div>
      )}
    </FormSection>
  );
}

const KIND_LABEL: Record<WebauthnCredential["kind"], string> = {
  passkey: "Passkey",
  security_key: "Security key",
};

function credentialName(cred: WebauthnCredential): string {
  return cred.name || "Unnamed";
}

function PasskeysSection(): ReactElement {
  const qc = useQueryClient();
  const { data, isLoading, error } = useQuery({ queryKey: WEBAUTHN_KEY, queryFn: listWebauthn });
  const [adding, setAdding] = useState(false);
  const [name, setName] = useState("");
  // Both lists move on a credential change: the MFA status's `webauthn` flag (and so the
  // Two-factor summary and the preferred-method choices) is derived from whether any exist.
  const invalidate = () => {
    qc.invalidateQueries({ queryKey: WEBAUTHN_KEY });
    qc.invalidateQueries({ queryKey: MFA_KEY });
  };
  const register = useMutation({
    mutationFn: (kind: "passkey" | "security_key") => registerWebauthn(kind, name.trim() || "My device"),
    onSuccess: () => {
      setName("");
      setAdding(false);
      invalidate();
    },
  });
  // The rows the bar's Remove was pressed for — every ticked credential, not one row's button. A
  // partial failure keeps the confirm open on just the credentials still registered; the re-read
  // runs either way, so the table never keeps showing one that is gone.
  const remove = useBulkRemove<WebauthnCredential>({
    getId: (c) => c.id,
    remove: removeWebauthn,
    onSettled: invalidate,
    onDone: () => list.clearSelection(),
    errorMessage: (err) => extractErrorMessage(err, "Could not remove. Try again."),
  });

  const columns: EditableListColumn<WebauthnCredential>[] = useMemo(
    () => [
      {
        key: "name",
        header: "Name",
        value: credentialName,
        render: (cred) => (
          <span className="truncate font-medium text-apt-text">{credentialName(cred)}</span>
        ),
      },
      {
        key: "kind",
        header: "Type",
        width: "9rem",
        value: (cred) => KIND_LABEL[cred.kind],
        render: (cred) => <Badge variant="neutral">{KIND_LABEL[cred.kind]}</Badge>,
      },
      {
        key: "createdAt",
        header: "Added",
        width: "8rem",
        searchable: false,
        value: (cred) => cred.createdAt,
        render: (cred) => (
          <span className="text-apt-text-muted">{formatDate(cred.createdAt)}</span>
        ),
      },
      {
        key: "lastUsedAt",
        header: "Last used",
        width: "8rem",
        searchable: false,
        value: (cred) => cred.lastUsedAt ?? "",
        render: (cred) => (
          <span className="text-apt-text-muted">{formatDate(cred.lastUsedAt, "Never")}</span>
        ),
      },
    ],
    [],
  );

  const list = useEditableList<WebauthnCredential>({
    rows: isLoading ? undefined : (data?.items ?? []),
    getRowId: (cred) => cred.id,
    columns,
  });
  const selected = list.selectedRows;

  function openAdd() {
    setName("");
    register.reset();
    setAdding(true);
  }

  function closeAdd() {
    // The browser's registration ceremony is in flight — closing now would orphan its result.
    if (register.isPending) return;
    setAdding(false);
  }

  return (
    <DetailSection title="Passkeys & security keys">
      <SectionNote>
        Sign in with a passkey (Face ID, Touch ID, Windows Hello) or a hardware security key.
      </SectionNote>
      {/* The same table admin's Users page draws, with Add and Remove on the bar. Remove used to
          sit on every row; a verb repeated per row is a second model beside the ticked selection,
          and it could only ever take one credential at a time. */}
      <EditableList
        list={list}
        ariaLabel="Passkeys and security keys"
        loading={isLoading}
        error={error}
        errorTitle="Couldn't load passkeys"
        columnWidthsKey="settings-security-passkeys"
        describeRow={credentialName}
        searchPlaceholder="Name or type"
        emptyLabel="No passkeys or security keys yet. Add one to sign in without a password."
        emptyFilteredLabel="No passkeys match this search."
        actions={
          <ListBarActions
            noun="passkey"
            selectedCount={selected.length}
            onAdd={openAdd}
            onDelete={() => remove.open(selected)}
            deleteLabel="Remove"
          />
        }
      />
      {/* A failed read with nothing to show REPLACES the list, bar and all (EditableList's
          rule: no actions over rows that cannot exist). Add is the one verb that needs no row,
          and registering a device is a separate endpoint from listing them — so a listing outage
          must not also take away the only way to add a second factor. */}
      {error != null && !isLoading && (data?.items ?? []).length === 0 && (
        <div>
          <Button type="button" size="sm" variant="outline" onClick={openAdd}>
            Add passkey or security key
          </Button>
        </div>
      )}

      {/* Add: name the device, then pick which ceremony to run — the kind decides which
          authenticators the browser offers, so it is the submit, not a field. */}
      <Dialog open={adding} onOpenChange={(open) => { if (!open) closeAdd(); }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Add a passkey or security key</DialogTitle>
          </DialogHeader>
          <form
            className="flex flex-col gap-4"
            onSubmit={(e) => {
              e.preventDefault();
              if (!register.isPending) register.mutate("passkey");
            }}
          >
            <Field label="Device name">
              <Input
                id="cred-name"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="MacBook"
                autoFocus
              />
            </Field>
            {register.isError && (
              <ErrorText
                error={extractErrorMessage(register.error, "Registration was cancelled or failed.")}
                className="text-xs"
              />
            )}
            <DialogFooter>
              <Button type="button" variant="ghost" size="sm" onClick={closeAdd} disabled={register.isPending}>
                Cancel
              </Button>
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={() => register.mutate("security_key")}
                disabled={register.isPending}
              >
                Add security key
              </Button>
              <Button type="submit" size="sm" disabled={register.isPending}>
                {register.isPending ? "Waiting for device…" : "Add passkey"}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Remove confirm — for every ticked credential the bar's Remove was pressed with. */}
      <AlertModal
        open={remove.targets != null}
        tone="error"
        title={
          remove.targets && remove.targets.length > 1
            ? `Remove ${remove.targets.length} sign-in methods?`
            : "Remove sign-in method?"
        }
        description={
          remove.targets ? (
            <>
              <span>
                Remove {remove.targets.map(credentialName).join(", ")}? You won’t be able to sign
                in with {remove.targets.length > 1 ? "them" : "it"} any more.
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
    </DetailSection>
  );
}

function RecoverySection({ status }: { status: MfaStatus }): ReactElement {
  const qc = useQueryClient();
  const regen = useMutation({
    mutationFn: regenerateRecoveryCodes,
    onSuccess: () => qc.invalidateQueries({ queryKey: MFA_KEY }),
  });
  // Derive the freshly-generated codes from the mutation result rather than mirroring
  // them into separate state (they reset automatically on the next regenerate).
  const codes = regen.data?.codes ?? null;

  return (
    <FormSection title="Recovery codes">
      <SectionNote>
        One-time codes to sign in if you lose your other factors. {status.recoveryRemaining} unused.
      </SectionNote>
      {codes && (
        <div className="space-y-2 rounded-lg border border-apt-gold/40 bg-apt-gold/10 p-3">
          <p className="text-sm text-apt-text">
            Save these now — they won’t be shown again. Each works once.
          </p>
          <ul className="grid grid-cols-2 gap-1 font-mono text-sm text-apt-text">
            {codes.map((c) => (
              <li key={c}>{c}</li>
            ))}
          </ul>
        </div>
      )}
      <div>
        <Button onClick={() => regen.mutate()} disabled={regen.isPending} variant="outline">
          {status.recoveryRemaining > 0 ? "Regenerate codes" : "Generate codes"}
        </Button>
      </div>
    </FormSection>
  );
}

function PreferredMethodSection({ status }: { status: MfaStatus }): ReactElement {
  const qc = useQueryClient();
  const available: PreferredMethod[] = (["totp", "sms", "webauthn"] as const).filter(
    (m) => status[m],
  );
  const save = useMutation({
    mutationFn: (m: PreferredMethod) => setPreferredMethod(m),
    onSuccess: () => qc.invalidateQueries({ queryKey: MFA_KEY }),
  });
  if (available.length === 0) return <></>;

  const labels: Record<PreferredMethod, string> = {
    totp: "Authenticator app",
    sms: "Text message (SMS)",
    webauthn: "Passkey / security key",
  };
  return (
    <FormSection title="Preferred 2FA method">
      <SectionNote>Which factor we offer first at sign-in.</SectionNote>
      <Select
        aria-label="Preferred 2FA method"
        value={status.preferredMethod ?? ""}
        onChange={(e) => {
          if (e.target.value) save.mutate(e.target.value as PreferredMethod);
        }}
        className="max-w-xs"
      >
        {!status.preferredMethod && <option value="">Choose a method…</option>}
        {available.map((m) => (
          <option key={m} value={m}>
            {labels[m]}
          </option>
        ))}
      </Select>
    </FormSection>
  );
}

/**
 * The Security settings panel. No page title and no API button of its own: the settings registry
 * draws the topic's `FeatureTitle` (title, `/account/mfa` API link, help) above every panel, and a
 * second heading here is what used to make Security read as a different site from its siblings.
 * Form width — the passkeys table has four short columns and fits a form's column comfortably.
 */
export function SecurityWorkspace(): ReactElement {
  const { data, isLoading, isError } = useQuery({ queryKey: MFA_KEY, queryFn: getMfaStatus });

  return (
    <SettingsBody>
      {isLoading && (
        <div className="flex items-center gap-2 text-sm text-apt-text-muted">
          <Spinner /> Loading…
        </div>
      )}
      {isError && (
        <ErrorText error="Couldn’t load your security settings. Reload to try again." />
      )}
      {data && (
        <>
          <FormSection title="Two-factor authentication">
            <SectionNote>
              {data.sms || data.totp || data.webauthn
                ? "Two-factor authentication is on."
                : "Add a second factor to require more than a password at sign-in."}
            </SectionNote>
            <div>
              <StatusRow on={data.totp} label="Authenticator app" />
              <StatusRow on={data.sms} label="Text message (SMS)" />
              <StatusRow on={data.webauthn} label="Passkeys / security keys" />
              <div className="flex items-center gap-2 pt-2 text-xs text-apt-text-dim">
                <Smartphone className="size-3.5" />
                Manage phone numbers on the Notifications page.
              </div>
            </div>
          </FormSection>
          <TotpSection status={data} />
        </>
      )}
      {/* OUTSIDE the `data &&` gate, deliberately: PasskeysSection reads neither `data` nor any
          other MFA-status field — it runs its own ["account","webauthn"] query and manages a
          sign-in method that works with no second factor configured at all. Gated on the MFA
          status, a failing (or merely slow) /account/mfa took the entire passkey surface with
          it, so a user whose MFA status 500s could not add, name, or REMOVE a passkey — the
          one recovery path that does not need a password. It sits between the two gated
          groups so the section order is unchanged whenever the status does load. */}
      <PasskeysSection />
      {data && (
        <>
          {/* Recovery codes are a fallback for a primary factor — only once one exists. */}
          {(data.sms || data.totp || data.webauthn) && <RecoverySection status={data} />}
          <PreferredMethodSection status={data} />
        </>
      )}
    </SettingsBody>
  );
}
