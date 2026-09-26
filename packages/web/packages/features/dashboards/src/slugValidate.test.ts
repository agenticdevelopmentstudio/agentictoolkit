// The stored-slug exemption on the group/site validators waives the slug's FORMAT rule only. The
// required-ness rule stays unconditional — `unchangedFromStored("", "")` is true, so an exemption
// that skipped the whole `validateSlug` call let an empty slug save whenever the stored one was
// empty too.
import { describe, it, expect } from "vitest";
import { groupValidate } from "./GroupDetail";
import { siteValidate } from "./SiteDetail";

describe("groupValidate stored-slug exemption", () => {
  const draft = (slug: string) => ({ name: "Group", slug, retentionDays: "30" });

  it("rejects an empty slug even when the stored slug is also empty", () => {
    expect(groupValidate(draft(""), [], undefined, "")).toBe("Slug is required.");
    expect(groupValidate(draft("   "), [], undefined, "")).toBe("Slug is required.");
  });

  it("rejects an empty slug on a create", () => {
    expect(groupValidate(draft(""), [])).toBe("Slug is required.");
  });

  it("still waives the format rule for an unchanged stored slug", () => {
    expect(groupValidate(draft("A_legacy"), [], undefined, "A_legacy")).toBeNull();
    expect(groupValidate(draft("A_legacy"), [])).not.toBeNull();
  });

  it("keeps uniqueness unconditional", () => {
    expect(groupValidate(draft("taken"), ["taken"], undefined, "taken")).toMatch(/already in use/);
  });
});

describe("siteValidate stored-slug exemption", () => {
  const draft = (slug: string) => ({ name: "Site", slug, groupId: "g1" });

  it("rejects an empty slug even when the stored slug is also empty", () => {
    expect(siteValidate(draft(""), [], undefined, "")).toBe("Slug is required.");
  });

  it("still waives the format rule for an unchanged stored slug", () => {
    expect(siteValidate(draft("A_legacy"), [], undefined, "A_legacy")).toBeNull();
  });
});
