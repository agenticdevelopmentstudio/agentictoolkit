// @vitest-environment jsdom
/// <reference types="@testing-library/jest-dom/vitest" />
// The realm settings have no mode control — the mode follows the ecosystem's features — but they do
// have the Gamification on/off switch, which adds or removes the FEATURE; and they save through ONE
// DetailsPane bar, whether they draw that pane themselves or sit in a bigger one (Mike, 2026-09-29).
import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { DetailsPane, SettingsDirtyProvider } from "@agentic-toolkit/resource";

vi.mock("@agentic-toolkit/auth", () => ({ reportUnexpectedAuthError: vi.fn() }));
const { push } = vi.hoisted(() => ({ push: vi.fn() }));
vi.mock("next/navigation", () => ({ useRouter: () => ({ push }) }));

const { getRealmConfig, updateRealmConfig } = vi.hoisted(() => ({
  getRealmConfig: vi.fn(),
  updateRealmConfig: vi.fn(),
}));
vi.mock("@agentic-toolkit/data/gamification", () => ({
  gamificationApi: { getRealmConfig, updateRealmConfig },
}));

// The on/off switch is the shared FeatureSwitch (its own test covers the feature write); here it
// stands in as a marker, so what these tests pin is that it is there, and where.
vi.mock("@agentic-toolkit/ecosystems", () => ({
  FeatureSwitch: ({ featureKey, lockedBy }: { featureKey: string; lockedBy?: string }) => (
    <div data-testid={`feature-switch-${featureKey}`} data-locked-by={lockedBy ?? ""} />
  ),
}));

import { RealmSettingsPane } from "./RealmSettingsPane";

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

const CONFIG = {
  mode: "gamification",
  skin: "rpg",
  timezone: "UTC",
  surfaces: {},
  seasons: null,
};

const saveButton = () => screen.getByRole("button", { name: "Save" });

describe("RealmSettingsPane", () => {
  it("has no mode switch, and puts the Gamification feature switch first", async () => {
    getRealmConfig.mockResolvedValue(CONFIG);
    render(
      <SettingsDirtyProvider>
        <RealmSettingsPane ecosystemId="eco-no-switch" />
      </SettingsDirtyProvider>,
    );
    const timezone = await screen.findByLabelText("Timezone");
    expect(screen.queryByLabelText("Enable gamification")).toBeNull();
    const feature = screen.getByTestId("feature-switch-gamification");
    // Gaming brings gamification with it, so Gaming holds this switch on.
    expect(feature).toHaveAttribute("data-locked-by", "gaming");
    expect(feature.compareDocumentPosition(timezone) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it("standing alone, draws its own bar and saves only what changed", async () => {
    getRealmConfig.mockResolvedValue(CONFIG);
    updateRealmConfig.mockResolvedValue({ config: { ...CONFIG, timezone: "Asia/Tokyo" }, replayed: null });
    render(
      <SettingsDirtyProvider>
        <RealmSettingsPane ecosystemId="eco-standalone" />
      </SettingsDirtyProvider>,
    );
    fireEvent.change(await screen.findByLabelText("Timezone"), { target: { value: "Asia/Tokyo" } });
    expect(saveButton()).toBeEnabled();
    fireEvent.click(saveButton());
    await waitFor(() =>
      expect(updateRealmConfig).toHaveBeenCalledWith("eco-standalone", { timezone: "Asia/Tokyo" }),
    );
    await screen.findByText("Saved.");
  });

  it("inside a bigger pane, is one section of that pane's bar rather than a bar of its own", async () => {
    getRealmConfig.mockResolvedValue(CONFIG);
    updateRealmConfig.mockRejectedValue(new Error("Realm is locked."));
    render(
      <SettingsDirtyProvider>
        <DetailsPane title="Outer" hoist={false}>
          <RealmSettingsPane ecosystemId="eco-nested" />
        </DetailsPane>
      </SettingsDirtyProvider>,
    );
    fireEvent.change(await screen.findByLabelText("Timezone"), { target: { value: "Asia/Tokyo" } });
    expect(screen.getAllByRole("button", { name: "Save" })).toHaveLength(1);
    fireEvent.click(saveButton());
    // The section throws; the outer pane reports it.
    expect(await screen.findByText("Realm is locked.")).toBeInTheDocument();
  });

  it("blocks Save while a season window is invalid", async () => {
    getRealmConfig.mockResolvedValue(CONFIG);
    render(
      <SettingsDirtyProvider>
        <RealmSettingsPane ecosystemId="eco-seasons" />
      </SettingsDirtyProvider>,
    );
    fireEvent.click(await screen.findByRole("switch", { name: "Seasons" }));
    expect(saveButton()).toBeDisabled();
  });
});
