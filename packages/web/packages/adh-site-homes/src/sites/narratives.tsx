"use client";

import { defineSiteHome, noSubPath } from "@agentic-toolkit/adh/home";
import { SiteHomePlaceholder } from "@agentic-toolkit/adh/layout";

/**
 * This site's workspace route — `/<workspace>`.
 *
 * Declared here rather than in a page because it is mounted TWICE: at
 * `app/[workspace]/[[...path]]` (the route itself) and at `app/home` (the workspace-less
 * entry every cross-site link names). SiteHomeRoute owns the assembly for both — it reads
 * the workspace segment and mounts what `render` returns inside SiteHomeShell, which
 * fetches the caller's workspaces, resolves the one to use (this URL's segment → their
 * stored preference → their personal workspace), keeps the URL in step, and renders the
 * chooser in a bar under the header.
 *
 * Until 2026-09-18 this rendered `NarrativesFrame` — a same-origin iframe of
 * `public/narratives-app`, the static bundle the narratives CLI publishes. The hub mounted
 * the same model at `/<workspace>/narratives`, so both hosts showed it behind the auth gate
 * and behind the workspace chooser. The bundle is ONE published artifact: every signed-in
 * visitor, in every workspace, in every organization, saw the identical narratives. A
 * workspace chooser above a surface that does not vary by workspace is worse than no
 * chooser — it states a scoping that isn't there. So the embed is gone, along with the
 * machinery that existed only to serve it: the `@agentic-toolkit/narratives` package, its
 * `NarrativesFrame`/`NarrativesFeature` pair, and the inner/outer path grammar whose only
 * job was to mirror the iframe's hash into the outer URL via `replaceState`.
 *
 * What replaces it is the family's placeholder, for the same reason `messages` uses one: the
 * feature is not built yet. It stays registered — in the site registry, in the hub's Plan nav
 * group, in the feature-id lists — because it is coming back, scoped to the workspace it is
 * opened in. When it does, it arrives in this file and the hub gets it without a change.
 *
 * `noSubPath` now, where the old model parsed the segments below the workspace as an inner
 * narrative path: with nothing to deep-link into, a grammar that accepted arbitrary depth
 * would resolve any URL under this route to the same placard.
 *
 * Auth: both mounts sit under a HomeGate layout.
 */
const NARRATIVES_UNSCOPED_BLURB =
  "Narratives is being rebuilt to be scoped to the workspace you're in — the view here was a " +
  "single published bundle that showed every visitor the same stories, whichever user or " +
  "organization they opened it as.";

export const narrativesHome = defineSiteHome({
  // No grammar below the workspace: `/<workspace>` is this site's whole address. `noSubPath`
  // is the family's way of saying so — every site mounts the same optional catch-all, so the
  // depth a site accepts is a line here rather than which directories it happens to have.
  parse: noSubPath,
  render: () => <SiteHomePlaceholder siteId="narratives" blurb={NARRATIVES_UNSCOPED_BLURB} />,
});

// The default export is what `app/home/page.tsx` and the workspace route import, so
// those two files can be the same bytes in every site. The named export above is the
// one this module's own documentation refers to; they are the same object.
export default narrativesHome;
