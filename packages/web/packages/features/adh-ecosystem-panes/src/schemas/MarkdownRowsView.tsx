"use client";

import { useCallback, useEffect, useState } from "react";
import { useResourceList } from "@agentic-toolkit/data";
import { markdownApi, type ResearchSummary } from "@agentic-toolkit/data/markdown";
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
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
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

/** A markdown-backed type → how to list it and how a new row lands on its shelf. */
const MARKDOWN_TYPES: Record<
  string,
  { list: { doc?: boolean; noted?: boolean }; create?: { doc?: boolean; note?: boolean }; keep?: (d: ResearchSummary) => boolean }
> = {
  "content.markdown": { list: {}, create: {} },
  "content.docs": { list: { doc: true }, create: { doc: true } },
  "content.notes": { list: { noted: true }, create: { note: true } },
  // A paper is a PUBLISHED doc (publish mints the marker; visibility is the publish switch), so
  // the list is filtered here and there is no New: a row created from this table is not a paper.
  "content.papers": { list: {}, keep: (d) => d.visibility === "public" },
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

export function MarkdownRowsView({ type, workspace }: { type: string; workspace?: string }) {
  const spec = MARKDOWN_TYPES[type]!;
  const opts = { workspace };
  const load = useCallback(
    async () =>
      (await markdownApi.list({}, { ...spec.list, workspace })).filter(spec.keep ?? (() => true)),
    // `spec` is a module constant per `type`.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [type, workspace],
  );
  const { items, reload, error, isFetching } = useResourceList<ResearchSummary>(
    `bucket-markdown-rows:${type}:${workspace ?? ""}`,
    load,
  );

  // The row being edited: `null` closed, `""` id for a new row.
  const [editing, setEditing] = useState<{ id: string } | null>(null);
  const [content, setContent] = useState("");
  // What `content` was when the dialog opened (or the row loaded), so closing over an edit prompts
  // instead of dropping it — "navigating away with an unsaved bucket didn't stop me with a warning … there's a whole system for this we built" (Mike, 2026-09-24).
  const [original, setOriginal] = useState("");
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
    markdownApi.get(editing.id, opts).then(
      (doc) => {
        if (!live) return;
        setContent(doc.content);
        setOriginal(doc.content);
      },
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
      if (editing?.id) await markdownApi.update(editing.id, { content }, opts);
      else await markdownApi.create({ content, ...spec.create }, opts);
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
    try {
      await markdownApi.remove(deleting.id, opts);
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
        canWrite={spec.create !== undefined}
        readOnlyNote="Papers are published docs — publish a doc to add one."
        onNew={() => {
          setContent("");
          setOriginal("");
          setActionError(null);
          setEditing({ id: "" });
        }}
        onEdit={(row) => {
          setActionError(null);
          setEditing({ id: String(row.id) });
        }}
        onDelete={(row) => setDeleting(row as unknown as ResearchSummary)}
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
            readOnly={spec.create === undefined}
            onChange={(e) => setContent(e.target.value)}
            placeholder="# Title"
          />
          <ErrorText error={actionError} />
          <DialogFooter>
            <Button variant="ghost" onClick={close}>
              {spec.create === undefined ? "Close" : "Cancel"}
            </Button>
            {spec.create !== undefined && (
              <Button onClick={() => void save()} disabled={busy || !content.trim()}>
                Save
              </Button>
            )}
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <UnsavedChangesAlert {...closeGate.exitAlertProps} />

      <AlertModal
        open={deleting !== null}
        title={`Delete “${deleting?.title ?? ""}”?`}
        description="The document is soft-deleted with its marker."
        destructive
        confirmLabel="Delete"
        busy={busy}
        onConfirm={() => void remove()}
        onCancel={() => setDeleting(null)}
      />
    </div>
  );
}
