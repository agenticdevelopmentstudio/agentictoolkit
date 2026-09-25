"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useResourceList } from "@agentic-toolkit/data";
import { docsApi } from "@agentic-toolkit/data/docs";
import {
  markdownApi,
  type MarkdownListOptions,
  type MarkdownScope,
  type ResearchFilters,
  type ResearchSummary,
} from "@agentic-toolkit/data/markdown";
import { notesApi } from "@agentic-toolkit/data/notes";
import { CrudTable, type CrudRow, type CrudTableMeta } from "@agentic-toolkit/crud";
import { AlertModal } from "@agenticdevelopertoolkit/ui/components/alert-modal";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@agenticdevelopertoolkit/ui/components/dialog";
import { DialogErrorText, ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { Textarea } from "@agenticdevelopertoolkit/ui/components/textarea";
import { UnsavedChangesAlert } from "@agenticdevelopertoolkit/ui/components/unsaved-changes-alert";
import { useExitGate } from "@agenticdevelopertoolkit/ui/hooks/useExitGate";

/**
 * The rows of a MARKDOWN-backed bucket table — `content.markdown` and the three marker tables
 * that file a markdown doc on a shelf (`content.docs`, `content.notes`, `content.papers`).
 *
 * WHY THESE NEED THEIR OWN VIEW. The backend keeps all four off generic CRUD (SKIP_TABLES — the
 * markdown routes own their version-snapshot and marker invariants), so they have no
 * `CRUD_TABLES` entry and the bucket's table detail used to say "these rows can't be browsed
 * here". They can (Mike, 2026-09-24): every one of them is a lens on `/content/markdown`, which
 * already filters to a shelf — so this is that list, drawn in the same `CrudTable` every other
 * bucket table uses, rather than a second route set that would drift from markdownDocuments.ts.
 */

/** What this view needs of a markdown client. `markdownApi` fits it, and so do `docsApi` and
 *  `notesApi`, which are `markdownApi` with their shelf's marker baked in. */
interface MarkdownClient {
  list(filters: ResearchFilters, opts?: MarkdownListOptions): Promise<ResearchSummary[]>;
  get(id: string, opts?: MarkdownScope): Promise<{ content: string }>;
  create(body: { content: string }, opts?: MarkdownScope): Promise<unknown>;
  update(id: string, body: { content: string }, opts?: MarkdownScope): Promise<unknown>;
  remove(id: string, opts?: MarkdownScope): Promise<void>;
}

/**
 * One list REQUEST: the client that sends it, the list filter it adds, and the cache key its answer
 * is kept under. The key names the request, not a table type, so two types that send the same
 * request share one entry. Declared once per request so a client, its filter and its key cannot
 * part.
 */
interface ListSource {
  api: MarkdownClient;
  listKey: string;
  list?: Pick<MarkdownListOptions, "visibility">;
}
const EVERY_DOCUMENT: ListSource = { api: markdownApi, listKey: "all" };
const DOCS_SHELF: ListSource = { api: docsApi, listKey: "docs" };
const NOTES_SHELF: ListSource = { api: notesApi, listKey: "notes" };
// A paper is a PUBLISHED doc, and the backend filters by visibility itself: picking the public
// ones out of the first page of every document hid any paper past that page (Mike, 2026-09-25).
const PUBLISHED: ListSource = { api: markdownApi, listKey: "public", list: { visibility: "public" } };

/**
 * A markdown-backed type → where its rows come from, whether a new row belongs here, and which of
 * the listed rows are its own. A shelf's rows go through that shelf's own client, which adds the
 * marker on the way in and lists by it on the way out, so a row made here cannot be misfiled. The
 * marker flags used to be spelled here by hand, a second copy of what those clients already own.
 */
const MARKDOWN_TYPES: Record<string, ListSource & { canCreate: boolean }> = {
  "content.markdown": { ...EVERY_DOCUMENT, canCreate: true },
  "content.docs": { ...DOCS_SHELF, canCreate: true },
  "content.notes": { ...NOTES_SHELF, canCreate: true },
  // A paper is a PUBLISHED doc (publish mints the marker; visibility is the publish switch), so
  // there is no New — a row created from this table is not a paper.
  "content.papers": { ...PUBLISHED, canCreate: false },
};

export function isMarkdownType(type: string): boolean {
  return type in MARKDOWN_TYPES;
}

const col = (name: string) => ({
  name,
  type: "string" as const,
  required: false,
  nullable: true,
  serverManaged: true,
});

/** The summary columns worth a glance; the body is in the row's editor, not the grid. */
const META: CrudTableMeta = {
  key: "content/markdown",
  schema: "content",
  table: "markdown",
  basePath: "/content/markdown",
  itemPath: "/content/markdown/{id}",
  pkParams: [],
  exposure: "owner",
  columns: ["title", "category", "visibility", "excerpt"].map(col),
};

/**
 * `ecosystemId` is the BUCKET's ecosystem: every op acts there (backend `?ecosystemId=`), so a
 * product bucket's rows are that product's, not the workspace-wide list — "an ecosystem shows only
 * its own data" (Mike, 2026-09-25).
 */
export function MarkdownRowsView({
  type,
  workspace,
  ecosystemId,
}: {
  type: string;
  workspace?: string;
  ecosystemId?: string;
}) {
  const spec = MARKDOWN_TYPES[type]!;
  const { api, list } = spec;
  const opts = useMemo(() => ({ workspace, ecosystemId }), [workspace, ecosystemId]);
  // Keyed on the request — source, workspace and ecosystem — so two types that send one request
  // share one entry, and two buckets never share one.
  const load = useCallback(() => api.list({}, { ...opts, ...list }), [api, opts, list]);
  const { items, reload, error, isFetching } = useResourceList<ResearchSummary>(
    `bucket-markdown-rows:${spec.listKey}:${workspace ?? ""}:${ecosystemId ?? ""}`,
    load,
  );

  // The row being edited: `null` closed, `""` id for a new row.
  const [editing, setEditing] = useState<{ id: string } | null>(null);
  const [content, setContent] = useState("");
  // What `content` was when the dialog opened (or the row loaded), so closing over an edit prompts
  // instead of dropping it — "navigating away with an unsaved bucket didn't stop me with a
  // warning … there's a whole system for this we built" (Mike, 2026-09-24).
  const [original, setOriginal] = useState("");
  // Whether the open row's stored content has arrived. Until it has, the empty box stands for a
  // document not yet read, not an empty one: text typed into it was overwritten when the load
  // landed, and a Save after a failed load replaced the stored document with whatever was typed.
  // A new row has nothing to read, so it starts loaded.
  const [loaded, setLoaded] = useState(true);
  const dirty = editing !== null && content !== original;
  const closeGate = useExitGate(dirty ? { isDirty: () => true } : null);
  const close = () => closeGate.attemptExit(() => setEditing(null));
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const fail = (e: unknown) => setActionError(e instanceof Error ? e.message : String(e));
  const [deleting, setDeleting] = useState<ResearchSummary | null>(null);

  useEffect(() => {
    if (!editing?.id) return;
    let live = true;
    setContent("");
    setOriginal("");
    setLoaded(false);
    api.get(editing.id, opts).then(
      (doc) => {
        if (!live) return;
        setContent(doc.content);
        setOriginal(doc.content);
        setLoaded(true);
      },
      // A failed read stays unloaded: the error says why, and nothing typed can be saved over a
      // document this dialog never saw.
      (e: unknown) => live && fail(e),
    );
    return () => {
      live = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [editing?.id]);

  async function save() {
    setBusy(true);
    setActionError(null);
    try {
      if (editing?.id) await api.update(editing.id, { content }, opts);
      else await api.create({ content }, opts);
      setEditing(null);
      await reload();
    } catch (e) {
      fail(e);
    } finally {
      setBusy(false);
    }
  }

  async function remove() {
    if (!deleting) return;
    setBusy(true);
    // A retry starts clean; the confirm shows only what THIS attempt said.
    setActionError(null);
    try {
      await api.remove(deleting.id, opts);
      setDeleting(null);
      await reload();
    } catch (e) {
      fail(e);
    } finally {
      setBusy(false);
    }
  }

  const rows = (items ?? []) as unknown as CrudRow[];
  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col overflow-y-auto px-6 py-4">
      <CrudTable
        meta={META}
        rows={rows}
        loading={isFetching && !items}
        error={error}
        canWrite={spec.canCreate}
        readOnlyNote="Papers are published docs — publish a doc to add one."
        onNew={() => {
          setContent("");
          setOriginal("");
          setLoaded(true);
          setActionError(null);
          setEditing({ id: "" });
        }}
        onEdit={(row) => {
          setActionError(null);
          // Before the dialog opens, not in the load effect alone: the effect runs after the
          // dialog's first paint, which would otherwise show an editable box for that frame.
          setLoaded(false);
          setEditing({ id: String(row.id) });
        }}
        onDelete={(row) => {
          setActionError(null);
          setDeleting(row as unknown as ResearchSummary);
        }}
      />

      <Dialog open={editing !== null} onOpenChange={(open) => !open && close()}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{editing?.id ? "Edit row" : "New row"}</DialogTitle>
          </DialogHeader>
          <Textarea
            aria-label="Markdown"
            rows={14}
            className="font-mono"
            value={content}
            readOnly={!spec.canCreate || !loaded}
            onChange={(e) => setContent(e.target.value)}
            // A failed read says so below; "Loading…" would claim it is still coming.
            placeholder={loaded ? "# Title" : actionError ? undefined : "Loading…"}
          />
          <ErrorText error={actionError} />
          <DialogFooter>
            <Button variant="ghost" onClick={close}>
              {spec.canCreate ? "Cancel" : "Close"}
            </Button>
            {spec.canCreate && (
              <Button onClick={() => void save()} disabled={busy || !loaded || !content.trim()}>
                Save
              </Button>
            )}
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <UnsavedChangesAlert {...closeGate.exitAlertProps} />

      {/* A confirm, not an alert: without `cancelLabel` AlertModal is a one-button alert whose ✕
          runs `onConfirm`, so closing it re-sent the delete, and `onCancel` was unreachable. The
          failure is shown HERE — it used to land in `actionError` under the edit dialog, which is
          always closed while a delete is being confirmed, so a refused delete said nothing. */}
      <AlertModal
        open={deleting !== null}
        title={`Delete “${deleting?.title ?? ""}”?`}
        description={
          <>
            The document is soft-deleted with its marker.
            <DialogErrorText error={actionError} />
          </>
        }
        destructive
        confirmLabel="Delete"
        cancelLabel="Cancel"
        busy={busy}
        onConfirm={() => void remove()}
        onCancel={() => {
          setDeleting(null);
          setActionError(null);
        }}
      />
    </div>
  );
}
