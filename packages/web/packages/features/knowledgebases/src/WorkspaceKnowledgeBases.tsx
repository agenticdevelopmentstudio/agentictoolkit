"use client";

import type { ReactElement } from "react";
import { EmptyState } from "@agenticdevelopertoolkit/ui/components/empty-state";
import { useWorkspaceDefaultEcosystemId } from "@agentic-toolkit/data/ecosystems";
import { WorkspaceNotManageable, WorkspaceResolutionError } from "@agentic-toolkit/resource";

/**
 * Resolves the workspace's own ecosystem and hands it to `children`, the scope every persona-memory
 * CRUD verb then names. Both hosts mount the feature through this: agenticdeveloperknowledgebases's
 * workspace route and the hub's embedded Knowledge Bases pane.
 *
 * Unscoped, a hub token's knowledge bases are ecosystem ZERO's: every workspace listed the same
 * rows, and a non-admin's creates landed in ecosystem zero whichever workspace they were in (Mike,
 * 2026-09-25: an ecosystem shows only its own data). The backend now reads `?ecosystemId=` on the
 * persona_memory tables and refuses one the caller cannot manage, so the gate is Storage's own
 * (StorageGroup): a failed resolution, a workspace the caller can view but not manage, and "still
 * asking" vs "there is none" each get their honest answer instead of a pane that reads an undefined
 * scope as the caller's token ecosystem. The error gate stays first: a failed lookup settles with no
 * id and no pending flag, exactly like "none".
 */
export function WorkspaceKnowledgeBases({
  workspaceSlug,
  children,
}: {
  workspaceSlug: string | undefined;
  children: (ecosystemId: string) => ReactElement;
}): ReactElement {
  const { ecosystemId, canManage, isError, isPending } =
    useWorkspaceDefaultEcosystemId(workspaceSlug);
  if (isError) return <WorkspaceResolutionError />;
  if (!ecosystemId) {
    return <EmptyState title={isPending ? "Loading…" : "This workspace has no ecosystem yet."} />;
  }
  if (!canManage) return <WorkspaceNotManageable feature="Knowledge Bases" />;
  return children(ecosystemId);
}
