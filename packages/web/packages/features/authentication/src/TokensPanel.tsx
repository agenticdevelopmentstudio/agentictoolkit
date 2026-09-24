"use client";

import type { ReactElement } from "react";
import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@agenticdevelopertoolkit/ui/components/dialog";
import { AlertModal } from "@agenticdevelopertoolkit/ui/components/alert-modal";
import { UnsavedChangesAlert } from "@agenticdevelopertoolkit/ui/components/unsaved-changes-alert";
import { DialogErrorText, ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import {
  EditableList,
  Field,
  useEditableList,
  type EditableListColumn,
} from "@agenticdevelopertoolkit/ui/blocks";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { Checkbox } from "@agenticdevelopertoolkit/ui/components/checkbox";
import { tokensApi, type ApiToken } from "@agentic-toolkit/data/security";
import {
  ListBarActions,
  SettingsBody,
  useBulkRemove,
  useReportBusy,
  useReportSettingsDirty,
} from "@agentic-toolkit/resource";
import { RevealedSecret, whenOr } from "./token-detail";

/**
 * API tokens panel: create (with scope + read-only flag), list, and revoke
 * personal API tokens. Token value is shown once on creation only.
 *
 * The same table admin's Users page draws — one-line rows, every verb on the bar above it. The
 * create form moved into a dialog behind the bar's New, and Revoke acts on the ticked rows through a
 * confirm, rather than one unconfirmed Revoke button per row that fired on a single click.
 */
export function TokensPanel(): ReactElement {
  const qc = useQueryClient();

  // ── UI-only state ──────────────────────────────────────────────────────────
  const [createOpen, setCreateOpen] = useState(false);
  const [name, setName] = useState("");
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [readOnly, setReadOnly] = useState(false);
  // The unsaved-changes alert raised by a close attempt on a half-filled create form.
  const [confirmingClose, setConfirmingClose] = useState(false);
  const [minted, setMinted] = useState<string | null>(null);
  // The "close without copying?" confirm, raised by a dismissal (Escape, backdrop, ×) of the reveal.
  const [confirmingDropSecret, setConfirmingDropSecret] = useState(false);

  // ── Server state ───────────────────────────────────────────────────────────
  const tokensQuery = useQuery({
    queryKey: ["api-tokens"],
    queryFn: tokensApi.list,
  });

  const scopesQuery = useQuery({
    queryKey: ["api-token-scopes"],
    queryFn: tokensApi.scopes,
  });

  const tokens: ApiToken[] = tokensQuery.data ?? [];
  const prefixes: string[] = scopesQuery.data ?? [];

  // This panel is a settings body, not a publisher: the list one component up owns the spinner. The
  // token read in particular has nothing else to say it is running — an unfinished list would be
  // drawn as the empty state, which is a wrong answer rather than a pending one. See `useReportBusy`.
  useReportBusy(tokensQuery.isFetching || scopesQuery.isFetching);

  // ── Mutations ──────────────────────────────────────────────────────────────
  const mintMutation = useMutation({
    mutationFn: tokensApi.mint,
    onSuccess: (created) => {
      // The dialog stays open on success: it is where the one-time reveal is drawn, and closing it
      // on the same tick would take the only copy of the secret with it.
      setMinted(created.token);
      setName("");
      setPicked(new Set());
      setReadOnly(false);
      qc.invalidateQueries({ queryKey: ["api-tokens"] });
    },
  });

  // The rows the bar's Revoke was pressed for — every ticked token, not one row's button. A partial
  // failure keeps the confirm open on just the tokens still live; the re-read runs either way, so
  // the table never keeps showing a revoked token as live.
  const revoke = useBulkRemove<ApiToken>({
    getId: (t) => t.id,
    remove: (id) => tokensApi.revoke(id),
    onSettled: () => void qc.invalidateQueries({ queryKey: ["api-tokens"] }),
    onDone: () => list.clearSelection(),
    errorMessage: (err) => (err instanceof Error ? err.message : "Couldn’t revoke. Please try again."),
  });

  function toggle(prefix: string): void {
    setPicked((prev) => {
      const next = new Set(prev);
      if (next.has(prefix)) next.delete(prefix);
      else next.add(prefix);
      return next;
    });
  }

  function mint(): void {
    const scope = [...picked].map((p) => (readOnly ? `${p}:read` : p));
    mintMutation.mutate({
      name,
      scope: scope.length ? scope : undefined,
    });
  }

  function openCreate(): void {
    // A fresh form every time: a draft abandoned through Discard must not reappear on the next New.
    setName("");
    setPicked(new Set());
    setReadOnly(false);
    setMinted(null);
    mintMutation.reset();
    setCreateOpen(true);
  }

  function closeCreate(): void {
    if (mintMutation.isPending) return;
    setCreateOpen(false);
    // The secret is dropped with the dialog: it was shown once, and a later New must not re-show it.
    setMinted(null);
  }

  // The same close gate every settings dialog has (Social links, Addresses): Escape, a backdrop
  // click, the × and Cancel all ask before throwing a typed name and ticked scopes away. Not once
  // the token is minted — the form is spent by then, and Done must just close.
  const draftDirty =
    createOpen && minted === null && (name.trim() !== "" || picked.size > 0 || readOnly);
  useReportSettingsDirty("settings-api-tokens", draftDirty);

  function requestCloseCreate(): void {
    if (mintMutation.isPending) return;
    // A dismissal of the REVEAL asks first: Escape or a stray backdrop click would otherwise throw
    // away the only copy of a secret the server will never show again. Done is the deliberate
    // close and skips this; it calls `closeCreate` directly.
    if (minted !== null) {
      setConfirmingDropSecret(true);
      return;
    }
    if (draftDirty) {
      setConfirmingClose(true);
      return;
    }
    closeCreate();
  }

  const canMint =
    !mintMutation.isPending &&
    name.trim() !== "" &&
    !scopesQuery.isPending &&
    !scopesQuery.isError;

  // ── Table ──────────────────────────────────────────────────────────────────
  const columns: EditableListColumn<ApiToken>[] = useMemo(
    () => [
      {
        key: "name",
        header: "Name",
        width: "12rem",
        value: (t) => t.name,
        render: (t) => <span className="truncate font-medium text-apt-text">{t.name}</span>,
      },
      {
        key: "prefix",
        header: "Prefix",
        width: "9rem",
        value: (t) => t.prefix,
        render: (t) => (
          <code className="truncate font-mono text-xs text-apt-text-muted">{t.prefix}…</code>
        ),
      },
      {
        key: "scope",
        header: "Scope",
        value: (t) => t.scope?.join(", ") ?? "legacy",
        render: (t) => (
          <span className="truncate font-mono text-xs text-apt-text-muted">
            {t.scope?.join(", ") ?? "legacy"}
          </span>
        ),
      },
      {
        key: "createdAt",
        header: "Created",
        width: "11rem",
        searchable: false,
        value: (t) => t.createdAt,
        render: (t) => <span className="text-apt-text-muted">{whenOr(t.createdAt, "—")}</span>,
      },
      {
        key: "lastUsedAt",
        header: "Last used",
        width: "11rem",
        searchable: false,
        value: (t) => t.lastUsedAt ?? "",
        render: (t) => <span className="text-apt-text-muted">{whenOr(t.lastUsedAt, "Never")}</span>,
      },
      {
        key: "expiresAt",
        header: "Expires",
        width: "11rem",
        searchable: false,
        value: (t) => t.expiresAt ?? "",
        render: (t) => <span className="text-apt-text-muted">{whenOr(t.expiresAt, "Never")}</span>,
      },
    ],
    [],
  );

  const list = useEditableList<ApiToken>({
    rows: tokensQuery.isLoading ? undefined : tokens,
    getRowId: (t) => t.id,
    columns,
  });
  const selected = list.selectedRows;

  // ── Render ─────────────────────────────────────────────────────────────────
  return (
    <>
      <SettingsBody width="full">
        <EditableList
          list={list}
          ariaLabel="API tokens"
          loading={tokensQuery.isLoading}
          error={tokensQuery.error}
          errorTitle="Couldn't load your tokens"
          columnWidthsKey="settings-api-tokens"
          describeRow={(t) => t.name}
          searchPlaceholder="Name, prefix or scope"
          emptyLabel="No tokens yet. Create one to call the API from a script or agent."
          emptyFilteredLabel="No tokens match this search."
          actions={
            <ListBarActions
              noun="token"
              addLabel="New"
              deleteLabel="Revoke"
              selectedCount={selected.length}
              onAdd={openCreate}
              onDelete={() => revoke.open(selected)}
            />
          }
        />
      </SettingsBody>

      {/* Create dialog — also where the one-time secret is revealed after a successful mint. */}
      <Dialog open={createOpen} onOpenChange={(open) => { if (!open) requestCloseCreate(); }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{minted ? "Token created" : "Create an API token"}</DialogTitle>
          </DialogHeader>

          {minted ? (
            <div className="flex flex-col gap-4">
              <RevealedSecret secret={minted} />
              <DialogFooter>
                <Button type="button" size="sm" onClick={closeCreate}>
                  Done
                </Button>
              </DialogFooter>
            </div>
          ) : (
            <form
              className="flex flex-col gap-4"
              onSubmit={(e) => {
                e.preventDefault();
                // Re-checked here, not only at the button: Enter in the name field submits the form
                // without going through the button that carries the gate.
                if (canMint) mint();
              }}
            >
              <Field label="Name">
                <Input
                  id="tok-name"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="e.g. research-agent"
                />
              </Field>

              {scopesQuery.isPending && (
                <p className="text-sm text-apt-text-muted">Loading scopes…</p>
              )}

              {scopesQuery.isError && (
                <div className="flex flex-col items-start gap-2 rounded-md border border-apt-red/50 bg-apt-red/10 p-3 text-sm">
                  <p className="text-apt-red">
                    Couldn’t load the scope catalogue. Token creation is disabled
                    until it loads — otherwise an empty selection would silently mint
                    a broad legacy token instead of the scoped one you intended.
                  </p>
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    onClick={() => scopesQuery.refetch()}
                  >
                    Retry
                  </Button>
                </div>
              )}

              {scopesQuery.isSuccess && prefixes.length > 0 && (
                <div className="flex flex-col gap-2">
                  <Label>Scope (leave empty for legacy curated-only access)</Label>
                  <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                    {prefixes.map((prefix) => (
                      <label
                        key={prefix}
                        className="flex cursor-pointer items-center gap-2 text-sm text-apt-text"
                      >
                        <Checkbox
                          checked={picked.has(prefix)}
                          onCheckedChange={() => toggle(prefix)}
                        />
                        <span className="font-mono">{prefix}</span>
                      </label>
                    ))}
                  </div>
                </div>
              )}

              <label
                htmlFor="api-token-read-only"
                className="flex cursor-pointer items-center gap-2 text-sm text-apt-text"
              >
                <Checkbox
                  id="api-token-read-only"
                  checked={readOnly}
                  onCheckedChange={(v) => setReadOnly(v === true)}
                />
                Read-only (GET/HEAD only)
              </label>

              <ErrorText
                error={
                  mintMutation.isError ? "Couldn’t create the token. Please try again." : null
                }
              />

              <DialogFooter>
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  onClick={requestCloseCreate}
                  disabled={mintMutation.isPending}
                >
                  Cancel
                </Button>
                <Button
                  type="submit"
                  size="sm"
                  disabled={!canMint}
                  className={canMint ? "bg-apt-gold text-apt-bg hover:bg-apt-gold-bright" : ""}
                >
                  {mintMutation.isPending ? "Creating…" : "Create token"}
                </Button>
              </DialogFooter>
            </form>
          )}
          {/* Discard calls `closeCreate()` directly: routing back through the gate would re-test
              `draftDirty` — still true — and re-raise the alert forever. */}
          <UnsavedChangesAlert
            open={confirmingClose}
            onDiscard={() => {
              setConfirmingClose(false);
              closeCreate();
            }}
            onStay={() => setConfirmingClose(false)}
          />
          <AlertModal
            open={confirmingDropSecret}
            tone="error"
            title="Close without copying?"
            description="This token won’t be shown again. If you haven’t copied it, you’ll have to revoke it and create another."
            confirmLabel="Close"
            cancelLabel="Keep open"
            onConfirm={() => {
              setConfirmingDropSecret(false);
              closeCreate();
            }}
            onCancel={() => setConfirmingDropSecret(false)}
          />
        </DialogContent>
      </Dialog>

      {/* Revoke confirm — for every ticked token the bar's Revoke was pressed with. */}
      <AlertModal
        open={revoke.targets != null}
        tone="error"
        title={
          revoke.targets && revoke.targets.length > 1
            ? `Revoke ${revoke.targets.length} tokens?`
            : "Revoke token?"
        }
        description={
          revoke.targets ? (
            <>
              <span>
                {`Revoke ${revoke.targets.map((t) => t.name).join(", ")}? Anything still using ${
                  revoke.targets.length === 1 ? "it" : "them"
                } will stop working immediately.`}
              </span>
              <DialogErrorText error={revoke.error} />
            </>
          ) : undefined
        }
        confirmLabel="Revoke"
        confirmVariant="destructive"
        cancelLabel="Cancel"
        busy={revoke.pending}
        onConfirm={revoke.confirm}
        onCancel={revoke.cancel}
      />
    </>
  );
}
