// @vitest-environment jsdom
//
// Component test for WorkItemEditor: its save gate/patch behaviour, and the two sections that
// hang below the form in edit mode — the card's conversation and its activity trail. This
// package's vitest config is jsdom (see vitest.config.ts).
//
// The api boundaries are mocked in the domain barrels (@agentic-toolkit/data/projects and
// @agentic-toolkit/data/reactions), so the editor's own wiring is exercised, not the transport.
// The mocks are PARTIAL (importOriginal-spread) because the panes below also use pure folds from
// those barrels — `threadOf`, the reaction kind constant — which have nothing to stub.
//
// What this file no longer covers, deliberately: posting a comment. The trail used to carry a
// one-line composer, from back when a comment WAS an activity row; comments are their own records
// now, and their pane's behaviour is tested where it lives (WorkItemComments.test.tsx). What is
// asserted here is only what this file owns — that the editor mounts both sections for the item
// in front of it, and that the trail is the read-only one.
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor, cleanup } from "@testing-library/react";

// The former @/api/{project-activity,project-work-items} hub modules now ship in ONE domain
// barrel, so their stubs merge into a single mock.
vi.mock("@agentic-toolkit/data/projects", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@agentic-toolkit/data/projects")>()),
  projectActivityApi: {
    projectActivity: vi.fn(),
    workItemActivity: vi.fn(),
  },
  projectWorkItemsApi: { create: vi.fn(), update: vi.fn() },
  projectCommentsApi: { list: vi.fn(), add: vi.fn(), edit: vi.fn(), remove: vi.fn() },
}));

vi.mock("@agentic-toolkit/data/reactions", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@agentic-toolkit/data/reactions")>()),
  reactionsApi: { list: vi.fn(), add: vi.fn(), remove: vi.fn() },
}));

import { WorkItemEditor } from "./WorkItemEditor";
import { itemWordsOf } from "./vocabulary";
import {
  projectActivityApi,
  projectCommentsApi,
  type ProjectActivity,
} from "@agentic-toolkit/data/projects";
import { reactionsApi } from "@agentic-toolkit/data/reactions";
import {
  projectWorkItemsApi,
  type EstimateScale,
  type Iteration,
  type Milestone,
  type ProjectStatus,
  type WorkItem,
} from "@agentic-toolkit/data/projects";

const workItemActivity = vi.mocked(projectActivityApi.workItemActivity);
const listComments = vi.mocked(projectCommentsApi.list);
const listReactions = vi.mocked(reactionsApi.list);
const update = vi.mocked(projectWorkItemsApi.update);

const ITEM: WorkItem = {
  id: "w1",
  projectId: "p1",
  itemKey: "WEB-1",
  title: "Design the landing page",
  description: "",
  statusId: "s1",
  assigneeKind: null,
  assigneeId: null,
  priority: 0,
  startDate: null,
  dueDate: null,
  labels: [],
  parentId: null,
  iterationId: null,
  milestoneId: null,
  estimate: null,
  rank: "V0",
  createdAt: "2026-07-03T00:00:00Z",
  updatedAt: "2026-07-03T00:00:00Z",
};

/** One workspace cycle, so the iteration picker has something to offer. `state` is DERIVED by
 *  the backend from the dates — the client never computes it, so a fixture states it. */
const CYCLE: Iteration = {
  id: "it1",
  name: "Sprint 7",
  description: "",
  startDate: "2026-07-01",
  endDate: "2026-07-14",
  state: "active",
  ownerKind: "customer",
  ownerId: "cust-1",
  ecosystemId: "eco-1",
  createdAt: "2026-06-30T00:00:00Z",
  updatedAt: "2026-06-30T00:00:00Z",
};

/** One point in THIS board's plan, so the milestone picker has something to offer. `counts` are
 *  derived by the backend on every read — a fixture just states them. */
const MILESTONE: Milestone = {
  id: "ms1",
  projectId: "p1",
  name: "Beta",
  description: "",
  targetDate: "2026-08-15",
  counts: { backlog: 0, todo: 0, in_progress: 0, done: 0, canceled: 0 },
  ecosystemId: "eco-1",
  createdAt: "2026-06-30T00:00:00Z",
  updatedAt: "2026-06-30T00:00:00Z",
};

const COMMENT: ProjectActivity = {
  id: "c1",
  projectId: "p1",
  workItemId: "w1",
  actorKind: "customer",
  actorId: "cust-1",
  actorLabel: "Ada",
  action: "comment.added",
  detail: { body: "Nice work" },
  createdAt: "2026-07-03T01:00:00Z",
};

beforeEach(() => {
  vi.clearAllMocks();
  workItemActivity.mockResolvedValue({ rows: [], nextBefore: null });
  listComments.mockResolvedValue([]);
  listReactions.mockResolvedValue([]);
});

afterEach(cleanup);

function renderEditor(
  item: WorkItem = ITEM,
  planning: {
    iterations?: Iteration[];
    milestones?: Milestone[];
    estimateScale?: EstimateScale;
  } = {},
  // The per-board settings, defaulted to the shape every test below assumes. Only the
  // "board settings" block passes anything here.
  settings: Partial<React.ComponentProps<typeof WorkItemEditor>> = {},
) {
  return render(
    <WorkItemEditor
      projectId="p1"
      item={item}
      statuses={[]}
      participants={[]}
      workItems={[ITEM]}
      labelOptions={[]}
      iterations={planning.iterations ?? []}
      milestones={planning.milestones ?? []}
      estimateScale={planning.estimateScale ?? "none"}
      onSaved={() => {}}
      onCancel={() => {}}
      {...settings}
    />,
  );
}

describe("WorkItemEditor conversation + activity trail (edit mode)", () => {
  it("mounts BOTH sections against the item in front of it", async () => {
    renderEditor();

    // Each reads the same card, from its own endpoint: the trail is what happened, the thread is
    // what was said. An editor that wired one of them to a different id would show one card's
    // form over another card's discussion.
    await waitFor(() =>
      expect(workItemActivity).toHaveBeenCalledWith("w1", { limit: 20, before: undefined }),
    );
    await waitFor(() => expect(listComments).toHaveBeenCalledWith("w1"));
    expect(screen.getByRole("region", { name: "Comments" })).not.toBeNull();
  });

  it("puts the ONE composer in the conversation, not in the trail", async () => {
    // A second composer under Activity would be two doors into one room — and the narrower one,
    // with no reply, no edit and no way to take a comment back.
    renderEditor();
    await waitFor(() => expect(listComments).toHaveBeenCalledWith("w1"));

    expect(screen.getByLabelText("Add a comment")).not.toBeNull();
    expect(screen.queryByLabelText("Comment")).toBeNull();
  });

  it("still RECORDS a comment in the trail, even though it is no longer written there", async () => {
    // The two surfaces are one story told twice: the trail says a comment was made and by whom,
    // the thread holds the words. Losing the trail row when the composer moved would have made
    // the audit record silently incomplete — and nothing on screen would have said so.
    workItemActivity.mockResolvedValue({ rows: [structuredClone(COMMENT)], nextBefore: null });
    renderEditor();

    expect(await screen.findByText("commented")).not.toBeNull();
    expect(screen.getByText("Ada")).not.toBeNull();
  });
});

describe("WorkItemEditor save gate", () => {
  it("starts disabled for an unmodified item and enables after an edit", () => {
    renderEditor();

    const save = screen.getByRole("button", { name: "Save changes" });
    expect(save).toBeDisabled();

    fireEvent.change(screen.getByPlaceholderText("Design the landing page"), {
      target: { value: "Design the new landing page" },
    });
    expect(save).toBeEnabled();
  });

  // The gate disables Save before `save()`'s own `setError("Title is required.")` can ever run, so
  // without a rendered reason a cleared title produces a grey button and no explanation at all.
  it("says WHY Save is blocked when the title is cleared", () => {
    renderEditor();

    expect(screen.queryByText("Title is required.")).toBeNull();

    fireEvent.change(screen.getByPlaceholderText("Design the landing page"), {
      target: { value: "  " },
    });

    expect(screen.getByRole("button", { name: "Save changes" })).toBeDisabled();
    expect(screen.getByText("Title is required.")).toBeInTheDocument();
  });

  // The other half: an item that arrives ALREADY invalid must not open with a complaint about a row
  // the user hasn't touched. Nothing-to-save is what the grey button already says.
  it("stays silent about an already-blank title the user hasn't touched", () => {
    renderEditor({ ...ITEM, title: "" });
    expect(screen.getByRole("button", { name: "Save changes" })).toBeDisabled();
    expect(screen.queryByText("Title is required.")).toBeNull();
  });
});

describe("WorkItemEditor save (edit mode)", () => {
  // The raw dirty check saw a different string and lit Save up; the PATCH it would have sent was
  // empty, because every field goes out trimmed. Save is gated on that PATCH now, so the no-op
  // write can't even be requested — which is stronger than skipping it after the click.
  it("a trailing space in the title is not a change — Save stays disabled and nothing is written", () => {
    const onSaved = vi.fn();
    render(
      <WorkItemEditor
        projectId="p1"
        item={ITEM}
        statuses={[]}
        participants={[]}
        workItems={[ITEM]}
        labelOptions={[]}
        iterations={[]}
        milestones={[]}
        estimateScale="none"
        onSaved={onSaved}
        onCancel={() => {}}
      />,
    );

    fireEvent.change(screen.getByPlaceholderText("Design the landing page"), {
      target: { value: `${ITEM.title} ` },
    });

    expect(screen.getByRole("button", { name: "Save changes" })).toBeDisabled();
    fireEvent.click(screen.getByRole("button", { name: "Save changes" }));
    expect(update).not.toHaveBeenCalled();
    expect(onSaved).not.toHaveBeenCalled();
  });

  // The other side of the same comparison: a row STORED with stray whitespace used to be diffed
  // trimmed-draft-against-raw-baseline, so it read as changed the instant it loaded — Save was live
  // on a form nobody had touched, offering a write that only re-normalises what is already there.
  it("an item stored with untrimmed text loads with Save disabled", () => {
    renderEditor({ ...ITEM, title: "  Design the landing page  ", description: " notes " });
    expect(screen.getByRole("button", { name: "Save changes" })).toBeDisabled();
  });

  it("diffs the second save against the saved row (baseline), not the stale item prop", async () => {
    update.mockResolvedValueOnce({ ...ITEM, title: "New Title" });
    renderEditor();

    const save = screen.getByRole("button", { name: "Save changes" });

    // First save: edit the title only.
    fireEvent.change(screen.getByPlaceholderText("Design the landing page"), {
      target: { value: "New Title" },
    });
    fireEvent.click(save);
    await waitFor(() => expect(update).toHaveBeenCalledTimes(1));
    expect(update).toHaveBeenNthCalledWith(1, "w1", { title: "New Title" });

    // Second save: edit ONLY the description — the draft's title still reads "New Title", the
    // exact value just saved. If buildPatch() diffed against the stale `item` PROP (title:
    // "Design the landing page", since props never change mid-test) instead of the hook's
    // committed BASELINE (title: "New Title" after the first save's commit()), it would wrongly
    // resend `title: "New Title"` a second time — a phantom re-send of a field the user didn't
    // touch this round. This is the whole justification for the `baseline` hook extension; without
    // it (or without the commit() call that advances it), this assertion fails.
    update.mockResolvedValueOnce({ ...ITEM, title: "New Title", description: "New description" });
    fireEvent.change(screen.getByLabelText(/description/i), {
      target: { value: "New description" },
    });
    fireEvent.click(save);
    await waitFor(() => expect(update).toHaveBeenCalledTimes(2));
    expect(update).toHaveBeenNthCalledWith(2, "w1", { description: "New description" });
  });
});

// Labels are the shared tagging system (content.keywords) reached through the shared
// `TagSetField` row, so what this file has to prove is the WIRING either side of that row:
// the draft carries a set, and `buildPatch` sends it only when it actually differs. The row's
// own affordances (autocomplete commit rule, the chooser's chips, minting a new label) are
// covered where they live, in ui's tagSetField/entityChooser tests.
describe("WorkItemEditor labels", () => {
  const VOCABULARY = ["bug", "chore", "design"];

  function renderWithLabels(item: WorkItem = ITEM) {
    return render(
      <WorkItemEditor
        projectId="p1"
        item={item}
        statuses={[]}
        participants={[]}
        workItems={[item]}
        labelOptions={VOCABULARY}
        iterations={[]}
        milestones={[]}
        estimateScale="none"
        onSaved={() => {}}
        onCancel={() => {}}
      />,
    );
  }

  it("adds a label from the vocabulary and PATCHes the whole set", async () => {
    update.mockResolvedValueOnce({ ...ITEM, labels: ["design"] });
    renderWithLabels();

    // Accepting a suggestion fires onValueChange with the WHOLE option string; TagSetField
    // treats an exact vocabulary match as the commit.
    fireEvent.change(screen.getByLabelText("Add a label"), { target: { value: "design" } });

    const save = screen.getByRole("button", { name: "Save changes" });
    await waitFor(() => expect(save).not.toBeDisabled());
    fireEvent.click(save);

    // The endpoint REPLACES the set rather than merging, so the patch carries every label the
    // item should end up with — not just the one added.
    await waitFor(() => expect(update).toHaveBeenCalledTimes(1));
    expect(update).toHaveBeenCalledWith("w1", { labels: ["design"] });
  });

  it("keeps Save disabled when the labels are untouched", () => {
    renderWithLabels({ ...ITEM, labels: ["bug", "chore"] });
    expect(screen.getByRole("button", { name: "Save changes" })).toBeDisabled();
  });

  // Order is DATA here — the backend stores it as `sort_order` on the link rows and hands it
  // back in that order. A set-wise comparison would call a re-order "unchanged" and silently
  // drop it, so the diff is order-sensitive.
  it("treats a re-order as a change", async () => {
    const item = { ...ITEM, labels: ["bug", "chore"] };
    update.mockResolvedValueOnce({ ...item, labels: ["chore", "bug"] });
    renderWithLabels(item);

    // Removing the leading chip and re-adding it puts the same two labels back in the other order.
    fireEvent.click(screen.getByRole("button", { name: "Remove bug" }));
    fireEvent.change(screen.getByLabelText("Add a label"), { target: { value: "bug" } });

    const save = screen.getByRole("button", { name: "Save changes" });
    await waitFor(() => expect(save).not.toBeDisabled());
    fireEvent.click(save);

    await waitFor(() => expect(update).toHaveBeenCalledTimes(1));
    expect(update).toHaveBeenCalledWith("w1", { labels: ["chore", "bug"] });
  });
});

// The three PLANNING fields — which cycle a card is committed to, which delivery it counts
// toward, and how big it is. All three are draft STRINGS over nullable API values, which is where
// the interesting cases are: "" is a real answer (the backlog / no milestone / unestimated) and
// has to PATCH as an explicit `null`, and `0` is a real size that must not collapse into
// "no estimate".
describe("WorkItemEditor iteration + milestone + estimate", () => {
  it("commits a backlog card to a cycle", async () => {
    update.mockResolvedValueOnce({ ...ITEM, iterationId: "it1" });
    renderEditor(ITEM, { iterations: [CYCLE] });

    fireEvent.change(screen.getByLabelText("Iteration"), { target: { value: "it1" } });
    const save = screen.getByRole("button", { name: "Save changes" });
    await waitFor(() => expect(save).not.toBeDisabled());
    fireEvent.click(save);

    await waitFor(() => expect(update).toHaveBeenCalledTimes(1));
    expect(update).toHaveBeenCalledWith("w1", { iterationId: "it1" });
  });

  // Sending the cycle back to the backlog is a CLEAR, and the only way to say that is an explicit
  // null: an omitted field would leave the card in the cycle it was being taken out of.
  it("sends a committed card back to the backlog as an explicit null", async () => {
    const committed = { ...ITEM, iterationId: "it1" };
    update.mockResolvedValueOnce({ ...committed, iterationId: null });
    renderEditor(committed, { iterations: [CYCLE] });

    fireEvent.change(screen.getByLabelText("Iteration"), { target: { value: "" } });
    fireEvent.click(screen.getByRole("button", { name: "Save changes" }));

    await waitFor(() => expect(update).toHaveBeenCalledTimes(1));
    expect(update).toHaveBeenCalledWith("w1", { iterationId: null });
  });

  it("aims a card at a milestone, on its OWN key", async () => {
    update.mockResolvedValueOnce({ ...ITEM, milestoneId: "ms1" });
    renderEditor(ITEM, { milestones: [MILESTONE] });

    fireEvent.change(screen.getByLabelText("Milestone"), { target: { value: "ms1" } });
    const save = screen.getByRole("button", { name: "Save changes" });
    await waitFor(() => expect(save).not.toBeDisabled());
    fireEvent.click(save);

    await waitFor(() => expect(update).toHaveBeenCalledTimes(1));
    // ONLY the milestone travels: aiming a card at a delivery says nothing about which fortnight
    // it is being worked in, so a patch that carried `iterationId` too would be inventing an
    // answer to the other question.
    expect(update).toHaveBeenCalledWith("w1", { milestoneId: "ms1" });
  });

  it("detaches a card from its milestone as an explicit null", async () => {
    const aimed = { ...ITEM, milestoneId: "ms1" };
    update.mockResolvedValueOnce({ ...aimed, milestoneId: null });
    renderEditor(aimed, { milestones: [MILESTONE] });

    fireEvent.change(screen.getByLabelText("Milestone"), { target: { value: "" } });
    fireEvent.click(screen.getByRole("button", { name: "Save changes" }));

    await waitFor(() => expect(update).toHaveBeenCalledTimes(1));
    expect(update).toHaveBeenCalledWith("w1", { milestoneId: null });
  });

  it("has no milestone field at all on a board with no plan", () => {
    // Unlike the iteration picker beside it, which always renders because "Backlog" is a real
    // answer to a question every workspace's cards face. A board that has declared no milestones
    // is being asked nothing, so the row is absent rather than empty.
    renderEditor(ITEM, { milestones: [] });
    expect(screen.queryByLabelText("Milestone")).toBeNull();
    expect(screen.getByLabelText("Iteration")).not.toBeNull();
  });

  it("keeps the field for a card aimed at a milestone the list no longer carries", () => {
    // A value the reader cannot see is a value they cannot correct — so a deleted or foreign
    // milestoneId keeps the row, and with it the only way to clear the reference.
    renderEditor({ ...ITEM, milestoneId: "gone" }, { milestones: [] });
    const select = screen.getByLabelText("Milestone") as HTMLSelectElement;
    expect(select.value).toBe("gone");
    expect(screen.getByRole("button", { name: "Save changes" })).toBeDisabled();
  });

  it("has no estimate field at all on a project that does not estimate", () => {
    renderEditor(ITEM, { estimateScale: "none" });
    expect(screen.queryByLabelText("Estimate")).toBeNull();
  });

  // Zero is a SIZE — a card someone looked at and judged free — so it has to reach the API as 0
  // rather than as the "" that means nobody has sized it.
  it("PATCHes an estimate of zero as 0, not as unestimated", async () => {
    update.mockResolvedValueOnce({ ...ITEM, estimate: 0 });
    renderEditor(ITEM, { estimateScale: "fibonacci" });

    fireEvent.change(screen.getByLabelText("Estimate"), { target: { value: "0" } });
    fireEvent.click(screen.getByRole("button", { name: "Save changes" }));

    await waitFor(() => expect(update).toHaveBeenCalledTimes(1));
    expect(update).toHaveBeenCalledWith("w1", { estimate: 0 });
  });

  it("clears a size back to unestimated as an explicit null", async () => {
    const sized = { ...ITEM, estimate: 5 };
    update.mockResolvedValueOnce({ ...sized, estimate: null });
    renderEditor(sized, { estimateScale: "fibonacci" });

    fireEvent.change(screen.getByLabelText("Estimate"), { target: { value: "" } });
    fireEvent.click(screen.getByRole("button", { name: "Save changes" }));

    await waitFor(() => expect(update).toHaveBeenCalledTimes(1));
    expect(update).toHaveBeenCalledWith("w1", { estimate: null });
  });

  // A card sized under a scale the board has since changed keeps its size selectable, or opening
  // the editor and saving anything else would silently re-size it.
  it("keeps a size the current scale no longer offers", () => {
    renderEditor({ ...ITEM, estimate: 13 }, { estimateScale: "linear" });
    const select = screen.getByLabelText("Estimate") as HTMLSelectElement;
    expect(select.value).toBe("13");
    expect(screen.getByRole("button", { name: "Save changes" })).toBeDisabled();
  });
});

// Every other test in this file renders with `statuses={[]}`, so the status field's real
// (populated) path was never exercised. An item with NO status used to load as `statuses[0].id`
// — the SAME invented value on both the draft and the baseline — so the field displayed a status
// the row didn't have, dirty stayed false, re-picking that status hit `set`'s sameValue
// short-circuit, and the item could never be given a status at all.
describe("WorkItemEditor status field with a statusless item", () => {
  const STATUSES: ProjectStatus[] = [
    { id: "s1", projectId: "p1", key: "todo", label: "To do", category: "todo", position: 0, createdAt: "2026-07-03T00:00:00Z" },
    { id: "s2", projectId: "p1", key: "doing", label: "Doing", category: "in_progress", position: 1, createdAt: "2026-07-03T00:00:00Z" },
  ];
  const NO_STATUS: WorkItem = { ...ITEM, statusId: null };

  function renderWithStatuses() {
    return render(
      <WorkItemEditor
        projectId="p1"
        item={NO_STATUS}
        statuses={STATUSES}
        participants={[]}
        workItems={[NO_STATUS]}
        labelOptions={[]}
        iterations={[]}
        milestones={[]}
        estimateScale="none"
        onSaved={() => {}}
        onCancel={() => {}}
      />,
    );
  }

  it("shows it has no status rather than the first one", () => {
    renderWithStatuses();
    const select = screen.getByLabelText("Status") as HTMLSelectElement;
    expect(select.value).toBe("");
    expect(screen.getByRole("option", { name: "— No status" })).toBeDefined();
  });

  // Deliberately picks the FIRST status — the very value the old fallback pre-filled the draft
  // AND the baseline with. That is the case the bug swallowed whole: the field already read
  // "To do", so choosing "To do" was a no-op the dirty check never saw and Save stayed dead.
  it("lets the first status be picked and PATCHes it", async () => {
    update.mockResolvedValueOnce({ ...NO_STATUS, statusId: "s1" });
    renderWithStatuses();

    const save = screen.getByRole("button", { name: "Save changes" });
    expect(save).toHaveProperty("disabled", true);

    fireEvent.change(screen.getByLabelText("Status"), { target: { value: "s1" } });
    expect(save).toHaveProperty("disabled", false);

    fireEvent.click(save);
    await waitFor(() => expect(update).toHaveBeenCalledTimes(1));
    expect(update).toHaveBeenNthCalledWith(1, "w1", { statusId: "s1" });
  });
});

// The editor used to draw its own API affordance beside ItemKey (`useRecordAffordance`, in the
// body row above Title); that button now lives once, in WorkItemsSurface's FeatureTitle header,
// so the editor itself must never render one — only the read-only key stays in that row.
describe("WorkItemEditor — no API affordance of its own", () => {
  it("renders ItemKey but no API button in the body", () => {
    renderEditor();
    expect(screen.getByText("WEB-1")).not.toBeNull();
    expect(screen.queryByRole("button", { name: /API/ })).toBeNull();
  });
});

describe("WorkItemEditor — board settings", () => {
  it("omits the Priority field on a board that does not rank", () => {
    renderEditor(ITEM, {}, { priorityScale: "none" });

    // Not disabled, not zeroed — absent. A rank the board does not use is a question the form has
    // no business asking, and the stored value is left exactly as it was.
    expect(screen.queryByLabelText("Priority")).toBeNull();
    // The rest of the form is untouched.
    expect(screen.getByLabelText("Title")).not.toBeNull();
  });

  it("shows the Priority field at the default scale", () => {
    renderEditor();
    expect(screen.getByLabelText("Priority")).not.toBeNull();
  });

  it("names the board's own card in the Parent hint", () => {
    renderEditor(ITEM, {}, { words: itemWordsOf({ itemNoun: "story", itemNounPlural: "stories" }) });
    expect(screen.getByText("An optional parent story in this project.")).not.toBeNull();
  });
});
