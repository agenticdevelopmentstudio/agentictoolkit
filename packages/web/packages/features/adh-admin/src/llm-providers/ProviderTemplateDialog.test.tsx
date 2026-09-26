// @vitest-environment jsdom
import { describe, it, expect, afterEach, vi } from "vitest";
import { render, screen, fireEvent, cleanup } from "@testing-library/react";
import { ProviderTemplateDialog } from "./ProviderTemplateDialog";
import type { ProviderTemplate } from "../api/llm-providers";

// ProviderTemplateDialog calls useCreateProviderTemplate()/useUpdateProviderTemplate()/
// useTemplateSyncKeys() internally — mock the API-hook module boundary so mutateAsync
// is a spy we can assert on, without a real network call or a react-query provider.
const createMutateAsync = vi.fn();
const updateMutateAsync = vi.fn();
vi.mock("../api/llm-providers", () => ({
  useCreateProviderTemplate: () => ({ mutateAsync: createMutateAsync }),
  useUpdateProviderTemplate: () => ({ mutateAsync: updateMutateAsync }),
  // No sync-key mapping loaded in either fixture below; irrelevant to canSave
  // (dirty && valid), which only the name/baseUrl fields drive here.
  useTemplateSyncKeys: () => ({ data: undefined, isSuccess: false, isError: false }),
}));

// The hub/admin vitest configs have no global afterEach; tear each render (+ its
// portalled dialog) down explicitly so it doesn't leak into the next test.
afterEach(() => {
  cleanup();
  createMutateAsync.mockReset();
  updateMutateAsync.mockReset();
});

function saveButton() {
  return screen.getByRole("button", { name: "Save" }) as HTMLButtonElement;
}

const TEMPLATE: ProviderTemplate = {
  id: "tpl_1",
  providerKind: "openai",
  name: "OpenAI",
  baseUrl: "https://api.openai.com/v1",
  documentationUrl: null,
  statusUrl: null,
  connectionSpec: null,
  availableVia: null,
  modalities: ["chat", "image"],
  createdAt: "2026-07-01T00:00:00Z",
  updatedAt: "2026-07-01T00:00:00Z",
  models: [],
};

describe("ProviderTemplateDialog (create mode) — Save is disabled at mount, enabled after a valid, dirty edit", () => {
  it("is disabled at mount (pristine)", () => {
    render(
      <ProviderTemplateDialog open template={null} onClose={vi.fn()} onDirtyChange={vi.fn()} />,
    );
    expect(saveButton().disabled).toBe(true);
  });

  it("enables once name and base URL are both filled in", () => {
    render(
      <ProviderTemplateDialog open template={null} onClose={vi.fn()} onDirtyChange={vi.fn()} />,
    );
    fireEvent.change(screen.getByPlaceholderText("e.g. OpenAI"), {
      target: { value: "My Provider" },
    });
    fireEvent.change(screen.getByPlaceholderText("https://api.openai.com/v1"), {
      target: { value: "https://api.example.com/v1" },
    });
    expect(saveButton().disabled).toBe(false);
  });

  it("stays disabled with a name but no base URL", () => {
    render(
      <ProviderTemplateDialog open template={null} onClose={vi.fn()} onDirtyChange={vi.fn()} />,
    );
    fireEvent.change(screen.getByPlaceholderText("e.g. OpenAI"), {
      target: { value: "My Provider" },
    });
    expect(saveButton().disabled).toBe(true);
  });

  // The gate disables Save, so handleSubmit's `throw new Error(...)` never reaches the user
  // through a click; a grey Save with nothing said reads as a broken button.
  it("says WHY Save is grey once a name is typed but the base URL is still missing", () => {
    render(
      <ProviderTemplateDialog open template={null} onClose={vi.fn()} onDirtyChange={vi.fn()} />,
    );
    fireEvent.change(screen.getByPlaceholderText("e.g. OpenAI"), {
      target: { value: "My Provider" },
    });
    expect(screen.getByText("A base URL is required.")).toBeTruthy();
  });

  // The other half: a pristine create form is blocked too (no name yet), so the reason really
  // is non-null at mount and only `dirty` keeps it quiet.
  it("stays silent at mount — an untouched form must not open by scolding", () => {
    render(
      <ProviderTemplateDialog open template={null} onClose={vi.fn()} onDirtyChange={vi.fn()} />,
    );
    expect(saveButton().disabled).toBe(true);
    expect(screen.queryByText("A name is required.")).toBeNull();
  });
});

describe("ProviderTemplateDialog (edit mode) — loaded, unedited form stays disabled; editing a field gates Save", () => {
  it("is disabled at mount (loaded, unedited)", () => {
    render(
      <ProviderTemplateDialog
        open
        template={TEMPLATE}
        onClose={vi.fn()}
        onDirtyChange={vi.fn()}
      />,
    );
    expect(saveButton().disabled).toBe(true);
  });

  it("enables once the name is edited", () => {
    render(
      <ProviderTemplateDialog
        open
        template={TEMPLATE}
        onClose={vi.fn()}
        onDirtyChange={vi.fn()}
      />,
    );
    fireEvent.change(screen.getByDisplayValue("OpenAI"), {
      target: { value: "OpenAI (updated)" },
    });
    expect(saveButton().disabled).toBe(false);
  });

  it("does not submit via the form's hidden default button when unedited — Enter in any text field activates THIS button, not the visible Save", () => {
    // Pressing Enter in a text input inside a <form> runs the browser's implicit-submission
    // algorithm, which activates the form's default button (the first submit button in tree
    // order) — here that's the hidden <button type="submit"> rendered inside the <form>; the
    // visible "Save" lives in DialogActions, a SIBLING of the form, so it is never the target
    // of implicit submission. Activating a disabled button is a no-op, so this only stays safe
    // if the hidden button carries the same disabled state as the visible one.
    render(
      <ProviderTemplateDialog
        open
        template={TEMPLATE}
        onClose={vi.fn()}
        onDirtyChange={vi.fn()}
      />,
    );
    // The dialog renders through a portal, so query relative to a known in-form element
    // rather than the render()'s own (unportalled) container.
    const nameField = screen.getByDisplayValue("OpenAI");
    const hiddenSubmit = nameField.closest("form")!.querySelector(
      'button[type="submit"]',
    ) as HTMLButtonElement;
    expect(hiddenSubmit).not.toBeNull();
    expect(hiddenSubmit.disabled).toBe(true);
    fireEvent.click(hiddenSubmit);
    expect(updateMutateAsync).not.toHaveBeenCalled();
  });

  it("DOES submit via the hidden default button once dirty — proves the assertion above is a real gate, not a button that's disabled for some other reason", () => {
    updateMutateAsync.mockResolvedValue(undefined);
    render(
      <ProviderTemplateDialog
        open
        template={TEMPLATE}
        onClose={vi.fn()}
        onDirtyChange={vi.fn()}
      />,
    );
    const nameField = screen.getByDisplayValue("OpenAI");
    fireEvent.change(nameField, { target: { value: "OpenAI (updated)" } });
    const hiddenSubmit = nameField.closest("form")!.querySelector(
      'button[type="submit"]',
    ) as HTMLButtonElement;
    expect(hiddenSubmit.disabled).toBe(false);
    fireEvent.click(hiddenSubmit);
    expect(updateMutateAsync).toHaveBeenCalled();
  });

  it("does not fire a SECOND write when Enter is pressed during an in-flight save", () => {
    // DialogActions swaps its whole action row for a spinner while `busy`, so mid-save the
    // hidden default button is the ONLY reachable submit path — and `useAction.run` has no
    // re-entrancy guard of its own. Without a busy term on this button, holding Enter (or a
    // double-tap) issues two PUTs for one edit.
    updateMutateAsync.mockImplementation(() => new Promise<void>(() => {})); // never settles
    render(
      <ProviderTemplateDialog
        open
        template={TEMPLATE}
        onClose={vi.fn()}
        onDirtyChange={vi.fn()}
      />,
    );
    const nameField = screen.getByDisplayValue("OpenAI");
    fireEvent.change(nameField, { target: { value: "OpenAI (updated)" } });
    const hiddenSubmit = nameField.closest("form")!.querySelector(
      'button[type="submit"]',
    ) as HTMLButtonElement;

    fireEvent.click(hiddenSubmit);
    expect(updateMutateAsync).toHaveBeenCalledTimes(1);

    expect(hiddenSubmit.disabled).toBe(true);
    fireEvent.click(hiddenSubmit);
    expect(updateMutateAsync).toHaveBeenCalledTimes(1);
  });
});

describe("ProviderTemplateDialog — Escape on a dirty draft asks before discarding", () => {
  // Dialog onOpenChange(false) is how Escape, the backdrop, and the × all reach
  // close() — firing Escape here exercises that whole path, not a bespoke one.
  it("does not close on Escape while dirty; Discard then closes", () => {
    const onClose = vi.fn();
    render(
      <ProviderTemplateDialog
        open
        template={TEMPLATE}
        onClose={onClose}
        onDirtyChange={vi.fn()}
      />,
    );
    const nameField = screen.getByDisplayValue("OpenAI");
    fireEvent.change(nameField, { target: { value: "OpenAI (updated)" } });

    fireEvent.keyDown(nameField, { key: "Escape" });
    expect(onClose).not.toHaveBeenCalled();

    // The alert is destructive and ignores Escape by design — Discard/Stay is the
    // only way out, which is exactly what this asserts by clicking through it.
    fireEvent.click(screen.getByRole("button", { name: "Discard" }));
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it("closes immediately on Escape when the form is clean — no alert", () => {
    const onClose = vi.fn();
    render(
      <ProviderTemplateDialog
        open
        template={TEMPLATE}
        onClose={onClose}
        onDirtyChange={vi.fn()}
      />,
    );
    fireEvent.keyDown(screen.getByDisplayValue("OpenAI"), { key: "Escape" });
    expect(onClose).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole("button", { name: "Discard" })).toBeNull();
  });
});
