// Runtime unit tests for the sync-tables admin API layer. The admin app's test
// harness is node-env vitest for pure transforms + fetch-boundary shaping (see
// vitest.config.ts and users.test.ts) — it has no DOM/testing-library, so this
// exercises the real toggle path at the `authedJson` boundary rather than a
// component render: mock the GET, "toggle" a row (setOverride with the inverted
// flag, exactly as the page's Switch does), and assert the PUT fires with the
// right URL + body AND the row reflects the new state returned by the response.
import { describe, expect, it, vi, beforeEach } from "vitest";

const { authedJson } = vi.hoisted(() => ({ authedJson: vi.fn() }));
vi.mock("../http", () => ({ authedJson }));

import {
  schemaOf,
  syncTablesApi,
  type EnrollmentRow,
} from "../sync-tables";

const row = (o: Partial<EnrollmentRow> & { resource: string }): EnrollmentRow => ({
  scope: "customer",
  pushMode: "generic",
  defaultEnabled: true,
  enabled: true,
  overridden: false,
  ...o,
});

beforeEach(() => authedJson.mockReset());

describe("schemaOf", () => {
  it("reads the schema off the prefix before the first dot", () => {
    expect(schemaOf(row({ resource: "content.feed" }))).toBe("content");
    expect(schemaOf(row({ resource: "social.user_blocks" }))).toBe("social");
  });

  it("takes only the FIRST segment, however many dots follow", () => {
    expect(schemaOf(row({ resource: "persona_memory.links" }))).toBe("persona_memory");
    expect(schemaOf(row({ resource: "content.feed.items" }))).toBe("content");
  });
});

describe("syncTablesApi.get", () => {
  it("unwraps the catalog from the { tables } response", async () => {
    const tables = [row({ resource: "content.feed" })];
    authedJson.mockResolvedValueOnce({ tables });
    await expect(syncTablesApi.get("eco-1")).resolves.toEqual(tables);
    expect(authedJson).toHaveBeenCalledWith("/api/admin/sync/tables/eco-1");
  });
});

describe("toggling a row (setOverride)", () => {
  it("PUTs { enabled: !current } and returns the refreshed catalog reflecting the new state", async () => {
    // The mocked GET: one row currently synced (enabled: true), no override yet.
    const before = row({ resource: "content.feed", enabled: true, overridden: false });
    authedJson.mockResolvedValueOnce({ tables: [before] });
    const loaded = await syncTablesApi.get("eco-1");
    const target = loaded[0]!;

    // The server's authoritative response after the toggle: same row, now off + overridden.
    const after = row({ resource: "content.feed", enabled: false, overridden: true });
    authedJson.mockResolvedValueOnce({ tables: [after] });

    // The page toggles by sending the INVERTED effective flag.
    const refreshed = await syncTablesApi.setOverride(
      "eco-1",
      target.resource,
      !target.enabled,
    );

    // The PUT fired with the right URL and body…
    expect(authedJson).toHaveBeenLastCalledWith(
      "/api/admin/sync/tables/eco-1/content.feed",
      { method: "PUT", body: JSON.stringify({ enabled: false }) },
    );
    // …and the row reflects the new state from the response (not a hand-patch).
    expect(refreshed).toEqual([after]);
    expect(refreshed[0]!.enabled).toBe(false);
    expect(refreshed[0]!.overridden).toBe(true);
  });
});

describe("error propagation (the page's load- and mutation-error branches)", () => {
  // `authedJson` throws on non-2xx; the api layer must let that reject rather
  // than swallow it, so the page's `isError`/mutation-error Alerts actually fire.
  it("get REJECTS when the http boundary throws (failed load)", async () => {
    authedJson.mockRejectedValueOnce(new Error("HTTP 403 Forbidden"));
    await expect(syncTablesApi.get("eco-1")).rejects.toThrow("HTTP 403 Forbidden");
  });

  it("setOverride REJECTS when the http boundary throws (failed toggle)", async () => {
    authedJson.mockRejectedValueOnce(new Error("HTTP 500 Internal Server Error"));
    await expect(
      syncTablesApi.setOverride("eco-1", "content.feed", false),
    ).rejects.toThrow("HTTP 500 Internal Server Error");
  });

  it("clearOverride REJECTS when the http boundary throws (failed reset)", async () => {
    authedJson.mockRejectedValueOnce(new Error("HTTP 409 Conflict"));
    await expect(
      syncTablesApi.clearOverride("eco-1", "content.feed"),
    ).rejects.toThrow("HTTP 409 Conflict");
  });
});

describe("resetting a row (clearOverride)", () => {
  it("DELETEs the override and returns the refreshed catalog reverted to default", async () => {
    const reset = row({
      resource: "content.feed",
      enabled: true,
      defaultEnabled: true,
      overridden: false,
    });
    authedJson.mockResolvedValueOnce({ tables: [reset] });

    const refreshed = await syncTablesApi.clearOverride("eco-1", "content.feed");

    expect(authedJson).toHaveBeenCalledWith("/api/admin/sync/tables/eco-1/content.feed", {
      method: "DELETE",
    });
    expect(refreshed).toEqual([reset]);
    expect(refreshed[0]!.overridden).toBe(false);
  });
});
