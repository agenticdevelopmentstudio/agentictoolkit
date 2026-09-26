"use client";

import type { ReactElement, ReactNode } from "react";
import {
  WorkspaceNotManageable,
  WorkspaceResolutionError,
  useReportBusy,
} from "@agentic-toolkit/resource";
import { useWorkspaceDefaultEcosystemId } from "@agentic-toolkit/data/ecosystems";

/**
 * The resolve-or-explain gate a pane in this package sits behind when its host has a WORKSPACE
 * rather than an ecosystem id — every pane here is scoped to an ecosystem, and a workspace's is
 * its DEFAULT one, which takes a request to find.
 *
 * Two things have to be answered before a pane may render, and neither is a pane's job:
 *
 * - A failed resolution must not fall through. Every pane reads a missing `ecosystemId` as a
 *   settled empty ecosystem, so a host that rendered one anyway would show "no server bags" for
 *   an ecosystem it never managed to look up — an authoritative lie.
 * - A plain org member can VIEW the workspace but not manage its infrastructure ecosystem. Left
 *   to itself each pane discovers the same 403 separately, which is one chance per pane to word
 *   it differently.
 *
 * `children` is a function so the resolved id reaches the pane without this component knowing
 * which pane it is; `feature` is the pane's own name, which is what the not-manageable notice
 * says the caller may not manage.
 */
export function EcosystemConfigGate({
  workspaceSlug,
  feature,
  children,
}: {
  /** The workspace whose default ecosystem the gated pane configures. */
  workspaceSlug: string | undefined;
  /** The gated pane's label, as the not-manageable notice should name it. */
  feature: string;
  children: (ecosystemId: string | undefined) => ReactNode;
}): ReactElement {
  const { ecosystemId, canManage, isLoadingError, isFetching } =
    useWorkspaceDefaultEcosystemId(workspaceSlug);
  // The spinner in front of the topic list this gate sits under. What it reports is the SCOPE
  // resolution, not the gated pane's contents: until the id lands the pane below is a shell with
  // nothing to read against, and the resolution is cached, so from the second visit on there is no
  // "Loading…" branch left to give it away. Reported upward rather than published as a level's
  // `busy` because the gate is mounted BELOW the list, one topic at a time, and has no level of its
  // own to hang it on. `isFetching`, never `isPending` — pending is false on exactly the cached
  // re-read the spinner exists for.
  useReportBusy(isFetching);
  // A failure with NO answer. `isError` is also true when a re-read fails behind a resolution
  // still in hand, and replaced a working pane with the error for it.
  if (isLoadingError) return <WorkspaceResolutionError />;
  if (ecosystemId && !canManage) return <WorkspaceNotManageable feature={feature} />;
  return <>{children(ecosystemId)}</>;
}
