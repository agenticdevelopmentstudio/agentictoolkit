"use client";

import { useCallback, useState } from "react";
import type { ReactNode } from "react";
import { Globe, Smartphone } from "lucide-react";

import {
  applicationsPrototypeApi,
  type ApplicationInput,
  type PrototypeApplication,
} from "../api/applications-prototype";
import { useResourceList } from "@agentic-toolkit/data";
import type { ApplicationPlatform } from "@agentic-toolkit/data/ecosystem-config";
import { ListToolButton } from "@agenticdevelopertoolkit/ui/blocks";
import { EmptyState } from "@agenticdevelopertoolkit/ui/components/empty-state";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import {
  CreateResourceDialog,
  DetailsPane,
  StackLevels,
  type MasterDetailActions,
} from "@agentic-toolkit/resource";
import { ApplicationClientAuthSection, useApplicationClientAuth } from "@agentic-toolkit/ecosystem-config";
import { useMasterDetailForm } from "@agentic-toolkit/resource";
import { useMasterDetailLevel } from "@agentic-toolkit/resource";
import type { TopicLeaf } from "@agentic-toolkit/resource";
import {
  ApplicationDetail,
  ApplicationPlacementFields,
  PLATFORM_NOUNS,
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
    a.platform !== b.platform ||
    !sameGrants(a.schemaGrants, b.schemaGrants)
  );
}

function appNormalize(d: ApplicationInput): ApplicationInput {
  return {
    identifier: d.identifier.trim(),
    name: d.name.trim(),
    platform: d.platform,
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
  // `must-create-in-modal`): the list toolbar's Add Website / Add App opens it for that
  // platform, and on save the new app is selected so its REAL detail opens. Null ⇒ closed.
  const [newPlatform, setNewPlatform] = useState<ApplicationPlatform | null>(null);

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
  const urlSelection = leaf ? { selectedId: leaf.leafId, onSelect: leaf.onSelect } : undefined;

  const form = useMasterDetailForm<PrototypeApplication, ApplicationInput>({
    items: apps,
    getId: (a) => a.id,
    urlSelection,
    blank: appBlank,
    toInput: appToInput,
    validate: (draft, others, base) =>
      appValidate(draft, others.map((o) => o.identifier), base?.identifier),
    differs: appDiffers,
    normalize: appNormalize,
    create: (input) => applicationsPrototypeApi.create(input, ecosystemId ?? ""),
    update: (id, input) => applicationsPrototypeApi.update(id, input),
    // No `remove`: deleting an application is its danger zone's type-to-confirm, not a bar
    // Delete one click from Save.
    refresh,
    createLabel: "New application",
  });

  // Opening an application opens its settings: everything editable about it, its login
  // registration included, in the detail. There is no rail level beneath it to pick them from.
  const openApp = form.editing && !form.creating ? form.selected : null;

  // The login registration's draft, loaded while an application is open. Its edits ride the
  // application's one bar: they light Save and Cancel with the application's own fields.
  const clientAuth = useApplicationClientAuth(openApp?.id ?? null);
  const actions = openApp ? composeActions(form.actions, form.dirty, clientAuth) : form.actions;
  const anyDirty = form.dirty || clientAuth.dirty;

  // Per-row icon = the application's platform, the same glyph as the toolbar creator that makes it.
  const PLATFORM_ICONS: Record<ApplicationPlatform, ReactNode> = {
    web: <Globe />,
    native: <Smartphone />,
  };

  // The apps list, PUBLISHED below through StackLevels — see `publish: false`.
  // Registers the editor's unsaved-work guard either way.
  const appsLevel = useMasterDetailLevel({
    id: "applications-list",
    title: "Applications",
    // The guard covers the client auth section's edits too: leaving with only those unsaved asks.
    form: { ...form, actions, dirty: anyDirty, guard: { isDirty: () => anyDirty } },
    items: apps,
    getId: (a) => a.id,
    getLabel: (a) => a.name,
    getItemIcon: (a) => PLATFORM_ICONS[a.platform],
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
    // One creator per platform instead of the lone `+`, which could not say which kind it makes.
    showNew: false,
    titleActions: (
      <>
        {(["web", "native"] as const).map((platform) => (
          <ListToolButton
            key={platform}
            label={`Add ${PLATFORM_NOUNS[platform]}`}
            aria-haspopup="dialog"
            className="gap-1 px-1 text-xs"
            onClick={() => setNewPlatform(platform)}
          >
            {platform === "web" ? <Globe size={13} aria-hidden /> : <Smartphone size={13} aria-hidden />}
            {`Add ${PLATFORM_NOUNS[platform]}`}
          </ListToolButton>
        ))}
      </>
    ),
    publish: false,
  });

  const levels = [appsLevel];

  // Create is a scoped modal: name + id, for the platform its creator named (schema grants,
  // access tokens and client auth live in the app's real detail, which opens once the created app
  // is selected). Drawn over whichever detail is open.
  const createDialog = newPlatform && (
    <CreateResourceDialog<ApplicationInput, PrototypeApplication>
      key={newPlatform}
      ariaLabel={`New ${PLATFORM_NOUNS[newPlatform]}`}
      heading={`New ${PLATFORM_NOUNS[newPlatform]}`}
      blank={() => appBlank(newPlatform)}
      validate={(d) => appValidate(d, (apps ?? []).map((a) => a.identifier))}
      create={(d) => applicationsPrototypeApi.create(appNormalize(d), ecosystemId ?? "")}
      onClose={() => setNewPlatform(null)}
      onCreated={(app) => {
        setNewPlatform(null);
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
  );

  // The pane is now ONLY the leaf detail: one DetailsPane bar over the form, or the placeholder.
  // No `title` on the bar — the full-width breadcrumb (… ▸ Applications ▸ <app>) already names the
  // pane, so a centered title here would just duplicate it (and crowd the Delete / Save buttons).
  return (
    <StackLevels levels={levels}>
    <DetailsPane
      actions={actions}
      // Creating is the list toolbar's; deleting is the detail's danger zone.
      showCreate={false}
      showDelete={false}
      help={help}
      api={
        form.selectedId
          ? {
              path: "/ecosystem/applications/{id}",
              pathValues: { id: form.selectedId },
              title: "Application API",
            }
          : null
      }
      bodyClassName="px-6 py-4"
    >
      <ErrorText error={loadError} />
      {openApp && form.draft ? (
          // The open application: everything about it, under the one bar.
          <ApplicationDetail
            key={form.detailKey}
            draft={form.draft}
            onChange={form.onChange}
            error={form.error}
            app={form.selected}
            scopePrefix={scopePrefix}
            ecosystemRdid={ecosystemId}
            renderTransfer={renderTransfer}
            clientAuth={<ApplicationClientAuthSection state={clientAuth} />}
            onDelete={async () => {
              const app = form.selected;
              if (!app) return;
              await applicationsPrototypeApi.delete(app.id);
              clientAuth.forget(app.id);
              if (leaf) leaf.onSelect(null);
              else form.actions.onCancel();
              // Not awaited: the delete has succeeded, and a failed re-read of the list must not
              // come back into the confirm dialog as the delete failing.
              void refresh();
            }}
          />
        ) : (
          <EmptyState
            title={
              loadError
                ? "Couldn't load applications."
                : apps === null
                  ? "Loading…"
                  : "Select an application to edit, or add a website or native app."
            }
          />
        )}

      {createDialog}
    </DetailsPane>
    </StackLevels>
  );
}

/** The part of the client auth state the bar needs. */
interface BarSection {
  dirty: boolean;
  canSave: boolean;
  blockedReason: string | null;
  saving: boolean;
  save: () => Promise<boolean>;
  reset: () => void;
}

/**
 * The open application's bar: its form bar with the login registration folded in. Clean
 * registration ⇒ the form's bar unchanged. Dirty ⇒ Save saves the registration, then the form if
 * it too is dirty; Cancel resets the registration without closing the application the way the
 * form's own Cancel does, and cancels the form only when it has edits of its own.
 */
export function composeActions(
  form: MasterDetailActions,
  formDirty: boolean,
  section: BarSection,
): MasterDetailActions {
  if (!section.dirty) return form;
  return {
    ...form,
    canSave: section.canSave && !section.saving && (!formDirty || form.canSave),
    // The form's reason only while the form has edits: a clean form is not what blocks Save.
    blockedReason: (formDirty ? form.blockedReason : null) ?? section.blockedReason,
    saving: form.saving || section.saving,
    canCancel: !section.saving,
    onSave: () => {
      void section.save().then((ok) => {
        if (ok && formDirty) form.onSave();
      });
    },
    onCancel: () => {
      section.reset();
      if (formDirty) form.onCancel();
    },
  };
}
