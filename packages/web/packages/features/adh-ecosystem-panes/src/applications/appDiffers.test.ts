// The same grants in a different key or list order are not an edit; Save must stay dark.
import { describe, it, expect } from "vitest";
import { appDiffers } from "./ApplicationsPane";
import { appBlank } from "./ApplicationDetail";
import { newSchemaGrant, noAccess, readOnly, type SchemaGrant } from "./permission-model";

const app = (schemaGrants: SchemaGrant[]) => ({ ...appBlank(), schemaGrants });

/** A grant with two tables, built afresh on every call so no two share an object — the compare
 *  has to find them equal by value, not by identity. (`readOnly()` and `noAccess()` return a new
 *  object per call, which is what keeps that true of the tables' permissions too.) */
function tabled(): SchemaGrant {
  return {
    schemaId: "s",
    permissions: { create: false, read: true, update: true, delete: false },
    tables: {
      t1: { level: "table", permissions: readOnly() },
      t2: { level: "row", permissions: noAccess() },
    },
  };
}

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

  it("finds equal copies equal, in any list order and any table insertion order", () => {
    // The edit-and-undo case: the same map rebuilt with its keys inserted the other way round.
    const rebuilt = tabled();
    rebuilt.tables = { t2: rebuilt.tables.t2!, t1: rebuilt.tables.t1! };
    expect(appDiffers(app([tabled(), a]), app([newSchemaGrant("a"), rebuilt]))).toBe(false);
  });

  // `dirty` calls this on every render, and an unedited draft holds its base's grants array (by
  // reference, from `appToInput`). That must cost nothing: a proxy that throws on ANY read —
  // `length` included — proves the grants are not walked at all.
  it("reads nothing when the draft still holds its base's grants", () => {
    const untouchable = new Proxy([a, b], {
      get() {
        throw new Error("the grants were read");
      },
    });
    expect(appDiffers(app(untouchable), app(untouchable))).toBe(false);
  });

  it("stops at the first grant that differs", () => {
    const edited = [{ ...a, permissions: { ...a.permissions, update: true } }, b];
    Object.defineProperty(edited, 1, {
      get() {
        throw new Error("read past the first difference");
      },
    });
    expect(appDiffers(app([a, b]), app(edited))).toBe(true);
  });

  it.each<[string, (g: SchemaGrant) => void]>([
    ["a schema-level permission", (g) => void (g.permissions.delete = true)],
    ["a table-level permission", (g) => void (g.tables.t1!.permissions.create = true)],
    ["a table's level", (g) => void (g.tables.t1!.level = "row")],
    ["an added table", (g) => void (g.tables.t3 = g.tables.t2!)],
    ["a removed table", (g) => void delete g.tables.t2],
    // Same COUNT of tables, so a compare of key counts alone would call these equal.
    ["a table swapped for another", (g) => void ((g.tables.t3 = g.tables.t2!), delete g.tables.t2)],
  ])("sees %s change", (_what, edit) => {
    const edited = tabled();
    edit(edited);
    expect(appDiffers(app([tabled()]), app([edited]))).toBe(true);
  });

  it("sees a different grant set of the same size", () => {
    expect(appDiffers(app([a]), app([b]))).toBe(true);
    expect(appDiffers(app([a, b]), app([newSchemaGrant("c"), a]))).toBe(true);
  });
});
