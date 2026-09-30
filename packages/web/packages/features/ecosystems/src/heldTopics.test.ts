// The Features list draws what the ecosystem holds, and nothing else — the child "Agentic Developer
// Hub" listed nineteen rows while its Manage features dialog ticked none (Mike, 2026-09-24).
import { describe, it, expect } from "vitest";
import type { ProvisionedFeature } from "@agentic-toolkit/data/ecosystems";
import { heldTopics } from "./heldTopics";

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

  // `provisioning` is in the ecosystem and the dialog ticks it, so the list shows it too — hiding
  // it left a feature stuck in provisioning nowhere on screen but a ticked box. It is MARKED, so
  // the caller shows its status instead of opening onto storage that may not be there.
  it("shows a provisioning row, marked, and still withholds a removed one", () => {
    const got = heldTopics(TOPICS, [row("storage", "provisioning"), row("dashboards", "removed")]);
    expect(ids(got)).toEqual(["storage", "settings"]);
    expect(got.find((t) => t.id === "storage")?.provisioning).toBe(true);
    expect(got.find((t) => t.id === "settings")?.provisioning).toBeUndefined();
  });

  // A group row with one feature active and another provisioning opens normally.
  it("does not mark a row when any of its features is already active", () => {
    const got = heldTopics(TOPICS, [
      row("user-authentication", "provisioning"),
      row("signin-apps", "active"),
    ]);
    expect(ids(got)).toEqual(["authentication", "settings"]);
    expect(got[0]?.provisioning).toBeUndefined();
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
    const got = heldTopics(TOPICS, null);
    expect(ids(got)).toEqual(ids(TOPICS));
    expect(got.some((t) => t.provisioning)).toBe(false);
  });
});
