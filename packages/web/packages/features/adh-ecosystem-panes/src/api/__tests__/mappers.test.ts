// Runtime unit tests for the pure response→view mapper in ../applications-prototype. These
// verify the field renames, null-defaulting, and enum coercion that sit between the spec-typed
// backend rows and the UI view models — the logic the type system can't check (a wrong rename
// still type-checks).
//
// Moved here from the hub with its subject. The sibling mapper tests (toTeam / toEcosystem /
// monitored-sites) went to @agentic-toolkit/data earlier, each into its own domain's __tests__;
// toApp stayed behind only because applications-prototype was still hub glue, and it no longer is.
import { describe, expect, it } from "vitest";
import { toApp } from "../applications-prototype";

type Row<F extends (arg: never) => unknown> = Parameters<F>[0];
const as = <F extends (arg: never) => unknown>(o: Record<string, unknown>): Row<F> =>
  o as unknown as Row<F>;

describe("toApp", () => {
  it("maps id→id+identifier and displayName→name", () => {
    const a = toApp(
      as<typeof toApp>({
        id: "com.acme.app",
        displayName: "App",
        consumerKind: "staff",
        ecosystemId: "e",
        createdAt: "c",
        updatedAt: "u",
      }),
    );
    expect(a.identifier).toBe("com.acme.app");
    expect(a.name).toBe("App");
  });
  it("maps the platform, defaulting a missing or unknown one to web", () => {
    const row = { id: "i", displayName: "n", consumerKind: "staff", ecosystemId: "e", createdAt: "c", updatedAt: "u" };
    expect(toApp(as<typeof toApp>({ ...row, platform: "native" })).platform).toBe("native");
    expect(toApp(as<typeof toApp>({ ...row, platform: "tv" })).platform).toBe("web");
  });
});
