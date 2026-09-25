// A bucket's own checks stop at its name and slug. Its tables are checked one at a time, by
// tableNameValidate, as each is added or edited — never as a list Settings cannot show.
import { describe, expect, it } from "vitest";
import { schemaValidate, tableNameValidate } from "./SchemaDefinitionDetail";

const table = (id: string, name: string) => ({ id, name, type: "content.contacts" });
const draft = { name: "Customer CRM", slug: "crm", description: "", tables: [] };

describe("schemaValidate", () => {
  it("does not look at the tables", () => {
    const tables = [table("t-1", "people"), table("t-2", "People"), table("t-3", "")];
    expect(schemaValidate({ ...draft, tables })).toBeNull();
  });

  it("still refuses a blank name, and a slug another bucket has", () => {
    expect(schemaValidate({ ...draft, name: "  " })).toBe("Name is required.");
    expect(schemaValidate(draft, [{ name: "Leads", slug: "crm" }])).toBe(
      'A bucket with the slug "crm" already exists.',
    );
  });
});

describe("tableNameValidate", () => {
  const tables = [table("t-1", "people")];

  it("refuses a blank name, and one another table has in any case", () => {
    expect(tableNameValidate("  ", tables)).toBe("Name is required.");
    expect(tableNameValidate("People", tables)).toBe(
      'A table named "People" already exists in this bucket.',
    );
  });

  it("accepts a name no other table has", () => {
    expect(tableNameValidate("leads", tables)).toBeNull();
  });
});
