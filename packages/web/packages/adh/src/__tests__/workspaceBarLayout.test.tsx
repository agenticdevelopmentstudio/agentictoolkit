/// <reference types="@testing-library/jest-dom/vitest" />
//
// The workspace chooser's PLACEMENT in the bar a feature site's workspace route renders
// (SiteHomeShell's; the hub's switcher lives in its header now). It is centred, and a name too
// long for the bar truncates at the trigger's ellipsis instead of overflowing the bar.
//
// Both are CSS: a flex row that centres its one child, and a `min-width: 0` on that child. jsdom
// resolves no layout, so it cannot see either. What it CAN see is the structure both depend on,
// plus the rules themselves as source text. The picker must be the bar's ONLY child, because a
// sibling would share the row and pull it off centre. It must also be a DIRECT child, because
// `min-width: 0` lands on whatever the bar holds and only helps on the picker's own root. The
// `display: flex` wrapper this replaced carried a `min-width: 0` of its own while the picker's
// root inside it kept its floor, so a long name overflowed the bar (by 200px at a 390px viewport,
// in Chromium). The direct-child assertion fails on that shape.
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, it, expect, afterEach } from "vitest";
import { render, cleanup, screen } from "@testing-library/react";
import { WorkspaceBar } from "../home/WorkspaceBar";
import { WorkspacePicker } from "../home/WorkspacePicker";
import type { WorkspaceOption } from "../home/WorkspaceOption";

afterEach(cleanup);

const WORKSPACES: WorkspaceOption[] = [
  { slug: "mine", name: "My Workspace" },
  { slug: "acme", name: "Acme" },
];

describe("WorkspaceBar layout", () => {
  it("holds the picker as its ONE direct child, with no visible label", () => {
    const { container } = render(
      <WorkspaceBar workspaces={WORKSPACES} selected="mine" onSelect={() => {}} />,
    );
    const bar = container.querySelector(".adh-home__toolbar");
    expect(bar).not.toBeNull();

    // ONE: the row centres what it holds, so any sibling (a label, the old trailing action) would
    // pull the chooser off centre.
    expect(bar!.children).toHaveLength(1);
    expect(bar!.querySelector(".adh-home__toolbar-label")).toBeNull();
    expect(bar!.firstElementChild).toContainElement(
      screen.getByRole("button", { name: "Workspace" }),
    );

    // DIRECT: that child is the picker's own root, not a wrapper of ours around it. The old
    // `.adh-home__toolbar-control` wrapper passes every assertion above and fails this one.
    // Compared against the picker rendered alone rather than against PopupMenu's classes, so
    // this stays a test of the bar and not of PopupMenu's markup.
    const alone = render(
      <WorkspacePicker workspaces={WORKSPACES} selected="mine" onSelect={() => {}} />,
    ).container.firstElementChild!;
    expect(bar!.firstElementChild!.tagName).toBe(alone.tagName);
    expect(bar!.firstElementChild!.className).toBe(alone.className);
  });
});

// jsdom resolves no layout, and vitest hands a CSS import back as an empty string, so the two
// rules the layout rests on are read as source text (the useHeaderLinksCollapsed.test.ts idiom),
// comments stripped so a comment quoting a rule cannot satisfy a match.
describe("the workspace bar's rules", () => {
  const css = readFileSync(
    resolve(import.meta.dirname, "../styles/adh-components.css"),
    "utf8",
  ).replace(/\/\*[\s\S]*?\*\//g, "");

  it("centres its content in a flex row", () => {
    const rule = css.match(/\.adh-home__toolbar\s*\{([^}]*)\}/);
    expect(rule, "no `.adh-home__toolbar {` rule in adh-components.css; did it move?").not.toBeNull();
    expect(rule![1]).toMatch(/display:\s*flex;/);
    expect(rule![1]).toMatch(/justify-content:\s*center;/);
  });

  it("lets its child shrink below the name's width, so a long name truncates", () => {
    // Without it the picker's root floors at the full name: a name wider than the bar overflows
    // both edges of a centred row instead of reaching the trigger's ellipsis.
    expect(css).toMatch(/\.adh-home__toolbar\s*>\s*\*\s*\{[^}]*min-width:\s*0;/);
  });
});
