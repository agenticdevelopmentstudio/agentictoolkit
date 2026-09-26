"use client";

import { useMemo, useState } from "react";
import { Trash2, UserPlus } from "lucide-react";
import {
  useAdminUsers,
  useDeleteUser,
  useGrantRole,
  useHubEcosystemRdid,
  useRevokeRole,
  type AdminUserSummary,
  type RdidMapping,
} from "../api/admin";
import {
  useAddToEcosystem,
  useRemoveFromEcosystem,
  type UserEcosystem,
} from "../api/memberships";
import { authedJson } from "../api/http";
import { Badge } from "@agenticdevelopertoolkit/ui/components/badge";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { OptionMenu } from "@agenticdevelopertoolkit/ui/components/option-menu";
import { RemovableChip } from "@agenticdevelopertoolkit/ui/components/removable-chip";
import { AlertModal } from "@agenticdevelopertoolkit/ui/components/alert-modal";
import { errorMessage } from "@agenticdevelopertoolkit/ui/lib/errors";
import { RdidPicker, type RdidOption } from "@agentic-toolkit/adh-ui/blocks";
import { ProgressModal } from "@agenticdevelopertoolkit/ui/blocks";
import { ApiButton } from "@agentic-toolkit/api-explorer";
import {
  EditableList,
  TypeToConfirmDialog,
  useBatchRun,
  useEditableList,
  type EditableListColumn,
} from "../components/editable-list";
import { ConfirmSourceDialog } from "../users/TransferDialog";
import { transferUser, useTransferPreview } from "../users/transfer";
import { NO_ROLE, roleLabel, roleValues } from "../users/roles";
import { formatDate } from "../lib/timestamps";

/**
 * Users — every customer of the hub ecosystem, and the four things an admin does to a set of them.
 *
 * Everything that acts lives in the BAR, not in the rows: Delete, Transfer and Add to ecosystem
 * all take a selection, and a per-row copy of each would be the same action offered twice with
 * different reach. The two controls that stayed in a row are the two that mean nothing across a
 * selection — the role menu (one user is an admin or is not; "make these nine admins" is not a
 * thing an operator asks for by ticking boxes) and the ecosystem chips (each chip is one
 * membership of one user, and its ✕ removes exactly that one).
 */

const ROLE_ITEMS = [
  { value: "user", label: "User" },
  { value: "admin", label: "Operator" },
];

/** Module-level so the runs below aren't handed a new key on every render. */
const USERS_KEY = ["admin", "users"];

/** The word an operator has to type to delete users. Deliberately not the count and not a name. */
const DELETE_WORD = "delete";

export function UsersPane() {
  const [pickerOpen, setPickerOpen] = useState(false);
  const [target, setTarget] = useState<RdidOption | null>(null);
  const [addPickerOpen, setAddPickerOpen] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);
  /** The one membership chip whose ✕ was pressed, waiting on its confirmation. */
  const [removing, setRemoving] = useState<{ user: AdminUserSummary; eco: UserEcosystem } | null>(
    null,
  );
  const [removeError, setRemoveError] = useState<string | null>(null);
  /** The backend's refusal (409 `last_operator`) to revoke the last operator on the platform. */
  const [roleError, setRoleError] = useState<string | null>(null);

  const { data: users, truncated, isLoading, error } = useAdminUsers();
  const { data: hubRdid } = useHubEcosystemRdid();
  const deleteUser = useDeleteUser();
  const grantRole = useGrantRole();
  const revokeRole = useRevokeRole();
  const addToEcosystem = useAddToEcosystem();
  const removeFromEcosystem = useRemoveFromEcosystem();

  // One runner per action rather than one shared between them: two runs can't be in flight at
  // once, but their progress modals say different things, and a single piece of state would have
  // to carry which run it belonged to anyway.
  const transferRun = useBatchRun({ invalidateKey: USERS_KEY, successMessage: "moved" });
  const deleteRun = useBatchRun({ invalidateKey: USERS_KEY, successMessage: "deleted" });
  const addRun = useBatchRun({ invalidateKey: USERS_KEY, successMessage: "added" });

  const columns: EditableListColumn<AdminUserSummary>[] = useMemo(
    () => [
      {
        key: "name",
        header: "User",
        value: (user) => user.name,
        render: (user) => (
          <span className="flex items-center gap-2">
            <span className="flex size-5 shrink-0 items-center justify-center rounded-full bg-apt-surface-2 text-[10px] font-medium text-apt-text-muted">
              {(user.name || user.email).charAt(0).toUpperCase()}
            </span>
            <span className="truncate font-medium text-apt-text">{user.name || "—"}</span>
          </span>
        ),
      },
      {
        key: "email",
        header: "Email",
        value: (user) => user.email,
        render: (user) => (
          <span className="font-mono text-xs text-apt-text-muted">{user.email}</span>
        ),
      },
      {
        key: "rdid",
        header: "Address",
        value: (user) => user.rdid,
        render: (user) =>
          user.rdid ? (
            <span className="font-mono text-xs text-apt-text-muted">{user.rdid}</span>
          ) : (
            <span className="text-apt-text-dim">—</span>
          ),
      },
      {
        key: "role",
        header: "Role",
        width: "14rem",
        // Sorted and searched by the role NAMES, not by what the cell draws — the cell is a menu
        // and a badge, and neither compares.
        value: roleLabel,
        render: (user) => (
          <span className="flex items-center gap-2">
            <span className="w-24">
              <OptionMenu
                ariaLabel={`Role for ${user.name || user.email}`}
                value={user.capabilities.includes("admin") ? "admin" : "user"}
                items={ROLE_ITEMS}
                onChange={(next) => {
                  const current = user.capabilities.includes("admin") ? "admin" : "user";
                  if (next === current) return;
                  if (next === "admin") grantRole.mutate({ userId: user.id, capability: "admin" });
                  else
                    revokeRole.mutate(
                      { userId: user.id, role: "admin" },
                      { onError: (e) => setRoleError(errorMessage(e)) },
                    );
                }}
              />
            </span>
            {/* Capabilities the two-item menu cannot express. It models admin-or-not, which is the
                grant an operator makes here; a `billing` capability granted elsewhere would
                otherwise be invisible on the one page that claims to show a user's roles. */}
            {user.capabilities
              .filter((cap) => cap !== "admin")
              .map((cap) => (
                <Badge key={cap} variant="accent">
                  {cap}
                </Badge>
              ))}
          </span>
        ),
      },
      {
        key: "ecosystems",
        header: "Ecosystems",
        // Searchable by address, so the free-text box finds a user by an ecosystem they are in as
        // well as by their own name — the same reasoning that folded rdid into the search.
        value: (user) => user.ecosystems.map((e) => e.rdid ?? e.ecosystemId).join(" "),
        render: (user) =>
          user.ecosystems.length === 0 ? (
            <span className="text-apt-text-dim">—</span>
          ) : (
            <span className="flex flex-wrap items-center gap-1">
              {user.ecosystems.map((eco) =>
                // The HUB row is the user's account, not a membership — the backend refuses to
                // delete it, and an ✕ that always answers 400 is worse than no ✕ at all.
                eco.isHub ? (
                  <Badge key={eco.customerId} variant="neutral">
                    {eco.rdid ?? "hub"}
                  </Badge>
                ) : (
                  <RemovableChip
                    key={eco.customerId}
                    variant="accent"
                    removeLabel={`Remove ${user.email || user.name} from ${eco.rdid ?? eco.ecosystemId}`}
                    onRemove={() => {
                      setRemoveError(null);
                      setRemoving({ user, eco });
                    }}
                  >
                    {eco.rdid ?? eco.ecosystemId}
                  </RemovableChip>
                ),
              )}
            </span>
          ),
      },
      {
        key: "joined",
        header: "Joined",
        width: "9rem",
        // Sorted by the RAW timestamp, shown formatted: sorting by "22 Aug 2026" sorts
        // alphabetically by month name.
        value: (user) => user.createdAt,
        render: (user) => (
          <span className="text-xs text-apt-text-dim">{formatDate(user.createdAt)}</span>
        ),
      },
    ],
    [grantRole, revokeRole],
  );

  const list = useEditableList<AdminUserSummary>({
    rows: users,
    getRowId: (user) => user.id,
    columns,
    facets: [
      {
        id: "role",
        label: "Role",
        // Only the roles the list actually contains — a menu offering a role nobody holds is a
        // checkbox whose only outcome is an empty table.
        valuesOf: roleValues,
        labelOf: (value) => (value === NO_ROLE ? "User (no roles)" : value),
      },
    ],
    textFilters: [
      {
        id: "ecosystem",
        placeholder: "Ecosystem",
        valuesOf: (user) => user.ecosystems.map((e) => e.rdid ?? e.ecosystemId),
        width: "16rem",
      },
    ],
  });

  const selected = list.selectedRows;
  const labelOf = (user: AdminUserSummary): string => user.email || user.name || user.id;
  const items = useMemo(
    () => selected.map((user) => ({ id: user.id, label: labelOf(user) })),
    [selected],
  );
  // The preflight runs while the SECOND gate is open — after a destination is chosen, before the
  // operator has typed the source address. That is the last moment the answer can still change
  // what they do, and the only one where nothing has moved yet.
  const preview = useTransferPreview(
    useMemo(() => selected.map((u) => u.id), [selected]),
    target?.entityId ?? null,
    target !== null,
  );

  const searchEcosystems = async (query: string, signal: AbortSignal): Promise<RdidOption[]> => {
    const params = new URLSearchParams({ q: query, entityType: "ecosystem", limit: "20" });
    return authedJson<RdidMapping[]>(`/api/registry/identifiers?${params}`, { signal });
  };

  return (
    <div>
      <div className="mb-6 flex items-center justify-between gap-2">
        <h1 className="text-2xl font-bold text-apt-text">Users</h1>
        <ApiButton endpoint={{ method: "GET", path: "/customer/customers" }} title="Customers API" />
      </div>

      <EditableList
        list={list}
        ariaLabel="Users"
        loading={isLoading}
        error={error}
        errorTitle="Couldn't load users"
        // Every filter on this page runs in the BROWSER, over whatever one request returned. Past
        // the backend's cap that turns a search into a claim the data cannot support: the table
        // empties and reads as "no such user", when the truth is "not in the part I fetched".
        truncationNotice={
          truncated ? (
            <>
              Showing the first {users?.length.toLocaleString()} users — there are more. Filters
              here search only what has been fetched, so{" "}
              <strong>an empty result does not mean the user does not exist</strong>.
            </>
          ) : undefined
        }
        columnWidthsKey="admin-users"
        // The email, not the name: two people called "Alex" would give a screen reader two
        // identical checkboxes, and the email is unique by construction here.
        describeRow={(user) => user.email}
        searchPlaceholder="Name, email or address"
        emptyLabel="No users yet."
        emptyFilteredLabel="No users match these filters."
        actions={
          <>
            <Button
              size="sm"
              variant="ghost"
              disabled={selected.length === 0}
              onClick={() => setAddPickerOpen(true)}
            >
              <UserPlus data-icon="inline-start" />
              Add to ecosystem
            </Button>
            <Button
              size="sm"
              variant="ghost"
              // The unresolved hub address disables Transfer for a concrete reason: the second
              // gate asks the operator to type the address they are moving OUT of, and it has no
              // string to check against until that lookup lands.
              disabled={selected.length === 0 || !hubRdid}
              onClick={() => setPickerOpen(true)}
            >
              Transfer
            </Button>
            <Button
              size="sm"
              variant="destructive-ghost"
              disabled={selected.length === 0}
              onClick={() => {
                setDeleteError(null);
                setConfirmDelete(true);
              }}
            >
              <Trash2 data-icon="inline-start" />
              Delete
            </Button>
          </>
        }
      />

      {/* ── Delete ─────────────────────────────────────────────────────────
          Typed, not clicked, and typed ONCE for the whole selection rather than once per user:
          the word being typed is `delete`, so repeating it per row would test nothing except
          patience. The count in the description is what the operator has to read. */}
      <TypeToConfirmDialog
        open={confirmDelete}
        title={selected.length === 1 ? "Delete this user?" : `Delete ${selected.length} users?`}
        description={
          <>
            Permanently deletes {selected.length === 1 ? labelOf(selected[0]!) : `${selected.length} users`}
            {selected.length === 1 ? "" : " and everything belonging to them"}. This cannot be
            undone.
          </>
        }
        confirmValue={DELETE_WORD}
        valueNoun="word"
        confirmLabel="Delete"
        error={deleteError}
        onCancel={() => setConfirmDelete(false)}
        onConfirm={() => {
          setConfirmDelete(false);
          void deleteRun.run(items, (item) => deleteUser.mutateAsync(item.id));
        }}
      />

      <ProgressModal
        open={deleteRun.state.running || deleteRun.state.finished}
        title="Deleting users"
        description="Each user is deleted on its own; a failure leaves the earlier deletions in place."
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

      {/* ── Add to ecosystem ───────────────────────────────────────────────
          No typed confirmation: this ADDS a membership and takes nothing away, and the ecosystem
          picker is already an explicit choice of what is about to happen. Idempotent at the
          backend, so a selection that already includes members of the target is not an error. */}
      <RdidPicker
        open={addPickerOpen}
        onOpenChange={setAddPickerOpen}
        entityTypeLabel="ecosystem"
        title="Add the selected users to which ecosystem?"
        search={searchEcosystems}
        onPick={(option) => {
          setAddPickerOpen(false);
          void addRun.run(items, (item) =>
            addToEcosystem.mutateAsync({ userId: item.id, ecosystemId: option.entityId }),
          );
        }}
      />

      <ProgressModal
        open={addRun.state.running || addRun.state.finished}
        title="Adding users to the ecosystem"
        description="Someone who is already a member is left as they are."
        total={addRun.state.total}
        done={addRun.state.done}
        currentLabel={addRun.state.currentLabel}
        error={addRun.state.error}
        results={addRun.state.results}
        finished={addRun.state.finished}
        onContinue={addRun.continueRun}
        onStop={addRun.stop}
        onClose={() => addRun.reset()}
      />

      {/* ── Transfer ───────────────────────────────────────────────────────
          Two gates: pick the destination, then type the address being moved out of. */}
      <RdidPicker
        open={pickerOpen}
        onOpenChange={setPickerOpen}
        entityTypeLabel="ecosystem"
        title="Choose the destination ecosystem"
        search={searchEcosystems}
        onPick={(option) => {
          setPickerOpen(false);
          setTarget(option);
        }}
      />

      <ConfirmSourceDialog
        open={target !== null}
        sourceRdid={hubRdid ?? ""}
        targetRdid={target?.rdid ?? ""}
        count={selected.length}
        conflicts={preview.data}
        checking={preview.isFetching}
        labelOf={(id) => {
          const user = selected.find((u) => u.id === id);
          return user ? labelOf(user) : id;
        }}
        onCancel={() => setTarget(null)}
        onConfirm={() => {
          const chosen = target;
          setTarget(null);
          if (!chosen) return;
          void transferRun.run(items, (item) => transferUser(item.id, chosen.entityId));
        }}
      />

      <ProgressModal
        open={transferRun.state.running || transferRun.state.finished}
        title="Moving users"
        description="Each user moves in its own transaction; a failure leaves the earlier moves in place."
        total={transferRun.state.total}
        done={transferRun.state.done}
        currentLabel={transferRun.state.currentLabel}
        error={transferRun.state.error}
        results={transferRun.state.results}
        finished={transferRun.state.finished}
        onContinue={transferRun.continueRun}
        onStop={transferRun.stop}
        onClose={() => {
          transferRun.reset();
          // The moved users are gone from this ecosystem's list, so the selection they were in no
          // longer describes anything.
          list.clearSelection();
        }}
      />

      {/* ── Remove one membership ──────────────────────────────────────────
          A click confirm rather than a typed one, and that is a judgement about reach: this
          removes one person from one ecosystem, and the chip the operator pressed names both.
          Deleting the user — which is unrecoverable and takes their data with it — is the one
          that asks them to type. */}
      <AlertModal
        open={removing !== null}
        tone="error"
        title="Remove from ecosystem?"
        description={
          removing
            ? `${labelOf(removing.user)} will no longer be a customer of ${removing.eco.rdid ?? removing.eco.ecosystemId}. Their hub account and their other ecosystems are unaffected.`
            : undefined
        }
        confirmLabel="Remove"
        confirmVariant="destructive"
        cancelLabel="Cancel"
        busy={removeFromEcosystem.isPending}
        onCancel={() => setRemoving(null)}
        onConfirm={() => {
          if (!removing) return;
          removeFromEcosystem.mutate(removing.eco.customerId, {
            onSuccess: () => setRemoving(null),
            onError: (e) => {
              // Closed either way: the failure alert replaces this dialog rather than stacking on
              // top of it, and the chip is still there to press again.
              setRemoving(null);
              setRemoveError(errorMessage(e));
            },
          });
        }}
      />

      {removeError && (
        <AlertModal
          open
          tone="error"
          title="Couldn't remove the membership"
          description={removeError}
          confirmLabel="OK"
          onConfirm={() => setRemoveError(null)}
        />
      )}

      {roleError && (
        <AlertModal
          open
          tone="error"
          title="Couldn't change the role"
          description={roleError}
          confirmLabel="OK"
          onConfirm={() => setRoleError(null)}
        />
      )}
    </div>
  );
}
