// `ecosystemUsersApi.update` sends an empty email / external id as NULL, never as ''. The
// (ecosystem_id, email) and (ecosystem_id, external_id) unique indexes admit any number of NULLs
// but a single '', and `toUser` reads NULL back as "" — so a form save that echoed "" turned every
// SSO user without an email into a '' and the second one saved in an ecosystem got a 409.
import { beforeEach, describe, expect, it, vi } from "vitest";

const authedJson = vi.fn();
vi.mock("@agentic-toolkit/auth/client", () => ({
  authedJson: (...args: unknown[]) => authedJson(...args),
  authedRequest: vi.fn(),
}));

import { ecosystemUsersApi } from "../customers";

const ROW = {
  id: "u1",
  ecosystemId: "e1",
  externalId: null,
  email: null,
  displayName: "Ada",
  slug: "ada",
  avatarUrl: "",
  createdAt: "c",
  updatedAt: "u",
};

/** The JSON body of the one PUT the call made. */
function sentBody(): Record<string, unknown> {
  const [, init] = authedJson.mock.calls[0] as [string, RequestInit];
  return JSON.parse(init.body as string) as Record<string, unknown>;
}

beforeEach(() => {
  authedJson.mockReset();
  authedJson.mockResolvedValue(ROW);
});

describe("ecosystemUsersApi.update", () => {
  // NULL, not '': the unique indexes admit any number of NULLs but a single ''.
  it("sends an empty email and external id as NULL", async () => {
    await ecosystemUsersApi.update("u1", {
      email: "",
      displayName: "Ada Lovelace",
      externalId: "",
      slug: "ada",
      avatarUrl: "",
    });
    expect(authedJson).toHaveBeenCalledWith(
      "/api/customer/customers/u1",
      expect.objectContaining({ method: "PUT" }),
    );
    const body = sentBody();
    expect(body.email).toBeNull();
    expect(body.externalId).toBeNull();
  });

  it("leaves the NOT NULL columns as '' — null there would be refused", async () => {
    await ecosystemUsersApi.update("u1", { email: "", avatarUrl: "", slug: "ada" });
    const body = sentBody();
    expect(body.avatarUrl).toBe("");
    expect(body.slug).toBe("ada");
  });

  it("sends a real address and external id unchanged", async () => {
    await ecosystemUsersApi.update("u1", { email: "ada@example.com", externalId: "sso|42" });
    const body = sentBody();
    expect(body.email).toBe("ada@example.com");
    expect(body.externalId).toBe("sso|42");
  });

  it("still omits a field the caller did not send", async () => {
    await ecosystemUsersApi.update("u1", { displayName: "Ada" });
    const body = sentBody();
    // `compact` drops undefined, so an absent field stays absent — NOT null, which would clear it.
    expect("email" in body).toBe(false);
    expect("externalId" in body).toBe(false);
  });

  it("reads a NULL email back as the form's empty string", async () => {
    const user = await ecosystemUsersApi.update("u1", { displayName: "Ada" });
    expect(user.email).toBe("");
    expect(user.externalId).toBe("");
  });
});
