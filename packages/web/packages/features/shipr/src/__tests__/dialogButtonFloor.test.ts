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
 * The attribute each element actually HONOURS — the assertion is the prop name, not the mention.
 *
 * `DialogContent` puts `className` on the surface itself. `AlertModal` has no `className`: it
 * renders its own `DialogContent` and forwards `contentClassName` to it, so
 * `<AlertModal className={SHIPR_DIALOG_SURFACE}>` sets the properties on nothing at all. Asking
 * only whether the constant appeared somewhere in the tag passed that exact line — the one miss
 * this test exists to catch, written in the shape most likely to be typed.
 */
const SURFACE_ATTR: Record<string, string> = {
  "<DialogContent": "className",
  "<AlertModal": "contentClassName",
};

/**
 * The whole opening tag that starts at `at`, or null when it never closes.
 *
 * NOT the text up to the first `>`. In real JSX that `>` is usually the one in an inline `=>`
 * handler a line or two in, which truncated the attribute list and hid every attribute after it
 * — on a multi-line `<AlertModal>`, typically the `contentClassName` being looked for. So a `>`
 * counts only at brace depth zero and outside a string.
 */
function openingTag(text: string, at: number): string | null {
  let depth = 0;
  let quote = "";
  for (let i = at; i < text.length; i++) {
    const c = text[i];
    if (quote) {
      if (c === quote) quote = "";
      continue;
    }
    if (c === '"' || c === "'" || c === "`") quote = c;
    else if (c === "{") depth++;
    else if (c === "}") depth--;
    else if (c === ">" && depth === 0) return text.slice(at, i + 1);
  }
  return null;
}

/** The expression `attr={…}` holds in this opening tag, or null when the tag does not pass it.
 *  Brace-balanced, so a template literal's own `${…}` does not end the value early. The leading
 *  `\s` is what keeps `className` from matching the tail of `contentClassName`. */
function attrExpression(tag: string, attr: string): string | null {
  const opened = new RegExp(`\\s${attr}=\\{`).exec(tag);
  if (!opened) return null;
  const start = opened.index + opened[0].length;
  let depth = 1;
  for (let i = start; i < tag.length; i++) {
    if (tag[i] === "{") depth++;
    else if (tag[i] === "}" && --depth === 0) return tag.slice(start, i);
  }
  return null;
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
      const rel = file.slice(SRC.length + 1);
      for (const [tag, attr] of Object.entries(SURFACE_ATTR)) {
        let at = text.indexOf(tag);
        while (at !== -1) {
          // `<DialogContentFoo` is a different element that happens to share a prefix.
          if (!/[A-Za-z0-9_]/.test(text[at + tag.length] ?? "")) {
            const open = openingTag(text, at);
            if (open === null) {
              missing.push(`${rel}: ${tag} (opening tag never closes)`);
              break;
            }
            const surface = attrExpression(open, attr);
            if (surface === null || !surface.includes("SHIPR_DIALOG_SURFACE")) {
              missing.push(`${rel}: ${tag} wants ${attr}={…SHIPR_DIALOG_SURFACE…}`);
            }
          }
          // Advance past THIS tag's own name. The old bound was the `>` position, which is `-1`
          // for a tag that never closes — and `indexOf(tag, -1)` restarts the search at 0, so the
          // same tag was found again, forever.
          at = text.indexOf(tag, at + tag.length);
        }
      }
    }
    expect(missing).toEqual([]);
  });
});
