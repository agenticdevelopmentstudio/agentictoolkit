/// <reference types="@testing-library/jest-dom/vitest" />
// A group's sub-rail closes on Settings under a divider like every other topics list, whatever
// order the group authored its members in (Mike, 2026-09-29).
import { render } from "@testing-library/react";
import type { TopicLevel } from "@agenticdevelopertoolkit/ui/blocks";
import { describe, expect, it, vi } from "vitest";

const seen: TopicLevel[][] = [];
vi.mock("../rail-host", () => ({
  StackLevels: ({ levels }: { levels: TopicLevel[] }) => {
    seen.push(levels);
    return null;
  },
}));

import { StackGroupDetail, type GroupTopicItem } from "../group-topic-detail";

const member = (id: string, label: string, extra: Partial<GroupTopicItem> = {}): GroupTopicItem => ({
  id,
  label,
  icon: null,
  render: () => null,
  ...extra,
});

function railRows(items: GroupTopicItem[]) {
  seen.length = 0;
  render(<StackGroupDetail items={items} levelId="g" title="Group" />);
  return seen.at(-1)![0]!.items.map((i) => ({
    id: i.id,
    dividerAfter: i.dividerAfter ?? false,
    dividerLabel: i.dividerLabel,
  }));
}

describe("StackGroupDetail — Settings last, behind a divider", () => {
  it("moves a member labelled Settings to the end and draws the divider above it", () => {
    const rows = railRows([
      member("gaming-settings", "Settings"),
      member("engine", "Engine"),
      member("content", "Content"),
    ]);
    expect(rows.map((r) => r.id)).toEqual(["engine", "content", "gaming-settings"]);
    expect(rows.filter((r) => r.dividerAfter).map((r) => r.id)).toEqual(["content"]);
  });

  it("forwards a member's own divider and caption to the rail", () => {
    const rows = railRows([
      member("a", "A", { dividerAfter: true, dividerLabel: "More" }),
      member("b", "B"),
    ]);
    expect(rows[0]).toEqual({ id: "a", dividerAfter: true, dividerLabel: "More" });
    // Never a line under the last row.
    expect(rows[1]!.dividerAfter).toBe(false);
  });
});
