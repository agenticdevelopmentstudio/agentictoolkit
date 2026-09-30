// @vitest-environment jsdom
//
// Component test for AbilitiesPanel — the persona editor's "what tools does this persona have"
// facet. Ported from the old workspace AgentToolsPanel.test.tsx's tool-catalog coverage, adapted
// to the personaId-prop shape (no more agent <Select> — the panel is scoped by a prop, so a
// "switch" is now a rerender with a new personaId). This package's vitest config is node-only, so
// this file opts into jsdom via the docblock above and drives React with @testing-library/react.
// Only the personaToolsApi module boundary is mocked (vi.mock) so the panel's grant/revoke wiring
// + optimistic revert are exercised, not the transport.
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor, cleanup, act } from "@testing-library/react";

vi.mock("@agentic-toolkit/data/personas", () => ({
  personaToolsApi: {
    list: vi.fn(),
    grant: vi.fn(),
    revoke: vi.fn(),
    setAutonomy: vi.fn(),
  },
}));

import { AbilitiesPanel } from "./AbilitiesPanel";
import { personaToolsApi, type ToolCatalogItem, type ToolGrant } from "@agentic-toolkit/data/personas";

const list = vi.mocked(personaToolsApi.list);
const grant = vi.mocked(personaToolsApi.grant);
const revoke = vi.mocked(personaToolsApi.revoke);
const setAutonomy = vi.mocked(personaToolsApi.setAutonomy);

// Most mocks below carry displayName === toolName (+ empty description): the fail-soft state a
// tool with no catalog row renders in, which keeps each row's accessible name equal to its tool
// name so the `box(toolName)` queries below stay stable. Rich displayName/description rendering
// gets its own dedicated test.
const SEARCH_THREADS: ToolCatalogItem = {
  toolName: "searchThreads",
  source: null,
  displayName: "searchThreads",
  description: "",
  readOnly: true,
  granted: false,
  autonomous: false,
};
const WEB_SEARCH: ToolCatalogItem = {
  toolName: "web.search",
  source: "web",
  displayName: "web.search",
  description: "",
  readOnly: true,
  granted: true,
  autonomous: false,
};
const CATALOG: ToolCatalogItem[] = [SEARCH_THREADS, WEB_SEARCH];

// Two disjoint one-tool catalogs (keyed by persona id) — used to prove that a stale list()
// response for the previously-selected persona never renders under the current one (#13).
const ALPHA: ToolCatalogItem = {
  toolName: "alpha",
  source: null,
  displayName: "alpha",
  description: "",
  readOnly: true,
  granted: false,
  autonomous: false,
};
const BETA: ToolCatalogItem = {
  toolName: "beta",
  source: null,
  displayName: "beta",
  description: "",
  readOnly: true,
  granted: false,
  autonomous: false,
};

// Two independently-grantable rows, used to prove per-row busy state (#15).
const TOOL_A: ToolCatalogItem = {
  toolName: "toolA",
  source: null,
  displayName: "toolA",
  description: "",
  readOnly: true,
  granted: false,
  autonomous: false,
};
const TOOL_B: ToolCatalogItem = {
  toolName: "toolB",
  source: null,
  displayName: "toolB",
  description: "",
  readOnly: true,
  granted: false,
  autonomous: false,
};

beforeEach(() => {
  vi.clearAllMocks();
  list.mockResolvedValue(structuredClone(CATALOG));
});

// This package's vitest config has no global afterEach, so RTL's auto-cleanup never
// registers — tear down each render explicitly to keep renders from bleeding across
// tests.
afterEach(cleanup);

// The Checkbox primitive derives its accessible name from the associated visible
// tool-name label (base-ui wires aria-labelledby from the row's <label>), so each
// row's box is addressed by its tool name.
const box = (toolName: string) => screen.getByRole("checkbox", { name: toolName });

// base-ui reflects a disabled control via the native `disabled` attribute (and/or
// aria-disabled); accept either so the assertion isn't coupled to one representation.
const isDisabled = (el: HTMLElement) =>
  el.hasAttribute("disabled") || el.getAttribute("aria-disabled") === "true";

describe("AbilitiesPanel", () => {
  it("renders the human displayName + description, demoting the raw tool name to a mono caption", async () => {
    const rich: ToolCatalogItem = {
      toolName: "dataKvSet",
      source: null,
      displayName: "Save a value",
      description: "Store a value under a key for the current user.",
      readOnly: false,
      granted: false,
      autonomous: false,
    };
    list.mockResolvedValue([rich]);
    render(<AbilitiesPanel personaId="p1" />);
    // The human copy leads and is the checkbox's accessible name…
    await screen.findByText("Save a value");
    expect(screen.getByRole("checkbox", { name: "Save a value" })).not.toBeNull();
    expect(screen.getByText("Store a value under a key for the current user.")).not.toBeNull();
    // …and the raw camelCase tool name is still present (demoted caption), never hidden.
    expect(screen.getByText("dataKvSet")).not.toBeNull();
  });

  it("renders a catalog row per tool for the given persona", async () => {
    render(<AbilitiesPanel personaId="p1" />);
    await screen.findByRole("checkbox", { name: "searchThreads" });
    expect(list).toHaveBeenCalledWith("p1");
    expect(box("web.search")).not.toBeNull();
    // The ungranted built-in is unchecked; the granted web tool is checked.
    expect(box("searchThreads").getAttribute("aria-checked")).toBe("false");
    expect(box("web.search").getAttribute("aria-checked")).toBe("true");
  });

  it("ticking an ungranted tool grants it", async () => {
    grant.mockResolvedValueOnce({ ...SEARCH_THREADS, granted: true });
    render(<AbilitiesPanel personaId="p1" />);
    await screen.findByRole("checkbox", { name: "searchThreads" });

    fireEvent.click(box("searchThreads"));

    await waitFor(() => expect(grant).toHaveBeenCalledWith("p1", "searchThreads"));
    expect(box("searchThreads").getAttribute("aria-checked")).toBe("true");
  });

  it("reverts the checkbox when the grant request rejects", async () => {
    grant.mockRejectedValueOnce(new Error("nope"));
    render(<AbilitiesPanel personaId="p1" />);
    await screen.findByRole("checkbox", { name: "searchThreads" });

    fireEvent.click(box("searchThreads"));
    // Optimistic tick flips it on immediately, then reverts back to unchecked once
    // the rejected grant settles.
    expect(box("searchThreads").getAttribute("aria-checked")).toBe("true");

    await waitFor(() => expect(grant).toHaveBeenCalledWith("p1", "searchThreads"));
    await waitFor(() =>
      expect(box("searchThreads").getAttribute("aria-checked")).toBe("false"),
    );
  });

  it("unticking a granted tool drives revoke", async () => {
    revoke.mockResolvedValueOnce(undefined);
    render(<AbilitiesPanel personaId="p1" />);
    await screen.findByRole("checkbox", { name: "searchThreads" });

    // web.search starts GRANTED (checked); clicking its box unticks it → revoke, box goes off.
    expect(box("web.search").getAttribute("aria-checked")).toBe("true");
    fireEvent.click(box("web.search"));

    await waitFor(() => expect(revoke).toHaveBeenCalledWith("p1", "web.search"));
    expect(box("web.search").getAttribute("aria-checked")).toBe("false");
  });

  it("toggling a granted tool's autonomy switch drives setAutonomy", async () => {
    setAutonomy.mockResolvedValueOnce({
      toolName: "web.search",
      source: "web",
      autonomous: true,
      createdAt: "2026-07-03T00:00:00Z",
    } as ToolGrant);
    render(<AbilitiesPanel personaId="p1" />);
    // The autonomy switch renders ONLY for a granted tool (web.search) and starts off.
    const autonomy = await screen.findByRole("switch", { name: "autonomy for web.search" });
    expect(autonomy.getAttribute("aria-checked")).toBe("false");

    fireEvent.click(autonomy);

    await waitFor(() => expect(setAutonomy).toHaveBeenCalledWith("p1", "web.search", true));
    expect(
      screen.getByRole("switch", { name: "autonomy for web.search" }).getAttribute("aria-checked"),
    ).toBe("true");
  });

  // #13 — switching persona A→B (a rerender with a new personaId) while list(A) is still in
  // flight must not let the late A response overwrite B's catalog under the B selection.
  it("drops a stale list response so the newly-selected persona's catalog stands (#13)", async () => {
    let resolveA!: (v: ToolCatalogItem[]) => void;
    const pendingA = new Promise<ToolCatalogItem[]>((resolve) => {
      resolveA = resolve;
    });
    list.mockImplementation((id: string) =>
      id === "p1" ? pendingA : Promise.resolve([BETA]),
    );

    const { rerender } = render(<AbilitiesPanel personaId="p1" />); // list(p1): still pending
    rerender(<AbilitiesPanel personaId="p2" />); // list(p2): resolves now

    await screen.findByRole("checkbox", { name: "beta" });

    // The slow A response lands LAST; the stale guard must drop it, not render A's catalog
    // under the persona-B selection.
    await act(async () => {
      resolveA([ALPHA]);
    });

    expect(screen.getByRole("checkbox", { name: "beta" })).not.toBeNull();
    expect(screen.queryByRole("checkbox", { name: "alpha" })).toBeNull();
  });

  // #15 — two concurrent row mutations must each keep their OWN row disabled until their own
  // request settles; settling the first must not re-enable the second.
  it("tracks per-row busy independently for concurrent mutations (#15)", async () => {
    list.mockResolvedValue([TOOL_A, TOOL_B]);
    let resolveA!: (v: ToolCatalogItem) => void;
    let resolveB!: (v: ToolCatalogItem) => void;
    grant.mockImplementation((_personaId: string, toolName: string) =>
      toolName === "toolA"
        ? new Promise((resolve) => {
            resolveA = resolve;
          })
        : new Promise((resolve) => {
            resolveB = resolve;
          }),
    );

    render(<AbilitiesPanel personaId="p1" />);
    await screen.findByRole("checkbox", { name: "toolA" });

    fireEvent.click(box("toolA")); // grant(toolA) now in flight → row A busy
    fireEvent.click(box("toolB")); // grant(toolB) now in flight → row B busy
    expect(grant).toHaveBeenCalledWith("p1", "toolA");
    expect(grant).toHaveBeenCalledWith("p1", "toolB");
    expect(isDisabled(box("toolA"))).toBe(true);
    expect(isDisabled(box("toolB"))).toBe(true);

    // Settle only A. B is still in flight, so its row MUST stay disabled (the old shared-
    // string busy state would have cleared it, re-enabling a double-submit).
    await act(async () => {
      resolveA({ ...TOOL_A, granted: true });
    });
    expect(isDisabled(box("toolA"))).toBe(false);
    expect(isDisabled(box("toolB"))).toBe(true);

    await act(async () => {
      resolveB({ ...TOOL_B, granted: true });
    });
    expect(isDisabled(box("toolB"))).toBe(false);
  });

  // A row mutation that settles AFTER a persona switch (rerender with a new personaId) must not
  // clear busy on the now-current persona's same-named row: its `finally` is gated on the load
  // token (like the reconcile/revert above), so an in-flight grant on the newly-selected persona
  // stays disabled and can't be double-submitted by a stale settle.
  it("a stale mutation settling after a persona switch never clears the current persona's busy row", async () => {
    list.mockResolvedValue([TOOL_A]); // both personas expose a same-named 'toolA' row
    let resolveP1!: (v: ToolCatalogItem) => void;
    let resolveP2!: (v: ToolCatalogItem) => void;
    grant.mockImplementation((personaId: string) =>
      personaId === "p1"
        ? new Promise((r) => {
            resolveP1 = r;
          })
        : new Promise((r) => {
            resolveP2 = r;
          }),
    );

    const { rerender } = render(<AbilitiesPanel personaId="p1" />);

    // Start granting p1's toolA → grant(p1) in flight, row busy on p1.
    await screen.findByRole("checkbox", { name: "toolA" });
    fireEvent.click(box("toolA"));
    expect(grant).toHaveBeenCalledWith("p1", "toolA");

    // Switch to persona p2 (reload bumps the load token + resets busy) and start granting its
    // OWN toolA → grant(p2) in flight, row busy on p2.
    rerender(<AbilitiesPanel personaId="p2" />);
    await screen.findByRole("checkbox", { name: "toolA" });
    fireEvent.click(box("toolA"));
    await waitFor(() => expect(grant).toHaveBeenCalledWith("p2", "toolA"));
    expect(isDisabled(box("toolA"))).toBe(true);

    // The stale p1 grant settles LAST: its token-gated finally must NOT clear persona p2's
    // busy row — it stays disabled while grant(p2) is still in flight.
    await act(async () => {
      resolveP1({ ...TOOL_A, granted: true });
    });
    expect(isDisabled(box("toolA"))).toBe(true);

    // p2's own grant settling then re-enables it (proves the row wasn't stuck).
    await act(async () => {
      resolveP2({ ...TOOL_A, granted: true });
    });
    await waitFor(() => expect(isDisabled(box("toolA"))).toBe(false));
  });

  // The point of caching the catalog per persona: clicking BACK to a persona shows its tools on
  // the first frame, with no read and no "Loading…" in between. That is the whole user-visible
  // difference — every other test here would pass just as well against a panel that re-read from
  // scratch every time.
  it("paints a persona's catalog from cache on the way back, without re-reading", async () => {
    list.mockImplementation((id: string) => Promise.resolve(id === "p1" ? [ALPHA] : [BETA]));

    const { rerender } = render(<AbilitiesPanel personaId="p1" />);
    await screen.findByRole("checkbox", { name: "alpha" });
    rerender(<AbilitiesPanel personaId="p2" />);
    await screen.findByRole("checkbox", { name: "beta" });
    expect(list).toHaveBeenCalledTimes(2);

    rerender(<AbilitiesPanel personaId="p1" />);

    // No `await`: p1's catalog is already on screen, and it never blanked on the way…
    expect(screen.getByRole("checkbox", { name: "alpha" })).not.toBeNull();
    expect(screen.queryByText("Loading…")).toBeNull();
    // …because it came from the cache rather than a third request.
    expect(list).toHaveBeenCalledTimes(2);
  });

  // An optimistic patch now lives in the CACHE rather than in component state, so a mutation
  // abandoned by a persona switch would otherwise leave its guess standing under that persona for
  // the rest of the staleness window — the settle that would have corrected it is exactly the one
  // being dropped. Dropping it marks that persona's entry stale instead, so coming back re-reads.
  it("re-reads a persona whose in-flight mutation was abandoned by a switch", async () => {
    list.mockImplementation((id: string) =>
      Promise.resolve(id === "p1" ? [structuredClone(TOOL_A)] : [BETA]),
    );
    let failP1!: (e: Error) => void;
    grant.mockImplementation(
      () =>
        new Promise<ToolGrant>((_resolve, reject) => {
          failP1 = reject;
        }),
    );

    const { rerender } = render(<AbilitiesPanel personaId="p1" />);
    await screen.findByRole("checkbox", { name: "toolA" });
    fireEvent.click(box("toolA")); // optimistic granted=true, written into p1's entry
    expect(box("toolA").getAttribute("aria-checked")).toBe("true");

    rerender(<AbilitiesPanel personaId="p2" />);
    await screen.findByRole("checkbox", { name: "beta" });

    // p1's grant fails only now — too late to revert the optimistic patch it left behind.
    await act(async () => {
      failP1(new Error("nope"));
    });

    rerender(<AbilitiesPanel personaId="p1" />);

    // p1 is stale, so it re-reads rather than serving the guess…
    await waitFor(() => expect(list).toHaveBeenCalledTimes(3));
    // …and the server's answer stands.
    await waitFor(() => expect(box("toolA").getAttribute("aria-checked")).toBe("false"));
  });

  // The panel used to draw its own API affordance beside the "Abilities" title (FieldGroup
  // `trailing`); that button now lives once, in PersonaEditor's leafHeader (its ButtonBar `api`),
  // so this body must never render one of its own — two API buttons for one persona would say
  // nothing about which is live.
  it("renders no API affordance of its own — that lives in the persona editor's header", async () => {
    render(<AbilitiesPanel personaId="p1" />);
    await screen.findByRole("checkbox", { name: "searchThreads" });
    expect(screen.queryByRole("button", { name: /API/ })).toBeNull();
  });

  // #14 — a genuinely null source is the only "Built-in"; a non-null (esp. delisted third-
  // party / integration) grant renders a distinct, clearly-not-native heading.
  it("labels non-null sources as their own groups, never Built-in (#14)", async () => {
    const staleMcp: ToolCatalogItem = {
      toolName: "mcp.acme.doThing",
      source: "mcp.acme",
      displayName: "mcp.acme.doThing",
      description: "",
      readOnly: false,
      granted: true,
      autonomous: false,
    };
    const staleIntegration: ToolCatalogItem = {
      toolName: "integration.gmail.conn123.sendEmail",
      source: "integration.gmail.conn123",
      displayName: "integration.gmail.conn123.sendEmail",
      description: "",
      readOnly: false,
      granted: true,
      autonomous: false,
    };
    list.mockResolvedValue([SEARCH_THREADS, staleMcp, staleIntegration]);
    render(<AbilitiesPanel personaId="p1" />);
    await screen.findByRole("checkbox", { name: "searchThreads" });

    // The curated built-in still groups under "Built-in"…
    expect(screen.getByText("Built-in")).not.toBeNull();
    // …but the untrusted grants get distinct, clearly-non-native headings — and their raw
    // source ids are never shown as-is (so a stale mcp.* grant can't read as built-in).
    expect(screen.getByText("Third-party: acme")).not.toBeNull();
    expect(screen.getByText("Integration: gmail")).not.toBeNull();
    expect(screen.queryByText("mcp.acme")).toBeNull();
  });
});
