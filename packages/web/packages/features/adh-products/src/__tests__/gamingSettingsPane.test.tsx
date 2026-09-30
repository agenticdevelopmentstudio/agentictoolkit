// @vitest-environment jsdom
/// <reference types="@testing-library/jest-dom/vitest" />
// Gaming ▸ Settings: no "Gaming support" dropdown — the mode follows the product's features — but
// the Gaming on/off switch (the FEATURE), then the realm's switches, then the game's status box,
// all under ONE bar (Mike, 2026-09-29).
import type { ReactNode } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";

const { push } = vi.hoisted(() => ({ push: vi.fn() }));
vi.mock("next/navigation", () => ({ useRouter: () => ({ push }) }));
vi.mock("@agentic-toolkit/auth", () => ({ reportUnexpectedAuthError: vi.fn() }));

const { getRealmConfig } = vi.hoisted(() => ({ getRealmConfig: vi.fn() }));
vi.mock("@agentic-toolkit/data/gamification", () => ({ gamificationApi: { getRealmConfig } }));
vi.mock("@agentic-toolkit/data/games", () => ({ gamesApi: { update: vi.fn() } }));

// The two sections stand in as markers: what this pane decides is WHICH show and in what order.
vi.mock("@agentic-toolkit/gamification", () => ({
  RealmSettingsPane: () => <div data-testid="realm-switches" />,
  realmConfigApi: (ecosystemId: string | undefined) => ({
    method: "PUT",
    path: "/gamification/realms/{ecosystemId}/config",
    pathValues: { ecosystemId },
  }),
}));
vi.mock("@agentic-toolkit/games", () => ({
  GAME_FOR_ECOSYSTEM_CACHE_KEY: "game-for-ecosystem",
  REALM_CONFIG_CACHE_KEY: "realm-config",
  GameOperationalFields: () => <div data-testid="game-status" />,
  gameDiffers: () => false,
  gameNormalize: (d: unknown) => d,
  gameToInput: (g: unknown) => g,
  gameValidate: () => null,
  useGameForEcosystem: () => ({ game: { id: "g1" }, error: null }),
}));

// The on/off switch is the shared FeatureSwitch (its own test covers the feature write); here it
// stands in as a marker, so what these tests pin is that it is there, and where.
vi.mock("@agentic-toolkit/ecosystems", () => ({
  FeatureSwitch: ({ featureKey, lockedBy }: { featureKey: string; lockedBy?: string }) => (
    <div data-testid={`feature-switch-${featureKey}`} data-locked-by={lockedBy ?? ""} />
  ),
}));

import { GamingSettingsPane } from "../GamingSettingsPane";

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

function renderPane(ecosystemId: string, mode: string, help?: ReactNode) {
  getRealmConfig.mockResolvedValue({ mode, skin: "rpg", timezone: "UTC", surfaces: {}, seasons: null });
  return render(<GamingSettingsPane ecosystemId={ecosystemId} help={help} />);
}

describe("GamingSettingsPane", () => {
  it("has no Gaming support dropdown", async () => {
    renderPane("eco-dropdown", "game");
    await screen.findByTestId("realm-switches");
    expect(screen.queryByLabelText("Gaming support")).toBeNull();
    expect(screen.queryByRole("combobox")).toBeNull();
  });

  it("puts the switches first and the status box after them, under one bar", async () => {
    renderPane("eco-order", "game");
    const gaming = screen.getByTestId("feature-switch-gaming");
    const switches = await screen.findByTestId("realm-switches");
    const status = await screen.findByTestId("game-status");
    expect(gaming.compareDocumentPosition(switches) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(switches.compareDocumentPosition(status) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(screen.getAllByRole("button", { name: "Save" })).toHaveLength(1);
  });

  it("shows only the realm settings for a gamification product", async () => {
    renderPane("eco-gamification", "gamification");
    await screen.findByTestId("realm-switches");
    expect(screen.queryByTestId("game-status")).toBeNull();
  });

  it("says how to turn gaming on when the product has none", async () => {
    renderPane("eco-none", "none");
    expect(await screen.findByText(/Turn Gaming on above/)).toBeInTheDocument();
    expect(screen.getByTestId("feature-switch-gaming")).toBeInTheDocument();
    expect(screen.queryByTestId("realm-switches")).toBeNull();
  });
});
