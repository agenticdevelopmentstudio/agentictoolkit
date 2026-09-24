"use client";

import type { ReactNode } from "react";
import { RailHostBoundary, useBasePathRoute } from "@agentic-toolkit/resource";
import type { Persona } from "@agentic-toolkit/data/personas";
import { PersonasSection } from "./PersonasSection";

/**
 * The Personas feature's site entry — a thin, host-agnostic wrapper that drives
 * {@link PersonasSection}'s `urlSelection` from an explicit `basePath` (via
 * {@link useBasePathRoute}), modeled on `DashboardsFeature`. A feature site mounts this directly
 * (`<PersonasFeature basePath="/home" {...parsePersonasPath(path)} />`) with no host-side glue
 * beyond parsing its own catch-all segments with {@link parsePersonasPath}.
 *
 * The hub mounts this too, as of 2026-08-30. It used to derive its own wiring — a second
 * arrangement of PersonasSection, kept because it needed FIVE seams this entry forwarded three of
 * (the try-it chat, the Project facet, Transfer Ownership) plus the owner-scoping slug. Every one
 * of those was already a `PersonasSection` prop; the only thing missing was a way through this
 * wrapper, so they are forwarded here rather than duplicated there. That leaves one mount of the
 * persona editor in the fleet, differing between hosts only in which optional seams arrive filled.
 */
export function PersonasFeature({
  basePath,
  personaId,
  subTab,
  workspaceSlug,
  renderChatPane,
  profileUrlFor,
  renderKnowledgeBases,
  renderProject,
  renderTransferOwnership,
  renderIntegrations,
}: {
  /** This feature's URL base — every push lands under it (e.g. `/<slug>/personas`, or `/home` on a
   *  feature site). Supplied by the host route rather than derived here, so the same feature
   *  mounts under either scheme. */
  basePath: string;
  /** The open persona's id (first path segment after `basePath`), or undefined for the All table. */
  personaId?: string;
  /** The active editor sub-tab (second path segment), or undefined for the first tab. */
  subTab?: string;
  /** The workspace whose personas this shows — owner-scoped list and create. Omitted ⇒ the
   *  caller's own creator-scoped personas. See {@link PersonasSection}. */
  workspaceSlug?: string;
  /** Renders the live try-it chat for a saved persona. See {@link PersonasSection}. */
  renderChatPane?: (persona: Persona) => ReactNode;
  /** The persona's public profile URL for a given slug. See {@link PersonasSection}. */
  profileUrlFor?: (slug: string) => string;
  /** Renders the Knowledge Bases browser scoped to a persona's owned ecosystem. See
   *  {@link PersonasSection}. */
  renderKnowledgeBases?: (scopeEcosystemId: string) => ReactNode;
  /** Renders a persona's auto-provisioned project (the editor's Project facet). See
   *  {@link PersonasSection}. */
  renderProject?: (personaId: string) => ReactNode;
  /** Host-rendered "Transfer Ownership" section for the open persona. See
   *  {@link PersonasSection}. */
  renderTransferOwnership?: (persona: Persona) => ReactNode;
  /** Renders the integrations pane scoped to a persona's owned ecosystem. See
   *  {@link PersonasSection}. */
  renderIntegrations?: (ecosystemId: string) => ReactNode;
}) {
  const { pushSegment, pushNested } = useBasePathRoute(basePath);
  // RailHostBoundary: standalone, PersonasSection's own-HTD fallback renders the persona
  // list, but PersonaEditor's facet tabs + exit guards exist only as rail-host publications
  // — the boundary self-hosts them so the editor is whole on a bare feature site.
  return (
    <RailHostBoundary>
      <PersonasSection
        workspaceSlug={workspaceSlug}
        urlSelection={{
          personaId,
          subtab: subTab,
          onSelectPersona: pushSegment,
          onSelectSubtab: (subtab) => pushNested(personaId, subtab),
        }}
        renderChatPane={renderChatPane}
        profileUrlFor={profileUrlFor}
        renderKnowledgeBases={renderKnowledgeBases}
        renderProject={renderProject}
        renderTransferOwnership={renderTransferOwnership}
        renderIntegrations={renderIntegrations}
      />
    </RailHostBoundary>
  );
}
