// @agentic-toolkit/gamification — a product's gamification realm: config, badge catalog, level
// ladder and custom event types.
//
// TWO arrangements of ONE set of sections, because two hosts want different things from them:
//
//   • GamificationFeature — the gamification site. Products as the root list, then four topics
//     (Catalog / Levels / Custom Events / Settings) per product.
//   • GamificationPane — the hub. All of it in one scroller under one save bar, which is what a
//     single topic on a product's twenty-topic rail has to be.
//
// The sections are exported too, for a third host that wants a different arrangement again.

export { GamificationFeature } from "./GamificationFeature";
export type { GamificationFeatureProps } from "./GamificationFeature";

export { GamificationPane } from "./GamificationPane";

export { GAMIFICATION_TOPICS } from "./topics";

export { RealmSettingsPane, GamificationSettingsTopicPane, realmConfigApi } from "./RealmSettingsPane";
export { CatalogSection } from "./CatalogSection";
export { LevelsSection } from "./LevelsSection";
export { BackfillSection } from "./BackfillSection";
export { EventTypesSection, sameEventTypeDraft } from "./EventTypesSection";
export { CatalogTopicPane, LevelsTopicPane, EventTypesTopicPane } from "./topic-panes";

export { RealmCatalogProvider, useRealmCatalog } from "./realm-catalog";

// The URL grammar lives at the SERVER-SAFE ./parse subpath ONLY — deliberately NOT re-exported
// here: this barrel's dist is a "use client" module, so an RSC page that imported the parse
// helper from it would throw in prod (render-only client refs). Same rule as
// @agentic-toolkit/ecosystems.
export type { GamificationPathSelection } from "./parse-path";
