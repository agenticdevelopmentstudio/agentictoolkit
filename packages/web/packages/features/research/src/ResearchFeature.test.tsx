// @vitest-environment jsdom
//
// Component test for ResearchFeature — the /research workspace: a master/detail surface over
// the signed-in user's markdown research documents. Only the data domain boundary
// (@agentic-toolkit/data/markdown), the Next navigation hook, and @agentic-toolkit/auth's
// useAuth are mocked, so the list-publish → create → open-via-URL wiring is exercised, not the
// transport.
//
// ResearchPane PUBLISHES its documents as a rail level, now preceded by the shared hierarchical
// category rail (via StackLevels, not a bare useStackLevel — the category depth varies with how
// far the user has walked in) into a rail HOST rather than rendering its own list — the button
// bar (Save/Cancel/Delete) is the only thing MasterDetailLeaf renders directly. So the harness
// below (mirroring ProjectsFeature.test.tsx's Rail) renders every published level's items flatly
// (no stack-frontier simulation), standing in for the hub's workspace shell. The category tree
// mock defaults to empty (see `categoryTree.mockResolvedValue([])` below), so the rail's own
// depth-0 level publishes only its two synthetic rows ("All"/"Uncategorized") in every test here
// — none of them exercise walking into a real category, which is covered by
// `@agentic-toolkit/categories`' own suite and by NotebookPane.test.tsx.
//
// The pane's two page-level controls (search/category/tag filters and the "Create Document"
// create) are no longer a page-wide strip: that HOME BAR was removed as clunky (Mike,
// 2026-09-24), and both now ride the documents level's own TOOLBAR (the row under a rail's
// title, `search`/`onNew`/`titleActions` on the published `TopicLevel` — see `topic-detail.tsx`'s
// `data-htd-toolbar`). This file's `Rail` stand-in (below) renders each level's toolbar itself,
// scoped per level id, so a test can tell "wired to this level" from "wired to some other one".
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { act, render, screen, fireEvent, waitFor, within, cleanup } from "@testing-library/react";
import { useMemo, useState, type ReactNode } from "react";
import {
  RailHostContext,
  useHostDetailTitle,
  type RailHostRegistry,
  type RegisteredLevels,
} from "@agentic-toolkit/resource";
import type { TopicLevel } from "@agenticdevelopertoolkit/ui/blocks";

// useBasePathRoute (ResearchFeature's URL wiring) reads next/navigation's useRouter; a stub is
// enough for most tests, which assert on the API calls rather than the resulting route. The
// "two bases" tests below (docBasePath !== basePath) DO assert on the route, so `push` is hoisted
// to one shared spy rather than minted fresh per `useRouter()` call — a fresh `vi.fn()` per call
// would leave no way to read back what a later render's `pushSegment` actually did.
const { push } = vi.hoisted(() => ({ push: vi.fn() }));
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push, replace: vi.fn(), prefetch: vi.fn() }),
}));

// ResearchPane reads useAuth() directly (for the userSlug fallback) — stub a signed-in user so
// it renders without an AuthProvider. reportUnexpectedAuthError is a no-op logger here.
vi.mock("@agentic-toolkit/auth", () => ({
  useAuth: () => ({ user: { name: "Ada Lovelace" } }),
  reportUnexpectedAuthError: vi.fn(),
}));

// `categoryTree` + `createCategory` (markdownApi) and the whole `taxonomyApi` sibling export are
// what the shared rail (`@agentic-toolkit/categories`' `useCategoryLevels`) reads and writes —
// see NotebookPane.test.tsx's identical pair of mocks, which this one mirrors now that
// ResearchPane draws the same rail. Every write fn (`renameCategory`/`addCategoryParent`/etc.) is
// exercised only if a test opens the gear menu; none here do yet, but a bare `vi.fn()` with no
// default keeps a stray call loud (an unmocked resolution) rather than silently `undefined`.
vi.mock("@agentic-toolkit/data/markdown", () => ({
  markdownApi: {
    list: vi.fn(),
    get: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    categories: vi.fn(),
    categoryTree: vi.fn(),
    createCategory: vi.fn(),
    tags: vi.fn(),
    routeAvailable: vi.fn(),
    publish: vi.fn(),
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
import { ResearchFeature } from "./ResearchFeature";
import { markdownApi, type ResearchDocument, type ResearchSummary } from "@agentic-toolkit/data/markdown";
import { parseResearchPath, researchSegments } from "./parse-path";

const list = vi.mocked(markdownApi.list);
const get = vi.mocked(markdownApi.get);
const create = vi.mocked(markdownApi.create);
const update = vi.mocked(markdownApi.update);
const categories = vi.mocked(markdownApi.categories);
const categoryTree = vi.mocked(markdownApi.categoryTree);
const tags = vi.mocked(markdownApi.tags);
const routeAvailable = vi.mocked(markdownApi.routeAvailable);
const publish = vi.mocked(markdownApi.publish);

const SUMMARY: ResearchSummary = {
  id: "doc-1",
  title: "Federated learning notes",
  category: "ml",
  tags: ["notes"],
  visibility: "private",
  publicRoute: null,
};

const DOCUMENT: ResearchDocument = {
  id: "doc-1",
  title: "Federated learning notes",
  content: "# Federated learning\n\nSome notes.",
  category: "ml",
  tags: ["notes"],
  visibility: "private",
  publicRoute: null,
};

// Incremented once per `beforeEach` run — the mechanism the G1 pin (below, "Deliberately
// declaration-order dependent") uses to turn its own adjacency requirement into an enforced
// assertion instead of a comment nobody has to obey. See the pin for how the two `let`s below
// are used together.
let beforeEachRunCount = 0;
// The `beforeEachRunCount` value G1 pin (1/2) recorded as its last action, so (2/2) can assert
// that exactly one `beforeEach` — its own — ran in between, i.e. that no test was inserted
// between the pair. `null` until (1/2) runs.
let g1PinRecordedBeforeEachCount: number | null = null;

beforeEach(() => {
  beforeEachRunCount++;
  // `vi.clearAllMocks()` (`.mockClear()` on every mock) drops call history but NOT a
  // still-queued `mockResolvedValueOnce`/`mockRejectedValueOnce` implementation — verified by
  // running it: a value queued by a test that throws (or otherwise returns) before consuming
  // it stays queued and leaks into the NEXT test's call to the same mock. `vi.resetAllMocks()`
  // (`.mockReset()` on every mock) additionally drops that queue AND any base implementation
  // set via `mockResolvedValue`/`mockImplementation` — including a base set by a PREVIOUS
  // test's own call to one of those, which a reset wipes just as thoroughly as one set here.
  // (The `vi.mock` factory above no longer sets a base for anything — every mock there is a
  // bare `vi.fn()` — so this `beforeEach` is the single place any default comes from.) That is
  // why every default the suite relies on is re-established below,
  // explicitly, in this same `beforeEach`: it is the only way to reset the *Once queue for
  // every mock (closing the leak class for all of them, not just the two — `update` and
  // `publish` — that a prior version of this comment singled out) while still giving each test
  // the same starting state.
  vi.resetAllMocks();
  list.mockResolvedValue([structuredClone(SUMMARY)]);
  get.mockResolvedValue(structuredClone(DOCUMENT));
  create.mockResolvedValue(structuredClone(DOCUMENT));
  categories.mockResolvedValue([]);
  // Empty tree: no test below exercises the rail's own category rows (only the synthetic
  // "All"/"Uncategorized" rows depth 0 always publishes), so this keeps every existing
  // assertion's set of on-screen rows exactly what it was before the rail existed.
  categoryTree.mockResolvedValue([]);
  tags.mockResolvedValue([]);
  routeAvailable.mockResolvedValue({ available: true, reason: "ok" });
});

// Explicit and redundant, deliberately: this package's vitest runs with `globals: true`
// (packages/web/packages/features/vitest.preset.ts:16), so RTL 16.3.2's own shipped
// `afterEach(cleanup)` DOES register (@testing-library/react/dist/index.js:23-30), and cleanup
// is idempotent. An earlier version of this comment asserted the opposite — no global afterEach,
// auto-cleanup never registers — and both halves were false. Keep the call if you like it as a
// local statement of intent; do not "fix" the config to match the claim that was here.
afterEach(cleanup);

// The cache a document is re-opened FROM is emptied between tests by the package's `vitest-setup`
// teardown — without it a document a previous test opened is still cached and still fresh, so the
// next test's `get` is never called and its assertion fails describing the feature working
// correctly. The tests below therefore each start from an empty cache.

/** Renders the published rail level (the document rows) the way the hub's workspace shell would,
 *  so the test can drive the rows — plus each level's own TOOLBAR (the `+` from `onNew`/
 *  `newLabel`, a controlled search box from `search`, and `titleActions`, the gear menu), scoped
 *  inside a `data-testid={`toolbar-${l.id}`}` wrapper so a test can scope `within()` it rather
 *  than trusting that nothing else on the page could satisfy an unscoped query. Mirrors the real
 *  rail's `data-htd-toolbar` (`topic-detail.tsx`), standing in for it since this harness draws its
 *  own minimal rail rather than the real one — the page-wide home bar these controls used to
 *  publish into was removed as clunky (Mike, 2026-09-24). The three are drawn in the real rail's
 *  order, `+` first, but ORDER is not this stand-in's to prove: the real rail decides it (and pops
 *  its search over from a magnifier where this draws the field outright), so it is pinned against
 *  the real rail, in `@agenticdevelopertoolkit/ui`'s `topic-rail-toolbar.test.tsx`. An earlier
 *  stand-in drew the `+` LAST, and a placement test here pinned that order — the opposite of the
 *  real toolbar's.
 *
 *  A level with no rows shows its `emptyLabel`, as the real rail does. The toolbar is published
 *  before the list resolves, so that text is how a test knows it is looking at the LOADED empty
 *  list rather than the loading one.
 *
 *  It also stands in for the two signals the real `TopicRail` owns: the header spinner it shows
 *  while `busy`, and the hover dwell after which it calls `onPrefetch`. The dwell's TIMING is the
 *  rail's own business (and is tested there); what belongs here is whether this pane wires the
 *  two at all — which is exactly the thing a typechecked optional prop cannot tell you. */
function Rail({ levels }: { levels: TopicLevel[] }) {
  return (
    <div>
      {levels.map((l) => (
        <div key={l.id}>
          {l.busy && <span data-testid={`busy-${l.id}`} />}
          {/* Wiring-level stand-in for the real rail's icon column: not rendering one is the
           *  observable effect of `hideItemIcons`, which nothing here otherwise reads. */}
          <span data-testid={`hide-item-icons-${l.id}`}>{String(Boolean(l.hideItemIcons))}</span>
          <div data-testid={`toolbar-${l.id}`}>
            {l.onNew ? (
              <button type="button" onClick={() => l.onNew?.()}>
                {l.newLabel}
              </button>
            ) : null}
            {l.search ? (
              <input
                type="search"
                aria-label={l.search.placeholder}
                value={l.search.query}
                onChange={(e) => l.search?.onQueryChange?.(e.target.value)}
              />
            ) : null}
            {l.titleActions}
          </div>
          {l.items.length === 0 && <p>{l.emptyLabel}</p>}
          <ul>
            {l.items.map((item) => (
              <li key={item.id}>
                <button
                  type="button"
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

/** A minimal rail HOST: it registers ResearchPane's published documents level and exposes the
 *  merged stack the way the hub's workspace shell would (the shell owns `mergedLevels`; this
 *  package owns only the RailHostContext contract). Stands in for the host so the published
 *  document rows AND their toolbar's own controls (rendered by `Rail` above) are drivable. No
 *  `HomeBarHost` any more: the controls ride the documents level's own `search`/`onNew`/
 *  `titleActions` now, so `Rail` above is the whole story.
 *
 *  `setDetailTitle`/`detailTitle` are wired through the package's own {@link useHostDetailTitle} —
 *  the REAL host-side hook every production host (StandaloneRailHost, the hub's
 *  WorkspaceChromeProvider) uses to turn `useDetailTitle` publishes into the string HTDV's
 *  `detailTitle` prop receives — rather than a hand-rolled stand-in, so what this test exercises
 *  is the actual merge logic, not a re-implementation of it. The rendered `detail-title` node
 *  stands in for HTDV's own title strip (`hierarchical-topic-detail.tsx`'s `detailTitle` slot),
 *  which lives in `@agenticdevelopertoolkit/ui` and is not something this harness renders — this package
 *  has no test coverage of HTDV itself, only of what reaches its host-side boundary. */
function Harness({ children }: { children: ReactNode }) {
  const [entries, setEntries] = useState<Map<string, RegisteredLevels>>(new Map());
  const { setDetailTitle, detailTitle } = useHostDetailTitle();
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
      setDetailTitle,
      toolbarSlot: null,
    }),
    [setDetailTitle],
  );
  const mergedLevels = [...entries.values()]
    .sort((a, b) => a.depth - b.depth)
    .flatMap((e) => e.levels);
  return (
    <RailHostContext.Provider value={registry}>
      {/* Stand-in for HTDV's title strip: same string {@link useHostDetailTitle} would hand
          the real detail header, rendered here so a test can read it back. Empty (not
          missing) when no pane is publishing, so "cleared" and "never rendered" both read as
          the same empty string rather than a testid that disappears from the DOM. */}
      <div data-testid="detail-title">{detailTitle ?? ""}</div>
      <Rail levels={mergedLevels} />
      {children}
    </RailHostContext.Provider>
  );
}

describe("ResearchFeature", () => {
  it("publishes the documents list from markdownApi.list", async () => {
    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" />
      </Harness>,
    );

    expect(await screen.findByText("Federated learning notes")).not.toBeNull();
    expect(list).toHaveBeenCalled();
  });

  it("creates a document through the Documents list's toolbar Create Document button", async () => {
    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" />
      </Harness>,
    );

    // Clicked THROUGH the toolbar, not through `screen`: this is the button the user now has,
    // scoped to the documents level's own toolbar rather than trusting that nothing else on the
    // page could satisfy an unscoped query. It opens the CREATE MODAL (HTD `must-create-in-modal`):
    // the title, plus the category that places it. The title is asked for here rather than a body
    // left to the editor because it is now the document's NAME — its first heading — so an empty
    // create would mint an "Untitled" row the user then has to go and find.
    const toolbar = within(await screen.findByTestId("toolbar-research-documents"));
    fireEvent.click(toolbar.getByRole("button", { name: "Create Document" }));

    // Scope to the dialog: the editor's portaled action bar has its own Save button.
    const dialog = within(screen.getByRole("dialog", { name: "New document" }));
    // Anchored regex, not the bare string: `Field` renders the hint INSIDE the <label>, so the
    // accessible name is "Title The document's first heading; you can edit the rest in the
    // editor."
    fireEvent.change(dialog.getByLabelText(/^Title/), {
      target: { value: "Hello research" },
    });
    fireEvent.click(dialog.getByRole("button", { name: "Save" }));

    await waitFor(() =>
      expect(create).toHaveBeenCalledWith(
        // A blank category and an empty tag list are omitted from the create body. The title
        // becomes the document's first heading — nothing else is sent, since the rest of the
        // body is written in the editor after the record is placed.
        { content: "# Hello research\n\n" },
        // No workspaceSlug prop in this harness → creator-owned (workspace undefined).
        { workspace: undefined },
      ),
    );
  });

  it("opens the selected document (deep link via docId) with its body loaded", async () => {
    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-1" />
      </Harness>,
    );

    // The body loads, and the identity field above it shows the title this body derives — Task
    // 16 gave the editor a Title input; it edits the frontmatter, not a separate field.
    const body = (await screen.findByLabelText("Markdown body")) as HTMLTextAreaElement;
    await waitFor(() => expect(body.value).toBe("# Federated learning\n\nSome notes."));
    expect(screen.getByLabelText("Title")).toHaveValue("Federated learning");
    await waitFor(() => expect(get).toHaveBeenCalledWith("doc-1", { workspace: undefined }));
  });

  // Task 11's ask: "the title should show in the header of the HTDV's details pane." Task 16
  // re-pointed this at the DRAFT (`useDetailTitle(draft ? deriveDocumentTitle(draft.content) :
  // null)`) now that the title is editable, so the header follows what the author is typing
  // rather than the saved document's name — "Federated learning" is what `deriveDocumentTitle`
  // reads off `DOCUMENT.content`'s first line, distinct from `DOCUMENT.title` ("Federated
  // learning notes") used elsewhere in this file for the list row / rail button name. A
  // mutation to `useDetailTitle(null)` (publishing nothing, ever) left `resource`'s 95/95 and
  // this package's own 20/20 both green, because nothing here asserted on the PUBLISH side of
  // that call. `resource/src/__tests__/detailTitle.test.tsx` covers the plumbing (a synthetic
  // pane through `useHostDetailTitle`); these two cover the integration point this task
  // actually delivers — that ResearchPane itself is the caller, and that it clears what it
  // published.
  it("publishes the open document's title into the detail header", async () => {
    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-1" />
      </Harness>,
    );

    // The doc loads asynchronously (get() resolves the cached-or-fetched copy); wait for the
    // title to land rather than asserting synchronously.
    await waitFor(() =>
      expect(screen.getByTestId("detail-title").textContent).toBe("Federated learning"),
    );
  });

  // ResearchFeature always wires research's opt-in `urlSelection` (see its own doc), so
  // `selectedId` is URL-driven and fixed by this test's `docId` prop for the life of one render —
  // clicking Cancel only pushes a route through the mocked router (asserted elsewhere, "closing an
  // open document (Cancel) returns to basePath"), it does not itself change `docId` here. So this
  // drives the transition through `rerender` with `docId` dropped, the same way "leaves a failed
  // save's message behind when another document is opened" (below) rerenders onto a new `docId` —
  // that changes `selectedDoc` from the SAME mounted `ResearchPane`, which is what exercises
  // `useDetailTitle`'s own cleanup path (its effect depends on `title`, so a title→null change
  // runs the previous effect's cleanup before the new, no-op-null one).
  it("leaves no stale title once the open document is deselected", async () => {
    const { rerender } = render(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-1" />
      </Harness>,
    );
    await waitFor(() =>
      expect(screen.getByTestId("detail-title").textContent).toBe("Federated learning"),
    );

    rerender(
      <Harness>
        <ResearchFeature basePath="/w1/research" />
      </Harness>,
    );

    await waitFor(() => expect(screen.getByTestId("detail-title").textContent).toBe(""));
  });

  // `canSave` is dirty && valid — the busy term is applied at the button (SaveCancelButtons
  // renders `disabled={!canSave || saving}`), never folded into the predicate. `saving` is a
  // RENDER value, so it cannot also serve as the in-flight guard: two activations inside a
  // single commit (a double-click before React paints the disabled button) both read the
  // pre-save `false` and both PUT. Only the handler's own ref stops the second.
  it("ignores a second Save that lands before the disabled state can render", async () => {
    update.mockReturnValue(new Promise(() => {})); // never settles — the save stays in flight
    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-1" />
      </Harness>,
    );

    const body = (await screen.findByLabelText("Markdown body")) as HTMLTextAreaElement;
    await waitFor(() => expect(body.value).toBe("# Federated learning\n\nSome notes."));
    fireEvent.change(body, { target: { value: "# Federated learning v2\n\nSome notes." } });

    const save = screen.getByRole("button", { name: "Save" });
    await act(async () => {
      save.click();
      save.click();
    });

    expect(update).toHaveBeenCalledTimes(1);
  });

  // The counterpart to the guard above: that ref is released in `finally`, so it also releases
  // when the PUT throws. Nothing pinned that — move the reset onto the success path and one 500
  // leaves `savingRef.current === true` for the rest of the session, with Save silently dead and
  // nothing on screen saying why.
  it("releases the in-flight latch when the save THROWS, so a retry still fires", async () => {
    update
      .mockRejectedValueOnce(new Error("Backend exploded."))
      .mockResolvedValueOnce(structuredClone({ ...DOCUMENT, title: "Federated learning v2" }));
    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-1" />
      </Harness>,
    );

    const body = (await screen.findByLabelText("Markdown body")) as HTMLTextAreaElement;
    await waitFor(() => expect(body.value).toBe("# Federated learning\n\nSome notes."));
    fireEvent.change(body, { target: { value: "# Federated learning v2\n\nSome notes." } });

    const save = screen.getByRole("button", { name: "Save" });
    await act(async () => {
      save.click();
    });
    expect(update).toHaveBeenCalledTimes(1);
    expect(await screen.findByText("Backend exploded.")).not.toBeNull();

    // The draft is untouched by the failure, so Save is live again — and it must actually fire.
    const retry = screen.getByRole("button", { name: "Save" }) as HTMLButtonElement;
    expect(retry.disabled).toBe(false);
    await act(async () => {
      retry.click();
    });
    expect(update).toHaveBeenCalledTimes(2);
  });

  // ── Pins `beforeEach`'s `vi.resetAllMocks()` (G1) ──────────────────────────────
  // Order-dependent by construction: the first test leaves a `mockResolvedValueOnce` on `get`
  // UNCONSUMED (nothing after it calls `get` again), and the second — the very next test vitest
  // runs — asserts the ONLY thing that can be true if `beforeEach` dropped that dangling queue
  // before it started: doc-1 opens with the beforeEach default (`DOCUMENT.content`), not the
  // poisoned response the first test queued. vitest runs a single file's tests in declaration
  // order with shuffling off — this repo does not opt into `sequence.shuffle`
  // (`packages/features/vitest.preset.ts` passes no `sequence` key to `defineConfig`, verified by
  // reading it) — so there is no randomness to worry about.
  //
  // What declaration order does NOT give you is protection against a future edit inserting a
  // test between this pair. Verified by running it: inserting a test that renders and opens a
  // document — the shape of nearly every other test in this file — between the pair, with
  // `vi.resetAllMocks()` reverted to `vi.clearAllMocks()`, left the suite fully green; the
  // interloper consumes the queued `get` response itself, so the regression this pin exists to
  // catch becomes silently undetectable. A comment asking the pair to stay adjacent does not
  // stop that. So adjacency is enforced below as an assertion: `beforeEachRunCount` (declared
  // above, module scope) increments once per `beforeEach` run; (1/2) records its value into
  // `g1PinRecordedBeforeEachCount` as its last action, and (2/2) asserts, as its FIRST action,
  // that exactly one `beforeEach` — its own — has run since. Insert any test between them and
  // that count is off by (at least) one, and the assertion fails and says why, whether or not the
  // interloper happens to touch `get`.
  //
  // `vi.clearAllMocks()` (`.mockClear()`) would leave the queued value in place — it only drops
  // call history — so it would bleed straight into the second test's first `get()` call.
  // `vi.resetAllMocks()` (`.mockReset()`) drops it, which is the one thing this pair exists to
  // require of whatever `beforeEach` does.
  it("G1 pin (1/2): queues a get() response for doc-1 that this test itself never consumes", async () => {
    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-1" />
      </Harness>,
    );
    const body = (await screen.findByLabelText("Markdown body")) as HTMLTextAreaElement;
    await waitFor(() => expect(body.value).toBe(DOCUMENT.content));
    expect(get).toHaveBeenCalledTimes(1);
    // Left dangling on purpose: nothing after this line calls `get` again in THIS test, so this
    // one-shot response is still queued when the file moves on to the next test.
    get.mockResolvedValueOnce({
      ...structuredClone(DOCUMENT),
      content: "# Leaked from G1 pin (1/2)\n\nA queue this stale must never reach a real test.",
    });
    // Last action, deliberately: records how many `beforeEach` runs have happened so far, so
    // (2/2) can assert that exactly one more — its own — ran between here and there.
    g1PinRecordedBeforeEachCount = beforeEachRunCount;
  });

  it("G1 pin (2/2): opens doc-1 with beforeEach's default, not (1/2)'s leaked queue", async () => {
    // First action, deliberately: if a test was inserted between (1/2) and (2/2), more than one
    // `beforeEach` ran since (1/2) recorded its count, and this fails before the render below can
    // paper over it by consuming the leaked queue itself.
    expect(
      beforeEachRunCount,
      "G1 pin (1/2) and (2/2) must remain adjacent test declarations. A test was inserted " +
        "between them, which lets the interloper's own render consume (1/2)'s leaked `get` " +
        "queue — the pin then silently stops testing anything, without any assertion failing " +
        `to say so. (recorded at (1/2): ${g1PinRecordedBeforeEachCount}, now: ${beforeEachRunCount})`,
    ).toBe((g1PinRecordedBeforeEachCount ?? NaN) + 1);
    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-1" />
      </Harness>,
    );
    // Under `vi.clearAllMocks()` this reads "# Leaked from G1 pin (1/2)…" instead — the query
    // cache is emptied between tests (packages/data/vitest-setup.ts), so this IS a fresh `get`
    // call, and a surviving *Once queue is the only thing that could answer it wrongly.
    const body = (await screen.findByLabelText("Markdown body")) as HTMLTextAreaElement;
    await waitFor(() => expect(body.value).toBe(DOCUMENT.content));
  });

  // ── Pins `beforeEach`'s `routeAvailable` default (G2) ───────────────────────────
  // G2's fix deletes the `vi.mock` factory's `routeAvailable.mockResolvedValue(...)` (a dead
  // second writer `vi.resetAllMocks()` wipes before any test body runs) so `beforeEach`'s own
  // `routeAvailable.mockResolvedValue({ available: true, reason: "ok" })` is the sole authority.
  // Nothing above in this file actually depends on that default resolving `available: true` —
  // every existing "unavailable" test overrides it per-test, and the writesPublicRoute gate
  // (ResearchPane.tsx) only ever blocks on `status === "unavailable"`, so a verdict that never
  // settles at all (`idle`) is indistinguishable from `available` to every assertion elsewhere
  // in this file. Verified by running it: deleting `beforeEach`'s `routeAvailable` line (with the
  // factory default already gone) left the suite at 54/54 green, not red — the "surviving
  // declaration is load-bearing" claim G2 makes is false without this pin. `checkSlug` (the
  // callback `useSlugAvailability` awaits) does `res.available` on whatever `routeAvailable`
  // resolves to; with no default at all that is `undefined`, `res.available` throws, and
  // `useSlugAvailability`'s own `.catch()` swallows it into `{ status: "idle" }` — which
  // `document-identity-field.tsx` renders as NO text in its `[data-slot="slug-status"]` span.
  // The default resolving `{ available: true, reason: "ok" }` instead renders "Available" there —
  // the one observable difference between the default doing its job and silently not existing.
  // Not because of `SLUG_REASON.ok`: `document-identity-field.tsx`'s `useSlugAvailability`
  // resolution branch hardcodes `{ status: "available", reason: null }` on the available path and
  // never reads `res.reason` at all, so `SLUG_REASON.ok` being `undefined` (vs. any other string)
  // is irrelevant here — verified by running it: setting `SLUG_REASON.ok` to a string in
  // `ResearchPane.tsx` and reverting left this pin still passing. `document-identity-field.tsx`'s
  // `[data-slot="slug-status"]` span then renders `verdict.reason ?? status`, i.e.
  // `null ?? STATUS_TEXT.available`, which is "Available".
  it("G2 pin: settles the slug availability check to Available from beforeEach's routeAvailable default", async () => {
    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-1" />
      </Harness>,
    );
    await screen.findByLabelText("Markdown body");
    // DOCUMENT is private with no publicRoute, so its slug follows the derived title
    // ("federated-learning") — truthy, which is what makes `useSlugAvailability` fire at all.
    await waitFor(() =>
      expect(document.querySelector('[data-slot="slug-status"]')).toHaveTextContent("Available"),
    );
  });

  // ── Categories and tags wiring (G3) ─────────────────────────────────────────────
  // `categories.mockResolvedValue([])` / `tags.mockResolvedValue([])` in `beforeEach` were dead
  // defaults — verified by running it: deleting both left the suite at 54/54 green, because
  // nothing anywhere in this file observed either call's RESOLVED VALUE, only that the calls
  // happened. That is a coverage hole over `markdownApi.categories()` / `markdownApi.tags()` →
  // `ResearchPane`'s `accountCategories`/`accountTags` → `ResearchDetail`'s `categoryOptions`/
  // `tagOptions` → `CategoriesAndTags` (`external/agenticdevelopertoolkit/packages/web/packages/ui/src/blocks/categories-and-tags.tsx`) — the
  // seam `external/agenticdevelopertoolkit/packages/web/packages/ui/src/__tests__/categoriesAndTags.test.tsx` cannot cover, because it renders
  // the control directly and never touches `markdownApi`.
  //
  // What's queryable: `CategoryField`/`TagSetField` (read via `ResearchDetail.tsx` and
  // `categories-and-tags.tsx`) each pair a `Combobox` autocomplete with an `EntityChooser`
  // "Choose…" browser. The browser is the one that renders its full option list as real DOM —
  // `role="option"` rows inside a `role="listbox"` — once its trigger is clicked (see
  // `external/agenticdevelopertoolkit/packages/web/packages/ui/src/components/list-chooser.tsx`, exercised the same way by
  // `external/agenticdevelopertoolkit/packages/web/packages/ui/src/__tests__/listChooser.test.tsx`'s `open()` helper). The category trigger's
  // accessible name is "Browse categories" (`Browse ${label.toLowerCase()}` off
  // `CategoriesAndTags`'s `label: "Categories"`); the tags trigger's is "Tags" (`EntityChooser`'s
  // multi-mode `ariaLabel` is the row's own `label`) — both per
  // `external/agenticdevelopertoolkit/packages/web/packages/ui/src/__tests__/categoriesAndTags.test.tsx`.
  it("wires markdownApi's categories and tags into the classification control's Choose… pickers", async () => {
    categories.mockResolvedValue(["Physics", "Chemistry"]);
    tags.mockResolvedValue(["alpha", "beta"]);
    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-1" />
      </Harness>,
    );
    await screen.findByLabelText("Markdown body");

    fireEvent.click(screen.getByRole("button", { name: "Browse categories" }));
    await waitFor(() =>
      expect(screen.getByRole("option", { name: "Physics" })).toBeInTheDocument(),
    );
    expect(screen.getByRole("option", { name: "Chemistry" })).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Tags" }));
    await waitFor(() => expect(screen.getByRole("option", { name: "alpha" })).toBeInTheDocument());
    expect(screen.getByRole("option", { name: "beta" })).toBeInTheDocument();
  });

  // ── Two bases (docBasePath) ────────────────────────────────────────────────────
  // The research SITE splits `basePath` (list) from `docBasePath` (open document) — see this
  // component's own doc comment. Every test above passes only `basePath`, exercising just the
  // default (docBasePath === basePath) path; these two are the only coverage of the split, so a
  // regression that swapped the two bases, or fell back to `basePath` for both, would pass every
  // other test in this file.

  it("routes a selected document under docBasePath, not basePath", async () => {
    render(
      <Harness>
        <ResearchFeature basePath="/acme/home" docBasePath="/acme/edit" />
      </Harness>,
    );

    const row = await screen.findByRole("button", { name: "Federated learning notes" });
    fireEvent.click(row);

    expect(push).toHaveBeenCalledWith("/acme/edit/doc-1", { scroll: false });
  });

  it("closing an open document (Cancel) returns to basePath, not docBasePath", async () => {
    render(
      <Harness>
        <ResearchFeature basePath="/acme/home" docBasePath="/acme/edit" docId="doc-1" />
      </Harness>,
    );

    const body = (await screen.findByLabelText("Markdown body")) as HTMLTextAreaElement;
    await waitFor(() => expect(body.value).toBe("# Federated learning\n\nSome notes."));

    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));

    expect(push).toHaveBeenCalledWith("/acme/home", { scroll: false });
  });

  // The research SITE's edit route (`/<ws>/edit/[paperUuid]/page.tsx`) doesn't read `docId` off
  // a prop the way this file's other tests do — it builds a `path` override for `SiteHomeRoute`
  // with `researchSegments([], paperUuid)`, and `SiteHomeRoute` runs that straight through
  // `parseResearchPath` (unconditionally — override or read-from-URL, same parse). A test that
  // hands `docId` to `ResearchFeature` directly, like every test above, never exercises that
  // parser at all, so it cannot catch a grammar mismatch between the writer and the reader. This
  // one reproduces the page's actual shape end to end: segments out of `researchSegments`, back
  // through `parseResearchPath`, into the props `ResearchFeature` actually receives on that
  // route — the same round trip a regression (e.g. handing down a bare `[paperUuid]`) would break.
  it("opens the document the edit route's real path segments resolve to, not the empty state", async () => {
    const segments = researchSegments([], "doc-1");
    const selection = parseResearchPath(segments);

    render(
      <Harness>
        <ResearchFeature
          basePath="/acme/home"
          docBasePath="/acme/edit"
          categorySlugs={selection.categorySlugs}
          docId={selection.docId}
        />
      </Harness>,
    );

    const body = (await screen.findByLabelText("Markdown body")) as HTMLTextAreaElement;
    await waitFor(() => expect(body.value).toBe("# Federated learning\n\nSome notes."));
    expect(screen.queryByText("Select a document to edit, or create a new one.")).toBeNull();
  });

  // ── The cache ────────────────────────────────────────────────────────────────
  // The complaint these exist for: "each time I click a topic we fetch the contents from the
  // database, this makes the site feel super slow." Each test below asserts a read that does NOT
  // happen — which is the only way to state the fix, since a document painted from the cache and
  // one painted from a fresh GET look identical on screen.

  it("paints a re-opened document from the cache instead of reading it again", async () => {
    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-1" />
      </Harness>,
    );
    const first = (await screen.findByLabelText("Markdown body")) as HTMLTextAreaElement;
    await waitFor(() => expect(first.value).toBe("# Federated learning\n\nSome notes."));
    expect(get).toHaveBeenCalledTimes(1);
    cleanup();

    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-1" />
      </Harness>,
    );
    // Synchronous `get…`, not `findBy…`: there is nothing to wait for. The body is on the FIRST
    // paint, and awaiting here would hide the difference between that and a fast refetch.
    const again = screen.getByLabelText("Markdown body") as HTMLTextAreaElement;
    expect(again.value).toBe("# Federated learning\n\nSome notes.");
    expect(get).toHaveBeenCalledTimes(1);
  });

  it("warms a hovered row's body, so the click that follows reads nothing", async () => {
    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" />
      </Harness>,
    );
    const row = await screen.findByRole("button", { name: "Federated learning notes" });
    await act(async () => {
      fireEvent.pointerEnter(row);
    });
    expect(get).toHaveBeenCalledWith("doc-1", { workspace: undefined });
    cleanup();

    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-1" />
      </Harness>,
    );
    const body = screen.getByLabelText("Markdown body") as HTMLTextAreaElement;
    expect(body.value).toBe("# Federated learning\n\nSome notes.");
    // The warm, and nothing since — the click spent no request of its own.
    expect(get).toHaveBeenCalledTimes(1);
  });

  // The instant paint is only safe because of this: a cached copy may be out of date, so the form
  // is READ-ONLY until the server's answer lands. Editing a stale copy and saving it would put
  // fields back that the server has since changed, and nothing on screen would say so.
  it("paints the cached body immediately but keeps it read-only until the server answers", async () => {
    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-1" />
      </Harness>,
    );
    const settled = (await screen.findByLabelText("Markdown body")) as HTMLTextAreaElement;
    await waitFor(() => expect(settled.value).toBe("# Federated learning\n\nSome notes."));
    expect(settled.disabled).toBe(false);
    cleanup();

    // Hold the next read open, then mark the entry stale so the remount revalidates. That window —
    // cached copy on screen, server's answer still in flight — is what the assertions below are.
    get.mockReturnValue(new Promise<ResearchDocument>(() => {}));
    await act(async () => {
      await getToolkitQueryClient().invalidateQueries();
    });

    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-1" />
      </Harness>,
    );
    const body = screen.getByLabelText("Markdown body") as HTMLTextAreaElement;
    expect(body.value).toBe("# Federated learning\n\nSome notes.");
    expect(body.disabled).toBe(true);
    // And the one thing that tells the user why: the spinner in front of the list's title.
    expect(screen.getByTestId("busy-research-documents")).not.toBeNull();
  });

  // A document row's identity is its title; the primitive that suppresses the (columned, but
  // otherwise empty) icon slot is covered at the `topic-detail.tsx` level — this pins that the
  // documents level actually WIRES `hideItemIcons: true` when it publishes itself, which the
  // typechecker cannot: an optional boolean prop compiles whether it is passed or not.
  it("publishes the documents level with hideItemIcons — a row's identity is its title alone", async () => {
    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" />
      </Harness>,
    );
    await screen.findByText("Federated learning notes");
    expect(screen.getByTestId("hide-item-icons-research-documents")).toHaveTextContent("true");
  });

  // The loader this pane used to own cleared the form error on every selection change. Nothing
  // pinned that, and the cache refactor deleted the loader — so without this the message from a
  // failed save on one document greets the user on the next one, attached to a document that
  // never failed.
  it("leaves a failed save's message behind when another document is opened", async () => {
    update.mockRejectedValueOnce(new Error("Backend exploded."));
    get.mockImplementation(async (id) => ({
      ...structuredClone(DOCUMENT),
      id,
      content: `# ${id}\n\nBody.`,
    }));
    const { rerender } = render(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-1" />
      </Harness>,
    );
    const body = (await screen.findByLabelText("Markdown body")) as HTMLTextAreaElement;
    await waitFor(() => expect(body.value).toBe("# doc-1\n\nBody."));
    fireEvent.change(body, { target: { value: "# doc-1 v2\n\nBody." } });
    await act(async () => {
      screen.getByRole("button", { name: "Save" }).click();
    });
    expect(await screen.findByText("Backend exploded.")).not.toBeNull();

    // Same mount, new selection — how Back, a deep link and a rail click all arrive.
    rerender(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-2" />
      </Harness>,
    );
    await waitFor(() =>
      expect((screen.getByLabelText("Markdown body") as HTMLTextAreaElement).value).toBe(
        "# doc-2\n\nBody.",
      ),
    );
    expect(screen.queryByText("Backend exploded.")).toBeNull();
  });

  it("paints the document list from cache on a remount, reading it once", async () => {
    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" />
      </Harness>,
    );
    expect(await screen.findByText("Federated learning notes")).not.toBeNull();
    // Two reads, not one: the filtered list, and the unfiltered universe behind the filter
    // dropdowns. They are separate keys because they answer separate questions.
    expect(list).toHaveBeenCalledTimes(2);
    cleanup();

    // Synchronous, like the document assertions above: the rows are on the FIRST paint.
    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" />
      </Harness>,
    );
    expect(screen.getByText("Federated learning notes")).not.toBeNull();
    expect(list).toHaveBeenCalledTimes(2);
  });

  // The debounce moved: it used to delay the REQUEST, and now delays the query KEY. Same 200ms of
  // typing without a read — and, unlike a debounced request, the value typed away from and back to
  // is a repaint rather than a round trip.
  it("spends one read on a settled search, and none on going back to it", async () => {
    // A search answers with nothing, so the rows themselves say which key is on screen.
    list.mockImplementation(async (f) => (f?.q ? [] : [structuredClone(SUMMARY)]));
    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" />
      </Harness>,
    );
    expect(await screen.findByText("Federated learning notes")).not.toBeNull();
    expect(list).toHaveBeenCalledTimes(2);

    const search = screen.getByLabelText("Search research documents");
    fireEvent.change(search, { target: { value: "f" } });
    fireEvent.change(search, { target: { value: "fe" } });
    fireEvent.change(search, { target: { value: "fed" } });
    await waitFor(() => expect(screen.queryByText("Federated learning notes")).toBeNull());
    // ONE read for three keystrokes, and it is the value the user stopped at.
    expect(list).toHaveBeenCalledTimes(3);
    expect(list).toHaveBeenLastCalledWith(
      { q: "fed", category: "", tag: "" },
      { workspace: undefined },
    );

    fireEvent.change(search, { target: { value: "" } });
    await waitFor(() => expect(screen.getByText("Federated learning notes")).not.toBeNull());
    // The unfiltered rows came back from the cache: the key returned to one already read.
    expect(list).toHaveBeenCalledTimes(3);
  });

  it("opens a created document from the create response, with no read at all", async () => {
    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" />
      </Harness>,
    );
    fireEvent.click(await screen.findByRole("button", { name: "Create Document" }));
    const dialog = within(await screen.findByRole("dialog"));
    fireEvent.change(dialog.getByLabelText(/^Title/), {
      target: { value: "Hello research" },
    });
    await act(async () => {
      fireEvent.click(dialog.getByRole("button", { name: "Save" }));
    });
    await waitFor(() => expect(create).toHaveBeenCalled());
    cleanup();

    // The create response IS the server's copy, so opening what was just created costs nothing.
    // (The mocked router can't advance the URL in this harness, so the open is a fresh mount at
    // the created id — which is also what a reload or a shared link does.)
    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-1" />
      </Harness>,
    );
    const body = screen.getByLabelText("Markdown body") as HTMLTextAreaElement;
    expect(body.value).toBe("# Federated learning\n\nSome notes.");
    expect(get).not.toHaveBeenCalled();
  });

  // ── The Documents list's toolbar ────────────────────────────────────────────────
  // Both of this pane's page-level controls now ride the documents level's own toolbar (the row
  // under the rail's title), not a page-wide home bar — that strip was removed as clunky (Mike,
  // 2026-09-24). Every query below goes through `within(toolbar-research-documents)` rather than
  // `screen`, which is the only thing that makes these tests capable of failing: an unscoped
  // `screen.getByRole("button", { name: "Create Document" })` finds the button whether it was
  // published onto this level's toolbar or floating disconnected somewhere else on the page.

  // WIRING only: which of the level's fields each control arrives through. Their ORDER is the real
  // rail's to decide, and this harness's `Rail` is a stand-in — see its doc for where it is pinned.
  it("publishes the search, the filters and Create Document onto the Documents list's toolbar", async () => {
    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" />
      </Harness>,
    );

    const toolbar = within(await screen.findByTestId("toolbar-research-documents"));
    expect(toolbar.getByRole("searchbox", { name: "Search research documents" })).not.toBeNull();
    expect(toolbar.getByRole("button", { name: "Create Document" })).not.toBeNull();
    // The whole filter cluster, not just the search field: `titleActions` carries both axes
    // behind one gear now, so the gear has to arrive too.
    expect(toolbar.getByRole("button", { name: "Document filters" })).not.toBeNull();

    // And nowhere ELSE. A control published onto this toolbar but ALSO still handed to the rail
    // some other way would satisfy every assertion above; only counting the whole document
    // catches it.
    expect(screen.getAllByRole("button", { name: "Create Document" })).toHaveLength(1);
    expect(screen.getAllByRole("searchbox")).toHaveLength(1);
  });

  it("opens the category and tag axes from the toolbar's gear — the whole filter cluster arrives", async () => {
    // The axes' OPTIONS come from the unfiltered universe read (`list({})`), not from the
    // editor's category/tag vocabulary — and that read is held back here until the rows are on
    // screen, so it lands when nothing else on the level moves. The gear is a React node, which
    // the rail host's publish key cannot see: before the level carried `filterKey`, a universe
    // that arrived last never reached the menus, and they offered only their all-pass entries.
    let landUniverse: (rows: ResearchSummary[]) => void = () => {};
    const universe = new Promise<ResearchSummary[]>((resolve) => {
      landUniverse = resolve;
    });
    list.mockImplementation((f) =>
      "q" in (f ?? {}) ? Promise.resolve([structuredClone(SUMMARY)]) : universe,
    );
    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" />
      </Harness>,
    );
    expect(await screen.findByText("Federated learning notes")).not.toBeNull();
    await act(async () => {
      landUniverse([
        { ...structuredClone(SUMMARY), id: "doc-2", category: "Physics", tags: ["alpha"] },
      ]);
    });

    const toolbar = within(screen.getByTestId("toolbar-research-documents"));
    fireEvent.click(toolbar.getByRole("button", { name: "Document filters" }));
    const menu = await screen.findByRole("menu");
    // Both axes, each announcing its own current (all-pass) value — the replacement for the two
    // plain `<select>`s this gear folded into one control.
    within(menu).getByRole("menuitem", { name: "Category: all categories" });
    within(menu).getByRole("menuitem", { name: "Tag: all tags" });
    // And each offering what the universe holds.
    fireEvent.click(within(menu).getByRole("menuitem", { name: "Category: all categories" }));
    expect(await screen.findByRole("menuitemradio", { name: "Physics" })).not.toBeNull();
    fireEvent.click(within(menu).getByRole("menuitem", { name: "Tag: all tags" }));
    expect(await screen.findByRole("menuitemradio", { name: "alpha" })).not.toBeNull();
  });

  // The gear writes through the pane's setter, and the level re-registers with every filter it
  // draws. Both halves were missing: with a tag on, clearing the category moved no plain field —
  // `emptyLabel` only moves when the filter set empties or fills, and the list key came back to a
  // cached, identical result — so the gear stayed on "Category: ml", and the next pick spread that
  // stale snapshot and put the cleared category straight back.
  it("keeps a cleared filter cleared when the other one is picked next", async () => {
    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" />
      </Harness>,
    );
    expect(await screen.findByText("Federated learning notes")).not.toBeNull();
    const toolbar = within(screen.getByTestId("toolbar-research-documents"));
    const pick = async (axis: RegExp, option: string) => {
      fireEvent.click(toolbar.getByRole("button", { name: /^Document filters/ }));
      fireEvent.click(await screen.findByRole("menuitem", { name: axis }));
      // Choosing a radio closes the menu (`closeOnClick`), so every pick reopens the gear.
      fireEvent.click(await screen.findByRole("menuitemradio", { name: option }));
    };

    await pick(/^Tag:/, "notes");
    await waitFor(() =>
      expect(list).toHaveBeenLastCalledWith(
        { q: "", tag: "notes", category: "" },
        { workspace: undefined },
      ),
    );
    await pick(/^Category:/, "ml");
    await waitFor(() =>
      expect(list).toHaveBeenLastCalledWith(
        { q: "", tag: "notes", category: "ml" },
        { workspace: undefined },
      ),
    );
    await pick(/^Category:/, "All categories");
    // Past the debounce, so the list is back on the tag-only key the first pick already read.
    await act(async () => {
      await new Promise((resolve) => setTimeout(resolve, 300));
    });

    fireEvent.click(toolbar.getByRole("button", { name: "Document filters (filtered)" }));
    expect(await screen.findByRole("menuitem", { name: "Category: all categories" })).not.toBeNull();
    fireEvent.click(await screen.findByRole("menuitem", { name: "Tag: notes" }));
    fireEvent.click(await screen.findByRole("menuitemradio", { name: "All tags" }));

    // Nothing narrows any more: the gear drops its "(filtered)" mark, and both axes read all-pass.
    fireEvent.click(await toolbar.findByRole("button", { name: "Document filters" }));
    expect(await screen.findByRole("menuitem", { name: "Category: all categories" })).not.toBeNull();
    expect(screen.getByRole("menuitem", { name: "Tag: all tags" })).not.toBeNull();
  });

  it("still publishes the toolbar with ZERO documents — the first create is when it matters most", async () => {
    // An empty list, and the create must survive it: gating the toolbar on having something to
    // list is precisely the trap this branch exists to close (a brand-new tenant with no way to
    // create anything at all). The unfiltered universe read is empty here too, so the gear's
    // menu holds only its all-pass entries — the search field is what has to be there.
    list.mockResolvedValue([]);
    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" />
      </Harness>,
    );

    // The toolbar is published while the list is still LOADING, so without this wait every
    // assertion below ran against the loading level, and a create gated on a loaded-but-empty list
    // would have passed. The loaded empty label is a plain field of the level, so its arrival is
    // also what re-registers the level the host draws.
    expect(await screen.findByText("No documents yet.")).not.toBeNull();
    const toolbar = within(screen.getByTestId("toolbar-research-documents"));
    expect(toolbar.getByRole("button", { name: "Create Document" })).not.toBeNull();
    expect(toolbar.getByRole("searchbox", { name: "Search research documents" })).not.toBeNull();
  });

  it("filters the list from the toolbar's search field", async () => {
    // The search box is the level's own controlled `search`, not a separate copy: typing in the
    // toolbar must still drive the pane's `filters` state and reach the list request. A field
    // that rendered on the toolbar but no longer fed the list would pass every placement
    // assertion above.
    list.mockImplementation(async (f) => (f?.q ? [] : [structuredClone(SUMMARY)]));
    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" />
      </Harness>,
    );
    expect(await screen.findByText("Federated learning notes")).not.toBeNull();

    const toolbar = within(await screen.findByTestId("toolbar-research-documents"));
    fireEvent.change(toolbar.getByRole("searchbox", { name: "Search research documents" }), {
      target: { value: "fed" },
    });
    await waitFor(() =>
      expect(list).toHaveBeenLastCalledWith(
        { q: "fed", category: "", tag: "" },
        { workspace: undefined },
      ),
    );
    await waitFor(() => expect(screen.queryByText("Federated learning notes")).toBeNull());
  });
});

// Task 16: the identity field above the body, and the one alert that stands between an
// author and saving a slug the API has already refused. `deriveDocumentTitle(DOCUMENT.content)`
// — "Federated learning", the `#` heading marker stripped off the body's first line — is a
// DIFFERENT string from `DOCUMENT.title` ("Federated learning notes", the field the list row
// and rail button use elsewhere in this file); the identity field reads the body, not that
// field, which is the whole point of the task.
const KNOWN_TITLE = "Federated learning";

/** Opens the known document with its editor on screen. `docId` is a static prop in this
 *  URL-driven harness — the mocked router's `push` never causes a re-render with a new
 *  `docId` — so clicking a rail row only proves `push` fired; it does not open anything here.
 *  Every existing test above that needs the editor visible mounts with `docId="doc-1"`
 *  directly, and this helper follows the same pattern. */
async function openFirstDocument(): Promise<void> {
  render(
    <Harness>
      <ResearchFeature basePath="/w1/research" docId="doc-1" />
    </Harness>,
  );
  const body = (await screen.findByLabelText("Markdown body")) as HTMLTextAreaElement;
  await waitFor(() => expect(body.value).toBe(DOCUMENT.content));
}

describe("ResearchFeature — title and slug", () => {
  afterEach(cleanup);

  it("shows the open document's title, read from its frontmatter", async () => {
    await openFirstDocument();
    expect(screen.getByLabelText("Title")).toHaveValue(KNOWN_TITLE);
  });

  it("writes an edited title into the body's frontmatter, so the derived title matches", async () => {
    await openFirstDocument();
    fireEvent.change(screen.getByLabelText("Title"), { target: { value: "Renamed Paper" } });
    const body = screen.getByLabelText("Markdown body") as HTMLTextAreaElement;
    expect(body.value).toContain('title: "Renamed Paper"');
  });

  it("keeps a trailing space typed mid-word — a keystroke round-trip through the trimmed, derived title must not revert it", async () => {
    // A single `fireEvent.change` with the whole final string can't observe this: the bug is
    // in what happens BETWEEN keystrokes. `setFrontmatterTitle` trims before it writes, and
    // `deriveDocumentTitle` re-reads that trimmed frontmatter — so a title field driven
    // straight off the derived value (no local edit buffer) drops a trailing space back to the
    // caller on the very next render, which drops the NEXT keystroke typed after it too. Typing
    // one character at a time and asserting the field after each is what actually exercises
    // that round trip.
    await openFirstDocument();
    const titleField = screen.getByLabelText("Title") as HTMLInputElement;
    const target = "New Title ";
    let typed = "";
    for (const ch of target) {
      typed += ch;
      fireEvent.change(titleField, { target: { value: typed } });
      expect(titleField).toHaveValue(typed);
    }
    // ...and the character typed right after the trailing space survives too — the field the
    // bug reverts silently swallows this one first.
    typed += "2";
    fireEvent.change(titleField, { target: { value: typed } });
    expect(titleField).toHaveValue("New Title 2");
  });

  it("follows the title with the slug until the slug is edited", async () => {
    await openFirstDocument();
    fireEvent.change(screen.getByLabelText("Title"), { target: { value: "Renamed Paper" } });
    expect(screen.getByLabelText("Slug")).toHaveValue("renamed-paper");

    fireEvent.change(screen.getByLabelText("Slug"), { target: { value: "renamed-paper-2" } });
    fireEvent.change(screen.getByLabelText("Title"), { target: { value: "Renamed Again" } });
    expect(screen.getByLabelText("Slug")).toHaveValue("renamed-paper-2");
  });

  it("alerts instead of saving when the slug is unavailable — on a PUBLISHED paper, whose save actually writes the route", async () => {
    // Gated on visibility (see FIX 3 below): only a published paper's Save can move the route,
    // so the fixture here must be public — a draft's slug writes nothing and must not be
    // blocked by this guard at all (see the next test).
    const published: ResearchDocument = { ...structuredClone(DOCUMENT), visibility: "public", publicRoute: "federated-learning" };
    get.mockResolvedValue(structuredClone(published));
    routeAvailable.mockResolvedValue({ available: false, reason: "taken" });
    await openFirstDocument();
    fireEvent.change(screen.getByLabelText("Title"), { target: { value: "Clashing" } });

    // SLUG_REASON maps the "taken" reason to this sentence, not to "unavailable" or "taken"
    // verbatim — the wording is the API's, and this is the string that actually renders.
    await waitFor(() =>
      expect(screen.getByText(/already uses that slug/i)).toBeInTheDocument(),
    );

    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    // AlertModal is built on @base-ui/react's <Dialog>, which renders role="dialog" — not
    // "alertdialog".
    expect(await screen.findByRole("dialog")).toHaveTextContent(/slug/i);
    expect(update).not.toHaveBeenCalled();
  });

  it("saves without the unavailable-slug alert when a published paper's slug is UNCHANGED, even though the checker reports it unavailable (FIX C5)", async () => {
    // The save GUARD and the write CONDITION now share one predicate (`writesPublicRoute`),
    // which adds the `slug !== publicRoute` term the guard used to omit. This deliberately
    // disagrees with the backend's real behaviour (which excludes the document's own id, so an
    // unchanged slug never actually reads "unavailable") to pin that the guard itself — not
    // just a well-behaved backend — is what lets an untouched slug through.
    const published: ResearchDocument = {
      ...structuredClone(DOCUMENT),
      visibility: "public",
      publicRoute: "federated-learning",
    };
    get.mockResolvedValue(structuredClone(published));
    routeAvailable.mockResolvedValue({ available: false, reason: "taken" });
    update.mockResolvedValueOnce({
      ...structuredClone(published),
      content: "# Federated learning\n\nSome notes, edited.",
    });
    await openFirstDocument();
    await waitFor(() =>
      expect(screen.getByText(/already uses that slug/i)).toBeInTheDocument(),
    );

    // Dirties the draft WITHOUT touching the title line, so the slug — still following,
    // unedited — stays exactly what it already was: the saved document's own route.
    fireEvent.change(screen.getByLabelText("Markdown body"), {
      target: { value: "# Federated learning\n\nSome notes, edited." },
    });

    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => expect(update).toHaveBeenCalled());
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(publish).not.toHaveBeenCalled();
  });

  it("does NOT block or alert on Save for a DRAFT with an unavailable slug — nothing is written yet (FIX 3)", async () => {
    // DOCUMENT (the fixture openFirstDocument opens) is private: an unpublished draft's slug is
    // never persisted by Save — only Publish writes the route — so a collision on a field that
    // has no effect until the author explicitly publishes must not lose the author's edits.
    routeAvailable.mockResolvedValue({ available: false, reason: "taken" });
    update.mockResolvedValueOnce(structuredClone(DOCUMENT));
    await openFirstDocument();
    fireEvent.change(screen.getByLabelText("Title"), { target: { value: "Clashing" } });

    // A DRAFT's unavailable slug also disables the Publish card's own button (FIX C8's reason
    // text lives right next to it), so the identity field's live-region verdict is no longer
    // the ONLY place this sentence renders — `getAllByText` rather than `getByText`.
    await waitFor(() =>
      expect(screen.getAllByText(/already uses that slug/i).length).toBeGreaterThan(0),
    );

    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => expect(update).toHaveBeenCalled());
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("shows ONE slug input — the publish card no longer carries its own", async () => {
    await openFirstDocument();
    expect(screen.getAllByLabelText(/slug|public route/i)).toHaveLength(1);
  });

  // The three below cover the live-publish half of the lifecycle: `onSave`'s
  // `if (saved.visibility === "public" && slug && slug !== saved.publicRoute)` block at
  // ResearchPane.tsx. Editing the SLUG field alone never dirties the draft (`dirty` compares
  // content/category/tags, not the slug — see `researchDiffers`), so a slug move that should
  // trigger a re-publish has to ride along with a content edit; the cleanest one is the title,
  // which both dirties the draft AND (unless the slug has been touched) drives the slug via the
  // "follows" behaviour already covered above.

  it("re-publishes a live paper when the title-driven slug moves", async () => {
    const published: ResearchDocument = {
      ...structuredClone(DOCUMENT),
      visibility: "public",
      publicRoute: "federated-learning",
    };
    get.mockResolvedValue(structuredClone(published));
    // The PUT response never carries a new route — only `publish` moves it — so `saved` here
    // still has the OLD route, which is exactly what makes `slug !== saved.publicRoute` true.
    update.mockResolvedValueOnce({
      ...structuredClone(published),
      content: "# Renamed Paper\n\nSome notes.",
    });
    publish.mockResolvedValueOnce({ ...structuredClone(published), publicRoute: "renamed-paper" });

    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-1" />
      </Harness>,
    );
    const body = (await screen.findByLabelText("Markdown body")) as HTMLTextAreaElement;
    await waitFor(() => expect(body.value).toBe(published.content));
    expect(screen.getByLabelText("Slug")).toHaveValue("federated-learning");

    fireEvent.change(screen.getByLabelText("Title"), { target: { value: "Renamed Paper" } });
    await waitFor(() => expect(screen.getByLabelText("Slug")).toHaveValue("renamed-paper"));

    await act(async () => {
      screen.getByRole("button", { name: "Save" }).click();
    });

    await waitFor(() =>
      expect(publish).toHaveBeenCalledWith("doc-1", "renamed-paper", { workspace: undefined }),
    );
  });

  it("does not re-publish a live paper when the slug is untouched", async () => {
    const published: ResearchDocument = {
      ...structuredClone(DOCUMENT),
      visibility: "public",
      publicRoute: "federated-learning",
    };
    get.mockResolvedValue(structuredClone(published));
    update.mockResolvedValueOnce({
      ...structuredClone(published),
      content: "# Federated learning\n\nSome notes, edited.",
    });

    render(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-1" />
      </Harness>,
    );
    const body = (await screen.findByLabelText("Markdown body")) as HTMLTextAreaElement;
    await waitFor(() => expect(body.value).toBe(published.content));
    expect(screen.getByLabelText("Slug")).toHaveValue("federated-learning");

    // Dirties the draft WITHOUT touching the title line, so the slug — which is still
    // following, unedited — stays exactly what it already was: the saved document's own route.
    fireEvent.change(body, { target: { value: "# Federated learning\n\nSome notes, edited." } });

    await act(async () => {
      screen.getByRole("button", { name: "Save" }).click();
    });

    await waitFor(() => expect(update).toHaveBeenCalledTimes(1));
    expect(publish).not.toHaveBeenCalled();
  });

  it("resets the slug's follow behaviour when the open document changes", async () => {
    const doc1: ResearchDocument = {
      ...structuredClone(DOCUMENT),
      visibility: "public",
      publicRoute: "federated-learning",
    };
    const doc2: ResearchDocument = {
      ...structuredClone(DOCUMENT),
      id: "doc-2",
      title: "Quantum notes",
      content: "# Quantum notes\n\nOther body.",
      visibility: "public",
      publicRoute: "quantum-notes",
    };
    get.mockImplementation(async (id) => structuredClone(id === "doc-2" ? doc2 : doc1));

    const { rerender } = render(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-1" />
      </Harness>,
    );
    await waitFor(() =>
      expect((screen.getByLabelText("Markdown body") as HTMLTextAreaElement).value).toBe(
        doc1.content,
      ),
    );
    // Seeded from doc-1's OWN publicRoute — the published-document half of "the slug seeds
    // from the title when there is no route, and from the route when there is one."
    expect(screen.getByLabelText("Slug")).toHaveValue("federated-learning");

    // Load doc-2 too, so it is CACHED by the time we come back to it below — the return trip
    // has to be a synchronous cache hit, not a fresh fetch, or a plain loading-gap unmount
    // (MasterDetailLeaf renders its empty-state placeholder while `selectedDoc` is null) would
    // reset `touched` on its own and the assertion below would pass with `key` gone too.
    rerender(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-2" />
      </Harness>,
    );
    await waitFor(() =>
      expect((screen.getByLabelText("Markdown body") as HTMLTextAreaElement).value).toBe(
        doc2.content,
      ),
    );
    expect(screen.getByLabelText("Slug")).toHaveValue("quantum-notes");

    // Touch doc-2's slug directly, then go BACK to doc-1 — already cached, so this transition
    // paints from cache with no null/loading frame in between and nothing naturally unmounts
    // `DocumentIdentityField`. Only the document-scoped `key` can reset its `touched` state here.
    fireEvent.change(screen.getByLabelText("Slug"), { target: { value: "quantum-notes-2" } });

    rerender(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-1" />
      </Harness>,
    );
    await waitFor(() =>
      expect((screen.getByLabelText("Markdown body") as HTMLTextAreaElement).value).toBe(
        doc1.content,
      ),
    );
    // doc-1's OWN route again, not doc-2's edited value carried over.
    expect(screen.getByLabelText("Slug")).toHaveValue("federated-learning");

    // And doc-1's slug still FOLLOWS its title. The parent's `slug` prop alone would already
    // satisfy the assertion above even with a stale, still-`touched` field (the value is
    // controlled from ResearchPane regardless of remount) — this second half is what actually
    // depends on `DocumentIdentityField` having remounted, because it exercises the field's own
    // `touched` state, not just the value the parent handed it.
    fireEvent.change(screen.getByLabelText("Title"), { target: { value: "Renamed Paper" } });
    expect(screen.getByLabelText("Slug")).toHaveValue("renamed-paper");
  });

  it("does not resurrect an abandoned title buffer when the selection returns to it (FIX C4)", async () => {
    // `titleEdit` is keyed by id (masked, not cleared, when the selection moves away) — the
    // same shape `slugEdit` has always had, and which the test above pins for the slug. This
    // pins the title half: leaving a document mid-edit without Save or Cancel, then coming
    // back, must show the stored/derived title, not the raw buffer left behind.
    const doc2: ResearchDocument = {
      ...structuredClone(DOCUMENT),
      id: "doc-2",
      title: "Quantum notes",
      content: "# Quantum notes\n\nOther body.",
    };
    get.mockImplementation(async (id) => structuredClone(id === "doc-2" ? doc2 : DOCUMENT));

    const { rerender } = render(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-1" />
      </Harness>,
    );
    await waitFor(() =>
      expect((screen.getByLabelText("Markdown body") as HTMLTextAreaElement).value).toBe(
        DOCUMENT.content,
      ),
    );

    // A trailing space, deliberately: it makes the raw buffer ("New Title ") observably
    // different from the trimmed, stored/derived title ("New Title") a fix would show instead.
    fireEvent.change(screen.getByLabelText("Title"), { target: { value: "New Title " } });
    expect(screen.getByLabelText("Title")).toHaveValue("New Title ");

    // Load doc-2 — cached by the time we return — then come back to doc-1. A cache hit, no
    // fetch, nothing naturally remounts the field.
    rerender(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-2" />
      </Harness>,
    );
    await waitFor(() =>
      expect((screen.getByLabelText("Markdown body") as HTMLTextAreaElement).value).toBe(
        doc2.content,
      ),
    );

    rerender(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-1" />
      </Harness>,
    );
    // Back to doc-1's body — heading unchanged. (Not a full-string match against
    // `DOCUMENT.content`: the edit above went through `onChange`, whose write path
    // legitimately rewrote the frontmatter `title:` key, so the body it left behind now carries
    // that frontmatter block. That's expected and is not what this test is about.)
    await waitFor(() =>
      expect((screen.getByLabelText("Markdown body") as HTMLTextAreaElement).value).toContain(
        "# Federated learning",
      ),
    );

    // The stored/derived title, not the abandoned raw buffer with its trailing space intact.
    expect(screen.getByLabelText("Title")).toHaveValue("New Title");
  });

  it("does not lose a hand-typed slug on an unpublished paper when the selection leaves and returns (FIX E1)", async () => {
    // Unlike `titleEdit`, `slugEdit` IS the store for an unpublished paper's slug — there is no
    // `publicRoute` (DOCUMENT is private, `publicRoute: null`) to fall back to, so clearing this
    // buffer on selection change would silently replace the author's typed slug with the
    // title-derived one. This pins that `slugEdit` is NOT cleared by the `[selectedId]` effect,
    // the way `titleEdit` deliberately is (see the test above).
    const doc2: ResearchDocument = {
      ...structuredClone(DOCUMENT),
      id: "doc-2",
      title: "Quantum notes",
      content: "# Quantum notes\n\nOther body.",
    };
    get.mockImplementation(async (id) => structuredClone(id === "doc-2" ? doc2 : DOCUMENT));

    const { rerender } = render(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-1" />
      </Harness>,
    );
    await waitFor(() =>
      expect((screen.getByLabelText("Markdown body") as HTMLTextAreaElement).value).toBe(
        DOCUMENT.content,
      ),
    );

    // A slug that is deliberately NOT what `routeFromTitle` would derive from the title, so a
    // reversion to the title-derived fallback is observable.
    fireEvent.change(screen.getByLabelText("Slug"), {
      target: { value: "my-custom-slug" },
    });
    expect(screen.getByLabelText("Slug")).toHaveValue("my-custom-slug");

    // Load doc-2 — cached by the time we return — then come back to doc-1. A cache hit, no
    // fetch, nothing naturally remounts the field.
    rerender(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-2" />
      </Harness>,
    );
    await waitFor(() =>
      expect((screen.getByLabelText("Markdown body") as HTMLTextAreaElement).value).toBe(
        doc2.content,
      ),
    );

    rerender(
      <Harness>
        <ResearchFeature basePath="/w1/research" docId="doc-1" />
      </Harness>,
    );
    await waitFor(() =>
      expect((screen.getByLabelText("Markdown body") as HTMLTextAreaElement).value).toBe(
        DOCUMENT.content,
      ),
    );

    // The typed slug survives the round trip — not reverted to the title-derived fallback.
    expect(screen.getByLabelText("Slug")).toHaveValue("my-custom-slug");
  });
});
