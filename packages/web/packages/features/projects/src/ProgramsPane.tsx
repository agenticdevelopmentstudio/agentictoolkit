"use client";

import { useCallback, useState, type ReactElement } from "react";
import { Layers } from "lucide-react";
import { Badge } from "@agenticdevelopertoolkit/ui/components/badge";
import { EmptyState } from "@agenticdevelopertoolkit/ui/components/empty-state";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { List, ListItem } from "@agenticdevelopertoolkit/ui/components/list";
import { useResourceList } from "@agentic-toolkit/data";
import {
  projectProgramsApi,
  type Program,
  type Project,
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
import {
  ProgramDetail,
  programBlank,
  programDiffers,
  programNormalize,
  programToInput,
  programToPatch,
  programValidate,
  type ProgramDraft,
} from "./ProgramDetail";
import { dateLabel, healthMeta } from "./helpers";

/**
 * PROGRAMS — the layer ABOVE the boards, as a master/detail topic.
 *
 * Reached through a project, like Iterations and for the same reason, and like an iteration a
 * program is NOT the project's: it belongs to the WORKSPACE, and a board joins one. That is what
 * makes rolling several boards up meaningful, and it is why nothing here filters to the board you
 * arrived through — doing so would turn a workspace-wide roll-up into a per-board label.
 *
 * The relationship to a MILESTONE is the one worth being clear about, because both are "a plan":
 * a milestone is a POINT inside one board, a program is a CONTAINER over several. A board joins
 * exactly one program (its `programId`), and that field is edited from the board's own settings,
 * not from here — a membership is a fact about the board, so it is written where the board is.
 *
 * Built on the shared master/detail substrate, so it inherits the rail level, the deep-linkable
 * selection, the dirty-draft guard and the create-as-modal that every converted pane has.
 */

/* ── The boards under one program ─────────────────────────────────────────── */

/**
 * The member boards, each wearing its OWN health.
 *
 * Deliberately not folded into one verdict, which is the same call the API makes and for the same
 * reason: three at-risk boards and one off-track board have no honest single colour, and inventing
 * one would be this pane asserting a judgement nobody made. A reader who wants a summary knows
 * what their summary is for; this list does not.
 *
 * A board with no reported health reads as a SENTENCE rather than a fourth badge tone. "Nobody has
 * said" is the absence of a claim, not a claim of its own, and a grey pill next to three coloured
 * ones would be read as one.
 */
function ProgramProjects({ program }: { program: Program }): ReactElement {
  const load = useCallback(() => projectProgramsApi.projects(program.id), [program.id]);
  const { items, error } = useResourceList<Project>(
    `program:${program.id}:projects`,
    load,
  );
  const projects = items ?? [];

  return (
    <DetailSection
      title="Boards"
      action={
        <span className="text-sm text-apt-text-muted">
          {items === null ? "" : `${projects.length} board${projects.length === 1 ? "" : "s"}`}
        </span>
      }
    >
      <ErrorText error={error} />
      {items === null ? (
        error ? null : (
          <p className="text-sm text-apt-text-muted">Loading…</p>
        )
      ) : projects.length === 0 ? (
        <EmptyState
          title="No boards in this program yet."
          description="A board joins a program from its own Project settings — a membership is a fact about the board."
        />
      ) : (
        <List>
          {projects.map((p) => {
            const health = p.health ? healthMeta(p.health) : null;
            return (
              <ListItem key={p.id} className="justify-between">
                <div className="flex min-w-0 items-center gap-2">
                  <span className="truncate text-sm text-apt-text">{p.name}</span>
                  {p.targetDate && (
                    <span className="hidden whitespace-nowrap text-xs text-apt-text-muted sm:inline">
                      {dateLabel(p.targetDate)}
                    </span>
                  )}
                </div>
                {health ? (
                  <Badge variant={health.variant}>{health.label}</Badge>
                ) : (
                  <span className="whitespace-nowrap text-xs text-apt-text-dim">
                    No health reported
                  </span>
                )}
              </ListItem>
            );
          })}
        </List>
      )}
    </DetailSection>
  );
}

/* ── The rail row's second line ───────────────────────────────────────────── */

/** A program's span as one phrase. Both ends are optional and independent, so all four shapes get
 *  a reading — and a standing program says so in words rather than showing an empty line, which
 *  would look like data that failed to load. */
export function programSublabel(p: Program): string {
  if (p.startDate && p.targetDate) return `${dateLabel(p.startDate)} → ${dateLabel(p.targetDate)}`;
  if (p.targetDate) return `Due ${dateLabel(p.targetDate)}`;
  if (p.startDate) return `From ${dateLabel(p.startDate)}`;
  return "No dates";
}

/* ── The pane ─────────────────────────────────────────────────────────────── */

export function ProgramsPane({
  title,
  leaf,
  workspaceSlug,
}: {
  title: string;
  /** The deep-linkable selection — which program is open (`…/programs/<id>`). */
  leaf: TopicLeaf;
  /** The workspace whose programs these are. Absent, the API answers with the caller's own reach,
   *  exactly as the project and iteration lists do. */
  workspaceSlug?: string;
}): ReactElement {
  const renderRecordAffordance = useRecordAffordance();
  const [newOpen, setNewOpen] = useState(false);

  // The SAME cache key the project's settings read their program picker from, so a program created
  // or renamed here is what the picker offers on the next mount rather than a stale copy.
  const load = useCallback(
    () => projectProgramsApi.list({ workspace: workspaceSlug }),
    [workspaceSlug],
  );
  const {
    items: programs,
    reload,
    error: loadError,
    isFetching,
  } = useResourceList<Program>(`workspace:${workspaceSlug ?? ""}:programs`, load);

  const ws = { workspace: workspaceSlug };
  const form = useMasterDetailForm<Program, ProgramDraft>({
    items: programs,
    getId: (p) => p.id,
    urlSelection: { selectedId: leaf.leafId, onSelect: leaf.onSelect },
    blank: programBlank,
    toInput: programToInput,
    validate: (draft, others, base) =>
      programValidate(draft, others.map((o) => o.name), base?.name),
    differs: programDiffers,
    normalize: programNormalize,
    create: (input) => projectProgramsApi.create(programToPatch(input), ws),
    update: (id, input) => projectProgramsApi.update(id, programToPatch(input)),
    remove: (p) => projectProgramsApi.remove(p.id).then(() => undefined),
    // Names what deleting a program actually does, which is the thing that makes it safe: the
    // member boards are un-assigned, not deleted. "In no program" is an ordinary state for a
    // board, which is why this delete never refuses.
    confirmDelete: (p) =>
      `Delete "${p.name}"? Its boards are not deleted — they stop rolling up into any program.`,
    refresh: reload,
    createLabel: "New program",
  });

  // PUBLISH the programs as a deeper rail level + register the editor's unsaved-work guard.
  useMasterDetailLevel({
    id: "project-programs-list",
    title: "Programs",
    form,
    items: programs,
    getId: (p) => p.id,
    getLabel: (p) => p.name,
    getSublabel: programSublabel,
    itemIcon: <Layers size={16} aria-hidden />,
    newLabel: "New program",
    leaf,
    emptyLabel: programs === null ? "Loading…" : "No programs yet.",
    // The spinner before "Programs" — the only thing that says a revalidation is running behind
    // rows the cache already put on screen. `emptyLabel` covers the FIRST read and nothing after.
    busy: isFetching,
    onNew: () => setNewOpen(true),
    overviewHelp:
      "A roll-up over several boards — one initiative the whole workspace can see at once.",
  });

  const selected = form.selected;

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <FeatureTitle title={title} />
      <MasterDetailLeaf
        form={form}
        error={loadError}
        trailing={renderRecordAffordance?.({
          path: "/project/programs/{id}",
          pathValues: { id: form.selectedId },
          title: "Program API",
        })}
        emptyTitle={
          programs === null ? "Loading…" : "Select a program to edit, or create a new one."
        }
        renderDetail={(draft) => (
          <div key={form.detailKey} className="flex flex-col gap-6">
            <ProgramDetail
              title="Program"
              draft={draft}
              onChange={form.onChange}
              error={form.error}
            />
            {/* Only for a SAVED program: the member boards address it by id, which a draft being
                created does not have yet. */}
            {selected && <ProgramProjects key={selected.id} program={selected} />}
          </div>
        )}
      />
      {newOpen && (
        <CreateResourceDialog
          ariaLabel="New program"
          heading="New program"
          blank={programBlank}
          validate={(d) => programValidate(d, (programs ?? []).map((p) => p.name))}
          create={(d) => projectProgramsApi.create(programToPatch(d), ws)}
          onClose={() => setNewOpen(false)}
          onCreated={(created) => {
            setNewOpen(false);
            void reload();
            leaf.onSelect(created.id);
          }}
          renderForm={(draft, onChange, error) => (
            <ProgramDetail draft={draft} onChange={onChange} error={error} />
          )}
        />
      )}
    </div>
  );
}
