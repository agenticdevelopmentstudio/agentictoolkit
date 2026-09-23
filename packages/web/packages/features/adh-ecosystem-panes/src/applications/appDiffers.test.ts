// The same grants in a different key or list order are not an edit; Save must stay dark.
import { describe, it, expect } from "vitest";
import { appDiffers } from "./ApplicationsPane";
import { appBlank } from "./ApplicationDetail";
import { newSchemaGrant } from "./permission-model";

describe("appDiffers", () => {
  const a = newSchemaGrant("a");
  const b = newSchemaGrant("b");
  it("ignores grant order and object key order", () => {
    const left = { ...appBlank(), schemaGrants: [a, b] };
    const reordered = {
      ...appBlank(),
      schemaGrants: [b, { tables: a.tables, permissions: a.permissions, schemaId: "a" }],
    };
    expect(appDiffers(left, reordered)).toBe(false);
  });
  it("still sees a real grant change", () => {
    const left = { ...appBlank(), schemaGrants: [a] };
    expect(appDiffers(left, { ...appBlank(), schemaGrants: [a, b] })).toBe(true);
  });
});
