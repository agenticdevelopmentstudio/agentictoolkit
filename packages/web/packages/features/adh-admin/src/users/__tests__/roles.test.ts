import { describe, expect, it } from "vitest";
import type { AdminUserSummary } from "../../api/admin";
import { NO_ROLE, roleLabel, roleValues } from "../roles";

const user = (capabilities: string[]): AdminUserSummary =>
  ({ capabilities }) as AdminUserSummary;

describe("roleLabel", () => {
  it("names the synthetic role for a user holding nothing", () => {
    expect(roleLabel(user([]))).toBe(NO_ROLE);
  });

  it("sorts before joining, so grant order does not change the sort key", () => {
    // The set is what the operator sees; the order the grants happened to arrive in is not part
    // of it, and two users holding the same roles must compare equal.
    expect(roleLabel(user(["billing", "admin"]))).toBe(roleLabel(user(["admin", "billing"])));
  });
});

describe("roleValues", () => {
  it("offers the synthetic role rather than nothing, so 'no roles' is filterable", () => {
    expect(roleValues(user([]))).toEqual([NO_ROLE]);
  });

  it("offers every capability held", () => {
    expect(roleValues(user(["admin", "billing"]))).toEqual(["admin", "billing"]);
  });
});
