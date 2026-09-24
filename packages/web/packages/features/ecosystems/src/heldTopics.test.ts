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

  // `provisioning` is in the ecosystem — the dialog ticks it too — so the list draws it.
  it("counts provisioning as held, and removed as not", () => {
    const got = heldTopics(TOPICS, [row("storage", "provisioning"), row("dashboards", "removed")]);
    expect(ids(got)).toEqual(["storage", "settings"]);
  });

  it("an ecosystem holding nothing shows only the unkeyed rows", () => {
    expect(ids(heldTopics(TOPICS, []))).toEqual(["settings"]);
  });

  // In flight: withhold rather than draw every row and yank most of them a tick later.
  it("withholds keyed rows while the read is in flight", () => {
    expect(ids(heldTopics(TOPICS, undefined))).toEqual(["settings"]);
  });

  // A failed read must not make a product look empty.
  it("shows every row when the read failed", () => {
    expect(ids(heldTopics(TOPICS, null))).toEqual(ids(TOPICS));
  });
});
