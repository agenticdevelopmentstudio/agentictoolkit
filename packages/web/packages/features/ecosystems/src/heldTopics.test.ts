// The Features list draws what the ecosystem holds, and nothing else — the child "Agentic Developer
// Hub" listed nineteen rows while its Manage features dialog ticked none (Mike, 2026-09-24).
import { describe, it, expect } from "vitest";
import type { ProvisionedFeature } from "@agentic-toolkit/data/ecosystems";
import { heldTopics, settingsLast } from "./heldTopics";

const TOPICS = [
  { id: "storage", features: ["storage"] },
  { id: "authentication", features: ["user-authentication", "signin-apps"] },
  { id: "dashboards", features: ["dashboards"] },
  { id: "settings" },
] as const;

const row = (featureKey: string, state: ProvisionedFeature["state"] = "active") =>
  ({ featureKey, state, provisionedAt: "", provisionedBy: null }) as ProvisionedFeature;

const ids = (topics: readonly { id: string }[]) => topics.map((t) => t.id);

describe("heldTopics", () => {
  it("keeps rows with a held feature, and every row that names none", () => {
    expect(ids(heldTopics(TOPICS, [row("storage")]))).toEqual(["storage", "settings"]);
  });

  it("keeps a group row when ANY of its features is held", () => {
    expect(ids(heldTopics(TOPICS, [row("signin-apps")]))).toEqual(["authentication", "settings"]);
  });

  // `provisioning` is in the ecosystem and the dialog ticks it too, but this list draws only what
  // can actually be navigated into — a still-provisioning feature can fail partway and open onto
  // storage that was never created (Mike, 2026-09-25).
  it("withholds a provisioning row, same as a removed one", () => {
    const got = heldTopics(TOPICS, [row("storage", "provisioning"), row("dashboards", "removed")]);
    expect(ids(got)).toEqual(["settings"]);
  });

  it("an ecosystem holding nothing shows only the unkeyed rows", () => {
    expect(ids(heldTopics(TOPICS, []))).toEqual(["settings"]);
  });

  // In flight: withhold rather than draw every row and yank most of them a tick later.
  it("withholds keyed rows while the read is in flight", () => {
    expect(ids(heldTopics(TOPICS, undefined))).toEqual(["settings"]);
  });

  // Except the row the URL names: withholding it too left a deep link to a product feature on
  // "Select a topic to view." for as long as the read took.
  it("keeps the routed row while the read is in flight, and only then", () => {
    expect(ids(heldTopics(TOPICS, undefined, "storage"))).toEqual(["storage", "settings"]);
    // Once the read lands the routed row is held to the same rule as the rest.
    expect(ids(heldTopics(TOPICS, [], "storage"))).toEqual(["settings"]);
    expect(ids(heldTopics(TOPICS, [row("dashboards")], "storage"))).toEqual([
      "dashboards",
      "settings",
    ]);
  });

  // A failed read must not make a product look empty.
  it("shows every row when the read failed", () => {
    expect(ids(heldTopics(TOPICS, null))).toEqual(ids(TOPICS));
  });
});

// Every topics list closes on Settings, alone under a rule (Mike, 2026-09-24).
describe("settingsLast", () => {
  const dividers = (topics: readonly { id: string; dividerAfter?: boolean }[]) =>
    topics.filter((t) => t.dividerAfter).map((t) => t.id);

  it("moves a leading Settings to the end, behind a divider", () => {
    const got = settingsLast([
      { id: "settings", dividerAfter: false },
      { id: "child-ecosystems", dividerAfter: false },
    ]);
    expect(ids(got)).toEqual(["child-ecosystems", "settings"]);
    expect(dividers(got)).toEqual(["child-ecosystems"]);
  });

  // The product rail hangs its divider on Stores; a product without a store drops that row.
  it("draws the divider above Settings whichever row the filter left above it", () => {
    const got = settingsLast([
      { id: "dashboards", dividerAfter: true },
      { id: "billing", dividerAfter: false },
      { id: "settings", dividerAfter: false },
    ]);
    expect(dividers(got)).toEqual(["dashboards", "billing"]);
  });

  it("never ends a list on a divider, and never divides a list that is only Settings", () => {
    expect(dividers(settingsLast([{ id: "a" }, { id: "b", dividerAfter: true }]))).toEqual([]);
    expect(dividers(settingsLast([{ id: "settings", dividerAfter: true }]))).toEqual([]);
  });
});
