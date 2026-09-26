// @vitest-environment jsdom
import { describe, it, expect, afterEach, vi } from "vitest";
import { render, screen, fireEvent, cleanup } from "@testing-library/react";
import { BagDialog } from "./ServerBagsPane";
import type { ServerBag } from "../api/admin";

// BagDialog calls useCreateBag()/useUpdateBag() internally (not prop-injected,
// unlike hub's BagDialog) — mock the API-hook module boundary so mutateAsync is
// a spy we can assert on, without a real network call or a react-query provider.
const createMutateAsync = vi.fn();
const updateMutateAsync = vi.fn();
vi.mock("../api/admin", () => ({
  useCreateBag: () => ({ mutateAsync: createMutateAsync }),
  useUpdateBag: () => ({ mutateAsync: updateMutateAsync }),
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

describe("BagDialog (create mode) — Save is disabled at mount, enabled after a valid, dirty edit", () => {
  it("is disabled at mount (pristine)", () => {
    render(
      <BagDialog open bag={null} latest={null} existingKeys={[]} onClose={vi.fn()} onDirtyChange={vi.fn()} />,
    );
    expect(saveButton().disabled).toBe(true);
  });

  it("stays disabled once dirty with unparseable JSON in the value field", () => {
    render(
      <BagDialog open bag={null} latest={null} existingKeys={[]} onClose={vi.fn()} onDirtyChange={vi.fn()} />,
    );
    fireEvent.change(screen.getByPlaceholderText("e.g. onboarding_config"), {
      target: { value: "new_bag" },
    });
    fireEvent.change(screen.getByPlaceholderText('e.g. { "maxItems": 20 }'), {
      target: { value: "{not json" },
    });
    expect(saveButton().disabled).toBe(true);
  });

  it("enables once a non-colliding key and valid JSON are both present", () => {
    render(
      <BagDialog
        open
        bag={null}
        latest={null}
        existingKeys={["onboarding_config"]}
        onClose={vi.fn()}
        onDirtyChange={vi.fn()}
      />,
    );
    fireEvent.change(screen.getByPlaceholderText("e.g. onboarding_config"), {
      target: { value: "new_bag" },
    });
    fireEvent.change(screen.getByPlaceholderText('e.g. { "maxItems": 20 }'), {
      target: { value: "42" },
    });
    expect(saveButton().disabled).toBe(false);
  });

  // The gate disables Save, so handleSubmit's `throw new Error(...)` never reaches the user
  // through a click. Without these the collision/JSON rules read as a broken button.
  it("says WHY Save is grey when the typed key collides with an existing bag", () => {
    render(
      <BagDialog
        open
        bag={null}
        latest={null}
        existingKeys={["onboarding_config"]}
        onClose={vi.fn()}
        onDirtyChange={vi.fn()}
      />,
    );
    fireEvent.change(screen.getByPlaceholderText('e.g. { "maxItems": 20 }'), {
      target: { value: "42" },
    });
    fireEvent.change(screen.getByPlaceholderText("e.g. onboarding_config"), {
      target: { value: "onboarding_config" },
    });
    expect(saveButton().disabled).toBe(true);
    expect(screen.getByText("A bag named “onboarding_config” already exists.")).toBeTruthy();
  });

  it("says WHY Save is grey when the value isn't parseable JSON", () => {
    render(
      <BagDialog open bag={null} latest={null} existingKeys={[]} onClose={vi.fn()} onDirtyChange={vi.fn()} />,
    );
    fireEvent.change(screen.getByPlaceholderText('e.g. { "maxItems": 20 }'), {
      target: { value: "{not json" },
    });
    expect(saveButton().disabled).toBe(true);
    expect(
      screen.getByText('Value must be valid JSON — e.g. true, 42, "text", or {"a": 1}.'),
    ).toBeTruthy();
  });

  // The other half, and the branch ruling for CREATE surfaces: they speak from the first frame.
  // A pristine create form is ALREADY blocked (an empty value box isn't valid JSON) and Save is
  // already grey, so staying quiet until the user types leaves a dead button with no explanation
  // at exactly the moment the user is deciding what to fill in. What it is blocked on is what
  // they came here to supply, so saying it up front is instruction, not scolding.
  it("says why Save is grey from the FIRST frame — an untouched create form is already blocked", () => {
    render(
      <BagDialog open bag={null} latest={null} existingKeys={[]} onClose={vi.fn()} onDirtyChange={vi.fn()} />,
    );
    expect(saveButton().disabled).toBe(true);
    expect(
      screen.getByText('Value must be valid JSON — e.g. true, 42, "text", or {"a": 1}.'),
    ).toBeTruthy();
  });

  it("clicking Save while enabled calls createBag.mutateAsync with the trimmed key and parsed value", () => {
    createMutateAsync.mockResolvedValue(undefined);
    render(
      <BagDialog open bag={null} latest={null} existingKeys={[]} onClose={vi.fn()} onDirtyChange={vi.fn()} />,
    );
    fireEvent.change(screen.getByPlaceholderText("e.g. onboarding_config"), {
      target: { value: "new_bag" },
    });
    fireEvent.change(screen.getByPlaceholderText('e.g. { "maxItems": 20 }'), {
      target: { value: "42" },
    });
    fireEvent.click(saveButton());
    expect(createMutateAsync).toHaveBeenCalledWith(
      expect.objectContaining({ key: "new_bag", value: 42 }),
    );
  });
});

describe("BagDialog (edit mode) — key field is fixed; JSON validity still gates Save", () => {
  const BAG: ServerBag = {
    key: "onboarding_config",
    value: true,
    description: "gates onboarding",
    createdAt: "2026-07-01T00:00:00Z",
    updatedAt: "2026-07-01T00:00:00Z",
  };

  it("is disabled at mount (loaded, unedited)", () => {
    render(
      <BagDialog
        open
        bag={BAG}
        latest={BAG}
        existingKeys={["onboarding_config"]}
        onClose={vi.fn()}
        onDirtyChange={vi.fn()}
      />,
    );
    expect(saveButton().disabled).toBe(true);
  });

  // The create form above speaks at mount; an EDIT form must not, and it doesn't need a `dirty`
  // term to stay quiet — it opens on a loaded, valid bag, so there is genuinely no reason yet.
  it("says nothing at mount — a loaded bag has no blocking reason to report", () => {
    render(
      <BagDialog
        open
        bag={BAG}
        latest={BAG}
        existingKeys={["onboarding_config"]}
        onClose={vi.fn()}
        onDirtyChange={vi.fn()}
      />,
    );
    expect(screen.queryByRole("status")).toBeNull();
  });

  // ...but "quiet" is a CONSEQUENCE of the loaded bag round-tripping, not a rule that edit
  // surfaces are exempt: `bagFormBlockedReason` parses `valueText` before it looks at
  // `editingMode`. `ServerBag["value"]` is typed `unknown`, so a bag arriving without one makes
  // the dialog's seed — `JSON.stringify(bag.value, null, 2)` — the non-string `undefined`, which
  // `JSON.parse` rejects. The untouched dialog then names the reason, which is right: Save really
  // is dead (handleSubmit's own parse would throw the same sentence), and the `dirty` term this
  // branch removed was hiding exactly that.
  it("says why Save is grey on an untouched EDIT of a bag that has no value at all", () => {
    render(
      <BagDialog
        open
        bag={{ ...BAG, value: undefined }}
        latest={{ ...BAG, value: undefined }}
        existingKeys={["onboarding_config"]}
        onClose={vi.fn()}
        onDirtyChange={vi.fn()}
      />,
    );
    expect(saveButton().disabled).toBe(true);
    expect(
      screen.getByText('Value must be valid JSON — e.g. true, 42, "text", or {"a": 1}.'),
    ).toBeTruthy();
  });

  // `isBagFormDirty` compares the description TRIMMED because that is exactly what the submit
  // path stores (`description.trim()`). Comparing it raw would light Save for an edit the save
  // normalises straight back out — the no-op write the gate exists to prevent.
  it("stays disabled when the only description edit is surrounding whitespace", () => {
    render(
      <BagDialog
        open
        bag={BAG}
        latest={BAG}
        existingKeys={["onboarding_config"]}
        onClose={vi.fn()}
        onDirtyChange={vi.fn()}
      />,
    );
    fireEvent.change(screen.getByPlaceholderText("What does this configure? (optional)"), {
      target: { value: "  gates onboarding  " },
    });
    expect(saveButton().disabled).toBe(true);
  });

  // The control for the assertion above: the description field really does drive the gate, so
  // "disabled" there is the trim doing its job and not a field wired to nothing.
  it("enables when the description changes in substance", () => {
    render(
      <BagDialog
        open
        bag={BAG}
        latest={BAG}
        existingKeys={["onboarding_config"]}
        onClose={vi.fn()}
        onDirtyChange={vi.fn()}
      />,
    );
    fireEvent.change(screen.getByPlaceholderText("What does this configure? (optional)"), {
      target: { value: "gates onboarding for new orgs" },
    });
    expect(saveButton().disabled).toBe(false);
  });

  it("enables once the JSON value is edited to different, still-valid JSON", () => {
    render(
      <BagDialog
        open
        bag={BAG}
        latest={BAG}
        existingKeys={["onboarding_config"]}
        onClose={vi.fn()}
        onDirtyChange={vi.fn()}
      />,
    );
    fireEvent.change(screen.getByPlaceholderText('e.g. { "maxItems": 20 }'), {
      target: { value: "false" },
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
      <BagDialog
        open
        bag={BAG}
        latest={BAG}
        existingKeys={["onboarding_config"]}
        onClose={vi.fn()}
        onDirtyChange={vi.fn()}
      />,
    );
    const valueField = screen.getByPlaceholderText('e.g. { "maxItems": 20 }');
    const hiddenSubmit = valueField.closest("form")!.querySelector(
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
      <BagDialog
        open
        bag={BAG}
        latest={BAG}
        existingKeys={["onboarding_config"]}
        onClose={vi.fn()}
        onDirtyChange={vi.fn()}
      />,
    );
    const valueField = screen.getByPlaceholderText('e.g. { "maxItems": 20 }');
    fireEvent.change(valueField, { target: { value: "false" } });
    const hiddenSubmit = valueField.closest("form")!.querySelector(
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
      <BagDialog
        open
        bag={BAG}
        latest={BAG}
        existingKeys={["onboarding_config"]}
        onClose={vi.fn()}
        onDirtyChange={vi.fn()}
      />,
    );
    const valueField = screen.getByPlaceholderText('e.g. { "maxItems": 20 }');
    fireEvent.change(valueField, { target: { value: "false" } });
    const hiddenSubmit = valueField.closest("form")!.querySelector(
      'button[type="submit"]',
    ) as HTMLButtonElement;

    fireEvent.click(hiddenSubmit);
    expect(updateMutateAsync).toHaveBeenCalledTimes(1);

    expect(hiddenSubmit.disabled).toBe(true);
    fireEvent.click(hiddenSubmit);
    expect(updateMutateAsync).toHaveBeenCalledTimes(1);
  });
});

describe("BagDialog — Escape on a dirty draft asks before discarding", () => {
  const BAG: ServerBag = {
    key: "onboarding_config",
    value: true,
    description: "gates onboarding",
    createdAt: "2026-07-01T00:00:00Z",
    updatedAt: "2026-07-01T00:00:00Z",
  };

  // Dialog onOpenChange(false) is how Escape, the backdrop, and the × all reach
  // close() — firing Escape here exercises that whole path, not a bespoke one.
  it("does not close on Escape while dirty; Discard then closes", () => {
    const onClose = vi.fn();
    render(
      <BagDialog
        open
        bag={BAG}
        latest={BAG}
        existingKeys={["onboarding_config"]}
        onClose={onClose}
        onDirtyChange={vi.fn()}
      />,
    );
    const descriptionField = screen.getByPlaceholderText("What does this configure? (optional)");
    fireEvent.change(descriptionField, { target: { value: "gates onboarding for new orgs" } });

    fireEvent.keyDown(descriptionField, { key: "Escape" });
    expect(onClose).not.toHaveBeenCalled();

    // The alert is destructive and ignores Escape by design — Discard/Stay is the
    // only way out, which is exactly what this asserts by clicking through it.
    fireEvent.click(screen.getByRole("button", { name: "Discard" }));
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it("closes immediately on Escape when the form is clean — no alert", () => {
    const onClose = vi.fn();
    render(
      <BagDialog
        open
        bag={BAG}
        latest={BAG}
        existingKeys={["onboarding_config"]}
        onClose={onClose}
        onDirtyChange={vi.fn()}
      />,
    );
    fireEvent.keyDown(
      screen.getByPlaceholderText("What does this configure? (optional)"),
      { key: "Escape" },
    );
    expect(onClose).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole("button", { name: "Discard" })).toBeNull();
  });
});

describe("BagDialog — a bag that changed underneath is refused, not overwritten", () => {
  const BAG: ServerBag = {
    key: "onboarding_config",
    value: { maxItems: 20 },
    description: "Onboarding",
    createdAt: "2026-06-01T00:00:00Z",
    updatedAt: "2026-07-01T00:00:00Z",
  };

  // PATCH /system-config/:key replaces the whole document and has no version column, so a save
  // built on a stale read silently discards whatever landed in between. `latest` is the list's
  // live row for the same key; when it disagrees with the one the form opened on, the write is
  // refused rather than sent.
  it("refuses the write when the live row's value differs from the one the form opened on", async () => {
    updateMutateAsync.mockResolvedValue(undefined);
    const onClose = vi.fn();
    render(
      <BagDialog
        open
        bag={BAG}
        latest={{ ...BAG, value: { maxItems: 99 } }}
        existingKeys={["onboarding_config"]}
        onClose={onClose}
        onDirtyChange={vi.fn()}
      />,
    );
    fireEvent.change(screen.getByPlaceholderText('e.g. { "maxItems": 20 }'), {
      target: { value: "false" },
    });
    fireEvent.click(saveButton());
    expect(await screen.findByText(/changed since you opened it/i)).toBeTruthy();
    expect(updateMutateAsync).not.toHaveBeenCalled();
    expect(onClose).not.toHaveBeenCalled();
  });

  // A description-only edit elsewhere is still someone else's edit: the PATCH sends both fields,
  // so saving over it would revert a rename nobody asked to revert.
  it("refuses on a description-only difference too", async () => {
    updateMutateAsync.mockResolvedValue(undefined);
    render(
      <BagDialog
        open
        bag={BAG}
        latest={{ ...BAG, description: "Renamed by someone else" }}
        existingKeys={["onboarding_config"]}
        onClose={vi.fn()}
        onDirtyChange={vi.fn()}
      />,
    );
    fireEvent.change(screen.getByPlaceholderText('e.g. { "maxItems": 20 }'), {
      target: { value: "false" },
    });
    fireEvent.click(saveButton());
    expect(await screen.findByText(/changed since you opened it/i)).toBeTruthy();
    expect(updateMutateAsync).not.toHaveBeenCalled();
  });

  // `updatedAt` is deliberately NOT part of the comparison: it moves for reasons that are not
  // changes to the stored document, and blocking on it would refuse an edit over nothing.
  it("allows the write when only updatedAt moved", () => {
    updateMutateAsync.mockResolvedValue(undefined);
    render(
      <BagDialog
        open
        bag={BAG}
        latest={{ ...BAG, updatedAt: "2026-08-01T00:00:00Z" }}
        existingKeys={["onboarding_config"]}
        onClose={vi.fn()}
        onDirtyChange={vi.fn()}
      />,
    );
    fireEvent.change(screen.getByPlaceholderText('e.g. { "maxItems": 20 }'), {
      target: { value: "false" },
    });
    fireEvent.click(saveButton());
    expect(updateMutateAsync).toHaveBeenCalledTimes(1);
  });

  // A row that has LEFT the list is a different fact from a row that changed, and the save's own
  // 404 names it precisely; guessing here would report a conflict that never happened.
  it("lets the write through when latest is null — the save's own 404 is the better report", () => {
    updateMutateAsync.mockResolvedValue(undefined);
    render(
      <BagDialog
        open
        bag={BAG}
        latest={null}
        existingKeys={["onboarding_config"]}
        onClose={vi.fn()}
        onDirtyChange={vi.fn()}
      />,
    );
    fireEvent.change(screen.getByPlaceholderText('e.g. { "maxItems": 20 }'), {
      target: { value: "false" },
    });
    fireEvent.click(saveButton());
    expect(updateMutateAsync).toHaveBeenCalledTimes(1);
  });
});
