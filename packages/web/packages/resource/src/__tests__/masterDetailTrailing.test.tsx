// @vitest-environment jsdom
/// <reference types="@testing-library/jest-dom/vitest" />
//
// A master/detail list closes on its Settings row: the entities, a divider, then Settings. The
// Applications row is the case that asked for it — ONE list of applications and then Settings,
// never a list holding an "Applications" entry (Mike, 2026-09-29).
import { describe, it, expect, vi } from "vitest";
import { renderHook } from "@testing-library/react";
import { useMasterDetailLevel } from "../master-detail/useMasterDetailLevel";
import type { MasterDetailForm } from "../master-detail/useMasterDetailForm";

type App = { id: string; name: string };
const APPS: App[] = [
  { id: "a1", name: "Website" },
  { id: "a2", name: "iOS" },
];

function fakeForm(selectedId: string | null = null) {
  return {
    selectedId,
    select: vi.fn(),
    actions: { onCancel: vi.fn(), onCreate: vi.fn() },
    creating: false,
    editing: false,
    dirty: false,
    guard: { isDirty: () => false },
  } as unknown as MasterDetailForm<App, App>;
}

function level(opts: {
  form?: MasterDetailForm<App, App>;
  items?: App[] | null;
  trailingSelected?: string | null;
  onTrailing?: (id: string) => void;
  leafOnSelect?: (id: string | null) => void;
}) {
  const form = opts.form ?? fakeForm();
  return renderHook(() =>
    useMasterDetailLevel<App, App>({
      id: "applications-list",
      title: "Applications",
      form,
      items: opts.items === undefined ? APPS : opts.items,
      getId: (a) => a.id,
      getLabel: (a) => a.name,
      newLabel: "New application…",
      publish: false,
      leaf: opts.leafOnSelect ? { leafId: null, onSelect: opts.leafOnSelect } : undefined,
      trailing: {
        items: [{ id: "settings", label: "Settings" }],
        selectedId: opts.trailingSelected ?? null,
        onSelect: opts.onTrailing ?? vi.fn(),
      },
    }),
  ).result.current;
}

describe("useMasterDetailLevel trailing rows", () => {
  it("draws the entities, a divider, then Settings last", () => {
    const l = level({});
    expect(l.items.map((i) => i.id)).toEqual(["a1", "a2", "settings"]);
    expect(l.items[1]).toMatchObject({ dividerAfter: true });
    expect(l.items[0]).not.toHaveProperty("dividerAfter");
  });

  it("still draws Settings while the list is empty or loading", () => {
    expect(level({ items: [] }).items.map((i) => i.id)).toEqual(["settings"]);
    expect(level({ items: null }).items.map((i) => i.id)).toEqual(["settings"]);
  });

  it("routes a Settings click to its own handler, and an entity click to the leaf", () => {
    const onTrailing = vi.fn();
    const leafOnSelect = vi.fn();
    const l = level({ onTrailing, leafOnSelect });
    l.onSelect("settings");
    expect(onTrailing).toHaveBeenCalledWith("settings");
    expect(leafOnSelect).not.toHaveBeenCalled();
    l.onSelect("a2");
    expect(leafOnSelect).toHaveBeenCalledWith("a2");
  });

  it("selects Settings while it is open, and draws no overview over it", () => {
    const l = level({ form: fakeForm("a1"), trailingSelected: "settings" });
    expect(l.selectedId).toBe("settings");
    expect(l.overview).toBe(false);
  });

  it("selects the entity otherwise", () => {
    const l = level({ form: fakeForm("a1") });
    expect(l.selectedId).toBe("a1");
    expect(l.overview).toBeUndefined();
  });
});
