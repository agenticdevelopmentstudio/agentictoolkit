"use client";

import { useCallback, useState } from "react";
import type { ReactNode } from "react";
import { Code, UserCog, UsersRound } from "lucide-react";

import {
  applicationsPrototypeApi,
  type ApplicationInput,
  type ApplicationKind,
  type PrototypeApplication,
} from "../api/applications-prototype";
import { useResourceList } from "@agentic-toolkit/data";
import { EmptyState } from "@agenticdevelopertoolkit/ui/components/empty-state";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { CreateResourceDialog } from "@agentic-toolkit/resource";
import { ButtonBar } from "@agentic-toolkit/resource";
import { RecordApiButton } from "@agentic-toolkit/api-explorer";
import { useMasterDetailForm } from "@agentic-toolkit/resource";
import { useMasterDetailLevel } from "@agentic-toolkit/resource";
import type { TopicLeaf } from "@agentic-toolkit/resource";
import {
  ApplicationDetail,
  ApplicationPlacementFields,
  appBlank,
  appToInput,
  appValidate,
} from "./ApplicationDetail";
import { CRUD_KEYS, type Crud, type SchemaGrant } from "./permission-model";
import type { RenderTransferSection } from "../transfer-seam";

/** Whether two grant lists hold the same grants, whatever order the list and its objects' keys
 *  are in. Order-blind because plain `JSON.stringify` was key-order sensitive: a `tables` map
 *  loaded from the server and the same map rebuilt by an edit-and-undo serialised differently,
 *  so Save lit up with nothing changed.
 *
 *  Compared field by field, copying nothing and stopping at the first difference, because this
 *  runs on EVERY render — `dirty` calls `appDiffers` — and the key-sorted canonical JSON it
 *  replaced (both lists copied and `localeCompare`-sorted, then a sorted copy of every object in
 *  them) cost 7-16x the plain stringify before it: 13.6ms a render at 50 grants of 100 tables.
 *  An unedited draft costs nothing at all: `appToInput` hands the draft its base's array, and
 *  the two stay the same array until an edit replaces it.
 *
 *  Grants are one per schema — `addGrant` refuses a second, and the backend returns one per
 *  bucket — so `schemaId` pairs them. The partner is looked for at the same index first, which
 *  is where an edit leaves it (`updateGrant` maps in place), and searched for only when the order
 *  differs: a scan that is quadratic in the number of grants, a handful, where a Map to look it
 *  up in would be an allocation on every render. The loops are index loops for the same reason:
 *  `find`, `every` and `for...of` each allocate a closure or an iterator per call. */
function sameGrants(a: readonly SchemaGrant[], b: readonly SchemaGrant[]): boolean {
  if (a === b) return true;
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    const grant = a[i]!;
    const sameIndex = b[i]!;
    const partner =
      sameIndex.schemaId === grant.schemaId ? sameIndex : findGrant(b, grant.schemaId);
    if (!partner || !sameGrant(grant, partner)) return false;
  }
  return true;
}

function findGrant(grants: readonly SchemaGrant[], schemaId: string): SchemaGrant | undefined {
  for (let i = 0; i < grants.length; i++) {
    if (grants[i]!.schemaId === schemaId) return grants[i];
  }
  return undefined;
}

function sameGrant(a: SchemaGrant, b: SchemaGrant): boolean {
  return a === b || (sameCrud(a.permissions, b.permissions) && sameTables(a.tables, b.tables));
}

/** The same table ids with equal grants: every id of `a` looked up in `b`, then the counts
 *  compared, so insertion order — what `JSON.stringify` saw — plays no part. `Object.hasOwn`
 *  rather than `in`, which would find a table named `constructor` on every object. */
function sameTables(a: SchemaGrant["tables"], b: SchemaGrant["tables"]): boolean {
  if (a === b) return true;
  let unmatched = 0;
  for (const id in a) {
    if (!Object.hasOwn(a, id)) continue;
    if (!Object.hasOwn(b, id)) return false;
    const x = a[id];
    const y = b[id];
    if (x !== y && (!x || !y || x.level !== y.level || !sameCrud(x.permissions, y.permissions))) {
      return false;
    }
    unmatched++;
  }
  for (const id in b) {
    if (Object.hasOwn(b, id)) unmatched--;
  }
  return unmatched === 0;
}

/** `CRUD_KEYS`, not the four names spelled out, so a capability added to `Crud` is compared too. */
function sameCrud(a: Crud, b: Crud): boolean {
  if (a === b) return true;
  for (let i = 0; i < CRUD_KEYS.length; i++) {
    const key = CRUD_KEYS[i]!;
    if (a[key] !== b[key]) return false;
  }
  return true;
}

export function appDiffers(a: ApplicationInput, b: ApplicationInput): boolean {
  return (
    a.identifier.trim() !== b.identifier.trim() ||
    a.name.trim() !== b.name.trim() ||
    a.kind !== b.kind ||
    !sameGrants(a.schemaGrants, b.schemaGrants)
  );
}

function appNormalize(d: ApplicationInput): ApplicationInput {
  return {
    identifier: d.identifier.trim(),
    name: d.name.trim(),
    kind: d.kind,
    schemaGrants: d.schemaGrants,
  };
}

export function ApplicationsPane({
  ecosystemId,
  help,
  leaf,
  renderTransfer,
}: {
  ecosystemId?: string;
  /** Unused: the breadcrumb names the pane now (kept for the ScopedPane prop shape). */
  title?: ReactNode;
  help?: ReactNode;
  /** Deep-linkable application selection (`…/applications/<appId>`); omit for internal. */
  leaf?: TopicLeaf;
  /** The host's Transfer Ownership section for the open application — see
   *  {@link RenderTransferSection}. Omitted ⇒ no transfer is offered. */
  renderTransfer?: RenderTransferSection;
}) {
  // Creating an application is a MODAL over the stack, never a blank leaf (HTD recipe
  // `must-create-in-modal`): the `+` opens it, and on save the new app is selected so its
  // REAL detail (schema grants, access tokens) opens.
  const [newOpen, setNewOpen] = useState(false);

  // The fixed `app.<ecosystem>.` prefix for NEW app ids — the type + ecosystem scope are
  // inherited and not the user's to edit (only the leaf is). The ecosystem id IS its rdid
  // (`ecosystem.<slug>`); if that's not resolvable, fall back to a free identifier field.
  const scopePrefix = ecosystemId?.startsWith("ecosystem.")
    ? `app.${ecosystemId.slice("ecosystem.".length)}.`
    : "";

  // Cached by ecosystem, so coming back to Applications paints the rows it already had and
  // revalidates behind them. `useCallback` is load-bearing: the hook treats a NEW fetcher identity
  // as "re-read", so an inline closure here would re-fetch on every render.
  //
  // A failed read leaves `apps` null, which on its own would sit on "Loading…" forever and hide the
  // failure. What prevents that is the labels below reading `loadError` FIRST — the old empty-array
  // substitution is no longer what flips the pane out of the loading state.
  const load = useCallback(() => applicationsPrototypeApi.list(ecosystemId), [ecosystemId]);
  const {
    items: apps,
    reload: refresh,
    error: loadError,
    isFetching,
  } = useResourceList<PrototypeApplication>(`ecosystem:${ecosystemId ?? ""}:applications`, load);

  // URL-driven selection (the apps list is now a published stack LEVEL; the row id lives in the
  // URL leaf segment). The hook routes selection changes through `leaf.onSelect`.
  const urlSelection = leaf
    ? { selectedId: leaf.leafId, onSelect: leaf.onSelect }
    : undefined;

  const form = useMasterDetailForm<PrototypeApplication, ApplicationInput>({
    items: apps,
    getId: (a) => a.id,
    urlSelection,
    blank: appBlank,
    toInput: appToInput,
    validate: (draft, others) => appValidate(draft, others.map((o) => o.identifier)),
    differs: appDiffers,
    normalize: appNormalize,
    create: (input) => applicationsPrototypeApi.create(input, ecosystemId ?? ""),
    update: (id, input) => applicationsPrototypeApi.update(id, input),
    remove: (a) => applicationsPrototypeApi.delete(a.id),
    confirmDelete: (a) => `Delete application "${a.name}"? This cannot be undone.`,
    refresh,
    createLabel: "New application",
  });

  // Per-row icon = the application's kind (who consumes it): staff tooling, a developer
  // integration, or a customer-facing app — the one discrete fact each row carries.
  const KIND_ICONS: Record<ApplicationKind, ReactNode> = {
    staff: <UserCog />,
    developer: <Code />,
    customer: <UsersRound />,
  };

  // PUBLISH the apps list as a deeper stack level + register the editor's unsaved-work guard.
  useMasterDetailLevel({
    id: "applications-list",
    title: "Applications",
    form,
    items: apps,
    getId: (a) => a.id,
    getLabel: (a) => a.name,
    getSublabel: (a) => a.identifier,
    getItemIcon: (a) => KIND_ICONS[a.kind],
    newLabel: "New application",
    leaf,
    emptyLabel: loadError
      ? "Couldn't load applications."
      : apps === null
        ? "Loading…"
        : "No applications yet.",
    // The spinner before "Applications" — the only thing that says a revalidation is running behind
    // rows the cache already put on screen. `emptyLabel` covers the FIRST read and nothing after.
    busy: isFetching,
    onNew: () => setNewOpen(true),
  });

  // The pane is now ONLY the leaf detail: the editor's button bar + the form, or the placeholder.
  // No `title` on the bar — the full-width breadcrumb (… ▸ Applications ▸ <app>) already names the
  // pane, so a centered title here would just duplicate it (and crowd the Delete / Save buttons).
  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <ErrorText error={loadError} className="px-6 pt-4" />
      <ButtonBar
        actions={form.actions}
        showCreate={false}
        trailing={
          <RecordApiButton
            path="/ecosystem/applications/{id}"
            pathValues={{ id: form.selectedId }}
            title="Application API"
          />
        }
        help={help}
      />
      <div className="flex min-h-0 min-w-0 flex-1 flex-col overflow-y-auto px-6 py-4">
        {form.editing && form.draft ? (
          <ApplicationDetail
            key={form.detailKey}
            title="Application"
            draft={form.draft}
            onChange={form.onChange}
            error={form.error}
            app={form.selected}
            scopePrefix={scopePrefix}
            ecosystemRdid={ecosystemId}
            renderTransfer={renderTransfer}
          />
        ) : (
          <EmptyState
            title={
              loadError
                ? "Couldn't load applications."
                : apps === null
                  ? "Loading…"
                  : "Select an application to edit, or create a new one."
            }
          />
        )}
      </div>

      {/* Create is a scoped modal: name + id + kind only (schema grants and access tokens
          live in the app's real detail, which opens once the created app is selected). */}
      {newOpen && (
        <CreateResourceDialog<ApplicationInput, PrototypeApplication>
          ariaLabel="New application"
          heading="New application"
          blank={appBlank}
          validate={(d) => appValidate(d, (apps ?? []).map((a) => a.identifier))}
          create={(d) => applicationsPrototypeApi.create(appNormalize(d), ecosystemId ?? "")}
          onClose={() => setNewOpen(false)}
          onCreated={(app) => {
            setNewOpen(false);
            void refresh();
            if (leaf) leaf.onSelect(app.id);
            else form.select(app.id);
          }}
          renderForm={(draft, onChange, error) => (
            <>
              <ApplicationPlacementFields
                draft={draft}
                onChange={onChange}
                app={null}
                scopePrefix={scopePrefix}
                autoFocusName
              />
              <ErrorText error={error} />
            </>
          )}
        />
      )}
    </div>
  );
}
