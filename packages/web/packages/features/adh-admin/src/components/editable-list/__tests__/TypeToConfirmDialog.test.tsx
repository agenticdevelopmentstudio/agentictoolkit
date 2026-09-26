// @vitest-environment jsdom
//
// The gate in front of every destructive action on the admin site. What is asserted here is the
// part that makes it a gate rather than a speed bump: the confirm button is dead until the exact
// value has been typed, and "exact" means exact.
import * as React from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { TypeToConfirmDialog } from "../TypeToConfirmDialog";

afterEach(cleanup);

const VALUE = "storage.acme.notes";

function setup(overrides: Partial<React.ComponentProps<typeof TypeToConfirmDialog>> = {}) {
  const onConfirm = vi.fn();
  const onCancel = vi.fn();
  const view = render(
    <TypeToConfirmDialog
      open
      title="Release this name?"
      confirmValue={VALUE}
      confirmLabel="Release"
      onConfirm={onConfirm}
      onCancel={onCancel}
      {...overrides}
    />,
  );
  const confirm = (): HTMLButtonElement =>
    screen.getByRole("button", { name: /Release|Working/ }) as HTMLButtonElement;
  const input = (): HTMLInputElement => screen.getByRole("textbox") as HTMLInputElement;
  const type = (value: string) => fireEvent.change(input(), { target: { value } });
  return { ...view, onConfirm, onCancel, confirm, input, type };
}

describe("arming", () => {
  it("starts disabled", () => {
    expect(setup().confirm().disabled).toBe(true);
  });

  it("arms only on an exact match", () => {
    const { confirm, type } = setup();
    type("storage.acme.note");
    expect(confirm().disabled).toBe(true);
    type(VALUE);
    expect(confirm().disabled).toBe(false);
  });

  it("does not fold case", () => {
    // Two rdids differing only in case are two different names, so accepting either would confirm
    // something other than what the dialog showed.
    const { confirm, type } = setup();
    type(VALUE.toUpperCase());
    expect(confirm().disabled).toBe(true);
  });

  it("does not trim", () => {
    const { confirm, type } = setup();
    type(` ${VALUE} `);
    expect(confirm().disabled).toBe(true);
  });

  it("stays disabled for an empty confirmValue", () => {
    // The load-bearing guard: an empty value matches the untouched input, which would arm a
    // destructive button with no typing at all.
    expect(setup({ confirmValue: "" }).confirm().disabled).toBe(true);
  });

  it("stays disabled while busy, even when typed correctly", () => {
    const { confirm, type } = setup({ busy: true });
    type(VALUE);
    expect(confirm().disabled).toBe(true);
  });
});

describe("confirming", () => {
  it("fires on click once armed", () => {
    const { confirm, type, onConfirm } = setup();
    type(VALUE);
    fireEvent.click(confirm());
    expect(onConfirm).toHaveBeenCalledOnce();
  });

  it("fires on Enter once armed, and not before", () => {
    const { input, type, onConfirm } = setup();
    fireEvent.keyDown(input(), { key: "Enter" });
    expect(onConfirm).not.toHaveBeenCalled();
    type(VALUE);
    fireEvent.keyDown(input(), { key: "Enter" });
    expect(onConfirm).toHaveBeenCalledOnce();
  });

  it("cancels", () => {
    const { onCancel } = setup();
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(onCancel).toHaveBeenCalledOnce();
  });
});

describe("re-arming between items", () => {
  it("clears the typing when the value it is pointed at changes", () => {
    // A run that walks a selection keeps this dialog open and swaps `confirmValue` underneath.
    // Carrying the previous row's typing across would leave the box holding text that confirms
    // nothing — or worse, arm the next name because the two happened to match.
    const { rerender, confirm, input, type } = setup();
    type(VALUE);
    expect(confirm().disabled).toBe(false);
    rerender(
      <TypeToConfirmDialog
        open
        title="Release this name?"
        confirmValue="storage.acme.other"
        confirmLabel="Release"
        onConfirm={vi.fn()}
        onCancel={vi.fn()}
      />,
    );
    expect(input().value).toBe("");
    expect(confirm().disabled).toBe(true);
  });
});

describe("reporting", () => {
  it("shows the value the operator has to type", () => {
    setup();
    expect(screen.getByText(VALUE)).toBeTruthy();
  });

  it("shows a failure without closing", () => {
    setup({ error: "the name is still held by two live addresses" });
    expect(screen.getByText(/still held by two live addresses/)).toBeTruthy();
    expect(screen.getByRole("textbox")).toBeTruthy();
  });
});
