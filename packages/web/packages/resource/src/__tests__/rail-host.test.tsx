/// <reference types="@testing-library/jest-dom/vitest" />
import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import type { TopicLevel } from "@agenticdevelopertoolkit/ui/blocks";
import { RailHostContext, StackLevels, type RailHostRegistry } from "../rail-host";

const level: TopicLevel = {
  id: "l1",
  title: "T",
  items: [],
  selectedId: null,
  onSelect: () => {},
  onClear: () => {},
};

describe("StackLevels", () => {
  it("no-ops without a host (children still render)", () => {
    render(<StackLevels levels={[level]}>inner</StackLevels>);
    expect(screen.getByText("inner")).toBeInTheDocument();
  });

  it("registers with a host and unregisters on unmount", () => {
    const registry: RailHostRegistry = {
      registerLevels: vi.fn(),
      unregisterLevels: vi.fn(),
      registerExitGuard: vi.fn(),
      popStack: vi.fn(),
      reportMissing: vi.fn(),
      reportBusy: vi.fn(),
      toolbarSlot: null,
    };
    const { unmount } = render(
      <RailHostContext.Provider value={registry}>
        <StackLevels levels={[level]}>inner</StackLevels>
      </RailHostContext.Provider>,
    );
    expect(registry.registerLevels).toHaveBeenCalledOnce();
    unmount();
    expect(registry.unregisterLevels).toHaveBeenCalledOnce();
  });

  /**
   * A CHANGED SET RE-PUBLISHES. The publish key is built from the level's plain fields, and a
   * `Set` is one of them: it is a bag of scalars, allocated when it changes rather than on every
   * render, so keying on its contents is nothing like keying on a node.
   *
   * `checkedIds` is why this matters. A tick changes that set and NOTHING else about the level, so
   * without this the host kept the level exactly as registered — drawing the row unticked, and,
   * far worse, keeping the `onToggleChecked` whose closure held the set as it was before the first
   * tick. Every tick after the first started from empty, and a bar acting on "the ticked rows"
   * acted on one of them.
   */
  it("re-registers when a Set field's CONTENTS change and nothing else does", () => {
    const registry: RailHostRegistry = {
      registerLevels: vi.fn(),
      unregisterLevels: vi.fn(),
      registerExitGuard: vi.fn(),
      popStack: vi.fn(),
      reportMissing: vi.fn(),
      reportBusy: vi.fn(),
      toolbarSlot: null,
    };
    const withChecked = (ids: string[]) => (
      <RailHostContext.Provider value={registry}>
        <StackLevels levels={[{ ...level, checkedIds: new Set(ids), checkable: true }]}>
          inner
        </StackLevels>
      </RailHostContext.Provider>
    );
    const { rerender } = render(withChecked([]));
    expect(registry.registerLevels).toHaveBeenCalledTimes(1);

    rerender(withChecked(["a"]));
    expect(registry.registerLevels).toHaveBeenCalledTimes(2);
    rerender(withChecked(["a", "b"]));
    expect(registry.registerLevels).toHaveBeenCalledTimes(3);

    // Same contents, new Set object — the identity churn the key exists to absorb.
    rerender(withChecked(["b", "a"]));
    expect(registry.registerLevels).toHaveBeenCalledTimes(3);
  });
});
