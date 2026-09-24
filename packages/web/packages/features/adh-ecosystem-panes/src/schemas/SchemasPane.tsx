"use client";

import { useCallback, useState } from "react";
import type { ReactNode } from "react";

import { Settings, Table2, Trash2 } from "lucide-react";
import { useResourceList } from "@agentic-toolkit/data";
import { EmptyState } from "@agenticdevelopertoolkit/ui/components/empty-state";
import { Field } from "@agenticdevelopertoolkit/ui/blocks";
import type { TopicLevel } from "@agenticdevelopertoolkit/ui/blocks";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { Textarea } from "@agenticdevelopertoolkit/ui/components/textarea";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { CreateResourceDialog, StackLevels } from "@agentic-toolkit/resource";
import { CRUD_TABLES, CrudDataView } from "@agentic-toolkit/crud";
import { schemasApi } from "@agentic-toolkit/data/markdown";
import { bucketsCacheKey, newSchemaTable, slugifyTableName } from "./schema-model";
import type { SchemaDefinition, SchemaDefinitionInput, SchemaTable } from "./schema-model";
import { ButtonBar } from "@agentic-toolkit/resource";
import { RecordApiButton } from "@agentic-toolkit/api-explorer";
import { useMasterDetailForm } from "@agentic-toolkit/resource";
import { useMasterDetailLevel } from "@agentic-toolkit/resource";
import type { TopicLeaf } from "@agentic-toolkit/resource";
import {
  SchemaDefinitionDetail,
  schemaBlank,
  schemaToInput,
  schemaValidate,
  tableNameValidate,
} from "./SchemaDefinitionDetail";
import { nameForType, TypeOptions } from "./type-options";
import type { RenderTransferSection } from "../transfer-seam";

/** The bucket rail's first row — the bucket's own Settings, above the divider and its tables. */
const SETTINGS = "settings";

// Settings edits the bucket's name and description only; its tables are added and removed one at
// a time from the bucket's rail, each a save of its own. So neither the dirty check nor the save
// looks at `tables` — a save from Settings must never rewrite the table list it did not show.
function schemaDiffers(a: SchemaDefinitionInput, b: SchemaDefinitionInput): boolean {
  return a.name !== b.name || a.description !== b.description;
}

function schemaNormalize(d: SchemaDefinitionInput): SchemaDefinitionInput {
  return {
    name: d.name.trim(),
    description: d.description.trim(),
    tables: d.tables,
  };
}

/** The generic-CRUD table a bucket table's `type` (`content.contacts`) names, if it has one. The
 *  CRUD key is `schema/kebab-table`; a type with no generic-CRUD surface (`content.markdown`,
 *  kept off CRUD by the backend) has none, and says so instead of showing an empty grid. */
function crudMetaForType(type: string) {
  const [schema, table] = type.split(".");
  if (!schema || !table) return undefined;
  return CRUD_TABLES[`${schema}/${table.replace(/_/g, "-")}`];
}

interface NewTableDraft {
  name: string;
  type: string;
}

export function SchemasPane({
  ecosystemId,
  help,
  leaf,
  renderTransfer,
}: {
  ecosystemId?: string;
  /** Unused: the breadcrumb names the pane now (kept for the ScopedPane prop shape). */
  title?: ReactNode;
  help?: ReactNode;
  /** Deep-linkable bucket selection (`…/schemas/<bucketId>`); omit for internal. */
  leaf?: TopicLeaf;
  /** The host's Transfer Ownership section for the open bucket — see
   *  {@link RenderTransferSection}. Omitted ⇒ no transfer is offered. */
  renderTransfer?: RenderTransferSection;
}) {
  // Creating a bucket is a MODAL over the stack, never a blank leaf (HTD recipe
  // `must-create-in-modal`): the `+` opens this, and on save the new bucket is
  // selected so its Settings open.
  const [newOpen, setNewOpen] = useState(false);
  // Adding a table is a modal too — the `+` on the bucket's own rail.
  const [addTableOpen, setAddTableOpen] = useState(false);

  // Cached by ecosystem, so coming back to Buckets paints the rows it already had and revalidates
  // behind them. `useCallback` is load-bearing: the hook treats a NEW fetcher identity as "re-read",
  // so an inline closure here would re-fetch on every render.
  const load = useCallback(() => schemasApi.list(ecosystemId), [ecosystemId]);
  const {
    items: schemas,
    reload: refresh,
    error: loadError,
    isFetching,
  } = useResourceList<SchemaDefinition>(bucketsCacheKey(ecosystemId), load);

  const urlSelection = leaf
    ? { selectedId: leaf.leafId, onSelect: leaf.onSelect }
    : undefined;

  const form = useMasterDetailForm<SchemaDefinition, SchemaDefinitionInput>({
    items: schemas,
    getId: (s) => s.id,
    urlSelection,
    blank: schemaBlank,
    toInput: schemaToInput,
    validate: (draft, others) => schemaValidate(draft, others.map((o) => o.name)),
    differs: schemaDiffers,
    normalize: schemaNormalize,
    create: (input) => schemasApi.create(input, ecosystemId ?? ""),
    // Name and description only — see `schemaDiffers`.
    update: (id, input) =>
      schemasApi.update(id, { name: input.name, description: input.description }),
    // No `remove`: deleting a bucket is the Settings danger zone's type-to-confirm, not a button
    // bar Delete one click away from Save.
    refresh,
    createLabel: "New bucket",
  });

  // PUBLISHED below, together with the open bucket's own rail — see `publish: false`.
  const bucketsLevel = useMasterDetailLevel({
    id: "buckets-list",
    title: "Buckets",
    form,
    items: schemas,
    getId: (s) => s.id,
    getLabel: (s) => s.name,
    itemIcon: <Table2 size={16} aria-hidden />,
    newLabel: "New bucket",
    leaf,
    // A failed read leaves `schemas` null forever, so "Loading…" alone would be a spinner that
    // never resolves in the rail while the error sits in the pane body. Same three-way as the
    // sibling Applications pane.
    emptyLabel: loadError
      ? "Couldn't load buckets."
      : schemas === null
        ? "Loading…"
        : "No buckets yet.",
    // The spinner before "Buckets" — the only thing that says a revalidation is running behind rows
    // the cache already put on screen. `emptyLabel` covers the FIRST read and nothing after.
    busy: isFetching,
    onNew: () => setNewOpen(true),
    publish: false,
  });

  // What the open bucket's rail has selected: its Settings, one of its tables, or nothing (Back).
  // Held WITH the bucket it belongs to, so opening another bucket starts on its Settings instead
  // of carrying a table id that is not one of its tables.
  const bucket = form.selected;
  const [subState, setSubState] = useState<{ bucketId: string; id: string | null } | null>(null);
  const sub = subState && bucket && subState.bucketId === bucket.id ? subState.id : SETTINGS;
  const openTable: SchemaTable | undefined =
    bucket && sub !== SETTINGS ? bucket.tables.find((t) => t.id === sub) : undefined;
  const selectSub = (id: string | null) => bucket && setSubState({ bucketId: bucket.id, id });

  // The bucket's own rail (Mike, 2026-09-24): Settings, a divider, then one row per table, with
  // the `+` in its header adding a table.
  const bucketLevel: TopicLevel | null = bucket
    ? {
        id: "bucket-contents",
        title: bucket.name,
        items: [
          {
            id: SETTINGS,
            label: "Settings",
            icon: <Settings size={16} aria-hidden />,
            dividerAfter: true,
            dividerLabel: "Tables",
          },
          ...bucket.tables.map((t) => ({
            id: t.id,
            label: t.name,
            sublabel: t.type,
            icon: <Table2 size={16} aria-hidden />,
          })),
        ],
        // A table that has just been removed is no longer a row; fall back to Settings.
        selectedId: sub === SETTINGS || openTable ? sub : SETTINGS,
        onSelect: (id) => selectSub(id),
        onClear: () => selectSub(null),
        defaultSelectedId: SETTINGS,
        onNew: () => setAddTableOpen(true),
        newLabel: "Add table",
        itemNoun: "table",
      }
    : null;

  async function removeTable(t: SchemaTable) {
    if (!bucket) return;
    await schemasApi.update(bucket.id, { tables: bucket.tables.filter((x) => x.id !== t.id) });
    selectSub(SETTINGS);
    await refresh();
  }

  const meta = openTable ? crudMetaForType(openTable.type) : undefined;

  return (
    <StackLevels levels={bucketLevel ? [bucketsLevel, bucketLevel] : [bucketsLevel]}>
      <div className="flex min-h-0 min-w-0 flex-1 flex-col">
        <ErrorText error={loadError} className="px-6 pt-4" />
        {bucket && openTable ? (
          // A table: `name: sql-table` over its data rows (Mike, 2026-09-24). A bucket table is a
          // NAME for one of the ecosystem's sql tables, so its rows are that table's rows in the
          // bucket's ecosystem — the rows carry no bucket of their own.
          <>
            <div className="flex items-center gap-2 border-b border-apt-border px-6 py-3">
              <h2 className="min-w-0 flex-1 truncate font-mono text-sm">
                <span className="font-semibold text-apt-text">{openTable.name}</span>
                <span className="text-apt-text-muted">: {openTable.type}</span>
              </h2>
              <Button
                type="button"
                variant="destructive-ghost"
                size="icon"
                onClick={() => void removeTable(openTable)}
                title="Remove table from bucket"
                aria-label={`Remove ${openTable.name} from bucket`}
              >
                <Trash2 />
              </Button>
            </div>
            {meta ? (
              <CrudDataView
                key={`${bucket.id}/${openTable.id}`}
                meta={meta}
                filter={{ ecosystemId: bucket.ecosystemId }}
                createDefaults={{ ecosystemId: bucket.ecosystemId }}
              />
            ) : (
              <EmptyState
                title="These rows can't be browsed here."
                description={`${openTable.type} has no generic data view.`}
              />
            )}
          </>
        ) : (
          <>
            <ButtonBar
              actions={form.actions}
              showCreate={false}
              // Deleting lives in the Settings danger zone below; a bar Delete would only ever be
              // a disabled second button naming the same action.
              showDelete={false}
              trailing={
                <RecordApiButton
                  path="/bucket/buckets/{id}"
                  pathValues={{ id: form.selectedId }}
                  title="Bucket API"
                />
              }
              help={help}
            />
            <div className="flex min-h-0 min-w-0 flex-1 flex-col overflow-y-auto px-6 py-4">
              {form.editing && form.draft ? (
                <div className="flex flex-col gap-6" key={form.detailKey}>
                  <SchemaDefinitionDetail
                    title="Settings"
                    draft={form.draft}
                    onChange={form.onChange}
                    error={form.error}
                    schema={bucket}
                    ecosystemRdid={ecosystemId}
                    renderTransfer={renderTransfer}
                    onDelete={
                      bucket?.kind === "custom"
                        ? async () => {
                            await schemasApi.delete(bucket.id);
                            if (leaf) leaf.onSelect(null);
                            else form.actions.onCancel();
                            await refresh();
                          }
                        : undefined
                    }
                  />
                </div>
              ) : (
                <EmptyState
                  title={
                    schemas === null ? "Loading…" : "Select a bucket to edit, or create a new one."
                  }
                />
              )}
            </div>
          </>
        )}

        {/* Create is a scoped modal: name + description only (tables are added from the new
            bucket's own rail, which opens once the created bucket is selected). */}
        {newOpen && (
          <CreateResourceDialog<SchemaDefinitionInput, SchemaDefinition>
            ariaLabel="New bucket"
            heading="New bucket"
            blank={schemaBlank}
            validate={(d) => schemaValidate(d, (schemas ?? []).map((s) => s.name))}
            create={(d) => schemasApi.create(schemaNormalize(d), ecosystemId ?? "")}
            onClose={() => setNewOpen(false)}
            onCreated={(created) => {
              setNewOpen(false);
              void refresh();
              if (leaf) leaf.onSelect(created.id);
              else form.select(created.id);
            }}
            renderForm={(draft, onChange, error) => (
              <>
                <Field label="Name" hint="Unique bucket name.">
                  <Input
                    /* eslint-disable-next-line jsx-a11y/no-autofocus -- focus the first field on open */
                    autoFocus
                    value={draft.name}
                    placeholder="Profile Basics"
                    onChange={(e) => onChange({ ...draft, name: e.target.value })}
                  />
                </Field>
                <Field label="Description">
                  <Textarea
                    rows={2}
                    placeholder="What this bucket is for."
                    value={draft.description}
                    onChange={(e) => onChange({ ...draft, description: e.target.value })}
                  />
                </Field>
                <ErrorText error={error} />
              </>
            )}
          />
        )}

        {addTableOpen && bucket && (
          <CreateResourceDialog<NewTableDraft, SchemaDefinition>
            ariaLabel="Add table"
            heading={`Add a table to ${bucket.name}`}
            blank={() => ({ name: "", type: "" })}
            validate={(d) =>
              d.type ? tableNameValidate(d.name, bucket.tables) : "Pick a type (sql-table)."
            }
            create={(d) =>
              schemasApi.update(bucket.id, {
                tables: [...bucket.tables, newSchemaTable(d.type, d.name.trim())],
              })
            }
            onClose={() => setAddTableOpen(false)}
            onCreated={(updated) => {
              setAddTableOpen(false);
              void refresh();
              // Open the table just added — the saved row carries the backend's id for it.
              const added = updated.tables.find(
                (t) => !bucket.tables.some((x) => x.name === t.name),
              );
              if (added) selectSub(added.id);
            }}
            renderForm={(draft, onChange, error) => (
              <>
                <Field label="Type (sql-table)">
                  <Select
                    aria-label="Type (sql-table)"
                    value={draft.type}
                    onChange={(e) => {
                      const type = e.target.value;
                      // Pre-fill the name from the type until the user has typed one of their own.
                      const autoName = !draft.name || draft.name === nameForType(draft.type);
                      onChange({ type, name: autoName ? nameForType(type) : draft.name });
                    }}
                  >
                    <option value="">Choose a type…</option>
                    <TypeOptions />
                  </Select>
                </Field>
                <Field label="Name" hint="Unique in this bucket; lowercase, no spaces.">
                  <Input
                    value={draft.name}
                    placeholder="contacts"
                    onChange={(e) => onChange({ ...draft, name: slugifyTableName(e.target.value) })}
                  />
                </Field>
                <ErrorText error={error} />
              </>
            )}
          />
        )}
      </div>
    </StackLevels>
  );
}
