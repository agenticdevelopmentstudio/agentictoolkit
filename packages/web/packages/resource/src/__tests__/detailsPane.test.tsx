/// <reference types="@testing-library/jest-dom/vitest" />
// A DetailsPane's ONE bar speaks for every section inside it: Save when anything is dirty and all
// of it is valid, each dirty section saved in order, Cancel discarding all (Mike, 2026-09-29).
import { act, fireEvent, render, screen } from "@testing-library/react";
import { useState } from "react";
import { describe, expect, it, vi } from "vitest";

import { DetailsPane, useDetailsSection } from "../details-pane";

/** A section whose draft is one text box; `invalid` text cannot be saved. */
function Section({
  name,
  log,
  fail,
}: {
  name: string;
  log: string[];
  fail?: boolean;
}) {
  const [saved, setSaved] = useState("");
  const [draft, setDraft] = useState("");
  useDetailsSection({
    dirty: draft !== saved,
    canSave: draft !== "invalid",
    blockedReason: draft === "invalid" ? `${name} is invalid.` : null,
    save: async () => {
      log.push(`save ${name}`);
      if (fail) throw new Error(`${name} failed.`);
      setSaved(draft);
    },
    reset: () => {
      log.push(`reset ${name}`);
      setDraft(saved);
    },
  });
  return <input aria-label={name} value={draft} onChange={(e) => setDraft(e.target.value)} />;
}

function Pane({ log, failB }: { log: string[]; failB?: boolean }) {
  return (
    <DetailsPane title="Thing" hoist={false}>
      <Section name="A" log={log} />
      <Section name="B" log={log} fail={failB} />
    </DetailsPane>
  );
}

const save = () => screen.getByRole("button", { name: "Save" });
const cancel = () => screen.getByRole("button", { name: "Cancel" });
const type = (name: string, value: string) =>
  fireEvent.change(screen.getByLabelText(name), { target: { value } });

describe("DetailsPane", () => {
  it("enables Save only while some section is dirty and every dirty section is valid", () => {
    render(<Pane log={[]} />);
    expect(save()).toBeDisabled();
    type("A", "x");
    expect(save()).toBeEnabled();
    type("B", "invalid");
    expect(save()).toBeDisabled();
    expect(screen.getByText("B is invalid.")).toBeInTheDocument();
    type("B", "");
    expect(save()).toBeEnabled();
    type("A", "");
    expect(save()).toBeDisabled();
  });

  it("saves the dirty sections in order, skipping clean ones, then reports Saved", async () => {
    const log: string[] = [];
    render(<Pane log={log} />);
    type("B", "b");
    type("A", "a");
    await act(async () => {
      fireEvent.click(save());
    });
    expect(log).toEqual(["save A", "save B"]);
    expect(screen.getByText("Saved.")).toBeInTheDocument();
    expect(save()).toBeDisabled();
  });

  it("stops at a failing section and shows its message", async () => {
    const log: string[] = [];
    render(<Pane log={log} failB />);
    type("A", "a");
    type("B", "b");
    await act(async () => {
      fireEvent.click(save());
    });
    expect(log).toEqual(["save A", "save B"]);
    expect(screen.getByText("B failed.")).toBeInTheDocument();
    // A is saved; B's edit is still pending, so Save stays live for a retry.
    expect(save()).toBeEnabled();
  });

  it("runs one save for two clicks inside a single commit", async () => {
    const log: string[] = [];
    render(<Pane log={log} />);
    type("A", "a");
    await act(async () => {
      const button = save();
      fireEvent.click(button);
      fireEvent.click(button);
    });
    expect(log).toEqual(["save A"]);
  });

  it("Cancel resets every section", () => {
    const log: string[] = [];
    render(<Pane log={log} />);
    type("A", "a");
    type("B", "b");
    fireEvent.click(cancel());
    expect(log).toEqual(["reset A", "reset B"]);
    expect(screen.getByLabelText("A")).toHaveValue("");
    expect(screen.getByLabelText("B")).toHaveValue("");
    expect(save()).toBeDisabled();
  });

  it("registers its own `section` prop for a component that renders the pane itself", async () => {
    const saveFn = vi.fn(async () => {});
    render(
      <DetailsPane hoist={false} section={{ dirty: true, canSave: true, save: saveFn, reset: () => {} }}>
        body
      </DetailsPane>,
    );
    await act(async () => {
      fireEvent.click(save());
    });
    expect(saveFn).toHaveBeenCalledTimes(1);
  });

  it("uses a list pane's own actions as-is", () => {
    const onSave = vi.fn();
    render(
      <DetailsPane
        hoist={false}
        actions={{
          onCreate: () => {},
          onCancel: () => {},
          canCancel: true,
          onSave,
          canSave: true,
          onDelete: () => {},
          canDelete: false,
        }}
      >
        <Section name="A" log={[]} />
      </DetailsPane>,
    );
    fireEvent.click(save());
    expect(onSave).toHaveBeenCalledTimes(1);
  });

  it("scrolls its body inside a container that does not grow", () => {
    const { container } = render(<Pane log={[]} />);
    const pane = container.querySelector('[data-slot="details-pane"]')!;
    const body = container.querySelector('[data-slot="details-body"]')!;
    expect(pane).toHaveClass("min-h-0", "flex-1", "flex-col");
    expect(body).toHaveClass("min-h-0", "flex-1", "overflow-y-auto");
  });
});
