// The DESTINATIONS list — the part of this feature that is new rather than moved.
//
// Only the three data reads and next/navigation are mocked; `useResourceList`, the rail-host
// publish path and IntegrationsPane itself run for real inside the same minimal host harness the
// sibling features' tests use (features/teams/src/TeamsFeature.test.tsx). That matters for the
// no-realm cases: the assertion that the pane is NOT mounted is only worth anything if a mounted
// pane would really have registered its level.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen, waitFor } from "@testing-library/react";
import { useMemo, useState, type ReactNode } from "react";
import {
  RailHostContext,
  type RailHostRegistry,
  type RegisteredLevels,
} from "@agentic-toolkit/resource";
import type { TopicLevel } from "@agenticdevelopertoolkit/ui/blocks";
import type { Workspace } from "@agentic-toolkit/data";

const { push } = vi.hoisted(() => ({ push: vi.fn() }));
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push, replace: vi.fn(), prefetch: vi.fn() }),
}));

vi.mock("@agentic-toolkit/data/personas", () => ({
  api: { personas: { list: vi.fn() } },
}));

vi.mock("@agentic-toolkit/data/ecosystems", () => ({
  ecosystemsApi: { listForWorkspace: vi.fn() },
  useWorkspaceDefaultEcosystemId: vi.fn(),
}));

vi.mock("@agentic-toolkit/data/integrations", () => ({
  integrationsApi: {
    listProviderConfigs: vi.fn(),
    listProviders: vi.fn(),
  },
  // ConnectAccountDialog imports it at module load; never called in these tests.
  oauthCallbackUrl: () => "http://localhost/integrations/oauth-callback",
}));

import { IntegrationsFeature } from "./IntegrationsFeature";
import { api as personasApi, type Persona } from "@agentic-toolkit/data/personas";
import {
  ecosystemsApi,
  useWorkspaceDefaultEcosystemId,
  type Ecosystem,
} from "@agentic-toolkit/data/ecosystems";
import { integrationsApi } from "@agentic-toolkit/data/integrations";

const listPersonas = vi.mocked(personasApi.personas.list);
const listProducts = vi.mocked(ecosystemsApi.listForWorkspace);
const defaultEcosystem = vi.mocked(useWorkspaceDefaultEcosystemId);
const listConfigs = vi.mocked(integrationsApi.listProviderConfigs);
const listProviders = vi.mocked(integrationsApi.listProviders);

const persona = (patch: Partial<Persona>): Persona =>
  ({
    id: "p1",
    slug: "persona.acme.scout",
    name: "Scout",
    ownedEcosystemId: "eco-scout",
    ...patch,
  }) as Persona;

const product = (patch: Partial<Ecosystem>): Ecosystem =>
  ({ id: "eco-1", name: "Acme App", identifier: "ecosystem.acme.app", ...patch }) as Ecosystem;

/** Each test gets its own slug: `useResourceList` caches rows at module scope keyed by the cache
 *  key, and every key here carries the slug — so a fresh slug is what keeps one test's rows out
 *  of the next one's first paint. */
let slugSeq = 0;
function workspaceFor(kind: Workspace["kind"], name: string): Workspace {
  slugSeq += 1;
  return { slug: `ws-${slugSeq}`, name, kind };
}

beforeEach(() => {
  vi.clearAllMocks();
  listPersonas.mockResolvedValue([]);
  listProducts.mockResolvedValue([]);
  defaultEcosystem.mockReturnValue({
    ecosystemId: "eco-workspace",
    canManage: true,
    isError: false,
    isPending: false,
    isFetching: false,
  });
  listConfigs.mockResolvedValue([]);
  listProviders.mockResolvedValue([]);
});

afterEach(cleanup);

/** Renders the merged rail as flat, queryable rows — one container per level, so a test can ask
 *  both "which rows are published" and "did the pane's own level get published at all". */
function Rail({ levels }: { levels: TopicLevel[] }) {
  return (
    <div>
      {levels.map((l) => (
        <div key={l.id} data-testid={`level-${l.id}`}>
          {l.items.map((item) => (
            <button key={item.id} type="button" onClick={() => l.onSelect(item.id)}>
              {item.label}
            </button>
          ))}
        </div>
      ))}
    </div>
  );
}

function Harness({ children }: { children: ReactNode }) {
  const [entries, setEntries] = useState<Map<string, RegisteredLevels>>(new Map());
  const registry: RailHostRegistry = useMemo(
    () => ({
      registerLevels: (id, entry) =>
        setEntries((m) => new Map(m).set(id, entry)),
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
  const mergedLevels = [...entries.values()]
    .sort((a, b) => a.depth - b.depth)
    .flatMap((e) => e.levels);
  return (
    <RailHostContext.Provider value={registry}>
      <Rail levels={mergedLevels} />
      {children}
    </RailHostContext.Provider>
  );
}

/** The rows of the destinations level, in published order. */
function destinationRows(): string[] {
  const level = screen.getByTestId("level-integrations-destinations");
  return [...level.querySelectorAll("button")].map((b) => b.textContent ?? "");
}

describe("the destinations list", () => {
  it("names the workspace's own row for a PERSONAL account, and lists it first", async () => {
    const ws = workspaceFor("individual", "Mike Fullerton");
    listProducts.mockResolvedValue([product({})]);
    render(
      <Harness>
        <IntegrationsFeature basePath="/home" workspace={ws} />
      </Harness>,
    );
    await waitFor(() => expect(destinationRows()).toEqual(["My Integrations", "Acme App"]));
  });

  it("names the same row for an ORGANIZATION account", async () => {
    // The whole reason SiteHomeScope carries the workspace ROW rather than its slug: this wording
    // is only decidable from `kind`, and it must be right on the FIRST paint.
    const ws = workspaceFor("organization", "Acme Inc");
    render(
      <Harness>
        <IntegrationsFeature basePath="/home" workspace={ws} />
      </Harness>,
    );
    await waitFor(() => expect(destinationRows()).toEqual(["Org Integrations"]));
  });

  it("lists the workspace, then its personas by name, then its products", async () => {
    const ws = workspaceFor("individual", "Mike Fullerton");
    listPersonas.mockResolvedValue([
      persona({ id: "p2", name: "Zeta", slug: "persona.acme.zeta" }),
      persona({ id: "p1", name: "Alpha", slug: "persona.acme.alpha" }),
    ]);
    listProducts.mockResolvedValue([product({ id: "eco-1", name: "Acme App" })]);
    render(
      <Harness>
        <IntegrationsFeature basePath="/home" workspace={ws} />
      </Harness>,
    );
    await waitFor(() =>
      expect(destinationRows()).toEqual(["My Integrations", "Alpha", "Zeta", "Acme App"]),
    );
    // Every read is scoped to THIS workspace — an unscoped list would show the personal
    // workspace's rows inside an org.
    expect(listPersonas).toHaveBeenCalledWith({ workspace: ws.slug });
    expect(listProducts).toHaveBeenCalledWith(ws.slug);
  });

  it("routes a picked destination onto the URL", async () => {
    const ws = workspaceFor("individual", "Mike Fullerton");
    render(
      <Harness>
        <IntegrationsFeature basePath="/home" workspace={ws} />
      </Harness>,
    );
    (await screen.findByText("My Integrations")).click();
    expect(push).toHaveBeenCalledWith("/home/workspace", { scroll: false });
  });

  it("reports a failed read ALONGSIDE the destinations that did load", async () => {
    const ws = workspaceFor("individual", "Mike Fullerton");
    listPersonas.mockRejectedValue(new Error("personas are down"));
    listProducts.mockResolvedValue([product({})]);
    render(
      <Harness>
        <IntegrationsFeature basePath="/home" workspace={ws} />
      </Harness>,
    );
    expect(await screen.findByText("personas are down")).toBeTruthy();
    // Not instead of them: the workspace row and the products are unaffected by the failure.
    expect(destinationRows()).toEqual(["My Integrations", "Acme App"]);
  });
});

describe("the pane below a destination", () => {
  it("mounts against the workspace's own ecosystem", async () => {
    const ws = workspaceFor("individual", "Mike Fullerton");
    render(
      <Harness>
        <IntegrationsFeature basePath="/home" workspace={ws} destinationId="workspace" />
      </Harness>,
    );
    await waitFor(() => expect(listConfigs).toHaveBeenCalledWith("eco-workspace"));
    expect(screen.getByTestId("level-integrations-list")).toBeTruthy();
  });

  it("mounts against a persona's OWN ecosystem, not the workspace's", async () => {
    const ws = workspaceFor("individual", "Mike Fullerton");
    listPersonas.mockResolvedValue([persona({ id: "p1", ownedEcosystemId: "eco-scout" })]);
    render(
      <Harness>
        <IntegrationsFeature basePath="/home" workspace={ws} destinationId="p1" />
      </Harness>,
    );
    await waitFor(() => expect(listConfigs).toHaveBeenCalledWith("eco-scout"));
    expect(listConfigs).not.toHaveBeenCalledWith("eco-workspace");
  });

  it("says a persona has no realm instead of reporting it has no integrations", async () => {
    // The defect this pins: IntegrationsPane with no ecosystemId resolves its list to [] and
    // renders "No integrations yet." — an authoritative-sounding answer to a question that was
    // never asked. So the pane must not be mounted at all.
    const ws = workspaceFor("individual", "Mike Fullerton");
    listPersonas.mockResolvedValue([persona({ id: "p1", ownedEcosystemId: null })]);
    render(
      <Harness>
        <IntegrationsFeature basePath="/home" workspace={ws} destinationId="p1" />
      </Harness>,
    );
    expect(await screen.findByText(/no realm yet/i)).toBeTruthy();
    expect(screen.queryByTestId("level-integrations-list")).toBeNull();
    expect(listConfigs).not.toHaveBeenCalled();
  });

  it("waits while the workspace's ecosystem is still resolving", async () => {
    // `isPending` is the third state, and it is NOT "no ecosystem": answering it as one would
    // flash the no-ecosystem copy on every cold load of the first destination.
    const ws = workspaceFor("individual", "Mike Fullerton");
    defaultEcosystem.mockReturnValue({
      canManage: false,
      isError: false,
      isPending: true,
      isFetching: false,
    });
    render(
      <Harness>
        <IntegrationsFeature basePath="/home" workspace={ws} destinationId="workspace" />
      </Harness>,
    );
    // Waited for the ROW first: "Loading…" is also what the body says while the destinations
    // themselves are still loading, so this pins the pending ECOSYSTEM read specifically.
    expect(await screen.findByText("My Integrations")).toBeTruthy();
    expect(screen.getByText("Loading…")).toBeTruthy();
    expect(screen.queryByText(/no ecosystem yet/i)).toBeNull();
    expect(listConfigs).not.toHaveBeenCalled();
  });

  it("says the workspace has no ecosystem once the read settles empty", async () => {
    const ws = workspaceFor("individual", "Mike Fullerton");
    defaultEcosystem.mockReturnValue({
      canManage: false,
      isError: false,
      isPending: false,
      isFetching: false,
    });
    render(
      <Harness>
        <IntegrationsFeature basePath="/home" workspace={ws} destinationId="workspace" />
      </Harness>,
    );
    expect(await screen.findByText(/no ecosystem yet/i)).toBeTruthy();
    expect(listConfigs).not.toHaveBeenCalled();
  });

  it("ignores a destination id that resolves to nothing", async () => {
    // Resolution is a LOOKUP, so an id from a stale link (or another workspace's product) falls
    // back to the destination list rather than scoping the pane to a principal we never verified.
    const ws = workspaceFor("individual", "Mike Fullerton");
    render(
      <Harness>
        <IntegrationsFeature basePath="/home" workspace={ws} destinationId="eco-somebody-else" />
      </Harness>,
    );
    expect(await screen.findByText(/select a destination/i)).toBeTruthy();
    expect(listConfigs).not.toHaveBeenCalled();
  });
});
