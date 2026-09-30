// Every topics list closes on Settings, alone under a rule (Mike, 2026-09-24).
import { describe, expect, it } from "vitest";

import { isSettingsTopic, settingsLast } from "../settings-last";

const ids = (topics: readonly { id: string }[]) => topics.map((t) => t.id);
const dividers = (topics: readonly { id: string; dividerAfter?: boolean }[]) =>
  topics.filter((t) => t.dividerAfter).map((t) => t.id);

describe("settingsLast", () => {
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

  // A group member keyed by something else ("gaming-settings") is still the list's Settings.
  it("recognises Settings by its label as well as its id", () => {
    expect(isSettingsTopic({ id: "gaming-settings", label: "Settings" })).toBe(true);
    expect(isSettingsTopic({ id: "gaming-settings", label: "Gaming" })).toBe(false);
    const got = settingsLast([
      { id: "gaming-settings", label: "Settings" },
      { id: "engine", label: "Engine" },
    ]);
    expect(ids(got)).toEqual(["engine", "gaming-settings"]);
    expect(dividers(got)).toEqual(["engine"]);
  });

  it("does not mutate the rows it was given", () => {
    const rows = [{ id: "settings" }, { id: "a" }];
    settingsLast(rows);
    expect(rows).toEqual([{ id: "settings" }, { id: "a" }]);
  });
});
