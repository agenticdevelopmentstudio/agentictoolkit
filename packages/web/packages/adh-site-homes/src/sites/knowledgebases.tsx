"use client";

import { defineSiteHome } from "@agentic-toolkit/adh/home";
import { KnowledgeBasesFeature, WorkspaceKnowledgeBases } from "@agentic-toolkit/knowledgebases";
// personaMemoryTables comes from the server-safe ./tables subpath (same reason as ./parse:
// the barrel dist is a "use client" module).
import { personaMemoryTables } from "@agentic-toolkit/knowledgebases/tables";
// The parse helper comes from the server-safe ./parse subpath, and keeping the grammar in one
// module is what stops this host and the hub drifting into parsing the same URL differently.
import { parseKnowledgeBasesPath } from "@agentic-toolkit/knowledgebases/parse";

// The persona-memory CRUD tables — the package's ONE implementation of the rule the hub's
// feature def encodes (every persona-memory-schema table, sorted by key); this site has no
// catalog of its own, so it calls the shared helper instead of re-filtering the metadata.
// Module scope, as before: the set is static, so it is computed once rather than per render.
const TABLES = personaMemoryTables();

/**
 * The Knowledge Bases feature — this site's gated product surface
 * (docs/platform/feature-platform-phase2.md): CRUD data views over the persona-memory tables,
 * the SAME @agentic-toolkit/knowledgebases surface the hub's /<slug>/knowledgebases route and
 * persona editor render, now rooted at the workspace rather than at /home. Selection is local,
 * so the optional catch-all segment is accepted (parseKnowledgeBasesPath) but not URL-driven.
 *
 * This file DECLARES the route; SiteHomeRoute assembles it — reading the `[workspace]` param and
 * the path below it, and mounting what `render` returns inside SiteHomeShell, which resolves the
 * workspace, keeps the URL in step, and renders the chooser in a bar under the header.
 * `scopedBase` arrives already built. Declared here rather than in a page because both
 * `app/[workspace]/[[...path]]` and `app/home` mount it.
 *
 * A client module because a model carries functions, which cannot cross from a Server Component
 * into the client shell — see SiteHomeRoute.
 *
 * Scoped to the chosen workspace's ecosystem ({@link WorkspaceKnowledgeBases}). It used to be
 * token-scoped, which for a hub token is ecosystem zero: every workspace showed the same rows and
 * every create landed there (Mike, 2026-09-25: an ecosystem shows only its own data).
 *
 * Auth: both mounts sit under a HomeGate layout.
 */
export const knowledgeBasesHome = defineSiteHome({
  parse: parseKnowledgeBasesPath,
  render: ({ scopedBase, workspaceSlug, view }) => (
    <WorkspaceKnowledgeBases workspaceSlug={workspaceSlug}>
      {(ecosystemId) => (
        <KnowledgeBasesFeature
          basePath={scopedBase}
          tables={TABLES}
          scopeEcosystemId={ecosystemId}
          {...view}
        />
      )}
    </WorkspaceKnowledgeBases>
  ),
});

// The default export is what `app/home/page.tsx` and the workspace route import, so
// those two files can be the same bytes in every site. The named export above is the
// one this module's own documentation refers to; they are the same object.
export default knowledgeBasesHome;
