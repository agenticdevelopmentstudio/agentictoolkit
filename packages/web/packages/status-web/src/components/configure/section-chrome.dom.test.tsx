// @vitest-environment jsdom
import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, fireEvent, cleanup } from "@testing-library/react";
import { EntityEditorShell } from "./section-chrome";

afterEach(cleanup); // no vitest globals → RTL's auto-cleanup never registers

// jsdom has no ResizeObserver; the Dialog primitive observes its content size.
class ResizeObserverStub {
  observe(): void {}
  unobserve(): void {}
  disconnect(): void {}
}
(globalThis as { ResizeObserver?: unknown }).ResizeObserver ??= ResizeObserverStub;

function shell(onDelete = vi.fn()) {
  render(
    <EntityEditorShell
      onCancel={vi.fn()}
      onSave={vi.fn()}
      canSave={false}
      saving={false}
      onDelete={onDelete}
      canDelete={true}
      deleteConfirm={{ title: 'Delete group "Olylo"?', description: "All of its sites go with it." }}
      error={null}
    >
      <div>form</div>
    </EntityEditorShell>,
  );
  return onDelete;
}

describe("EntityEditorShell delete confirmation", () => {
  it("Delete opens the shared AlertModal (no browser confirm); confirming runs onDelete", () => {
    const onDelete = shell();
    fireEvent.click(screen.getByRole("button", { name: "Delete" }));
    expect(onDelete).not.toHaveBeenCalled(); // armed, not executed
    expect(screen.getByText('Delete group "Olylo"?')).toBeTruthy();
    // The modal's own destructive Delete button (the bar's is the other one).
    const deletes = screen.getAllByRole("button", { name: "Delete" });
    fireEvent.click(deletes[deletes.length - 1]!);
    expect(onDelete).toHaveBeenCalledTimes(1);
  });

  it("Cancel in the modal closes it without deleting", () => {
    const onDelete = shell();
    fireEvent.click(screen.getByRole("button", { name: "Delete" }));
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(onDelete).not.toHaveBeenCalled();
    expect(screen.queryByText('Delete group "Olylo"?')).toBeNull();
  });
});
