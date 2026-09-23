"use client";

import { useCallback, useState, type ReactNode } from "react";
import { Trash2 } from "lucide-react";
import { clientRefusal, useResourceList } from "@agentic-toolkit/data";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { TopicSelectHint, type TopicDetailItem, type TopicLevel } from "@agenticdevelopertoolkit/ui/blocks";
import {
  useStackLevel,
  useRailExitGuard,
  useMasterDetailForm,
  RecordSettingsPane,
  CreateResourceDialog,
  type TopicLeaf,
} from "@agentic-toolkit/resource";
import { sortByGroup } from "./group";

/** Everything one of the three per-game child collections needs to become a pane. */
export interface GameChildPaneConfig<TRow, TInput> {
  /** Stable level id + cache-key discriminator, e.g. "definitions". */
  collection: string;
  /** Rail heading, e.g. "Content". */
  listTitle: string;
  /** Singular noun for the select nudge and the New button, e.g. "definition". */
  itemNoun: string;
  icon: ReactNode;
  getId: (row: TRow) => string;
  getLabel: (row: TRow) => string;
  /** The field the list groups on — `kind` for definitions and mappings, `trigger` for
   *  effects. Shown as each row's sublabel and used as the sort's primary key. */
  getGroup: (row: TRow) => string;
  /** The row's `sort_order`. Orders each group AHEAD of the label, which is what makes the
   *  list explicitly orderable rather than alphabetical — the spec's named requirement for
   *  effects, where the schema says the order is load-bearing. All three child tables carry
   *  the column, so all three supply this. The ordering is EDITED in the detail form's own
   *  `sortOrder` field: there is no drag handle, and no reorder control that would have to
   *  write several rows at once against an API that does not exist yet. */
  getSort?: (row: TRow) => number;
  list: (gameId: string) => Promise<TRow[]>;
  create: (gameId: string, input: TInput) => Promise<TRow>;
  update: (id: string, input: TInput) => Promise<TRow>;
  remove: (id: string) => Promise<void>;
  /** The confirmation shown before `remove` runs. Required alongside `remove`, and not
   *  optional: `useMasterDetailForm` refuses to delete without BOTH, so a missing prompt
   *  is a silently dead Delete button rather than an unconfirmed one. */
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
  /** Anything that belongs BELOW the open row's own fields and needs the SAVED row rather
   *  than the draft — the definition detail's inline effects and connections. Given the row,
   *  never the draft, because those children are addressed by the row's id, and deliberately
   *  not rendered by the create dialog: a definition that does not exist yet has no id for a
   *  child to point at. */
  renderExtra?: (row: TRow) => ReactNode;
  /** Copy for the nudge shown while nothing is selected. */
  hint: string;
}

/**
 * The shared shape of Content, Connections and Effects: a per-game collection published as
 * a stack level (so selecting a row deep-links it, `…/<topic>/<rowId>`) with the selected
 * row's editor in the pane body. Creation is a MODAL over the stack, opened by the level's
 * `+` — the fleet's `must-create-in-modal` recipe, same as team members.
 *
 * Rows are ORDERED by group rather than headed by one: see `sortByGroup`.
 *
 * With no game selected the list is empty by construction (nothing is fetched), so the pane
 * renders under the workspace's unselected landing without asking the backend anything.
 */
export function GameChildPane<TRow, TInput>({
  gameId,
  leaf,
  title,
  config,
}: {
  gameId?: string;
  leaf?: TopicLeaf;
  title?: ReactNode;
  config: GameChildPaneConfig<TRow, TInput>;
}) {
  const [newOpen, setNewOpen] = useState(false);

  const load = useCallback(
    () => (gameId ? config.list(gameId) : Promise.resolve([] as TRow[])),
    // `config` is a literal rebuilt each render by the topic factory; only its identity would
    // change, never its behaviour, so the fetch depends on the game alone.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [gameId],
  );
  const {
    items: rows,
    reload,
    error: loadError,
    isFetching,
  } = useResourceList<TRow>(`game:${gameId ?? ""}:${config.collection}`, load);

  // Swallowed on purpose: each caller re-reads AFTER its own write already succeeded, so a
  // failed re-read must not be reported as a failed save. The failure still lands in the
  // hook's `error`, which the banner below renders.
  const refresh = useCallback(() => reload().catch(() => {}), [reload]);

  const ordered = sortByGroup(rows ?? [], config.getGroup, config.getLabel, config.getSort);
  const selectedId = leaf?.leafId ?? null;
  const selected = selectedId ? ordered.find((r) => config.getId(r) === selectedId) ?? null : null;

  const form = useMasterDetailForm<TRow, TInput>({
    items: ordered,
    getId: config.getId,
    blank: config.blank,
    toInput: config.toInput,
    validate: config.validate,
    differs: config.differs,
    normalize: config.normalize,
    update: config.update,
    // Delete belongs to the form, not to this pane. The hook owns the whole two-step flow —
    // request opens the shared AlertModal, confirm performs the remove, clears the selection
    // (through `urlSelection`, so the leaf segment goes with it) and re-reads the list. A
    // hand-rolled Delete here got the destructive half and none of the confirmation.
    remove: (row) => config.remove(config.getId(row)),
    confirmDelete: config.confirmDelete,
    refresh,
    urlSelection: leaf ? { selectedId, onSelect: (id) => leaf.onSelect(id) } : undefined,
  });

  const items: TopicDetailItem[] = ordered.map((row) => ({
    id: config.getId(row),
    label: config.getLabel(row),
    // The group, on every row — this is what makes the ordering READ as grouping.
    sublabel: config.getGroup(row) || undefined,
    icon: config.icon,
  }));

  const level: TopicLevel = {
    id: `${config.collection}-list`,
    title: config.listTitle,
    items,
    selectedId,
    onSelect: (id) => leaf?.onSelect(id),
    onClear: () => leaf?.onSelect(null),
    itemNoun: config.itemNoun,
    // A failed read leaves `rows` null exactly as a pending one does, so "Loading…" alone
    // would spin here forever over a read that has already given up.
    emptyLabel:
      rows !== null
        ? `No ${config.listTitle.toLowerCase()} yet.`
        : loadError
          ? `Couldn’t load ${config.listTitle.toLowerCase()}.`
          : "Loading…",
    busy: isFetching,
    onNew: gameId ? () => setNewOpen(true) : undefined,
    newLabel: `New ${config.itemNoun}`,
  };
  // The level is built by hand rather than by `useMasterDetailLevel` for two reasons that hook
  // cannot express: the rows are GROUP-ORDERED (`sortByGroup`, above), and the `+` is gated on a
  // game being selected — the hook's `onNew` falls back to an INLINE create, and creation here is
  // a modal. So the guard half of that hook is registered explicitly; without it a dirty draft in
  // this pane is discarded silently on Back, breadcrumb-up, or a re-click of the topic.
  useStackLevel(level);
  useRailExitGuard(form.dirty ? form.guard : null);

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      {/* RecordSettingsPane below gets no `activeId` — deliberately. Its effect there calls
          `form.select(activeId)` to bind the form to an externally-chosen record, which is what
          the five single-record panes need because nothing else carries that selection in. This
          pane is URL-driven (`urlSelection` above), and in that mode `useMasterDetailForm`
          already re-hydrates the draft itself whenever the id changes from outside the hook —
          deep-link, back, forward. Passing `activeId` as well would route `select` back through
          `leaf.onSelect` → `router.push` for a URL the rail had just pushed, costing a second
          history entry on every row click. */}
      {selected ? (
        <RecordSettingsPane
          form={form}
          items={ordered}
          getId={config.getId}
          title={title}
          loadError={loadError}
          emptyLabel={config.hint}
          // RecordSettingsPane hides ButtonBar's own Delete (`showDelete={false}`) but still
          // renders its confirm modal, so the button rides in `trailing` and the modal is free.
          trailing={
            <Button
              size="sm"
              variant="destructive-ghost"
              onClick={form.actions.onDelete}
              disabled={!form.actions.canDelete}
            >
              <Trash2 data-icon="inline-start" />
              Delete
            </Button>
          }
          renderDetail={(draft) => (
            <div key={form.detailKey} className="flex flex-col gap-8">
              {config.renderFields(draft, form.onChange, form.error)}
              {/* `selected`, not the draft: an edge or an effect is addressed by the SAVED
                  row's id, and an unsaved rename of the parent changes neither. */}
              {selected ? config.renderExtra?.(selected) : null}
            </div>
          )}
        />
      ) : (
        <section className="flex min-w-0 flex-1 flex-col gap-3 overflow-y-auto px-6 py-8">
          <ErrorText error={loadError} />
          {rows === null && !loadError ? (
            <p className="text-sm text-apt-text-muted">Loading…</p>
          ) : (
            <TopicSelectHint title={`Select a ${config.itemNoun}, or add one.`}>
              {config.hint}
            </TopicSelectHint>
          )}
        </section>
      )}

      {newOpen && (
        <CreateResourceDialog<TInput, TRow>
          ariaLabel={`New ${config.itemNoun}`}
          heading={`New ${config.itemNoun}`}
          blank={config.blank}
          validate={(d) => config.validate(config.normalize(d), ordered, null)}
          create={(d) => {
            // A refusal the operator caused, so it carries a 4xx — see `clientRefusal`. The
            // rail cannot open this dialog without a game, so this is the unreachable guard.
            if (!gameId) return Promise.reject(clientRefusal("Select a game first."));
            return config.create(gameId, config.normalize(d));
          }}
          onClose={() => setNewOpen(false)}
          onCreated={(row) => {
            setNewOpen(false);
            refresh();
            leaf?.onSelect(config.getId(row));
          }}
          renderForm={(draft, onChange, error) => config.renderFields(draft, onChange, error)}
        />
      )}
    </div>
  );
}
