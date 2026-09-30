// @vitest-environment jsdom
/// <reference types="@testing-library/jest-dom/vitest" />
// The games site's Settings: the Gaming on/off switch first — it adds or removes the Gaming FEATURE,
// and the mode follows the features — then the game's fields, under one DetailsPane bar
// (Mike, 2026-09-29).
import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";

const { push } = vi.hoisted(() => ({ push: vi.fn() }));
vi.mock("next/navigation", () => ({ useRouter: () => ({ push }) }));
vi.mock("@agentic-toolkit/auth", () => ({ reportUnexpectedAuthError: vi.fn() }));

const { forEcosystem, update } = vi.hoisted(() => ({ forEcosystem: vi.fn(), update: vi.fn() }));
vi.mock("@agentic-toolkit/data/games", () => ({ gamesApi: { forEcosystem, update } }));
vi.mock("@agentic-toolkit/data/gamification", () => ({ gamificationApi: {} }));

// The on/off switch is the shared FeatureSwitch (its own test covers the feature write); here it
// stands in as a marker, so what these tests pin is that it is there, and where.
vi.mock("@agentic-toolkit/ecosystems", () => ({
  FeatureSwitch: ({ featureKey, lockedBy }: { featureKey: string; lockedBy?: string }) => (
    <div data-testid={`feature-switch-${featureKey}`} data-locked-by={lockedBy ?? ""} />
  ),
}));

import { GameSettingsTopicPane } from "../GameSettingsPane";

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

const GAME = {
  id: "g1",
  slug: "quest",
  name: "Quest",
  description: "",
  engine: "ink",
  engineConfig: "",
  characterNames: "off",
  status: "active",
  eventLog: "debug",
  eventRetentionDays: 90,
};

describe("GameSettingsPane", () => {
  it("puts the Gaming feature switch before the game's fields", async () => {
    forEcosystem.mockResolvedValue(GAME);
    render(<GameSettingsTopicPane ecosystemId="eco-switch" />);
    const status = await screen.findByLabelText("Status");
    const feature = screen.getByTestId("feature-switch-gaming");
    expect(feature.compareDocumentPosition(status) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it("saves the whole game row through the pane's bar", async () => {
    forEcosystem.mockResolvedValue(GAME);
    update.mockResolvedValue({ ...GAME, status: "hidden" });
    render(<GameSettingsTopicPane ecosystemId="eco-save" />);
    fireEvent.change(await screen.findByLabelText("Status"), { target: { value: "hidden" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await waitFor(() =>
      expect(update).toHaveBeenCalledWith("g1", expect.objectContaining({ status: "hidden", engine: "ink" })),
    );
    await screen.findByText("Saved.");
  });

  it("points at the Gaming feature when no game exists", async () => {
    forEcosystem.mockResolvedValue(null);
    render(<GameSettingsTopicPane ecosystemId="eco-none" />);
    expect(await screen.findByText(/add the Gaming feature to mint one/)).toBeInTheDocument();
  });
});
