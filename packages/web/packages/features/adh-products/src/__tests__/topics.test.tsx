import { describe, it, expect } from "vitest";
import { PRODUCT_TOPICS, HOST_RENDERED_TOPIC_IDS, PLACEHOLDER_TOPIC_IDS } from "../topics";
import { PRODUCT_TOPIC_CONFIGS, productTopicPaneRenderer } from "../ProductsFeature";

// Two invariants that hold the rail together and that nothing else can see: a topic renders a
// BLANK cell when its icon is missing, and a BLANK PANE when no one claims it. Both are legal
// React, so neither tsc nor a screenshot of the topics that DO work says a word.

describe("the product topic rail", () => {
  it("gives every topic an icon", () => {
    const iconless = PRODUCT_TOPIC_CONFIGS.filter((t) => !t.icon).map((t) => t.id);
    expect(iconless).toEqual([]);
  });

  it("carries every topic through to the rail config, in order", () => {
    expect(PRODUCT_TOPIC_CONFIGS.map((t) => t.id)).toEqual(PRODUCT_TOPICS.map((t) => t.id));
    expect(PRODUCT_TOPIC_CONFIGS.map((t) => t.label)).toEqual(PRODUCT_TOPICS.map((t) => t.label));
  });

  it("keeps every dividerAfter, which is what groups the rail visually", () => {
    expect(PRODUCT_TOPIC_CONFIGS.map((t) => t.dividerAfter)).toEqual(
      PRODUCT_TOPICS.map((t) => t.dividerAfter),
    );
  });
});

describe("the host-rendered seam", () => {
  // A POSITIVE assertion about the SETTLED list, not a spot-check of four names: every id a host
  // is told to expect is either a real topic or a GROUP MEMBER — All Data under Storage, Email
  // Signup under Authentication. An id that is neither would be a seam contract for a pane that
  // can never be asked for.
  it("names only real topics (plus the group members that are not ones)", () => {
    const topicIds = new Set<string>(PRODUCT_TOPICS.map((t) => t.id));
    const notATopic = HOST_RENDERED_TOPIC_IDS.filter((id) => !topicIds.has(id));
    expect(notATopic).toEqual(["all-data", "email-signup"]);
  });

  // The other direction, and the one that actually fails on a change: EVERY topic on the rail has
  // to be somebody's. Adding one to PRODUCT_TOPICS without a pane means a row that opens on
  // nothing — legal React, invisible to tsc, and invisible to a screenshot of the rest.
  it("leaves no topic unowned", () => {
    // Claimed by this package's own topic-pane switch — ASKED, not re-listed. A hand-kept copy of
    // the switch's cases only fails when a topic is ADDED, which is the direction that already
    // fails loudly; the direction that fails silently is a case removed or renamed while the rail
    // row stays, because EcosystemsFeature reads the resulting null as "host declines" and hands
    // the id to renderFeaturePanel, where every host's exhaustive default renders the raw string.
    // Asking the real renderer is what makes that show up here.
    const render = productTopicPaneRenderer({ workspaceSlug: "acme" });
    const claims = (id: string) => render(id, { ecosystemId: "eco_1", title: id }) != null;
    const PACKAGE_PANES = PRODUCT_TOPICS.map((t) => t.id).filter(claims);

    // Rendered by EcosystemsFeature itself, asked of NEITHER seam: the three GROUP topics, whose
    // nested sub-rails it owns (their members come back through the seams — Buckets/Access/Users
    // and User Auth/Sign-in apps/Storage Access Tokens to the switch above, All Data and Email
    // Signup to the host), and the product's own entity pane.
    const FEATURE_OWNED = ["storage", "invitations", "authentication", "settings"];
    const owned = new Set<string>([...PACKAGE_PANES, ...FEATURE_OWNED, ...HOST_RENDERED_TOPIC_IDS]);
    const unowned = PRODUCT_TOPICS.map((t) => t.id).filter((id) => !owned.has(id));
    expect(unowned).toEqual([]);

    // And the switch must not claim what the host was promised: an id in both places means the
    // host's pane is dead code it still has to maintain.
    const doubleClaimed = HOST_RENDERED_TOPIC_IDS.filter(claims);
    expect(doubleClaimed).toEqual([]);
  });

  // The seam's own decline rule, which is what makes the test above load-bearing: a claimed topic
  // must return an ELEMENT even when the ecosystem has not resolved yet. Returning null there
  // reads as a decline, and the pane renders the literal topic id instead of blanking.
  it("still claims its topics before the ecosystem id resolves", () => {
    const render = productTopicPaneRenderer({ workspaceSlug: "acme" });
    const withEco = PRODUCT_TOPICS.map((t) => t.id).filter(
      (id) => render(id, { ecosystemId: "eco_1", title: id }) != null,
    );
    for (const id of withEco) {
      expect(render(id, { ecosystemId: undefined, title: id }), id).not.toBeNull();
    }
  });
});

describe("the placeholder topics", () => {
  // The list exists so both hosts DON'T write the same "coming soon" eight times, which only
  // holds while every id on it is a real rail row the package actually answers. An id that is
  // neither is a promise to nobody.
  it("names only real topics", () => {
    const topicIds = new Set<string>(PRODUCT_TOPICS.map((t) => t.id));
    expect(PLACEHOLDER_TOPIC_IDS.filter((id) => !topicIds.has(id))).toEqual([]);
  });

  // Disjoint from the host seam, in both directions: an id in both lists tells the host to build
  // a pane the package will never ask it for, and the host's copy rots unnoticed.
  it("is disjoint from the host-rendered seam", () => {
    const hostRendered = new Set<string>(HOST_RENDERED_TOPIC_IDS);
    expect(PLACEHOLDER_TOPIC_IDS.filter((id) => hostRendered.has(id))).toEqual([]);
  });

  // And the package really does answer them — the whole point of NOT putting them on the seam.
  // A miss here reads as a decline, and the host's exhaustive default renders the raw topic id.
  it("is claimed by the package's own pane renderer", () => {
    const render = productTopicPaneRenderer({ workspaceSlug: "acme" });
    for (const id of PLACEHOLDER_TOPIC_IDS) {
      expect(render(id, { ecosystemId: "eco_1", title: id }), id).not.toBeNull();
    }
  });
});
