"use client";

import { useCallback, useState, type ReactElement } from "react";
import { CalendarRange } from "lucide-react";
import { Badge } from "@agenticdevelopertoolkit/ui/components/badge";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { EmptyState } from "@agenticdevelopertoolkit/ui/components/empty-state";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { Field } from "@agenticdevelopertoolkit/ui/blocks/field";
import { List, ListItem } from "@agenticdevelopertoolkit/ui/components/list";
import { Progress } from "@agenticdevelopertoolkit/ui/components/progress";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { useResourceList } from "@agentic-toolkit/data";
import {
  projectIterationsApi,
  type Iteration,
  type IterationWorkItem,
} from "@agentic-toolkit/data/projects";
import {
  CreateResourceDialog,
  DetailSection,
  FeatureTitle,
  MasterDetailLeaf,
  useMasterDetailForm,
  useMasterDetailLevel,
  useRecordAffordance,
  type TopicLeaf,
} from "@agentic-toolkit/resource";
import { ItemKey } from "./ItemKey";
import {
  IterationDetail,
  iterationBlank,
  iterationDiffers,
  iterationNormalize,
  iterationToInput,
  iterationValidate,
  type IterationDraft,
} from "./IterationDetail";
import {
  categoryVariant,
  estimateScaleIsSummable,
  estimateScaleLabel,
  iterationDateRange,
  iterationStateMeta,
} from "./helpers";

/**
 * ITERATIONS — the workspace's time-boxes, as a master/detail topic.
 *
 * The pane is reached through a project, but the boxes it lists are NOT the project's: an
 * iteration belongs to a WORKSPACE, so one fortnight holds cards from every board its owner
 * runs. That is the whole reason the feature exists — a team's sprint does not stop at a board
 * boundary — and it is why the detail below shows cards from projects other than the one you
 * arrived through, each labelled with the board it came from. Nothing here filters to the
 * current project: doing so would quietly turn a workspace cycle into a per-board one and make
 * the rollover's count disagree with what it moved.
 *
 * It is built on the shared master/detail substrate rather than a hand-rolled list + form, so it
 * inherits the behaviours every other converted pane already has: the list is PUBLISHED as a rail
 * level of the one stack (never a nested list inside the leaf), selection is the URL's leaf
 * segment and therefore deep-linkable, the unsaved-work guard is registered while the draft is
 * dirty, and create is a MODAL over a real record rather than a blank detail pane.
 *
 * The one thing the substrate does not cover is what makes a cycle a workflow rather than a
 * label: closing it. That lives in {@link IterationCards}, next to the cards whose count it
 * quotes.
 */

/* ── The cards in one box ─────────────────────────────────────────────────── */

/** The two categories that mean a card is out of play — the same pair the server's rollover
 *  reads, named once here so the count under the button and the number it reports back cannot
 *  drift apart. */
function isOpen(card: IterationWorkItem): boolean {
  return card.statusCategory !== "done" && card.statusCategory !== "canceled";
}

/**
 * The box's SIZE rollup, or `null` when there is nothing honest to say about it.
 *
 * A box spans boards, and an estimate is a number in the units ITS OWN board named — so the
 * total of a box is only meaningful once every card in it was sized on the same scale. That is
 * the whole reason each row carries its project's `estimateScale`: without it a reader would add
 * a fibonacci 8 to a t-shirt 3 and report 11 of something.
 *
 * Three answers, and the middle one is the point of the function:
 *  - `null` — no board in this box estimates at all, so no line appears.
 *  - `{ summable: false, reason }` — there IS sizing here but it cannot be added up, either
 *    because the boards disagree or because the scale is t-shirts (whose values are ladder
 *    POSITIONS, so XS is 0 and a sum understates three small cards as no work). The sentence
 *    says which, rather than quietly showing card counts and letting the reader assume nobody
 *    sized anything.
 *  - `{ summable: true, … }` — one summable scale, with `unsized` naming how many cards
 *    contributed nothing, because a total is only as trustworthy as its coverage. Every
 *    summable scale is a ladder of POINTS (that is what makes it summable), so the total needs
 *    no unit beyond that word and the scale's own name is not carried here.
 */
type SizeRollup =
  | { summable: false; reason: string }
  | { summable: true; done: number; total: number; unsized: number };

function sizeRollup(cards: IterationWorkItem[]): SizeRollup | null {
  const scales = [...new Set(cards.map((c) => c.estimateScale))].filter((s) => s !== "none");
  if (scales.length === 0) return null;
  if (scales.length > 1) {
    return {
      summable: false,
      reason: `The boards in this iteration size on different scales (${scales
        .map(estimateScaleLabel)
        .join(", ")}), so their sizes are not added up.`,
    };
  }
  const scale = scales[0]!;
  if (!estimateScaleIsSummable(scale)) {
    return {
      summable: false,
      reason: `${estimateScaleLabel(scale)} are steps on a ladder rather than amounts, so they are not added up.`,
    };
  }
  // A card counts toward the total only if it was sized ON THIS SCALE — a card from a board that
  // does not estimate carries no comparable number even when it happens to hold one, and is
  // reported as unsized rather than folded into a total it does not belong to.
  const sized = cards.filter((c) => c.estimate !== null && c.estimateScale === scale);
  const sum = (list: IterationWorkItem[]) => list.reduce((n, c) => n + (c.estimate ?? 0), 0);
  return {
    summable: true,
    done: sum(sized.filter((c) => !isOpen(c))),
    total: sum(sized),
    unsized: cards.length - sized.length,
  };
}

/** The rollover's destination, as the Select's value. A box is its id; the backlog is the empty
 *  string, because `null` is not a thing an `<option>` can carry — and the backlog is a real
 *  destination, not the absence of one. */
const BACKLOG = "";

function IterationCards({
  iteration,
  others,
  onRolledOver,
}: {
  iteration: Iteration;
  /** Every OTHER live box in the workspace — the rollover's candidate destinations. */
  others: Iteration[];
  /** Re-read the boxes after a rollover: the cards moved into another one. */
  onRolledOver: () => Promise<void> | void;
}): ReactElement {
  const load = useCallback(() => projectIterationsApi.workItems(iteration.id), [iteration.id]);
  const { items, reload, error } = useResourceList<IterationWorkItem>(
    `iteration:${iteration.id}:work-items`,
    load,
  );
  const cards = items ?? [];
  const open = cards.filter(isOpen);
  const done = cards.length - open.length;
  const pct = cards.length === 0 ? 0 : Math.round((done / cards.length) * 100);
  const sizes = sizeRollup(cards);

  const [destination, setDestination] = useState<string>(BACKLOG);
  const [rolling, setRolling] = useState(false);
  const [rollError, setRollError] = useState<string | null>(null);
  // What the last rollover actually did, in the server's own numbers. Kept until the next one:
  // the cards leave the list, so without this the only evidence of a successful sweep would be
  // a section that emptied itself.
  const [result, setResult] = useState<string | null>(null);

  const state = iterationStateMeta(iteration.state);

  async function rollover(): Promise<void> {
    setRolling(true);
    setRollError(null);
    setResult(null);
    try {
      const to = destination === BACKLOG ? null : destination;
      const { moved } = await projectIterationsApi.rollover(iteration.id, to);
      const where = to === null ? "the backlog" : (others.find((o) => o.id === to)?.name ?? "another iteration");
      setResult(
        moved === 0
          ? `Nothing to roll over — every card in ${iteration.name} is done or canceled.`
          : `Moved ${moved} card${moved === 1 ? "" : "s"} to ${where}.`,
      );
      await reload().catch(() => {});
      await onRolledOver();
    } catch (e) {
      setRollError(e instanceof Error ? e.message : "Failed to roll over.");
    } finally {
      setRolling(false);
    }
  }

  return (
    <>
      <DetailSection
        title="Cards"
        action={<Badge variant={state.variant}>{state.label}</Badge>}
      >
        <ErrorText error={error} />
        {items === null ? (
          error ? null : (
            <p className="text-sm text-apt-text-muted">Loading…</p>
          )
        ) : cards.length === 0 ? (
          <EmptyState
            title="No cards in this iteration."
            description="Commit work to it from a card's Iteration field."
          />
        ) : (
          <div className="flex flex-col gap-3">
            <div className="flex flex-col gap-1.5">
              <div className="flex items-baseline justify-between gap-3 text-sm">
                <span className="text-apt-text">
                  {cards.length} card{cards.length === 1 ? "" : "s"}
                </span>
                <span className="text-apt-text-muted">
                  {done} done · {open.length} open
                </span>
              </div>
              <Progress
                value={pct}
                aria-label={`${pct}% of this iteration's cards are done or canceled`}
              />
              {/* The bar above stays a CARD count — every box has cards, and only some have
                  sizes, so the one figure that is always available is the one that gets the
                  graphic. Sizes read as a sentence underneath, including when they cannot be
                  added up. */}
              {sizes === null ? null : (
                <p className="text-xs text-apt-text-muted">
                  {sizes.summable
                    ? `${sizes.done} of ${sizes.total} points done` +
                      (sizes.unsized > 0
                        ? ` · ${sizes.unsized} card${sizes.unsized === 1 ? "" : "s"} unsized`
                        : "")
                    : sizes.reason}
                </p>
              )}
            </div>
            <List>
              {cards.map((card) => (
                <ListItem key={card.id} className="justify-between">
                  <div className="flex min-w-0 items-center gap-2">
                    <ItemKey itemKey={card.itemKey} />
                    <span className="truncate text-sm text-apt-text">{card.title}</span>
                    {/* The board, because this ONE list spans them — the same reason the row
                        carries its own key prefix. */}
                    <span className="hidden truncate text-xs text-apt-text-muted sm:inline">
                      {card.projectName}
                    </span>
                  </div>
                  <Badge variant={categoryVariant(card.statusCategory)}>{card.statusName}</Badge>
                </ListItem>
              ))}
            </List>
          </div>
        )}
      </DetailSection>

      <DetailSection title="Close cycle">
        <div className="flex max-w-xl flex-col gap-3">
          <p className="text-sm text-apt-text-muted">
            Move everything that did not finish out of {iteration.name}. A card counts as
            finished when its column is done or canceled — everything else moves, the backlog
            included.
          </p>
          <div className="flex flex-wrap items-end gap-3">
            <Field label="Move unfinished cards to" className="min-w-56 flex-1">
              <Select
                value={destination}
                onChange={(e) => {
                  setRollError(null);
                  setResult(null);
                  setDestination(e.target.value);
                }}
              >
                <option value={BACKLOG}>Backlog</option>
                {others.map((o) => (
                  <option key={o.id} value={o.id}>
                    {o.name}
                  </option>
                ))}
              </Select>
            </Field>
            <Button
              onClick={() => void rollover()}
              // Disabled on an empty box rather than hidden: the control is part of what an
              // iteration IS, and a button that disappears once the work is done reads as a
              // feature that broke.
              disabled={rolling || items === null || open.length === 0}
            >
              {open.length === 0
                ? "Nothing to roll over"
                : `Roll over ${open.length} card${open.length === 1 ? "" : "s"}`}
            </Button>
          </div>
          <ErrorText error={rollError} />
          {result && <p className="text-sm text-apt-text-muted">{result}</p>}
        </div>
      </DetailSection>
    </>
  );
}

/* ── The pane ─────────────────────────────────────────────────────────────── */

export function IterationsPane({
  title,
  leaf,
  workspaceSlug,
}: {
  title: string;
  /** The deep-linkable selection — which box is open (`…/iterations/<id>`). */
  leaf: TopicLeaf;
  /** The workspace whose boxes these are. Absent, the API answers with the caller's own reach,
   *  exactly as the project list does. */
  workspaceSlug?: string;
}): ReactElement {
  const renderRecordAffordance = useRecordAffordance();
  const [newOpen, setNewOpen] = useState(false);

  // The SAME cache key the Work Items surface reads its iteration picker from, so a box created
  // or renamed here is what the picker offers on the next mount rather than a stale copy.
  const load = useCallback(
    () => projectIterationsApi.list({ workspace: workspaceSlug }),
    [workspaceSlug],
  );
  const {
    items: iterations,
    reload,
    error: loadError,
    isFetching,
  } = useResourceList<Iteration>(`workspace:${workspaceSlug ?? ""}:iterations`, load);

  const ws = { workspace: workspaceSlug };
  const form = useMasterDetailForm<Iteration, IterationDraft>({
    items: iterations,
    getId: (i) => i.id,
    urlSelection: { selectedId: leaf.leafId, onSelect: leaf.onSelect },
    blank: iterationBlank,
    toInput: iterationToInput,
    validate: (draft, others, base) =>
      iterationValidate(draft, others.map((o) => o.name), base?.name),
    differs: iterationDiffers,
    normalize: iterationNormalize,
    create: (input) => projectIterationsApi.create(input, ws),
    update: (id, input) => projectIterationsApi.update(id, input),
    remove: (i) => projectIterationsApi.remove(i.id).then(() => undefined),
    // Names what deleting a box actually does, which is the thing that makes it safe: the cards
    // are un-assigned, not deleted. "No iteration" is the backlog — an ordinary place for a card
    // to be — which is why this delete never refuses the way deleting a board COLUMN must.
    confirmDelete: (i) =>
      `Delete "${i.name}"? Its cards are not deleted — they move back to the backlog.`,
    refresh: reload,
    createLabel: "New iteration",
  });

  // PUBLISH the boxes as a deeper rail level + register the editor's unsaved-work guard.
  useMasterDetailLevel({
    id: "project-iterations-list",
    title: "Iterations",
    form,
    items: iterations,
    getId: (i) => i.id,
    getLabel: (i) => i.name,
    // Dates first, then where the box sits relative to today: the span is what tells two
    // similarly-named cycles apart, and the state is derived FROM it.
    getSublabel: (i) =>
      `${iterationDateRange(i.startDate, i.endDate)} · ${iterationStateMeta(i.state).label}`,
    itemIcon: <CalendarRange size={16} aria-hidden />,
    newLabel: "New iteration",
    leaf,
    emptyLabel: iterations === null ? "Loading…" : "No iterations yet.",
    // The spinner before "Iterations" — the only thing that says a revalidation is running behind
    // rows the cache already put on screen. `emptyLabel` covers the FIRST read and nothing after.
    busy: isFetching,
    onNew: () => setNewOpen(true),
    overviewHelp:
      "A time-box the whole workspace shares — one sprint holds work from every board its owner runs.",
  });

  const selected = form.selected;

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <FeatureTitle title={title} />
      <MasterDetailLeaf
        form={form}
        error={loadError}
        trailing={renderRecordAffordance?.({
          path: "/project/iterations/{id}",
          pathValues: { id: form.selectedId },
          title: "Iteration API",
        })}
        emptyTitle={
          iterations === null
            ? "Loading…"
            : "Select an iteration to edit, or create a new one."
        }
        renderDetail={(draft) => (
          <div key={form.detailKey} className="flex flex-col gap-6">
            <IterationDetail
              title="Iteration"
              draft={draft}
              onChange={form.onChange}
              error={form.error}
            />
            {/* Only for a SAVED box: the cards and the rollover both address it by id, which a
                draft being created does not have yet. */}
            {selected && (
              <IterationCards
                key={selected.id}
                iteration={selected}
                others={(iterations ?? []).filter((i) => i.id !== selected.id)}
                onRolledOver={reload}
              />
            )}
          </div>
        )}
      />
      {newOpen && (
        <CreateResourceDialog
          ariaLabel="New iteration"
          heading="New iteration"
          blank={iterationBlank}
          validate={(d) => iterationValidate(d, (iterations ?? []).map((i) => i.name))}
          create={(d) => projectIterationsApi.create(iterationNormalize(d), ws)}
          onClose={() => setNewOpen(false)}
          onCreated={(created) => {
            setNewOpen(false);
            void reload();
            leaf.onSelect(created.id);
          }}
          renderForm={(draft, onChange, error) => (
            <IterationDetail draft={draft} onChange={onChange} error={error} />
          )}
        />
      )}
    </div>
  );
}
