"use client";

import { useCallback, useMemo, useRef, useState } from "react";
import type { ReactNode } from "react";

import { KeyRound } from "lucide-react";
import { useResourceList } from "@agentic-toolkit/data";
import { EmptyState } from "@agenticdevelopertoolkit/ui/components/empty-state";
import { bucketAccessApi, type AccessGroup } from "@agentic-toolkit/data/security";
import { schemasApi, type SchemaDefinition } from "@agentic-toolkit/data/markdown";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { Field, TopicSelectHint } from "@agenticdevelopertoolkit/ui/blocks";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { Textarea } from "@agenticdevelopertoolkit/ui/components/textarea";
import {
  ButtonBar,
  CreateResourceDialog,
  useMasterDetailForm,
  useMasterDetailLevel,
  type TopicLeaf,
} from "@agentic-toolkit/resource";
import { AccessGroupDetail } from "./AccessGroupDetail";
import {
  isEveryone,
  type AccessGroupInput,
  type AccessItem,
  type BucketRef,
  type Principal,
} from "./access-model";

/** The minimal user shape AccessPane reads from the host's user directory (id +
 *  enough to label a member row: a display name, falling back to email). */
export interface AccessDirectoryUser {
  id: string;
  displayName: string;
  email: string;
}

/** The minimal application shape AccessPane reads from the host's application directory. */
export interface AccessDirectoryApp {
  id: string;
  name: string;
}

function sortItems(items: AccessItem[]): AccessItem[] {
  // Group by bucket name, the seeded "everyone" first within each bucket, then by name.
  return [...items].sort(
    (a, b) =>
      a.bucketName.localeCompare(b.bucketName) ||
      Number(isEveryone(b.group)) - Number(isEveryone(a.group)) ||
      a.group.name.localeCompare(b.group.name),
  );
}

/**
 * The Ecosystems "Access" topic: every access list in the ecosystem (across all
 * buckets) in one place, each badged with its bucket. Decoupled from the bucket
 * editor — this is the single home for managing who can access what. Built on the
 * shared MasterDetailLayout + useMasterDetailForm, like the sibling Buckets/Users
 * panes.
 */
export function AccessPane({
  ecosystemId,
  help,
  leaf,
  usersDirectory,
  applicationsDirectory,
}: {
  ecosystemId?: string;
  /** Unused: the breadcrumb names the pane now (kept for the ScopedPane prop shape). */
  title?: ReactNode;
  help?: ReactNode;
  /** Deep-linkable access-list selection (`…/access/<groupId>`); omit for internal. */
  leaf?: TopicLeaf;
  /** The host's user directory (list users scoped to an ecosystem) — the user registry stays
   *  host-owned; this feature only needs id + a display label to populate the member picker. */
  usersDirectory: (ecosystemId: string | undefined) => Promise<AccessDirectoryUser[]>;
  /** The host's application directory (list applications scoped to an ecosystem) — the
   *  application registry stays host-owned; injected for the same reason as usersDirectory. */
  applicationsDirectory: (ecosystemId: string | undefined) => Promise<AccessDirectoryApp[]>;
}) {
  // Creating an access list is a MODAL over the stack, never a blank leaf (HTD recipe
  // `must-create-in-modal`): the `+` opens it, and on save the new list is selected so
  // its REAL detail (members + grants) opens.
  const [newOpen, setNewOpen] = useState(false);

  // FOUR reads, each cached on its own, replacing the two hand-rolled loaders and the two
  // latest-wins generation counters they needed. A reply for an ecosystem the user has left is a
  // different cache entry rather than something a counter has to reject, and the cache survives
  // the unmount the counters never did.
  //
  // The buckets are read under the SAME cache key the Buckets pane uses, so the two panes share
  // one fetch: opening Access after Buckets paints its list instantly and revalidates behind it.
  // `useCallback` is load-bearing — the hook treats a NEW fetcher identity as "re-read".
  const loadDefs = useCallback(() => schemasApi.list(ecosystemId), [ecosystemId]);
  const {
    items: defs,
    reload: reloadDefs,
    error: defsError,
    isFetching: defsFetching,
  } = useResourceList<SchemaDefinition>(`ecosystem:${ecosystemId ?? ""}:buckets`, loadDefs);

  // Every access group the caller can see, in ONE call rather than a fan-out per bucket — and
  // across every ecosystem, so it is cached WITHOUT a scope segment. The ecosystem filter is the
  // join below.
  const {
    items: allGroups,
    reload: reloadGroups,
    error: groupsError,
    isFetching: groupsFetching,
  } = useResourceList<AccessGroup>("bucket:access-groups", bucketAccessApi.listAllGroups);

  const buckets = useMemo<BucketRef[]>(
    () =>
      (defs ?? []).map((d) => ({
        id: d.id,
        name: d.name,
        types: d.tables.map((t) => ({ id: t.id, name: t.name })),
      })),
    [defs],
  );

  // Joined client-side by bucketId; a group whose bucket isn't in this ecosystem's set is dropped
  // (the bucket filter IS the ecosystem filter, since a group inherits its bucket's owner). Null
  // until BOTH reads have landed: a join against half the data is a SHORTER list, not a visibly
  // partial one, so the rail would read it as "no access lists yet".
  const items = useMemo<AccessItem[] | null>(() => {
    if (defs === null || allGroups === null) return null;
    const nameByBucket = new Map(buckets.map((b) => [b.id, b.name]));
    return sortItems(
      allGroups
        .filter((group) => nameByBucket.has(group.bucketId))
        .map((group) => ({ group, bucketName: nameByBucket.get(group.bucketId) as string })),
    );
  }, [defs, allGroups, buckets]);

  const loadError = defsError ?? groupsError;

  // A create/update/delete re-reads both halves of the join — the groups because they changed,
  // the buckets because a name shown on every row comes from there.
  //
  // Swallowing, and it has to: every caller re-reads AFTER its own write succeeded, so a failed
  // re-read is neither a failed save nor a failed delete, and one of those callers is a fire-and-
  // forget `void refresh()` in the create dialog below, where a rejection is an unhandled promise
  // rejection and nothing more. The failure still reaches the screen as `loadError`, which is the
  // banner the two list hooks above already feed.
  const refresh = useCallback(async () => {
    await Promise.all([reloadDefs(), reloadGroups()]).catch(() => {});
  }, [reloadDefs, reloadGroups]);

  // The host's directories, held in a ref so each FETCHER's identity depends on the ecosystem
  // alone. A host that rebuilt these closures per render would otherwise re-read on every render
  // — the hazard the old `principalsGen` counter existed to survive rather than to avoid. A
  // fresh closure is not new data, so pinning the identity here is the whole fix.
  const directories = useRef({ usersDirectory, applicationsDirectory });
  directories.current = { usersDirectory, applicationsDirectory };

  const loadUsers = useCallback(
    async (): Promise<Principal[]> =>
      (await directories.current.usersDirectory(ecosystemId)).map((u) => ({
        id: u.id,
        label: u.displayName || u.email,
      })),
    [ecosystemId],
  );
  const { items: principalUsers } = useResourceList<Principal>(
    `ecosystem:${ecosystemId ?? ""}:access-principal-users`,
    loadUsers,
  );

  const loadApps = useCallback(
    async (): Promise<Principal[]> =>
      (await directories.current.applicationsDirectory(ecosystemId)).map((a) => ({
        id: a.id,
        label: a.name,
      })),
    [ecosystemId],
  );
  const { items: principalApps } = useResourceList<Principal>(
    `ecosystem:${ecosystemId ?? ""}:access-principal-apps`,
    loadApps,
  );

  // Deliberately NOT folded into `loadError`: a directory that won't load leaves an empty member
  // PICKER, and members can still be added by raw id. Nothing about the access lists failed.
  const principals = useMemo(
    () => ({ users: principalUsers ?? [], apps: principalApps ?? [] }),
    [principalUsers, principalApps],
  );

  const bucketNameFor = (id: string) => buckets.find((b) => b.id === id)?.name ?? "—";

  const urlSelection = leaf
    ? { selectedId: leaf.leafId, onSelect: leaf.onSelect }
    : undefined;

  // The access-list draft's placement rules — bucket + name + description — extracted so the
  // form (edit) and the create MODAL share one source of truth (validation, trimming, the
  // create call). Members and grants are NOT placement; they live in the detail that opens once
  // the created list is selected.
  const groupBlank = (): AccessGroupInput => ({ bucketId: "", name: "", description: "" });
  const groupValidate = (draft: AccessGroupInput, others: AccessItem[]): string | null => {
    if (!draft.bucketId) return "Choose a bucket.";
    if (!draft.name.trim()) return "Name is required.";
    const dup = others.some(
      (o) =>
        o.group.bucketId === draft.bucketId &&
        o.group.name.toLowerCase() === draft.name.trim().toLowerCase(),
    );
    if (dup) return `An access list named "${draft.name.trim()}" already exists in that bucket.`;
    return null;
  };
  const groupNormalize = (d: AccessGroupInput): AccessGroupInput => ({
    bucketId: d.bucketId,
    name: d.name.trim(),
    description: d.description.trim(),
  });
  const createGroupItem = async (input: AccessGroupInput): Promise<AccessItem> => {
    const group = await bucketAccessApi.createGroup(input.bucketId, {
      name: input.name,
      description: input.description,
    });
    return { group, bucketName: bucketNameFor(input.bucketId) };
  };

  const form = useMasterDetailForm<AccessItem, AccessGroupInput>({
    items,
    getId: (i) => i.group.id,
    urlSelection,
    blank: groupBlank,
    toInput: (i) => ({
      bucketId: i.group.bucketId,
      name: i.group.name,
      description: i.group.description,
    }),
    validate: groupValidate,
    differs: (a, b) =>
      a.bucketId !== b.bucketId ||
      a.name.trim() !== b.name.trim() ||
      a.description.trim() !== b.description.trim(),
    normalize: groupNormalize,
    create: createGroupItem,
    update: async (id, input) => {
      const group = await bucketAccessApi.updateGroup(id, {
        name: input.name,
        description: input.description,
      });
      return { group, bucketName: bucketNameFor(group.bucketId) };
    },
    // The seeded "everyone" list is built in — reject its deletion with a clear message.
    remove: (item) =>
      isEveryone(item.group)
        ? Promise.reject(new Error("The “everyone” list is built in and can’t be deleted."))
        : bucketAccessApi.deleteGroup(item.group.id),
    confirmDelete: (item) =>
      `Delete access list "${item.group.name}"? Its members and grants will be removed.`,
    refresh,
    createLabel: "New access list",
  });

  // PUBLISH the access lists as a deeper stack level + register the editor's unsaved-work guard.
  useMasterDetailLevel({
    id: "access-list",
    title: "Access lists",
    form,
    items,
    getId: (i) => i.group.id,
    getLabel: (i) => (isEveryone(i.group) ? "Everyone" : i.group.name),
    getSublabel: (i) => i.bucketName,
    itemIcon: <KeyRound size={16} aria-hidden />,
    newLabel: "New access list",
    leaf,
    // `loadError` FIRST: a failed read leaves `items` null, which on its own would sit on
    // "Loading…" forever with only the banner saying otherwise.
    emptyLabel: loadError
      ? "Couldn't load access lists."
      : items === null
        ? "Loading…"
        : "No access lists yet.",
    // The spinner before "Access lists" — the only thing that says a revalidation is running
    // behind rows the cache already put on screen. `emptyLabel` covers the FIRST read and
    // nothing after.
    busy: defsFetching || groupsFetching,
    onNew: () => setNewOpen(true),
  });

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <ErrorText error={loadError} className="px-6 pt-4" />
      <ButtonBar
        actions={form.actions}
        showCreate={false}
        api={{
          path: "/bucket/access-groups/{groupId}",
          pathValues: { groupId: form.selectedId },
          title: "Access group API",
        }}
        help={help}
      />
      <div className="flex min-h-0 min-w-0 flex-1 flex-col overflow-y-auto px-6 py-4">
        {form.editing && form.draft ? (
          <AccessGroupDetail
            key={form.detailKey}
            title="Access list"
            draft={form.draft}
            onChange={form.onChange}
            error={form.error}
            creating={form.creating}
            group={form.selected}
            buckets={buckets}
            principals={principals}
          />
        ) : loadError ? (
          <EmptyState title="Couldn't load access lists." />
        ) : items === null ? (
          <EmptyState title="Loading…" />
        ) : (
          <TopicSelectHint title="Select an access list to edit, or create a new one." />
        )}
      </div>

      {/* Create is a scoped modal: bucket + name + description only (members and grants live
          in the list's real detail, which opens once the created list is selected). */}
      {newOpen && (
        <CreateResourceDialog<AccessGroupInput, AccessItem>
          ariaLabel="New access list"
          heading="New access list"
          blank={groupBlank}
          validate={(d) => groupValidate(d, items ?? [])}
          create={(d) => createGroupItem(groupNormalize(d))}
          onClose={() => setNewOpen(false)}
          onCreated={(item) => {
            setNewOpen(false);
            void refresh();
            if (leaf) leaf.onSelect(item.group.id);
            else form.select(item.group.id);
          }}
          renderForm={(draft, onChange, error) => (
            <>
              <Field label="Bucket" hint="The bucket this access list controls.">
                <Select
                  value={draft.bucketId}
                  onChange={(e) => onChange({ ...draft, bucketId: e.target.value })}
                >
                  <option value="">Select a bucket…</option>
                  {buckets.map((b) => (
                    <option key={b.id} value={b.id}>
                      {b.name}
                    </option>
                  ))}
                </Select>
              </Field>
              <Field label="Name" hint="Unique within the bucket.">
                <Input
                  /* eslint-disable-next-line jsx-a11y/no-autofocus -- focus the first text field on open */
                  autoFocus
                  value={draft.name}
                  placeholder="Editors"
                  onChange={(e) => onChange({ ...draft, name: e.target.value })}
                />
              </Field>
              <Field label="Description">
                <Textarea
                  rows={2}
                  value={draft.description}
                  placeholder="What this access list is for."
                  onChange={(e) => onChange({ ...draft, description: e.target.value })}
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
