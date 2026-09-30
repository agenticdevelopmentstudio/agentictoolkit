"use client";

import { useMemo, useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { Plus, Pencil, Trash2, PlugZap } from "lucide-react";
import {
  useProviderTemplateWindow,
  useDeleteProviderTemplate,
  type ProviderTemplate,
} from "../api/llm-providers";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Badge } from "@agenticdevelopertoolkit/ui/components/badge";
import { UnsavedChangesGuard } from "@agenticdevelopertoolkit/ui/components/unsaved-changes-guard";
import { ProgressModal } from "@agenticdevelopertoolkit/ui/blocks";
import { FeatureTitle } from "@agentic-toolkit/resource";
import {
  EditableList,
  TypeToConfirmDialog,
  WindowFooter,
  useBatchRun,
  useEditableList,
  type EditableListColumn,
  type EditableListFacet,
} from "../components/editable-list";
import { ProviderTemplateDialog } from "../llm-providers/ProviderTemplateDialog";
import { VerifyDialog } from "../llm-providers/VerifyDialog";
import { SyncPanel } from "../llm-providers/SyncPanel";

/**
 * The provider-template catalog a persona connects to — kind, base URL, models, and how the
 * connect UI authenticates.
 *
 * Every action moved to the bar. The three icon buttons that used to ride each row were the same
 * three verbs repeated once per template, and the destructive one sat a single click from the
 * pointer with only an "are you sure?" between it and a template whose deletion takes its models
 * with it. Delete now takes a selection and a typed word; Edit and Verify take exactly one row,
 * because each opens a dialog about one template and there is no honest way to point it at four.
 */

const KIND_BADGE_VARIANT: Record<
  ProviderTemplate["providerKind"],
  "accent" | "blue" | "orange" | "neutral"
> = {
  openai: "accent",
  anthropic: "blue",
  gemini: "orange",
  external: "neutral",
};

/** Whether the connect UI knows how to authenticate against this template. */
const authLabel = (t: ProviderTemplate): string => (t.connectionSpec ? "configured" : "none");

export function LlmProvidersPane({ help }: { help?: ReactNode } = {}) {
  const router = useRouter();
  const catalog = useProviderTemplateWindow();

  const [creating, setCreating] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [verifyingId, setVerifyingId] = useState<string | null>(null);
  const [dialogDirty, setDialogDirty] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);

  const deleteTemplate = useDeleteProviderTemplate();
  const deleteRun = useBatchRun({
    invalidateKey: ["admin", "llm-providers", "templates"],
    successMessage: "deleted",
  });

  const columns = useMemo<EditableListColumn<ProviderTemplate>[]>(
    () => [
      {
        key: "name",
        header: "Name",
        width: "16rem",
        value: (t) => t.name,
        render: (t) => (
          <span className="block truncate font-medium text-apt-text" title={t.name}>
            {t.name}
          </span>
        ),
      },
      {
        key: "providerKind",
        header: "Kind",
        width: "8rem",
        value: (t) => t.providerKind,
        render: (t) => <Badge variant={KIND_BADGE_VARIANT[t.providerKind]}>{t.providerKind}</Badge>,
      },
      {
        key: "baseUrl",
        header: "Base URL",
        width: "minmax(0,1fr)",
        value: (t) => t.baseUrl,
        render: (t) => (
          <span className="block truncate font-mono text-xs text-apt-text-muted" title={t.baseUrl}>
            {t.baseUrl}
          </span>
        ),
      },
      {
        key: "models",
        header: "Models",
        width: "6.5rem",
        align: "end",
        // The COUNT, not the rendered string: sorting text would put 9 after 10.
        value: (t) => t.models.length,
        render: (t) => <span className="tabular-nums text-apt-text-muted">{t.models.length}</span>,
      },
      {
        key: "auth",
        header: "Auth",
        width: "8rem",
        value: authLabel,
        render: (t) =>
          t.connectionSpec ? (
            <Badge variant="success">configured</Badge>
          ) : (
            <span className="text-apt-text-dim">none</span>
          ),
      },
    ],
    [],
  );

  const facets = useMemo<EditableListFacet<ProviderTemplate>[]>(
    () => [
      { id: "kind", label: "Kind", valuesOf: (t) => [t.providerKind] },
      { id: "auth", label: "Auth", valuesOf: (t) => [authLabel(t)] },
    ],
    [],
  );

  const list = useEditableList<ProviderTemplate>({
    rows: catalog.rows,
    getRowId: (t) => t.id,
    columns,
    facets,
    initialSort: { key: "name", dir: "asc" },
  });

  const selected = list.selectedRows;
  // Resolved from the LIVE rows, never captured at click time: a saved template refetches, and a
  // dialog comparing against the row as it looked before the save reads as permanently dirty.
  const editing = useMemo(
    () => catalog.rows.find((t) => t.id === editingId) ?? null,
    [catalog.rows, editingId],
  );
  const verifying = useMemo(
    () => catalog.rows.find((t) => t.id === verifyingId) ?? null,
    [catalog.rows, verifyingId],
  );

  const modelCount = selected.reduce((n, t) => n + t.models.length, 0);

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <FeatureTitle
        title="LLM Providers"
        api={{
          method: "GET",
          path: "/persona/provider-templates",
          pathValues: {},
          title: "Provider templates API",
        }}
        help={help}
      />
      <div className="flex min-h-0 min-w-0 flex-1 flex-col overflow-y-auto px-6 pb-8 pt-2">
        <p className="mb-6 max-w-2xl text-sm text-apt-text-muted">
          The provider-template catalog a persona connects to — kind, base URL, its available models,
          and (optionally) how the connect UI authenticates. Deleting a template also deletes its
          models.
        </p>

        <SyncPanel />

        <div className="mt-6">
          <EditableList<ProviderTemplate>
            list={list}
            ariaLabel="Provider templates"
            loading={catalog.isLoading}
            error={catalog.error}
            errorTitle="Couldn't load provider templates"
            columnWidthsKey="admin-llm-providers"
            describeRow={(t) => t.name}
            searchPlaceholder="Name, kind or URL"
            emptyLabel="No provider templates yet."
            emptyFilteredLabel="No templates match these filters."
            actions={
              <>
                <Button size="sm" variant="ghost" onClick={() => setCreating(true)}>
                  <Plus data-icon="inline-start" />
                  New
                </Button>
                <Button
                  size="sm"
                  variant="ghost"
                  disabled={selected.length !== 1}
                  onClick={() => {
                    setEditingId(selected[0]!.id);
                    setDialogOpen(true);
                  }}
                >
                  <Pencil data-icon="inline-start" />
                  Edit
                </Button>
                {/* One row: verifying probes ONE base URL with ONE credential and reports what came
                    back. A run over four would be four reports in a dialog built to show one. */}
                <Button
                  size="sm"
                  variant="ghost"
                  disabled={selected.length !== 1}
                  onClick={() => setVerifyingId(selected[0]!.id)}
                >
                  <PlugZap data-icon="inline-start" />
                  Verify
                </Button>
                <Button
                  size="sm"
                  variant="destructive-ghost"
                  disabled={selected.length === 0}
                  onClick={() => setConfirmDelete(true)}
                >
                  <Trash2 data-icon="inline-start" />
                  Delete
                </Button>
              </>
            }
            footer={
              <WindowFooter
                noun="templates"
                // A catalog, not a log: the server returns it in its own order, so "the newest
                // hundred" would be a claim about an ordering this list does not have.
                windowWord="first"
                unloadedWord="more"
                wholeWord="catalog"
                loaded={catalog.rows.length}
                showing={list.rows.length}
                total={catalog.total}
                hasMore={catalog.hasMore}
                busy={catalog.isFetchingMore}
                onLoadMore={catalog.loadMore}
              />
            }
          />
        </div>

        <UnsavedChangesGuard when={dialogDirty} onNavigate={(href) => router.push(href)} />

        <ProviderTemplateDialog
          // A fresh key per target remounts the form, so its draft resets between targets — while
          // reopening the SAME one restores what was typed.
          key={creating ? "create" : (editingId ?? "closed")}
          open={creating || (dialogOpen && editing !== null)}
          template={creating ? null : editing}
          onClose={() => {
            setCreating(false);
            setDialogOpen(false);
          }}
          onDirtyChange={setDialogDirty}
        />

        <VerifyDialog
          key={verifyingId ?? "verify-closed"}
          open={verifying !== null}
          template={verifying}
          onClose={() => setVerifyingId(null)}
        />

        {/* Typed, not clicked. A template's deletion takes its models with it and strands every
            persona configured against it, and the selection can hold rows scrolled out of view. */}
        <TypeToConfirmDialog
          open={confirmDelete}
          title={selected.length === 1 ? "Delete this template?" : `Delete ${selected.length} templates?`}
          description={
            <>
              {selected.map((t) => t.name).join(", ")} — and {modelCount} model
              {modelCount === 1 ? "" : "s"} — will be removed. Personas configured against them will
              no longer resolve.
            </>
          }
          confirmValue="delete"
          valueNoun="word"
          confirmLabel="Delete"
          onCancel={() => setConfirmDelete(false)}
          onConfirm={() => {
            setConfirmDelete(false);
            void deleteRun.run(
              selected.map((t) => ({ id: t.id, label: t.name })),
              (item) => deleteTemplate.mutateAsync(item.id),
            );
          }}
        />

        <ProgressModal
          open={deleteRun.state.running || deleteRun.state.finished}
          title="Deleting provider templates"
          description="Each template is deleted on its own; a failure leaves the earlier deletions in place."
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
      </div>
    </div>
  );
}
