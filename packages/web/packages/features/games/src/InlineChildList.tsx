"use client";

import { useCallback, type ReactNode } from "react";
import { Plus } from "lucide-react";
import { useResourceList } from "@agentic-toolkit/data";
import { ButtonBar } from "@agenticdevelopertoolkit/ui/blocks";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { AlertModal } from "@agenticdevelopertoolkit/ui/components/alert-modal";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { cn } from "@agenticdevelopertoolkit/ui/lib/utils";
import { useMasterDetailForm, type TopicLeaf } from "@agentic-toolkit/resource";
import { sortByGroup } from "./group";
import { inlineUrlSelection } from "./inlineSelection";

/** Everything one inline child collection needs. Deliberately the same vocabulary as
 *  `GameChildPaneConfig` — these are the SAME rows, reached from a second place. */
export interface InlineChildListConfig<TRow, TInput> {
  /** Cache-key discriminator. MUST match the top-level pane's (`effects`, `mappings`) so both
   *  views of one collection read and invalidate a single cached list — a create here shows up
   *  in the Effects topic without a reload, because there is only one list. */
  collection: string;
  title: string;
  /** One line under the heading saying what the rows below are, in this context. */
  blurb: string;
  itemNoun: string;
  emptyLabel: string;
  /** Keep only the rows belonging to the open definition (`definitionId` / `fromId`). Filtering
   *  CLIENT-SIDE rather than asking for a narrower list is what lets both views share one cache
   *  entry; the collections are a game's, and a game's content is small. */
  keep: (row: TRow) => boolean;
  getId: (row: TRow) => string;
  getLabel: (row: TRow) => string;
  getGroup: (row: TRow) => string;
  getSort: (row: TRow) => number;
  list: (gameId: string) => Promise<TRow[]>;
  create: (gameId: string, input: TInput) => Promise<TRow>;
  update: (id: string, input: TInput) => Promise<TRow>;
  remove: (id: string) => Promise<void>;
  confirmDelete: (row: TRow) => string;
  blank: () => TInput;
  toInput: (row: TRow) => TInput;
  normalize: (input: TInput) => TInput;
  differs: (a: TInput, b: TInput) => boolean;
  /** `base` is the selected row's stored input (null while creating) — the hook passes it so a
   *  rule can exempt a value the record already holds; see useMasterDetailForm's `validate`. */
  validate: (draft: TInput, others: TRow[], base: TInput | null) => string | null;
  renderFields: (
    draft: TInput,
    onChange: (next: TInput) => void,
    error: string | null | undefined,
  ) => ReactNode;
}

/**
 * A child collection shown INSIDE the definition that owns it — the effects that fire on this
 * thing, and the connections that lead out of it. An author works one definition at a time and
 * has to see both there; the top-level Effects and Connections topics answer the other question
 * (the whole game at once, for balancing and for the map), so neither replaces the other and
 * BOTH write the same rows.
 *
 * The editors are the shared `EffectFields` / `MappingFields` the top-level panes render, not
 * copies: a rule stated twice is a rule that drifts.
 *
 * The bar here is the plain `ui` one, NOT `resource`'s — that one portals into the workspace
 * toolbar, which the pane this list sits inside is already using for the definition's own
 * Save/Cancel. Two of them would fight over one slot. The delete confirmation `resource`'s bar
 * would have brought along is rendered below instead, from the same hook state.
 */
export function InlineChildList<TRow, TInput>({
  gameId,
  leaf,
  config,
}: {
  gameId: string;
  /** The FIFTH URL segment, built by `subLeafFor(definitionId)`. Both inline lists under one
   *  definition share it, and `inlineUrlSelection` is what keeps that from crossing the
   *  wires: a list ignores an id it does not have, and clears the segment only when the
   *  segment is its own. Two editors CAN be open at once — a create does not touch the URL
   *  (see `useMasterDetailForm.create`), so a new connection opens beneath an already-open
   *  effect. What cannot happen is one list closing the other. */
  leaf?: TopicLeaf;
  config: InlineChildListConfig<TRow, TInput>;
}) {
  const load = useCallback(
    () => config.list(gameId),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [gameId],
  );
  const {
    items: all,
    reload,
    error: loadError,
  } = useResourceList<TRow>(`game:${gameId}:${config.collection}`, load);

  // Swallowed for the same reason it is in GameChildPane: this re-read follows a write that has
  // already succeeded, and reporting its failure as the write's would tell the author their edit
  // was lost. The hook's own `error` still renders it.
  const refresh = useCallback(() => reload().catch(() => {}), [reload]);

  const rows =
    all === null
      ? null
      : sortByGroup(all.filter(config.keep), config.getGroup, config.getLabel, config.getSort);

  const form = useMasterDetailForm<TRow, TInput>({
    items: rows,
    getId: config.getId,
    blank: config.blank,
    toInput: config.toInput,
    validate: config.validate,
    differs: config.differs,
    normalize: config.normalize,
    create: (input) => config.create(gameId, input),
    update: config.update,
    remove: (row) => config.remove(config.getId(row)),
    confirmDelete: config.confirmDelete,
    refresh,
    urlSelection: inlineUrlSelection(leaf, rows, config.getId),
  });

  const actions = form.actions;

  return (
    <section className="flex flex-col gap-3">
      <div className="flex items-start justify-between gap-4">
        <div className="flex flex-col gap-1">
          <h3 className="font-mono text-sm font-medium tracking-wide text-apt-gold">
            {config.title}
          </h3>
          <p className="text-xs text-apt-text-muted">{config.blurb}</p>
        </div>
        <Button variant="ghost" size="sm" onClick={actions.onCreate}>
          <Plus data-icon="inline-start" />
          New {config.itemNoun}
        </Button>
      </div>

      <ErrorText error={loadError} />

      {rows === null ? (
        <p className="text-sm text-apt-text-muted">Loading…</p>
      ) : rows.length === 0 ? (
        <p className="text-sm text-apt-text-muted">{config.emptyLabel}</p>
      ) : (
        <ul className="flex flex-col gap-1">
          {rows.map((row) => {
            const id = config.getId(row);
            const active = id === form.selectedId;
            return (
              <li key={id}>
                <button
                  type="button"
                  onClick={() => form.select(id)}
                  aria-current={active ? "true" : undefined}
                  className={cn(
                    "w-full rounded-md border border-l-2 px-3 py-2 text-left transition-colors",
                    active
                      ? "border-apt-border border-l-apt-gold bg-apt-surface-2 text-apt-text"
                      : "border-transparent text-apt-text-muted hover:bg-apt-surface-2/50 hover:text-apt-text",
                  )}
                >
                  <span className="block truncate text-sm font-medium">{config.getLabel(row)}</span>
                  <span className="block truncate text-xs text-apt-text-muted">
                    {config.getGroup(row)}
                  </span>
                </button>
              </li>
            );
          })}
        </ul>
      )}

      {form.editing && form.draft && (
        <div className="flex flex-col gap-3">
          <ButtonBar actions={actions} showCreate={false} ariaLabel={`${config.title} actions`} />
          {/* `resource`'s bar shows this beside Save; the `ui` one has no slot for it, and a grey
              Save that says nothing is the defect that put it there in the first place. */}
          {actions.blockedReason && (
            <p role="status" className="text-xs text-apt-text-muted">
              {actions.blockedReason}
            </p>
          )}
          <div key={form.detailKey}>
            {config.renderFields(form.draft, form.onChange, form.error)}
          </div>
        </div>
      )}

      {/* The confirm the shared bar usually brings with it. Same hook state, same modal. */}
      <AlertModal
        open={actions.deletePrompt != null}
        tone="error"
        title="Confirm deletion"
        description={actions.deletePrompt ?? undefined}
        confirmLabel="Delete"
        confirmVariant="destructive"
        cancelLabel="Cancel"
        busy={actions.deleting}
        onConfirm={() => actions.onConfirmDelete?.()}
        onCancel={() => actions.onCancelDelete?.()}
      />
    </section>
  );
}
