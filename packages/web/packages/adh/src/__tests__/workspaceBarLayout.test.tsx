/// <reference types="@testing-library/jest-dom/vitest" />
//
// The workspace chooser's PLACEMENT in the bar every home-route templated site renders. It is
// centred, and it has to be centred the same way whether or not the bar carries a trailing action
// — the hub's bar has one ("New Organization"), every feature site's has none, and the fleet's
// point is that the switcher is in the same place on all of them.
//
// That is a CSS grid (`1fr auto 1fr`, the group pinned to track 2), so jsdom cannot see the
// centring itself: it resolves no layout. What it CAN see is the structure the centring depends
// on — that the label and the trigger are one group, that the group is the middle-track element,
// and that a trailing action stays OUTSIDE it (an action swept into the group would be centred
// along with it, and would shift the group left by its own width). These assertions fail on the
// flat flex row this replaced, where the three were siblings.
import { describe, it, expect, afterEach } from "vitest";
import { render, cleanup, screen } from "@testing-library/react";
import { WorkspaceBar } from "../home/WorkspaceBar";
import type { WorkspaceOption } from "../home/WorkspaceOption";

afterEach(cleanup);

const WORKSPACES: WorkspaceOption[] = [
  { slug: "mine", name: "My Workspace" },
  { slug: "acme", name: "Acme" },
];

const control = (container: HTMLElement) => container.querySelector(".adh-home__toolbar-control");

describe("WorkspaceBar layout", () => {
  it("holds the trigger in ONE centred group, with no visible label", () => {
    const { container } = render(
      <WorkspaceBar workspaces={WORKSPACES} selected="mine" onSelect={() => {}} />,
    );

    const group = control(container);
    expect(group).not.toBeNull();
    // The bar is the group's parent, not the trigger's, which is what lets one `grid-column: 2`
    // centre it.
    expect(group!.parentElement).toHaveClass("adh-home__toolbar");
    expect(group!.querySelector(".adh-home__toolbar-label")).toBeNull();
    expect(group!).toContainElement(screen.getByRole("button", { name: "Workspace" }));
  });

  it("leaves a trailing action outside the group, as the bar's own child", () => {
    const { container } = render(
      <WorkspaceBar
        workspaces={WORKSPACES}
        selected="mine"
        onSelect={() => {}}
        action={<button type="button">New Organization</button>}
      />,
    );

    const group = control(container)!;
    const action = screen.getByRole("button", { name: "New Organization" });
    // Outside the centred track, and a direct child of the bar — so it lands in track 3 by flow
    // and the group's position does not depend on how wide it is.
    expect(group).not.toContainElement(action);
    expect(action.parentElement).toHaveClass("adh-home__toolbar");
  });

  it("puts the group in the same place with and without an action", () => {
    // The centring's whole claim: the hub's bar and a feature site's bar place the chooser
    // identically. In the DOM that is the group being the bar's FIRST child either way — the
    // action appends after it and never displaces it (in a flex row it did, by its own width).
    const bare = render(<WorkspaceBar workspaces={WORKSPACES} selected="mine" onSelect={() => {}} />);
    const bareIndex = [...control(bare.container)!.parentElement!.children].indexOf(
      control(bare.container)!,
    );
    cleanup();

    const withAction = render(
      <WorkspaceBar
        workspaces={WORKSPACES}
        selected="mine"
        onSelect={() => {}}
        action={<button type="button">New Organization</button>}
      />,
    );
    const actionIndex = [...control(withAction.container)!.parentElement!.children].indexOf(
      control(withAction.container)!,
    );

    expect(actionIndex).toBe(bareIndex);
    expect(actionIndex).toBe(0);
  });
});
