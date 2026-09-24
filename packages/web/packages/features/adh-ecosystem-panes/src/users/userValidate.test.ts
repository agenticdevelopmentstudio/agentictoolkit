// `POST /customer/resolve` creates users from an externalId alone, so an SSO/BYO user can have no
// email. Before the stored-email exemption, Save on such a user stayed disabled for any edit at all.
//
// The create and edit cases run through the real `useMasterDetailForm`, wired as `UsersPane` wires
// it, because what `userValidate` is TOLD the stored email is comes from the hook. Calling it by
// hand with no stored email tested a create the hook never made: the hook passed `blank()` as the
// stored record, its "" matched a new user's empty email, and "Email is required." was waived.
import { act, renderHook } from "@testing-library/react";
import { describe, it, expect } from "vitest";
import { useMasterDetailForm } from "@agentic-toolkit/resource";
import type { EcosystemUser, EcosystemUserInput } from "../api/customers";
import { userBlank, userToInput, userValidate } from "./UserDetail";

const SSO_USER: EcosystemUser = {
  id: "sso",
  ecosystemId: "e1",
  // NULL in `customer.customers`, read back as "" by `toUser`.
  email: "",
  displayName: "SSO User",
  externalId: "sso|42",
  slug: "",
  avatarUrl: "",
  createdAt: "c",
  updatedAt: "u",
};

/** `UsersPane`'s form, with the transport stubbed out. */
function useUsersForm() {
  return useMasterDetailForm<EcosystemUser, EcosystemUserInput>({
    items: [SSO_USER],
    getId: (u) => u.id,
    blank: userBlank,
    toInput: userToInput,
    validate: (draft, others, base) =>
      userValidate(draft, others.map((o) => o.email), base?.email),
    differs: (a, b) =>
      (Object.keys(a) as (keyof EcosystemUserInput)[]).some((k) => a[k].trim() !== b[k].trim()),
    create: async (input) => ({ ...SSO_USER, ...input, id: "new" }),
    update: async (id, input) => ({ ...SSO_USER, ...input, id }),
    refresh: () => {},
    createLabel: "New user",
  });
}

describe("userValidate", () => {
  it("lets a user with no stored email be edited", () => {
    const { result } = renderHook(useUsersForm);
    act(() => result.current.select("sso"));
    act(() => result.current.onChange({ ...userToInput(SSO_USER), displayName: "Ada" }));
    expect(result.current.actions.blockedReason).toBeNull();
    expect(result.current.actions.canSave).toBe(true);
  });
  it("still requires an email on create", () => {
    const { result } = renderHook(useUsersForm);
    act(() => result.current.actions.onCreate());
    act(() => result.current.onChange({ ...userBlank(), displayName: "Ada" }));
    expect(result.current.actions.blockedReason).toBe("Email is required.");
    expect(result.current.actions.canSave).toBe(false);
  });
  it("still checks an email the user types", () => {
    expect(userValidate({ ...userBlank(), email: "nope" }, [], "")).toBe("Enter a valid email address.");
    expect(userValidate({ ...userBlank(), email: "a@b.co" }, ["A@b.co"], "")).toMatch(/already exists/);
  });
});
