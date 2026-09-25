import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("../../http", async (orig) => ({
  ...(await orig<Record<string, unknown>>()),
  authedJson: vi.fn(),
  authedRequest: vi.fn(),
}));

import { authedJson } from "../../http";
import { schemasApi } from "../schemas";

// A bucket row with no `slug` — the hub's bucket-types e2e fixture was one — reached
// schemaValidate's `draft.slug.trim()` the moment the bucket was opened, and the TypeError took
// the Buckets pane down with it. The row maps to an empty slug instead, the same way a row with no
// `kind` maps to "custom".

const json = vi.mocked(authedJson);

beforeEach(() => json.mockReset());

describe("schemasApi — a bucket row without a slug", () => {
  it("maps to an empty slug, never undefined", async () => {
    json
      .mockResolvedValueOnce([
        {
          id: "b-1",
          ecosystemId: "eco-uuid",
          name: "mybucket",
          metadata: null,
          createdAt: "2026-01-01T00:00:00Z",
          updatedAt: "2026-01-01T00:00:00Z",
        },
      ])
      .mockResolvedValueOnce([]);
    const [bucket] = await schemasApi.list("eco-uuid");
    expect(bucket).toMatchObject({ slug: "", kind: "custom" });
  });
});
