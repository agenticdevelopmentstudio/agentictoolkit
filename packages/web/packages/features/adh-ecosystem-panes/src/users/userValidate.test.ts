// `POST /customer/resolve` creates users from an externalId alone, so an SSO/BYO user can have no
// email. Before the stored-email exemption, Save on such a user stayed disabled for any edit at all.
import { describe, it, expect } from "vitest";
import { userBlank, userValidate } from "./UserDetail";

describe("userValidate", () => {
  it("lets a user with no stored email be edited", () => {
    expect(userValidate({ ...userBlank(), displayName: "Ada" }, [], "")).toBeNull();
  });
  it("still requires an email on create", () => {
    expect(userValidate(userBlank(), [])).toBe("Email is required.");
  });
  it("still checks an email the user types", () => {
    expect(userValidate({ ...userBlank(), email: "nope" }, [], "")).toBe("Enter a valid email address.");
    expect(userValidate({ ...userBlank(), email: "a@b.co" }, ["A@b.co"], "")).toMatch(/already exists/);
  });
});
