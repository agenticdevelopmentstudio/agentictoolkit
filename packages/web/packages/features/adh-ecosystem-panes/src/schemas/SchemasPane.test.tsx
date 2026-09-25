// @vitest-environment jsdom
import { useMemo, useState } from "react";
import type { ReactNode } from "react";
import { act, cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { TopicLevel } from "@agenticdevelopertoolkit/ui/blocks";
import { UnsavedChangesAlert } from "@agenticdevelopertoolkit/ui/components/unsaved-changes-alert";
import { useExitGate } from "@agenticdevelopertoolkit/ui/hooks/useExitGate";

// The bucket layout (Mike, 2026-09-24): the buckets list, then the open bucket's own rail — its
// tables, with a gear opening the bucket's Settings in a dialog and the "+" adding a table — and a
// table's detail is `name: sql-table` over that table's data rows.

const { push } = vi.hoisted(() => ({ push: vi.fn() }));
vi.mock("next/navigation", () => ({ useRouter: () => ({ push }), usePathname: () => "/" }));

const { schemasApi, markdownApi } = vi.hoisted(() => ({
  schemasApi: { list: vi.fn(), update: vi.fn(), delete: vi.fn(), create: vi.fn() },
  markdownApi: { list: vi.fn(), get: vi.fn(), create: vi.fn(), update: vi.fn(), remove: vi.fn() },
}));
vi.mock("@agentic-toolkit/data/markdown", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@agentic-toolkit/data/markdown")>()),
  schemasApi,
}));
// The markdown client at its SOURCE module, not only the barrel: the notes and docs shelf clients
// import it from there, so a barrel-only mock would leave a notes table reading the real one.
vi.mock("../../../../data/src/markdown/markdown", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../../../../data/src/markdown/markdown")>()),
  markdownApi,
}));
// Reports what the table view was handed — the bucket decides the scope and the new-row defaults.
// Its "stage a row" button stands in for an unsaved row: the view reports a dirty guard, and
// withdraws it when it unmounts, as the real grid does. `CrudTable` is the grid a markdown-backed
// table draws its rows in; it reports how many it was handed.
vi.mock("@agentic-toolkit/crud", async () => {
  const { useEffect, useState } = await import("react");
  const { useExitGuardChannel } = await import("../../../../crud/src/useExitGuardChannel");
  return {
    CRUD_TABLES: { "content/contacts": { key: "content/contacts" } },
    useExitGuardChannel,
    CrudDataView: function CrudDataView({
      meta,
      filter,
      scopeEcosystemId,
      createDefaults,
      onGuardChange,
    }: {
      meta: { key: string };
      filter?: Record<string, string>;
      scopeEcosystemId?: string;
      createDefaults?: Record<string, string>;
      onGuardChange?: (g: { isDirty: () => boolean } | null) => void;
    }) {
      const [staged, setStaged] = useState(false);
      useEffect(() => {
        onGuardChange?.(staged ? { isDirty: () => true } : null);
        return () => onGuardChange?.(null);
      }, [onGuardChange, staged]);
      return (
        <div>
          <div data-testid="rows">
            {`${meta.key} ${JSON.stringify(filter)} ${scopeEcosystemId} ${JSON.stringify(createDefaults)}`}
          </div>
          <button type="button" onClick={() => setStaged(true)}>
            stage a row
          </button>
        </div>
      );
    },
    CrudTable: ({ meta, rows }: { meta: { key: string }; rows: unknown[] }) => (
      <div data-testid="markdown-rows">{`${meta.key} ${rows.length}`}</div>
    ),
  };
});
vi.mock("@agentic-toolkit/api-explorer", () => ({ RecordApiButton: () => null }));

import { RailHostContext } from "@agentic-toolkit/resource";
import type { PaneExitGuard, RailHostRegistry, RegisteredLevels } from "@agentic-toolkit/resource";
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
const LEADS = { id: "t-2", name: "leads", type: "content.contacts" };

/**
 * A minimal host: keeps the published levels and draws each as a list of buttons, under a real
 * toolbar slot, as StandaloneRailHost has one. It keeps the published exit guards too, and runs a
 * click on ANOTHER row of a level that has a selection past them, behind its own Discard / Stay —
 * the sibling swap the real host's `railOnSelect` guards. Re-clicking the selected row stays a
 * plain select here.
 */
function Host({ children }: { children: ReactNode }) {
  const [entries, setEntries] = useState<Map<string, RegisteredLevels>>(new Map());
  const [guards, setGuards] = useState<ReadonlyMap<string, PaneExitGuard>>(new Map());
  const [toolbarSlot, setToolbarSlot] = useState<HTMLDivElement | null>(null);
  const handlers = useMemo<Omit<RailHostRegistry, "toolbarSlot">>(
    () => ({
      registerLevels: (id, entry) => setEntries((m) => new Map(m).set(id, entry)),
      unregisterLevels: (id) =>
        setEntries((m) => {
          const next = new Map(m);
          next.delete(id);
          return next;
        }),
      registerExitGuard: (id, guard) =>
        setGuards((m) => {
          if (guard === null && !m.has(id)) return m;
          const next = new Map(m);
          if (guard === null) next.delete(id);
          else next.set(id, guard);
          return next;
        }),
      popStack: () => {},
      reportMissing: () => {},
      reportBusy: () => {},
    }),
    [],
  );
  const registry = useMemo<RailHostRegistry>(
    () => ({ ...handlers, toolbarSlot }),
    [handlers, toolbarSlot],
  );
  const exitGuard = useMemo<PaneExitGuard | null>(
    () => (guards.size ? { isDirty: () => [...guards.values()].some((g) => g.isDirty()) } : null),
    [guards],
  );
  const gate = useExitGate(exitGuard);
  const levels: TopicLevel[] = [...entries.values()]
    .sort((a, b) => a.depth - b.depth)
    .flatMap((e) => e.levels);
  return (
    <RailHostContext.Provider value={registry}>
      <div data-testid="toolbar-slot" ref={setToolbarSlot} />
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
                onClick={() =>
                  level.selectedId != null && level.selectedId !== item.id
                    ? gate.attemptExit(() => level.onSelect(item.id))
                    : level.onSelect(item.id)
                }
              >
                {item.label}
              </button>
              {item.dividerAfter && <hr aria-label={item.dividerLabel} />}
            </div>
          ))}
        </nav>
      ))}
      <UnsavedChangesAlert {...gate.exitAlertProps} />
      {children}
    </RailHostContext.Provider>
  );
}

function renderPane(workspaceSlug?: string) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <Host>
        <SchemasPane ecosystemId="ecosystem.acme" workspaceSlug={workspaceSlug} />
      </Host>
    </QueryClientProvider>,
  );
}

const rail = (id: string) => screen.getByRole("navigation", { name: id });
const stageRow = () => fireEvent.click(screen.getByRole("button", { name: "stage a row" }));

async function openBucket(workspaceSlug?: string) {
  renderPane(workspaceSlug);
  fireEvent.click(await within(rail("buckets-list")).findByRole("button", { name: "Customer CRM" }));
  return rail("bucket-contents");
}

async function openSettings() {
  const contents = await openBucket();
  fireEvent.click(within(contents).getByRole("button", { name: "Bucket settings" }));
  return screen.findByRole("dialog");
}

/** Answer the Remove confirm with Remove. */
async function confirmRemove() {
  const confirm = await screen.findByRole("dialog", { name: /^Remove / });
  await act(async () => {
    fireEvent.click(within(confirm).getByRole("button", { name: "Remove" }));
  });
}

/** The pencil in the open `people` table's header, and the dialog it opens. */
async function editPeople() {
  fireEvent.click(screen.getByRole("button", { name: "Edit people" }));
  return screen.findByRole("dialog", { name: "Edit table" });
}

beforeEach(() => {
  schemasApi.list.mockResolvedValue([BUCKET]);
  // A slug edit moves the rdid, as the backend's rename cascade does.
  schemasApi.update.mockImplementation((_id: string, patch: Partial<typeof BUCKET>) =>
    Promise.resolve({ ...BUCKET, ...patch, id: `storage.acme.${patch.slug ?? BUCKET.slug}` }),
  );
  markdownApi.list.mockResolvedValue([]);
});

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

describe("SchemasPane — the bucket layout", () => {
  it("opens a bucket onto its tables alone, the first one showing", async () => {
    const contents = await openBucket();
    const rows = within(contents).getAllByRole("button").map((b) => b.getAttribute("aria-label") ?? b.textContent);
    expect(rows).toEqual(["Bucket settings", "Table actions", "Add table", "people"]);
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

  // Save and Cancel belong to the dialog, not to the host's toolbar strip: a host with a real slot
  // (StandaloneRailHost) drew them outside the modal, behind its backdrop.
  it("Settings keeps Save and Cancel in its dialog when the host has a toolbar slot", async () => {
    const dialog = await openSettings();
    expect(within(dialog).getByRole("button", { name: /save/i })).toBeInTheDocument();
    expect(within(dialog).getByRole("button", { name: "Cancel" })).toBeInTheDocument();
    expect(screen.getByTestId("toolbar-slot")).toBeEmptyDOMElement();
  });

  it("a built-in bucket offers no Delete", async () => {
    schemasApi.list.mockResolvedValue([{ ...BUCKET, kind: "system" }]);
    const dialog = await openSettings();
    expect(within(dialog).queryByRole("button", { name: /Danger Zone/ })).toBeNull();
  });

  it("a table shows `name: sql-table` over the bucket ecosystem's rows", async () => {
    const contents = await openBucket();
    fireEvent.click(within(contents).getByRole("button", { name: "people" }));
    expect(screen.getByRole("heading")).toHaveTextContent("people: content.contacts");
    // A verified SCOPE, not a plain filter: as a filter, a non-admin's product bucket read empty
    // and every create was refused (Mike, 2026-09-25).
    expect(screen.getByTestId("rows")).toHaveTextContent(
      'content/contacts undefined eco-uuid {"ecosystemId":"eco-uuid"}',
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

  // A new slug is a new rdid, and the open table's rows are keyed on it.
  it("a Settings save that moves the slug asks first over unsaved rows", async () => {
    const contents = await openBucket();
    stageRow();
    fireEvent.click(within(contents).getByRole("button", { name: "Bucket settings" }));
    const dialog = await screen.findByRole("dialog");
    const save = () => fireEvent.click(within(dialog).getByRole("button", { name: /save/i }));
    fireEvent.change(within(dialog).getByLabelText("Slug"), { target: { value: "customers" } });
    save();
    fireEvent.click(await screen.findByRole("button", { name: "Stay" }));
    expect(schemasApi.update).not.toHaveBeenCalled();

    save();
    fireEvent.click(await screen.findByRole("button", { name: "Discard" }));
    await waitFor(() =>
      expect(schemasApi.update).toHaveBeenCalledWith(
        BUCKET.id,
        expect.objectContaining({ slug: "customers" }),
      ),
    );
  });

  it("a Settings save that keeps the slug does not ask", async () => {
    const contents = await openBucket();
    stageRow();
    fireEvent.click(within(contents).getByRole("button", { name: "Bucket settings" }));
    const dialog = await screen.findByRole("dialog");
    fireEvent.change(within(dialog).getByDisplayValue("Customer CRM"), {
      target: { value: "Customers" },
    });
    fireEvent.click(within(dialog).getByRole("button", { name: /save/i }));
    await waitFor(() => expect(schemasApi.update).toHaveBeenCalled());
    expect(screen.queryByText("Discard unsaved changes?")).toBeNull();
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

  // The dialog's Cancel used to be the form's, which deselects the bucket — closing it out from
  // under the table the user was looking at.
  it("Cancel drops the edit and closes, leaving the bucket and its table open", async () => {
    const dialog = await openSettings();
    fireEvent.change(within(dialog).getByDisplayValue("Customer CRM"), {
      target: { value: "Customers" },
    });
    fireEvent.click(within(dialog).getByRole("button", { name: "Cancel" }));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(screen.getByRole("heading")).toHaveTextContent("people: content.contacts");

    const contents = rail("bucket-contents");
    fireEvent.click(within(contents).getByRole("button", { name: "Bucket settings" }));
    const reopened = await screen.findByRole("dialog");
    expect(within(reopened).getByDisplayValue("Customer CRM")).toBeInTheDocument();
    expect(schemasApi.update).not.toHaveBeenCalled();
  });

  it("switching tables over an unsaved row asks first", async () => {
    schemasApi.list.mockResolvedValue([{ ...BUCKET, tables: [...BUCKET.tables, LEADS] }]);
    const contents = await openBucket();
    stageRow();
    fireEvent.click(within(contents).getByRole("button", { name: "leads" }));
    fireEvent.click(await screen.findByRole("button", { name: "Stay" }));
    expect(screen.getByRole("heading")).toHaveTextContent("people: content.contacts");

    fireEvent.click(within(rail("bucket-contents")).getByRole("button", { name: "leads" }));
    fireEvent.click(await screen.findByRole("button", { name: "Discard" }));
    await waitFor(() => expect(screen.getByRole("heading")).toHaveTextContent("leads: content.contacts"));
    // ONE Discard: the host asks, and the table rail's own select does not ask again.
    expect(screen.queryByRole("button", { name: "Discard" })).toBeNull();
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

  it("opening a table just added asks first over unsaved rows", async () => {
    const contents = await openBucket();
    stageRow();
    fireEvent.click(within(contents).getByRole("button", { name: "Add table" }));
    const dialog = await screen.findByRole("dialog", { name: "Add table" });
    fireEvent.change(within(dialog).getByLabelText("Type (sql-table)"), {
      target: { value: "content.contacts" },
    });
    const added = { id: "t-9", name: "contacts", type: "content.contacts" };
    const withAdded = { ...BUCKET, tables: [...BUCKET.tables, added] };
    schemasApi.update.mockResolvedValueOnce(withAdded);
    schemasApi.list.mockResolvedValue([withAdded]);
    await act(async () => {
      fireEvent.click(within(dialog).getByRole("button", { name: "Save" }));
    });
    fireEvent.click(await screen.findByRole("button", { name: "Discard" }));
    await waitFor(() =>
      expect(screen.getByRole("heading")).toHaveTextContent("contacts: content.contacts"),
    );
  });

  it("removing the open table over unsaved rows asks first", async () => {
    await openBucket();
    stageRow();
    const trash = () =>
      fireEvent.click(screen.getByRole("button", { name: "Remove people from bucket" }));
    trash();
    fireEvent.click(await screen.findByRole("button", { name: "Stay" }));
    expect(schemasApi.update).not.toHaveBeenCalled();

    trash();
    fireEvent.click(await screen.findByRole("button", { name: "Discard" }));
    await confirmRemove();
    await waitFor(() => expect(schemasApi.update).toHaveBeenCalledWith(BUCKET.id, { tables: [] }));
  });

  // One stray click on the trash drops the table's id and every persona interest pointing at it,
  // so it asks first (Mike, 2026-09-25).
  it("removing a table is confirmed; Cancel sends nothing", async () => {
    await openBucket();
    fireEvent.click(screen.getByRole("button", { name: "Remove people from bucket" }));
    const confirm = await screen.findByRole("dialog", { name: /^Remove / });
    expect(confirm).toHaveTextContent("Remove “people” from Customer CRM?");
    fireEvent.click(within(confirm).getByRole("button", { name: "Cancel" }));
    await waitFor(() => expect(screen.queryByRole("dialog", { name: /^Remove / })).toBeNull());
    expect(schemasApi.update).not.toHaveBeenCalled();
  });

  // A removal used to be fired and forgotten: a refused one said nothing, and a second click sent
  // it again.
  it("a refused removal says why in the confirm; a retry starts clean and cannot be sent twice", async () => {
    await openBucket();
    schemasApi.update.mockRejectedValueOnce(new Error("The table is in use."));
    fireEvent.click(screen.getByRole("button", { name: "Remove people from bucket" }));
    await confirmRemove();
    const confirm = await screen.findByRole("dialog", { name: /^Remove / });
    expect(await within(confirm).findByText("The table is in use.")).toBeInTheDocument();
    // The table is still open behind the modal (which hides it from the a11y tree meanwhile).
    expect(
      screen.getByRole("heading", { hidden: true, name: "people: content.contacts" }),
    ).toBeInTheDocument();

    let settle!: (saved: typeof BUCKET) => void;
    schemasApi.update.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          settle = resolve;
        }),
    );
    await confirmRemove();
    expect(within(confirm).queryByText("The table is in use.")).toBeNull();
    expect(
      screen.getByRole("button", { hidden: true, name: "Remove people from bucket" }),
    ).toBeDisabled();
    expect(schemasApi.update).toHaveBeenCalledTimes(2);
    await act(async () => settle({ ...BUCKET, tables: [] }));
  });

  // The old tables editor's bulk verbs, back on the bucket's rail behind its table actions.
  it("Add all tables adds every type the bucket lacks, in one save, ids kept", async () => {
    await openBucket();
    fireEvent.click(screen.getByRole("button", { name: "Table actions" }));
    await act(async () => {
      fireEvent.click(await screen.findByRole("menuitem", { name: "Add all tables" }));
    });
    const [, patch] = schemasApi.update.mock.calls[0]! as [string, { tables: typeof BUCKET.tables }];
    expect(patch.tables[0]).toEqual(BUCKET.tables[0]);
    const types = patch.tables.map((t) => t.type);
    expect(types.filter((t) => t === "content.contacts")).toHaveLength(1);
    expect(types.length).toBeGreaterThan(2);
    expect(new Set(patch.tables.map((t) => t.name)).size).toBe(patch.tables.length);
  });

  it("Remove all tables is confirmed, then empties the bucket", async () => {
    schemasApi.list.mockResolvedValue([{ ...BUCKET, tables: [...BUCKET.tables, LEADS] }]);
    await openBucket();
    fireEvent.click(screen.getByRole("button", { name: "Table actions" }));
    fireEvent.click(await screen.findByRole("menuitem", { name: "Remove all tables…" }));
    const confirm = await screen.findByRole("dialog", { name: /^Remove / });
    expect(confirm).toHaveTextContent("Remove every table from Customer CRM?");
    expect(schemasApi.update).not.toHaveBeenCalled();
    await confirmRemove();
    await waitFor(() => expect(schemasApi.update).toHaveBeenCalledWith(BUCKET.id, { tables: [] }));
  });

  // Without the pencil, the only fix for a wrong name or type was remove + re-add, which mints the
  // table a new id.
  it("the pencil edits a table in place: pre-filled, and a rename keeps its id", async () => {
    await openBucket();
    const dialog = await editPeople();
    expect(within(dialog).getByLabelText("Type (sql-table)")).toHaveValue("content.contacts");
    const name = within(dialog).getByPlaceholderText("contacts");
    expect(name).toHaveValue("people");
    expect(within(dialog).getByRole("button", { name: "Save" })).toBeDisabled();

    const renamed = { id: "t-1", name: "persons", type: "content.contacts" };
    schemasApi.list.mockResolvedValue([{ ...BUCKET, tables: [renamed] }]);
    fireEvent.change(name, { target: { value: "persons" } });
    await act(async () => {
      fireEvent.click(within(dialog).getByRole("button", { name: "Save" }));
    });
    expect(schemasApi.update).toHaveBeenCalledWith(BUCKET.id, { tables: [renamed] });
    await waitFor(() =>
      expect(screen.getByRole("heading")).toHaveTextContent("persons: content.contacts"),
    );
  });

  it("a retype keeps the table's name", async () => {
    await openBucket();
    const dialog = await editPeople();
    fireEvent.change(within(dialog).getByLabelText("Type (sql-table)"), {
      target: { value: "content.locations" },
    });
    expect(within(dialog).getByPlaceholderText("contacts")).toHaveValue("people");
    await act(async () => {
      fireEvent.click(within(dialog).getByRole("button", { name: "Save" }));
    });
    expect(schemasApi.update).toHaveBeenCalledWith(BUCKET.id, {
      tables: [{ id: "t-1", name: "people", type: "content.locations" }],
    });
  });

  it("a stored type the catalogue does not list shows as itself, marked unlisted", async () => {
    schemasApi.list.mockResolvedValue([
      { ...BUCKET, tables: [{ id: "t-1", name: "people", type: "content.legacy" }] },
    ]);
    await openBucket();
    const dialog = await editPeople();
    expect(within(dialog).getByLabelText("Type (sql-table)")).toHaveValue("content.legacy");
    expect(
      within(dialog).getByRole("option", { name: "content.legacy (unlisted)" }),
    ).toBeInTheDocument();
  });

  it("an edit cannot take another table's name", async () => {
    schemasApi.list.mockResolvedValue([{ ...BUCKET, tables: [...BUCKET.tables, LEADS] }]);
    await openBucket();
    const dialog = await editPeople();
    fireEvent.change(within(dialog).getByPlaceholderText("contacts"), {
      target: { value: "leads" },
    });
    await act(async () => {
      fireEvent.click(within(dialog).getByRole("button", { name: "Save" }));
    });
    expect(
      within(dialog).getByText('A table named "leads" already exists in this bucket.'),
    ).toBeInTheDocument();
    expect(schemasApi.update).not.toHaveBeenCalled();
  });

  // A retype swaps the rows under the table, so the pencil asks on open — the dialog's Save cannot
  // wait on a second question.
  it("the pencil over unsaved rows asks first", async () => {
    await openBucket();
    stageRow();
    fireEvent.click(screen.getByRole("button", { name: "Edit people" }));
    fireEvent.click(await screen.findByRole("button", { name: "Stay" }));
    expect(screen.queryByRole("dialog", { name: "Edit table" })).toBeNull();

    fireEvent.click(screen.getByRole("button", { name: "Edit people" }));
    fireEvent.click(await screen.findByRole("button", { name: "Discard" }));
    expect(await screen.findByRole("dialog", { name: "Edit table" })).toBeInTheDocument();
  });

  // A notes table is a lens on the workspace's markdown documents, drawn in the same grid as every
  // other bucket table — listed through the notes client, which asks for the noted ones.
  it("a notes table lists the workspace's notes in the markdown grid", async () => {
    schemasApi.list.mockResolvedValue([
      { ...BUCKET, tables: [{ id: "t-3", name: "notes", type: "content.notes" }] },
    ]);
    markdownApi.list.mockResolvedValue([
      { id: "n-1", title: "Jotted", tags: [], visibility: "private" },
    ]);
    await openBucket("acme");
    expect(screen.getByRole("heading")).toHaveTextContent("notes: content.notes");
    await waitFor(() =>
      expect(screen.getByTestId("markdown-rows")).toHaveTextContent("content/markdown 1"),
    );
    // The bucket's own ecosystem's notes, not the workspace-wide set.
    expect(markdownApi.list).toHaveBeenCalledWith(
      {},
      { workspace: "acme", ecosystemId: "eco-uuid", noted: true },
    );
  });
});
