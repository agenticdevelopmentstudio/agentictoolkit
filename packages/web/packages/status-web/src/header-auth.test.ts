import { describe, it, expect } from "vitest";
import { fetchStatusUser } from "./header-auth";

// The /api/auth/me semantics that keep a logged-in user logged in across backend
// hiccups: the backend never 401s that route (signed-out is a definitive 200
// { user: null }), so a non-OK response is INFRASTRUCTURE trouble and must throw —
// React Query then keeps the cached session and retries — never read as signed-out.
describe("fetchStatusUser", () => {
  const respond = (body: unknown, status = 200): typeof fetch =>
    (async () => Response.json(body as Record<string, unknown>, { status })) as unknown as typeof fetch;

  it("resolves the user from a definitive 200", async () => {
    const user = { email: "a@b.c", displayName: "A", role: "admin" as const };
    await expect(fetchStatusUser(respond({ user }))).resolves.toEqual(user);
  });

  it("resolves null from a definitive signed-out 200 { user: null }", async () => {
    await expect(fetchStatusUser(respond({ user: null }))).resolves.toBeNull();
  });

  it("THROWS on a 5xx (backend restart / starved proxy) instead of reading it as signed-out", async () => {
    await expect(fetchStatusUser(respond({}, 500))).rejects.toThrow(/HTTP 500/);
  });

  it("propagates a network failure so the cached session is kept", async () => {
    const failing = (async () => {
      throw new TypeError("fetch failed");
    }) as unknown as typeof fetch;
    await expect(fetchStatusUser(failing)).rejects.toThrow(/fetch failed/);
  });
});
