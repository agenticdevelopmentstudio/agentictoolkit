// @agentic-toolkit/knowledgebases — the Knowledge Bases feature: CRUD data views over the
// persona-memory tables, in the one merged stack (the hub's rail-host, or standalone on a feature
// site's /home). The panel is internal; the barrel exposes the feature entry (the host passes
// `basePath` + the `tables` it resolved from its own catalogs) and the URL parse both hosts share.
export { KnowledgeBasesFeature } from "./KnowledgeBasesFeature";
// The workspace → ecosystem gate both hosts mount the feature through, so the scope is resolved
// and refused the same way on the site and in the hub.
export { WorkspaceKnowledgeBases } from "./WorkspaceKnowledgeBases";

// The persona-memory table rule. ALSO exported at the server-safe ./tables subpath —
// RSC pages must import it from there (this barrel's dist is a "use client" module).
export { personaMemoryTables } from "./tables";

// The /home Knowledge Bases URL grammar, owned here so both hosts parse it identically.
// The URL grammar lives at the SERVER-SAFE ./parse subpath ONLY — deliberately NOT
// re-exported here: this barrel's dist is a "use client" module, so an RSC page that
// imported the parse helper from it would throw in prod (render-only client refs).

// KnowledgeBasesPane is ALSO exported directly (not just via KnowledgeBasesFeature) because
// HOSTS inject the bare pane into the persona editor's Knowledge facet through its
// renderKnowledgeBases seam (the hub does this in its persona host-seams module and its
// feature-panels "knowledgebases" case) — those call sites need the pane, not the
// basePath-carrying feature entry.
export { KnowledgeBasesPane } from "./KnowledgeBasesPane";
