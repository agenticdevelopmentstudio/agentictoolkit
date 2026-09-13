/// <reference types="@testing-library/jest-dom/vitest" />
//
// A pane that owns its own button bar. Two halves of one change, and they only make sense
// together: the bar has to have somewhere to go (the host's toolbar slot), and the rail's
// header `+` has to stop offering a second, unlabelled creator next to the bar's own "Add".
//
// Before this, `StandaloneRailHost` published `toolbarSlot: null`, so every `ToolbarPortal` on a
// bare feature site rendered inline inside the detail — which is exactly where the integrations
// pane's Save/Test/Remove buttons were, and why they were reported as scattered.
import type { ReactNode } from "react";
import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import type { TopicLevel } from "@agenticdevelopertoolkit/ui/blocks";
import { StandaloneRailHost } from "../standalone-rail-host";
import { StackLevels, ToolbarPortal, useToolbarPortal } from "../rail-host";
import { useMasterDetailLevel } from "../master-detail/useMasterDetailLevel";
import type { MasterDetailForm } from "../master-detail/useMasterDetailForm";

afterEach(cleanup);

/** One published level plus whatever the leaf renders — the shape every converted pane has. */
function Feature({ children }: { children?: ReactNode }) {
  const level: TopicLevel = {
    id: "integrations",
    title: "Integrations",
    items: [{ id: "gh1", label: "GitHub (acme)" }],
    selectedId: null,
    onSelect: () => {},
    onClear: () => {},
    emptyLabel: "none",
  };
  return (
    <StackLevels levels={[level]}>
      <div>{children}</div>
    </StackLevels>
  );
}

describe("the host's toolbar slot", () => {
  it("mounts an empty slot when no pane portals anything", () => {
    render(
      <StandaloneRailHost>
        <Feature />
      </StandaloneRailHost>,
    );
    // The slot is mounted unconditionally — there is nothing to portal into otherwise — and the
    // strip around it collapses on `:empty`, which is a stylesheet fact jsdom cannot see. What is
    // assertable, and what actually regresses, is that the slot holds nothing.
    const slot = document.querySelector("[data-adh-toolbar-slot]");
    expect(slot).not.toBeNull();
    expect(slot).toBeEmptyDOMElement();
  });

  it("puts a pane's ToolbarPortal content in the slot, not in the pane", () => {
    function Pane() {
      return (
        <>
          <ToolbarPortal>
            <button type="button">Add</button>
          </ToolbarPortal>
          <p>detail body</p>
        </>
      );
    }
    render(
      <StandaloneRailHost>
        <Feature>
          <Pane />
        </Feature>
      </StandaloneRailHost>,
    );
    const slot = document.querySelector("[data-adh-toolbar-slot]")!;
    expect(slot).toContainElement(screen.getByRole("button", { name: "Add" }));
    // …and the bar is NOT inside the pane body it was declared in.
    expect(screen.getByText("detail body").parentElement).not.toContainElement(
      screen.getByRole("button", { name: "Add" }),
    );
  });

  it("hands the same node to useToolbarPortal, so a pane can tell whether it has one", () => {
    let seen: HTMLElement | null | undefined;
    function Probe() {
      seen = useToolbarPortal();
      return null;
    }
    render(
      <StandaloneRailHost>
        <Feature>
          <Probe />
        </Feature>
      </StandaloneRailHost>,
    );
    expect(seen).toBe(document.querySelector("[data-adh-toolbar-slot]"));
  });
});

/** A form stub: `useMasterDetailLevel` reads only these fields to build the level. */
function stubForm(onCreate: () => void): MasterDetailForm<{ id: string }, { id: string }> {
  return {
    selectedId: null,
    selected: null,
    creating: false,
    editing: false,
    dirty: false,
    draft: null,
    error: null,
    detailKey: "k",
    onChange: () => {},
    select: () => {},
    actions: { onCreate } as MasterDetailForm<{ id: string }, { id: string }>["actions"],
    guard: { isDirty: () => false },
  };
}

describe("useMasterDetailLevel showNew", () => {
  function Pane({ showNew, onCreate }: { showNew?: boolean; onCreate: () => void }) {
    useMasterDetailLevel({
      id: "integrations",
      title: "Integrations",
      form: stubForm(onCreate),
      items: [{ id: "gh1" }],
      getId: (i) => i.id,
      getLabel: () => "GitHub (acme)",
      newLabel: "New integration…",
      showNew,
    });
    return <div>leaf</div>;
  }

  it("draws the header + by default", () => {
    const onCreate = vi.fn();
    render(
      <StandaloneRailHost>
        <Pane onCreate={onCreate} />
      </StandaloneRailHost>,
    );
    expect(screen.getByRole("button", { name: "New integration" })).toBeInTheDocument();
  });

  it("omits it when the surface owns creation, without disturbing the rows", () => {
    const onCreate = vi.fn();
    render(
      <StandaloneRailHost>
        <Pane showNew={false} onCreate={onCreate} />
      </StandaloneRailHost>,
    );
    expect(screen.queryByRole("button", { name: "New integration" })).toBeNull();
    // The list itself is untouched — this suppresses an affordance, not the level.
    expect(screen.getAllByRole("button", { name: "GitHub (acme)" }).length).toBeGreaterThan(0);
  });
});
