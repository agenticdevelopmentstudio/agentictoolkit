// Runtime unit tests for the admin users page JOIN (`toUserRows`): capabilities, addresses,
// ecosystem memberships, and the null-defaulting of the customer columns.
//
// The search, pagination, role-filter and sort cases this file used to carry are GONE with the
// code they covered: the page no longer paginates, and `useEditableList` now owns narrowing and
// ordering (see src/components/editable-list/__tests__/use-editable-list.test.ts). What is left is
// the part that is still this module's job — turning four fetch results into one row.
import { describe, expect, it } from "vitest";
import { rdidMapFrom, toUserRows } from "../admin";
import type { UserEcosystem } from "../memberships";

type Customer = Parameters<typeof toUserRows>[0][number];
const user = (o: Partial<Customer> & { id: string }): Customer =>
  ({ email: null, displayName: null, avatarUrl: "", createdAt: "2026-01-01", ...o }) as unknown as Customer;

const eco = (o: Partial<UserEcosystem> & { ecosystemId: string }): UserEcosystem => ({
  customerId: `c-${o.ecosystemId}`,
  rdid: null,
  isHub: false,
  ...o,
});

describe("toUserRows", () => {
  const rows = [
    user({ id: "1", displayName: "Alice", email: "alice@x.com" }),
    user({ id: "2", displayName: "Bob", email: "bob@y.com" }),
    user({ id: "3", displayName: null, email: null }),
  ];
  const caps = [
    { userId: "1", capability: "admin" },
    { userId: "1", capability: "billing" },
    { userId: "2", capability: "support" },
  ];

  it("joins each customer to its capabilities", () => {
    const out = toUserRows(rows, caps);
    expect(out.find((u) => u.id === "1")?.capabilities).toEqual(["admin", "billing"]);
    expect(out.find((u) => u.id === "2")?.capabilities).toEqual(["support"]);
    expect(out.find((u) => u.id === "3")?.capabilities).toEqual([]); // none → empty
  });

  it("defaults nullable customer columns to empty strings", () => {
    const u3 = toUserRows(rows, caps).find((u) => u.id === "3")!;
    expect(u3.email).toBe("");
    expect(u3.name).toBe("");
  });

  it("returns every row, in the order it was given them", () => {
    // The whole list, unnarrowed and unordered — the filtering and sorting the old transform did
    // belongs to the list controller now, and a join that quietly dropped or reordered rows would
    // take that decision back.
    expect(toUserRows(rows, caps).map((u) => u.id)).toEqual(["1", "2", "3"]);
  });
});

describe("toUserRows — rdid column", () => {
  it("joins each user to their address by entity id", () => {
    const rows = [user({ id: "u1", email: "a@t.co" }), user({ id: "u2", email: "b@t.co" })];
    const map = rdidMapFrom([
      { rdid: "user.acme.a", entityType: "customer", entityId: "u1" },
      { rdid: "user.acme.b", entityType: "customer", entityId: "u2" },
    ]);
    expect(toUserRows(rows, [], map).map((u) => u.rdid)).toEqual(["user.acme.a", "user.acme.b"]);
  });

  it("leaves rdid null for a user the registry does not know", () => {
    // A real state, not an error: a customer created before the address was minted has none,
    // and rendering "undefined" in the column would read as a bug in the row rather than a gap.
    expect(toUserRows([user({ id: "u1" })], [], rdidMapFrom([]))[0]!.rdid).toBeNull();
  });

  it("keeps rdid null when no map is supplied at all", () => {
    expect(toUserRows([user({ id: "u1" })], [])[0]!.rdid).toBeNull();
  });
});

describe("toUserRows — ecosystems column", () => {
  it("attaches each user's memberships", () => {
    const memberships = new Map<string, UserEcosystem[]>([
      ["u1", [eco({ ecosystemId: "hub", isHub: true, rdid: "com.hub" }), eco({ ecosystemId: "e2" })]],
    ]);
    const out = toUserRows([user({ id: "u1" }), user({ id: "u2" })], [], undefined, memberships);
    expect(out[0]!.ecosystems.map((e) => e.ecosystemId)).toEqual(["hub", "e2"]);
    // Not undefined: the column renders a list, and a user the lookup said nothing about has an
    // empty one rather than a missing one.
    expect(out[1]!.ecosystems).toEqual([]);
  });

  it("leaves every user's ecosystems empty when the lookup has not landed", () => {
    // The rows arrive before the membership fetch resolves, and the page renders them in that
    // gap — an empty cell, not a crash.
    expect(toUserRows([user({ id: "u1" })], [])[0]!.ecosystems).toEqual([]);
  });
});

describe("rdidMapFrom", () => {
  it("keys by entity id", () => {
    const map = rdidMapFrom([{ rdid: "user.a.b", entityType: "customer", entityId: "u1" }]);
    expect(map.get("u1")).toBe("user.a.b");
  });
});
