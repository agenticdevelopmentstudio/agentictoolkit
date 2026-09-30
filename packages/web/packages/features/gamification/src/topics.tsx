import { Award, Settings, TrendingUp, Zap } from "lucide-react";
import type { EcosystemsTopicConfig } from "@agentic-toolkit/ecosystems";

/**
 * The gamification rail for a selected product: the four halves of what used to be one long
 * scrolling pane in the hub, each now its own topic.
 *
 * This package is the SSoT for the ids as well as the labels, because the ids are URL segments:
 * `…/<productId>/levels` has to keep meaning the ladder after the site and the hub have drifted
 * apart. A host spreads this array rather than restating it — the same contract
 * `IN_PACKAGE_TOPICS` has in @agentic-toolkit/ecosystems.
 *
 * `settings` is deliberately the same id the ecosystems package uses for the ecosystem RECORD
 * pane. It is not a collision to route around: on this site the product's record is not on the
 * rail at all, and "Settings" here means the realm config the user came for. EcosystemsFeature
 * gives the host's `renderTopicPane` first refusal on every id precisely so a host can mean its
 * own thing by a shared word.
 */
export const GAMIFICATION_TOPICS: EcosystemsTopicConfig[] = [
  {
    id: "catalog",
    label: "Catalog",
    icon: <Award size={16} aria-hidden />,
    description: "Platform default and realm-defined badges, grouped by line.",
    dividerAfter: false,
  },
  {
    id: "levels",
    label: "Levels",
    icon: <TrendingUp size={16} aria-hidden />,
    description: "The point ladder members climb.",
    dividerAfter: false,
  },
  {
    id: "custom-events",
    label: "Custom Events",
    icon: <Zap size={16} aria-hidden />,
    description: "Realm-defined events this product can post to award points.",
    dividerAfter: true,
  },
  {
    id: "settings",
    label: "Settings",
    icon: <Settings size={16} aria-hidden />,
    description: "Pick a skin, and choose which surfaces show gamification.",
    dividerAfter: false,
  },
];
