import { Boxes, Cpu, Settings, Waypoints, Zap } from "lucide-react";
import type { EcosystemsTopicConfig } from "@agentic-toolkit/ecosystems";

/**
 * The games rail for a selected product: Engine, Content, Connections, Effects, then
 * Settings. `overview` is GONE — the game's name/slug/description are the PRODUCT's now
 * (edited under the product's own Settings, a different topic entirely), so
 * there is nothing left for a games-side "Overview" to show. Settings here means the
 * gaming-mode switch plus the game's operational fields (status, character names, event
 * log, retention) — see GameSettingsPane.
 *
 * `EcosystemsTopicConfig` carries no `leadsTo` (unlike the old `ResourceTopic` this
 * replaces) — the games package renders Content/Connections/Effects as list+detail panes
 * "leading to a list" itself (`GameChildPane`'s own `useStackLevel`), so the outer topic
 * row needs no flag to say so; it is only ever a fact about the pane, never the rail.
 *
 * This package is the SSoT for the ids as well as the labels — same contract
 * `GAMIFICATION_TOPICS` has (they are URL segments, so drift here breaks a bookmark).
 */
export const GAME_TOPICS: EcosystemsTopicConfig[] = [
  {
    id: "engine",
    label: "Engine",
    icon: <Cpu size={16} aria-hidden />,
    description: "The runtime this game is built for, and its configuration.",
    dividerAfter: false,
  },
  {
    id: "content",
    label: "Content",
    icon: <Boxes size={16} aria-hidden />,
    description: "The things this game is made of — rooms, spells, items.",
    dividerAfter: false,
  },
  {
    id: "connections",
    label: "Connections",
    icon: <Waypoints size={16} aria-hidden />,
    description: "How those things relate to one another.",
    dividerAfter: false,
  },
  {
    id: "effects",
    label: "Effects",
    icon: <Zap size={16} aria-hidden />,
    description: "What happens, and what fires it.",
    dividerAfter: true,
  },
  {
    id: "settings",
    label: "Settings",
    icon: <Settings size={16} aria-hidden />,
    description: "Turn gaming on or off, and this game's status, character names and event log.",
    dividerAfter: false,
  },
];
