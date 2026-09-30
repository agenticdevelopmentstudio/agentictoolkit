// The feature manager's pure rules. The invariant they exist for: whatever a rail draws, the
// Manage features dialog shows as enabled — the dialog ticks `present`, so every drawn feature row
// must stand on a present key.
import { describe, expect, it } from "vitest";
import type { CatalogFeature, FeatureState, ProvisionedFeature } from "../ecosystem-features";
import {
  featureHoldings,
  featureRowLabel,
  featureRowState,
  featureUnavailableReason,
  featuresAddedWith,
} from "../feature-manager";

const row = (featureKey: string, state: FeatureState): ProvisionedFeature => ({
  featureKey,
  state,
  provisionedAt: "",
  provisionedBy: null,
  updatedAt: "",
});

const ROWS = [row("storage", "active"), row("billing", "provisioning"), row("dashboards", "removed")];

describe("featureHoldings", () => {
  it("splits one list by state, present being everything not removed", () => {
    const h = featureHoldings(ROWS);
    expect([...h.present]).toEqual(["storage", "billing"]);
    expect([...h.active]).toEqual(["storage"]);
    expect([...h.provisioning]).toEqual(["billing"]);
    expect([...h.removed]).toEqual(["dashboards"]);
  });
});

describe("featureRowState", () => {
  const h = featureHoldings(ROWS);

  it("draws a row whose feature is active", () => {
    expect(featureRowState(["storage"], h)).toBe("active");
  });

  it("marks a row whose only held feature is still provisioning", () => {
    expect(featureRowState(["billing"], h)).toBe("provisioning");
  });

  it("hides a removed feature and one never added", () => {
    expect(featureRowState(["dashboards"], h)).toBe("hidden");
    expect(featureRowState(["messaging"], h)).toBe("hidden");
  });

  it("always draws a structural row, which names no feature", () => {
    expect(featureRowState(undefined, h)).toBe("active");
  });

  // The new-ecosystem rule: it holds nothing, so no feature row shows.
  it("hides every feature row of an ecosystem holding nothing", () => {
    const empty = featureHoldings([]);
    for (const key of ["storage", "messaging", "dashboards", "users"]) {
      expect(featureRowState([key], empty)).toBe("hidden");
    }
  });

  // The rail ⊆ dialog invariant, over every state a key can be in.
  it("never draws a feature row the dialog would leave unticked", () => {
    const states: (FeatureState | null)[] = ["active", "provisioning", "removed", null];
    for (const a of states) {
      for (const b of states) {
        const rows = [
          ...(a ? [row("a", a)] : []),
          ...(b ? [row("b", b)] : []),
        ];
        const holdings = featureHoldings(rows);
        for (const features of [["a"], ["b"], ["a", "b"]]) {
          if (featureRowState(features, holdings) === "hidden") continue;
          expect(features.some((k) => holdings.present.has(k)), `${a}/${b} ${features}`).toBe(true);
        }
      }
    }
  });
});

describe("featureRowLabel", () => {
  const catalog = [{ key: "signin-apps", label: "Client Auth" }];

  it("names a one-feature row after the catalog", () => {
    expect(featureRowLabel(["signin-apps"], "Sign-in apps", catalog)).toBe("Client Auth");
  });

  it("keeps its own name for a multi-feature or structural row, or before the catalog loads", () => {
    expect(featureRowLabel(["signin-apps", "users"], "Group", catalog)).toBe("Group");
    expect(featureRowLabel(undefined, "Settings", catalog)).toBe("Settings");
    expect(featureRowLabel(["signin-apps"], "Client Auth", undefined)).toBe("Client Auth");
  });
});

describe("featureUnavailableReason", () => {
  const client = new Map([["organizations", "Only a user's or an organization's own ecosystem can have Organizations."]]);

  it("disables what this ecosystem may not add, with the server's reason", () => {
    const h = featureHoldings([]);
    expect(featureUnavailableReason({ key: "organizations" }, h, client)).toMatch(/own ecosystem/);
    expect(featureUnavailableReason({ key: "messaging", comingSoon: true }, h, client)).toBe("Coming soon.");
    expect(featureUnavailableReason({ key: "storage" }, h, client)).toBeUndefined();
  });

  it("never disables a held feature, so it can still be taken off", () => {
    const h = featureHoldings([row("organizations", "active")]);
    expect(featureUnavailableReason({ key: "organizations" }, h, client)).toBeUndefined();
  });
});

describe("featuresAddedWith", () => {
  const catalog = [
    { key: "gaming", requiresFeatures: ["gamification"] },
    { key: "gamification" },
    { key: "teams", requiresFeatures: ["organizations"] },
    { key: "organizations" },
  ] as unknown as CatalogFeature[];

  it("brings in what a feature requires", () => {
    expect(new Set(featuresAddedWith("gaming", catalog, () => false))).toEqual(new Set(["gaming", "gamification"]));
  });

  it("never brings in one this ecosystem may not add", () => {
    expect(featuresAddedWith("teams", catalog, (k) => k === "organizations")).toEqual(["teams"]);
  });
});
