// @vitest-environment jsdom
import { act, cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// The rows of a markdown-backed bucket table: each type lists through its own shelf's client, into
// the same `CrudTable` grid as every other bucket table, and a row opens in an editor dialog.

const { markdownApi } = vi.hoisted(() => ({
  markdownApi: { list: vi.fn(), get: vi.fn(), create: vi.fn(), update: vi.fn(), remove: vi.fn() },
}));
// Mocked at its SOURCE module, which the notes and docs shelf clients import it from — a mock of
// the barrel alone would leave those two reading the real one.
vi.mock("../../../../data/src/markdown/markdown", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../../../../data/src/markdown/markdown")>()),
  markdownApi,
}));

type Row = { id: string; title: string };
// The grid: its rows' titles, and the New / Edit / Delete a user would click.
vi.mock("@agentic-toolkit/crud", () => ({
  CrudTable: ({
    rows,
    canWrite,
    onNew,
    onEdit,
    onDelete,
  }: {
    rows: Row[];
    canWrite: boolean;
    onNew: () => void;
    onEdit: (row: Row) => void;
    onDelete: (row: Row) => void;
  }) => (
    <div>
      <span data-testid="row-titles">{rows.map((r) => r.title).join(", ")}</span>
      {canWrite && (
        <button type="button" onClick={onNew}>
          New
        </button>
      )}
      {rows.map((r) => (
        <span key={r.id}>
          <button type="button" onClick={() => onEdit(r)}>{`Edit ${r.title}`}</button>
          <button type="button" onClick={() => onDelete(r)}>{`Delete ${r.title}`}</button>
        </span>
      ))}
    </div>
  ),
}));

import { MarkdownRowsView } from "./MarkdownRowsView";

const doc = (id: string, title: string, visibility = "private") => ({
  id,
  title,
  tags: [],
  visibility,
});
const show = (type: string, ecosystemId = "eco-1") =>
  render(<MarkdownRowsView type={type} workspace="acme" ecosystemId={ecosystemId} />);
const SCOPE = { workspace: "acme", ecosystemId: "eco-1" };

beforeEach(() => {
  markdownApi.list.mockResolvedValue([]);
  markdownApi.get.mockResolvedValue({ content: "" });
  markdownApi.create.mockResolvedValue({});
  markdownApi.update.mockResolvedValue({});
  markdownApi.remove.mockResolvedValue(undefined);
});

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

describe("MarkdownRowsView — which rows, and whose", () => {
  it.each([
    ["content.markdown", {}],
    ["content.papers", { visibility: "public" }],
    ["content.docs", { doc: true }],
    ["content.notes", { noted: true }],
  ])("%s lists through its shelf's own client, in the bucket's ecosystem", async (type, flags) => {
    show(type);
    await waitFor(() => expect(markdownApi.list).toHaveBeenCalledWith({}, { ...SCOPE, ...flags }));
  });

  it.each([
    ["content.markdown", {}],
    ["content.docs", { doc: true }],
    ["content.notes", { note: true }],
  ])("a new %s row is filed on its own shelf", async (type, marker) => {
    show(type);
    fireEvent.click(await screen.findByRole("button", { name: "New" }));
    const dialog = await screen.findByRole("dialog", { name: "New row" });
    fireEvent.change(within(dialog).getByRole("textbox", { name: "Markdown" }), {
      target: { value: "# Hello" },
    });
    await act(async () => {
      fireEvent.click(within(dialog).getByRole("button", { name: "Save" }));
    });
    expect(markdownApi.create).toHaveBeenCalledWith(
      { content: "# Hello", ...marker },
      SCOPE,
    );
  });

  // Papers are filtered by the SERVER: picking the public ones out of the first page of every
  // document hid any paper past that page (Mike, 2026-09-25). The view draws what it is sent.
  it("papers asks for the public rows and offers no New", async () => {
    markdownApi.list.mockResolvedValue([doc("d-2", "Paper", "public")]);
    show("content.papers");
    await waitFor(() => expect(screen.getByTestId("row-titles")).toHaveTextContent("Paper"));
    expect(screen.queryByRole("button", { name: "New" })).toBeNull();
  });

  // Two buckets never share one cache entry: a product's rows are that product's.
  it("a different bucket's ecosystem is a different request", async () => {
    markdownApi.list.mockResolvedValue([doc("d-1", "Mine")]);
    const view = show("content.markdown");
    await waitFor(() => expect(screen.getByTestId("row-titles")).toHaveTextContent("Mine"));
    markdownApi.list.mockResolvedValue([doc("d-9", "Theirs")]);
    view.rerender(<MarkdownRowsView type="content.markdown" workspace="acme" ecosystemId="eco-2" />);
    await waitFor(() => expect(screen.getByTestId("row-titles")).toHaveTextContent("Theirs"));
    expect(markdownApi.list).toHaveBeenLastCalledWith({}, { workspace: "acme", ecosystemId: "eco-2" });
  });
});

describe("MarkdownRowsView — editing a row", () => {
  it("an opened row stays read-only, and unsaveable, until its content arrives", async () => {
    markdownApi.list.mockResolvedValue([doc("d-1", "Draft")]);
    let land!: (loaded: { content: string }) => void;
    markdownApi.get.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          land = resolve;
        }),
    );
    show("content.markdown");
    fireEvent.click(await screen.findByRole("button", { name: "Edit Draft" }));
    const dialog = await screen.findByRole("dialog", { name: "Edit row" });
    const box = within(dialog).getByRole("textbox", { name: "Markdown" });
    const saveButton = within(dialog).getByRole("button", { name: "Save" });
    expect(box).toHaveAttribute("readonly");
    expect(box).toHaveAttribute("placeholder", "Loading…");
    // Even with text in the box, Save waits for the stored content.
    fireEvent.change(box, { target: { value: "# Mine" } });
    expect(saveButton).toBeDisabled();

    await act(async () => land({ content: "# Draft" }));
    expect(box).not.toHaveAttribute("readonly");
    expect(box).toHaveValue("# Draft");
    expect(saveButton).toBeEnabled();
    expect(markdownApi.get).toHaveBeenCalledWith("d-1", SCOPE);
  });

  it("a row that fails to load says why, and cannot be saved over", async () => {
    markdownApi.list.mockResolvedValue([doc("d-1", "Draft")]);
    markdownApi.get.mockRejectedValueOnce(new Error("Document not found."));
    show("content.markdown");
    fireEvent.click(await screen.findByRole("button", { name: "Edit Draft" }));
    const dialog = await screen.findByRole("dialog", { name: "Edit row" });
    expect(await within(dialog).findByText("Document not found.")).toBeInTheDocument();
    const box = within(dialog).getByRole("textbox", { name: "Markdown" });
    expect(box).toHaveAttribute("readonly");
    expect(box).not.toHaveAttribute("placeholder");
    fireEvent.change(box, { target: { value: "# Mine" } });
    expect(within(dialog).getByRole("button", { name: "Save" })).toBeDisabled();
  });
});

describe("MarkdownRowsView — deleting a row", () => {
  it("a refused delete says why in its confirm; a reopened confirm starts clean", async () => {
    markdownApi.list.mockResolvedValue([doc("d-1", "Draft")]);
    markdownApi.remove.mockRejectedValueOnce(new Error("The document is locked."));
    show("content.markdown");
    fireEvent.click(await screen.findByRole("button", { name: "Delete Draft" }));
    const confirm = await screen.findByRole("dialog", { name: /Delete “Draft”\?/ });
    await act(async () => {
      fireEvent.click(within(confirm).getByRole("button", { name: "Delete" }));
    });
    expect(await within(confirm).findByRole("alert")).toHaveTextContent("The document is locked.");
    expect(markdownApi.remove).toHaveBeenCalledWith("d-1", SCOPE);

    fireEvent.click(within(confirm).getByRole("button", { name: "Cancel" }));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    fireEvent.click(screen.getByRole("button", { name: "Delete Draft" }));
    const reopened = await screen.findByRole("dialog", { name: /Delete “Draft”\?/ });
    expect(within(reopened).queryByRole("alert")).toBeNull();
    expect(markdownApi.remove).toHaveBeenCalledTimes(1);
  });

  // Without a Cancel label the confirm was a one-button alert, whose ✕ ran the delete.
  it("closing the delete confirm with ✕ deletes nothing", async () => {
    markdownApi.list.mockResolvedValue([doc("d-1", "Draft")]);
    show("content.markdown");
    fireEvent.click(await screen.findByRole("button", { name: "Delete Draft" }));
    const confirm = await screen.findByRole("dialog", { name: /Delete “Draft”\?/ });
    fireEvent.click(within(confirm).getByRole("button", { name: "Close" }));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(markdownApi.remove).not.toHaveBeenCalled();
  });
});
