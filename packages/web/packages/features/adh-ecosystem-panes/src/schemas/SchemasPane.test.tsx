// @vitest-environment jsdom
import { useMemo, useState } from "react";
import type { ReactNode } from "react";
import { act, cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { TopicLevel } from "@agenticdevelopertoolkit/ui/blocks";

// The bucket layout (Mike, 2026-09-24): the buckets list, then the open bucket's own rail — its
// tables, with a gear opening the bucket's Settings in a dialog and the "+" adding a table — and a
// table's detail is `name: sql-table` over that table's data rows.

const { push } = vi.hoisted(() => ({ push: vi.fn() }));
vi.mock("next/navigation", () => ({ useRouter: () => ({ push }), usePathname: () => "/" }));

const { schemasApi } = vi.hoisted(() => ({
  schemasApi: { list: vi.fn(), update: vi.fn(), delete: vi.fn(), create: vi.fn() },
}));
vi.mock("@agentic-toolkit/data/markdown", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@agentic-toolkit/data/markdown")>()),
  schemasApi,
}));
// Reports what the table view was handed — the bucket decides the filter and the new-row defaults.
// Its "stage a row" button stands in for an unsaved row: the view registers a dirty guard.
vi.mock("@agentic-toolkit/crud", async () => ({
  CRUD_TABLES: { "content/contacts": { key: "content/contacts" } },
  useExitGuardChannel: (await import("../../../../crud/src/useExitGuardChannel")).useExitGuardChannel,
  CrudDataView: ({
    meta,
    filter,
    createDefaults,
    onGuardChange,
  }: {
    meta: { key: string };
    filter?: Record<string, string>;
    createDefaults?: Record<string, string>;
    onGuardChange?: (g: { isDirty: () => boolean } | null) => void;
  }) => (
    <div>
      <div data-testid="rows">{`${meta.key} ${JSON.stringify(filter)} ${JSON.stringify(createDefaults)}`}</div>
      <button type="button" onClick={() => onGuardChange?.({ isDirty: () => true })}>
        stage a row
      </button>
    </div>
  ),
}));
vi.mock("@agentic-toolkit/api-explorer", () => ({ RecordApiButton: () => null }));

import { RailHostContext } from "@agentic-toolkit/resource";
import type { RailHostRegistry, RegisteredLevels } from "@agentic-toolkit/resource";
import { SchemasPane } from "./SchemasPane";

const STAMPS = { createdAt: "2026-01-01T00:00:00Z", updatedAt: "2026-01-01T00:00:00Z" };
const BUCKET = {
  id: "storage.acme.crm",
  name: "Customer CRM",
  slug: "crm",
  description: "Customer data",
  ecosystemId: "eco-uuid",
  kind: "custom",
  tables: [{ id: "t-1", name: "people", type: "content.contacts" }],
  ...STAMPS,
};

/** A minimal host: keeps the published levels and draws each as a list of buttons. */
function Host({ children }: { children: ReactNode }) {
  const [entries, setEntries] = useState<Map<string, RegisteredLevels>>(new Map());
  const registry = useMemo<RailHostRegistry>(
    () => ({
      registerLevels: (id, entry) => setEntries((m) => new Map(m).set(id, entry)),
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
  const levels: TopicLevel[] = [...entries.values()]
    .sort((a, b) => a.depth - b.depth)
    .flatMap((e) => e.levels);
  return (
    <RailHostContext.Provider value={registry}>
      {levels.map((level) => (
        <nav key={level.id} aria-label={level.id}>
          <span>{level.title}</span>
          {level.titleActions}
          {level.onNew && (
            <button type="button" onClick={level.onNew}>
              {level.newLabel}
            </button>
          )}
          {level.items.map((item) => (
            <div key={item.id}>
              <button
                type="button"
                aria-pressed={level.selectedId === item.id}
                onClick={() => level.onSelect(item.id)}
              >
                {item.label}
              </button>
              {item.dividerAfter && <hr aria-label={item.dividerLabel} />}
            </div>
          ))}
        </nav>
      ))}
      {children}
    </RailHostContext.Provider>
  );
}

function renderPane() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <Host>
        <SchemasPane ecosystemId="ecosystem.acme" />
      </Host>
    </QueryClientProvider>,
  );
}

const rail = (id: string) => screen.getByRole("navigation", { name: id });

async function openBucket() {
  renderPane();
  fireEvent.click(await within(rail("buckets-list")).findByRole("button", { name: "Customer CRM" }));
  return rail("bucket-contents");
}

async function openSettings() {
  const contents = await openBucket();
  fireEvent.click(within(contents).getByRole("button", { name: "Bucket settings" }));
  return screen.findByRole("dialog");
}

beforeEach(() => {
  schemasApi.list.mockResolvedValue([BUCKET]);
  // A slug edit moves the rdid, as the backend's rename cascade does.
  schemasApi.update.mockImplementation((_id: string, patch: Partial<typeof BUCKET>) =>
    Promise.resolve({ ...BUCKET, ...patch, id: `storage.acme.${patch.slug ?? BUCKET.slug}` }),
  );
});

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

describe("SchemasPane — the bucket layout", () => {
  it("opens a bucket onto its tables alone, the first one showing", async () => {
    const contents = await openBucket();
    const rows = within(contents).getAllByRole("button").map((b) => b.getAttribute("aria-label") ?? b.textContent);
    expect(rows).toEqual(["Bucket settings", "Add table", "people"]);
    expect(within(contents).queryByRole("separator")).toBeNull();
    expect(within(contents).getByRole("button", { name: "people" })).toHaveAttribute(
      "aria-pressed",
      "true",
    );
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("the gear opens Settings in a dialog: name, description, and the danger zone", async () => {
    const dialog = await openSettings();
    expect(within(dialog).getByDisplayValue("Customer CRM")).toBeInTheDocument();
    expect(within(dialog).getByDisplayValue("Customer data")).toBeInTheDocument();
    fireEvent.click(within(dialog).getByRole("button", { name: /Danger Zone/ }));
    expect(within(dialog).getByRole("button", { name: /^Delete Bucket$/ })).toBeInTheDocument();
  });

  it("the built-in default bucket offers no Delete", async () => {
    schemasApi.list.mockResolvedValue([{ ...BUCKET, kind: "default" }]);
    const dialog = await openSettings();
    expect(within(dialog).queryByRole("button", { name: /Danger Zone/ })).toBeNull();
  });

  it("a table shows `name: sql-table` over the bucket ecosystem's rows", async () => {
    const contents = await openBucket();
    fireEvent.click(within(contents).getByRole("button", { name: "people" }));
    expect(screen.getByRole("heading")).toHaveTextContent("people: content.contacts");
    expect(screen.getByTestId("rows")).toHaveTextContent(
      'content/contacts {"ecosystemId":"eco-uuid"} {"ecosystemId":"eco-uuid"}',
    );
  });

  it("saving Settings sends the name, slug and description only, never the table list", async () => {
    const dialog = await openSettings();
    fireEvent.change(within(dialog).getByDisplayValue("Customer CRM"), { target: { value: "Customers" } });
    // A saved bucket's slug does NOT follow a rename of its display name — that would move its rdid.
    expect(within(dialog).getByLabelText("Slug")).toHaveValue("crm");
    fireEvent.click(within(dialog).getByRole("button", { name: /save/i }));
    await waitFor(() => expect(schemasApi.update).toHaveBeenCalled());
    expect(schemasApi.update).toHaveBeenCalledWith(BUCKET.id, {
      name: "Customers",
      slug: "crm",
      description: "Customer data",
    });
  });

  // "buckets need unique slugs and rdids" (Mike, 2026-09-24).
  it("Settings shows the slug behind its storage prefix, and the rdid read-only", async () => {
    const dialog = await openSettings();
    expect(within(dialog).getByText("storage.acme.")).toBeInTheDocument();
    expect(within(dialog).getByLabelText("Slug")).toHaveValue("crm");
    expect(within(dialog).getByDisplayValue("storage.acme.crm")).toHaveAttribute("readonly");
  });

  it("a slug edit saves the slug; a bad or taken one is refused before the request", async () => {
    schemasApi.list.mockResolvedValue([
      BUCKET,
      { ...BUCKET, id: "storage.acme.leads", name: "Leads", slug: "leads" },
    ]);
    const dialog = await openSettings();
    const slug = within(dialog).getByLabelText("Slug");
    const save = () => fireEvent.click(within(dialog).getByRole("button", { name: /save/i }));

    fireEvent.change(slug, { target: { value: "leads" } });
    save();
    expect(await within(dialog).findByText('A bucket with the slug "leads" already exists.')).toBeInTheDocument();

    fireEvent.change(slug, { target: { value: "customers" } });
    save();
    await waitFor(() => expect(schemasApi.update).toHaveBeenCalled());
    expect(schemasApi.update).toHaveBeenCalledWith(BUCKET.id, expect.objectContaining({ slug: "customers" }));
  });

  it("the built-in default bucket's slug is not editable", async () => {
    schemasApi.list.mockResolvedValue([{ ...BUCKET, kind: "default" }]);
    const dialog = await openSettings();
    expect(within(dialog).getByLabelText("Slug")).toBeDisabled();
  });

  it("New bucket: the slug follows the name until it is edited, and is sent on create", async () => {
    schemasApi.create.mockResolvedValue({ ...BUCKET, id: "storage.acme.pb", name: "Profile Basics", slug: "pb" });
    renderPane();
    fireEvent.click(await within(rail("buckets-list")).findByRole("button", { name: "New bucket" }));
    const dialog = await screen.findByRole("dialog");
    expect(within(dialog).getByText("storage.acme.")).toBeInTheDocument();
    const name = within(dialog).getByPlaceholderText("Profile Basics");
    const slug = within(dialog).getByLabelText("Slug");

    fireEvent.change(name, { target: { value: "Profile Basics" } });
    expect(slug).toHaveValue("profile-basics");
    fireEvent.change(slug, { target: { value: "pb" } });
    fireEvent.change(name, { target: { value: "Profile Basics 2" } });
    expect(slug).toHaveValue("pb");

    await act(async () => {
      fireEvent.click(within(dialog).getByRole("button", { name: /create|save/i }));
    });
    await waitFor(() => expect(schemasApi.create).toHaveBeenCalled());
    expect(schemasApi.create.mock.calls[0]![0]).toMatchObject({ name: "Profile Basics 2", slug: "pb" });
  });

  // "navigating away with an unsaved bucket didn't stop me with a warning" (Mike, 2026-09-24).
  it("closing Settings over an edit asks first; Stay keeps it, Discard restores the saved name", async () => {
    const dialog = await openSettings();
    fireEvent.change(within(dialog).getByDisplayValue("Customer CRM"), { target: { value: "Customers" } });
    fireEvent.keyDown(dialog, { key: "Escape" });
    fireEvent.click(await screen.findByRole("button", { name: "Stay" }));
    expect(within(screen.getByRole("dialog")).getByDisplayValue("Customers")).toBeInTheDocument();

    fireEvent.keyDown(screen.getByRole("dialog"), { key: "Escape" });
    fireEvent.click(await screen.findByRole("button", { name: "Discard" }));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    fireEvent.click(within(rail("bucket-contents")).getByRole("button", { name: "Bucket settings" }));
    expect(within(await screen.findByRole("dialog")).getByDisplayValue("Customer CRM")).toBeInTheDocument();
    expect(schemasApi.update).not.toHaveBeenCalled();
  });

  it("switching tables over an unsaved row asks first", async () => {
    schemasApi.list.mockResolvedValue([
      { ...BUCKET, tables: [...BUCKET.tables, { id: "t-2", name: "leads", type: "content.contacts" }] },
    ]);
    const contents = await openBucket();
    fireEvent.click(screen.getByRole("button", { name: "stage a row" }));
    fireEvent.click(within(contents).getByRole("button", { name: "leads" }));
    fireEvent.click(await screen.findByRole("button", { name: "Stay" }));
    expect(screen.getByRole("heading")).toHaveTextContent("people: content.contacts");

    fireEvent.click(within(rail("bucket-contents")).getByRole("button", { name: "leads" }));
    fireEvent.click(await screen.findByRole("button", { name: "Discard" }));
    await waitFor(() => expect(screen.getByRole("heading")).toHaveTextContent("leads: content.contacts"));
  });

  it("the rail's + adds a table: type picks the name, and the save appends it", async () => {
    const contents = await openBucket();
    fireEvent.click(within(contents).getByRole("button", { name: "Add table" }));
    const dialog = await screen.findByRole("dialog");
    fireEvent.change(within(dialog).getByLabelText("Type (sql-table)"), {
      target: { value: "content.contacts" },
    });
    expect(within(dialog).getByPlaceholderText("contacts")).toHaveValue("contacts");
    await act(async () => {
      fireEvent.click(within(dialog).getByRole("button", { name: /add table|create|save/i }));
    });
    await waitFor(() => expect(schemasApi.update).toHaveBeenCalled());
    const [id, patch] = schemasApi.update.mock.calls[0]!;
    expect(id).toBe(BUCKET.id);
    expect(patch.tables.map((t: { name: string; type: string }) => [t.name, t.type])).toEqual([
      ["people", "content.contacts"],
      ["contacts", "content.contacts"],
    ]);
  });
});
