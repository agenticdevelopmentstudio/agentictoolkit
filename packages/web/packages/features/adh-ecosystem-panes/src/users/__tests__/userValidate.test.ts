// The handle is REQUIRED on create: the backend dropped `customer.customers.slug`'s column
// default (a fabricated `user-3f2a91c0b4de` is a uuid wearing a handle), so a create that
// omits it is refused. Its spec went required with it, and the old `slug || undefined`
// stopped compiling — which is what broke every site's build on 2026-09-24.
import { describe, expect, it } from "vitest";
import { userBlank, userValidate } from "../UserDetail";

describe("userValidate", () => {
  it("refuses a draft without a handle", () => {
    expect(userValidate({ ...userBlank(), email: "jane@example.com" })).toBe(
      "Handle is required.",
    );
  });

  it("refuses a handle that is only whitespace", () => {
    expect(userValidate({ ...userBlank(), email: "jane@example.com", slug: "   " })).toBe(
      "Handle is required.",
    );
  });

  it("accepts a draft with an email and a handle", () => {
    expect(userValidate({ ...userBlank(), email: "jane@example.com", slug: "jane" })).toBeNull();
  });
});
