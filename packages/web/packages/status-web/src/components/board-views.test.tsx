import { describe, expect, it } from "vitest";
import {
  BOARD_PATHS,
  BOARD_VIEWS,
  SETTINGS_SECTIONS,
  entityIdFromPath,
  isBoardPath,
  isRosterTopic,
  sectionFromPath,
  topicFromPath,
  visibleSettingsSections,
  type SettingsSection,
} from "./board-views";

// board-views is the board's routing + role-gate SINGLE SOURCE OF TRUTH: every rail, the
// (board) route group's metadata and the only client-side role gate read it. It is pure
// (path in, decision out) with no DOM, so it is testable exactly where its bugs are —
// which matters because the failure modes here are silent: a section that misses the
// roster set gets no entity list and a dead deep link, and a role gate that leaks reads
// as a working page rather than an error.

describe("topicFromPath", () => {
  it("reads the FIRST segment, so a Settings deep link is still the Settings topic", () => {
    expect(topicFromPath("/settings")).toBe("settings");
    expect(topicFromPath("/settings/sites")).toBe("settings");
    expect(topicFromPath("/settings/sites/site_1")).toBe("settings");
  });

  it("resolves every declared topic, and only those", () => {
    for (const v of BOARD_VIEWS) expect(topicFromPath(`/${v.id}`)).toBe(v.id);
    expect(topicFromPath("/nope")).toBeNull();
  });

  it("has no selection on the landing or the root", () => {
    expect(topicFromPath("/home")).toBeNull();
    expect(topicFromPath("/")).toBeNull();
    expect(topicFromPath("")).toBeNull();
  });

  it("normalizes trailing slashes rather than treating them as a deeper path", () => {
    expect(topicFromPath("/overview/")).toBe("overview");
    expect(topicFromPath("/settings///")).toBe("settings");
  });
});

describe("isBoardPath", () => {
  it("accepts the landing and every topic at any depth", () => {
    expect(isBoardPath("/home")).toBe(true);
    expect(isBoardPath("/settings/sites/site_1")).toBe(true);
    for (const p of BOARD_PATHS) expect(isBoardPath(p)).toBe(true);
  });

  it("rejects anything off the board", () => {
    expect(isBoardPath("/login")).toBe(false);
    expect(isBoardPath("/")).toBe(false);
  });
});

describe("sectionFromPath", () => {
  it("resolves each declared section under /settings", () => {
    for (const s of SETTINGS_SECTIONS) expect(sectionFromPath(`/settings/${s.id}`)).toBe(s.id);
  });

  it("ignores the entity segment", () => {
    expect(sectionFromPath("/settings/sites/site_1")).toBe("sites");
  });

  it("is null off /settings, on bare /settings, and on an unknown section", () => {
    expect(sectionFromPath("/settings")).toBeNull();
    expect(sectionFromPath("/settings/nope")).toBeNull();
    // The retired top-level roster routes must NOT resolve — they are Settings sections
    // now, and a stale bookmark has to land on "nothing selected", not a phantom section.
    expect(sectionFromPath("/sites")).toBeNull();
    expect(sectionFromPath("/overview/sites")).toBeNull();
  });
});

describe("entityIdFromPath", () => {
  it("reads the third segment of a roster path, percent-decoded", () => {
    expect(entityIdFromPath("/settings/sites/site_1")).toBe("site_1");
    expect(entityIdFromPath("/settings/groups/a%20b")).toBe("a b");
  });

  it("is null without a roster section or an id", () => {
    expect(entityIdFromPath("/settings/sites")).toBeNull();
    expect(entityIdFromPath("/settings")).toBeNull();
    expect(entityIdFromPath("/overview")).toBeNull();
  });

  it("ignores a third segment under the LEAF section, which has no entity level", () => {
    expect(entityIdFromPath("/settings/appearance/anything")).toBeNull();
  });

  it("survives a malformed escape rather than throwing at the router", () => {
    expect(entityIdFromPath("/settings/sites/%E0%A4%A")).toBeNull();
  });
});

describe("isRosterTopic", () => {
  it("is true for every section EXCEPT the appearance leaf", () => {
    for (const s of SETTINGS_SECTIONS) {
      expect(isRosterTopic(s.id)).toBe(s.id !== "appearance");
    }
  });

  it("is false for null", () => {
    expect(isRosterTopic(null)).toBe(false);
  });
});

describe("visibleSettingsSections", () => {
  const ids = (role: string | null | undefined): SettingsSection[] =>
    visibleSettingsSections(role).map((s) => s.id);

  it("gives an admin everything", () => {
    expect(ids("admin")).toEqual(SETTINGS_SECTIONS.map((s) => s.id));
  });

  it("leaves a viewer the appearance leaf and NO roster", () => {
    expect(ids("viewer")).toEqual(["appearance"]);
  });

  it("gives an unapproved `pending` account no roster either", () => {
    // The roles are admin | viewer | pending. `pending` is the hole a deny-list leaves:
    // every roster read is admin-gated on the server, so offering one answers 403.
    expect(ids("pending")).toEqual(["appearance"]);
  });

  it("fails CLOSED for an unknown or not-yet-loaded role", () => {
    // BoardShell calls this with `user?.role` while auth is still resolving, so the
    // undefined case is a real render, not a defensive branch.
    expect(ids(undefined)).toEqual(["appearance"]);
    expect(ids(null)).toEqual(["appearance"]);
    expect(ids("some-future-role")).toEqual(["appearance"]);
  });

  it("preserves the declared order, so the rail can't reorder itself per role", () => {
    const declared = SETTINGS_SECTIONS.map((s) => s.id);
    for (const role of ["admin", "viewer", "pending", undefined]) {
      const seen = ids(role);
      expect(seen).toEqual(declared.filter((id) => seen.includes(id)));
    }
  });
});

describe("the section list's own invariants", () => {
  it("is sorted alphabetically by label — the order the file promises", () => {
    const labels = SETTINGS_SECTIONS.map((s) => s.label);
    expect(labels).toEqual([...labels].sort((a, b) => a.localeCompare(b)));
  });

  it("gives every section a description, which the route's metadata reads", () => {
    for (const s of SETTINGS_SECTIONS) expect(s.description.length).toBeGreaterThan(0);
  });

  it("has exactly one leaf section, so a new section defaults to being a roster", () => {
    expect(SETTINGS_SECTIONS.filter((s) => !isRosterTopic(s.id)).map((s) => s.id)).toEqual(["appearance"]);
  });

  it("round-trips every section id through the path parser", () => {
    for (const s of SETTINGS_SECTIONS) {
      const path = `/settings/${s.id}`;
      expect(topicFromPath(path)).toBe("settings");
      expect(sectionFromPath(path)).toBe(s.id);
      expect(isBoardPath(path)).toBe(true);
    }
  });
});
