"use client";

import { useMemo, type ReactElement } from "react";
import { defineSiteHome } from "@agentic-toolkit/adh/home";
import { ProductsFeature, type ProductsFeatureProps } from "@agentic-toolkit/adh-products";
import type { EcosystemsPathSelection } from "@agentic-toolkit/ecosystems";
// Grammar from the server-safe ./parse subpath — the ONLY home for parse helpers now
// (the barrels deliberately do not re-export them; see any feature barrel's note).
import { parseEcosystemsPath } from "@agentic-toolkit/ecosystems/parse";
// The feature fetches through the toolkit's react-query cache, which reads the toolkit's OWN
// QueryClient context — mount its provider here (same physical module as the hooks; a
// host-provided QueryClientProvider would be a different copy and invisible to them).
import { ToolkitQueryProvider } from "@agentic-toolkit/data/query";
import { productFeaturePanelRenderer } from "./feature-panels";

/**
 * The Products feature — this site's gated product surface: agenticdeveloperproducts.com is where
 * you manage products. This is the SAME @agentic-toolkit/adh-products surface the hub's
 * `/<workspace>/products` route renders — since 2026-08-30 literally so, because that route mounts
 * THIS model.
 *
 * What used to be claimed here — that Products left the hub's workspace rail and "nothing points
 * at it" — is not what the hub's workspace-features.ts says: `products` is the ANCHOR row the
 * product-scoped segments were demoted under (see NOT_RAIL_FLEET_SEGMENTS' second block, "Scoped
 * to a PRODUCT, so listed under one"). Those eight-plus rows left the rail; Products is what they
 * left it FOR.
 *
 * URL grammar (parseEcosystemsPath), rooted at the workspace:
 *   /<ws> | /<ws>/<productId> | /<ws>/<productId>/<topic>[/<leafId>[/<entityId>]]
 *
 * Seams filled HERE, by the model:
 * - renderFeaturePanel: the feature REQUIRES it — the four ids it does not own (Dashboards /
 *   Billing, the Storage group's All Data member, and Email Signup). See ./feature-panels for
 *   what each is here. A host with its own registry replaces it whole; see
 *   {@link ProductsHostSeams}.
 * - renderTransfer / renderTransferOwnership are NOT supplied, so on this site an open product,
 *   bucket or application shows no Transfer Ownership section. That is the honest result rather
 *   than an omission: building the destination list means naming every workspace the caller
 *   belongs to AND every ecosystem under each, which is the hub's own workspace API layer. Both
 *   are host seams for exactly this case, and the hub fills both.
 *
 * This file DECLARES the route; SiteHomeRoute assembles it — reading the `[workspace]` param and
 * the path below it, and mounting what `render` returns inside SiteHomeShell, which resolves the
 * workspace, keeps the URL in step, and renders the chooser in a bar under the header.
 * `scopedBase` arrives already built. Declared here rather than in a page because both
 * `app/[workspace]/[[...path]]` and `app/home` mount it.
 *
 * A client module for two reasons at once: a host seam is a function, and so are a model's own
 * `parse`/`render` — neither can cross the serialization boundary.
 *
 * Auth: both mounts sit under a HomeGate layout.
 */
export const productsHome = defineSiteHome({
  parse: parseEcosystemsPath,
  render: ({ scopedBase, workspaceSlug, view }, host: ProductsHostSeams) => (
    <ToolkitQueryProvider>
      <ProductsHome base={scopedBase} workspaceSlug={workspaceSlug} {...host} {...view} />
    </ToolkitQueryProvider>
  ),
});

// The default export is what `app/home/page.tsx` and the workspace route import, so
// those two files can be the same bytes in every site. The named export above is the
// one this module's own documentation refers to; they are the same object.
export default productsHome;

/** What a HOST may add to this site's Products surface. */
export interface ProductsHostSeams {
  /**
   * A host's OWN answer to the feature's one required seam, replacing this site's
   * ({@link productFeaturePanelRenderer}) wholesale rather than adding to it.
   *
   * An override and not an addition because the seam is one function over
   * {@link HOST_RENDERED_TOPIC_IDS}, and a host that has real panes for those ids has them for
   * ALL of them: the hub's is its workspace feature-panel registry, where every one of the four
   * is also a rail feature with a route behind it — including `email-signup`, the one pane this
   * site genuinely cannot draw and names an ElsewherePane for. Merging the two would produce a
   * surface that is neither host's.
   */
  renderFeaturePanel?: ProductsFeatureProps["renderFeaturePanel"];
  /** Transfer Ownership for an open bucket or application. Omitted ⇒ no such section — see the
   *  docblock above for why this site omits it. */
  renderTransfer?: ProductsFeatureProps["renderTransfer"];
  /** Transfer Ownership for the PRODUCT itself, on its settings topic. Omitted ⇒ no section. */
  renderTransferOwnership?: ProductsFeatureProps["renderTransferOwnership"];
  labels?: ProductsFeatureProps["labels"];
}

/**
 * A component rather than JSX inline in `render`, because the feature-panel renderer closes over
 * the workspace slug and so has to be memoized — `render` is a plain function the shell calls,
 * not a component, so a hook cannot live there.
 */
function ProductsHome({
  base,
  workspaceSlug,
  renderFeaturePanel: hostFeaturePanel,
  renderTransfer,
  renderTransferOwnership,
  labels,
  ...selection
}: { base: string; workspaceSlug: string } & ProductsHostSeams &
  EcosystemsPathSelection): ReactElement {
  // Built unconditionally, even when the host overrides it: the hook cannot be conditional, and
  // the builder is a closure over one string — cheaper than the branch would be to read.
  const siteFeaturePanel = useMemo(
    () => productFeaturePanelRenderer({ workspaceSlug }),
    [workspaceSlug],
  );
  return (
    <ProductsFeature
      basePath={base}
      workspaceSlug={workspaceSlug}
      renderFeaturePanel={hostFeaturePanel ?? siteFeaturePanel}
      renderTransfer={renderTransfer}
      renderTransferOwnership={renderTransferOwnership}
      labels={labels}
      {...selection}
    />
  );
}
