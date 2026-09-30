"use client";

import { Award, Cpu, Boxes, Sparkles, Settings, TrendingUp, Waypoints, Zap } from "lucide-react";
import { reportUnexpectedAuthError } from "@agentic-toolkit/auth";
import { isForbidden, useResourceItemQuery } from "@agentic-toolkit/data";
import { gamificationApi, type RealmConfig } from "@agentic-toolkit/data/gamification";
import { StackGroupDetail, type GroupTopicItem, type TopicLeaf } from "@agentic-toolkit/resource";
import {
  CatalogTopicPane,
  EventTypesTopicPane,
  GamificationSettingsTopicPane,
  LevelsTopicPane,
} from "@agentic-toolkit/gamification";
import {
  GameConnectionsPane,
  GameContentPane,
  GameEffectsPane,
  GameEnginePane,
  REALM_CONFIG_CACHE_KEY,
} from "@agentic-toolkit/games";
import { GamingSettingsPane } from "./GamingSettingsPane";

/**
 * Read one product's gaming mode, classifying the failure the same way
 * `RealmSettingsPane`'s own `loadRealmConfig` does — a 403 here means "you can't administer
 * this product's gamification", not an incident.
 *
 * `REALM_CONFIG_CACHE_KEY` (imported above) is `@agentic-toolkit/games`'s canonical, exported
 * constant for this row's cache key — the SAME key `RealmSettingsPane` and `useGameForEcosystem`
 * read/write, so a mode the backend moved when a feature was added or removed is reflected
 * here — and in which members even SHOW — as soon as that entry is refreshed. The LOADER function itself has no such shared export: `useGameForEcosystem.ts`
 * keeps `loadRealmConfig` package-internal (its own `GameSettingsPane` reaches it via a relative
 * import, not the barrel), so this is a private copy of that same handful of lines, same as
 * `RealmSettingsPane`'s.
 */
async function loadRealmConfig(ecosystemId: string): Promise<RealmConfig> {
  try {
    return await gamificationApi.getRealmConfig(ecosystemId);
  } catch (err) {
    if (isForbidden(err)) {
      throw new Error("You don't have access to this product's gaming settings.");
    }
    reportUnexpectedAuthError(err, { feature: "gaming-group", step: "load" });
    throw err instanceof Error ? err : new Error("Failed to load this product's gaming settings.");
  }
}

/** `subLeafFor ? subLeaf : undefined` on every list+detail member below — NOT the bare `subLeaf`
 *  `render` is handed — for the exact reason `BillingGroup.tsx` documents on its Stripe member:
 *  `StackGroupDetail` hands a member a TRUTHY sentinel leaf (`LOCAL_SUBLEAF`) when the host cedes
 *  no deeper URL segment, and a pane that reads that sentinel's truthiness to decide "am I
 *  URL-driven?" would go URL-driven pinned at "nothing selected" forever. `subLeafFor` is
 *  genuinely optional here (products' `renderTopicPane` always supplies it today, per §4.3, but
 *  nothing enforces that a future host will), so this group honors the same contract its member
 *  panes do — check the PROP, not the per-call argument, to tell a real sub-leaf from the
 *  sentinel. */
function subLeafOrUndefined(
  subLeafFor: ((memberId: string) => TopicLeaf) | undefined,
  subLeaf: TopicLeaf,
): TopicLeaf | undefined {
  return subLeafFor ? subLeaf : undefined;
}

/**
 * The products site's Gaming and Gamification groups (design doc §4) — HOST-OWNED
 * `StackGroupDetail`s, not `@agentic-toolkit/ecosystems`'s hardcoded `GROUP_IDS`. They have to be
 * host-owned because the Gaming member list depends on DATA (the realm's `mode`), and the
 * toolkit's own group machinery is static by design (§4.2) — teaching it to read gamification
 * config would put gaming-specific knowledge in a package that has none today.
 *
 * Gaming and Gamification are two features, so two rail rows, each one `part` of this group
 * (Mike, 2026-09-29). Members, Settings always last (§4.2):
 *   - `gamification` → Catalog, Levels, Custom Events, Settings (the realm's settings) — the
 *     feature being held is what shows them, not the realm's mode.
 *   - `gaming`       → Settings alone while `mode` is not `game` (the mode follows the product's
 *     features, so this is the moment between adding Gaming and the realm catching up), then
 *     Engine, Content, Connections, Effects, Settings.
 *
 * Mode defaults to `'none'` while the config is loading or (for a brand-new product) absent, so
 * the Gaming row never flashes the full list before collapsing to one — the common case (most
 * products are not games) renders right the first time.
 */
export function GamingGroup({
  part,
  ecosystemId,
  leaf,
  subLeafFor,
  helpFor,
}: {
  /** Which rail row this is: the Gaming feature's group or the Gamification feature's. */
  part: "gaming" | "gamification";
  ecosystemId?: string;
  /** This group's OWN leaf (which member is active) — cedes the group's own selection to the
   *  host's URL the same way `leaf` does for every other host-owned pane (`RenderTopicPaneCtx`). */
  leaf?: TopicLeaf;
  /** Cedes the segment BELOW the active member to it, so e.g. Content's own list is itself
   *  deep-linkable — the additive toolkit change §4.3 exists for. */
  subLeafFor?: (memberId: string) => TopicLeaf;
  /** The host's `helpFor` closure itself (not a resolved string): this group builds several
   *  members' worth of help text internally, where a host's ordinary `case` arm only ever needs
   *  one. */
  helpFor: (key: string | undefined) => string | undefined;
}) {
  // reportErrors: false — same reasoning as RealmSettingsPane: a 403 here is expected (a viewer
  // who can see the product but not administer its gamification) and is turned into a sentence
  // above, not filed as an incident.
  const { item: config } = useResourceItemQuery<RealmConfig>(
    REALM_CONFIG_CACHE_KEY,
    ecosystemId ?? null,
    loadRealmConfig,
    { reportErrors: false },
  );
  const mode = config?.mode ?? "none";

  const items: GroupTopicItem[] = [];

  if (part === "gaming" && mode === "game") {
    items.push(
      {
        id: "engine",
        label: "Engine",
        icon: <Cpu size={16} aria-hidden />,
        description: "The runtime this game is built for, and its configuration.",
        render: () => (
          <GameEnginePane ecosystemId={ecosystemId} title="Engine" />
        ),
      },
      {
        id: "content",
        label: "Content",
        icon: <Boxes size={16} aria-hidden />,
        description: "The things this game is made of — rooms, spells, items.",
        leadsTo: "list",
        render: (subLeaf) => (
          <GameContentPane
            ecosystemId={ecosystemId}
            title="Content"
            leaf={subLeafOrUndefined(subLeafFor, subLeaf)}
          />
        ),
      },
      {
        id: "connections",
        label: "Connections",
        icon: <Waypoints size={16} aria-hidden />,
        description: "How those things relate to one another.",
        leadsTo: "list",
        render: (subLeaf) => (
          <GameConnectionsPane
            ecosystemId={ecosystemId}
            title="Connections"
            leaf={subLeafOrUndefined(subLeafFor, subLeaf)}
          />
        ),
      },
      {
        id: "effects",
        label: "Effects",
        icon: <Zap size={16} aria-hidden />,
        description: "What happens, and what fires it.",
        leadsTo: "list",
        render: (subLeaf) => (
          <GameEffectsPane
            ecosystemId={ecosystemId}
            title="Effects"
            leaf={subLeafOrUndefined(subLeafFor, subLeaf)}
          />
        ),
      },
    );
  }

  if (part === "gamification") {
    items.push(
      {
        id: "catalog",
        label: "Catalog",
        icon: <Award size={16} aria-hidden />,
        description: "Platform default and realm-defined badges, grouped by line.",
        render: () => <CatalogTopicPane ecosystemId={ecosystemId} />,
      },
      {
        id: "levels",
        label: "Levels",
        icon: <TrendingUp size={16} aria-hidden />,
        description: "The point ladder members climb.",
        render: () => <LevelsTopicPane ecosystemId={ecosystemId} />,
      },
      {
        id: "custom-events",
        label: "Custom Events",
        // gamification's own rail uses Zap for this (features/gamification/src/topics.tsx) —
        // renamed here only because Effects, above, already claims Zap on THIS rail and the two
        // sit in the same list once mode is 'game'. Sparkles keeps the "something bespoke fires"
        // family without colliding.
        icon: <Sparkles size={16} aria-hidden />,
        description: "Realm-defined events this product can post to award points.",
        render: () => <EventTypesTopicPane ecosystemId={ecosystemId} />,
      },
    );
  }

  items.push(
    part === "gamification"
      ? {
          id: "settings",
          label: "Settings",
          icon: <Settings size={16} aria-hidden />,
          description: "Skin, timezone, surfaces and seasons for this product's gamification.",
          render: () => <GamificationSettingsTopicPane ecosystemId={ecosystemId} />,
        }
      : {
          id: "settings",
          label: "Settings",
          icon: <Settings size={16} aria-hidden />,
          description:
            mode === "game"
              ? "Surfaces, seasons and the game's status."
              : "This product's gaming settings.",
          render: () => (
            <GamingSettingsPane ecosystemId={ecosystemId} help={helpFor("ecosystems/gaming/settings")} />
          ),
        },
  );

  return (
    <StackGroupDetail
      levelId={`ecosystem-${part}`}
      title={part === "gaming" ? "Gaming" : "Gamification"}
      items={items}
      urlSelection={{ selectedId: leaf?.leafId ?? null, onSelect: leaf?.onSelect ?? (() => {}) }}
      renderSubLeaf={subLeafFor}
    />
  );
}
