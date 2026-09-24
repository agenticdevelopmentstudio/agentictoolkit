"use client";

import type { ReactElement, ReactNode } from "react";
import { notFound } from "next/navigation";
import { defineSiteHome } from "@agentic-toolkit/adh/home";
import { StorageGroup, type RenderTransferSection } from "@agentic-toolkit/adh-ecosystem-panes";
import { parseStoragePath, type StoragePathSelection } from "@agentic-toolkit/adh-ecosystem-panes/parse";
import { useWorkspaceDefaultEcosystemId } from "@agentic-toolkit/data/ecosystems";
// The panes fetch through the toolkit's react-query cache, which reads the toolkit's OWN
// QueryClient context — mount its provider here (same physical module as the hooks; a
// host-provided QueryClientProvider would be a different copy and invisible to them).
import { ToolkitQueryProvider } from "@agentic-toolkit/data/query";
import { useBasePathRoute } from "@agentic-toolkit/resource";

/**
 * The Storage feature — this site's gated product surface, and the REASON Storage left the hub's
 * workspace rail: agenticdeveloperstorage.com is where you manage buckets now, so the hub stopped
 * offering the topic (see ALL_FEATURES in the hub's workspace-features.ts). This is the SAME
 * @agentic-toolkit/adh-ecosystem-panes StorageGroup the hub's `/<workspace>/storage` route renders
 * — one rail, two hosts. A product's Storage topic looks identical but is NOT this component: it is
 * a list EcosystemsFeature hand-declares, so it carries only the first three members and does not
 * follow this one when a member is added.
 *
 * URL grammar, rooted at the workspace, identical to the hub's:
 *   /<ws> | /<ws>/<memberId> | /<ws>/<memberId>/<entityId>
 * where memberId is buckets | access | all-data | tokens. CLOSED at those forms — an unknown member
 * or a third segment is a 404, not this same pane served at every depth (see `parse`).
 *
 * Host seams:
 * - scope is resolved HERE, from the slug the shell already settled on — the same
 *   `useWorkspaceDefaultEcosystemId` that the hub's own `useDefaultEcosystemId` is a two-line
 *   adapter over, so both hosts reach one resolution and the gate below it stays one decision.
 * - renderTransfer and renderAllData come from the MOUNT ({@link StorageHostSeams}), because
 *   neither can be built here and both can be built by the hub. This site supplies neither, and
 *   that is the honest result rather than a gap: a Transfer Ownership section has to name every
 *   workspace the caller belongs to AND every ecosystem under each, which is the hub's own
 *   workspace API layer; and All Data's package default is right for a site with no rail chrome
 *   of its own to publish the schema ▸ table rails into.
 *
 *   Both were HARDCODED absent until 2026-08-30, and that is what kept the hub on a SECOND mount
 *   of StorageGroup (`src/components/storage/StorageFeature.tsx`) rather than on this model — two
 *   compositions of one rail, agreeing only by review. The seams were optional on StorageGroup
 *   the whole time; what was missing was a way for a host to reach them. See SiteHomeModel.render.
 *
 * This file DECLARES the route; SiteHomeRoute assembles it — reading the `[workspace]` param and
 * the path below it, and mounting what `render` returns inside SiteHomeShell, which resolves the
 * workspace, keeps the URL in step, and renders the chooser in a bar under the header.
 * `scopedBase` arrives already built. Declared here rather than in a page because both
 * `app/[workspace]/[[...path]]` and `app/home` mount it.
 *
 * A client module because a model carries functions, and functions cannot cross from a Server
 * Component into the client shell — see SiteHomeRoute.
 *
 * Auth: both mounts sit under a HomeGate layout.
 */
export const storageHome = defineSiteHome({
  // The grammar is CLOSED at two segments below the workspace, and the first must name a real
  // member. `parse` is where the family says a path does not exist — the same place `noSubPath`
  // says it for a site with no sub-path at all — so the refusal happens above the shell, before
  // the workspace list is fetched and the chooser drawn.
  //
  // Not parsed here but IMPORTED, from the package that owns the rail: the hub's
  // `/<workspace>/storage` mounts the same four members at the same two depths, and a copy per
  // host is what lets one of them start admitting a URL the other 404s. The shared grammar
  // ANSWERS with null rather than calling `notFound()` itself, because its other host is a Server
  // Component that answers a refusal its own way; turning that null into this site's 404 is the
  // one line of it that belongs to a host.
  parse: (segments) => parseStoragePath(segments) ?? notFound(),
  render: ({ scopedBase, workspaceSlug, view }, host: StorageHostSeams) => (
    <ToolkitQueryProvider>
      <StorageHome base={scopedBase} workspaceSlug={workspaceSlug} {...host} {...view} />
    </ToolkitQueryProvider>
  ),
});

/**
 * What a HOST may add to this site's Storage rail. Both fields optional, both absent on
 * agenticdeveloperstorage.com — the model's docstring above says why each is a host's to build
 * and not this package's.
 *
 * The types are StorageGroup's own, re-exported rather than restated: a seam bag that described
 * these props in its own words would be a second declaration of a signature that already exists,
 * free to drift from the component it is handed to.
 */
export interface StorageHostSeams {
  /** Transfer Ownership for an open bucket. Omitted ⇒ an open bucket shows no such section. */
  renderTransfer?: RenderTransferSection;
  /** A host's own All Data member, for a host with rail chrome to publish into. Omitted ⇒ the
   *  package's own local-selection browser. */
  renderAllData?: (ecosystemId: string | undefined) => ReactNode;
}

// The default export is what `app/home/page.tsx` and the workspace route import, so
// those two files can be the same bytes in every site. The named export above is the
// one this module's own documentation refers to; they are the same object.
export default storageHome;

/**
 * A component rather than JSX inline in `render`, because the ecosystem scope and the push
 * helpers are HOOKS, and `render` is a plain function the shell calls — not a component.
 */
function StorageHome({
  base,
  workspaceSlug,
  memberId,
  entityId,
  renderTransfer,
  renderAllData,
}: {
  base: string;
  workspaceSlug: string;
} & StoragePathSelection &
  StorageHostSeams): ReactElement {
  const scope = useWorkspaceDefaultEcosystemId(workspaceSlug);
  // The same push semantics the hub's useFeatureRoute delegates to, against this site's base
  // instead of `/<workspace>/storage`.
  const { pushSegment, pushNested } = useBasePathRoute(base);
  return (
    <StorageGroup
      scope={scope}
      // The slug the shell already settled on, so Tokens mints and lists against the workspace's
      // OWN principal — an org's tokens on an org workspace. `scope` cannot carry it: it is the
      // ecosystem RESOLUTION, which is still in flight on the render this is already known for.
      workspaceSlug={workspaceSlug}
      urlSelection={{ selectedId: memberId, onSelect: pushSegment }}
      renderSubLeaf={(mid) => ({
        leafId: entityId,
        onSelect: (eid) => pushNested(mid, eid),
      })}
      // Undefined on this site, which is StorageGroup's own documented degrade — "no transfer
      // section", "the package's own browser" — and not a missing prop. Forwarding them is the
      // whole reason the hub can mount THIS model instead of composing StorageGroup a second time.
      renderTransfer={renderTransfer}
      renderAllData={renderAllData}
    />
  );
}
