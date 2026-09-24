"use client";

import { useCallback, useState } from "react";
import type { ReactNode } from "react";

import {
  ecosystemUsersApi,
  type EcosystemUser,
  type EcosystemUserInput,
} from "../api/customers";
import { Users } from "lucide-react";
import { useResourceList } from "@agentic-toolkit/data";
import { Field } from "@agenticdevelopertoolkit/ui/blocks";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { CreateResourceDialog } from "@agentic-toolkit/resource";
import { ButtonBar } from "@agentic-toolkit/resource";
import { RecordApiButton } from "@agentic-toolkit/api-explorer";
import { useMasterDetailForm } from "@agentic-toolkit/resource";
import { useMasterDetailLevel } from "@agentic-toolkit/resource";
import type { TopicLeaf } from "@agentic-toolkit/resource";
import { UserDetail, userBlank, userToInput, userValidate } from "./UserDetail";
import { UsersTable } from "./UsersTable";

function userDiffers(a: EcosystemUserInput, b: EcosystemUserInput): boolean {
  return (Object.keys(a) as (keyof EcosystemUserInput)[]).some(
    (k) => a[k].trim() !== b[k].trim(),
  );
}

function userNormalize(d: EcosystemUserInput): EcosystemUserInput {
  return {
    email: d.email.trim(),
    displayName: d.displayName.trim(),
    externalId: d.externalId.trim(),
    slug: d.slug.trim(),
    avatarUrl: d.avatarUrl.trim(),
  };
}

/** The Users topic for an ecosystem: the end-customers who authenticate to it
 * (`customer.customers`), as a master/detail list scoped to the ecosystem. */
export function UsersPane({
  ecosystemId,
  help,
  leaf,
}: {
  ecosystemId?: string;
  /** Unused: the breadcrumb names the pane now (kept for the ScopedPane prop shape). */
  title?: ReactNode;
  help?: ReactNode;
  /** Deep-linkable user selection (`…/users/<userId>`); omit for internal. */
  leaf?: TopicLeaf;
}) {
  // Creating a user is a MODAL over the stack, never a blank leaf (HTD recipe
  // `must-create-in-modal`): the `+` opens it, and on save the new user is selected
  // so its REAL detail (external id, handle, avatar) opens.
  const [newOpen, setNewOpen] = useState(false);

  // Cached by ecosystem, so coming back to Users paints the rows it already had and revalidates
  // behind them. `useCallback` is load-bearing: the hook treats a NEW fetcher identity as "re-read",
  // so an inline closure here would re-fetch on every render.
  const load = useCallback(() => ecosystemUsersApi.list(ecosystemId), [ecosystemId]);
  const {
    items: users,
    reload: refresh,
    error: loadError,
    isFetching,
  } = useResourceList<EcosystemUser>(`ecosystem:${ecosystemId ?? ""}:users`, load);

  const urlSelection = leaf
    ? { selectedId: leaf.leafId, onSelect: leaf.onSelect }
    : undefined;

  const form = useMasterDetailForm<EcosystemUser, EcosystemUserInput>({
    items: users,
    getId: (u) => u.id,
    urlSelection,
    blank: userBlank,
    toInput: userToInput,
    validate: (draft, others) => userValidate(draft, others.map((o) => o.email)),
    differs: userDiffers,
    normalize: userNormalize,
    create: (input) => ecosystemUsersApi.create(input, ecosystemId ?? ""),
    update: (id, input) => ecosystemUsersApi.update(id, input),
    remove: (u) => ecosystemUsersApi.delete(u.id),
    confirmDelete: (u) =>
      `Delete user "${u.displayName || u.email}"? This cannot be undone.`,
    refresh,
    createLabel: "New user",
  });

  // PUBLISH the users list as a deeper stack level + register the editor's unsaved-work guard.
  useMasterDetailLevel({
    id: "users-list",
    title: "Users",
    form,
    items: users,
    getId: (u) => u.id,
    getLabel: (u) => u.displayName || u.email || "—",
    getSublabel: (u) => u.email || u.externalId || "—",
    itemIcon: <Users size={16} aria-hidden />,
    newLabel: "New user",
    leaf,
    // A failed read leaves `users` null forever, so "Loading…" alone would be a spinner that never
    // resolves in the rail while the error sits in the pane body. Same three-way as the sibling
    // Applications pane.
    emptyLabel: loadError
      ? "Couldn't load users."
      : users === null
        ? "Loading…"
        : "No users yet.",
    // The spinner before "Users" — the only thing that says a revalidation is running behind rows
    // the cache already put on screen. `emptyLabel` covers the FIRST read and nothing after.
    busy: isFetching,
    onNew: () => setNewOpen(true),
  });

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <ButtonBar
        actions={form.actions}
        showCreate={false}
        trailing={
          <RecordApiButton
            path="/customer/customers/{id}"
            pathValues={{ id: form.selectedId }}
            title="User API"
          />
        }
        help={help}
      />
      <div className="flex min-h-0 min-w-0 flex-1 flex-col overflow-y-auto px-6 py-4">
        {form.editing && form.draft ? (
          <UserDetail
            key={form.detailKey}
            title="User"
            draft={form.draft}
            onChange={form.onChange}
            error={form.error}
          />
        ) : (
          // Not an empty state telling you to pick a row from a list that is somewhere else. This
          // is the list — the ecosystem's users, in the same table the admin site shows its own in
          // — so "select a user" is a thing you can do from here rather than an instruction about
          // the rail. It also carries the load failure, which is why the `ErrorText` that used to
          // sit above the bar is gone: `EditableList` replaces the table with the error when there
          // are no rows, and strips it over the rows when a REFETCH fails, and both readings are
          // better than an error line above an empty table saying "No users yet."
          <UsersTable
            users={users}
            error={loadError}
            onOpen={(id) => (leaf ? leaf.onSelect(id) : form.select(id))}
          />
        )}
      </div>

      {/* Create is a scoped modal: email + display name only (external id, handle, and
          avatar live in the user's real detail, which opens once the user is selected). */}
      {newOpen && (
        <CreateResourceDialog<EcosystemUserInput, EcosystemUser>
          ariaLabel="New user"
          heading="New user"
          blank={userBlank}
          validate={(d) => userValidate(d, (users ?? []).map((u) => u.email))}
          create={(d) => ecosystemUsersApi.create(userNormalize(d), ecosystemId ?? "")}
          onClose={() => setNewOpen(false)}
          onCreated={(user) => {
            setNewOpen(false);
            void refresh();
            if (leaf) leaf.onSelect(user.id);
            else form.select(user.id);
          }}
          renderForm={(draft, onChange, error) => (
            <>
              <Field label="Email" hint="The identifier this user signs in to the ecosystem with.">
                <Input
                  /* eslint-disable-next-line jsx-a11y/no-autofocus -- focus the first field on open */
                  autoFocus
                  type="email"
                  value={draft.email}
                  placeholder="person@example.com"
                  onChange={(e) => onChange({ ...draft, email: e.target.value })}
                />
              </Field>
              <Field label="Display name">
                <Input
                  value={draft.displayName}
                  placeholder="Jane Doe"
                  onChange={(e) => onChange({ ...draft, displayName: e.target.value })}
                />
              </Field>
              <Field label="Handle" hint="A short handle for the user — the last part of their address.">
                <Input
                  value={draft.slug}
                  placeholder="jane"
                  onChange={(e) => onChange({ ...draft, slug: e.target.value })}
                />
              </Field>
              <ErrorText error={error} />
            </>
          )}
        />
      )}
    </div>
  );
}
