// The provisioned list is read two ways, and the two differ on purpose: the picker and a product's
// Features list ask what the ecosystem HAS, the hub's rail asks what can be navigated into. Each
// reader used to copy its own filter by hand; these pin the two named reads they share now.
import { describe, expect, it } from "vitest";
import {
  activeFeatureKeys,
  presentFeatureKeys,
  type FeatureState,
  type ProvisionedFeature,
} from "../ecosystem-features";

const row = (featureKey: string, state: FeatureState): ProvisionedFeature => ({
  featureKey,
  state,
  provisionedAt: "",
  provisionedBy: null,
  updatedAt: "",
});

const ROWS = [row("storage", "active"), row("billing", "provisioning"), row("dashboards", "removed")];

describe("presentFeatureKeys", () => {
  // A feature still being built is in the ecosystem: offering it for adding would queue it twice.
  it("counts active and provisioning, and not removed", () => {
    expect([...presentFeatureKeys(ROWS)]).toEqual(["storage", "billing"]);
  });

  it("is empty for an ecosystem holding nothing", () => {
    expect(presentFeatureKeys([]).size).toBe(0);
  });
});

describe("activeFeatureKeys", () => {
  // A provisioning feature can have stopped partway, so a row for it could open onto a pane whose
  // storage is not there.
  it("counts active only", () => {
    expect([...activeFeatureKeys(ROWS)]).toEqual(["storage"]);
  });

  it("is empty for an ecosystem holding nothing", () => {
    expect(activeFeatureKeys([]).size).toBe(0);
  });
});
