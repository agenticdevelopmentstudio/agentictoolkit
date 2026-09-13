// @vitest-environment jsdom
//
// Component + helper tests for TeamPermissionsPane — the workspace roles editor. Mirrors the
// TeamMembersPane test style: jsdom + @testing-library/react, mocking only the data boundary
// (@agentic-toolkit/data/access). The roles LIST is published to a rail HOST via
// useMasterDetailLevel (not rendered by the pane itself), so a tiny <Rail> harness backed by the
// toolkit's RailHostContext renders the published rows + the "New role" affordance — the same path
// the hub's workspace shell uses. The editor's ButtonBar portals into the (null) toolbar slot,
// which ToolbarPortal renders inline, so Save/Delete are drivable here too.
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  render,
  screen,
  fireEvent,
  waitFor,
  cleanup,
  within,
} from "@testing-library/react";
import { useMemo, useState, type ReactNode } from "react";
import type { TopicLevel } from "@agenticdevelopertoolkit/ui/blocks";
import {
  RailHostContext,
  type RailHostRegistry,
  type RegisteredLevels,
  type PaneExitGuard,
} from "@agentic-toolkit/resource";

// Only `reportUnexpectedAuthError` is stubbed — the pane's telemetry seam, which two tests below
// assert on. Spread the real module rather than replacing it: `@agenticdevelopertoolkit/ui`'s
// create-resource-dialog (the pane's "New role" modal) imports from here too, and a bare factory
// would silently strip whatever it needs.
vi.mock("@agentic-toolkit/auth", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@agentic-toolkit/auth")>()),
  reportUnexpectedAuthError: vi.fn(),
}));

vi.mock("@agentic-toolkit/data/access", () => ({
  ACCESS_FEATURES: [
    { key: "projects", label: "Projects" },
    { key: "personas", label: "Personas" },
  ],
  accessApi: {
    listFeatures: vi.fn(),
    listRoles: vi.fn(),
    createRole: vi.fn(),
    updateRole: vi.fn(),
    deleteRole: vi.fn(),
  },
}));

import {
  TeamPermissionsPane,
  parseVerbs,
  formatVerbs,
} from "./TeamPermissionsPane";
import { accessApi, type AccessRoleRow } from "@agentic-toolkit/data/access";
import { reportUnexpectedAuthError } from "@agentic-toolkit/auth";

const reported = vi.mocked(reportUnexpectedAuthError);
const listFeatures = vi.mocked(accessApi.listFeatures);
const listRoles = vi.mocked(accessApi.listRoles);
const updateRole = vi.mocked(accessApi.updateRole);

/** Build a role fixture with sensible defaults (custom, non-default). */
function role(
  over: Partial<AccessRoleRow> & { id: string; slug: string; name: string },
): AccessRoleRow {
  return { description: "", isSystem: false, defaultFor: "", grants: [], ...over } as AccessRoleRow;
}

const REVIEWER = role({
  id: "r1",
  slug: "reviewer",
  name: "Reviewer",
  grants: [
    { feature: "projects", itemVerbs: "R", subitemVerbs: "" },
    { feature: "personas", itemVerbs: "", subitemVerbs: "" },
  ],
});
const USER_SYS = role({
  id: "r2",
  slug: "user",
  name: "User",
  isSystem: true,
  defaultFor: "customer",
  grants: [
    { feature: "projects", itemVerbs: "R", subitemVerbs: "R" },
    { feature: "personas", itemVerbs: "R", subitemVerbs: "" },
  ],
});
const ADMIN = role({
  id: "r3",
  slug: "admin",
  name: "Admin",
  isSystem: true,
  grants: [
    { feature: "projects", itemVerbs: "C,R,U,D,M", subitemVerbs: "C,R,U,D" },
    { feature: "personas", itemVerbs: "C,R,U,D,M", subitemVerbs: "C,R,U,D" },
  ],
});
// A role holding a grant for a feature area this build does NOT render. ACCESS_FEATURES is a fixed
// list shared by every product on the toolkit, while the BACKEND's feature-area registry is
// per-deployment — so a server can (and does) return grants for areas the pane knows nothing about.
// Saving is a full replacement server-side, and an omitted feature is audited as a DELIBERATE
// revocation that the deploy-time role backfill then refuses to restore, so a grant this pane drops
// is destroyed permanently and silently. It must ride through untouched.
const WITH_UNKNOWN = role({
  id: "r4",
  slug: "editor",
  name: "Editor",
  grants: [
    { feature: "projects", itemVerbs: "R", subitemVerbs: "" },
    { feature: "personas", itemVerbs: "R", subitemVerbs: "" },
    { feature: "audiences", itemVerbs: "C,R,U,D", subitemVerbs: "C,R,U,D" },
  ],
});

// The three feature areas an adh-shaped backend reports — `audiences` is deliberately NOT in the
// mocked ACCESS_FEATURES above, so it can only ever reach the matrix via the endpoint.
const SERVER_FEATURES = [
  { key: "projects", label: "Projects" },
  { key: "personas", label: "Personas" },
  { key: "audiences", label: "Audiences" },
];

beforeEach(() => {
  vi.clearAllMocks();
  // DEFAULT: the endpoint does not exist. This pane ships in products whose backend predates it,
  // and that degraded path must stay the pane's exact pre-endpoint behavior — so every test that
  // does not opt in runs against the hardcoded ACCESS_FEATURES, not the server's list.
  listFeatures.mockRejectedValue(
    Object.assign(new Error("Not Found"), { status: 404 }),
  );
  listRoles.mockResolvedValue([]);
});

// Explicit and redundant, deliberately: this package's vitest runs with `globals: true`
// (packages/web/packages/features/vitest.preset.ts:16), so RTL 16.3.2's own shipped
// `afterEach(cleanup)` DOES register (@testing-library/react/dist/index.js:23-30), and cleanup
// is idempotent. An earlier version of this comment asserted the opposite — no global afterEach,
// auto-cleanup never registers — and both halves were false. Keep the call if you like it as a
// local statement of intent; do not "fix" the config to match the claim that was here.
afterEach(cleanup);

/** Renders the published roles level (its rows + the "New role" affordance + empty label) the way
 *  the workspace shell would, so the test can see and drive the shell-owned master list. */
function Rail({ levels }: { levels: TopicLevel[] }) {
  const level = levels[0];
  const rows = levels.flatMap((l) => l.items);
  return (
    <div>
      {level?.onNew && level.newLabel && (
        <button type="button" onClick={() => level.onNew?.()}>
          {level.newLabel}
        </button>
      )}
      {rows.length === 0 && level?.emptyLabel && <p>{level.emptyLabel}</p>}
      <ul>
        {rows.map((it) => (
          <li key={it.id}>
            <button type="button" onClick={() => level?.onSelect(it.id)}>
              {it.label}
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}

/** A minimal rail HOST: registers pane-published levels/guards the way the hub's shell does, so the
 *  published master list is drivable. toolbarSlot is null — this stub's choice, not production's,
 *  where `StandaloneRailHost` publishes a real node — so the pane's ButtonBar renders inline and
 *  the queries below can find its buttons without a portal target to mount. */
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
          if (!m.has(id)) return m;
          const next = new Map(m);
          next.delete(id);
          return next;
        }),
      registerExitGuard: (_id: string, _guard: PaneExitGuard | null) => {},
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

// `workspaceSlug` defaults to "acme" when omitted; pass `null` to drive the no-workspace path
// (a plain `undefined` would trip the default-parameter value instead).
function TestHarness({ workspaceSlug = "acme" }: { workspaceSlug?: string | null }) {
  const [leafId, setLeafId] = useState<string | null>(null);
  return (
    <Harness>
      <TeamPermissionsPane
        workspaceSlug={workspaceSlug ?? undefined}
        leaf={{ leafId, onSelect: setLeafId }}
      />
    </Harness>
  );
}

/** A feature area's caption in the grants matrix. Scoped to the `<span>` because the "default for"
 *  <select> carries an <option>Personas</option> that an unscoped getByText would also match. */
const featureLabel = (label: string): HTMLElement =>
  screen.getByText(label, { selector: "span" });

/** The bordered block for one feature area (its label plus both verb lines). */
const featureRow = (label: string): HTMLElement =>
  featureLabel(label).closest("div") as HTMLElement;

/** The "Items" verb line inside a feature row ("Sub-items" is the sibling line). */
const itemVerbs = (label: string): HTMLElement =>
  within(featureRow(label)).getByText("Items").closest("div") as HTMLElement;

/** The "Sub-items" verb line inside a feature row. */
const subitemVerbs = (label: string): HTMLElement =>
  within(featureRow(label)).getByText("Sub-items").closest("div") as HTMLElement;

describe("TeamPermissionsPane", () => {
  it("renders the workspace roles and badges the system ones", async () => {
    listRoles.mockResolvedValue([structuredClone(REVIEWER), structuredClone(USER_SYS)]);
    render(<TestHarness />);

    // Both roles appear as master rows; the custom one carries no System badge until selected.
    await screen.findByRole("button", { name: "Reviewer" });
    expect(screen.getByRole("button", { name: "User" })).not.toBeNull();

    // Selecting the system role surfaces its "System" badge in the detail header.
    fireEvent.click(screen.getByRole("button", { name: "User" }));
    expect(await screen.findByText("System")).not.toBeNull();

    // The custom role has no System badge.
    fireEvent.click(screen.getByRole("button", { name: "Reviewer" }));
    await screen.findByDisplayValue("Reviewer"); // detail re-hydrated to the custom role
    expect(screen.queryByText("System")).toBeNull();
  });

  it("renders the admin role fully disabled with the immutable note and no save/delete", async () => {
    listRoles.mockResolvedValue([structuredClone(ADMIN)]);
    render(<TestHarness />);

    fireEvent.click(await screen.findByRole("button", { name: "Admin" }));

    // The note is shown, the identity fields are disabled, and there are no editing affordances.
    expect(await screen.findByText("The admin role is immutable.")).not.toBeNull();
    const nameInput = screen.getByDisplayValue("Admin") as HTMLInputElement;
    expect(nameInput.disabled).toBe(true);
    expect(screen.queryByRole("button", { name: "Save" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Delete" })).toBeNull();
  });

  it("toggling the M verb and saving PATCHes the role with the canonical verb string", async () => {
    listRoles.mockResolvedValue([structuredClone(REVIEWER)]);
    updateRole.mockResolvedValue(structuredClone(REVIEWER));
    render(<TestHarness />);

    fireEvent.click(await screen.findByRole("button", { name: "Reviewer" }));
    await screen.findByDisplayValue("Reviewer");

    // Scope to the Projects feature row (both features render an M chip) and add M to its item verbs.
    const projectsRow = screen.getByText("Projects").closest("div") as HTMLElement;
    fireEvent.click(within(projectsRow).getByRole("button", { name: "M" }));

    // Save is enabled once the draft is dirty; it drives updateRole via the shared button bar.
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => expect(updateRole).toHaveBeenCalledTimes(1));
    // R + M resolve to canonical 'R,M' (M is always last), and personas stays untouched.
    expect(updateRole).toHaveBeenCalledWith(
      "acme",
      "r1",
      expect.objectContaining({
        grants: expect.arrayContaining([
          expect.objectContaining({ feature: "projects", itemVerbs: "R,M", subitemVerbs: "" }),
          expect.objectContaining({ feature: "personas", itemVerbs: "", subitemVerbs: "" }),
        ]),
      }),
    );
  });

  it("renders a row for a backend-reported area absent from ACCESS_FEATURES, and round-trips it", async () => {
    // The server enforces three areas; the hardcoded ACCESS_FEATURES mocked above holds two. The
    // third can therefore only reach the matrix through GET /access/features — which is the whole
    // point: without it, `audiences` is an area an admin can neither grant NOR withhold on a
    // custom role, while the seeded system roles confer it anyway.
    listFeatures.mockResolvedValue(structuredClone(SERVER_FEATURES));
    listRoles.mockResolvedValue([structuredClone(REVIEWER)]);
    updateRole.mockResolvedValue(structuredClone(REVIEWER));
    render(<TestHarness />);

    fireEvent.click(await screen.findByRole("button", { name: "Reviewer" }));
    await screen.findByDisplayValue("Reviewer");

    // The pane asked THIS deployment which areas it enforces, naming the workspace…
    expect(listFeatures).toHaveBeenCalledWith("acme");
    // …and the extra row is present, under the server's own label. `REVIEWER` carries no
    // `audiences` grant at all, so the row exists because the FEATURE list says so, not because
    // some grant happened to mention it.
    expect(REVIEWER.grants.some((g) => g.feature === "audiences")).toBe(false);
    expect(await screen.findByText("Audiences")).not.toBeNull();

    // It is a live editor, not a read-only echo: grant item R + M and sub-item R on it, then save.
    fireEvent.click(within(itemVerbs("Audiences")).getByRole("button", { name: "R" }));
    fireEvent.click(within(featureRow("Audiences")).getByRole("button", { name: "M" }));
    fireEvent.click(within(subitemVerbs("Audiences")).getByRole("button", { name: "R" }));
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => expect(updateRole).toHaveBeenCalledTimes(1));
    const grants = updateRole.mock.calls[0]![2]!.grants!;
    expect(grants).toContainEqual({ feature: "audiences", itemVerbs: "R,M", subitemVerbs: "R" });
    // A FIRST-CLASS row, not a carried passenger: exactly the three server areas go out, once
    // each — a duplicated `audiences` would mean the rendered row and `carried` both emitted it.
    expect([...grants].map((g) => g.feature)).toEqual(["projects", "personas", "audiences"]);
    // The untouched rendered rows still ride along at their stored verbs (the PATCH replaces all).
    expect(grants).toContainEqual({ feature: "projects", itemVerbs: "R", subitemVerbs: "" });
  });

  it("falls back to ACCESS_FEATURES when the feature endpoint is unavailable, still carrying unrendered grants", async () => {
    // The degraded path, and the reason `carried` must survive this change: on a backend that
    // predates /access/features the matrix is the hardcoded two rows again, so `audiences` is
    // unrendered — and a save is a full replacement whose omissions are audited as DELIBERATE
    // revocations the deploy-time backfill refuses to restore.
    listFeatures.mockRejectedValue(Object.assign(new Error("Not Found"), { status: 404 }));
    listRoles.mockResolvedValue([structuredClone(WITH_UNKNOWN)]);
    updateRole.mockResolvedValue(structuredClone(WITH_UNKNOWN));
    render(<TestHarness />);

    fireEvent.click(await screen.findByRole("button", { name: "Editor" }));
    await screen.findByDisplayValue("Editor");

    // PRECONDITION: the fixture really does hold the grant we are about to call "preserved" —
    // otherwise the assertion below would be satisfied by a role that never had it.
    expect(WITH_UNKNOWN.grants).toContainEqual({
      feature: "audiences",
      itemVerbs: "C,R,U,D",
      subitemVerbs: "C,R,U,D",
    });
    expect(listFeatures).toHaveBeenCalledWith("acme");
    // A failed fetch degrades to the hardcoded list — NOT to an empty matrix, and not to a crash.
    expect(featureLabel("Projects")).not.toBeNull();
    expect(featureLabel("Personas")).not.toBeNull();
    // The unknown area is NOT rendered — this pane edits exactly what it was told exists.
    expect(screen.queryByText("audiences")).toBeNull();
    expect(screen.queryByText("Audiences")).toBeNull();

    // Edit an unrelated (rendered) feature, then save.
    fireEvent.click(within(featureRow("Projects")).getByRole("button", { name: "M" }));
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => expect(updateRole).toHaveBeenCalledTimes(1));
    const grants = updateRole.mock.calls[0]![2]!.grants!;
    // The edit landed, AND the invisible grant went back out VERBATIM.
    expect(grants).toContainEqual({ feature: "projects", itemVerbs: "R,M", subitemVerbs: "" });
    expect(grants).toContainEqual({
      feature: "audiences",
      itemVerbs: "C,R,U,D",
      subitemVerbs: "C,R,U,D",
    });
    expect([...grants].map((g) => g.feature).sort()).toEqual([
      "audiences",
      "personas",
      "projects",
    ]);
  });

  it("treats an EMPTY feature list as unreadable: falls back, AND reports and surfaces it", async () => {
    // A server that answers `{ features: [] }` is answering nonsense — no deployment enforces
    // nothing. Believing it would render zero rows and sweep EVERY grant into `carried`, so the
    // roles editor would silently become read-only. Fall back on the MATRIX exactly as a 404 does…
    listFeatures.mockResolvedValue([]);
    listRoles.mockResolvedValue([structuredClone(REVIEWER)]);
    render(<TestHarness />);

    fireEvent.click(await screen.findByRole("button", { name: "Reviewer" }));
    await screen.findByDisplayValue("Reviewer");

    expect(featureLabel("Projects")).not.toBeNull();
    expect(featureLabel("Personas")).not.toBeNull();

    // …but NOT on the reporting: a 404 is an old backend (expected, silent), while an empty 200 is
    // a live backend answering nonsense. `listFeatures` resolves that shape instead of throwing, so
    // if this pane also stayed quiet it would be the ONE unreadable answer nobody ever hears about
    // — an admin editing a two-row matrix on a three-area deployment, permanently.
    expect(await screen.findByRole("alert")).toHaveTextContent("came back empty");
    expect(reported).toHaveBeenCalledTimes(1);
    const [err, ctx] = reported.mock.calls[0]!;
    expect((err as Error).message).toContain("empty list");
    expect(ctx).toMatchObject({ feature: "team-permissions", step: "loadFeatures" });
  });

  it("surfaces a genuine (non-404) feature-list failure while still degrading to the fallback", async () => {
    // Unlike a 404 (a product whose backend predates the endpoint — the expected, silent degrade
    // path exercised above), a 500 or a network failure is unexpected: the admin should see SOME
    // sign something went wrong, not a matrix that quietly looks like an old backend.
    listFeatures.mockRejectedValue(
      Object.assign(new Error("Feature service unavailable"), { status: 500 }),
    );
    listRoles.mockResolvedValue([structuredClone(REVIEWER)]);
    render(<TestHarness />);

    fireEvent.click(await screen.findByRole("button", { name: "Reviewer" }));
    await screen.findByDisplayValue("Reviewer");

    // The matrix still works — a genuine failure degrades exactly like a 404 would.
    expect(featureLabel("Projects")).not.toBeNull();
    expect(featureLabel("Personas")).not.toBeNull();
    // …but the failure itself is surfaced, not swallowed.
    expect(await screen.findByRole("alert")).toHaveTextContent("Feature service unavailable");
  });

  it("does not cache a genuine failure, so the next refresh retries the fetch", async () => {
    // The very first attempt fails for a real reason (not a 404); the second — driven by the
    // post-save refresh() — succeeds. If the failed attempt had been cached (the bug), the pane
    // would stay pinned to the two-row fallback for its entire lifetime and `listFeatures` would
    // never be called again.
    listFeatures
      .mockRejectedValueOnce(Object.assign(new Error("boom"), { status: 500 }))
      .mockResolvedValueOnce(structuredClone(SERVER_FEATURES));
    listRoles.mockResolvedValue([structuredClone(REVIEWER)]);
    updateRole.mockResolvedValue(structuredClone(REVIEWER));
    render(<TestHarness />);

    fireEvent.click(await screen.findByRole("button", { name: "Reviewer" }));
    await screen.findByDisplayValue("Reviewer");
    expect(screen.queryByText("Audiences")).toBeNull();

    // An unrelated edit + save triggers the pane's post-save refresh(), which re-invokes
    // loadFeatures for the same workspace slug.
    fireEvent.click(within(featureRow("Projects")).getByRole("button", { name: "M" }));
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await waitFor(() => expect(updateRole).toHaveBeenCalledTimes(1));
    await waitFor(() => expect(listFeatures).toHaveBeenCalledTimes(2));

    // Re-select to rehydrate the draft against the now-resolved list: proves the retried fetch's
    // result is live, not still pinned to the fallback cached from the first, failed attempt.
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    fireEvent.click(screen.getByRole("button", { name: "Reviewer" }));
    await screen.findByDisplayValue("Reviewer");
    expect(await screen.findByText("Audiences")).not.toBeNull();
  });

  it("never paints a STALE feature-list failure over a workspace that already loaded", async () => {
    // `loadFeatures` swallows its own errors (it returns the fallback), so `refresh`'s
    // `g !== gen.current` guards can never see them — the banner it paints has to check the
    // generation ITSELF. Without that check, a slow failure for workspace A landing after B has
    // loaded stamps A's error over B's correct matrix, and nothing clears `loadError` again until
    // the next refresh() — so the admin reads a permanent error about a workspace they left.
    let failAcme: (e: unknown) => void = () => {};
    listFeatures
      .mockImplementationOnce(
        () =>
          new Promise((_resolve, reject) => {
            failAcme = reject;
          }),
      )
      .mockResolvedValueOnce(structuredClone(SERVER_FEATURES));
    listRoles.mockResolvedValue([structuredClone(REVIEWER)]);

    const { rerender } = render(<TestHarness workspaceSlug="acme" />);
    await waitFor(() => expect(listFeatures).toHaveBeenCalledWith("acme"));

    // Switch workspaces while acme's feature fetch is still in flight. Same component instance, so
    // the generation ref survives — which is the whole mechanism under test.
    rerender(<TestHarness workspaceSlug="beta" />);
    await waitFor(() => expect(listFeatures).toHaveBeenCalledWith("beta"));
    fireEvent.click(await screen.findByRole("button", { name: "Reviewer" }));
    await screen.findByDisplayValue("Reviewer");
    // beta painted its OWN three-area list, so we can tell its matrix from the fallback.
    expect(await screen.findByText("Audiences")).not.toBeNull();

    // NOW acme fails, long after beta is on screen.
    failAcme(Object.assign(new Error("acme is on fire"), { status: 500 }));
    // The report is deliberately NOT generation-gated: an error that happened, happened.
    await waitFor(() => expect(reported).toHaveBeenCalledTimes(1));
    expect((reported.mock.calls[0]![0] as Error).message).toBe("acme is on fire");

    // The BANNER is: beta is fine, and says so.
    expect(screen.queryByRole("alert")).toBeNull();
    expect(screen.queryByText("acme is on fire")).toBeNull();
    // And beta's matrix is untouched — not degraded to the two-row fallback acme returned.
    expect(screen.getByText("Audiences")).not.toBeNull();
  });

  it("stays pristine on a role with a carried grant (Save disabled, nothing submitted)", async () => {
    // The dirty check walks the RENDERED rows index-aligned; carried rows must not tip a
    // never-touched form into dirty (which would offer Save on a form the user never edited).
    listRoles.mockResolvedValue([structuredClone(WITH_UNKNOWN)]);
    render(<TestHarness />);

    fireEvent.click(await screen.findByRole("button", { name: "Editor" }));
    await screen.findByDisplayValue("Editor");

    const save = screen.getByRole("button", { name: "Save" }) as HTMLButtonElement;
    expect(save.disabled).toBe(true);
    fireEvent.click(save);
    await waitFor(() => expect(updateRole).not.toHaveBeenCalled());

    // …and a real edit still registers (the carried row does not MASK a genuine change).
    const projectsRow = screen.getByText("Projects").closest("div") as HTMLElement;
    fireEvent.click(within(projectsRow).getByRole("button", { name: "M" }));
    await waitFor(() =>
      expect((screen.getByRole("button", { name: "Save" }) as HTMLButtonElement).disabled).toBe(
        false,
      ),
    );
  });

  it("shows the defined empty state (never a spinner) with no workspaceSlug", async () => {
    render(<TestHarness workspaceSlug={null} />);

    // The pane resolves to a DEFINED empty message rather than an eternal "Loading…"; it never
    // calls the roles API without a workspace.
    const hits = await screen.findAllByText("Open Teams from your hub workspace to manage roles.");
    expect(hits.length).toBeGreaterThan(0);
    expect(screen.queryByText("Loading…")).toBeNull();
    expect(listRoles).not.toHaveBeenCalled();
  });
});

describe("parseVerbs / formatVerbs", () => {
  it("parses an empty string to no verbs", () => {
    expect(parseVerbs("")).toEqual({
      crud: { create: false, read: false, update: false, delete: false },
      manage: false,
    });
  });

  it("parses a mixed-case string and drops unknown letters", () => {
    // lowercase accepted, 'x'/'z' are garbage and dropped, M sets manage.
    expect(parseVerbs("c,r,x,z,M")).toEqual({
      crud: { create: true, read: true, update: false, delete: false },
      manage: true,
    });
  });

  it("parses the full set", () => {
    expect(parseVerbs("C,R,U,D,M")).toEqual({
      crud: { create: true, read: true, update: true, delete: true },
      manage: true,
    });
  });

  it("formats in canonical C,R,U,D,M order regardless of enabled subset", () => {
    expect(formatVerbs({ create: false, read: true, update: false, delete: false }, true)).toBe(
      "R,M",
    );
    expect(formatVerbs({ create: true, read: true, update: true, delete: true }, true)).toBe(
      "C,R,U,D,M",
    );
    expect(formatVerbs({ create: false, read: false, update: false, delete: false }, false)).toBe(
      "",
    );
  });

  it("round-trips a reordered string to canonical order", () => {
    const { crud, manage } = parseVerbs("M,R");
    expect(formatVerbs(crud, manage)).toBe("R,M");
  });

  it("drops M from a sub-item format (CRUD-only)", () => {
    const { crud } = parseVerbs("R,M");
    expect(formatVerbs(crud, false)).toBe("R");
  });
});
