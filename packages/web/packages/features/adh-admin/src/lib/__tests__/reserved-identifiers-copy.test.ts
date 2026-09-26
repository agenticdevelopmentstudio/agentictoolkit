// The Reserved Identifiers page's operator-facing wording. Asserted because the three release
// reasons do genuinely different things — two delete a mapping, one renames a live row and moves
// its subtree — and a confirmation that describes the wrong one is a real failure, not a typo.
import { describe, expect, it } from "vitest";
import {
  REASONS,
  outcomeDetail,
  outcomeTitle,
  releaseExplanation,
} from "../reserved-identifiers-copy";
import type { ReservedIdentifier } from "../../api/reserved-identifiers";

const item = (o: Partial<ReservedIdentifier>): ReservedIdentifier => ({
  rdid: "storage.acme.notes",
  entityType: "bucket",
  entityId: "b1",
  reason: "deleted-entity",
  heldSince: null,
  releasable: true,
  ...o,
});

describe("releaseExplanation", () => {
  it("says RENAMED, not deleted, when a deleted entity is holding the name", () => {
    const text = releaseExplanation(item({ reason: "deleted-entity" }));
    expect(text).toContain("renamed to a placeholder");
    expect(text).toContain("moves with it");
    expect(text).not.toContain("will be deleted");
  });

  it("says the mapping is deleted for an orphan, and names the missing thing in plain words", () => {
    const text = releaseExplanation(item({ reason: "orphan", entityType: "bucket_type" }));
    expect(text).toContain("bucket type"); // never the raw `bucket_type`
    expect(text).toContain("no longer exists");
    expect(text).toContain("mapping will be deleted");
  });

  it("warns that existing links stop resolving when an old address is released", () => {
    const text = releaseExplanation(item({ reason: "rename-leftover" }));
    expect(text).toContain("stops those links resolving");
  });
});

describe("outcome copy", () => {
  it("reports a clean release as released, with the placeholder it chose", () => {
    const result = {
      rdid: "storage.acme.notes",
      reason: "deleted-entity" as const,
      freed: true,
      placeholder: "released-0123abcd",
      aliasesRemoved: 2,
      stillHeldBy: [],
      children: [],
    };
    expect(outcomeTitle(result)).toBe("Released storage.acme.notes");
    expect(outcomeDetail(result)).toContain("available again");
    expect(outcomeDetail(result)).toContain("released-0123abcd");
  });

  it("does NOT report a partial release as a success, and names what was left", () => {
    const result = {
      rdid: "ecosystem.acme.old",
      reason: "deleted-entity" as const,
      freed: false,
      placeholder: "released-0123abcd",
      aliasesRemoved: 1,
      stillHeldBy: ["persona.acme.old.squatter"],
      children: [],
    };
    expect(outcomeTitle(result)).toBe("Partly released ecosystem.acme.old");
    expect(outcomeDetail(result)).not.toContain("available again");
    expect(outcomeDetail(result)).toContain("persona.acme.old.squatter");
  });
});

describe("REASONS", () => {
  it("gives every reason a label, a blurb and a distinct badge colour", () => {
    const variants = Object.values(REASONS).map((r) => r.variant);
    expect(new Set(variants).size).toBe(variants.length);
    for (const entry of Object.values(REASONS)) {
      expect(entry.label).toBeTruthy();
      expect(entry.blurb).toBeTruthy();
    }
  });
});
