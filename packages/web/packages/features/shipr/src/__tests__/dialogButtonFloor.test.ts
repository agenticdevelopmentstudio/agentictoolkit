import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { SHIPR_DIALOG_SURFACE } from "../dialogSurface";

const SRC = join(__dirname, "..");

function sources(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    if (e.isDirectory()) return e.name === "__tests__" ? [] : sources(join(dir, e.name));
    return e.name.endsWith(".tsx") ? [join(dir, e.name)] : [];
  });
}

/**
 * EVERY DIALOG SURFACE IN THIS PACKAGE RAISES THE BUTTON FLOOR.
 *
 * The console's dialog buttons were reported as too small, and the fix is a pair of custom
 * properties (`--adh-button-min-*`) that every descendant `Button` reads. A dialog renders into a
 * PORTAL on `document.body`, so it inherits nothing from the console — each surface has to set
 * them itself, and a new dialog that forgets is invisible until somebody notices the buttons in
 * one modal are smaller than in the one behind it.
 *
 * A source check rather than a render, because what is being guarded is a rule about a FILE that
 * does not exist yet. Rendering the eight dialogs there are today would assert nothing about the
 * ninth, which is the only one that will get this wrong.
 */
describe("the shipr dialog button floor", () => {
  it("names a minimum height and width", () => {
    expect(SHIPR_DIALOG_SURFACE).toContain("--adh-button-min-height:");
    expect(SHIPR_DIALOG_SURFACE).toContain("--adh-button-min-width:");
  });

  it("is carried by every DialogContent and AlertModal in the package", () => {
    const missing: string[] = [];
    for (const file of sources(SRC)) {
      const text = readFileSync(file, "utf8");
      // One surface per opening tag; `contentClassName`/`className` may follow on a later line,
      // so each tag is read up to the end of its own attribute list.
      for (const tag of ["<DialogContent", "<AlertModal"]) {
        let at = text.indexOf(tag);
        while (at !== -1) {
          const end = text.indexOf(">", at);
          if (!text.slice(at, end).includes("SHIPR_DIALOG_SURFACE")) {
            missing.push(`${file.slice(SRC.length + 1)}: ${tag}`);
          }
          at = text.indexOf(tag, end);
        }
      }
    }
    expect(missing).toEqual([]);
  });
});
