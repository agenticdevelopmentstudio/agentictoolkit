"use client";

import type { ReactNode } from "react";
import { SettingsDirtyProvider } from "@agentic-toolkit/resource";

import { BackfillSection } from "./BackfillSection";
import { CatalogSection } from "./CatalogSection";
import { EventTypesSection } from "./EventTypesSection";
import { LevelsSection } from "./LevelsSection";
import { RealmCatalogProvider } from "./realm-catalog";

/**
 * The gamification site's four topic panes — one section each, in its own scroller.
 *
 * Two things every pane here has to supply that the hub's combined pane supplies once:
 *
 * - **A scroller.** A topic pane is handed the detail column at whatever height the rail gives
 *   it; without `min-h-0 … overflow-y-auto` a long badge list grows the column instead of
 *   scrolling inside it. `RealmSettingsPane` draws its own DetailsPane (one bar over a scrolling
 *   body), so the Settings topic is not wrapped here.
 * - **A {@link SettingsDirtyProvider}.** It must sit INSIDE the rail host `ResourceExplorer`
 *   mounts — outside it, `useRailExitGuard` finds no host and a rail row switch never learns the
 *   pane is dirty. One per pane rather than one around the feature, and safe either way: a
 *   provider nested inside another defers to it, which is what keeps the hub (whose chrome
 *   already has one) unchanged.
 */

function TopicScroller({ children }: { children: ReactNode }) {
  return (
    <div className="min-h-0 flex-1 overflow-y-auto px-6 py-6">
      <div className="max-w-3xl space-y-7">{children}</div>
    </div>
  );
}

/** Catalog: the realm's badges, plus the backfill that awards new ones retroactively. */
export function CatalogTopicPane({ ecosystemId }: { ecosystemId?: string }) {
  return (
    <SettingsDirtyProvider>
      <RealmCatalogProvider ecosystemId={ecosystemId}>
        <TopicScroller>
          <CatalogSection ecosystemId={ecosystemId} />
          <div className="border-t border-apt-border pt-6">
            <BackfillSection ecosystemId={ecosystemId} />
          </div>
        </TopicScroller>
      </RealmCatalogProvider>
    </SettingsDirtyProvider>
  );
}

/** Levels: the point ladder, plus the same backfill — a raised rung re-grades nobody on its own,
 *  and the ladder's own save note says so in words ("Backfill to re-grade existing members"). */
export function LevelsTopicPane({ ecosystemId }: { ecosystemId?: string }) {
  return (
    <SettingsDirtyProvider>
      <RealmCatalogProvider ecosystemId={ecosystemId}>
        <TopicScroller>
          <LevelsSection ecosystemId={ecosystemId} />
          <div className="border-t border-apt-border pt-6">
            <BackfillSection ecosystemId={ecosystemId} />
          </div>
        </TopicScroller>
      </RealmCatalogProvider>
    </SettingsDirtyProvider>
  );
}

/** Custom Events: realm-defined event types. No catalog provider — event types are their own
 *  endpoint, not part of the catalog response. */
export function EventTypesTopicPane({ ecosystemId }: { ecosystemId?: string }) {
  return (
    <SettingsDirtyProvider>
      <TopicScroller>
        <EventTypesSection ecosystemId={ecosystemId} />
      </TopicScroller>
    </SettingsDirtyProvider>
  );
}
