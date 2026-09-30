"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactElement,
  type ReactNode,
} from "react";
import { Activity, FileStack, HeartPulse, ListTodo, Trash2, Users } from "lucide-react";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { Badge } from "@agenticdevelopertoolkit/ui/components/badge";
import { EmptyState } from "@agenticdevelopertoolkit/ui/components/empty-state";
import { Field } from "@agenticdevelopertoolkit/ui/blocks/field";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { List, ListItem } from "@agenticdevelopertoolkit/ui/components/list";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Textarea } from "@agenticdevelopertoolkit/ui/components/textarea";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Disclosure } from "@agenticdevelopertoolkit/ui/components/disclosure";
import { InfoPanel } from "@agenticdevelopertoolkit/ui/blocks/info-panel";
import { StatCard } from "@agenticdevelopertoolkit/ui/blocks/stat-card";
import { StatList, StatListRow } from "@agenticdevelopertoolkit/ui/blocks/stat-list";
import {
  isConflict,
  useResourceItemQuery,
  useResourceItemWriter,
  useResourceList,
} from "@agentic-toolkit/data";
import {
  projectsApi,
  projectWorkItemsApi,
  projectArtifactsApi,
  projectActivityApi,
  projectProgramsApi,
  validateKeyPrefix,
  DEFAULT_ITEM_NOUN,
  DEFAULT_ITEM_NOUN_PLURAL,
  type Program,
  type Project,
  type ProjectActivity,
  type ProjectArtifact,
  type ProjectParticipant,
  type EstimateScale,
  type PriorityScale,
  type ProjectStatus,
  type WorkItem,
} from "@agentic-toolkit/data/projects";
import { FeatureTitle } from "@agentic-toolkit/resource";
import { AssigneePicker, fromOptionValue, toOptionValue } from "./AssigneePicker";
import { ProjectStatusUpdates } from "./ProjectStatusUpdates";
import {
  actionPhrase,
  actorText,
  categoryVariant,
  commentBody,
  dateLabel,
  dayIndex,
  daysUntil,
  healthMeta,
  relativeTime,
  todayIndex,
  ESTIMATE_SCALES,
  estimateScaleOptionLabel,
  PRIORITY_SCALES,
  priorityScaleOptionLabel,
  type BadgeVariant,
} from "./helpers";
import { itemWordsOf } from "./vocabulary";

/**
 * WHAT THE PROJECT IS — the Overview topic.
 *
 * A project is a PLACE, and this is its front door: what it is about, how much work is in it and
 * where that work stands, what material it holds, who is in it, and what has happened lately.
 * Everything here is a SUMMARY with a home elsewhere in the rail — Work Items, Contents, Activity
 * — so the reading is "here is the state of this place, and the rail is how you go into it". The
 * rail is the navigation; no panel here duplicates it as a link, which is how every other pane in
 * this package behaves.
 *
 * The pane used to be its settings form, which made the first thing you saw when you opened a
 * project a text box for renaming it. The form is still here in full, demoted into a closed
 * Disclosure near the bottom: editing a project's own record is a rare, deliberate act, and it was
 * crowding out the ninety per cent of visits that are asking how the project is doing.
 *
 * Every figure is derived CLIENT-SIDE from the same lists the other topics load, through the
 * shared `useResourceList` on the SAME cache keys — so opening Overview warms Work Items and
 * Contents (and vice versa) instead of re-fetching, and there is no summary endpoint to keep in
 * agreement with the lists it summarises.
 *
 * It renders its content inline (rather than publishing a stack level), so it slots straight into
 * the ResourceExplorer Overview topic pane and a plain render exercises it in tests.
 *
 * Note: the project's own `status` is a FREE-FORM lifecycle varchar (e.g. "active") with no
 * backend enum guard — a different axis from the per-project work-item board columns
 * (`statuses.list`). So it edits as a free-text Input, not a Select over the board columns (which
 * would mislabel the project with a column key like "todo").
 */

/** How many activity rows the summary shows. Enough to answer "is anything happening here", short
 *  enough that the Activity topic is still where you go to actually read the trail. */
const RECENT_ACTIVITY = 5;

/* ── Participant kind → Badge tone ────────────────────────────────────────── */
function kindVariant(kind: ProjectParticipant["participantKind"]): BadgeVariant {
  switch (kind) {
    case "customer":
      return "blue";
    case "persona":
      return "accent";
    case "team":
      return "orange";
    default:
      return "neutral";
  }
}

const KINDS: ProjectParticipant["participantKind"][] = ["customer", "persona", "team"];

/** The kinds a LEAD may be — the same three, and the backend's `project_lead_kind_chk` is what
 *  makes that list closed. Narrowing through this is what turns the assignee picker's opaque
 *  `${kind}:${id}` string back into the union the patch body wants, instead of a cast that would
 *  send whatever the option carried. */
function asLeadKind(kind: string): Project["leadKind"] {
  return (KINDS as string[]).includes(kind) ? (kind as Project["leadKind"]) : null;
}

/** "no program", as the Select's value. "" rather than a word, so it cannot collide with an id
 *  and so an unset draft field and "rolls up into nothing" are the same thing. */
const NO_PROGRAM = "";

/* ── Derived figures ──────────────────────────────────────────────────────── */

/** The work summary: how many items sit in each board CATEGORY, plus how many are past due.
 *
 *  Counted by category rather than by status, because the categories are the closed vocabulary
 *  every project shares — a project that renamed "In progress" to "Cooking" still reports its
 *  cooking cards as in flight, and a summary written against status LABELS would report nothing
 *  for it. An item whose statusId resolves to no status (a stale id) is counted in `unknown`
 *  rather than silently dropped, so the parts always sum to the whole.
 *
 *  OVERDUE is "has a due date strictly before today, and is not finished": `done` and `canceled`
 *  are both terminal, and a closed card with a past due date is history, not a problem. Today is
 *  the viewer's LOCAL day (see helpers.todayIndex), so the count changes when their date does. */
function workSummary(items: WorkItem[], statuses: ProjectStatus[]) {
  const category = new Map(statuses.map((s) => [s.id, s.category]));
  const counts = { backlog: 0, todo: 0, in_progress: 0, done: 0, canceled: 0, unknown: 0 };
  const today = todayIndex();
  let overdue = 0;
  for (const item of items) {
    const cat = category.get(item.statusId);
    if (cat) counts[cat] += 1;
    else counts.unknown += 1;
    if (cat === "done" || cat === "canceled") continue;
    const due = item.dueDate ? dayIndex(item.dueDate) : null;
    if (due !== null && due < today) overdue += 1;
  }
  const open = items.length - counts.done - counts.canceled;
  return { ...counts, open, total: items.length, overdue };
}

/** The material summary: how many links point each way, and how many of them no longer resolve.
 *
 *  `unresolved` is counted because it is the one number here that is a PROBLEM rather than a
 *  size: a link whose target was deleted still lists (Contents says so on the row), and a project
 *  quietly accumulating dead pointers is worth seeing from the front door. */
function materialSummary(artifacts: ProjectArtifact[]) {
  let ingested = 0;
  let produced = 0;
  let unresolved = 0;
  for (const a of artifacts) {
    if (a.direction === "produced") produced += 1;
    else ingested += 1;
    if (!a.target) unresolved += 1;
  }
  return { ingested, produced, unresolved, total: artifacts.length };
}

/* ── The plan, read-only ──────────────────────────────────────────────────── */

/**
 * The board's plan as one line under its description: when it runs, who is answerable for it, and
 * what it rolls up into.
 *
 * Read-only and up here, editable and down in the settings Disclosure — the same split the name
 * and description already get, for the same reason: these are facts a visitor wants in the first
 * two seconds and edits almost nobody makes. A board with none of them set renders NOTHING rather
 * than four dashes; an empty plan is an ordinary state, and a row of placeholders would read as a
 * form somebody failed to fill in.
 *
 * The target date is the one part that can carry alarm: a date already behind us on an unarchived
 * board is a slipped plan, and it says so. Nothing else here is coloured — a lead and a program
 * are memberships, not judgements.
 */
function PlanLine({
  project,
  programs,
}: {
  project: Project;
  /** the workspace's programs, for putting a NAME to `programId`. An id this reader cannot
   *  resolve is echoed rather than hidden — see below. */
  programs: Program[];
}): ReactElement | null {
  const parts: ReactNode[] = [];
  if (project.startDate) parts.push(`Started ${dateLabel(project.startDate)}`);
  if (project.targetDate) {
    const delta = daysUntil(project.targetDate);
    const late = delta !== null && delta < 0 && !project.archivedAt;
    parts.push(
      <span key="target" className={late ? "text-apt-red" : undefined}>
        {late ? `Target ${dateLabel(project.targetDate)} · overdue` : `Target ${dateLabel(project.targetDate)}`}
      </span>,
    );
  }
  if (project.leadKind && project.leadId) {
    parts.push(`Lead ${project.leadKind} · ${project.leadId}`);
  }
  if (project.programId) {
    // A program the reader cannot see still gets named by its id rather than dropped: "this board
    // rolls up somewhere you cannot open" is true and useful, and silence would read as "nowhere".
    const program = programs.find((p) => p.id === project.programId);
    parts.push(program ? `In ${program.name}` : `In program ${project.programId}`);
  }
  if (parts.length === 0) return null;

  return (
    <p className="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-apt-text-muted">
      {parts.map((part, i) => (
        <span key={i} className="flex items-center gap-2">
          {i > 0 && <span aria-hidden className="text-apt-text-dim">·</span>}
          {part}
        </span>
      ))}
    </p>
  );
}

/* ── Pane ─────────────────────────────────────────────────────────────────── */

export function ProjectOverviewPane({
  projectId,
  title,
  workspaceSlug,
  renderTransferOwnership,
}: {
  projectId: string;
  title: string;
  /** The owning workspace, for the PROGRAM picker — a board may only join a program under its own
   *  owner. Absent, the programs API answers from the caller's own reach, the same fallback the
   *  project list uses, so the picker still offers something true. */
  workspaceSlug?: string;
  /**
   * Host-injected Transfer Ownership section, rendered last in the pane. Absent on a standalone
   * feature site (`frontend/src/marketing/projects` mounts `ProjectsFeature` without it) — the
   * host owns the workspace list and the mutation.
   *
   * Handed the LOADED project rather than the editable draft below: `name` is a separate piece of
   * state that only re-syncs from a project row on load and after a save adopts the returned one,
   * so a typed-but-unsaved rename would otherwise reach the confirmation dialog as the object's
   * name while the server still knows it by the old one.
   */
  renderTransferOwnership?: (project: { id: string; name: string }) => ReactNode;
}): ReactElement {
  // THE project record, on ONE cache entry shared with the board and the triage queue — the two
  // other panes that read it for the same board's vocabulary and scales. Opening Settings after
  // the board costs no read at all: the record paints from the cache and the re-read settles
  // behind that paint.
  //
  // `useResourceItemQuery` (the bare query) rather than `useResourceItem`: the missing-item alert
  // it composes needs a read that can SAY the item is gone, and `projectsApi.get` returns null for
  // a 404 and for a 500 alike. Backing the user out of a board over a transient failure is worse
  // than the "Project not found." this has always shown, so the record keeps that empty state and
  // does not arm the alert. Narrowing the api's null-for-missing contract is not this change.
  const {
    item: project,
    isSettled,
    reload: reloadProject,
  } = useResourceItemQuery<Project | null>("project:projects", projectId, projectsApi.get);
  const writeProject = useResourceItemWriter<Project | null>("project:projects");

  // Editable settings draft (populated from the loaded project; re-synced when the
  // project changes — on load and after a successful save adopts the returned row).
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [status, setStatus] = useState("");
  const [color, setColor] = useState("");
  const [keyPrefix, setKeyPrefix] = useState("");
  const [estimateScale, setEstimateScale] = useState<EstimateScale>("none");
  const [priorityScale, setPriorityScale] = useState<PriorityScale>("standard");
  // What this board CALLS its cards. Two fields rather than one plus a suffix: English does not
  // pluralise reliably enough to guess ("story" → "storys"), and a board renaming its items is
  // exactly the moment a guess would be visible. They travel together — see the patch below.
  const [itemNoun, setItemNoun] = useState(DEFAULT_ITEM_NOUN);
  const [itemNounPlural, setItemNounPlural] = useState(DEFAULT_ITEM_NOUN_PLURAL);
  // The PLAN half of the same draft. Flat scalars like the rest of it: the two dates are the
  // native inputs' own "" -or- YYYY-MM-DD strings, the lead is the assignee picker's composite
  // `${kind}:${id}` codec, and the program is a bare id. Every one of the four is CLEARABLE, which
  // is why "" is a meaningful value here and not merely an unfilled box.
  const [startDate, setStartDate] = useState("");
  const [targetDate, setTargetDate] = useState("");
  const [lead, setLead] = useState("");
  const [programId, setProgramId] = useState(NO_PROGRAM);
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  // The participant add control (the roster itself is a shared resource list, below).
  const [kindDraft, setKindDraft] =
    useState<ProjectParticipant["participantKind"]>("customer");
  const [idDraft, setIdDraft] = useState("");
  const [adding, setAdding] = useState(false);
  const [addError, setAddError] = useState<string | null>(null);
  const [removingId, setRemovingId] = useState<string | null>(null);
  // A failed REMOVE. Separate from the hook's load error (which is about reading the roster) and
  // from `addError` (which belongs under the add control, not by the list).
  const [removeError, setRemoveError] = useState<string | null>(null);

  const mounted = useRef(true);
  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);

  /* ── The lists this pane summarises ────────────────────────────────────────
   * The SAME cache keys the topics that own these lists use, so the two directions of a
   * navigation both paint from cache: Overview → Work Items is instant, and so is the way back.
   * Every summary degrades SOFT here — each panel falls back to `?? []` and shows its own zero
   * state, because a project's front door should still tell you what it is when one of four
   * background reads is unavailable. That fallback is at the READ SITE, not in the fetcher, for
   * every key another topic also reads: work items, artifacts and programs all rethrow, because
   * those keys are the primary lists of the Work Items, Material and Programs topics — a
   * `.catch(() => [])` writes a fabricated SUCCESS into the SHARED entry, and those panes would
   * then say "there is nothing here", with no error, for as long as it stayed fresh. Only the two
   * reads nobody else owns swallow in their fetcher (the statuses and the activity HEAD — the
   * Activity topic reads a different, paginated key), where an empty answer fabricates nothing for
   * anyone. The project record itself is the exception to the softness: it IS the pane, so its
   * absence is the "not found" state. */
  const loadItems = useCallback(
    () => projectWorkItemsApi.listForProject(projectId),
    [projectId],
  );
  const loadStatuses = useCallback(
    () => projectsApi.statuses.list(projectId).catch(() => [] as ProjectStatus[]),
    [projectId],
  );
  const loadParticipants = useCallback(
    () => projectsApi.participants.list(projectId),
    [projectId],
  );
  const loadArtifacts = useCallback(() => projectArtifactsApi.list(projectId), [projectId]);
  // Newest-first, and only the head of the trail: the Activity topic owns the paginated read.
  const loadActivity = useCallback(
    () =>
      projectActivityApi
        .projectActivity(projectId, { limit: RECENT_ACTIVITY })
        .then((page) => page.rows)
        .catch(() => [] as ProjectActivity[]),
    [projectId],
  );

  const { items: itemRows } = useResourceList<WorkItem>(
    `project:${projectId}:work-items`,
    loadItems,
  );
  const { items: statusRows } = useResourceList<ProjectStatus>(
    `project:${projectId}:statuses`,
    loadStatuses,
  );
  // The roster is the one list this pane WRITES, so it keeps its error and its reload.
  const {
    items: participantRows,
    reload: reloadParticipants,
    error: participantsError,
  } = useResourceList<ProjectParticipant>(
    `project:${projectId}:participants`,
    loadParticipants,
  );
  const { items: artifactRows } = useResourceList<ProjectArtifact>(
    `project:${projectId}:artifacts`,
    loadArtifacts,
  );
  const { items: activityRows } = useResourceList<ProjectActivity>(
    `project:${projectId}:recent-activity`,
    loadActivity,
  );

  // The workspace's programs, for the membership picker below — the SAME cache key the Programs
  // topic reads, so joining a program here and opening that topic do not disagree. Degrades to an
  // empty picker HERE — a board is still worth editing when the roll-up list is briefly
  // unavailable, and the picker's orphan guard keeps the current membership selectable regardless
  // — but the failure is left in the shared entry for the Programs topic, which owns it, to show.
  const loadPrograms = useCallback(
    () => projectProgramsApi.list({ workspace: workspaceSlug }),
    [workspaceSlug],
  );
  const { items: programRows } = useResourceList<Program>(
    `workspace:${workspaceSlug ?? ""}:programs`,
    loadPrograms,
  );

  const participants = participantRows;
  const work = useMemo(
    () => workSummary(itemRows ?? [], statusRows ?? []),
    [itemRows, statusRows],
  );
  const material = useMemo(() => materialSummary(artifactRows ?? []), [artifactRows]);

  // Seed the editable draft from a project row — called when the load resolves and
  // after a save adopts the returned row (so a save clears the dirty state). Kept
  // imperative (seeded exactly when data arrives) rather than a derive-from-state
  // effect. Setters are stable, so this callback is stable.
  const seedDraft = useCallback((p: Project) => {
    setName(p.name);
    setDescription(p.description ?? "");
    setStatus(p.status);
    setColor(p.color);
    setKeyPrefix(p.keyPrefix);
    setEstimateScale(p.estimateScale);
    setPriorityScale(p.priorityScale);
    // Already defaulted by the mapper, so the draft never holds "" — an empty box here would read
    // as "this board has no word for its cards", which is not a state the record can be in.
    setItemNoun(p.itemNoun);
    setItemNounPlural(p.itemNounPlural);
    setStartDate(p.startDate ?? "");
    setTargetDate(p.targetDate ?? "");
    // The two halves of a lead are always both set or both null — the backend refuses half a
    // lead — so one composite string is a faithful carrier and not a lossy flattening.
    setLead(
      p.leadKind && p.leadId
        ? toOptionValue({ assigneeKind: p.leadKind, assigneeId: p.leadId })
        : "",
    );
    setProgramId(p.programId ?? NO_PROGRAM);
  }, []);

  // Seed the draft from the record ONCE per project — on the FIRST answer, whether that answer
  // came from the cache or the wire. Not on every change of the record: the read now settles a
  // second time behind the paint, and a health report re-reads it too, so re-seeding on identity
  // would wipe whatever someone had typed into the settings form seconds earlier. A save adopts
  // its own returned row explicitly (see `save`), which is the other half of the same rule.
  //
  // Seeded DURING RENDER, not in an effect: a render holding the record beside an unseeded draft
  // is a render in which every field reads as changed, and an effect would let that paint. A set
  // during a component's own render re-renders it before anything is committed, so that state
  // never reaches the screen.
  //
  // The render it replaces still RUNS to completion, though — React re-invokes the component after
  // this one returns, it does not abandon it mid-body — which is why `seeded` gates the diff below
  // rather than the render-phase set being the whole fix.
  const [seededFor, setSeededFor] = useState<string | null>(null);
  const seeded = project !== null && seededFor === projectId;
  if (project && seededFor !== projectId) {
    setSeededFor(projectId);
    seedDraft(project);
  }

  // Only PATCH the fields that actually changed (project routes patch, not put).
  //
  // Empty until the draft has been SEEDED from this record, not merely until the record exists.
  // The two are one render apart (see above), and diffing a blank draft against a real record
  // says every field changed: the form would report itself dirty and run its validators — which
  // reject the empty string — over a state nobody typed.
  const patch = useMemo(() => {
    if (!project || !seeded) return {};
    const next: {
      name?: string;
      description?: string;
      status?: string;
      color?: string;
      keyPrefix?: string;
      estimateScale?: EstimateScale;
      priorityScale?: PriorityScale;
      itemNoun?: string;
      itemNounPlural?: string;
      startDate?: string | null;
      targetDate?: string | null;
      leadKind?: Project["leadKind"];
      leadId?: string | null;
      programId?: string | null;
    } = {};
    if (name.trim() !== project.name) next.name = name.trim();
    if (description !== (project.description ?? "")) next.description = description;
    if (status !== project.status) next.status = status;
    if (color.trim() !== project.color) next.color = color.trim();
    if (estimateScale !== project.estimateScale) next.estimateScale = estimateScale;
    if (priorityScale !== project.priorityScale) next.priorityScale = priorityScale;
    // The two nouns travel as a PAIR, always both or neither — the backend refuses one without the
    // other, exactly as it refuses half a lead. So editing only the singular still sends both, and
    // the untouched half arrives unchanged rather than as a 400 about a field nobody touched.
    const nextNoun = itemNoun.trim();
    const nextNounPlural = itemNounPlural.trim();
    if (nextNoun !== project.itemNoun || nextNounPlural !== project.itemNounPlural) {
      next.itemNoun = nextNoun;
      next.itemNounPlural = nextNounPlural;
    }
    // Upper-cased on the way out, because `adh` and `ADH` are the same claim and the backend
    // stores only the upper form — sending the raw text would make the field look dirty forever.
    const nextPrefix = keyPrefix.trim().toUpperCase();
    if (nextPrefix !== project.keyPrefix) next.keyPrefix = nextPrefix;

    // The plan. Every one of these sends an explicit `null` to CLEAR — the client's `compact`
    // drops only `undefined`, so a null is the difference between "unset this" and "leave it".
    if (startDate !== (project.startDate ?? "")) next.startDate = startDate || null;
    if (targetDate !== (project.targetDate ?? "")) next.targetDate = targetDate || null;
    // The lead travels as a PAIR, always both or neither — the backend refuses half of one, so
    // sending `leadId` alone would be a 400 rather than a partial edit. Clearing sends two nulls.
    const currentLead =
      project.leadKind && project.leadId
        ? toOptionValue({ assigneeKind: project.leadKind, assigneeId: project.leadId })
        : "";
    if (lead !== currentLead) {
      const parsed = fromOptionValue(lead);
      const kind = parsed ? asLeadKind(parsed.assigneeKind) : null;
      next.leadKind = kind;
      next.leadId = kind ? parsed!.assigneeId : null;
    }
    if (programId !== (project.programId ?? NO_PROGRAM)) {
      next.programId = programId || null;
    }
    return next;
  }, [
    project,
    seeded,
    name,
    description,
    status,
    color,
    keyPrefix,
    estimateScale,
    priorityScale,
    itemNoun,
    itemNounPlural,
    startDate,
    targetDate,
    lead,
    programId,
  ]);

  // Shown (and blocking) only once the field has been TOUCHED into the patch — a project that
  // arrives with no prefix yet must not open its settings already complaining.
  const keyPrefixError = patch.keyPrefix === undefined ? null : validateKeyPrefix(patch.keyPrefix);

  // The backend's own date rule, restated so the reason arrives before the round trip. It is
  // checked against the pair the project will END UP as — exactly as the server does — which is
  // what makes moving one end of an already-dated plan an ordinary one-field edit. `YYYY-MM-DD`
  // sorts lexicographically as it sorts chronologically, so this needs no parsing and no timezone.
  const datesError =
    startDate && targetDate && targetDate < startDate
      ? "The target date is before the start date."
      : null;

  // Both words or neither, and neither of them blank. Like the key prefix, it complains only once
  // the pair has been TOUCHED into the patch — a board that has never been renamed must not open
  // its settings already showing an error. The pair is checked together because the patch sends it
  // together: an empty half would be a 400 the reader could have been spared.
  const nounsError =
    patch.itemNoun === undefined
      ? null
      : !patch.itemNoun || !patch.itemNounPlural
        ? "A singular and a plural are both required."
        : null;

  const dirty = Object.keys(patch).length > 0;
  const canSave =
    dirty && name.trim().length > 0 && !keyPrefixError && !datesError && !nounsError && !saving;

  // The activity trail's word, read from the SAVED record rather than the draft: typing a new
  // noun into the settings form must not rewrite the history above it. It changes when the save
  // lands, which is when the rename is true.
  const words = itemWordsOf(project);

  async function save() {
    if (!project || !dirty) return;
    if (!name.trim()) {
      setSaveError("Name is required.");
      return;
    }
    // The Save button is disabled on this, but the guard is here too: `canSave` governs a click,
    // and nothing stops a future keyboard path from calling straight through.
    if (datesError) {
      setSaveError(datesError);
      return;
    }
    if (nounsError) {
      setSaveError(nounsError);
      return;
    }
    setSaving(true);
    setSaveError(null);
    try {
      const updated = await projectsApi.update(projectId, patch);
      // The server's OWN answer, straight into the shared entry — no re-read to arrive back at
      // bytes already in hand, and a rename is on the board's and the queue's vocabulary before
      // either is opened again. Written whether or not this pane is still mounted: the bytes are
      // true either way, and it is only the DRAFT below that must not be touched after unmount.
      writeProject(projectId, updated);
      if (mounted.current) seedDraft(updated);
    } catch (e) {
      if (mounted.current) {
        setSaveError(
          // The prefix is the only field here whose uniqueness is enforced ACROSS
          // projects, so a 409 on a patch carrying one is always about it — naming it
          // beats "conflicts with an existing value", which leaves the reader to guess
          // which of the five fields they have to change.
          isConflict(e)
            ? patch.keyPrefix !== undefined
              ? `Another project already uses the key prefix ${patch.keyPrefix}.`
              : "That change conflicts with an existing value."
            : e instanceof Error
              ? e.message
              : "Failed to save changes.",
        );
      }
    } finally {
      if (mounted.current) setSaving(false);
    }
  }

  async function addParticipant() {
    // The Add button is disabled while adding, but the Enter-key path is not —
    // guard here so a rapid double-Enter can't fire a second add.
    if (adding) return;
    const participantId = idDraft.trim();
    if (!participantId) {
      setAddError("Enter a participant id.");
      return;
    }
    setAdding(true);
    setAddError(null);
    try {
      await projectsApi.participants.add(projectId, {
        participantKind: kindDraft,
        participantId,
      });
    } catch (e) {
      if (mounted.current) {
        setAddError(
          isConflict(e)
            ? `That ${kindDraft} is already a participant.`
            : e instanceof Error
              ? e.message
              : "Failed to add participant.",
        );
      }
      return;
    } finally {
      if (mounted.current) setAdding(false);
    }
    if (mounted.current) setIdDraft("");
    // The reload's own promise rejects on failure; the hook has already surfaced it as
    // `participantsError`, so there is nothing left for this caller to do with it.
    await reloadParticipants().catch(() => {});
  }

  async function removeParticipant(p: ProjectParticipant) {
    // Guard against a rapid double-click firing two DELETEs for the same row (mirrors
    // addParticipant's `adding` guard).
    if (removingId === p.id) return;
    setRemovingId(p.id);
    setRemoveError(null);
    try {
      await projectsApi.participants.remove(projectId, p.participantId, p.participantKind);
    } catch (e) {
      if (mounted.current) {
        setRemoveError(e instanceof Error ? e.message : "Failed to remove participant.");
      }
      return;
    } finally {
      if (mounted.current) setRemovingId(null);
    }
    await reloadParticipants().catch(() => {});
  }

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <FeatureTitle
        title={title}
        api={{
          path: "/project/projects/{id}",
          pathValues: { id: projectId },
          title: "Project API",
        }}
      />
      <section className="flex min-w-0 flex-1 flex-col gap-6 overflow-y-auto px-6 py-4">
        {/* Not-found is a SETTLED answer of nothing. Before the read settles there is either a
            cached record to paint or nothing yet, and "Project not found." about a project whose
            read is still in flight is a lie the cache made easy to tell. */}
        {!project ? (
          isSettled ? (
            <EmptyState title="Project not found." />
          ) : (
            <p className="text-sm text-apt-text-muted">Loading…</p>
          )
        ) : (
          <>
            {/* ── What this project is ─────────────────────────────────── */}
            <header className="flex max-w-3xl flex-col gap-2">
              <div className="flex flex-wrap items-center gap-2">
                <Badge variant="neutral">{project.status}</Badge>
                {project.archivedAt && <Badge variant="orange">archived</Badge>}
                {/* The health, with the DATE of the claim beside it. A colour with no date is a
                    claim of unknown age, and "on track, six weeks ago" is a different sentence
                    from "on track". A project nobody has reported on shows NO badge — the absence
                    of a claim is not a fourth colour, and it is said in the Health panel below
                    where there is room to say it properly. */}
                {project.health && (
                  <>
                    <Badge variant={healthMeta(project.health).variant}>
                      {healthMeta(project.health).label}
                    </Badge>
                    {project.healthUpdatedAt && (
                      <time
                        dateTime={project.healthUpdatedAt}
                        className="text-xs text-apt-text-dim"
                      >
                        as of {relativeTime(project.healthUpdatedAt)}
                      </time>
                    )}
                  </>
                )}
              </div>
              {project.description ? (
                <p className="text-sm whitespace-pre-wrap text-apt-text-muted">
                  {project.description}
                </p>
              ) : (
                // An absent description is a fact about the project, not an error — say so
                // plainly and point at where it is written, rather than rendering a gap.
                <p className="text-sm text-apt-text-dim italic">
                  No description yet — add one in Project settings below.
                </p>
              )}
              <PlanLine project={project} programs={programRows ?? []} />
            </header>

            {/* ── How it is doing ──────────────────────────────────────── */}
            <div className="grid gap-4 lg:grid-cols-3">
              <StatCard
                title="Work"
                icon={<ListTodo size={15} className="text-apt-text-muted" aria-hidden />}
                stats={[
                  { label: "Open", value: work.open },
                  {
                    label: "In progress",
                    value: work.in_progress,
                    tone: categoryVariant("in_progress"),
                  },
                  { label: "Done", value: work.done, tone: categoryVariant("done") },
                  // Only when there ARE any: a permanent "Overdue 0" trains the eye to skip the
                  // row, which is the one row that must never be skipped.
                  ...(work.overdue > 0
                    ? [{ label: "Overdue", value: work.overdue, tone: "error" as const }]
                    : []),
                ]}
                footnote={
                  work.total === 0
                    ? `no ${words.many} yet`
                    : `${words.count(work.total)} · ${Math.round(
                        (work.done / work.total) * 100,
                      )}% done`
                }
              />

              <StatCard
                title="Material"
                icon={<FileStack size={15} className="text-apt-text-muted" aria-hidden />}
                stats={[
                  { label: "Ingested", value: material.ingested },
                  { label: "Produced", value: material.produced },
                  ...(material.unresolved > 0
                    ? [
                        {
                          label: "Unresolved",
                          value: material.unresolved,
                          tone: "orange" as const,
                        },
                      ]
                    : []),
                ]}
                footnote={
                  material.total === 0
                    ? "nothing attached yet"
                    : `${material.total} attachment${material.total === 1 ? "" : "s"}`
                }
              />

              <InfoPanel
                title="Recent activity"
                icon={<Activity size={15} className="text-apt-text-muted" aria-hidden />}
              >
                {activityRows === null ? (
                  <p className="text-sm text-apt-text-muted">Loading…</p>
                ) : activityRows.length === 0 ? (
                  <p className="text-sm text-apt-text-dim">Nothing has happened yet.</p>
                ) : (
                  <StatList as="ul">
                    {activityRows.map((row) => (
                      <StatListRow
                        key={row.id}
                        as="li"
                        // A comment's own words say more than "commented" does, so when there
                        // is a body it IS the line — same precedence the full feed uses.
                        label={`${actorText(row)} ${
                          commentBody(row) ?? actionPhrase(row.action, row.detail, words)
                        }`}
                        labelTitle={`${actorText(row)} ${actionPhrase(row.action, row.detail, words)}`}
                        trailing={
                          <time dateTime={row.createdAt} className="text-apt-text-dim">
                            {relativeTime(row.createdAt)}
                          </time>
                        }
                      />
                    ))}
                  </StatList>
                )}
              </InfoPanel>
            </div>

            {/* ── How it says it is doing ──────────────────────────────── */}
            {/* The narrative behind the badge in the header. It sits next to the derived figures
                above rather than in settings, because a check-in is a REPORT — someone's claim
                about whether the plan will hold — and reading it against the counts is the whole
                point. A refetch of the project after every write is what keeps the badge and the
                top row of this panel from disagreeing; the panel does not own `health`. */}
            <InfoPanel
              title="Health"
              icon={<HeartPulse size={15} className="text-apt-text-muted" aria-hidden />}
              className="max-w-3xl"
            >
              <ProjectStatusUpdates
                projectId={projectId}
                participants={participants ?? []}
                onChanged={() => {
                  // Only the row, never the draft: the seed above fires once per project, so this
                  // re-read moves the header badge without throwing away whatever someone had
                  // typed into the settings form while reporting a status. Swallowed — a failed
                  // re-read must not be reported as a failed check-in, which succeeded.
                  void reloadProject().catch(() => {});
                }}
              />
            </InfoPanel>

            {/* ── Who is in it ─────────────────────────────────────────── */}
            <InfoPanel
              title="People"
              icon={<Users size={15} className="text-apt-text-muted" aria-hidden />}
              count={participants?.length ?? 0}
              className="max-w-3xl"
            >
              <div className="flex flex-col gap-3">
                <div className="flex flex-wrap items-end gap-3">
                  <Field label="Kind" className="w-40">
                    <Select
                      value={kindDraft}
                      onChange={(e) => {
                        setAddError(null);
                        setKindDraft(
                          e.target.value as ProjectParticipant["participantKind"],
                        );
                      }}
                    >
                      {KINDS.map((k) => (
                        <option key={k} value={k}>
                          {k}
                        </option>
                      ))}
                    </Select>
                  </Field>
                  <Field label="Participant id" className="min-w-56 flex-1">
                    <Input
                      value={idDraft}
                      onChange={(e) => {
                        setAddError(null);
                        setIdDraft(e.target.value);
                      }}
                      onKeyDown={(e) => {
                        if (e.key === "Enter") void addParticipant();
                      }}
                      placeholder="Actor id"
                    />
                  </Field>
                  <Button
                    onClick={() => void addParticipant()}
                    disabled={adding || !idDraft.trim()}
                  >
                    Add
                  </Button>
                </div>
                <ErrorText error={addError} />

                {/* A read failure and a failed remove are different events, and they do not
                    co-occur in practice — one line, whichever happened. */}
                <ErrorText error={participantsError ?? removeError} />
                {participants === null ? (
                  // Only while the read is genuinely outstanding: with an error above, "Loading…"
                  // is a promise the pane is not keeping.
                  participantsError ? null : (
                    <p className="text-sm text-apt-text-muted">Loading…</p>
                  )
                ) : participants.length === 0 ? (
                  <EmptyState title="No participants yet." />
                ) : (
                  <List>
                    {participants.map((p) => (
                      <ListItem key={p.id} className="justify-between">
                        <div className="flex min-w-0 items-center gap-2">
                          <Badge variant={kindVariant(p.participantKind)}>
                            {p.participantKind}
                          </Badge>
                          <span className="truncate font-mono text-sm text-apt-text">
                            {p.participantId}
                          </span>
                          {p.role && p.role !== "member" && (
                            <span className="shrink-0 text-xs text-apt-text-muted">
                              {p.role}
                            </span>
                          )}
                        </div>
                        <Button
                          variant="ghost"
                          size="icon-sm"
                          aria-label={`Remove ${p.participantId}`}
                          disabled={removingId === p.id}
                          onClick={() => void removeParticipant(p)}
                        >
                          <Trash2 />
                        </Button>
                      </ListItem>
                    ))}
                  </List>
                )}
              </div>
            </InfoPanel>

            {/* ── Its own record ───────────────────────────────────────── */}
            <Disclosure
              title="Project settings"
              subtitle="Name, description, lifecycle status, board accent, key prefix, estimate scale, and the plan — dates, lead, and program."
              className="max-w-3xl"
            >
              <div className="flex max-w-xl flex-col gap-5">
                <Field label="Name">
                  <Input
                    value={name}
                    onChange={(e) => {
                      setSaveError(null);
                      setName(e.target.value);
                    }}
                    placeholder="Website relaunch"
                  />
                </Field>
                <Field label="Description">
                  <Textarea
                    value={description}
                    onChange={(e) => {
                      setSaveError(null);
                      setDescription(e.target.value);
                    }}
                    placeholder="What is this project about? (optional)"
                    rows={3}
                  />
                </Field>
                <Field label="Status">
                  <Input
                    value={status}
                    onChange={(e) => {
                      setSaveError(null);
                      setStatus(e.target.value);
                    }}
                    placeholder="active"
                  />
                </Field>
                <Field label="Color" hint="The project's board accent.">
                  <Input
                    value={color}
                    onChange={(e) => {
                      setSaveError(null);
                      setColor(e.target.value);
                    }}
                    placeholder="Board accent color"
                  />
                </Field>
                {/* Renaming this renames EVERY card's key at once — which is the point of
                    storing the prefix on the project rather than on each card. The hint says so
                    plainly, because it is the one field here whose blast radius is larger than
                    the row it sits in. */}
                <Field
                  label="Key prefix"
                  hint={`Names this project's ${words.many} — ADH gives ADH-1, ADH-2, … Renaming it renames every key.`}
                  error={keyPrefixError ?? undefined}
                >
                  <Input
                    value={keyPrefix}
                    onChange={(e) => {
                      setSaveError(null);
                      setKeyPrefix(e.target.value.toUpperCase());
                    }}
                    maxLength={8}
                    placeholder="ADH"
                  />
                </Field>
                {/* The one setting that turns a whole field on and off: `none` — the default
                    every project starts on — means no size picker and no size chip anywhere in
                    this project. Switching away NEVER rewrites a card: the numbers already
                    stored stay exactly as they are and simply stop being offered, which is what
                    makes this cheap to change your mind about. */}
                <Field
                  label="Estimate scale"
                  hint="Which sizes this project's cards can be given. Changing it leaves sizes already set alone."
                >
                  <Select
                    value={estimateScale}
                    onChange={(e) => {
                      setSaveError(null);
                      setEstimateScale(e.target.value as EstimateScale);
                    }}
                  >
                    {ESTIMATE_SCALES.map((s) => (
                      <option key={s} value={s}>
                        {estimateScaleOptionLabel(s)}
                      </option>
                    ))}
                  </Select>
                </Field>
                {/* The same switch for RANKING, and it behaves the same way: turning it off hides
                    the priority field, the column, the board badge and the filter, and rewrites
                    nothing. A rank already set stays on the card and comes back untouched if the
                    board turns ranking on again — which is what makes this a setting rather than a
                    migration. It differs from the estimate one in which end is the default:
                    boards rank unless told otherwise, and do not estimate unless told to. */}
                <Field
                  label="Priority scale"
                  hint="Whether this project's cards carry a priority. Turning it off leaves ranks already set alone."
                >
                  <Select
                    value={priorityScale}
                    onChange={(e) => {
                      setSaveError(null);
                      setPriorityScale(e.target.value as PriorityScale);
                    }}
                  >
                    {PRIORITY_SCALES.map((s) => (
                      <option key={s} value={s}>
                        {priorityScaleOptionLabel(s)}
                      </option>
                    ))}
                  </Select>
                </Field>
                {/* What this board CALLS its cards — the word every surface in the project reads,
                    from the rail row down to a bulk dialog's "Update 3 …". Two boxes, not one plus
                    a rule: English does not pluralise reliably enough to guess, and "storys" would
                    be visible on every screen the rename was made to fix. The pair saves together
                    (see the patch), so the plural is never left describing the previous word. */}
                <div className="flex flex-wrap gap-4">
                  <Field
                    label="Item name"
                    className="min-w-44 flex-1"
                    hint="What one card is called here — story, task, recipe."
                    error={nounsError ?? undefined}
                  >
                    <Input
                      value={itemNoun}
                      onChange={(e) => {
                        setSaveError(null);
                        setItemNoun(e.target.value);
                      }}
                      maxLength={32}
                      placeholder={DEFAULT_ITEM_NOUN}
                    />
                  </Field>
                  <Field
                    label="Item name (plural)"
                    className="min-w-44 flex-1"
                    hint="And what several are called."
                  >
                    <Input
                      value={itemNounPlural}
                      onChange={(e) => {
                        setSaveError(null);
                        setItemNounPlural(e.target.value);
                      }}
                      maxLength={32}
                      placeholder={DEFAULT_ITEM_NOUN_PLURAL}
                    />
                  </Field>
                </div>
                {/* ── The plan ───────────────────────────────────────────
                    Four fields that say when this board runs, who answers for it, and what it
                    belongs to. They live in the SAME draft and the same Save as the rest — a plan
                    is part of the project's record, not a second object with its own button, and
                    splitting the save would let someone leave with half an edit applied. */}
                <div className="flex flex-wrap gap-4">
                  <Field
                    label="Start date"
                    className="min-w-44 flex-1"
                    hint="Optional — a standing board has no ends."
                    error={datesError ?? undefined}
                  >
                    <Input
                      type="date"
                      value={startDate}
                      onChange={(e) => {
                        setSaveError(null);
                        setStartDate(e.target.value);
                      }}
                    />
                  </Field>
                  <Field
                    label="Target date"
                    className="min-w-44 flex-1"
                    hint="Optional, and independent of the start."
                  >
                    <Input
                      type="date"
                      value={targetDate}
                      onChange={(e) => {
                        setSaveError(null);
                        setTargetDate(e.target.value);
                      }}
                    />
                  </Field>
                </div>
                {/* The same control a card's assignee uses, over the same roster, under another
                    word — a lead IS an assignee, of the board rather than of one card. */}
                <AssigneePicker
                  participants={participants ?? []}
                  value={fromOptionValue(lead)}
                  onChange={(v) => {
                    setSaveError(null);
                    setLead(toOptionValue(v));
                  }}
                  label="Lead"
                  noneLabel="No lead"
                />
                {/* A board joins at most one program, and only one under its OWN owner — which is
                    why the list is the workspace's and a cross-workspace id is a 400 rather than
                    something this picker can offer. The orphan option keeps a membership this
                    reader cannot resolve selectable, so opening settings never silently detaches
                    the board on the next save. */}
                <Field
                  label="Program"
                  hint="The roll-up this board belongs to. A program spans several boards in this workspace."
                >
                  <Select
                    value={programId}
                    onChange={(e) => {
                      setSaveError(null);
                      setProgramId(e.target.value);
                    }}
                  >
                    <option value={NO_PROGRAM}>No program</option>
                    {programId !== NO_PROGRAM &&
                    !(programRows ?? []).some((p) => p.id === programId) ? (
                      <option value={programId}>Keep current program</option>
                    ) : null}
                    {(programRows ?? []).map((p) => (
                      <option key={p.id} value={p.id}>
                        {p.name}
                      </option>
                    ))}
                  </Select>
                </Field>
                <ErrorText error={saveError} />
                <div className="flex items-center gap-2">
                  <Button onClick={() => void save()} disabled={!canSave}>
                    {saving ? "Saving…" : "Save changes"}
                  </Button>
                </div>
              </div>
            </Disclosure>

            {/* ── Transfer ─────────────────────────────────────────────── */}
            {renderTransferOwnership && renderTransferOwnership(project)}
          </>
        )}
      </section>
    </div>
  );
}
