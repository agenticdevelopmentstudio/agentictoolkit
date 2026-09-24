// @vitest-environment jsdom
//
// Component test for AssistantsPanel — the user Settings "Assistants" panel. Only the
// personaUserToolsApi module boundary is mocked (vi.mock) so the panel's per-tool consent
// wiring + optimistic revert are exercised, not the transport.
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor, cleanup, within, act } from "@testing-library/react";

vi.mock("@agentic-toolkit/data/personas", () => ({
  personaUserToolsApi: {
    listActable: vi.fn(),
    listTools: vi.fn(),
    setAllowed: vi.fn(),
  },
}));

import { AssistantsPanel } from "./AssistantsPanel";
import {
  personaUserToolsApi,
  type UserActablePersona,
  type UserTool,
} from "@agentic-toolkit/data/personas";

const listActable = vi.mocked(personaUserToolsApi.listActable);
const listTools = vi.mocked(personaUserToolsApi.listTools);
const setAllowed = vi.mocked(personaUserToolsApi.setAllowed);

const PERSONAS: UserActablePersona[] = [{ id: "a1", slug: "bit", name: "Bitbag" }];

// An ungranted-by-me built-in and a web tool I already allow — so the checklist shows both
// an off and an on toggle (default off). displayName === toolName (+ empty description) is the
// fail-soft state that keeps each row's accessible name equal to its tool name, so the
// `box(toolName)` queries stay stable; rich copy rendering has its own dedicated test.
const SEARCH: UserTool = {
  toolName: "searchThreads",
  source: null,
  displayName: "searchThreads",
  description: "",
  readOnly: true,
  allowed: false,
};
const WEB: UserTool = {
  toolName: "web.search",
  source: "web",
  displayName: "web.search",
  description: "",
  readOnly: true,
  allowed: true,
};
const TOOLS: UserTool[] = [SEARCH, WEB];

beforeEach(() => {
  vi.clearAllMocks();
  listActable.mockResolvedValue(structuredClone(PERSONAS));
  listTools.mockResolvedValue(structuredClone(TOOLS));
  // Default: a realistic backend echo — the returned view reflects exactly the requested
  // allowed set, so optimistic UI and the reconciled response agree.
  setAllowed.mockImplementation(async (_id: string, allowed: string[]) =>
    TOOLS.map((t) => ({ ...t, allowed: allowed.includes(t.toolName) })),
  );
});

// The personas package vitest config has no global afterEach, so RTL's auto-cleanup never
// registers — tear down each render explicitly to keep renders from bleeding across tests.
afterEach(cleanup);

// Each row's Enabled-column Checkbox is named "Allow <tool>" (the tool's human label), and the
// table is `selectable={false}`, so the only checkboxes on screen are these allow switches.
const box = (toolName: string) => screen.getByRole("checkbox", { name: `Allow ${toolName}` });

/** Render the panel and pick persona `id`, waiting for its tool table to load. */
async function renderAndPick(id: string) {
  render(<AssistantsPanel />);
  await screen.findByRole("option", { name: "Bitbag" });
  fireEvent.change(screen.getByRole("combobox"), { target: { value: id } });
  await screen.findByRole("checkbox", { name: "Allow searchThreads" });
}

describe("AssistantsPanel", () => {
  it("wraps the persona picker in a Field (label associates the select)", async () => {
    render(<AssistantsPanel />);
    await screen.findByRole("option", { name: "Bitbag" });
    const select = screen.getByRole("combobox");
    const label = select.closest("label");
    expect(label).not.toBeNull();
    expect(label?.textContent).toContain("Assistant");
  });

  it("lists the actable personas in the picker", async () => {
    render(<AssistantsPanel />);
    expect(await screen.findByRole("option", { name: "Bitbag" })).not.toBeNull();
    expect(listActable).toHaveBeenCalled();
  });

  it("shows a persona's tools with the caller's allow toggle reflected", async () => {
    await renderAndPick("a1");
    expect(listTools).toHaveBeenCalledWith("a1");
    // Default off: the ungranted-by-me built-in is unchecked; the one I allow is checked.
    expect(box("searchThreads").getAttribute("aria-checked")).toBe("false");
    expect(box("web.search").getAttribute("aria-checked")).toBe("true");
  });

  it("renders the human displayName + description, demoting the raw tool name to a mono caption", async () => {
    listTools.mockResolvedValue([
      {
        toolName: "dataKvSet",
        source: null,
        displayName: "Save a value",
        description: "Store a value under a key for the current user.",
        readOnly: false,
        allowed: false,
      },
    ]);
    render(<AssistantsPanel />);
    await screen.findByRole("option", { name: "Bitbag" });
    fireEvent.change(screen.getByRole("combobox"), { target: { value: "a1" } });
    // The human copy leads and names the row's allow checkbox…
    await screen.findByText("Save a value");
    expect(screen.getByRole("checkbox", { name: "Allow Save a value" })).not.toBeNull();
    expect(screen.getByText("Store a value under a key for the current user.")).not.toBeNull();
    // …and the raw camelCase tool name is still present (demoted caption), never hidden.
    expect(screen.getByText("dataKvSet")).not.toBeNull();
  });

  it("labels each tool's provenance in a Source column (null source alone reads Built-in)", async () => {
    await renderAndPick("a1");
    expect(screen.getByRole("columnheader", { name: /source/i })).not.toBeNull();
    expect(screen.getByText("Built-in")).not.toBeNull();
    expect(screen.getByText("Web")).not.toBeNull();
  });

  it("ticking an unchecked tool PUTs the new allowed set with it added", async () => {
    await renderAndPick("a1");

    fireEvent.click(box("searchThreads"));

    await waitFor(() => expect(setAllowed).toHaveBeenCalledTimes(1));
    expect(setAllowed.mock.lastCall?.[0]).toBe("a1");
    expect([...(setAllowed.mock.lastCall?.[1] ?? [])].sort()).toEqual([
      "searchThreads",
      "web.search",
    ]);
    expect(box("searchThreads").getAttribute("aria-checked")).toBe("true");
  });

  it('"All on" PUTs every tool name', async () => {
    await renderAndPick("a1");

    fireEvent.click(screen.getByRole("button", { name: /all on/i }));

    await waitFor(() => expect(setAllowed).toHaveBeenCalledTimes(1));
    expect(setAllowed.mock.lastCall?.[0]).toBe("a1");
    expect([...(setAllowed.mock.lastCall?.[1] ?? [])].sort()).toEqual([
      "searchThreads",
      "web.search",
    ]);
  });

  it('"All off" PUTs the empty set', async () => {
    await renderAndPick("a1");

    fireEvent.click(screen.getByRole("button", { name: /all off/i }));

    await waitFor(() => expect(setAllowed).toHaveBeenCalledTimes(1));
    expect(setAllowed.mock.calls[0]).toEqual(["a1", []]);
  });

  it('with a search typed, "All shown off" flips only the rows on screen', async () => {
    // Both on, so a whole-list All off would PUT [] — the search must keep web.search allowed.
    const BOTH_ON = TOOLS.map((t) => ({ ...t, allowed: true }));
    listTools.mockResolvedValue(structuredClone(BOTH_ON));
    await renderAndPick("a1");

    fireEvent.change(screen.getByPlaceholderText("Tool, name or source"), {
      target: { value: "searchThreads" },
    });
    await waitFor(() =>
      expect(screen.queryByRole("checkbox", { name: "Allow web.search" })).toBeNull(),
    );
    fireEvent.click(screen.getByRole("button", { name: "All shown off" }));

    await waitFor(() => expect(setAllowed).toHaveBeenCalledTimes(1));
    expect(setAllowed.mock.calls[0]).toEqual(["a1", ["web.search"]]);
  });

  it("clears the search when another assistant is picked", async () => {
    const TWO: UserActablePersona[] = [
      { id: "a1", slug: "bit", name: "Bitbag" },
      { id: "a2", slug: "baz", name: "Bazbag" },
    ];
    listActable.mockResolvedValue(structuredClone(TWO));
    await renderAndPick("a1");
    const search = screen.getByPlaceholderText("Tool, name or source") as HTMLInputElement;
    fireEvent.change(search, { target: { value: "web" } });

    fireEvent.change(screen.getByRole("combobox"), { target: { value: "a2" } });
    await screen.findByRole("checkbox", { name: "Allow searchThreads" });
    expect(
      (screen.getByPlaceholderText("Tool, name or source") as HTMLInputElement).value,
    ).toBe("");
    expect(screen.getByRole("button", { name: "All on" })).not.toBeNull();
  });

  it("reverts the checkbox when the PUT rejects", async () => {
    setAllowed.mockRejectedValueOnce(new Error("nope"));
    await renderAndPick("a1");

    fireEvent.click(box("searchThreads"));
    // Optimistic tick flips it on immediately, then reverts once the rejected PUT settles.
    expect(box("searchThreads").getAttribute("aria-checked")).toBe("true");

    await waitFor(() => expect(setAllowed).toHaveBeenCalled());
    await waitFor(() =>
      expect(box("searchThreads").getAttribute("aria-checked")).toBe("false"),
    );
  });

  it("shows a friendly empty state when no personas may act for the user", async () => {
    listActable.mockResolvedValueOnce([]);
    render(<AssistantsPanel />);
    expect(await screen.findByText(/no assistants/i)).not.toBeNull();
    expect(screen.queryByRole("combobox")).toBeNull();
  });

  it("keeps the picker options addressable within the select", async () => {
    render(<AssistantsPanel />);
    await screen.findByRole("option", { name: "Bitbag" });
    const select = screen.getByRole("combobox");
    expect(within(select).getByRole("option", { name: "Bitbag" })).not.toBeNull();
  });

  it("unticking one already-on tool PUTs the reduced set with only the still-on tool", async () => {
    // Both tools start allowed, so unticking one must leave a NON-empty reduced set (proving the
    // payload is the derived remaining set, not a blanket all-off).
    const BOTH_ON: UserTool[] = [
      { toolName: "searchThreads", source: null, displayName: "searchThreads", description: "", readOnly: true, allowed: true },
      { toolName: "web.search", source: "web", displayName: "web.search", description: "", readOnly: true, allowed: true },
    ];
    listTools.mockResolvedValue(structuredClone(BOTH_ON));
    setAllowed.mockImplementation(async (_id: string, allowed: string[]) =>
      BOTH_ON.map((t) => ({ ...t, allowed: allowed.includes(t.toolName) })),
    );
    await renderAndPick("a1");
    expect(box("searchThreads").getAttribute("aria-checked")).toBe("true");
    expect(box("web.search").getAttribute("aria-checked")).toBe("true");

    fireEvent.click(box("searchThreads")); // untick just this one

    await waitFor(() => expect(setAllowed).toHaveBeenCalledTimes(1));
    expect(setAllowed.mock.lastCall?.[0]).toBe("a1");
    // The reduced set drops the unticked tool but keeps the still-on one.
    expect(setAllowed.mock.lastCall?.[1]).toEqual(["web.search"]);
    expect(box("searchThreads").getAttribute("aria-checked")).toBe("false");
    expect(box("web.search").getAttribute("aria-checked")).toBe("true");
  });

  it("drops a stale in-flight tool list when the persona is switched mid-load (loadToken guard)", async () => {
    const TWO: UserActablePersona[] = [
      { id: "a1", slug: "bit", name: "Bitbag" },
      { id: "a2", slug: "baz", name: "Bazbag" },
    ];
    listActable.mockResolvedValue(structuredClone(TWO));
    const A1_TOOLS: UserTool[] = [
      { toolName: "onlyA1", source: null, displayName: "onlyA1", description: "", readOnly: true, allowed: false },
    ];
    const A2_TOOLS: UserTool[] = [
      { toolName: "onlyA2", source: null, displayName: "onlyA2", description: "", readOnly: true, allowed: false },
    ];
    // a1's list stays pending until we release it; a2's resolves immediately.
    let resolveA1: (() => void) | undefined;
    listTools.mockImplementation((id: string) => {
      if (id === "a1") {
        return new Promise<UserTool[]>((res) => {
          resolveA1 = () => res(structuredClone(A1_TOOLS));
        });
      }
      return Promise.resolve(structuredClone(A2_TOOLS));
    });

    render(<AssistantsPanel />);
    await screen.findByRole("option", { name: "Bazbag" });
    const select = screen.getByRole("combobox");
    fireEvent.change(select, { target: { value: "a1" } }); // a1 load starts, stays pending
    fireEvent.change(select, { target: { value: "a2" } }); // a2 load resolves and renders
    await screen.findByRole("checkbox", { name: "Allow onlyA2" });

    // Release a1's since-abandoned load AFTER the switch: the loadToken guard must ignore it so
    // a1's tool never crosses into the a2 selection now on screen.
    await act(async () => {
      resolveA1?.();
      await Promise.resolve();
    });
    expect(screen.queryByRole("checkbox", { name: "Allow onlyA1" })).toBeNull();
    expect(screen.queryByRole("checkbox", { name: "Allow onlyA2" })).not.toBeNull();
  });
});
