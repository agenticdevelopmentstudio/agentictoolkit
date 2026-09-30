"use client";

import type { ReactElement } from "react";
import { EmptyState } from "@agenticdevelopertoolkit/ui/components/empty-state";
import { useDetailTitle } from "@agenticdevelopertoolkit/ui/blocks/detail-title";

// The shared surfaces a workspace-scoped feature shows INSTEAD of its pane: two for an ecosystem
// gate that did not open, one for a feature that isn't built yet. They live here rather than in
// any one host because three apps now render the gated panes, and two copies of this copy is two
// different answers to the same question.

/**
 * The shared failure surface for a workspace whose default-ecosystem resolution failed
 * (useDefaultEcosystemId's ONE request — retry: false — errored): without a defined
 * surface the scoped panes would sit on their loading states forever, or worse, render
 * an authoritative-looking empty list. One component so Storage / Integrations (and the
 * next scoped feature) can't drift on the copy.
 */
export function WorkspaceResolutionError(): ReactElement {
  return (
    <div className="flex min-h-0 flex-1 items-center justify-center p-6">
      <EmptyState
        title="Couldn't load this workspace"
        description="The workspace's default ecosystem didn't resolve — reload the page to retry."
      />
    </div>
  );
}

/**
 * The shared surface for a workspace-level owner-admin feature (Storage / Integrations) opened
 * by someone who can VIEW the workspace but not MANAGE its infrastructure ecosystem — a plain
 * organization member. The panes' reads/writes would otherwise 403 per-pane; this shows the same
 * honest "ask an admin" notice the Products feature uses (EcosystemsFeature.notManageablePane),
 * so the two promoted features don't drift on the copy.
 */
export function WorkspaceNotManageable({ feature }: { feature: string }): ReactElement {
  return (
    <div className="flex min-h-0 flex-1 items-center justify-center p-6">
      <EmptyState
        title={`You don't have admin access to ${feature}`}
        description="Managing this workspace's infrastructure needs organization admin access — ask one of the organization's admins."
      />
    </div>
  );
}

/**
 * Placeholder for a feature whose dedicated UI isn't built yet — it replaces the pane with a
 * centered "Coming soon" label. The feature's data stays reachable in the meantime via All Data.
 *
 * Here, next to the two gate surfaces above, for the same reason: it is what a host renders
 * INSTEAD of a pane, and the hub is no longer the only host that has to render it — Billing is
 * a product topic, so every mount of the Products feature reaches this.
 */
export function ComingSoon({
  title,
  blurb,
}: {
  /** The feature's display title, shown above the "Coming soon" label. */
  title: string;
  /**
   * Why it is not here yet, when there is a reason worth saying — a feature that is PAUSED
   * reads very differently from one that was never started, and "Coming soon" alone cannot
   * tell the two apart. Optional, because most callers genuinely have nothing to add.
   *
   * Added 2026-08-31 for the hub's embedded Messages pane, whose route counterpart already
   * said why (direct messages are parked while the per-product Messaging tool ships) while
   * the pane said only "Coming soon". The sentence itself lives with the site model that
   * owns the feature — `MESSAGES_PAUSED_BLURB` — so the two surfaces cannot drift.
   */
  blurb?: string;
}): ReactElement {
  // Inside a detail stack the name rides the stack's detail strip (see FeatureTitle).
  const { hoisted, portal } = useDetailTitle(title);
  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col items-center justify-center gap-2 p-8 text-center">
      {portal}
      {!hoisted && <h1 className="font-mono text-lg tracking-wide text-apt-text">{title}</h1>}
      <p className="font-mono text-sm uppercase tracking-widest text-apt-text-dim">
        Coming soon
      </p>
      {blurb ? <p className="max-w-prose text-sm text-apt-text-muted">{blurb}</p> : null}
    </div>
  );
}
