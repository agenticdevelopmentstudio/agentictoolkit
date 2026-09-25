// @vitest-environment jsdom
//
// Component test for NotebookPane — the notes workspace. Only the one data domain boundary
// (@agentic-toolkit/data/notes) and @agentic-toolkit/auth's telemetry are mocked, so the
// level-publish → filter → create → save wiring is exercised, not the transport.
//
// The pane PUBLISHES its lists as rail levels rather than rendering them. The harness below
// stands in for the rail host twice over: it renders the published levels (so their rows are
// clickable) and it hands the test the level OBJECTS, because half of what this change is about
// is which affordances a level no longer carries — and an absent `+` has no DOM to assert on.
// Everything that acts on the notes LIST — Create Note, the pop-over search, and the gear's
// filters and taxonomy editors — now rides that level's own toolbar (`onNew`/`search`/
// `titleActions`), after the page-wide home bar they used to publish into was removed as clunky
// (Mike, 2026-09-24). The harness's `<Rail>` below renders each level's toolbar controls itself,
// scoped per level id via `data-testid={\`toolbar-${l.id}\`}`, so a test can tell "wired to this
// level" from "wired to some other one" rather than trusting an unscoped `screen.*` query.
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { act, cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { useMemo, useState, type ReactNode } from "react";
import {
  RailHostContext,
  type RailHostRegistry,
  type RegisteredLevels,
} from "@agentic-toolkit/resource";
import type { TopicLevel } from "@agenticdevelopertoolkit/ui/blocks";

vi.mock("@agentic-toolkit/auth", () => ({
  useAuth: () => ({ user: { name: "Ada Lovelace" } }),
  reportUnexpectedAuthError: vi.fn(),
}));

vi.mock("@agentic-toolkit/data/notes", () => ({
  notesApi: {
    list: vi.fn(),
    get: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    remove: vi.fn(),
    categories: vi.fn(),
    tagSet: vi.fn(),
    createCategory: vi.fn(),
  },
  taxonomyApi: {
    renameCategory: vi.fn(),
    categoryParents: vi.fn(),
    addCategoryParent: vi.fn(),
    removeCategoryParent: vi.fn(),
    deleteCategory: vi.fn(),
    renameTag: vi.fn(),
    deleteTag: vi.fn(),
  },
}));

import { getToolkitQueryClient } from "@agentic-toolkit/data/query";
import { NotebookPane } from "./NotebookPane";
import {
  notesApi,
  taxonomyApi,
  type Note,
  type NoteCategory,
  type NoteSummary,
  type NoteTag,
} from "@agentic-toolkit/data/notes";

const list = vi.mocked(notesApi.list);
const get = vi.mocked(notesApi.get);
const create = vi.mocked(notesApi.create);
const update = vi.mocked(notesApi.update);
const categories = vi.mocked(notesApi.categories);
const tagSet = vi.mocked(notesApi.tagSet);
const renameTag = vi.mocked(taxonomyApi.renameTag);

const SUMMARY: NoteSummary = {
  id: "note-1",
  title: "Standup",
  excerpt: "Discussed the migration and the rollout order.",
  category: "Work",
  tags: ["meeting"],
  visibility: "private",
  publicRoute: null,
};

const NOTE: Note = {
  id: "note-1",
  title: "Standup",
  content: "# Standup\n\nDiscussed the migration.",
  category: "Work",
  tags: ["meeting"],
  visibility: "private",
  publicRoute: null,
};

/** A note written before a body was required — the shape the reported Save bug lives in. */
const EMPTY_NOTE: Note = { ...NOTE, id: "note-2", title: "Untitled", content: "" };

const WORK: NoteCategory = { id: "cat-1", name: "Work", parentIds: [], sortOrder: 0 };
const PERSONAL: NoteCategory = { id: "cat-2", name: "Personal", parentIds: [], sortOrder: 1 };

beforeEach(() => {
  vi.clearAllMocks();
  window.localStorage.clear();
  list.mockResolvedValue([structuredClone(SUMMARY)]);
  get.mockResolvedValue(structuredClone(NOTE));
  create.mockResolvedValue(structuredClone(NOTE));
  update.mockResolvedValue(structuredClone(NOTE));
  categories.mockResolvedValue([structuredClone(WORK)]);
  // Two tags, one of them NOT on the fixture note: the tag row commits on an exact vocabulary
  // match, so a second label is what makes "add a tag" expressible at all.
  tagSet.mockResolvedValue([
    { id: "kw-1", label: "meeting" },
    { id: "kw-2", label: "retro" },
  ]);
});

afterEach(cleanup);

// The cache a note is re-opened FROM is emptied between tests by the package's `vitest-setup`
// teardown — without it a note a previous test opened is still cached and still fresh, so the next
// test's `get` is never called and its assertion fails describing the feature working correctly.
// The tests below therefore each start from an empty cache.

/** The merged stack, captured per render so a test can assert on a level's SHAPE. */
let levels: TopicLevel[] = [];

function levelById(id: string): TopicLevel {
  const hit = levels.find((l) => l.id.startsWith(id));
  if (!hit) throw new Error(`no published level starting with ${id}: ${levels.map((l) => l.id)}`);
  return hit;
}

/** Renders the published rows the way the hub's workspace shell would.
 *
 *  It also stands in for the two signals the real `TopicRail` owns: the header spinner it shows
 *  while `busy`, and the hover dwell after which it calls `onPrefetch`. The dwell's TIMING is the
 *  rail's own business (and is tested there); what belongs here is whether this pane wires the
 *  two at all — which is exactly the thing a typechecked optional prop cannot tell you. */
function Rail({ published }: { published: TopicLevel[] }) {
  return (
    <div>
      {published.map((l) => (
        <div key={l.id}>
          <h3>{l.title}</h3>
          {l.busy && <span data-testid={`busy-${l.id}`} />}
          {/* Scoped per level id, the way the real `TopicRail`'s own `data-htd-toolbar` row is:
           *  every `+`, search box and gear this pane publishes lives on ITS level's toolbar, so a
           *  test can tell "wired to the notes level" from "wired to some other one". */}
          <div data-testid={`toolbar-${l.id}`}>
            {l.onNew && (
              <button type="button" onClick={() => l.onNew?.()}>
                {l.newLabel}
              </button>
            )}
            {l.search && (
              <input
                type="search"
                aria-label={l.search.placeholder}
                value={l.search.query}
                onChange={(e) => l.search?.onQueryChange?.(e.target.value)}
              />
            )}
            {l.titleActions}
          </div>
          <ul>
            {l.items.map((item) => (
              <li key={item.id}>
                <button
                  type="button"
                  disabled={item.disabled}
                  onClick={() => l.onSelect?.(item.id)}
                  onPointerEnter={() => l.onPrefetch?.(item.id)}
                >
                  {item.label}
                </button>
              </li>
            ))}
          </ul>
        </div>
      ))}
    </div>
  );
}

/** A minimal rail host. `toolbarSlot` is `null` since no test here opens an editor; the
 *  feature-bar fields that used to sit beside it are gone from `RailHostRegistry` entirely. */
function Harness({ children }: { children: ReactNode }) {
  const [entries, setEntries] = useState<Map<string, RegisteredLevels>>(new Map());
  const registry: RailHostRegistry = useMemo(
    () => ({
      registerLevels: (id, entry) =>
        setEntries((m) => {
          const next = new Map(m);
          next.set(id, entry);
          return next;
        }),
      unregisterLevels: (id) =>
        setEntries((m) => {
          const next = new Map(m);
          next.delete(id);
          return next;
        }),
      registerExitGuard: () => {},
      popStack: () => {},
      reportMissing: () => {},
      reportBusy: () => {},
      toolbarSlot: null,
    }),
    [],
  );
  levels = [...entries.values()].sort((a, b) => a.depth - b.depth).flatMap((e) => e.levels);
  return (
    <RailHostContext.Provider value={registry}>
      <Rail published={levels} />
      {children}
    </RailHostContext.Provider>
  );
}

type PaneProps = { categorySlugs?: string[]; noteId?: string };

function renderPane(props: PaneProps = {}) {
  const onSelectCategory = vi.fn();
  const onSelectNote = vi.fn();
  const tree = (p: PaneProps) => (
    <Harness>
      <NotebookPane
        categorySlugs={p.categorySlugs ?? []}
        noteId={p.noteId}
        onSelectCategory={onSelectCategory}
        onSelectNote={onSelectNote}
        workspaceSlug="acme"
      />
    </Harness>
  );
  const { rerender } = render(tree(props));
  // Re-render IN PLACE with a new selection — the way Back, a deep link and a rail click all
  // arrive, since `onSelectNote` is a stub here and the open id is a prop. A fresh `render` would
  // remount instead, resetting exactly the state some of these tests are about.
  return { onSelectCategory, onSelectNote, select: (p: PaneProps) => rerender(tree(p)) };
}

describe("the rail", () => {
  it("leads with the categories — nothing unselectable stands in front of them", async () => {
    renderPane();
    await screen.findByRole("button", { name: "Work" });

    // Not a style rule. The rail host renders levels up to the FIRST one with no selection and
    // stops (`stack-frontier.ts`), so a level that can never take a selection — a read-only
    // ecosystems list whose every row was `disabled`, which is what used to lead here — pins the
    // frontier at itself and the categories and the notes are never drawn at all. In a browser
    // that read as a notebook with no notes in it. Hence both halves of this assertion: the
    // categories come first, and every level published is one a click can advance past.
    expect(levels[0]!.id).toBe("notebook-categories-0");
    for (const level of levels) {
      expect(level.items.some((i) => !i.disabled)).toBe(true);
    }
  });

  it("offers no `+` on the categories level, but keeps Create Note on the notes level", async () => {
    renderPane();
    await screen.findByRole("button", { name: "Standup" });

    // Category creation moved to the category editor, so that level's header holds nothing but
    // navigation. The notes level is the opposite case: Create Note rode the button bar until it
    // was removed as clunky (Mike, 2026-09-24), and came back as that level's own `+` rather than
    // staying gone — so both halves of this assertion matter, not just the categories' absence.
    expect(levelById("notebook-categories").onNew).toBeUndefined();
    expect(levelById("notebook-notes").onNew).toBeDefined();
    expect(levelById("notebook-notes").newLabel).toBe("Create Note");
    expect(levelById("notebook-notes").titleActions).not.toBeUndefined();

    const toolbar = within(screen.getByTestId("toolbar-notebook-notes"));
    expect(toolbar.getByRole("button", { name: "Create Note" })).not.toBeNull();
  });

  it("prepends All and Uncategorized to the root category list", async () => {
    renderPane();
    await screen.findByRole("button", { name: "Work" });

    const level = levelById("notebook-categories");
    expect(level.items.map((i) => i.label)).toEqual(["All", "Uncategorized", "Work"]);
    // Nothing selected means the whole notebook, which is what All names.
    expect(level.selectedId).toBe("-all");
  });

  it("navigates All to the bare notebook and Uncategorized to its reserved slug", async () => {
    const { onSelectCategory } = renderPane({ categorySlugs: ["work"] });
    await screen.findByRole("button", { name: "Work" });

    fireEvent.click(screen.getByRole("button", { name: "Uncategorized" }));
    expect(onSelectCategory).toHaveBeenLastCalledWith(["-none"]);

    fireEvent.click(screen.getByRole("button", { name: "All" }));
    // "All" is the ABSENCE of a category, which the URL grammar already spells as no segments.
    expect(onSelectCategory).toHaveBeenLastCalledWith([]);
  });

  it("shows only uncategorized notes on the Uncategorized row, filtered client-side", async () => {
    list.mockResolvedValue([
      structuredClone(SUMMARY),
      { ...structuredClone(SUMMARY), id: "note-3", title: "Loose thought", category: null },
    ]);
    renderPane({ categorySlugs: ["-none"] });

    expect(await screen.findByRole("button", { name: "Loose thought" })).not.toBeNull();
    expect(screen.queryByRole("button", { name: "Standup" })).toBeNull();
    // The backend has no "no category" parameter — a blank one means "don't filter" — so the
    // request must NOT carry one, and the narrowing has to happen here.
    expect(list).toHaveBeenCalledWith({ q: "", tag: "", category: "" }, { workspace: "acme" });
  });
});

// This bar's filters and taxonomy editors were a button bar in the page-wide home bar until
// that strip was removed as clunky (Mike, 2026-09-24). They now live in `NoteListOptions`, the
// gear on the notes level's own toolbar — see that file's header comment. Search stayed a plain
// field on the toolbar rather than folding into the gear, since typing is not a menu action.
describe("the notes list's gear and search", () => {
  it("searches, and filters by category and tag", async () => {
    renderPane();
    await screen.findByRole("button", { name: "Standup" });

    fireEvent.change(screen.getByLabelText("Search notes"), { target: { value: "migration" } });

    fireEvent.click(screen.getByRole("button", { name: "Notes list options" }));
    fireEvent.click(await screen.findByRole("menuitem", { name: /^Category:/ }));
    fireEvent.click(await screen.findByRole("menuitemradio", { name: "Work" }));

    await waitFor(() =>
      expect(list).toHaveBeenLastCalledWith(
        { q: "migration", tag: "", category: "Work" },
        { workspace: "acme" },
      ),
    );

    // Selecting a radio closes the menu (`closeOnClick`), and choosing a category makes the
    // gear's own accessible name grow "(filtered)" — so the reopen has to match that, not the
    // plain label from the first open.
    fireEvent.click(screen.getByRole("button", { name: /^Notes list options/ }));
    expect(await screen.findByRole("menuitem", { name: "Category: Work" })).not.toBeNull();
    fireEvent.click(await screen.findByRole("menuitem", { name: /^Tag:/ }));
    fireEvent.click(await screen.findByRole("menuitemradio", { name: "meeting" }));

    await waitFor(() =>
      expect(list).toHaveBeenLastCalledWith(
        { q: "migration", tag: "meeting", category: "Work" },
        { workspace: "acme" },
      ),
    );
  });

  it("offers a tag the vocabulary read delivers after the notes", async () => {
    // The Tag menu's options are the tag vocabulary read, held back here until the notes AND the
    // category rows are on screen, so it lands when nothing else on any published level moves.
    // The gear is a React node, which the rail host's publish key cannot see: before the level
    // carried `filterKey`, a vocabulary that arrived last never reached the menu, which offered
    // only "All tags".
    let landTags: (tags: NoteTag[]) => void = () => {};
    tagSet.mockReturnValue(
      new Promise<NoteTag[]>((resolve) => {
        landTags = resolve;
      }),
    );
    renderPane();
    await screen.findByRole("button", { name: "Standup" });
    await screen.findByRole("button", { name: "Work" });
    await act(async () => {
      landTags([
        { id: "kw-1", label: "meeting" },
        { id: "kw-2", label: "retro" },
      ]);
    });

    fireEvent.click(screen.getByRole("button", { name: "Notes list options" }));
    fireEvent.click(await screen.findByRole("menuitem", { name: /^Tag:/ }));
    expect(await screen.findByRole("menuitemradio", { name: "retro" })).not.toBeNull();
  });

  // The gear writes through the pane's setter, and the level re-registers with every filter it
  // draws. Both halves were missing: with a tag on, clearing the category moved no plain field —
  // `filtering` only moves when the filter set empties or fills, and the list key came back to a
  // cached, identical result — so the gear stayed on "Category: Work", and the next pick spread
  // that stale snapshot and put the cleared category straight back.
  it("keeps a cleared filter cleared when the other one is picked next", async () => {
    renderPane();
    await screen.findByRole("button", { name: "Standup" });
    const toolbar = within(screen.getByTestId("toolbar-notebook-notes"));
    const pick = async (axis: RegExp, option: string) => {
      fireEvent.click(toolbar.getByRole("button", { name: /^Notes list options/ }));
      fireEvent.click(await screen.findByRole("menuitem", { name: axis }));
      // Choosing a radio closes the menu (`closeOnClick`), so every pick reopens the gear.
      fireEvent.click(await screen.findByRole("menuitemradio", { name: option }));
    };

    await pick(/^Tag:/, "meeting");
    await waitFor(() =>
      expect(list).toHaveBeenLastCalledWith(
        { q: "", tag: "meeting", category: "" },
        { workspace: "acme" },
      ),
    );
    await pick(/^Category:/, "Work");
    await waitFor(() =>
      expect(list).toHaveBeenLastCalledWith(
        { q: "", tag: "meeting", category: "Work" },
        { workspace: "acme" },
      ),
    );
    await pick(/^Category:/, "All categories");
    // Past the debounce, so the list is back on the tag-only key the first pick already read.
    await act(async () => {
      await new Promise((resolve) => setTimeout(resolve, 300));
    });

    fireEvent.click(toolbar.getByRole("button", { name: "Notes list options (filtered)" }));
    expect(await screen.findByRole("menuitem", { name: "Category: all categories" })).not.toBeNull();
    fireEvent.click(await screen.findByRole("menuitem", { name: "Tag: meeting" }));
    fireEvent.click(await screen.findByRole("menuitemradio", { name: "All tags" }));

    // Nothing narrows any more: the gear drops its "(filtered)" mark, and both axes read all-pass.
    fireEvent.click(await toolbar.findByRole("button", { name: "Notes list options" }));
    expect(await screen.findByRole("menuitem", { name: "Category: all categories" })).not.toBeNull();
    expect(screen.getByRole("menuitem", { name: "Tag: all tags" })).not.toBeNull();
  });

  it("publishes onto the notes level's own toolbar, not some shared strip", async () => {
    renderPane();
    await screen.findByRole("button", { name: "Standup" });

    // Scoped to the notes level's own toolbar node, not just "somewhere in the document" — an
    // unscoped query would pass just as well if these had landed on the categories level's
    // toolbar instead.
    const toolbar = within(screen.getByTestId("toolbar-notebook-notes"));
    expect(toolbar.getByLabelText("Search notes")).not.toBeNull();
    expect(toolbar.getByRole("button", { name: "Create Note" })).not.toBeNull();
    expect(toolbar.getByRole("button", { name: "Notes list options" })).not.toBeNull();
  });

  it("asks for nothing when the rail and the filter name different categories", async () => {
    categories.mockResolvedValue([structuredClone(WORK), structuredClone(PERSONAL)]);
    renderPane({ categorySlugs: ["work"] });
    await screen.findByRole("button", { name: "Standup" });
    const before = list.mock.calls.length;

    fireEvent.click(screen.getByRole("button", { name: "Notes list options" }));
    fireEvent.click(await screen.findByRole("menuitem", { name: /^Category:/ }));
    fireEvent.click(await screen.findByRole("menuitemradio", { name: "Personal" }));

    // A note has one category, so the intersection is empty — and an empty answer needs no
    // request. The list has to actually empty out, not keep showing the pre-filter rows.
    await waitFor(() => expect(screen.queryByRole("button", { name: "Standup" })).toBeNull());
    expect(list.mock.calls.length).toBe(before);
  });

  it("opens the tag editor, which renames by id", async () => {
    renderPane();
    await screen.findByRole("button", { name: "Standup" });

    fireEvent.click(screen.getByRole("button", { name: "Notes list options" }));
    fireEvent.click(await screen.findByRole("menuitem", { name: "Edit tags…" }));
    const field = await screen.findByLabelText("Name of tag meeting");
    fireEvent.change(field, { target: { value: "standup" } });
    fireEvent.keyDown(field, { key: "Enter" });

    // By id, never by label: `content.keyword_items` links to the row, so the rename carries
    // every note wearing it.
    await waitFor(() => expect(renameTag).toHaveBeenCalledWith("kw-1", "standup"));
  });
});

describe("creating a note", () => {
  it("asks for the body, category and tags — and no title", async () => {
    renderPane();
    await screen.findByRole("button", { name: "Standup" });

    fireEvent.click(screen.getByRole("button", { name: "Create Note" }));
    const dialog = within(await screen.findByRole("dialog", { name: "New note" }));

    // The title is the body's first line, derived by the backend, so there is nothing to type.
    expect(dialog.queryByLabelText("Title")).toBeNull();
    fireEvent.change(dialog.getByLabelText("Note"), {
      target: { value: "# Retro\n\nWhat went well." },
    });
    await act(async () => {
      dialog.getByRole("button", { name: "Save" }).click();
    });

    expect(create).toHaveBeenCalledWith(
      { content: "# Retro\n\nWhat went well." },
      { workspace: "acme" },
    );
  });

  it("refuses an empty body, so no note is minted that can never be saved again", async () => {
    renderPane();
    await screen.findByRole("button", { name: "Standup" });

    fireEvent.click(screen.getByRole("button", { name: "Create Note" }));
    const dialog = within(await screen.findByRole("dialog", { name: "New note" }));
    // Adding only a tag makes the draft dirty — Save goes live — but the create still has to
    // refuse, and say why rather than failing at the backend with a shape error.
    fireEvent.change(dialog.getByLabelText("Add a tag"), { target: { value: "retro" } });
    await act(async () => {
      dialog.getByRole("button", { name: "Save" }).click();
    });

    expect(dialog.getByText("A note body is required.")).not.toBeNull();
    expect(create).not.toHaveBeenCalled();
  });
});

describe("the Save button", () => {
  it("enables when a tag is added to an open note", async () => {
    // The reported defect, at its simplest: adding classification IS an edit.
    renderPane({ noteId: "note-1" });
    await waitFor(() => expect(get).toHaveBeenCalledWith("note-1", { workspace: "acme" }));

    const save = (await screen.findByRole("button", { name: "Save" })) as HTMLButtonElement;
    expect(save.disabled).toBe(true);

    fireEvent.change(await screen.findByLabelText("Add a tag"), { target: { value: "retro" } });

    await waitFor(() => expect(save.disabled).toBe(false));
    await act(async () => {
      save.click();
    });
    expect(update).toHaveBeenCalledWith(
      "note-1",
      expect.objectContaining({ tags: ["meeting", "retro"] }),
      { workspace: "acme" },
    );
  });

  it("says WHY it is disabled on a note that has no body", async () => {
    // The other half of the same report: a note written before a body was required opens
    // invalid and untouched, so Save is grey no matter what is edited. The reason is on the
    // field from the first render — gating it on `dirty` is what hid it.
    get.mockResolvedValue(structuredClone(EMPTY_NOTE));
    renderPane({ noteId: "note-2" });

    expect(await screen.findByText("A note body is required.")).not.toBeNull();
    const save = (await screen.findByRole("button", { name: "Save" })) as HTMLButtonElement;

    fireEvent.change(await screen.findByLabelText("Add a tag"), { target: { value: "retro" } });
    await waitFor(() => expect(screen.getByLabelText("Remove retro")).not.toBeNull());
    expect(save.disabled).toBe(true);

    // Writing the body clears the blocker, and only then does Save come alive.
    fireEvent.change(screen.getByLabelText("Note"), { target: { value: "# Retro" } });
    await waitFor(() => expect(save.disabled).toBe(false));
  });

  it("flags the blocked note's own row while it cannot be saved", async () => {
    get.mockResolvedValue(structuredClone(EMPTY_NOTE));
    list.mockResolvedValue([
      structuredClone(SUMMARY),
      { ...structuredClone(SUMMARY), id: "note-2", title: "Untitled" },
    ]);
    renderPane({ noteId: "note-2" });

    // The row is where the user is looking when they wonder why Save is grey.
    await waitFor(() =>
      expect(levelById("notebook-notes").items.find((i) => i.id === "note-2")?.blocked).toBe(true),
    );
    expect(levelById("notebook-notes").items.find((i) => i.id === "note-1")?.blocked).toBe(false);
  });
});

describe("the notes list options", () => {
  it("carries each note's excerpt, clamped to the stored preview-line count", async () => {
    window.localStorage.setItem("apt:notebook:preview-lines", "3");
    renderPane();
    await screen.findByRole("button", { name: "Standup" });

    const item = levelById("notebook-notes").items[0];
    expect(item.preview).toBe("Discussed the migration and the rollout order.");
    expect(item.previewLines).toBe(3);
  });

  it("drops the preview entirely at zero lines", async () => {
    window.localStorage.setItem("apt:notebook:preview-lines", "0");
    renderPane();
    await screen.findByRole("button", { name: "Standup" });

    // Not "render it with zero lines" — a preview nobody asked for should not be on the row at
    // all, so nothing can leak it through padding or a screen reader.
    expect(levelById("notebook-notes").items[0].preview).toBeUndefined();
  });
});

// The complaint these exist for: "each time I click a topic we fetch the contents from the
// database, this makes the site feel super slow." Each test below asserts a read that does NOT
// happen — which is the only way to state the fix, since a note painted from the cache and one
// painted from a fresh GET look identical on screen.
describe("the cache", () => {
  it("paints a re-opened note from the cache instead of reading it again", async () => {
    renderPane({ noteId: "note-1" });
    const first = (await screen.findByLabelText("Note")) as HTMLTextAreaElement;
    await waitFor(() => expect(first.value).toBe("# Standup\n\nDiscussed the migration."));
    expect(get).toHaveBeenCalledTimes(1);
    cleanup();

    renderPane({ noteId: "note-1" });
    // Synchronous `get…`, not `findBy…`: there is nothing to wait for. The body is on the FIRST
    // paint, and awaiting here would hide the difference between that and a fast refetch.
    const again = screen.getByLabelText("Note") as HTMLTextAreaElement;
    expect(again.value).toBe("# Standup\n\nDiscussed the migration.");
    expect(get).toHaveBeenCalledTimes(1);
  });

  it("warms a hovered row's body, so the click that follows reads nothing", async () => {
    renderPane();
    const row = await screen.findByRole("button", { name: "Standup" });
    await act(async () => {
      fireEvent.pointerEnter(row);
    });
    expect(get).toHaveBeenCalledWith("note-1", { workspace: "acme" });
    cleanup();

    renderPane({ noteId: "note-1" });
    const body = screen.getByLabelText("Note") as HTMLTextAreaElement;
    expect(body.value).toBe("# Standup\n\nDiscussed the migration.");
    // The warm, and nothing since — the click spent no request of its own.
    expect(get).toHaveBeenCalledTimes(1);
  });

  // The instant paint is only safe because of this: a cached copy may be out of date, so the form
  // is READ-ONLY until the server's answer lands. Editing a stale copy and saving it would put
  // fields back that the server has since changed, and nothing on screen would say so.
  it("paints the cached body immediately but keeps it read-only until the server answers", async () => {
    renderPane({ noteId: "note-1" });
    const settled = (await screen.findByLabelText("Note")) as HTMLTextAreaElement;
    await waitFor(() => expect(settled.value).toBe("# Standup\n\nDiscussed the migration."));
    expect(settled.disabled).toBe(false);
    cleanup();

    // Hold the next read open, then mark the entry stale so the remount revalidates. That window —
    // cached copy on screen, server's answer still in flight — is what the assertions below are.
    get.mockReturnValue(new Promise<Note>(() => {}));
    await act(async () => {
      await getToolkitQueryClient().invalidateQueries();
    });

    renderPane({ noteId: "note-1" });
    const body = screen.getByLabelText("Note") as HTMLTextAreaElement;
    expect(body.value).toBe("# Standup\n\nDiscussed the migration.");
    expect(body.disabled).toBe(true);
    // And the one thing that tells the user why: the spinner in front of the list's title.
    expect(screen.getByTestId("busy-notebook-notes")).not.toBeNull();
  });

  it("opens a created note from the create response, with no read at all", async () => {
    renderPane();
    await screen.findByRole("button", { name: "Standup" });
    fireEvent.click(screen.getByRole("button", { name: "Create Note" }));
    const dialog = within(await screen.findByRole("dialog", { name: "New note" }));
    fireEvent.change(dialog.getByLabelText("Note"), {
      target: { value: "# Retro\n\nWhat went well." },
    });
    await act(async () => {
      dialog.getByRole("button", { name: "Save" }).click();
    });
    await waitFor(() => expect(create).toHaveBeenCalled());
    cleanup();

    // The create response IS the server's copy, so opening what was just created costs nothing.
    // (`onSelectNote` is a stub here, so the open is a fresh mount at the created id — which is
    // also what a reload or a shared link does.)
    renderPane({ noteId: "note-1" });
    const body = screen.getByLabelText("Note") as HTMLTextAreaElement;
    expect(body.value).toBe("# Standup\n\nDiscussed the migration.");
    expect(get).not.toHaveBeenCalled();
  });

  // The loader the cache replaced cleared the form error on every selection change. Without a
  // replacement, the message from a failed save on one note greets the user on the next one,
  // attached to a note that never failed.
  it("leaves a failed save's message behind when another note is opened", async () => {
    update.mockRejectedValueOnce(new Error("Backend exploded."));
    get.mockImplementation(async (id) => ({
      ...structuredClone(NOTE),
      id,
      content: `# ${id}\n\nBody.`,
    }));
    const { select } = renderPane({ noteId: "note-1" });
    const body = (await screen.findByLabelText("Note")) as HTMLTextAreaElement;
    await waitFor(() => expect(body.value).toBe("# note-1\n\nBody."));
    fireEvent.change(body, { target: { value: "# note-1 v2\n\nBody." } });
    await act(async () => {
      screen.getByRole("button", { name: "Save" }).click();
    });
    expect(await screen.findByText("Backend exploded.")).not.toBeNull();

    select({ noteId: "note-2" });
    await waitFor(() =>
      expect((screen.getByLabelText("Note") as HTMLTextAreaElement).value).toBe("# note-2\n\nBody."),
    );
    expect(screen.queryByText("Backend exploded.")).toBeNull();
  });
});

// What the conversion is FOR. Every list this pane shows — the notes, the categories, the tags —
// now reads through the shared cache, so a scope already visited paints on the first frame
// instead of blanking to "Loading…" while it is read again.
describe("the lists read through the cache", () => {
  const WORK_NOTE: NoteSummary = { ...SUMMARY, id: "note-9", title: "Roadmap", category: "Work" };

  it("reads each category scope once, and repaints the one already read", async () => {
    // The rows say which scope is on screen: the backend filters by EXACT name, so "Work" and
    // the whole notebook are two different answers.
    list.mockImplementation(async (f) =>
      f?.category === "Work" ? [structuredClone(WORK_NOTE)] : [structuredClone(SUMMARY)],
    );
    const { select } = renderPane();
    expect(await screen.findByRole("button", { name: "Standup" })).not.toBeNull();
    expect(list).toHaveBeenCalledTimes(1);

    select({ categorySlugs: ["work"] });
    expect(await screen.findByRole("button", { name: "Roadmap" })).not.toBeNull();
    expect(list).toHaveBeenCalledTimes(2);

    // Back out. Synchronous, unlike both `findBy`s above: the whole-notebook key was already
    // read, so its rows are on the FIRST frame and nothing is asked of the backend.
    select({ categorySlugs: [] });
    expect(screen.getByRole("button", { name: "Standup" })).not.toBeNull();
    expect(screen.queryByRole("button", { name: "Roadmap" })).toBeNull();
    expect(list).toHaveBeenCalledTimes(2);
  });

  // The debounce moved: it used to delay the REQUEST, and now delays the query KEY. Same 200ms of
  // typing without a read — and, unlike a debounced request, the value typed away from and back
  // to is a repaint rather than a round trip.
  it("spends one read on a settled search, and none on going back to it", async () => {
    // A search answers with nothing, so the rows themselves say which key is on screen.
    list.mockImplementation(async (f) => (f?.q ? [] : [structuredClone(SUMMARY)]));
    renderPane();
    expect(await screen.findByRole("button", { name: "Standup" })).not.toBeNull();
    expect(list).toHaveBeenCalledTimes(1);

    const search = screen.getByLabelText("Search notes");
    fireEvent.change(search, { target: { value: "r" } });
    fireEvent.change(search, { target: { value: "ro" } });
    fireEvent.change(search, { target: { value: "roa" } });
    await waitFor(() => expect(screen.queryByRole("button", { name: "Standup" })).toBeNull());
    // ONE read for three keystrokes, and it is the value the user stopped at.
    expect(list).toHaveBeenCalledTimes(2);
    expect(list).toHaveBeenLastCalledWith(
      { q: "roa", tag: "", category: "" },
      { workspace: "acme" },
    );

    fireEvent.change(search, { target: { value: "" } });
    await waitFor(() => expect(screen.getByRole("button", { name: "Standup" })).not.toBeNull());
    // The unfiltered rows came back from the cache: the key returned to one already read.
    expect(list).toHaveBeenCalledTimes(2);
  });

  it("paints all three lists from cache on a remount, reading each once", async () => {
    renderPane();
    expect(await screen.findByRole("button", { name: "Standup" })).not.toBeNull();
    expect(await screen.findByRole("button", { name: "Work" })).not.toBeNull();
    expect(list).toHaveBeenCalledTimes(1);
    expect(categories).toHaveBeenCalledTimes(1);
    expect(tagSet).toHaveBeenCalledTimes(1);
    cleanup();

    // Synchronous: the notes and the category rows are both on the FIRST paint.
    renderPane();
    expect(screen.getByRole("button", { name: "Standup" })).not.toBeNull();
    expect(screen.getByRole("button", { name: "Work" })).not.toBeNull();
    expect(list).toHaveBeenCalledTimes(1);
    expect(categories).toHaveBeenCalledTimes(1);
    expect(tagSet).toHaveBeenCalledTimes(1);
  });
});

// ── The rail draws a DAG ───────────────────────────────────────────────────────────────
//
// `category-tree.test.ts` pins the FOLD in isolation. What these add is the pane: that a
// category filed in two places is reachable from both through the levels the rail actually
// publishes, and that the chain a click produces names the parent the user came through.
// That last part is the whole reason a node carries its `path` — with only an id, both
// routes to Q3 would be the same string and the breadcrumb would be a coin toss.
describe("the rail, for a category filed in two places", () => {
  const PLANNING: NoteCategory = { id: "cat-3", name: "Planning", parentIds: [], sortOrder: 2 };
  const Q3: NoteCategory = {
    id: "cat-4",
    name: "Q3",
    parentIds: ["cat-1", "cat-3"],
    sortOrder: 3,
  };

  beforeEach(() => {
    categories.mockResolvedValue([
      structuredClone(WORK),
      structuredClone(PLANNING),
      structuredClone(Q3),
    ]);
  });

  it("lists both parents at the root, sorted by name after the two synthetic rows", async () => {
    renderPane();
    await screen.findByRole("button", { name: "Work" });

    const level = levelById("notebook-categories-0");
    // The shared hook sorts every level by name; the two synthetic rows still lead. No
    // sublabel: the spec says a category row shows the name and nothing else.
    expect(level.items.map((i) => i.label)).toEqual(["All", "Uncategorized", "Planning", "Work"]);
  });

  it("shows Q3 under Work", async () => {
    renderPane({ categorySlugs: ["work"] });
    await screen.findByRole("button", { name: "Work" });

    expect(levelById("notebook-categories-1").items.map((i) => i.label)).toEqual(["Q3"]);
  });

  it("shows the same Q3 under Planning", async () => {
    // The assertion that would be false for a tree: one row, two homes, neither of them a
    // copy the user has to keep in sync.
    renderPane({ categorySlugs: ["planning"] });
    await screen.findByRole("button", { name: "Planning" });

    expect(levelById("notebook-categories-1").items.map((i) => i.label)).toEqual(["Q3"]);
  });

  it("navigates through the parent the user actually came from", async () => {
    const { onSelectCategory } = renderPane({ categorySlugs: ["planning"] });
    await screen.findByRole("button", { name: "Planning" });

    levelById("notebook-categories-1").onSelect?.("q3");
    // ["work", "q3"] would end at the same category and still be the wrong answer: it is the
    // route, not the destination, that the breadcrumb and the Back button are built from.
    expect(onSelectCategory).toHaveBeenLastCalledWith(["planning", "q3"]);
  });

  it("selects Q3 in the level it was reached through", async () => {
    renderPane({ categorySlugs: ["planning", "q3"] });
    await screen.findByRole("button", { name: "Planning" });

    expect(levelById("notebook-categories-1").selectedId).toBe("q3");
    expect(levelById("notebook-categories-0").selectedId).toBe("planning");
  });
});
