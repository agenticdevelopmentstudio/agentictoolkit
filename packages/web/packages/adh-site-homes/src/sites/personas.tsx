"use client";

import type { ReactNode } from "react";
import dynamic from "next/dynamic";
import { defineSiteHome } from "@agentic-toolkit/adh/home";
import type { Persona } from "@agentic-toolkit/data/personas";
import { personaProfileUrl } from "@agentic-toolkit/adh-registry";
import { personaMemoryTables } from "@agentic-toolkit/knowledgebases/tables";
import { PersonasFeature } from "@agentic-toolkit/personas";
// Relative, not a package subpath: ProfilePersonas lives IN this site now (it imports the adh
// vocabulary tier, which a portable @agentic-toolkit package may not — see its own docblock),
// not in @agentic-toolkit/personas.
import { ProfilePersonas } from "./ProfilePersonas";
// PersonasSection fetches through the toolkit's react-query cache, which reads the
// toolkit's OWN QueryClient context — mount its provider here (same physical module
// as the hooks; a host-provided QueryClientProvider would be a different copy and
// invisible to them). Mirrors the sibling personabuilder site's mount.
import { ToolkitQueryProvider } from "@agentic-toolkit/data/query";
// Grammar from the server-safe ./parse subpath — the ONLY home for parse helpers now
// (the barrels deliberately do not re-export them; see any feature barrel's note).
import { parsePersonasPath } from "@agentic-toolkit/personas/parse";

const loading = () => <p className="p-4 text-sm text-apt-text-muted">Loading…</p>;
const KnowledgeBasesPane = dynamic(
  () => import("@agentic-toolkit/knowledgebases").then((m) => m.KnowledgeBasesPane),
  { loading },
);

// The persona-memory CRUD tables — the knowledgebases package's one implementation of the rule.
const KB_TABLES = personaMemoryTables();

/**
 * The Personas feature — this site's gated product surface, and the reason agenticdeveloperpersonas.com
 * exists: it is where you define personas now. This is the SAME @agentic-toolkit/personas surface
 * the hub's `/<workspace>/personas` route renders — since 2026-08-30 literally so, because that
 * route mounts THIS model (the hub's PersonasRoute).
 *
 * What used to be claimed here — that Personas left the hub's workspace rail and "nothing points
 * at it" — was never true of the rail: `personas` is not in the hub's NOT_RAIL_FLEET_SEGMENTS, so
 * the row is drawn like any other fleet segment. The sentence survived a rail reshuffle it had
 * described correctly beforehand, which is why it is corrected rather than deleted: what it got
 * right is that the SITE is the product surface, and the hub's row leads to the same one.
 *
 * URL grammar (parsePersonasPath), rooted at the workspace:
 *   /<ws> | /<ws>/<personaId> | /<ws>/<personaId>/<subTab>
 *
 * Seams filled HERE, by the model, because nothing about them is a host's — the same two the
 * sibling personabuilder site supplies, from the same owners, so the mounts cannot drift:
 * - profileUrlFor: the persona's public registry profile — the shared
 *   @agentic-toolkit/adh-registry personaProfileUrl rule (the hub used the same one, from its own
 *   copy of the call, until this became its mount).
 * - renderKnowledgeBases: the Knowledge facet embeds the knowledgebases pane with the
 *   persona-memory tables from the toolkit's generated catalog. The hub passed its OWN table set
 *   here — `featureTables(getFeatureDef("knowledgebases"))` — and a drift test in the hub asserts
 *   the two resolve the same keys, which is why this one can serve both rather than becoming a
 *   third seam nobody could tell was wrong.
 *
 * Seams a HOST fills — see {@link PersonasHostSeams}. The live try-it chat, the Project facet,
 * Transfer Ownership and Integrations are each a package boundary this one cannot cross, so on
 * this site the editor shows the fallbacks {@link PersonaEditor} documents (the same ones
 * personabuilder shows) and the hub fills all four.
 *
 * This file DECLARES the route; SiteHomeRoute assembles it — reading the `[workspace]` param and
 * the path below it, and mounting what `render` returns inside SiteHomeShell, which resolves the
 * workspace, keeps the URL in step, and renders the chooser in a bar under the header.
 * `scopedBase` arrives already built. Declared here rather than in a page because both
 * `app/[workspace]/[[...path]]` and `app/home` mount it.
 *
 * A client module for two reasons at once: two of the feature's host seams are functions, and so
 * are a model's own `parse`/`render` — neither can cross the serialization boundary.
 *
 * `workspaceSlug` is still not passed BY DEFAULT, matching personabuilder: the persona list is
 * token-scoped here, which is what it was before the workspace segment existed. Owner-scoping it
 * (an org workspace showing the org's personas) is the open platform decision
 * (feature-platform-phase2 §2) — the hub's route had answered it for itself all along, and what
 * changed on 2026-08-30 is that a host can now SAY so (`scopeToWorkspace`) instead of keeping a
 * second mount in order to act on it. §2 is no more settled than it was.
 *
 * Auth: both mounts sit under a HomeGate layout; data is token-scoped.
 */
export const personasHome = defineSiteHome({
  parse: parsePersonasPath,
  render: ({ scopedBase, workspaceSlug, view }, host: PersonasHostSeams) => (
    <ToolkitQueryProvider>
      <PersonasFeature
        basePath={scopedBase}
        // §2, answered by the MOUNT and not here. Undefined ⇒ token-scoped, exactly as before.
        workspaceSlug={host.scopeToWorkspace ? workspaceSlug : undefined}
        profileUrlFor={personaProfileUrl}
        renderKnowledgeBases={(scopeEcosystemId) => (
          <KnowledgeBasesPane tables={KB_TABLES} scopeEcosystemId={scopeEcosystemId} />
        )}
        renderChatPane={host.renderChatPane}
        renderProject={host.renderProject}
        renderTransferOwnership={host.renderTransferOwnership}
        renderIntegrations={host.renderIntegrations}
        {...view}
      />
    </ToolkitQueryProvider>
  ),
  profileSection: (principal) => <ProfilePersonas principal={principal} />,
});

/** What a HOST may add to this site's Personas surface. Every field optional — this site fills
 *  none of them, and the editor's own fallbacks are what a persona shows without them. */
export interface PersonasHostSeams {
  /**
   * This host has decided feature-platform-phase2 §2 FOR ITSELF: scope the list and any persona
   * created here to the workspace the shell resolved, rather than to the token.
   *
   * A boolean rather than a `workspaceSlug` string, deliberately — the slug is already in the
   * render context, so what a host contributes is the DECISION, not the value. Same seam shape as
   * dashboards', for the same reason: naming the decision keeps §2 legible as still open.
   */
  scopeToWorkspace?: boolean;
  /** The live try-it chat for a saved persona. Omitted ⇒ the editor's "Chat isn't available in
   *  this view." fallback. Hub-only glue: @agentic-toolkit/persona/chat is not a dependency a
   *  portable feature site carries. */
  renderChatPane?: (persona: Persona) => ReactNode;
  /** The persona's auto-provisioned project (the editor's Project facet). Omitted ⇒ no facet. */
  renderProject?: (personaId: string) => ReactNode;
  /** Transfer Ownership for the open persona. Omitted ⇒ no such section — the destination list is
   *  the caller's whole workspace tree, which is a host's to build and not this package's. */
  renderTransferOwnership?: (persona: Persona) => ReactNode;
  /** The persona's own Integrations facet — the provider-config pane scoped to the ecosystem it
   *  OWNS (@agentic-toolkit/integrations' IntegrationsPane is not a dependency a portable feature
   *  site carries). Omitted ⇒ the editor's "not available in this view" fallback. */
  renderIntegrations?: (ecosystemId: string) => ReactNode;
}

// The default export is what `app/home/page.tsx` and the workspace route import, so
// those two files can be the same bytes in every site. The named export above is the
// one this module's own documentation refers to; they are the same object.
export default personasHome;
