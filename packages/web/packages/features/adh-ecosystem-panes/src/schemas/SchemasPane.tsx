"use client";

import { useCallback, useRef, useState } from "react";
import type { ReactNode } from "react";

import { Pencil, Settings, Table2, Trash2, Wrench } from "lucide-react";
import { useResourceList } from "@agentic-toolkit/data";
import { EmptyState } from "@agenticdevelopertoolkit/ui/components/empty-state";
import { AlertModal } from "@agenticdevelopertoolkit/ui/components/alert-modal";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@agenticdevelopertoolkit/ui/components/dropdown-menu";
import { Field, ListToolButton } from "@agenticdevelopertoolkit/ui/blocks";
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
import { DialogErrorText, ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { CreateResourceDialog, StackLevels } from "@agentic-toolkit/resource";
import { CRUD_TABLES, CrudDataView, useExitGuardChannel } from "@agentic-toolkit/crud";
import { UnsavedChangesAlert } from "@agenticdevelopertoolkit/ui/components/unsaved-changes-alert";
import { useExitGate } from "@agenticdevelopertoolkit/ui/hooks/useExitGate";
import { useRailExitGuard } from "@agentic-toolkit/resource";
import { schemasApi } from "@agentic-toolkit/data/markdown";
import { bucketsCacheKey, newSchemaTable, slugifyTableName, tableNameInput } from "./schema-model";
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
import { nameForType, TYPE_BY_ID, TypeOptions } from "./type-options";
import { isMarkdownType, MarkdownRowsView } from "./MarkdownRowsView";
import type { RenderTransferSection } from "../transfer-seam";

// Settings edits the bucket's name, slug and description only; its tables are added and removed
// from the bucket's rail — one at a time, or all at once from its table actions — each a save of
// its own. So neither the dirty check nor the save
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

/** The table ops `mutateTables` serializes — see there. */
type TableOp = "add" | "edit" | "remove" | "addAll";

const TABLE_OP_BUSY = "Another change to this bucket's tables is still saving. Try again in a moment.";

/** Table-name validation as a save sees it: the name the field holds, slugified to its final shape
 *  (the field keeps trailing separators while typing — `tableNameInput`). */
function finalTableNameValidate(raw: string, others: SchemaTable[]): string | null {
  return tableNameValidate(slugifyTableName(raw), others);
}

export function SchemasPane({
  ecosystemId,
  workspaceSlug,
  help,
  leaf,
  renderTransfer,
}: {
  ecosystemId?: string;
  /** The workspace whose principal owns a markdown-backed table's documents (docs, notes,
   *  papers). The rows are ALSO scoped to the bucket's ecosystem (`?ecosystemId=`), so a product
   *  bucket lists that product's documents, never the workspace-wide set (Mike, 2026-09-25).
   *  Undefined acts as the caller, the same degrade every `?workspace=` reader makes. */
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
    validate: (draft, others, base) => schemaValidate(draft, others, base?.slug),
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
  // WHICH bucket's Settings are open, not merely whether. A boolean outlived every way out that
  // did not clear it — the dialog's Cancel deselected the bucket and left it set, so Settings
  // popped open over the next bucket selected. Keyed to the id, the dialog can only ever show the
  // bucket whose gear opened it.
  const [settingsFor, setSettingsFor] = useState<string | null>(null);

  // Unsaved work goes through the shared exit-guard system, as in every other pane — "navigating
  // away with an unsaved bucket didn't stop me with a warning … there's a whole system for this we
  // built" (Mike, 2026-09-24).
  // Three ways to lose it here: (1) the open table's unsaved rows, published to the rail so Back,
  // breadcrumbs, leaving the bucket and a click on a SIBLING table prompt — the rail host runs a
  // sibling swap past this published guard itself, so the table rail's `onSelect` must not gate
  // it again (it did, and asked the same question twice); (2) the pane's own ways off the open
  // table, which no rail sees — removing it, editing it (a retype swaps its rows), opening a table
  // just added, and a Settings save that moves the slug the rows are keyed on — gated here by
  // `rowsGate`; (3) closing Settings with an edited name or description. (The bucket form's own
  // guard is already published by useMasterDetailLevel.)
  const { exitGuard: rowsGuard, registerGuard } = useExitGuardChannel();
  useRailExitGuard(rowsGuard);
  const rowsGate = useExitGate(rowsGuard);
  // Read through a ref wherever a callback can outlive its render: Add table's `onCreated` runs
  // once the create resolves, from the render that started it. That is how the rail's `onSelect`
  // once switched tables without asking — the rail republishes a level only when its plain fields
  // change, so it still held the CLEAN gate after a row was staged.
  const rowsGateRef = useRef(rowsGate);
  rowsGateRef.current = rowsGate;
  const settingsGate = useExitGate(form.dirty ? form.guard : null);
  const closeSettings = () =>
    settingsGate.attemptExit(() => {
      // Discard = re-hydrate the draft from the saved bucket, keeping it selected.
      if (form.dirty && bucket) form.select(bucket.id);
      setSettingsFor(null);
    });

  // Every table op — add, edit, remove, add all — is a save of its own that sends the bucket's
  // WHOLE table list, which the data client reconciles against the server: tables missing from it
  // are DELETEd, unknown ids POSTed. So two ops must never overlap, and none may send a list read
  // at render time: a second op built on the snapshot the first one started from would delete the
  // table the first created, or resurrect the one it removed. Hence (1) ONE in-flight guard, read
  // through a ref — the rail republishes `titleActions` only when a plain field moves, so a
  // handler there can be a render old and a state flag in its closure stale — with the state copy
  // disabling `+`, the pencil, the trash and Add all while it is set; and (2) every op re-reads the
  // bucket's tables from the server and applies ITSELF to that list (`mutateTables`).
  const [tableOp, setTableOp] = useState<TableOp | null>(null);
  const tableOpRef = useRef<TableOp | null>(null);
  // The bucket as of the latest render, for the same stale-closure reason (a slug save moves its id).
  const bucketRef = useRef(bucket);
  bucketRef.current = bucket;
  const removing = tableOp === "remove";
  // The tables a Remove is waiting on the user to confirm. A removal drops the table's bucket_types
  // row — and with it every persona interest pointing at that id — so one stray click on the trash
  // must not be enough (Mike, 2026-09-25). `what` names them in the question; `all` removes every
  // table the bucket holds when the removal RUNS, not the ones listed when it was asked.
  const [pendingRemove, setPendingRemove] = useState<{
    tables: SchemaTable[];
    what: string;
    all?: boolean;
  } | null>(null);
  const [addAllError, setAddAllError] = useState<string | null>(null);
  const tablesBusy = tableOp !== null;
  // The (slugified) name of the table an Add table save is creating, so the dialog's `onCreated`
  // opens that one — not "whichever name the render-time list lacked".
  const addedNameRef = useRef<string | null>(null);

  /** Run one table op: refuse while another is in flight, re-read the bucket's CURRENT tables, and
   *  save `compute(current)`. `compute` may throw to refuse (a name taken meanwhile, a table
   *  already gone). */
  async function mutateTables(
    kind: TableOp,
    compute: (current: SchemaTable[]) => SchemaTable[],
  ): Promise<SchemaDefinition> {
    const target = bucketRef.current;
    if (!target) throw new Error("No bucket is open.");
    if (tableOpRef.current) throw new Error(TABLE_OP_BUSY);
    tableOpRef.current = kind;
    setTableOp(kind);
    try {
      const fresh = await schemasApi.get(target.id);
      if (!fresh) throw new Error("Couldn't read the bucket's current tables. Try again.");
      return await schemasApi.update(fresh.id, { tables: compute(fresh.tables) });
    } finally {
      tableOpRef.current = null;
      setTableOp(null);
    }
  }
  // Why the confirmed removal was refused — shown in the confirm, which is the only place the
  // question it answered is still on screen.
  const [removeError, setRemoveError] = useState<string | null>(null);

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
        // Ungated on purpose: the rail host already runs a sibling swap past the guard that
        // `useRailExitGuard(rowsGuard)` above publishes — gating it here too asked the same
        // question twice.
        onSelect: (id) => selectSub(id),
        // Back/deselect is a level CLEAR, which the rail host already runs through the guard.
        onClear: () => selectSub(null),
        defaultSelectedId: bucket.tables[0]?.id,
        // No `+` while a table op is saving: an Add started then would be built on the list that
        // op is replacing. The ref check covers a handler the rail registered a render ago.
        onNew: tablesBusy
          ? undefined
          : () => {
              if (!tableOpRef.current) setAddTableOpen(true);
            },
        newLabel: "Add table",
        // The plain companion of the busy state: a moved plain field is what makes the rail
        // re-register this level, and with it `titleActions`' disabled Add all / Remove all.
        busy: tablesBusy,
        // The rail toolbar's own tool button, as the `+` beside it is drawn: a ghost Button here
        // stood larger and brighter than the `+`, the look the list tools had already been moved
        // off (Mike, 2026-09-24). One click, straight to a dialog — a gear opening a MENU would be
        // GearMenuTrigger's.
        titleActions: (
          <>
            <ListToolButton
              label="Bucket settings"
              aria-haspopup="dialog"
              onClick={() => setSettingsFor(bucket.id)}
            >
              <Settings size={15} aria-hidden />
            </ListToolButton>
            {/* The bulk verbs the old in-Settings tables editor had — Add all, Remove all — back on
                the list they act on, behind a tool menu, each still a save of its own (Mike,
                2026-09-25). The gear stays one click to Settings; these are a second list of
                verbs, so they get their own trigger rather than a menu in front of Settings. */}
            <DropdownMenu>
              <DropdownMenuTrigger
                aria-label="Table actions"
                title="Table actions"
                className="flex shrink-0 items-center justify-center rounded p-0.5 text-apt-text-muted outline-none hover:text-apt-text focus-visible:ring-2 focus-visible:ring-apt-gold/40"
              >
                <Wrench size={15} aria-hidden />
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                <DropdownMenuItem
                  disabled={missingTypes(bucket.tables).length === 0 || tablesBusy}
                  onClick={() => void addAllTables()}
                >
                  Add all tables
                </DropdownMenuItem>
                <DropdownMenuItem
                  disabled={bucket.tables.length === 0 || tablesBusy}
                  onClick={() => {
                    if (tableOpRef.current) return;
                    // Every table goes, the open one with it, so staged rows ask first.
                    rowsGateRef.current.attemptExit(() => {
                      setRemoveError(null);
                      setPendingRemove({ tables: bucket.tables, what: "every table", all: true });
                    });
                  }}
                >
                  Remove all tables…
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </>
        ),
        itemNoun: "table",
        emptyLabel: "No tables yet.",
      }
    : null;


  // Renaming or retyping a table (the pencil beside the trash) is a save of its own as well, in a
  // modal like Add table's, pre-filled. The deleted in-place tables editor used to do this;
  // without it, the only fix for a wrong name or type was remove + re-add, which mints a new
  // bucket_types id and strands whatever pointed at the old one (a persona interest's
  // bucketTypeId). Held by id, as Settings is by bucket, so the dialog can only ever edit a table
  // of the bucket on screen.
  const [editTableId, setEditTableId] = useState<string | null>(null);
  const editTable = bucket?.tables.find((t) => t.id === editTableId);

  async function removeTables(gone: SchemaTable[], all = false) {
    if (!bucketRef.current || tableOpRef.current) return;
    setRemoveError(null);
    const ids = new Set(gone.map((t) => t.id));
    try {
      // Applied to the tables the server holds NOW: a table another op added since the confirm
      // opened is kept (unless the confirm said "every table"), and one already gone stays gone.
      await mutateTables("remove", (current) =>
        all ? [] : current.filter((x) => !ids.has(x.id)),
      );
    } catch (err) {
      // Shown in the confirm, which stays open on a refusal: the question it answered is still
      // the one on screen, and a retry is one click.
      setRemoveError(err instanceof Error ? err.message : "Couldn't remove the table.");
      return;
    }
    setPendingRemove(null);
    selectSub(null);
    // The removal has landed. A failed re-read is the list's own error (`loadError`, above the
    // pane), never reported as a failed removal — that would tell the user to do it again.
    await refresh().catch(() => {});
  }

  // Every catalogue type the bucket doesn't hold yet, named as Add table would name it — suffixed
  // with its schema where that name is already taken, so a bulk add never trips the uniqueness
  // rule a hand-picked name would be asked to fix.
  function missingTypes(tables: SchemaTable[]): SchemaTable[] {
    const held = new Set(tables.map((t) => t.type));
    const names = new Set(tables.map((t) => t.name));
    const out: SchemaTable[] = [];
    for (const t of TYPE_BY_ID.values()) {
      if (held.has(t.id)) continue;
      const base = nameForType(t.id);
      const name = names.has(base) ? `${base}_${t.schema}` : base;
      names.add(name);
      out.push(newSchemaTable(t.id, name));
    }
    return out;
  }

  // Reached from the rail's `titleActions`, which can be a render old — so everything it reads is
  // a ref or the server, never this render's `bucket`.
  async function addAllTables() {
    if (!bucketRef.current || tableOpRef.current) return;
    setAddAllError(null);
    try {
      await mutateTables("addAll", (current) => [...current, ...missingTypes(current)]);
    } catch (err) {
      setAddAllError(err instanceof Error ? err.message : "Couldn't add the tables.");
      return;
    }
    await refresh().catch(() => {});
  }

  const meta = openTable ? crudMetaForType(openTable.type) : undefined;
  // What the open table's rows view is keyed on: the bucket (its rdid moves with the slug), the
  // table, and the table's TYPE — a retype makes it another sql table, and rows staged in the old
  // one's grid must not carry onto the new one's.
  const rowsKey = bucket && openTable ? `${bucket.id}/${openTable.id}/${openTable.type}` : "";

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
                variant="ghost"
                size="icon"
                // Asked on open, not on Save: a retype swaps the rows under the table, and the
                // dialog's Save cannot wait on a second question (a Stay would leave it saving).
                // The staged rows go only if the save retypes the table (`rowsKey`): a rename or
                // a cancel leaves them staged, as a refused removal does.
                onClick={() =>
                  !tableOpRef.current &&
                  rowsGateRef.current.attemptExit(() => setEditTableId(openTable.id))
                }
                // Any table op, not only a removal: an edit opened over an Add in flight would be
                // saved against the list that Add is replacing.
                disabled={tablesBusy}
                title="Edit table"
                aria-label={`Edit ${openTable.name}`}
              >
                <Pencil />
              </Button>
              <Button
                type="button"
                variant="destructive-ghost"
                size="icon"
                // Removing the table unmounts its rows, so rows staged in them ask first — the
                // same question leaving the table any other way asks — and then the removal itself
                // is confirmed.
                onClick={() =>
                  !tableOpRef.current &&
                  rowsGateRef.current.attemptExit(() => {
                    setRemoveError(null);
                    setPendingRemove({ tables: [openTable], what: `“${openTable.name}”` });
                  })
                }
                disabled={tablesBusy}
                title="Remove table from bucket"
                aria-label={`Remove ${openTable.name} from bucket`}
              >
                <Trash2 />
              </Button>
            </div>
            {isMarkdownType(openTable.type) ? (
              <MarkdownRowsView
                key={rowsKey}
                type={openTable.type}
                workspace={workspaceSlug}
                ecosystemId={bucket.ecosystemId}
              />
            ) : meta ? (
              <CrudDataView
                key={rowsKey}
                meta={meta}
                // A SCOPE, not a filter: the backend verifies the caller manages the bucket's
                // ecosystem and acts there on every verb. As a plain filter it read a non-admin's
                // product bucket as empty and refused every create (Mike, 2026-09-25).
                scopeEcosystemId={bucket.ecosystemId}
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
          open={!!bucket && settingsFor === bucket.id}
          onOpenChange={(open) => (open ? setSettingsFor(bucket?.id ?? null) : closeSettings())}
        >
          <DialogContent className="max-w-2xl">
            <DialogHeader>
              <DialogTitle>{bucket?.name}</DialogTitle>
            </DialogHeader>
            <ButtonBar
              // Inside the dialog, always. The default hoists the bar into the host's toolbar slot,
              // and a host that publishes a real one (StandaloneRailHost, on the storage and
              // products sites) put Save and Cancel outside the modal, behind its backdrop.
              hoist={false}
              actions={{
                ...form.actions,
                // The form's Cancel deselects the bucket — right for a detail pane, wrong for a
                // dialog over the bucket's own tables: it closed the bucket out from under the
                // user. Cancel here drops the edit (the same re-hydrate `closeSettings` discards
                // with) and closes, leaving the bucket and its open table where they were.
                onCancel: () => {
                  if (form.dirty && bucket) form.select(bucket.id);
                  setSettingsFor(null);
                },
                // A new slug is a new rdid, and the open table and its rows are keyed on it, so a
                // save that moves it leaves them — rows staged there ask first.
                onSave: () =>
                  bucket && form.draft && form.draft.slug.trim() !== bucket.slug
                    ? rowsGateRef.current.attemptExit(form.actions.onSave)
                    : form.actions.onSave(),
              }}
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
                          setSettingsFor(null);
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

        {/* A confirm, not an alert: `cancelLabel` makes the ✕ a Cancel rather than a second
            Confirm. A refusal is said HERE, in the question it answered. */}
        <AlertModal
          open={pendingRemove !== null}
          title={`Remove ${pendingRemove?.what ?? ""} from ${bucket?.name ?? "the bucket"}?`}
          description={
            <>
              The table is taken out of this bucket, and anything that points at it by id — a
              persona's interest in it — stops pointing anywhere. Its rows stay in the ecosystem.
              <DialogErrorText error={removeError} />
            </>
          }
          destructive
          confirmLabel="Remove"
          cancelLabel="Cancel"
          busy={removing}
          onConfirm={() =>
            pendingRemove && void removeTables(pendingRemove.tables, pendingRemove.all)
          }
          onCancel={() => {
            setPendingRemove(null);
            setRemoveError(null);
          }}
        />
        <AlertModal
          open={addAllError !== null}
          title="Couldn't add the tables"
          description={addAllError ?? ""}
          onConfirm={() => setAddAllError(null)}
        />

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
              d.type ? finalTableNameValidate(d.name, bucket.tables) : "Pick a type (sql-table)."
            }
            // Appended to the tables the server holds NOW, re-checked there: another op may have
            // taken the name, or changed the list, since this dialog opened.
            create={(d) => {
              const name = slugifyTableName(d.name);
              addedNameRef.current = name;
              return mutateTables("add", (current) => {
                const taken = tableNameValidate(name, current);
                if (taken) throw new Error(taken);
                return [...current, newSchemaTable(d.type, name)];
              });
            }}
            onClose={() => setAddTableOpen(false)}
            onCreated={(updated) => {
              setAddTableOpen(false);
              void refresh();
              // Open the table just added — the saved row carries the backend's id for it. Opening
              // it leaves the open table, so rows staged there ask first; the ref, because this
              // runs once the create resolves, from the render that opened the dialog.
              const added = updated.tables.find((t) => t.name === addedNameRef.current);
              if (added) rowsGateRef.current.attemptExit(() => selectSub(added.id));
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
                    onChange={(e) => onChange({ ...draft, name: tableNameInput(e.target.value) })}
                  />
                </Field>
                <ErrorText error={error} />
              </>
            )}
          />
        )}

        {editTable && bucket && (
          <CreateResourceDialog<NewTableDraft, SchemaDefinition>
            ariaLabel="Edit table"
            heading={`Edit ${editTable.name}`}
            blank={() => ({ name: editTable.name, type: editTable.type })}
            validate={(d) =>
              finalTableNameValidate(d.name, bucket.tables.filter((x) => x.id !== editTable.id))
            }
            // The same id, patched in place: the data client PUTs a known table rather than
            // re-creating it, so the table keeps its bucket_types id. Patched into the tables the
            // server holds NOW — a table removed meanwhile is refused, never re-created by the
            // edit, and a name another op took meanwhile is refused too.
            create={(d) => {
              const name = slugifyTableName(d.name);
              return mutateTables("edit", (current) => {
                if (!current.some((x) => x.id === editTable.id)) {
                  throw new Error(`“${editTable.name}” is no longer in this bucket.`);
                }
                const taken = tableNameValidate(
                  name,
                  current.filter((x) => x.id !== editTable.id),
                );
                if (taken) throw new Error(taken);
                return current.map((x) =>
                  x.id === editTable.id ? { ...x, name, type: d.type } : x,
                );
              });
            }}
            onClose={() => setEditTableId(null)}
            onCreated={() => {
              setEditTableId(null);
              void refresh();
              // Pinned by id rather than left to the default (the bucket's first table): the
              // re-read list comes back in the backend's order, which nothing promises is the same.
              selectSub(editTable.id);
            }}
            renderForm={(draft, onChange, error) => (
              <>
                <Field label="Type (sql-table)">
                  <Select
                    aria-label="Type (sql-table)"
                    value={draft.type}
                    // Unlike Add table, a retype leaves the name alone: this one is already named.
                    onChange={(e) => onChange({ ...draft, type: e.target.value })}
                  >
                    {/* A stored type the curated catalogue no longer lists still shows its real
                        value, not a silently mismatched first option. */}
                    {!TYPE_BY_ID.has(editTable.type) && (
                      <option value={editTable.type}>{editTable.type} (unlisted)</option>
                    )}
                    <TypeOptions />
                  </Select>
                </Field>
                <Field label="Name" hint="Unique in this bucket; lowercase, no spaces.">
                  <Input
                    value={draft.name}
                    placeholder="contacts"
                    onChange={(e) => onChange({ ...draft, name: tableNameInput(e.target.value) })}
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
