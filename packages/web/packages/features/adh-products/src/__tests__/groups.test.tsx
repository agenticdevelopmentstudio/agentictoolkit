/// <reference types="@testing-library/jest-dom/vitest" />
//
// The two host-owned groups whose members the rail rows now split or absorb (Mike, 2026-09-29):
// Gaming and Gamification are two features, so two rows, each one `part` of GamingGroup; and
// ApplicationsGroup is ONE list — the applications, and nothing after them (the ecosystem's
// client auth is Users ▸ Authentication). The old `apps/<appId>` and `<appId>/settings` links
// are sent on to `<appId>`, and the old Settings, Client Auth and Users ▸ Settings ids to the list.
import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import type { GroupTopicItem } from "@agentic-toolkit/resource";

vi.mock("@agentic-toolkit/resource", () => ({
  StackGroupDetail: ({
    title,
    items,
    urlSelection,
  }: {
    title: string;
    items: GroupTopicItem[];
    urlSelection: { selectedId: string | null };
  }) => (
    <div data-testid="group" data-title={title} data-selected={urlSelection.selectedId ?? ""}>
      {items.map((i) => (
        <span key={i.id}>{i.id}</span>
      ))}
    </div>
  ),
}));

let mode: "none" | "gamification" | "game" = "none";
vi.mock("@agentic-toolkit/data", () => ({
  isForbidden: () => false,
  useResourceItemQuery: () => ({ item: { mode } }),
}));
vi.mock("@agentic-toolkit/data/gamification", () => ({ gamificationApi: {} }));
vi.mock("@agentic-toolkit/auth", () => ({ reportUnexpectedAuthError: vi.fn() }));
vi.mock("@agentic-toolkit/gamification", () => ({
  CatalogTopicPane: () => null,
  EventTypesTopicPane: () => null,
  GamificationSettingsTopicPane: () => null,
  LevelsTopicPane: () => null,
}));
vi.mock("@agentic-toolkit/games", () => ({
  GameConnectionsPane: () => null,
  GameContentPane: () => null,
  GameEffectsPane: () => null,
  GameEnginePane: () => null,
  REALM_CONFIG_CACHE_KEY: "realm-config",
}));
vi.mock("../GamingSettingsPane", () => ({ GamingSettingsPane: () => null }));
vi.mock("@agentic-toolkit/adh-ecosystem-panes", () => ({
  ApplicationsPane: (props: { leaf?: { leafId: string | null } }) => (
    <div
      data-testid="applications"
      data-selected={props.leaf?.leafId ?? ""}
      data-props={Object.keys(props).sort().join(",")}
    />
  ),
}));

import { GamingGroup } from "../GamingGroup";
import { ApplicationsGroup } from "../ApplicationsGroup";

afterEach(() => {
  cleanup();
  mode = "none";
});

const members = () => [...screen.getByTestId("group").querySelectorAll("span")].map((s) => s.textContent);
const helpFor = () => undefined;

describe("GamingGroup", () => {
  it("gives the Gamification row its own members, whatever the mode", () => {
    render(<GamingGroup part="gamification" ecosystemId="e1" helpFor={helpFor} />);
    expect(screen.getByTestId("group")).toHaveAttribute("data-title", "Gamification");
    expect(members()).toEqual(["catalog", "levels", "custom-events", "settings"]);
  });

  it("gives the Gaming row only Settings until the product is a game", () => {
    mode = "gamification";
    render(<GamingGroup part="gaming" ecosystemId="e1" helpFor={helpFor} />);
    expect(screen.getByTestId("group")).toHaveAttribute("data-title", "Gaming");
    expect(members()).toEqual(["settings"]);
  });

  it("gives a game's Gaming row the engine members, and none of Gamification's", () => {
    mode = "game";
    render(<GamingGroup part="gaming" ecosystemId="e1" helpFor={helpFor} />);
    expect(members()).not.toContain("catalog");
    expect(members()).toContain("engine");
    expect(members().at(-1)).toBe("settings");
  });
});

describe("ApplicationsGroup", () => {
  const pane = () => screen.getByTestId("applications");

  it("is the applications list itself, with nothing after it — no second list", () => {
    render(<ApplicationsGroup ecosystemId="e1" helpFor={helpFor} />);
    expect(screen.queryByTestId("group")).toBeNull();
    expect(pane().getAttribute("data-props")).not.toContain("trailing");
  });

  it.each(["settings", "signin-apps", "auth"])("sends the old %s id on to the list", (old) => {
    const onSelect = vi.fn();
    const subLeafFor = vi.fn(() => ({ leafId: null, onSelect: vi.fn() }));
    render(
      <ApplicationsGroup
        ecosystemId="e1"
        helpFor={helpFor}
        leaf={{ leafId: old, onSelect }}
        subLeafFor={subLeafFor}
      />,
    );
    expect(pane()).toHaveAttribute("data-selected", "");
    expect(onSelect).toHaveBeenCalledWith(null, { replace: true });
    expect(subLeafFor).not.toHaveBeenCalled();
  });

  it("sends an old apps/<appId> link on to the application", () => {
    const onSelect = vi.fn();
    const subLeafFor = vi.fn(() => ({ leafId: "app_123", onSelect: vi.fn() }));
    render(
      <ApplicationsGroup
        ecosystemId="e1"
        helpFor={helpFor}
        leaf={{ leafId: "apps", onSelect }}
        subLeafFor={subLeafFor}
      />,
    );
    expect(subLeafFor).toHaveBeenCalledWith("apps");
    expect(pane()).toHaveAttribute("data-selected", "app_123");
    expect(onSelect).toHaveBeenCalledWith("app_123", { replace: true });
  });

  it("sends an old <appId>/settings link on to the application", () => {
    const onSelect = vi.fn();
    const subLeafFor = vi.fn(() => ({ leafId: "settings", onSelect: vi.fn() }));
    render(
      <ApplicationsGroup
        ecosystemId="e1"
        helpFor={helpFor}
        leaf={{ leafId: "app_9", onSelect }}
        subLeafFor={subLeafFor}
      />,
    );
    expect(subLeafFor).toHaveBeenCalledWith("app_9");
    expect(pane()).toHaveAttribute("data-selected", "app_9");
    expect(onSelect).toHaveBeenCalledWith("app_9", { replace: true });
  });

  it("leaves an application's address alone", () => {
    const id = "app_9";
    const onSelect = vi.fn();
    const subLeafFor = vi.fn(() => ({ leafId: null, onSelect: vi.fn() }));
    render(
      <ApplicationsGroup
        ecosystemId="e1"
        helpFor={helpFor}
        leaf={{ leafId: id, onSelect }}
        subLeafFor={subLeafFor}
      />,
    );
    expect(pane()).toHaveAttribute("data-selected", id);
    expect(onSelect).not.toHaveBeenCalled();
  });
});
