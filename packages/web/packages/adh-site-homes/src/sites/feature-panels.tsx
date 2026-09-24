"use client";

import type { ReactNode } from "react";
import dynamic from "next/dynamic";
import { HOST_RENDERED_TOPIC_IDS } from "@agentic-toolkit/adh-products/topics";
// A hook cannot be reached through `next/dynamic`, so this is a static import beside the file's
// other statics — and it has to come from the `/context` subpath, not the barrel. The barrel is one
// bundled module holding all five billing panes plus the integrations pane the Stripe topic
// renders, so a static import of the hook FROM IT would load every one of them on this page,
// leaving the `dynamic()` below deferring nothing.
import { useBillingContext } from "@agentic-toolkit/adh-billing/context";

/**
 * This site's answer to the Products feature's one REQUIRED seam: the panes for the topics
 * @agentic-toolkit/adh-products does not own — {@link HOST_RENDERED_TOPIC_IDS}.
 *
 * The hub answers the same seam with its whole workspace feature-panel registry, because on the
 * hub every one of these ids is ALSO a rail feature with a route of its own. Here there is no
 * such registry and no such route, so this is the list itself — four ids, and the switch is
 * exhaustive over them (the `never` default makes an id added to that list a compile error here,
 * which is the point of the list being exported data rather than a switch's fall-through).
 *
 * Heavy panes stay code-split via next/dynamic, so a product opened on any other topic never
 * ships them.
 */
const loading = () => <p className="p-4 text-sm text-apt-text-muted">Loading…</p>;

const DashboardsFeature = dynamic(
  () => import("@agentic-toolkit/dashboards").then((m) => m.DashboardsFeature),
  { loading },
);
const AllDataPane = dynamic(
  () => import("@agentic-toolkit/adh-ecosystem-panes").then((m) => m.AllDataPane),
  { loading },
);
const BillingGroup = dynamic(
  () => import("@agentic-toolkit/adh-billing").then((m) => m.BillingGroup),
  { loading },
);

type HostRenderedTopicId = (typeof HOST_RENDERED_TOPIC_IDS)[number];

const isHostRendered = (id: string): id is HostRenderedTopicId =>
  (HOST_RENDERED_TOPIC_IDS as readonly string[]).includes(id);

// The return type declares NO `opts`, deliberately, though the seam it satisfies passes one: a
// narrower function is assignable, and this host routes no sub-path for any of the three panes —
// DashboardsFeature keeps its Groups/Sites selection internal in embedded mode, AllDataPane's
// selection is local component state by design, and BillingGroup is mounted without
// `urlSelection` so its member selection stays internal too. Declaring the parameter and then
// dropping it would promise a deep link this site cannot honour; leaving it off says the same
// thing where a reader looks first. Add it back with a pane that reads it.
export function productFeaturePanelRenderer({
  workspaceSlug,
}: {
  workspaceSlug: string;
}): (feature: string, opts?: { ecosystemId?: string }) => ReactNode {
  return function renderProductFeaturePanel(feature, opts) {
    // Anything outside the seam's declared set is the feature asking for a pane it never told
    // this host about. Render the raw id rather than nothing — ugly, but it names itself.
    if (!isHostRendered(feature)) return feature;
    switch (feature) {
      case "dashboards":
        // Embedded mode (no basePath): Groups/Sites selection stays internal, in place — the
        // product's topic rail is never navigated away. The workspace slug owner-scopes every op
        // (an org workspace sees the ORG'S monitored sites), exactly as the hub's embedded mount
        // does.
        //
        // No `reservedSlugs`: that list is the HUB's URL namespace (its `/[slug]` profile
        // routes), and this site does not have one. The sibling agenticdeveloperdashboards.com
        // mount omits it for the same reason.
        //
        // No `renderTransferOwnership`: naming the destination workspaces needs the hub's
        // workspace API layer. Omitted ⇒ no section, which is the seam's own rule.
        return <DashboardsFeature workspaceSlug={workspaceSlug} />;
      case "billing":
        // Embedded mode (no urlSelection): the group's member selection stays internal, in place —
        // the product's topic rail is never navigated away.
        return <ProductBillingPanel workspaceSlug={workspaceSlug} />;
      case "all-data":
        // The Storage group's third member. The package's own browser, with the crud package's
        // DefaultCrudShell: the hub passes a variant only because it has rail chrome of its own
        // to publish the schema ▸ table rails into, and this site has none. The workspace slug
        // confines it to the rows that workspace owns, exactly as the hub's mount does.
        // And the ecosystem whose Storage rail it sits in — the workspace alone spans them all.
        return <AllDataPane workspace={workspaceSlug} ecosystemId={opts?.ecosystemId} />;
      case "email-signup":
        // The Authentication group's fourth member, and the one pane this site genuinely cannot
        // draw: the panel is the hub's, built on hub-local workspace context and API clients, and
        // there is no package to import it from. Say where it lives rather than rendering the raw
        // id (what the `never` default would do) or an empty pane — both of which read as a bug.
        // This case becomes `<EmailSignupPanel/>` the day that panel moves into a package.
        return <ElsewherePane title="Email Signup" where="Agentic Developer Hub" />;
      default: {
        const exhaustive: never = feature;
        return exhaustive;
      }
    }
  };
}

/** A surface that exists, but not on this host. Names both halves — what it is and where it is —
 *  because "not here" without "there" is indistinguishable from "not built". */
function ElsewherePane({ title, where }: { title: string; where: string }): ReactNode {
  return (
    <section className="flex flex-1 flex-col items-center justify-center gap-2 p-8 text-center">
      <h2 className="text-lg font-medium text-apt-text">{title}</h2>
      <p className="max-w-prose text-sm text-apt-text-muted">
        {title} for this product is managed in the {where}.
      </p>
    </section>
  );
}

function ProductBillingPanel({ workspaceSlug }: { workspaceSlug: string }): ReactNode {
  const context = useBillingContext(workspaceSlug);
  return <BillingGroup context={context} />;
}
