import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { QueryClient } from "@tanstack/react-query";
import { describe, expect, it } from "vitest";

import {
  ADMIN_QUERY_KEY_PREFIXES,
  ADMIN_STALE_TIME,
  applyAdminQueryDefaults,
} from "../AdminQueryProvider";

const SRC = join(__dirname, "..");

function sourceFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return name === "__tests__" ? [] : sourceFiles(path);
    return /\.tsx?$/.test(name) && !/\.test\.tsx?$/.test(name) ? [path] : [];
  });
}

// The leading string segments of every literal query key in the sources: an array literal right
// after `queryKey:` / `key:`, or one declared `as const` in a key factory (`KEYS.requests`, …) —
// including a factory's `return [...]` and a literal wrapped onto its own line after the `=>`.
function literalKeyHeads(): string[][] {
  const heads: string[][] = [];
  const keyLine = /(?:queryKey:|\bkey:|=>|\breturn|^\s*\w+:|^\s*)\s*\[\s*("[^"]+"(?:\s*,\s*"[^"]+")?)/;
  for (const file of sourceFiles(SRC)) {
    for (const line of readFileSync(file, "utf8").split("\n")) {
      if (!/queryKey:|\bkey: \[|as const/.test(line)) continue;
      const match = keyLine.exec(line);
      if (!match) continue;
      heads.push(match[1].split(",").map((s) => JSON.parse(s.trim()) as string));
    }
  }
  return heads;
}

describe("admin query freshness", () => {
  it("pins every admin key prefix to the admin staleTime", () => {
    const client = applyAdminQueryDefaults(new QueryClient());
    for (const prefix of ADMIN_QUERY_KEY_PREFIXES) {
      expect(client.getQueryDefaults([...prefix, "x"]).staleTime, prefix.join("/")).toBe(
        ADMIN_STALE_TIME,
      );
    }
  });

  it("covers every literal key the panes read under", () => {
    // Fails on the commit that adds a read under a new prefix, which would otherwise quietly fall
    // back to the host's default and behave differently on the hub than on the admin site.
    const heads = literalKeyHeads();
    // The scan must find the keys, or it proves nothing (a guard that cannot find its targets
    // must fail, not pass).
    expect(heads.length).toBeGreaterThan(20);
    const client = applyAdminQueryDefaults(new QueryClient());
    const uncovered = heads.filter(
      (head) => client.getQueryDefaults([...head, "x"]).staleTime !== ADMIN_STALE_TIME,
    );
    expect(uncovered).toEqual([]);
  });

  it("leaves a non-admin read under a shared first word alone", () => {
    const client = applyAdminQueryDefaults(new QueryClient());
    expect(client.getQueryDefaults(["auth", "session"]).staleTime).toBeUndefined();
    expect(client.getQueryDefaults(["system", "status"]).staleTime).toBeUndefined();
  });
});
