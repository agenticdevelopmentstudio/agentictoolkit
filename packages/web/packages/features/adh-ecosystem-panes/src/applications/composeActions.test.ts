// An application's client auth section rides on the application's one bar: its edits light Save
// and Cancel, and its Cancel must not close the application the way the form's own Cancel does.
import { describe, it, expect, vi } from "vitest";
import type { MasterDetailActions } from "@agentic-toolkit/resource";
import { composeActions } from "./ApplicationsPane";

function formActions(over: Partial<MasterDetailActions> = {}): MasterDetailActions {
  return {
    onCreate: vi.fn(),
    onCancel: vi.fn(),
    canCancel: true,
    onSave: vi.fn(),
    canSave: false,
    blockedReason: null,
    saving: false,
    onDelete: vi.fn(),
    canDelete: true,
    ...over,
  };
}

function section(over: Partial<Parameters<typeof composeActions>[2]> = {}) {
  return {
    dirty: true,
    canSave: true,
    blockedReason: null,
    saving: false,
    save: vi.fn(async () => true),
    reset: vi.fn(),
    ...over,
  };
}

describe("composeActions", () => {
  it("is the form's bar as-is while client auth is clean", () => {
    const form = formActions();
    expect(composeActions(form, false, section({ dirty: false }))).toBe(form);
  });

  it("lights Save for client auth edits alone and saves only them", async () => {
    const form = formActions();
    const ca = section();
    const bar = composeActions(form, false, ca);
    expect(bar.canSave).toBe(true);
    bar.onSave();
    await vi.waitFor(() => expect(ca.save).toHaveBeenCalled());
    expect(form.onSave).not.toHaveBeenCalled();
  });

  it("saves both halves, client auth first, when both are dirty", async () => {
    const form = formActions({ canSave: true });
    const ca = section();
    composeActions(form, true, ca).onSave();
    await vi.waitFor(() => expect(form.onSave).toHaveBeenCalled());
    expect(ca.save).toHaveBeenCalled();
  });

  it("does not save the form when the client auth write fails", async () => {
    const form = formActions({ canSave: true });
    const ca = section({ save: vi.fn(async () => false) });
    composeActions(form, true, ca).onSave();
    await vi.waitFor(() => expect(ca.save).toHaveBeenCalled());
    expect(form.onSave).not.toHaveBeenCalled();
  });

  it("holds Save while either half cannot save, and says why", () => {
    expect(composeActions(formActions({ canSave: false }), true, section()).canSave).toBe(false);
    const blocked = composeActions(
      formActions(),
      false,
      section({ canSave: false, blockedReason: "Return origin must be http(s)." }),
    );
    expect(blocked.canSave).toBe(false);
    expect(blocked.blockedReason).toBe("Return origin must be http(s).");
  });

  it("cancels client auth alone without closing the application", () => {
    const form = formActions();
    const ca = section();
    composeActions(form, false, ca).onCancel();
    expect(ca.reset).toHaveBeenCalled();
    expect(form.onCancel).not.toHaveBeenCalled();
  });

  it("cancels both when the form is dirty too", () => {
    const form = formActions();
    const ca = section();
    composeActions(form, true, ca).onCancel();
    expect(ca.reset).toHaveBeenCalled();
    expect(form.onCancel).toHaveBeenCalled();
  });
});
