// @vitest-environment jsdom
import * as React from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { ConfirmSourceDialog } from "../TransferDialog";

afterEach(cleanup);

function setup(overrides: Partial<React.ComponentProps<typeof ConfirmSourceDialog>> = {}) {
  const onConfirm = vi.fn();
  render(
    <ConfirmSourceDialog
      open
      sourceRdid="ecosystem.Acme"
      targetRdid="ecosystem.dest"
      count={3}
      onCancel={vi.fn()}
      onConfirm={onConfirm}
      {...overrides}
    />,
  );
  return { onConfirm, field: () => screen.getByLabelText(/type the current ecosystem/i) };
}
const confirmButton = () => screen.getByRole("button", { name: "Transfer" }) as HTMLButtonElement;

describe("ConfirmSourceDialog", () => {
  it("blocks until the source rdid is typed", () => {
    setup();
    expect(confirmButton().disabled).toBe(true);
  });

  it("is CASE SENSITIVE", () => {
    // The brief says so, and the reason is that this gate exists to be slow. A case-insensitive
    // match accepts a half-remembered address; typing it exactly means reading it.
    const { field } = setup();
    fireEvent.change(field(), { target: { value: "ecosystem.acme" } });
    expect(confirmButton().disabled).toBe(true);
    fireEvent.change(field(), { target: { value: "ecosystem.Acme" } });
    expect(confirmButton().disabled).toBe(false);
  });

  it("does not accept the TARGET address", () => {
    // The gate asks which set of users is selected, not where they are going — and the operator
    // just picked the target off a list, so retyping it confirms nothing.
    const { field } = setup();
    fireEvent.change(field(), { target: { value: "ecosystem.dest" } });
    expect(confirmButton().disabled).toBe(true);
  });

  it("does not accept surrounding whitespace as a match", () => {
    const { field } = setup();
    fireEvent.change(field(), { target: { value: " ecosystem.Acme " } });
    expect(confirmButton().disabled).toBe(true);
  });

  it("stays shut while the source address is still unresolved", () => {
    // The source rdid is looked up, not hardcoded, so it is "" for the moment before the lookup
    // lands. An empty field would equal an empty expectation and open the gate on a dialog that
    // had not yet named what the users were leaving.
    const { field } = setup({ sourceRdid: "" });
    expect(confirmButton().disabled).toBe(true);
    fireEvent.change(field(), { target: { value: "" } });
    expect(confirmButton().disabled).toBe(true);
  });

  it("names how many users and where they are going", () => {
    setup();
    expect(screen.getByText(/3 users/)).toBeTruthy();
    expect(screen.getByText(/ecosystem\.dest/)).toBeTruthy();
  });

  it("confirming calls onConfirm exactly once", () => {
    const { onConfirm, field } = setup();
    fireEvent.change(field(), { target: { value: "ecosystem.Acme" } });
    fireEvent.click(confirmButton());
    expect(onConfirm).toHaveBeenCalledTimes(1);
  });
});
