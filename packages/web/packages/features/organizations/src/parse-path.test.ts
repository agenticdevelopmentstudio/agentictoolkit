import { describe, expect, it } from "vitest";
import { parseOrganizationsPath } from "./parse-path.js";

// This grammar's first segment is an organization SLUG — the only feature whose ResourceExplorer
// id is a name the user chose rather than an opaque row id. Both facts below follow from that,
// and neither is visible in a screenshot.
describe("parseOrganizationsPath", () => {
  it("reads the first segment as the org slug, the second as its topic, the rest untouched", () => {
    expect(parseOrganizationsPath(["acme", "teams", "eng", "members"])).toEqual({
      activeOrgSlug: "acme",
      activeTopic: "teams",
      topicPath: ["eng", "members"],
    });
  });

  it("spends the literal `all` on the landing — which is why no org may be slugged it", () => {
    // The collision this word creates is closed at the MINT boundary, not here: `all` is in
    // RESERVED_ROUTE_SLUGS (backend/src/adh/src/lib/rdid.ts), and
    // <adh-tools>/sites/scripts/verify_reserved_route_slugs.py re-derives it from this file so the two
    // cannot drift. Pinned here so the reason survives beside the code that spends the word.
    expect(parseOrganizationsPath(["all"])).toEqual({ all: true, topicPath: [] });
  });

  it("distinguishes the landing ASKED FOR from the one fallen back to", () => {
    // A bare path is not `all: true` — ResourceExplorer reads the difference (`explicitAll` vs
    // `bare`), so collapsing them would be a behaviour change, not a tidy-up.
    expect(parseOrganizationsPath([])).toEqual({ topicPath: [] });
    expect(parseOrganizationsPath(undefined)).toEqual({ topicPath: [] });
  });

  it("drops empty segments, so a doubled slash cannot shift the slug into the topic slot", () => {
    // Without the filter, `//acme/tokens` parses as the org named "" with topic "acme": a
    //404-looking blank pane rather than the org the URL plainly names.
    expect(parseOrganizationsPath(["", "acme", "tokens"])).toEqual({
      activeOrgSlug: "acme",
      activeTopic: "tokens",
      topicPath: [],
    });
    expect(parseOrganizationsPath(["acme", "", "tokens"])).toEqual({
      activeOrgSlug: "acme",
      activeTopic: "tokens",
      topicPath: [],
    });
    // A trailing slash is the same selection as the tidy URL, not "topic ''".
    expect(parseOrganizationsPath(["acme", ""])).toEqual({
      activeOrgSlug: "acme",
      activeTopic: undefined,
      topicPath: [],
    });
  });

  it("always yields an array below the topic, so a topic can read topicPath[0] unguarded", () => {
    expect(parseOrganizationsPath(["acme"]).topicPath).toEqual([]);
    expect(parseOrganizationsPath(["acme", "settings"]).topicPath).toEqual([]);
  });
});
