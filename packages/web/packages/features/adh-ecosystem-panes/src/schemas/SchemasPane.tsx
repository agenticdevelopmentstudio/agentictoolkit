"use client";

import { useCallback, useRef, useState } from "react";
import type { ReactNode } from "react";

import { Settings, Table2, Trash2 } from "lucide-react";
import { useResourceList } from "@agentic-toolkit/data";
import { EmptyState } from "@agenticdevelopertoolkit/ui/components/empty-state";
import { Field } from "@agenticdevelopertoolkit/ui/blocks";
import type { TopicLevel } from "@agenticdevelopertoolkit/ui/blocks";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@agenticdevelopertoolkit/ui/components/dialog";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { Textarea } from "@agenticdevelopertoolkit/ui/components/textarea";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { CreateResourceDialog, StackLevels } from "@agentic-toolkit/resource";
import { CRUD_TABLES, CrudDataView, useExitGuardChannel } from "@agentic-toolkit/crud";
import { UnsavedChangesAlert } from "@agenticdevelopertoolkit/ui/components/unsaved-changes-alert";
import { useExitGate } from "@agenticdevelopertoolkit/ui/hooks/useExitGate";
import { useRailExitGuard } from "@agentic-toolkit/resource";
import { schemasApi } from "@agentic-toolkit/data/markdown";
import { bucketsCacheKey, newSchemaTable, slugifyTableName } from "./schema-model";
import type { SchemaDefinition, SchemaDefinitionInput, SchemaTable } from "./schema-model";
import { ButtonBar } from "@agentic-toolkit/resource";
import { RecordApiButton } from "@agentic-toolkit/api-explorer";
import { useMasterDetailForm } from "@agentic-toolkit/resource";
import { useMasterDetailLevel } from "@agentic-toolkit/resource";
import type { TopicLeaf } from "@agentic-toolkit/resource";
import {
  BucketSlugField,
  bucketSlugPrefix,
  SchemaDefinitionDetail,
  withName,
  schemaBlank,
  schemaToInput,
  schemaValidate,
  tableNameValidate,
} from "./SchemaDefinitionDetail";
import { nameForType, TypeOptions } from "./type-options";
import { isMarkdownType, MarkdownRowsView } from "./MarkdownRowsView";
import type { RenderTransferSection } from "../transfer-seam";

// Settings edits the bucket's name, slug and description only; its tables are added and removed one
// at a time from the bucket's rail, each a save of its own. So neither the dirty check nor the save
// looks at `tables` — a save from Settings must never rewrite the table list it did not show.
function schemaDiffers(a: SchemaDefinitionInput, b: SchemaDefinitionInput): boolean {
  return a.name !== b.name || a.slug !== b.slug || a.description !== b.description;
}

function schemaNormalize(d: SchemaDefinitionInput): SchemaDefinitionInput {
  return {
    name: d.name.trim(),
    slug: d.slug.trim(),
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
  workspaceSlug,
  help,
  leaf,
  renderTransfer,
}: {
  ecosystemId?: string;
  /** The workspace whose documents a markdown-backed table (docs, notes, papers) lists — those
   *  rows are owned by the workspace's principal, not scoped by ecosystem. Undefined lists the
   *  caller's own, the same degrade every `?workspace=` reader makes. */
  workspaceSlug?: string;
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
    validate: (draft, others) => schemaValidate(draft, others),
    differs: schemaDiffers,
    normalize: schemaNormalize,
    create: (input) => schemasApi.create(input, ecosystemId ?? ""),
    // Name, slug and description only — see `schemaDiffers`. A slug edit returns the bucket under
    // its NEW rdid, and the form re-selects by the returned id.
    update: (id, input) =>
      schemasApi.update(id, { name: input.name, slug: input.slug, description: input.description }),
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

  // Which of the open bucket's tables is showing, or none (Back). Held WITH the bucket it belongs
  // to, so opening another bucket starts on its first table instead of carrying a table id that is
  // not one of its tables.
  const bucket = form.selected;
  const [subState, setSubState] = useState<{ bucketId: string; id: string | null } | null>(null);
  const sub =
    subState && bucket && subState.bucketId === bucket.id
      ? subState.id
      : (bucket?.tables[0]?.id ?? null);
  const openTable: SchemaTable | undefined = bucket?.tables.find((t) => t.id === sub);
  const selectSub = (id: string | null) => bucket && setSubState({ bucketId: bucket.id, id });
  const [settingsOpen, setSettingsOpen] = useState(false);

  // Unsaved work goes through the shared exit-guard system, as in every other pane — "navigating away with an unsaved bucket didn't stop me with a warning … there's a whole system for this we built" (Mike, 2026-09-24).
  // Three ways to lose it here: (1) the open table's unsaved rows, published to the rail so Back,
  // breadcrumbs and leaving the bucket prompt; (2) a click on a SIBLING table, a forward selection
  // the rail does not guard, so it is gated here; (3) closing Settings with an edited name or
  // description. (The bucket form's own guard is already published by useMasterDetailLevel.)
  const { exitGuard: rowsGuard, registerGuard } = useExitGuardChannel();
  useRailExitGuard(rowsGuard);
  const rowsGate = useExitGate(rowsGuard);
  // Read through a ref: the rail republishes a level only when its ids, selection or row count
  // change, so an `onSelect` closing over `rowsGate` would still hold the CLEAN gate after a row
  // was staged — and switch tables without asking.
  const rowsGateRef = useRef(rowsGate);
  rowsGateRef.current = rowsGate;
  const settingsGate = useExitGate(form.dirty ? form.guard : null);
  const closeSettings = () =>
    settingsGate.attemptExit(() => {
      // Discard = re-hydrate the draft from the saved bucket, keeping it selected.
      if (form.dirty && bucket) form.select(bucket.id);
      setSettingsOpen(false);
    });

  // The bucket's own rail is its tables and nothing else; the bucket's Settings sit behind the
  // gear in its header and open in a dialog (Mike, 2026-09-24: "add a gear icon … show the
  // settings in a dialog, remove settings from the tables list"). The `+` beside it adds a table.
  const bucketLevel: TopicLevel | null = bucket
    ? {
        id: "bucket-contents",
        title: bucket.name,
        items: bucket.tables.map((t) => ({
          id: t.id,
          label: t.name,
          sublabel: t.type,
          icon: <Table2 size={16} aria-hidden />,
        })),
        // A table that has just been removed is no longer a row.
        selectedId: openTable ? sub : null,
        onSelect: (id) => rowsGateRef.current.attemptExit(() => selectSub(id)),
        // Back/deselect is a level CLEAR, which the rail host already runs through the guard.
        onClear: () => selectSub(null),
        defaultSelectedId: bucket.tables[0]?.id,
        onNew: () => setAddTableOpen(true),
        newLabel: "Add table",
        titleActions: (
          <Button
            type="button"
            variant="ghost"
            size="icon"
            onClick={() => setSettingsOpen(true)}
            title="Bucket settings"
            aria-label="Bucket settings"
          >
            <Settings />
          </Button>
        ),
        itemNoun: "table",
        emptyLabel: "No tables yet.",
      }
    : null;

  async function removeTable(t: SchemaTable) {
    if (!bucket) return;
    await schemasApi.update(bucket.id, { tables: bucket.tables.filter((x) => x.id !== t.id) });
    selectSub(null);
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
            {isMarkdownType(openTable.type) ? (
              <MarkdownRowsView
                key={`${bucket.id}/${openTable.id}`}
                type={openTable.type}
                workspace={workspaceSlug}
              />
            ) : meta ? (
              <CrudDataView
                key={`${bucket.id}/${openTable.id}`}
                meta={meta}
                filter={{ ecosystemId: bucket.ecosystemId }}
                createDefaults={{ ecosystemId: bucket.ecosystemId }}
                onGuardChange={registerGuard}
              />
            ) : (
              <EmptyState
                title="These rows can't be browsed here."
                description={`${openTable.type} has no generic data view.`}
              />
            )}
          </>
        ) : (
          <EmptyState
            title={
              schemas === null
                ? "Loading…"
                : bucket
                  ? bucket.tables.length
                    ? "Select a table to see its rows."
                    : "No tables yet — add one with +."
                  : "Select a bucket, or create a new one."
            }
          />
        )}

        {/* The bucket's Settings, from the gear in its rail header. */}
        <Dialog
          open={settingsOpen && !!bucket}
          onOpenChange={(open) => (open ? setSettingsOpen(true) : closeSettings())}
        >
          <DialogContent className="max-w-2xl">
            <DialogHeader>
              <DialogTitle>{bucket?.name}</DialogTitle>
            </DialogHeader>
            <ButtonBar
              actions={form.actions}
              showCreate={false}
              // Deleting lives in the danger zone below; a bar Delete would only ever be a
              // disabled second button naming the same action.
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
            {form.editing && form.draft && (
              <div className="flex max-h-[70vh] flex-col gap-6 overflow-y-auto" key={form.detailKey}>
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
                          setSettingsOpen(false);
                          if (leaf) leaf.onSelect(null);
                          else form.actions.onCancel();
                          await refresh();
                        }
                      : undefined
                  }
                />
              </div>
            )}
          </DialogContent>
        </Dialog>

        <UnsavedChangesAlert {...rowsGate.exitAlertProps} />
        <UnsavedChangesAlert {...settingsGate.exitAlertProps} />

        {/* Create is a scoped modal: name + description only (tables are added from the new
            bucket's own rail, which opens once the created bucket is selected). */}
        {newOpen && (
          <CreateResourceDialog<SchemaDefinitionInput, SchemaDefinition>
            ariaLabel="New bucket"
            heading="New bucket"
            blank={schemaBlank}
            validate={(d) => schemaValidate(d, schemas ?? [])}
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
                    onChange={(e) => onChange(withName(draft, e.target.value))}
                  />
                </Field>
                <BucketSlugField
                  draft={draft}
                  onChange={onChange}
                  prefix={bucketSlugPrefix(undefined, ecosystemId)}
                />
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
