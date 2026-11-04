// @vitest-environment jsdom
//
// Component test for the Save gate in ServicesSection's service editor (task 4 of the
// editable-detail Save wiring): Save must start DISABLED for an already-loaded service and only
// enable once the draft actually differs from what was loaded (dirty && valid), not merely because
// the required fields happen to be filled (the pre-existing bug this task fixes). Only the
// `@agentic-toolkit/data/personas` module boundary is mocked, so the real ServiceEditor/useDirtyDraft
// wiring is exercised, not the transport.
//
// HierarchicalTopicDetail (which ServicesSection renders through) measures its container's
// clientWidth via ResizeObserver to choose wide vs. narrow layout; jsdom's default clientWidth is 0,
// which reads as narrow and would hide the selected leaf's detail pane behind a push-nav this test
// never drives. Force wide mode the same way external/adhsdk/packages/web/packages/ui/src/__tests__/hierarchicalTopicDetail.test.tsx
// does — override clientWidth before the first (useLayoutEffect) measurement.
import { describe, it, expect, vi, beforeEach, afterEach, afterAll } from "vitest";
import { render, screen, fireEvent, waitFor, cleanup } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

vi.mock("@agentic-toolkit/data/personas", () => ({
  api: {
    templates: vi.fn(),
    services: {
      list: vi.fn(),
      create: vi.fn(),
      patch: vi.fn(),
      delete: vi.fn(),
      connect: vi.fn(),
      refreshModels: vi.fn(),
    },
  },
}));

import { ServicesSection } from "./ServicesSection";
import {
  RailHostContext,
  type PaneExitGuard,
  type RailHostRegistry,
} from "@agentic-toolkit/resource";
import { api, type UserService } from "@agentic-toolkit/data/personas";

const list = vi.mocked(api.services.list);
const patchService = vi.mocked(api.services.patch);

const SERVICE: UserService = {
  id: "svc_1",
  templateId: null,
  providerKind: "openai",
  name: "My OpenAI",
  baseUrl: "https://api.openai.com/v1",
  hasApiKey: true,
  connectStatus: "connected",
  connectError: null,
  lastConnectedAt: null,
  documentationUrl: null,
  statusUrl: null,
  models: [],
  modelsFetchedAt: null,
};

// Module-scope prototype patch — safe under featureVitest()'s default per-file test isolation
// (each test file gets its own module registry/prototype), but a trap if `isolate` were ever
// turned off (patch would leak into other files). Restore it in `afterAll` so this file cleans
// up after itself regardless.
const originalClientWidth = Object.getOwnPropertyDescriptor(HTMLElement.prototype, "clientWidth");
Object.defineProperty(HTMLElement.prototype, "clientWidth", {
  configurable: true,
  get: () => 1200,
});

beforeEach(() => {
  vi.clearAllMocks();
  list.mockResolvedValue([SERVICE]);
});

afterEach(cleanup);

afterAll(() => {
  if (originalClientWidth) {
    Object.defineProperty(HTMLElement.prototype, "clientWidth", originalClientWidth);
  } else {
    delete (HTMLElement.prototype as { clientWidth?: unknown }).clientWidth;
  }
});

describe("ServicesSection save gate (service editor)", () => {
  it("starts disabled for an unmodified service and enables after one field edit", async () => {
    render(<ServicesSection urlSelection={{ serviceId: SERVICE.id, onSelectService: vi.fn() }} />);

    const save = await screen.findByRole("button", { name: "Save" });
    expect(save).toBeDisabled();

    await userEvent.type(screen.getByLabelText(/name/i), "!");
    expect(save).toBeEnabled();
  });

  it("re-disables Save after a successful save (baseline moves AND saving clears)", async () => {
    const saved: UserService = { ...SERVICE, name: "Renamed" };
    patchService.mockResolvedValue(saved);

    render(<ServicesSection urlSelection={{ serviceId: SERVICE.id, onSelectService: vi.fn() }} />);

    const save = await screen.findByRole("button", { name: "Save" });
    fireEvent.change(screen.getByLabelText(/name/i), { target: { value: "Renamed" } });
    expect(save).toBeEnabled();

    fireEvent.click(save);
    await waitFor(() =>
      expect(patchService).toHaveBeenCalledWith("svc_1", {
        name: "Renamed",
        baseUrl: SERVICE.baseUrl,
      }),
    );

    // Assert BOTH halves of post-save recovery, not just one: the button's accessible name is
    // back to "Save" (a stuck `saving` flag — no `finally { setSaving(false) }` on the success
    // path — would leave it reading "Saving…" forever, so this `findByRole` would time out) AND
    // that "Save" button is disabled (a skipped `commit()` — baseline never adopts the saved row
    // — would leave `dirty` true forever, so the button would be enabled instead). Either bug
    // alone fails this pair; asserting only "disabled" (as before) missed the stuck-saving bug
    // entirely, since a permanently-disabled "Saving…" button also satisfies `toBeDisabled()`.
    const saveAfter = await screen.findByRole("button", { name: "Save" });
    expect(saveAfter).toBeDisabled();
  });

  // `handleSave` opens with `if (!valid) return` — the gate disables Save before that can run, so
  // clearing a required field otherwise yields a grey button and zero explanation.
  it("says WHY Save is blocked when a required field is cleared", async () => {
    render(<ServicesSection urlSelection={{ serviceId: SERVICE.id, onSelectService: vi.fn() }} />);

    await screen.findByRole("button", { name: "Save" });
    expect(screen.queryByText("A name is required.")).toBeNull();

    fireEvent.change(screen.getByLabelText(/name/i), { target: { value: "  " } });

    expect(screen.getByRole("button", { name: "Save" })).toBeDisabled();
    expect(screen.getByText("A name is required.")).toBeInTheDocument();
  });

  // The other half: a service that arrives already invalid must not open with a complaint about a
  // row the user hasn't touched.
  it("stays silent about an already-blank name the user hasn't touched", async () => {
    list.mockResolvedValue([{ ...SERVICE, name: "" }]);
    render(<ServicesSection urlSelection={{ serviceId: SERVICE.id, onSelectService: vi.fn() }} />);

    const save = await screen.findByRole("button", { name: "Save" });
    expect(save).toBeDisabled();
    expect(screen.queryByText("A name is required.")).toBeNull();
  });
});

// The SAME `dirty` the gate above reads used to gate nothing else, so every exit that does not go
// through Save discarded the draft in silence — a rail row switch, the breadcrumb up, an in-app
// link, a reload. Publishing it into the host's registry is what makes the enclosing exits see it,
// exactly as the sibling PersonaEditor does with its own dirt.
describe("ServicesSection unsaved-work guard (service editor)", () => {
  /** A minimal rail host recording which ids currently hold a guard — the same stand-in
   *  PersonaEditor.test.tsx and resource's railExitGuardDirtyRegistration.test.tsx use, so
   *  "registered" means what it means to the real hub/standalone hosts. */
  function makeHost() {
    const live = new Map<string, PaneExitGuard>();
    const registry: RailHostRegistry = {
      registerLevels: vi.fn(),
      unregisterLevels: vi.fn(),
      registerExitGuard: vi.fn((id: string, g: PaneExitGuard | null) => {
        if (g === null) live.delete(id);
        else live.set(id, g);
      }),
      popStack: vi.fn(),
      reportMissing: vi.fn(),
      reportBusy: vi.fn(),
      toolbarSlot: null,
    };
    return { live, registry };
  }

  function renderUnderHost(host: ReturnType<typeof makeHost>) {
    render(
      <RailHostContext.Provider value={host.registry}>
        <ServicesSection urlSelection={{ serviceId: SERVICE.id, onSelectService: vi.fn() }} />
      </RailHostContext.Provider>,
    );
  }

  it("registers nothing while the open service is unmodified", async () => {
    const host = makeHost();
    renderUnderHost(host);
    await screen.findByRole("button", { name: "Save" });
    // The control for the tests below: presence IS the dirty signal the host's browser guard
    // reads (`guards.size > 0`), so an always-registering editor would prompt on the way out of
    // every service anyone merely looked at.
    expect(host.live.size).toBe(0);
  });

  it("publishes a guard reporting dirty once the draft is edited", async () => {
    const host = makeHost();
    renderUnderHost(host);
    await screen.findByRole("button", { name: "Save" });

    await userEvent.type(screen.getByLabelText(/name/i), "!");

    expect(host.live.size).toBe(1);
    expect([...host.live.values()][0]!.isDirty()).toBe(true);
  });

  it("withdraws the guard when the edit is reverted", async () => {
    const host = makeHost();
    renderUnderHost(host);
    await screen.findByRole("button", { name: "Save" });

    const name = screen.getByLabelText(/name/i);
    await userEvent.type(name, "!");
    expect(host.live.size).toBe(1);

    await userEvent.type(name, "{backspace}");
    expect(host.live.size).toBe(0);
  });

  // Saving is the one exit that is not a loss, and `commit()` re-seeds the baseline — so the guard
  // must come down on the same signal that re-disables Save, or the next navigation prompts about
  // work that is already on the server.
  it("withdraws the guard after a successful save", async () => {
    const host = makeHost();
    patchService.mockResolvedValue({ ...SERVICE, name: "Renamed" });
    renderUnderHost(host);

    const save = await screen.findByRole("button", { name: "Save" });
    fireEvent.change(screen.getByLabelText(/name/i), { target: { value: "Renamed" } });
    expect(host.live.size).toBe(1);

    fireEvent.click(save);
    await waitFor(() => expect(patchService).toHaveBeenCalled());
    await waitFor(() => expect(host.live.size).toBe(0));
  });
});
