"use client";

import { useCallback, useMemo } from "react";
import { useResourceList, workspacesApi, type Workspace } from "@agentic-toolkit/data";
import { api as personasApi, type Persona } from "@agentic-toolkit/data/personas";
import {
  ecosystemsApi,
  useWorkspaceDefaultEcosystemId,
  type Ecosystem,
} from "@agentic-toolkit/data/ecosystems";

/**
 * The URL segment for the workspace's own destination — a RESERVED LITERAL, not an id.
 *
 * The workspace row is the one destination whose ecosystem id is not known when the URL is
 * written: it is resolved asynchronously (`useWorkspaceDefaultEcosystemId`), so addressing it by
 * that id would make the first destination unlinkable until a second request came back, and would
 * change the URL of "My Integrations" the day an account's infrastructure ecosystem is
 * re-provisioned. A stable literal keeps the link stable and keeps the resolution an
 * implementation detail.
 *
 * Collision with a real ecosystem id is impossible in practice (ids are uuids/rdids) and harmless
 * in principle: {@link resolveDestination} scans the destinations array in order and the workspace
 * row is always first, so the literal deterministically wins.
 */
export const WORKSPACE_DESTINATION_ID = "workspace";

/** What a destination IS — drives its icon and its empty-state wording, nothing else. */
export type DestinationKind = "workspace" | "persona" | "product";

/**
 * One row of the integrations root list: a place integrations can be connected TO.
 *
 * Every integration binds to an `ecosystemId` (see `@agentic-toolkit/data/integrations` —
 * every connect body requires one), so a "destination" is ultimately an ecosystem. The three
 * kinds differ only in how that ecosystem is reached: the workspace's own infrastructure
 * ecosystem, a persona's owned realm, or a product, which IS an ecosystem.
 */
export interface IntegrationDestination {
  /** The URL segment addressing this destination — see {@link WORKSPACE_DESTINATION_ID} for the
   *  workspace row, the persona's rdid for a persona, the ecosystem's id for a product. */
  id: string;
  /** The row's title in the list. */
  label: string;
  /** The row's subtitle — the workspace/persona/product's own handle or name. */
  sublabel: string;
  kind: DestinationKind;
  /**
   * The ecosystem whose provider configs this destination shows — a deliberate TRI-STATE, and
   * the reason this field is not simply `string`:
   *
   *   `undefined` → not resolved YET. Show a loading state; do NOT mount the pane, which would
   *                 read a missing id as "no integrations yet" and say so.
   *   `null`      → resolved, and there is no ecosystem. A persona with no owned realm is the
   *                 real case; it is still listed (it exists, and it explains itself) but it has
   *                 nothing to show.
   *   `string`    → mount the pane against this id.
   *
   * Only the workspace row is ever `undefined`, because only it resolves out of band; the other
   * two carry their answer in the row that produced them.
   */
  ecosystemId: string | null | undefined;
  /**
   * False ONLY when the resolution definitively says the caller can view this destination but not
   * manage it — a plain organization member opening the workspace's own row. The feature shows
   * `WorkspaceNotManageable` in place of the pane, which is the answer the hub's own
   * `/…/integrations` route gave before it mounted this feature (`useDefaultEcosystemId`'s
   * `ecosystemId && !canManage` gate); without it every read and write in the pane 403s one at a
   * time and the reader is left to infer why from a wall of failures.
   *
   * Per-DESTINATION rather than over the whole feature, which is where this improves on the gate
   * it replaces: the flag answers for the workspace's infrastructure ecosystem only, and a persona's
   * realm or a product is a different ecosystem with its own grants. Gating the feature on it would
   * hide destinations the member can genuinely manage.
   *
   * True while loading and true for the persona/product rows — the same default-to-permitted rule
   * `useWorkspaceDefaultEcosystemId.canManage` follows. It is the absence of a definitive NO, not
   * a claim of permission; the backend is still the authority on every write.
   */
  manageable: boolean;
}

/** What {@link useIntegrationDestinations} returns. */
export interface IntegrationDestinationsResult {
  /** The rows, or null while the first load is still in flight. Ordered: the workspace first,
   *  then personas, then products. */
  destinations: IntegrationDestination[] | null;
  /** The first load failure across the three reads, or null. Reported ALONGSIDE whatever did
   *  load — one dead read must not blank the destinations that are fine. */
  error: string | null;
}

/**
 * Resolve a URL segment to a destination. A LOOKUP, deliberately, rather than a shape test on the
 * segment: the three id schemes (a reserved literal, a persona rdid, an ecosystem id) are not
 * reliably distinguishable by inspection, and a mis-read would scope the pane to the wrong
 * principal's integrations rather than fail. An unknown segment answers null, which the feature
 * renders as the bare list — the same thing it renders for no segment at all.
 */
export function resolveDestination(
  destinations: IntegrationDestination[] | null,
  id: string | undefined,
): IntegrationDestination | null {
  if (!id || !destinations) return null;
  return destinations.find((d) => d.id === id) ?? null;
}

/**
 * The integrations root list for a workspace: its own integrations, one row per persona it owns,
 * and one per product it owns.
 *
 * Three reads, because the three kinds live in three places, and the workspace's own ecosystem is
 * the odd one out — it is resolved by the shared react-query hook rather than fetched here, so
 * there is ONE cache entry for it platform-wide (that hook's doc is explicit that hosts must not
 * re-implement its query). The other two go through `useResourceList`, whose module-scope cache
 * seeds the first paint after the remount that every navigation on a catch-all segment causes.
 *
 * The rows are withheld until the personas AND products reads have SETTLED (resolved or failed),
 * so the list does not visibly grow under the cursor a moment after it appears. It is deliberately
 * NOT gated on the workspace ecosystem: that row's label and address are known without it, and
 * waiting would hold the whole list on the one read the user is least likely to be waiting for.
 */
export function useIntegrationDestinations(workspace: Workspace): IntegrationDestinationsResult {
  return useDestinationRows(workspace.slug, workspace);
}

/**
 * The three reads, for a slug whose workspace row may not have arrived yet.
 *
 * `workspace` is null ONLY while a slug-only caller is still resolving it — see
 * {@link useTransferTargets}. The rows are withheld for as long as it is, because the first row
 * is the workspace's own and a list that names it wrongly for a frame is worse than one that
 * appears a frame later.
 *
 * `slug` is undefined when the caller has no workspace at all. The loaders then return a promise
 * that never settles, which is `useResourceList`'s own idiom for a list held in Loading until its
 * scope arrives: an empty array would be a claim that the workspace has no personas, and the
 * hooks cannot simply not be called.
 */
function useDestinationRows(
  slug: string | undefined,
  workspace: Pick<Workspace, "kind" | "name"> | null,
): IntegrationDestinationsResult {
  // Slug-bearing cache keys: `useResourceList`'s cache is tenant-scoped, and one tenant has
  // several workspaces — a shared key would seed an org's first paint with the personal
  // workspace's rows. The `integrations::` prefix keeps them distinct from any other feature
  // caching the same endpoints.
  const loadPersonas = useCallback(
    () => (slug ? personasApi.personas.list({ workspace: slug }) : never<Persona>()),
    [slug],
  );
  const loadProducts = useCallback(
    () => (slug ? ecosystemsApi.listForWorkspace(slug) : never<Ecosystem>()),
    [slug],
  );

  const personas = useResourceList<Persona>(`integrations::personas::${slug ?? ""}`, loadPersonas);
  const products = useResourceList<Ecosystem>(`integrations::products::${slug ?? ""}`, loadProducts);

  const {
    ecosystemId: workspaceEcosystemId,
    isPending: workspacePending,
    // A failure with NO answer: a re-read failing behind the resolved id keeps the row working, and
    // is not "couldn't resolve".
    isLoadingError: workspaceFailed,
    canManage: workspaceManageable,
  } = useWorkspaceDefaultEcosystemId(slug);

  const personaRows = personas.items;
  const productRows = products.items;
  const settled =
    (personaRows !== null || personas.error !== null) &&
    (productRows !== null || products.error !== null);

  const destinations = useMemo<IntegrationDestination[] | null>(() => {
    if (!settled || !workspace) return null;
    const rows: IntegrationDestination[] = [
      {
        id: WORKSPACE_DESTINATION_ID,
        // The brief's exact wording, and the one place the workspace's KIND changes what the user
        // reads — which is why the shell hands features the resolved workspace ROW rather than
        // just its slug.
        label: workspace.kind === "organization" ? "Org Integrations" : "My Integrations",
        sublabel: workspace.name,
        kind: "workspace",
        // `isPending` is what separates "still asking" from the definitive "this account has no
        // infrastructure ecosystem"; both read as an absent id, and they are not the same answer.
        ecosystemId: workspacePending ? undefined : (workspaceEcosystemId ?? null),
        manageable: workspaceManageable,
      },
    ];
    // Sorted here because the personas endpoint does not promise an order (the ecosystems client
    // sorts its own rows before returning them), and a list that reshuffles between mounts is
    // worse than any particular order.
    for (const p of [...(personaRows ?? [])].sort((a, b) => a.name.localeCompare(b.name))) {
      rows.push({
        id: p.id,
        label: p.name,
        sublabel: p.slug,
        kind: "persona",
        // A persona that owns no realm is listed anyway: it is a destination the user can see they
        // have, and the pane explains why it is empty. Hiding it would read as the persona being
        // missing. An absent field is treated as "no realm" rather than "unknown" because this row
        // has already resolved — there is nothing further to wait for.
        ecosystemId: p.ownedEcosystemId ?? null,
        // A persona's realm is not the workspace's infrastructure ecosystem, so the workspace
        // flag says nothing about it and nothing else here does either — see `manageable`.
        manageable: true,
      });
    }
    for (const e of productRows ?? []) {
      rows.push({
        id: e.id,
        label: e.name,
        sublabel: e.identifier,
        kind: "product",
        // A product IS an ecosystem — no second hop.
        ecosystemId: e.id,
        manageable: true,
      });
    }
    return rows;
  }, [
    settled,
    personaRows,
    productRows,
    workspace,
    workspacePending,
    workspaceEcosystemId,
    workspaceManageable,
  ]);

  return {
    destinations,
    error:
      personas.error ??
      products.error ??
      (workspaceFailed ? "Couldn't resolve this workspace's own integrations." : null),
  };
}

/** A promise that never settles — see {@link useDestinationRows}. */
function never<T>(): Promise<T[]> {
  return new Promise<T[]>(() => {});
}

/** A place an integration can be MOVED to. A destination that has resolved to a real ecosystem,
 *  which is the only kind a transfer can name: the backend's transfer takes a target ecosystem
 *  id, so a persona with no realm is not a target, it is a row with nowhere to put anything. */
export interface TransferTarget {
  ecosystemId: string;
  label: string;
  sublabel: string;
  kind: DestinationKind;
}

/** What {@link useTransferTargets} returns. `targets` is null until the list is known — an empty
 *  array is the different, definitive answer "there is nowhere else to put this". */
export interface TransferTargetsResult {
  targets: TransferTarget[] | null;
  error: string | null;
}

/**
 * Where the integrations in this pane could be transferred TO — the same workspace/persona/product
 * list the integrations root shows, minus the ecosystem they are already in.
 *
 * A SLUG is all this takes, which is the whole reason it exists next to
 * {@link useIntegrationDestinations}: the pane is mounted inside shipr's connections dialog, which
 * holds `client.workspace` and has never had the resolved `Workspace` row. The row is looked up
 * from the workspaces list instead — the same `useResourceList("workspaces")` entry the shell's
 * own chooser reads, so this costs a cache hit rather than a request.
 *
 * An undefined slug answers `targets: null` forever, and the pane draws no Transfer button. That
 * is a host that has not said which workspace it is in, not a workspace with nowhere to transfer
 * to, and the two must not render the same.
 */
export function useTransferTargets(
  workspaceSlug: string | undefined,
  excludeEcosystemId: string | null | undefined,
): TransferTargetsResult {
  const workspaces = useResourceList<Workspace>("workspaces", workspacesApi.list);
  const row = workspaceSlug
    ? ((workspaces.items ?? []).find((w) => w.slug === workspaceSlug) ?? null)
    : null;
  const { destinations, error } = useDestinationRows(workspaceSlug, row);

  const targets = useMemo<TransferTarget[] | null>(() => {
    if (!destinations) return null;
    return destinations
      .filter(
        (d): d is IntegrationDestination & { ecosystemId: string } =>
          typeof d.ecosystemId === "string" &&
          d.ecosystemId !== excludeEcosystemId &&
          // `manageable` is false only when the resolution DEFINITIVELY said this caller may see
          // the destination and not administer it — a plain organization member's own workspace
          // row. A transfer into it is a write, so offering it is a menu entry whose only
          // possible outcome is a 403 reported as "couldn't be transferred", with nothing in the
          // sentence saying the destination was never available in the first place.
          d.manageable,
      )
      .map((d) => ({
        ecosystemId: d.ecosystemId,
        label: d.label,
        sublabel: d.sublabel,
        kind: d.kind,
      }));
  }, [destinations, excludeEcosystemId]);

  return { targets, error: error ?? workspaces.error };
}
