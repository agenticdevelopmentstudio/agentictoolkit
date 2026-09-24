// @vitest-environment jsdom
//
// The corpus binding — that `NotebookPane` under `DOCS_CORPUS` is genuinely a second shelf and
// not the notes shelf wearing different words.
//
// `NotebookPane.test.tsx` covers the SURFACE (levels, filtering, create, save) once, under the
// default notes corpus, and none of that behaviour is corpus-dependent — re-running it here
// would buy a second copy of the same evidence. What is NOT covered there is the only thing
// that differs, and it is the thing a regression would silently break: which client the pane
// reads and writes through. A corpus wired to `notesApi` by accident would still render, still
// filter, still save — and quietly file every document into the wrong bucket. So these tests
// assert the seam: `docsApi` is called, `notesApi` is not, and the rail level and its toolbar
// carry the document nouns rather than the note ones.
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
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

// Both clients are mocked, because the assertion that matters is a NEGATIVE one: the notes
// client has to be present and observable for "it was never called" to mean anything.
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

vi.mock("@agentic-toolkit/data/docs", () => ({
  docsApi: {
    list: vi.fn(),
    get: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    remove: vi.fn(),
    categories: vi.fn(),
    tagSet: vi.fn(),
    createCategory: vi.fn(),
  },
}));

import { NotebookPane } from "./NotebookPane";
import { DOCS_CORPUS } from "./corpus";
import {
  notesApi,
  type Note,
  type NoteCategory,
  type NoteSummary,
} from "@agentic-toolkit/data/notes";
import { docsApi } from "@agentic-toolkit/data/docs";

const docs = {
  list: vi.mocked(docsApi.list),
  get: vi.mocked(docsApi.get),
  create: vi.mocked(docsApi.create),
  categories: vi.mocked(docsApi.categories),
  tagSet: vi.mocked(docsApi.tagSet),
};

const SUMMARY: NoteSummary = {
  id: "doc-1",
  title: "Onboarding checklist",
  excerpt: "Everything a new hire needs in week one.",
  category: "Work",
  tags: [],
  visibility: "private",
  publicRoute: null,
};

const DOC: Note = {
  id: "doc-1",
  title: "Onboarding checklist",
  content: "# Onboarding checklist\n\nWeek one.",
  category: "Work",
  tags: [],
  visibility: "private",
  publicRoute: null,
};

const WORK: NoteCategory = {
  id: "cat-1",
  name: "Work",
  parentIds: [],
  sortOrder: 0,
};

beforeEach(() => {
  vi.clearAllMocks();
  window.localStorage.clear();
  docs.list.mockResolvedValue([structuredClone(SUMMARY)]);
  docs.get.mockResolvedValue(structuredClone(DOC));
  docs.create.mockResolvedValue(structuredClone(DOC));
  docs.categories.mockResolvedValue([structuredClone(WORK)]);
  docs.tagSet.mockResolvedValue([]);
});

afterEach(cleanup);

let levels: TopicLevel[] = [];

function levelById(id: string): TopicLevel {
  const hit = levels.find((l) => l.id.startsWith(id));
  if (!hit)
    throw new Error(
      `no published level starting with ${id}: ${levels.map((l) => l.id)}`,
    );
  return hit;
}

/** The same minimal rail host `NotebookPane.test.tsx` uses: it renders the published levels and
 *  hands the test the level objects, so a level's SHAPE can be asserted on. Each level's `+`,
 *  search and gear render on ITS OWN toolbar, scoped via `data-testid={`toolbar-${l.id}`}` —
 *  they rode the page-wide home bar until that strip was removed as clunky (Mike, 2026-09-24). */
function Harness({ children }: { children: ReactNode }) {
  const [entries, setEntries] = useState<Map<string, RegisteredLevels>>(
    new Map(),
  );
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
  levels = [...entries.values()]
    .sort((a, b) => a.depth - b.depth)
    .flatMap((e) => e.levels);
  return (
    <RailHostContext.Provider value={registry}>
      <div>
        {levels.map((l) => (
          <div key={l.id}>
            <h3>{l.title}</h3>
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
                  onChange={(e) => l.search?.onQueryChange(e.target.value)}
                />
              )}
              {l.titleActions}
            </div>
            <ul>
              {l.items.map((item) => (
                <li key={item.id}>
                  <button type="button" onClick={() => l.onSelect?.(item.id)}>
                    {item.label}
                  </button>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>
      {children}
    </RailHostContext.Provider>
  );
}

function renderDocsPane() {
  render(
    <Harness>
      <NotebookPane
        categorySlugs={[]}
        onSelectCategory={vi.fn()}
        onSelectNote={vi.fn()}
        workspaceSlug="acme"
        corpus={DOCS_CORPUS}
      />
    </Harness>,
  );
}

describe("the docs corpus", () => {
  it("reads through the docs client and never touches the notes one", async () => {
    renderDocsPane();
    await screen.findByRole("button", { name: "Onboarding checklist" });

    expect(docs.list).toHaveBeenCalled();
    expect(docs.categories).toHaveBeenCalled();
    // The whole point of the corpus seam: a document read through `notesApi` would be filed
    // under `content.notes`, in the notes bucket, and appear on the wrong shelf.
    expect(notesApi.list).not.toHaveBeenCalled();
    expect(notesApi.categories).not.toHaveBeenCalled();
  });

  it("publishes its own rail level, named for documents", async () => {
    renderDocsPane();
    await screen.findByRole("button", { name: "Onboarding checklist" });

    // Ids are addressed by hosts and by tests, so a corpus that reused the notebook's would
    // collide with a notebook pane mounted beside it in the same rail.
    expect(levels[0]!.id).toBe("docs-categories-0");
    const level = levelById("docs-documents");
    expect(level.title).toBe("Documents");
    expect(level.items.map((i) => i.label)).toEqual(["Onboarding checklist"]);
  });

  it("carries the document nouns onto the documents level's own toolbar", async () => {
    renderDocsPane();
    await screen.findByRole("button", { name: "Onboarding checklist" });

    // Its own level's toolbar, not "somewhere in the document" — pins the search box and the
    // create button to the documents level specifically, since an unscoped query would pass
    // just as well if these had landed on the categories level's toolbar instead.
    const toolbar = within(screen.getByTestId("toolbar-docs-documents"));
    expect(toolbar.getByLabelText("Search documents")).not.toBeNull();
    expect(toolbar.getByRole("button", { name: "Create Document" })).not.toBeNull();
  });

  it("creates through the docs client", async () => {
    renderDocsPane();
    await screen.findByRole("button", { name: "Onboarding checklist" });

    fireEvent.click(screen.getByRole("button", { name: "Create Document" }));
    const dialog = within(
      await screen.findByRole("dialog", { name: "New document" }),
    );
    // The body field is labelled for the corpus too — a docs surface asking for a "Note" would
    // be telling the user they are somewhere else.
    fireEvent.change(dialog.getByLabelText("Document"), {
      target: { value: "# Expenses\n\nHow to file one." },
    });
    await act(async () => {
      dialog.getByRole("button", { name: "Save" }).click();
    });

    await waitFor(() =>
      expect(docs.create).toHaveBeenCalledWith(
        { content: "# Expenses\n\nHow to file one." },
        { workspace: "acme" },
      ),
    );
    expect(notesApi.create).not.toHaveBeenCalled();
  });
});
