"use client";

import type { ReactElement, ReactNode } from "react";
import { Table2, KeyRound, KeySquare, Database } from "lucide-react";
import { AccessPane } from "@agentic-toolkit/authentication";
import { StorageTokensPanel } from "@agentic-toolkit/ecosystem-config";
import {
  RailHostBoundary,
  StackGroupDetail,
  WorkspaceNotManageable,
  WorkspaceResolutionError,
  type GroupTopicItem,
} from "@agentic-toolkit/resource";
import { helpFor } from "@agentic-toolkit/adh/help/store";
import { EmptyState } from "@agenticdevelopertoolkit/ui/components/empty-state";
import { SchemasPane } from "../schemas/SchemasPane";
import { ecosystemUsersApi } from "../api/customers";
import { applicationsPrototypeApi } from "../api/applications-prototype";
import { AllDataPane } from "./AllDataPane";
import { STORAGE_MEMBER_IDS, type StorageMemberId } from "./parse-path";
import type { RenderTransferSection } from "../transfer-seam";

/**
 * How far the caller got resolving the ecosystem this group is scoped to.
 *
 * Injected rather than resolved here because the two hosts resolve it from different places —
 * the hub from its workspace context, a feature site from the workspace its shell already
 * resolved — while the GATE below (what each outcome shows) must be one decision, not two.
 */
export interface EcosystemScopeResolution {
  /** Undefined while loading AND when the workspace has no infrastructure ecosystem — neither is an
   *  error state, and `isPending` tells them apart. The group settles both itself rather than
   *  handing a pane an undefined that could mean either: Buckets and All Data mount only with a
   *  resolved id. Access and Tokens are still handed it as it stands. */
  ecosystemId?: string;
  /** False only when the resolution definitively says the caller may VIEW this workspace but not
   *  MANAGE its infrastructure ecosystem (a plain org member). */
  canManage: boolean;
  /** The last lookup failed. The group shows its retry surface only when that failure left NO
   *  `ecosystemId`: a re-read failing behind a resolution already in hand keeps the panes on it. */
  isError: boolean;
  /** True until the lookup settles. An undefined `ecosystemId` once this is false is the settled
   *  "this workspace has no infrastructure ecosystem" — and so is a failed lookup, which is why
   *  `isError` is checked first. */
  isPending: boolean;
}

/**
 * The Storage group — Buckets / Access / All Data / Tokens — as a nested topic▸detail rail.
 *
 * The SAME four members appear in two places, which is why they live here rather than in either
 * host: the hub's `/<workspace>/storage` and agenticdeveloperstorage.com's workspace route, each
 * scoped to that workspace's default ecosystem. A copy per host is two copies of one rail, and
 * nothing makes them agree.
 *
 * A product's Storage topic (Products ▸ <product> ▸ Storage) looks like this rail and is not it:
 * EcosystemsFeature hand-declares its own three members (EcosystemsFeature.tsx:207-215), scoped to
 * the product's ecosystem rather than the workspace's, and imports neither this component nor
 * STORAGE_MEMBER_IDS. So a member added here reaches the two hosts above and does NOT reach a
 * product's Storage topic.
 *
 * That is not the same as saying a product has no Tokens. It has one, as its OWN top-level rail
 * member (ProductsFeature.tsx:194), mounting this same panel scoped to the product's ecosystem.
 * The two placements answer differently-scoped questions and neither follows the other.
 *
 * The group opens UNSELECTED — selecting an item never auto-selects a topic (StackGroupDetail's
 * own rule).
 *
 * Self-hosting: it wraps its rail in RailHostBoundary, so it draws one under the hub's chrome and
 * on a bare feature site alike. See the boundary at the bottom of this file.
 */
export function StorageGroup({
  scope,
  workspaceSlug,
  urlSelection,
  renderSubLeaf,
  renderTransfer,
  renderAllData,
}: {
  scope: EcosystemScopeResolution;
  /**
   * The workspace whose principal owns what this rail mints — passed to the backend as
   * `?workspace=`, so an ORG workspace lists and mints the ORG'S tokens rather than the signed-in
   * caller's personal ones.
   *
   * Separate from `scope` rather than folded into it, because the two answer different questions:
   * `scope` is how far the ecosystem RESOLUTION got (and gates the whole group on it), while this
   * is the workspace's identity, which the caller already knows before any resolution runs.
   *
   * Optional, and undefined is a real state rather than a caller's oversight: the hub's embedded
   * /home launcher mounts this group with no workspace in the URL at all. Undefined means the
   * caller's OWN tokens — the same honest degrade `useWorkspaceDefaultEcosystemId` makes for a
   * slug-less host, not an error.
   */
  workspaceSlug?: string;
  /** Omit for internal selection (an embedded launcher) — StackGroupDetail's fallback. */
  urlSelection?: { selectedId: string | null; onSelect: (id: string | null) => void };
  renderSubLeaf?: (memberId: string) => { leafId: string | null; onSelect: (id: string | null) => void };
  /** Transfer Ownership for an open bucket — see {@link RenderTransferSection}. Omitted ⇒ no
   *  transfer section, which is the honest result for a host that cannot name the destinations. */
  renderTransfer?: RenderTransferSection;
  /** The All Data member. Defaults to the package's own local-selection browser; a host with rail
   *  chrome of its own passes a variant that publishes into its stack. Handed the resolved
   *  ecosystem, which it MUST scope to — see AllDataPane's ECOSYSTEM note. */
  renderAllData?: (ecosystemId: string | undefined) => ReactNode;
}): ReactElement {
  const { ecosystemId, canManage, isError, isPending } = scope;
  // `isError && no id`, not `isError`: react-query's `isError` stays true when a background re-read
  // fails behind an answer still on screen, and gating on it alone replaced a working Storage group
  // with "couldn't load" over a hiccup. Read off the id rather than a hook-only flag, so a host
  // that builds its own resolution gets the same rule.
  if (isError && ecosystemId === undefined) return <WorkspaceResolutionError />;
  // A plain org member can view the workspace but not manage its infrastructure ecosystem — its
  // reads/writes would 403 per-pane, so show the honest notice instead.
  if (ecosystemId && !canManage) return <WorkspaceNotManageable feature="Storage" />;
  // What Buckets and All Data show until there is an ecosystem to scope them to. Both used to be
  // handed the bare undefined, which meant "still asking" and "there is none" alike: a workspace
  // with no infrastructure ecosystem showed "Loading…" forever on All Data, and Buckets listed
  // every bucket unscoped and opened rows from other ecosystems. So neither mounts without a
  // resolved id, and `isPending` says which of the two this is. The error gate above has to stay
  // first: a failed lookup settles with no id and no pending flag, exactly like "none".
  const unresolved = (
    <EmptyState title={isPending ? "Loading…" : "This workspace has no ecosystem yet."} />
  );
  // Keyed by member id and then mapped over STORAGE_MEMBER_IDS, so the record is TOTAL over the
  // grammar's list and the rail's order comes from it — that list stays the one description of
  // what this group is, for the panes here and for the parse a host validates a URL against.
  const panes: Record<StorageMemberId, Omit<GroupTopicItem, "id">> = {
    buckets: {
      label: "Buckets",
      icon: <Table2 size={16} aria-hidden />,
      render: (subLeaf) =>
        ecosystemId ? (
          <SchemasPane
            ecosystemId={ecosystemId}
            workspaceSlug={workspaceSlug}
            help={helpFor("ecosystems/schemas")}
            leaf={subLeaf}
            renderTransfer={renderTransfer}
          />
        ) : (
          unresolved
        ),
    },
    access: {
      label: "Access",
      icon: <KeyRound size={16} aria-hidden />,
      render: (subLeaf) => (
        <AccessPane
          ecosystemId={ecosystemId}
          help={helpFor("ecosystems/access")}
          leaf={subLeaf}
          usersDirectory={ecosystemUsersApi.list}
          applicationsDirectory={applicationsPrototypeApi.list}
        />
      ),
    },
    "all-data": {
      label: "All Data",
      icon: <Database size={16} aria-hidden />,
      render: () =>
        ecosystemId
          ? (renderAllData?.(ecosystemId) ?? (
              <AllDataPane workspace={workspaceSlug} ecosystemId={ecosystemId} />
            ))
          : unresolved,
    },
    // The `adh_…` storage-access principals, each of which owns its own isolated bucket — which
    // is what earns this row a place in THIS rail rather than only under Orgs ▸ Configuration,
    // where the same panel is mounted (OrganizationsFeature.tsx:134). It is storage the tokens
    // reach and storage they are made of, so the surface that manages buckets is where you look
    // for them. This is an ADDITION: that mount stays exactly where it was.
    //
    // Not the `tmp_…` personal API tokens user settings mints — a different principal that
    // happens to share the noun; see StorageTokensPanel's own header for the distinction.
    //
    // A key, like Access above it, because a token IS a key platform-wide (Configuration's row
    // and the hub's rail both draw one) — squared off so the two rows are still told apart at
    // rail size.
    //
    // Scoped by `ecosystemId` exactly as the three members above are, so this rail means one
    // thing throughout: the tokens whose buckets live in the ecosystem whose buckets Buckets
    // lists. The hub's standalone /tokens route deliberately passes no ecosystem and therefore
    // spans every one of the owner's — a wider question, asked somewhere else.
    //
    // Ignores the sub-leaf: the panel is a flat roster with a create form, so there is no inner
    // entity for the segment below to name.
    tokens: {
      label: "Tokens",
      icon: <KeySquare size={16} aria-hidden />,
      render: () => <StorageTokensPanel ecosystemId={ecosystemId} workspace={workspaceSlug} />,
    },
  };
  const items: GroupTopicItem[] = STORAGE_MEMBER_IDS.map((id) => ({ id, ...panes[id] }));
  // StackGroupDetail PUBLISHES its rail rather than drawing one — StackLevels registers the level
  // with the nearest rail host and is a documented NO-OP without one, so the rows go nowhere and
  // only the leaf's "Select a topic." hint renders. That is what an unhosted mount looks like: not
  // an error, not an empty list, a surface with nothing on it.
  //
  // The hub supplies a host (WorkspaceChromeProvider) and this boundary passes straight through
  // there; agenticdeveloperstorage.com has no chrome of its own, so the boundary becomes the host.
  // It lives HERE, on the component a site mounts, for the reason RailHostBoundary's own doc gives
  // for every feature entry: a host each site had to remember to add is a host a site can forget,
  // and forgetting it costs the whole rail with nothing to say so.
  //
  // Below the two gates above, not around them: they render a plain notice with no rails, and a
  // standalone host around one would draw an empty stack frame around a sentence.
  return (
    <RailHostBoundary>
      <StackGroupDetail
        levelId="storage-group"
        title="Storage"
        items={items}
        urlSelection={urlSelection}
        renderSubLeaf={renderSubLeaf}
      />
    </RailHostBoundary>
  );
}
