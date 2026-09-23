"use client";

import { useCallback, useMemo, useState, type ReactElement } from "react";
import { Flag } from "lucide-react";
import { Badge } from "@agenticdevelopertoolkit/ui/components/badge";
import { EmptyState } from "@agenticdevelopertoolkit/ui/components/empty-state";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { List, ListItem } from "@agenticdevelopertoolkit/ui/components/list";
import { Progress } from "@agenticdevelopertoolkit/ui/components/progress";
import { useResourceList } from "@agentic-toolkit/data";
import {
  projectMilestonesApi,
  projectWorkItemsApi,
  projectsApi,
  milestoneProgress,
  type Milestone,
  type ProjectStatus,
  type WorkItem,
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
  MilestoneDetail,
  milestoneBlank,
  milestoneDiffers,
  milestoneNormalize,
  milestoneToInput,
  milestoneToPatch,
  milestoneValidate,
  type MilestoneDraft,
} from "./MilestoneDetail";
import { dateLabel, daysUntil, statusMeta } from "./helpers";
import { DEFAULT_ITEM_WORDS, type ItemWords } from "./vocabulary";

/**
 * MILESTONES — the project's own plan, as a master/detail topic.
 *
 * The sibling of Iterations, and the contrast with it is the whole point: an iteration is a
 * WORKSPACE's time-box and answers "what are we doing this fortnight", while a milestone belongs to
 * ONE board and answers "what has to be true before we can say this is done". So a card carries
 * both, independently — the same card is in Sprint 12 and counts toward Public Beta — and neither
 * field is derivable from the other. That is why this pane exists rather than a second view of the
 * iterations one.
 *
 * Built on the shared master/detail substrate for the same reasons Iterations is: the list is
 * PUBLISHED as a rail level of the one stack, selection is the URL's leaf segment and therefore
 * deep-linkable, the unsaved-work guard is registered while the draft is dirty, and create is a
 * MODAL over a real record rather than a blank detail pane.
 *
 * Nothing here writes progress. A milestone's counts are derived server-side from the cards
 * pointing at it, so a card moving column changes this pane's numbers without this pane being
 * involved — which is also why a stale count is not a state it can get into.
 */

/* ── The cards counting toward one milestone ──────────────────────────────── */

/**
 * The cards, and how far along the point is.
 *
 * Two sources, deliberately, and they answer two different questions. The BAR quotes the server's
 * own `counts` through {@link milestoneProgress} — the one committed answer to "does a canceled
 * card count as unfinished" (it does not, in either half), written down in the data package so two
 * panes cannot disagree. The ROWS come from the project's work-item list, on the SAME cache key the
 * Work Items topic reads, so opening this pane costs no extra fetch and the cards are the cards
 * that surface already has.
 *
 * They are read from the same board, so they agree; where they could differ is a card the caller
 * cannot see, which the server counts and this list cannot show. That is the honest way round: the
 * total is the plan's real size, and the rows are what this reader may open.
 */
function MilestoneCards({
  milestone,
  items,
  itemsError,
  statuses,
  words,
}: {
  milestone: Milestone;
  /** the project's cards, already loaded by the shared list cache. */
  items: WorkItem[] | null;
  /** why there are no cards to show, when the shared read FAILED. Null is not enough on its own:
   *  a failed read leaves `items` null forever, and "Loading…" would then be a spinner that never
   *  resolves. */
  itemsError: string | null;
  statuses: ProjectStatus[];
  /** what this board calls those cards. */
  words: ItemWords;
}): ReactElement {
  const cards = useMemo(
    () => (items ?? []).filter((w) => w.milestoneId === milestone.id),
    [items, milestone.id],
  );
  const progress = milestoneProgress(milestone);
  const pct = progress === null ? 0 : Math.round(progress.ratio * 100);
  const canceled = milestone.counts?.canceled ?? 0;

  return (
    <DetailSection
      title={words.manyTitle}
      action={
        milestone.targetDate ? (
          <span className="text-sm text-apt-text-muted">{dateLabel(milestone.targetDate)}</span>
        ) : (
          <span className="text-sm text-apt-text-dim">No target date</span>
        )
      }
    >
      {items === null && itemsError === null ? (
        <p className="text-sm text-apt-text-muted">Loading…</p>
      ) : (
        <div className="flex flex-col gap-3">
          {/* The bar renders even at zero cards: an empty milestone is 0 % of a plan that exists,
              and hiding the bar would make a fresh milestone look like a broken one. */}
          <div className="flex flex-col gap-1.5">
            <div className="flex items-baseline justify-between gap-3 text-sm">
              <span className="text-apt-text">
                {/* `words.count`, not `card${n === 1 ? "" : "s"}`: the suffix idiom is correct for
                    exactly one noun and wrong for every board with an irregular plural. */}
                {progress === null
                  ? words.count(cards.length)
                  : `${progress.done} of ${progress.total} done`}
              </span>
              {/* Canceled cards are outside the bar entirely, so the count that IS shown has to
                  say so rather than leaving the reader to reconcile two numbers. It is read from
                  the server's own tally, not as `rows − total`: those two are scoped differently
                  (a card the caller cannot see is in one and not the other), so subtracting them
                  would label a permissions gap as a cancellation. */}
              {canceled > 0 ? (
                <span className="text-apt-text-muted">{canceled} canceled</span>
              ) : null}
            </div>
            <Progress
              value={pct}
              aria-label={`${pct}% of the ${words.many} counting toward ${milestone.name} are done`}
            />
          </div>
          {itemsError !== null ? (
            // The BAR above still stands — it is the server's own tally and did not fail — so this
            // says only what is actually missing: the rows. Claiming "nothing counts toward this
            // milestone" here would be a fact the pane does not have.
            <ErrorText error={itemsError} />
          ) : cards.length === 0 ? (
            <EmptyState
              title="Nothing counts toward this milestone yet."
              description={`Point work at it from a ${words.one}'s Milestone field.`}
            />
          ) : (
            <List>
              {cards.map((card) => {
                const status = statusMeta(card.statusId, statuses);
                return (
                  <ListItem key={card.id} className="justify-between">
                    <div className="flex min-w-0 items-center gap-2">
                      <ItemKey itemKey={card.itemKey} />
                      <span className="truncate text-sm text-apt-text">{card.title}</span>
                    </div>
                    <Badge variant={status.variant}>{status.label}</Badge>
                  </ListItem>
                );
              })}
            </List>
          )}
        </div>
      )}
    </DetailSection>
  );
}

/* ── The rail row's second line ───────────────────────────────────────────── */

/**
 * A milestone's one-line summary: when it is aimed at, and how far along it is.
 *
 * The date comes first because it is what tells two similarly-named points apart, and a date
 * already behind us says so IN WORDS rather than only by colour — a rail sublabel has no room for
 * a badge, and "overdue" is exactly the fact a reader must not have to infer. A point whose cards
 * are all finished is never overdue: the plan was met, the calendar just moved on.
 */
export function milestoneSublabel(m: Milestone): string {
  const progress = milestoneProgress(m);
  const done = progress !== null && progress.total > 0 && progress.done === progress.total;
  const delta = m.targetDate ? daysUntil(m.targetDate) : null;
  const when =
    m.targetDate === null
      ? "No date"
      : delta !== null && delta < 0 && !done
        ? `${dateLabel(m.targetDate)} · overdue`
        : dateLabel(m.targetDate);
  return progress === null ? when : `${when} · ${progress.done}/${progress.total} done`;
}

/* ── The pane ─────────────────────────────────────────────────────────────── */

export function MilestonesPane({
  projectId,
  title,
  leaf,
  words = DEFAULT_ITEM_WORDS,
}: {
  projectId: string;
  title: string;
  /** The deep-linkable selection — which point is open (`…/milestones/<id>`). */
  leaf: TopicLeaf;
  /** What this board calls the cards that count toward a point. */
  words?: ItemWords;
}): ReactElement {
  const renderRecordAffordance = useRecordAffordance();
  const [newOpen, setNewOpen] = useState(false);

  const load = useCallback(() => projectMilestonesApi.list(projectId), [projectId]);
  const {
    items: milestones,
    reload,
    error: loadError,
    isFetching,
  } = useResourceList<Milestone>(`project:${projectId}:milestones`, load);

  // The two lists the detail reads, on the SAME cache keys the Work Items topic uses — so arriving
  // here from that surface costs nothing, and so does going back.
  //
  // Sharing an entry is also why the CARDS fetcher does not swallow its own failure the way the
  // statuses one does: a `.catch(() => [])` writes a fabricated SUCCESS into the shared entry, and
  // the Work Items surface — whose whole subject is those cards — would then read "this board is
  // empty" with no error to show, and go on reading it for the five minutes the entry stays fresh.
  // The failure is kept, and each reader decides what to do with it; this pane's is `itemsError`
  // below. Statuses stay soft because every reader of that key treats them as decoration.
  const loadItems = useCallback(
    () => projectWorkItemsApi.listForProject(projectId),
    [projectId],
  );
  const loadStatuses = useCallback(
    () => projectsApi.statuses.list(projectId).catch(() => [] as ProjectStatus[]),
    [projectId],
  );
  const { items: workItems, error: workItemsError } = useResourceList<WorkItem>(
    `project:${projectId}:work-items`,
    loadItems,
  );
  const { items: statusRows } = useResourceList<ProjectStatus>(
    `project:${projectId}:statuses`,
    loadStatuses,
  );

  const form = useMasterDetailForm<Milestone, MilestoneDraft>({
    items: milestones,
    getId: (m) => m.id,
    urlSelection: { selectedId: leaf.leafId, onSelect: leaf.onSelect },
    blank: milestoneBlank,
    toInput: milestoneToInput,
    validate: (draft, others, base) =>
      milestoneValidate(draft, others.map((o) => o.name), base?.name),
    differs: milestoneDiffers,
    normalize: milestoneNormalize,
    create: (input) => projectMilestonesApi.create(projectId, milestoneToPatch(input)),
    update: (id, input) => projectMilestonesApi.update(projectId, id, milestoneToPatch(input)),
    remove: (m) => projectMilestonesApi.remove(projectId, m.id).then(() => undefined),
    // Names what deleting a point actually does, which is the thing that makes it safe: the cards
    // are DETACHED, not deleted. "Counts toward no milestone" is an ordinary state for a card —
    // which is why this delete never refuses the way deleting a board COLUMN must.
    confirmDelete: (m) =>
      `Delete "${m.name}"? Its ${words.many} are not deleted — they stop counting toward any milestone.`,
    refresh: reload,
    createLabel: "New milestone",
  });

  // PUBLISH the plan as a deeper rail level + register the editor's unsaved-work guard.
  useMasterDetailLevel({
    id: "project-milestones-list",
    title: "Milestones",
    form,
    items: milestones,
    getId: (m) => m.id,
    getLabel: (m) => m.name,
    getSublabel: milestoneSublabel,
    itemIcon: <Flag size={16} aria-hidden />,
    newLabel: "New milestone",
    leaf,
    emptyLabel: milestones === null ? "Loading…" : "No milestones yet.",
    // The spinner before "Milestones" — the only thing that says a revalidation is running behind
    // rows the cache already put on screen. `emptyLabel` covers the FIRST read and nothing after.
    busy: isFetching,
    onNew: () => setNewOpen(true),
    overviewHelp: `A point in this project's plan — what has to be true, and when. ${words.manyCap} count toward it.`,
  });

  const selected = form.selected;

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <FeatureTitle title={title} />
      <MasterDetailLeaf
        form={form}
        error={loadError}
        trailing={renderRecordAffordance?.({
          path: "/project/projects/{id}/milestones",
          pathValues: { id: projectId },
          title: "Milestones API",
        })}
        emptyTitle={
          milestones === null ? "Loading…" : "Select a milestone to edit, or create a new one."
        }
        renderDetail={(draft) => (
          <div key={form.detailKey} className="flex flex-col gap-6">
            <MilestoneDetail
              title="Milestone"
              draft={draft}
              onChange={form.onChange}
              error={form.error}
            />
            {/* Only for a SAVED point: the cards address it by id, which a draft being created
                does not have yet. */}
            {selected && (
              <MilestoneCards
                key={selected.id}
                milestone={selected}
                items={workItems}
                itemsError={workItemsError}
                statuses={statusRows ?? []}
                words={words}
              />
            )}
          </div>
        )}
      />
      {newOpen && (
        <CreateResourceDialog
          ariaLabel="New milestone"
          heading="New milestone"
          blank={milestoneBlank}
          validate={(d) => milestoneValidate(d, (milestones ?? []).map((m) => m.name))}
          create={(d) => projectMilestonesApi.create(projectId, milestoneToPatch(d))}
          onClose={() => setNewOpen(false)}
          onCreated={(created) => {
            setNewOpen(false);
            void reload();
            leaf.onSelect(created.id);
          }}
          renderForm={(draft, onChange, error) => (
            <MilestoneDetail draft={draft} onChange={onChange} error={error} />
          )}
        />
      )}
    </div>
  );
}
