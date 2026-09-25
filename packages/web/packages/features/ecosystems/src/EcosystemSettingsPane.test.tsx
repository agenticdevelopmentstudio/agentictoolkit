// @vitest-environment jsdom
//
// The host-injected Transfer Ownership seam: that the pane calls it with the ACTIVE record, places
// it above the Danger Zone, and renders nothing at all when the host injects none (a standalone
// feature site) or when no record is selected.
//
// `./EcosystemForm` is module-mocked because `useRdidAvailability` calls react-query's `useQuery`,
// which throws without a QueryClientProvider. Same prop-echoing-stub idiom as personas'
// PersonaEditor.test.tsx. Nothing else in the pane's tree touches react-query (@agentic-toolkit/
// resource has no react-query dependency at all), so this one mock is the whole harness.
import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, cleanup, act } from "@testing-library/react";
import type { ComponentProps } from "react";
import { ecosystemsApi, type Ecosystem } from "@agentic-toolkit/data/ecosystems";

// The stub ECHOES the props that carry the pane's answer to "what is this row's slug?" and "what
// does the availability probe say about it", so the tests below assert what the field was handed
// rather than what it rendered (the real field is a controlled input in a package this file
// deliberately does not load). Its button is the only way to type here, for the same reason.
vi.mock("./EcosystemForm", () => ({
  EcosystemFields: ({
    prefix,
    slug,
    status,
    onSlug,
  }: {
    prefix: string;
    slug: string;
    status: string;
    onSlug: (v: string) => void;
  }) => (
    <div data-testid="eco-fields" data-prefix={prefix} data-slug={slug} data-status={status}>
      <button type="button" onClick={() => onSlug("gizmos")}>
        rename
      </button>
    </div>
  ),
  ecoCreateRdidValid: () => true,
  // Spied so "what did the pane ask about" is assertable — `null` is the pane declining to ask.
  useRdidAvailability: vi.fn(() => "available"),
}));

// Only the transport is replaced; the mappers and types stay real.
vi.mock("@agentic-toolkit/data/ecosystems", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@agentic-toolkit/data/ecosystems")>()),
  ecosystemsApi: { update: vi.fn() },
}));

import { EcosystemSettingsPane } from "./EcosystemSettingsPane";
import { useRdidAvailability } from "./EcosystemForm";

afterEach(() => {
  cleanup();
  // mockReset, not mockClear: it also drops a verdict a test set for itself (the rename-gate
  // tests below) and puts back the factory's "available" for the next one.
  vi.mocked(useRdidAvailability).mockReset();
  vi.mocked(ecosystemsApi.update).mockReset();
});

/** The last identifier the pane asked the availability probe about — `null` when it asked nothing. */
const probedFor = () => vi.mocked(useRdidAvailability).mock.calls.at(-1)?.[0] ?? null;

const WIDGETS: Ecosystem = {
  id: "ecosystem.acme.widgets",
  identifier: "ecosystem.acme.widgets",
  slug: "widgets",
  name: "Widgets",
  description: "",
  region: "",
  domain: "",
  createdAt: "2026-01-01T00:00:00.000Z",
  updatedAt: "2026-01-01T00:00:00.000Z",
};

// Echoes back what the seam was handed, so "called with the ACTIVE record" is directly assertable
// rather than inferred from the node merely existing.
const seam = (e: { id: string; identifier: string }) => (
  <div data-testid="transfer" data-id={e.id} data-identifier={e.identifier} />
);

function renderPane(props: Partial<ComponentProps<typeof EcosystemSettingsPane>> = {}) {
  return render(
    <EcosystemSettingsPane
      noun="Product"
      ecosystemId={WIDGETS.id}
      items={[WIDGETS]}
      refresh={() => {}}
      {...props}
    />,
  );
}

describe("EcosystemSettingsPane transfer seam", () => {
  it("renders the host's seam, handed the active ecosystem", () => {
    renderPane({ renderTransferOwnership: seam });
    const node = screen.getByTestId("transfer");
    expect(node.getAttribute("data-id")).toBe("ecosystem.acme.widgets");
    expect(node.getAttribute("data-identifier")).toBe("ecosystem.acme.widgets");
  });

  it("renders nothing where the host injects no seam", () => {
    renderPane();
    expect(screen.queryByTestId("transfer")).toBeNull();
  });

  it("renders nothing when no record is active", () => {
    renderPane({ ecosystemId: "ecosystem.acme.gone", renderTransferOwnership: seam });
    expect(screen.queryByTestId("transfer")).toBeNull();
  });

  // Order matters: the Danger Zone is terminal, so anything below it reads as part of it.
  // compareDocumentPosition is the only oracle here — both sections exist either way, so a
  // presence assertion would pass with them swapped.
  it("places the seam ABOVE the Danger Zone", () => {
    renderPane({ renderTransferOwnership: seam, onDelete: async () => {} });
    const transfer = screen.getByTestId("transfer");
    const danger = screen.getByRole("region", { name: "Danger Zone" });
    expect(transfer.compareDocumentPosition(danger) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });
});

// A row's rdid is the handle stored for it; its address is DERIVED from `<parent chain>.<slug>`.
// They are the same string until something writes one without the other — a bare handle rename,
// a backfill, or (before 2026-08-10) a slug rename whose cascade moved the descendants and left
// the row's own handle behind. The hub's own product sat drifted that way, and the field labelled
// "Slug" showed `agenticdeveloperhub` while the slug column said something else entirely.
describe("EcosystemSettingsPane slug sourcing", () => {
  const DRIFTED: Ecosystem = { ...WIDGETS, slug: "gadgets" };

  it("hands the field the STORED SLUG, not the handle's last segment", () => {
    renderPane({ ecosystemId: DRIFTED.id, items: [DRIFTED] });
    const fields = screen.getByTestId("eco-fields");
    expect(fields.getAttribute("data-slug")).toBe("gadgets");
    // The scope still comes from the handle — a rename moves the leaf, never the parent chain.
    expect(fields.getAttribute("data-prefix")).toBe("ecosystem.acme.");
  });

  it("shows the slug unchanged where handle and slug agree", () => {
    renderPane();
    expect(screen.getByTestId("eco-fields").getAttribute("data-slug")).toBe("widgets");
  });
});

// THE WINDOW AFTER A RENAME LANDS. The hook re-points its selection at the id the server returned,
// so the form keeps editing the row it just saved — but `active` is found by the `ecosystemId`
// PROP, which still names the OLD id until the host navigates. For that render the pane has a
// draft and no active row, and it used to answer the gap by treating the address as top-level and
// the draft as changed: it re-split `ecosystem.acme.gizmos` under a bare `ecosystem.` prefix and
// probed the address the save had just minted — which exists, because the save minted it. A
// successful rename therefore ended on "already in use", with Save disabled.
describe("EcosystemSettingsPane between a rename and the host's navigation", () => {
  const RENAMED: Ecosystem = {
    ...WIDGETS,
    id: "ecosystem.acme.gizmos",
    identifier: "ecosystem.acme.gizmos",
    slug: "gizmos",
  };

  /** Rename WIDGETS -> RENAMED through the pane, then land the parent's list refresh WITHOUT the
   *  navigation — `ecosystemId` still points at the old id. */
  async function renameAndRefresh() {
    vi.mocked(ecosystemsApi.update).mockResolvedValue(RENAMED);
    const view = renderPane();
    await act(async () => {
      screen.getByRole("button", { name: "rename" }).click();
    });
    await act(async () => {
      screen.getByRole("button", { name: "Save" }).click();
    });
    view.rerender(
      <EcosystemSettingsPane
        noun="Product"
        ecosystemId={WIDGETS.id}
        items={[RENAMED]}
        refresh={() => {}}
      />,
    );
    return view;
  }

  it("sends the rename and keeps editing the row the server returned", async () => {
    await renameAndRefresh();
    expect(vi.mocked(ecosystemsApi.update)).toHaveBeenCalledWith(
      "ecosystem.acme.widgets",
      expect.objectContaining({ identifier: "ecosystem.acme.gizmos" }),
    );
    expect(screen.getByTestId("eco-fields").getAttribute("data-slug")).toBe("gizmos");
  });

  it("keeps the SCOPED prefix rather than collapsing to top-level", async () => {
    await renameAndRefresh();
    expect(screen.getByTestId("eco-fields").getAttribute("data-prefix")).toBe("ecosystem.acme.");
  });

  it("probes nothing, and reports no problem, while there is no row to compare against", async () => {
    await renameAndRefresh();
    expect(probedFor()).toBeNull();
    expect(screen.getByTestId("eco-fields").getAttribute("data-status")).toBe("idle");
  });
});

// A RENAME WAITS FOR THE PROBE'S GO-AHEAD. useMasterDetailForm waives any reason the STORED record
// reproduces (a problem the backend wrote is not the edit's fault), and this pane's `validate` used
// to judge "is this a rename?" by the probe's render-scoped verdict instead of by the identifier it
// was handed. So while the probe was checking or had errored, the untouched stored row reproduced
// "Waiting for the identifier availability check.", the waiver cleared it, and Save sent the
// rename without the probe's go-ahead.
describe("EcosystemSettingsPane rename gate", () => {
  it.each(["checking", "error"] as const)(
    "keeps Save disabled, and says why, while the probe is %s",
    async (verdict) => {
      vi.mocked(useRdidAvailability).mockReturnValue(verdict);
      renderPane();
      await act(async () => {
        screen.getByRole("button", { name: "rename" }).click();
      });
      // The pane really is asking about the NEW address, so the verdict is about this rename.
      expect(probedFor()).toBe("ecosystem.acme.gizmos");
      expect(screen.getByTestId("eco-fields").getAttribute("data-status")).toBe(verdict);
      expect(screen.getByRole("button", { name: "Save" })).toBeDisabled();
      expect(screen.getByText("Waiting for the identifier availability check.")).toBeInTheDocument();
    },
  );
});
