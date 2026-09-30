"use client";

import { useMemo, type ReactNode } from "react";
import { EcosystemsFeature, type RenderTopicPaneCtx } from "@agentic-toolkit/ecosystems";

import { GamificationSettingsTopicPane } from "./RealmSettingsPane";
import { CatalogTopicPane, EventTypesTopicPane, LevelsTopicPane } from "./topic-panes";
import { GAMIFICATION_TOPICS } from "./topics";
import type { GamificationPathSelection } from "./parse-path";

/**
 * The Gamification feature: the workspace's products as the root list, and each product's realm
 * config split across four topics.
 *
 * It is @agentic-toolkit/ecosystems in `listFirst` mode with a different topic set — NOT a second
 * navigator. A product IS an ecosystem: the list, its create flow, the rdid resume key, the
 * breadcrumb, the not-manageable gate and the whole rail stack already exist there and already
 * mean the right things. What is gamification-specific is exactly the four panes below, which is
 * why this file is short: the alternative was ~1600 lines of re-implemented navigation whose only
 * novelty would have been the bugs.
 *
 * `renderTopicPane` claims all four ids, including `settings` — EcosystemsFeature gives the host
 * first refusal on every topic, so "Settings" here is the realm config rather than the ecosystem
 * record. See {@link GAMIFICATION_TOPICS}.
 *
 * The hub mounts this too, as of 2026-08-30, at `/<workspace>/gamification`. That route used to
 * render {@link GamificationPane} against the workspace's own INFRASTRUCTURE ecosystem — one
 * stacked pane, one realm, no list. Its scope is the workspace's PRODUCTS now, which is a change
 * of surface and worth stating plainly: the infra realm's gamification config is no longer at
 * that URL. It is the hub's own rail that says so first — `workspace-features.ts` demoted
 * gamification out of the workspace rail and under Products with the reason "a workspace does not
 * have 'an Auth' or 'a Storage', one of its products does", and a workspace does not have a
 * Gamification either. The route scoped to the infra realm was what that demotion left behind.
 * The hub's /home launcher still embeds the combined pane (EcosystemTopicPanel), so the
 * single-realm arrangement is not gone, only no longer the thing this URL means.
 *
 * The one thing the old route had that this lacked was the help blurb over the realm settings,
 * which is now {@link GamificationFeatureProps.helpFor}.
 */
export interface GamificationFeatureProps extends GamificationPathSelection {
  basePath: string;
  /** The workspace whose products the root list shows. REQUIRED in practice: `listFirst` reads
   *  the workspace-OWNED ecosystems, so without it there is no list to be first. */
  workspaceSlug?: string;
  /**
   * Contextual help lookup, keyed the way the rest of the platform keys it (`ecosystems/<topic>`).
   * Passed down rather than reached for: the sentences are adh's product vocabulary and a portable
   * feature package may not import them, which is why every host that mounts one supplies this.
   *
   * NOT forwarded to EcosystemsFeature, deliberately — that prop is only consulted for its OWN
   * Settings pane, and this feature claims `settings` for the realm config, so the forward would
   * be dead. It is consumed here, by the pane that actually renders a blurb.
   */
  helpFor?: (key: string) => string | undefined;
}

/** Curried on `helpFor` so the identity is stable per lookup rather than per render — the same
 *  shape the Products site's feature-panel renderer uses. */
function gamificationTopicPaneRenderer(
  helpFor: ((key: string) => string | undefined) | undefined,
): (topicId: string, ctx: RenderTopicPaneCtx) => ReactNode {
  return (topicId, ctx) => {
    switch (topicId) {
      case "catalog":
        return <CatalogTopicPane ecosystemId={ctx.ecosystemId} />;
      case "levels":
        return <LevelsTopicPane ecosystemId={ctx.ecosystemId} />;
      case "custom-events":
        return <EventTypesTopicPane ecosystemId={ctx.ecosystemId} />;
      case "settings":
        return (
          <GamificationSettingsTopicPane
            ecosystemId={ctx.ecosystemId}
            // The realm-settings blurb — the one help key the hub's own `/…/gamification` route
            // passed (via GamificationPane) and the one this feature renders. `RealmSettingsPane`
            // shows it as its bar's "?" help; the other three panes have no place for one.
            help={helpFor?.("ecosystems/gamification")}
          />
        );
      default:
        // Nothing else is on this rail. Declining (rather than rendering a placeholder) hands the
        // id back to EcosystemsFeature, so a topic added upstream still gets its own pane.
        return null;
    }
  };
}

export function GamificationFeature({
  basePath,
  workspaceSlug,
  helpFor,
  ...selection
}: GamificationFeatureProps) {
  const renderTopicPane = useMemo(() => gamificationTopicPaneRenderer(helpFor), [helpFor]);
  return (
    <EcosystemsFeature
      basePath={basePath}
      workspaceSlug={workspaceSlug}
      listFirst
      labels={{ singular: "Product", plural: "Products" }}
      topics={GAMIFICATION_TOPICS}
      renderTopicPane={renderTopicPane}
      {...selection}
    />
  );
}
