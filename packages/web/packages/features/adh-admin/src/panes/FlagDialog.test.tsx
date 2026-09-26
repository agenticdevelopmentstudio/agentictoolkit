// @vitest-environment jsdom
import { describe, it, expect, afterEach, vi } from "vitest";
import { render, screen, fireEvent, cleanup } from "@testing-library/react";
import { FlagDialog } from "./FeatureFlagsPane";

// FlagDialog calls useCreateFlag()/useUpdateFlag() internally (not prop-injected, unlike hub's
// FlagDialog) — mock the API-hook module boundary so mutateAsync is a spy we can assert on,
// without a real network call or a react-query provider.
const createAsync = vi.fn();
const updateAsync = vi.fn();
vi.mock("../api/admin", () => ({
  useCreateFlag: () => ({ mutateAsync: createAsync }),
  useUpdateFlag: () => ({ mutateAsync: updateAsync }),
}));

// The hub/admin vitest configs have no global afterEach; tear each render (+ its portalled
// dialog) down explicitly so it doesn't leak into the next test.
afterEach(() => {
  cleanup();
  createAsync.mockReset();
  updateAsync.mockReset();
});

const BETA = { id: 1, key: "beta", description: "Beta features", enabled: true };

function saveButton() {
  return screen.getByRole("button", { name: "Save" }) as HTMLButtonElement;
}

function keyField() {
  return screen.getByPlaceholderText("e.g. dark_mode");
}

function descriptionField() {
  return screen.getByPlaceholderText("What does this flag gate? (optional)");
}

/** Render in CREATE mode (no flag). */
function create(existingKeys: string[] = []) {
  render(
    <FlagDialog
      open
      flag={null}
      existingKeys={existingKeys}
      onClose={vi.fn()}
      onDirtyChange={vi.fn()}
    />,
  );
}

/** Render in EDIT mode, pointed at `beta`. */
function edit(existingKeys: string[] = ["beta"], onClose = vi.fn()) {
  render(
    <FlagDialog
      open
      flag={BETA as never}
      existingKeys={existingKeys}
      onClose={onClose}
      onDirtyChange={vi.fn()}
    />,
  );
}

describe("creating — Save is disabled at mount, enabled after a valid, dirty edit", () => {
  it("is disabled at mount (pristine)", () => {
    create();
    expect(saveButton().disabled).toBe(true);
  });

  it("enables once a key is typed", () => {
    create();
    fireEvent.change(keyField(), { target: { value: "new_flag" } });
    expect(saveButton().disabled).toBe(false);
  });

  it("stays disabled for a whitespace-only key", () => {
    create();
    fireEvent.change(keyField(), { target: { value: "   " } });
    expect(saveButton().disabled).toBe(true);
  });

  // M4: the whitespace-key case above passes even with the validity term deleted, because a
  // whitespace-only key also reads as NOT DIRTY. This one is dirty (a description was typed)
  // and invalid (no key), so only the validity term can hold Save down.
  it("stays disabled when a description is typed but the key is left blank", () => {
    create();
    fireEvent.change(descriptionField(), { target: { value: "gates dark theme" } });
    expect(saveButton().disabled).toBe(true);
  });

  // The gate disables Save, so handleSubmit's `throw new Error("A key is required.")` never
  // reaches the user through a click; without this, a grey Save reads as a broken button.
  it("says WHY Save is grey once the form is dirty but the key is still missing", () => {
    create();
    fireEvent.change(descriptionField(), { target: { value: "gates dark theme" } });
    expect(screen.getByText("A key is required.")).toBeTruthy();
  });

  // The other half, and the branch ruling for CREATE surfaces: they speak from the first frame.
  // A pristine dialog is blocked too (no key yet) and Save is already grey, so waiting for the
  // user to type leaves a dead button unexplained at the moment they are deciding what to fill
  // in — and the thing it is blocked on is exactly what they opened the dialog to supply.
  it("says why Save is grey from the FIRST frame — an untouched form is already blocked", () => {
    create();
    expect(saveButton().disabled).toBe(true);
    expect(screen.getByText("A key is required.")).toBeTruthy();
  });

  // This dialog used to check only "key is non-blank", while its hub twin also rejected a key
  // that already exists. A colliding key LOOKS perfectly valid, so admin lit Save up for a click
  // whose only possible outcome was a 409 from the server.
  it("stays disabled for a key that already exists, and names it", () => {
    create(["dark_mode"]);
    fireEvent.change(keyField(), { target: { value: "dark_mode" } });
    expect(saveButton().disabled).toBe(true);
    expect(screen.getByText(/already exists/)).toBeTruthy();
  });

  it("catches a colliding key that is only padded with whitespace", () => {
    create(["dark_mode"]);
    fireEvent.change(keyField(), { target: { value: "  dark_mode  " } });
    expect(saveButton().disabled).toBe(true);
  });

  it("enables again once the key is changed to a free one", () => {
    create(["dark_mode"]);
    fireEvent.change(keyField(), { target: { value: "dark_mode" } });
    expect(saveButton().disabled).toBe(true);
    fireEvent.change(keyField(), { target: { value: "light_mode" } });
    expect(saveButton().disabled).toBe(false);
    expect(screen.queryByText(/already exists/)).toBeNull();
  });

  it("clicking Save while enabled calls createFlag.mutateAsync with the trimmed key", () => {
    createAsync.mockResolvedValue(undefined);
    create();
    fireEvent.change(keyField(), { target: { value: "new_flag" } });
    fireEvent.click(saveButton());
    expect(createAsync).toHaveBeenCalledWith(expect.objectContaining({ key: "new_flag" }));
  });
});

describe("editing — the row's own values, and only what changed", () => {
  it("opens on the flag's values", () => {
    edit();
    expect((keyField() as HTMLInputElement).value).toBe("beta");
    expect((descriptionField() as HTMLInputElement).value).toBe("Beta features");
  });

  it("opens with Save grey and nothing blocking it — an unedited row is simply not dirty", () => {
    edit();
    expect(saveButton().disabled).toBe(true);
    // The distinction that matters: the create dialog opens blocked AND says why. Editing an
    // existing row is blocked by nothing, so a reason here would be an accusation about a form
    // the user has not touched.
    expect(screen.queryByText("A key is required.")).toBeNull();
    expect(screen.queryByText(/already exists/)).toBeNull();
  });

  // The row's own key is in `existingKeys` — it is one of the list's rows. Counting it as a
  // collision would grey out Save for every edit that leaves the key alone, which is most of them.
  it("does not treat the row's own key as a collision", () => {
    edit(["beta", "gamma"]);
    fireEvent.change(descriptionField(), { target: { value: "Beta, revised" } });
    expect(saveButton().disabled).toBe(false);
    expect(screen.queryByText(/already exists/)).toBeNull();
  });

  // Renaming is something this page has always been able to do, and the gate has to hold for it:
  // hub's shared `editingMode` skips every check because hub disables the key input.
  it("still blocks a rename onto ANOTHER row's key", () => {
    edit(["beta", "gamma"]);
    fireEvent.change(keyField(), { target: { value: "gamma" } });
    expect(saveButton().disabled).toBe(true);
    expect(screen.getByText(/already exists/)).toBeTruthy();
  });

  it("still blocks a rename to nothing", () => {
    edit();
    fireEvent.change(keyField(), { target: { value: "" } });
    expect(saveButton().disabled).toBe(true);
    expect(screen.getByText("A key is required.")).toBeTruthy();
  });

  // A PUT that carried every field would write back the two the operator never touched, undoing
  // whatever landed on them while the dialog sat open.
  it("sends ONLY the changed field", () => {
    updateAsync.mockResolvedValue(undefined);
    edit();
    fireEvent.change(descriptionField(), { target: { value: "Beta, revised" } });
    fireEvent.click(saveButton());
    expect(updateAsync).toHaveBeenCalledWith({
      id: 1,
      changes: { description: "Beta, revised" },
    });
  });

  it("sends a rename as a key change", () => {
    updateAsync.mockResolvedValue(undefined);
    edit();
    fireEvent.change(keyField(), { target: { value: "beta_renamed" } });
    fireEvent.click(saveButton());
    expect(updateAsync).toHaveBeenCalledWith({ id: 1, changes: { key: "beta_renamed" } });
  });

  it("never creates while editing", () => {
    updateAsync.mockResolvedValue(undefined);
    edit();
    fireEvent.change(descriptionField(), { target: { value: "Beta, revised" } });
    fireEvent.click(saveButton());
    expect(createAsync).not.toHaveBeenCalled();
  });
});

describe("the hidden default submit button", () => {
  it("does not submit when unedited — Enter in any text field activates THIS button, not the visible Save", () => {
    // Pressing Enter in a text input inside a <form> runs the browser's implicit-submission
    // algorithm, which activates the form's default button (the first submit button in tree
    // order) — here that's the hidden <button type="submit"> rendered inside the <form>; the
    // visible "Save" lives in DialogActions, a SIBLING of the form, so it is never the target
    // of implicit submission. Activating a disabled button is a no-op, so this only stays safe
    // if the hidden button carries the same disabled state as the visible one.
    create();
    // The dialog renders through a portal, so query relative to a known in-form element
    // rather than the render()'s own (unportalled) container.
    const form = keyField().closest("form")!;
    const hiddenSubmit = form.querySelector('button[type="submit"]') as HTMLButtonElement;
    expect(hiddenSubmit).not.toBeNull();
    expect(hiddenSubmit.disabled).toBe(true);
    fireEvent.click(hiddenSubmit);
    expect(createAsync).not.toHaveBeenCalled();
  });

  it("DOES submit once dirty — proves the assertion above is a real gate, not a button that's disabled for some other reason", () => {
    createAsync.mockResolvedValue(undefined);
    create();
    fireEvent.change(keyField(), { target: { value: "new_flag" } });
    const hiddenSubmit = keyField()
      .closest("form")!
      .querySelector('button[type="submit"]') as HTMLButtonElement;
    expect(hiddenSubmit.disabled).toBe(false);
    fireEvent.click(hiddenSubmit);
    expect(createAsync).toHaveBeenCalled();
  });

  it("does not fire a SECOND write when Enter is pressed during an in-flight save", () => {
    // DialogActions swaps its whole action row for a spinner while `busy`, so mid-save the
    // hidden default button is the ONLY reachable submit path — and `useAction.run` has no
    // re-entrancy guard of its own. Without a busy term on this button, holding Enter (or a
    // double-tap) creates the flag twice.
    createAsync.mockImplementation(() => new Promise<void>(() => {})); // never settles
    create();
    fireEvent.change(keyField(), { target: { value: "new_flag" } });
    const hiddenSubmit = keyField()
      .closest("form")!
      .querySelector('button[type="submit"]') as HTMLButtonElement;

    fireEvent.click(hiddenSubmit);
    expect(createAsync).toHaveBeenCalledTimes(1);

    expect(hiddenSubmit.disabled).toBe(true);
    fireEvent.click(hiddenSubmit);
    expect(createAsync).toHaveBeenCalledTimes(1);
  });
});
