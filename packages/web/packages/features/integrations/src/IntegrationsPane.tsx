"use client";

import { useCallback, useMemo, useState } from "react";
import type { ReactNode } from "react";

import {
  Bookmark,
  Calendar,
  CreditCard,
  Landmark,
  ListTodo,
  Mail,
  MessageSquareText,
  MessagesSquare,
  Music,
  Plug,
  Share2,
  StickyNote,
  UserRound,
} from "lucide-react";
import { EmptyState } from "@agenticdevelopertoolkit/ui/components/empty-state";
import { TopicSelectHint } from "@agenticdevelopertoolkit/ui/blocks";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { AlertModal } from "@agenticdevelopertoolkit/ui/components/alert-modal";
import { useDualModeSelection } from "@agenticdevelopertoolkit/ui/hooks/useDualModeSelection";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import {
  integrationsApi,
  type MaskedProviderConfig,
  type ProviderCatalogEntry,
} from "@agentic-toolkit/data/integrations";
import { isForbidden, useResourceItemQuery, useResourceList } from "@agentic-toolkit/data";
import { useRecordAffordance } from "@agentic-toolkit/resource";
import { useMasterDetailForm } from "@agentic-toolkit/resource";
import { useMasterDetailLevel } from "@agentic-toolkit/resource";
import type { TopicLeaf } from "@agentic-toolkit/resource";
import {
  intBlank,
  intDiffers,
  intToBody,
  intToCreateBody,
  intToInput,
  intValidate,
  type IntegrationInput,
} from "./IntegrationDetail";
import { IntegrationDetailView } from "./IntegrationDetailView";
import { AddIntegrationModal } from "./AddIntegrationModal";

// The stand-ins for a list whose read FAILED. Module scope so each is one identity for the whole
// process: the derived `rows` memo compares on them, and a fresh `[]` per render would re-run the
// master/detail item effects on every pass.
const NO_CONFIGS: MaskedProviderConfig[] = [];
const NO_PROVIDERS: ProviderCatalogEntry[] = [];

// A leading icon per row keyed off the provider's FIRST service type (the icon-only rail strip
// needs every row to carry a glyph). Falls back to a generic plug for a service type not mapped
// here (or a provider with no service types).
const SERVICE_TYPE_ICONS: Record<string, ReactNode> = {
  email: <Mail />,
  sms: <MessageSquareText />,
  messaging: <MessagesSquare />,
  messages: <MessagesSquare />,
  calendar: <Calendar />,
  tasks: <ListTodo />,
  bookmarks: <Bookmark />,
  notes: <StickyNote />,
  music: <Music />,
  social: <Share2 />,
  profile: <UserRound />,
  financial: <Landmark />,
  billing: <CreditCard />,
};

/**
 * The row's ADDRESS — its rdid when it has one, else its uuid. Both are accepted by every by-id
 * integrations route (GET/PUT/DELETE resolve a uuid OR an rdid), so the uuid is a complete
 * substitute, and it is the only correct fallback: `rdid` is nullable (a row predating the mint,
 * or one whose canonical mapping an operator freed), and a null — like the `""` the API used to
 * send in its place — is not an identity. Keying on the raw field would collapse every unmapped
 * config in the list into one row, and hand the master/detail machine one shared id for all of
 * them. Every identity, key, and URL segment in this pane goes through here.
 */
export const addressOf = (r: MaskedProviderConfig): string => r.rdid ?? r.id;

/**
 * Merge the by-id fallback row into the loaded collection. Exported — with `addressOf` — so the
 * `null === null` trap is pinnable directly: comparing raw `rdid`s reads two DIFFERENT unmapped
 * configs as the same row, and the deep-linked one is then silently dropped from the list — a bug
 * no type check can see, because `null === null` is perfectly legal.
 */
export function mergeFetchedRow(
  configs: MaskedProviderConfig[],
  fetched: MaskedProviderConfig | null,
): MaskedProviderConfig[] {
  const list = [...configs];
  if (fetched && !list.some((c) => addressOf(c) === addressOf(fetched))) list.push(fetched);
  list.sort((a, b) => a.name.localeCompare(b.name));
  return list;
}

/**
 * Integrations settings pane — the ecosystem's provider-config INSTANCES as a master/detail.
 * Each row is one saved integration instance (`listProviderConfigs`), addressed by `addressOf`
 * (deep links are `…/integrations/<rdid-or-uuid>`); multiple instances of the same service are allowed,
 * so the row shows the instance NAME with the provider's category subtitle. Selecting a row
 * renders the shared `IntegrationDetailView` in `mode="saved"` (which owns its own Save and, for
 * OAuth-family providers, its connected-accounts manager). "Add integration" opens the two-pane
 * `AddIntegrationModal` over the stack; the created instance is selected so its detail opens when
 * the modal is closed. Removing an instance deletes its stored config + secret.
 */
export function IntegrationsPane({
  ecosystemId,
  providerIds,
  levelTitle = "Integrations",
  addFilter,
  leaf,
  onChanged,
}: {
  ecosystemId?: string;
  /**
   * Restrict the pane to these providers — the rows it LISTS and the catalog "Add integration"
   * offers. Omit for the whole catalog, which is what both existing hosts do.
   *
   * Its reason for existing is one integration record reachable from two places: the billing site
   * mounts this pane with `["stripe"]` rather than growing a Stripe form of its own, so setting
   * Stripe up there and setting it up under Integrations write the same
   * `integration.provider_config` row through the same routes. Two edit surfaces for one
   * credential is what makes drift inevitable rather than unlikely.
   */
  providerIds?: readonly string[];
  /** The published level's title. Defaults to "Integrations"; the billing site passes "Stripe",
   *  because a rail level called "Integrations" holding only Stripe rows, inside a site called
   *  Billing, names the wrong thing three times. */
  levelTitle?: string;
  /**
   * What the Add-integration picker's filter box starts on — passed straight through. Shipr's
   * Connections passes `"Code"`, so the picker opens on the forges instead of on the alphabet.
   *
   * Distinct from `providerIds`, which is a restriction: this is a starting value the operator
   * can see in the box and clear.
   */
  addFilter?: string;
  /** Accepted for the ScopedPane prop shape; the breadcrumb + level title name the pane now. */
  title?: ReactNode;
  /** Accepted for the ScopedPane prop shape; there is no button bar to host a "?" popover now. */
  help?: ReactNode;
  /** Deep-linkable instance selection (`…/integrations/<rdid-or-uuid>`). */
  leaf?: TopicLeaf;
  /**
   * A write to this ecosystem's provider configs SUCCEEDED — created, saved, rotated or removed.
   * Optional; this pane already refreshes its own list, so a host needs it only when it holds
   * state DERIVED from these rows that no longer agrees with them.
   *
   * The billing site is that host: `GET /billing/context`'s `stripeStatus` is read once above
   * the rail and cached at the client's staleTime, and Setup's "Connected" / "Not connected" line
   * plus its Connect-vs-Manage button are derived from it. Without a seam here, connecting Stripe
   * on this pane leaves Setup reporting the opposite for five minutes, with nothing on the page
   * able to correct it.
   *
   * Fired on the SUCCESS path only, never on a rejected write, and never on a rotation that
   * failed — a host uses this to re-read a fact, and re-reading after a failure would just paint
   * the same stale answer with more confidence.
   */
  onChanged?: () => void;
}) {
  // Creating is a MODAL over the stack (HTD `must-create-in-modal`): the `+` opens it, and on
  // add the new instance is selected so its REAL detail opens once the modal is dismissed.
  const [modalOpen, setModalOpen] = useState(false);

  // Cached by ecosystem, so coming back to Integrations paints the rows it already had and
  // revalidates behind them. `useCallback` is load-bearing: the hook treats a NEW fetcher identity
  // as "re-read", so an inline closure here would re-fetch on every render.
  //
  // The forbidden case is rewritten HERE, in the fetcher, because that is the only place still
  // holding the error object — the hook hands back a message, not a throwable. The rewrite keeps
  // `status` on the replacement: `reportUnexpectedAuthError` gates on it (anything under 500 is
  // dropped), so a bare `new Error` would start reporting the 403 this pane has always swallowed.
  const loadConfigs = useCallback(async () => {
    if (!ecosystemId) return [];
    try {
      return await integrationsApi.listProviderConfigs(ecosystemId);
    } catch (err) {
      if (!isForbidden(err)) throw err;
      throw Object.assign(new Error("You don't have access to this ecosystem's integrations."), {
        status: 403,
      });
    }
  }, [ecosystemId]);
  const {
    items: configs,
    reload: refreshConfigs,
    error: loadError,
    isFetching: configsFetching,
  } = useResourceList<MaskedProviderConfig>(
    `ecosystem:${ecosystemId ?? ""}:integrations`,
    loadConfigs,
  );

  // The provider catalog is ecosystem-independent, so it is cached WITHOUT a scope segment: every
  // ecosystem's pane reads the same rows, and after the first visit nobody fetches it again.
  const {
    items: providers,
    error: catalogError,
    isFetching: catalogFetching,
  } = useResourceList<ProviderCatalogEntry>("integrations:providers", integrationsApi.listProviders);

  // A failed read used to be substituted with `[]` so the pane didn't hang on "Loading…" forever;
  // the hook leaves `items` null instead, so make that substitution here — once, for both lists.
  // It matters most for the CATALOG: `rows` withholds every instance until the catalog has landed
  // (see the gate below), so a null-forever catalog would mean a pane that never shows a row.
  // The banners name both failures. Module-scope constants, because `rows` memoizes on these.
  const configRows = configs ?? (loadError ? NO_CONFIGS : null);
  const providerRows = providers ?? (catalogError ? NO_PROVIDERS : null);

  // The filter, applied at exactly the two derived values it must reach, and nowhere else.
  //
  // A Set hoisted through useMemo because both memos below depend on it: a fresh Set per render
  // would defeat `rows`'s memo, and `rows` is the `items` IDENTITY that useMasterDetailForm and
  // useMasterDetailLevel compare against — a new array each pass re-runs their item effects.
  // `providerIds` is a caller-owned array, so memoize on its joined text rather than its identity;
  // a host writing the array inline (which the billing site does) would otherwise pass a new one
  // every render.
  const providerFilterKey = providerIds ? providerIds.join(",") : null;
  const providerFilter = useMemo(
    () => (providerFilterKey === null ? null : new Set(providerFilterKey.split(","))),
    [providerFilterKey],
  );

  // The same filter, for a config resolved by ADDRESS rather than read off a list. A leaf naming a
  // config outside `providerIds` has to behave exactly like an address that does not exist —
  // otherwise a filtered host (the billing site passes `["stripe"]`) either falls through to the
  // generic "select an integration" hint with no explanation, or, for a config the list never
  // carried, fetches it by id and lets `mergeFetchedRow` splice the foreign provider into `rows`.
  const inFilter = useCallback(
    (c: MaskedProviderConfig | null | undefined): MaskedProviderConfig | null =>
      c && (providerFilter === null || providerFilter.has(c.providerId)) ? c : null,
    [providerFilter],
  );
  const visibleConfigRows = useMemo(
    () =>
      configRows === null || providerFilter === null
        ? configRows
        : configRows.filter((c) => providerFilter.has(c.providerId)),
    [configRows, providerFilter],
  );
  const offerableProviders = useMemo(
    () =>
      providerRows === null || providerFilter === null
        ? providerRows
        : providerRows.filter((p) => providerFilter.has(p.providerId)),
    [providerRows, providerFilter],
  );

  const providerById = useMemo(
    () => new Map((providerRows ?? []).map((p) => [p.providerId, p])),
    [providerRows],
  );

  // Selection is DUAL-MODE, and this hook is the pane's single copy of it.
  //
  // `leaf` is the URL contract: present when the host cedes a segment below the topic (the
  // Integrations site, and a billing host that threads `renderSubLeaf`), absent when it does not
  // (the hub's workspace rail and the products topic, which mount BillingGroup with internal
  // selection). Reading `leaf?.leafId` directly for the derived values below is what broke: with
  // no leaf that expression is permanently `null`, so `selectedInList` and therefore `cfg` were
  // permanently null while `useMasterDetailForm` — which runs its OWN `useDualModeSelection` —
  // held a perfectly good internal selection. The rail highlighted the clicked row (it reads
  // `form.selectedId`) and the detail below it rendered nothing, forever, on two of three hosts.
  //
  // One hook, therefore, owning the state for both: the pane reads `selectedId`, and the form is
  // handed `{ selectedId, select }` so its own dual-mode hook is always in url-driven mode
  // pointing here. Two hooks cannot disagree when only one of them holds state.
  const urlSelection = leaf ? { selectedId: leaf.leafId, onSelect: leaf.onSelect } : undefined;
  const { selectedId, select: setSelectedId } = useDualModeSelection(urlSelection);

  // The selected instance, resolved from the loaded list by its address.
  const selectedInList = (configRows ?? []).find((c) => addressOf(c) === selectedId) ?? null;

  // Fallback for a deep link the list hasn't surfaced yet (or an instance addressable by id but
  // not in the list): read the masked config by id/rdid so its detail still resolves.
  //
  // Keyed by the address asked for, which is what retires the old staleness filter: a reply for a
  // previous address is a DIFFERENT cache entry now, so it can no longer be mistaken for this one.
  // `useResourceItemQuery`, not `useResourceItem`: a config missing from the list is the ordinary
  // case here (that is the whole reason this read exists), and the composed hook would announce it
  // as deleted-on-the-server.
  const loadById = useCallback(
    (id: string) => integrationsApi.getProviderConfigById(ecosystemId ?? "", id),
    [ecosystemId],
  );
  // The item type carries the null: this endpoint answers "no such config" with a null body rather
  // than a 404, so it is a legitimate cached ANSWER and not an absence to re-ask for.
  const { item: fetchedCfg } = useResourceItemQuery<MaskedProviderConfig | null>(
    `ecosystem:${ecosystemId ?? ""}:integrations`,
    selectedId && ecosystemId && !selectedInList ? selectedId : null,
    loadById,
  );

  // Both routes pass through `inFilter`: the list one because the leaf may name a config the
  // filter hides, the by-id one because that read is keyed by address and knows nothing of it.
  const visibleFetchedCfg = inFilter(fetchedCfg);
  const cfg = inFilter(selectedInList) ?? visibleFetchedCfg;
  const provider = cfg ? providerById.get(cfg.providerId) : undefined;

  // One row per instance, sorted by name. The deep-linked instance is kept present even before
  // the list fetch surfaces it (resolved by-id above) so the level highlights it and the form
  // selects it.
  //
  // Gated on the provider catalog too (not just `configs`), because a leaf/param navigation
  // (e.g. right after Add) remounts this pane's subtree, refetching BOTH lists fresh — and if
  // the provider-configs fetch resolves first, the toolkit's `useMasterDetailForm` re-hydrate
  // effect would find the row in `items` immediately and seed the draft via `toInput` (=
  // `intToInput`) while `providerById` is still empty, permanently locking in a provider-less
  // draft with its api_key `fields` left blank (that effect only seeds once per selected id).
  // Withholding `rows` until the catalog has loaded keeps the row invisible to that effect
  // until `toInput` can resolve the provider.
  // Memoized: `rows` is the `items` identity `useMasterDetailForm`/`useMasterDetailLevel` compare
  // against, so a fresh array on every render would re-run their item effects each pass.
  const rows = useMemo<MaskedProviderConfig[] | null>(() => {
    if (visibleConfigRows === null || providerRows === null) return null;
    // On `addressOf` again — `c.rdid === fetchedCfg.rdid` would read `null === null` as a match
    // and swallow the deep-linked row whenever any OTHER unmapped config is in the list.
    return mergeFetchedRow(visibleConfigRows, visibleFetchedCfg);
  }, [visibleConfigRows, providerRows, visibleFetchedCfg]);

  // The master/detail machine drives selection (URL-keyed via `leaf`), the selected instance's
  // draft (seeded from `intToInput` on address change), the pane-exit unsaved-work guard, and the
  // delete flow. The saved-instance detail (`IntegrationDetailView`) owns its own Save button, so
  // this pane does NOT render a master-detail Save button bar — the guard's `update` is only the
  // background exit-save path; `create` is unused (creating is the modal). Delete is a
  // destructive control in the detail wired to `form.actions.onDelete` + the shared AlertModal.
  const form = useMasterDetailForm<MaskedProviderConfig, IntegrationInput>({
    items: rows,
    getId: addressOf,
    // Always supplied, even when this pane has no URL leaf: it points at the pane's own dual-mode
    // hook above, which is internal state in that case. The machine is therefore always in its
    // url-driven branch — which is what we want, since the re-hydrate effect that branch guards is
    // exactly how a selection made anywhere (the rail, a deep link, back/forward) reaches the
    // draft. `create()`'s `if (!url) setSelection(null)` is the one behaviour this skips, and this
    // pane never calls it: creating here is the modal (`onNew` below), not the inline form.
    urlSelection: { selectedId, onSelect: setSelectedId },
    blank: () => intBlank(""),
    toInput: (r) => intToInput(r, providerById.get(r.providerId)),
    validate: (draft) => intValidate(draft, providerById.get(draft.providerId), cfg),
    differs: intDiffers,
    create: (input) =>
      integrationsApi.createProviderConfig(
        ecosystemId ?? "",
        intToCreateBody(input, providerById.get(input.providerId)),
      ),
    // `id` is the machine's own id for the row being saved (`getId` = `addressOf`), and PUT
    // accepts a uuid OR an rdid — so address the row by it directly, whichever it is. Reaching
    // for `cfg?.id` instead would write to whatever instance is SELECTED right now, which on the
    // background exit-save path is not necessarily the row the machine is flushing.
    update: (id, input) =>
      integrationsApi.updateProviderConfig(ecosystemId ?? "", id, {
        name: input.name.trim(),
        ...intToBody(input, providerById.get(input.providerId)),
      }),
    // `await`ed rather than returned so `onChanged` fires only once the delete actually resolved —
    // a rejected delete leaves the row (and any host state derived from it) exactly as it was.
    remove: async (r) => {
      await integrationsApi.deleteProviderConfigById(ecosystemId ?? "", r.id);
      onChanged?.();
    },
    confirmDelete: (r) =>
      `Remove the "${r.name}" integration? This permanently deletes its stored configuration and secret.`,
    refresh: refreshConfigs,
    createLabel: "Add integration",
  });

  // The host-injected per-record affordance (the hub supplies its api-explorer button); null on
  // a standalone feature site → the detail's trailing row renders nothing at all.
  const renderRecordAffordance = useRecordAffordance();

  // The row's leading icon: the provider's first service type → a glyph (generic plug otherwise).
  const iconForRow = (r: MaskedProviderConfig): ReactNode => {
    const first = providerById.get(r.providerId)?.serviceTypes?.[0];
    return (first && SERVICE_TYPE_ICONS[first]) || <Plug />;
  };

  useMasterDetailLevel({
    id: "integrations-list",
    title: levelTitle,
    form,
    items: rows,
    getId: addressOf,
    getLabel: (r) => r.name,
    getSublabel: (r) => providerById.get(r.providerId)?.subtitle ?? "",
    getItemIcon: iconForRow,
    newLabel: "Add integration",
    leaf,
    // A failed load resolves to `[]` (see `configRows`), so name the error rather than hiding
    // it behind "No integrations yet.". Also checks the catalog (see the `rows` gate above) so
    // this doesn't misreport "No integrations yet." during the brief window where configs have
    // resolved but the catalog hasn't.
    emptyLabel: loadError
      ? "Couldn't load integrations."
      : configRows === null || providerRows === null
        ? "Loading…"
        : "No integrations yet.",
    // The spinner before "Integrations" — the only thing that says a revalidation is running behind
    // rows the cache already put on screen. Either read repaints these rows, so either one counts.
    busy: configsFetching || catalogFetching,
    onNew: () => setModalOpen(true),
  });

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <ErrorText error={loadError} className="px-6 pt-4" />
      <ErrorText error={catalogError} className="px-6 pt-4" />
      <div className="flex min-h-0 min-w-0 flex-1 flex-col overflow-y-auto px-6 py-4">
        {cfg && provider && form.draft ? (
          <div className="flex flex-col gap-6">
            {/* The row exists only when a host actually supplies an affordance — an empty
                flex row would otherwise open a gap above the detail on every standalone site. */}
            {renderRecordAffordance && (
              <div className="flex items-center justify-end">
                {renderRecordAffordance({
                  path: "/integrations/ecosystems/{ecosystemId}/provider-configs/{configId}",
                  pathValues: { ecosystemId, configId: cfg.id },
                  title: "Integration config API",
                })}
              </div>
            )}
            <IntegrationDetailView
              key={addressOf(cfg)}
              provider={provider}
              ecosystemId={ecosystemId ?? ""}
              mode="saved"
              config={cfg}
              draft={form.draft}
              onChange={form.onChange}
              // IntegrationDetailView owns Save and hands back the saved row directly, bypassing
              // the master-detail `form` — so its built-in re-hydrate-draft-from-saved-entity
              // never runs. Without this, a freshly-saved secret leaves `form.draft`'s secret
              // field holding the just-typed value while a re-derived baseline reads it blank
              // (secrets are never echoed back), so `intDiffers` stays true forever and the
              // pane-exit guard false-prompts "unsaved changes" on the next navigation. Reset the
              // draft here so it matches what the toolkit's own save() does.
              onSaved={(row) => {
                void refreshConfigs();
                form.onChange(intToInput(row, provider));
                onChanged?.();
              }}
              // A rotation touches nothing the operator typed, so it deliberately does NOT reset
              // the draft — only the cached list row, which is where `cfg` comes from and would
              // otherwise keep showing the retired webhook secret.
              onRotated={() => {
                void refreshConfigs();
                onChanged?.();
              }}
            />
            <div className="flex flex-col gap-2 border-t border-apt-border pt-6">
              <div>
                <Button variant="destructive" onClick={() => form.actions.onDelete()}>
                  Remove integration
                </Button>
              </div>
              <p className="text-xs text-apt-text-muted">
                Deletes this integration and its stored credentials. Connected accounts are
                removed separately, via Disconnect.
              </p>
            </div>
          </div>
        ) : // `selectedId`, not `leaf?.leafId` — see the dual-mode hook above. With a row selected
        // and only the CATALOG still loading, the leaf-only test fell through to the select nudge
        // on an internal-selection host, telling the operator to select the thing they had just
        // selected.
        selectedId && (configRows === null || providerRows === null) ? (
          <EmptyState title="Loading…" />
        ) : loadError ? (
          <EmptyState title="Couldn't load integrations." />
        ) : configRows === null ? (
          <EmptyState title="Loading…" />
        ) : (
          // Nothing selected and the list loaded: the almost-empty centered select-nudge, not a
          // dashed EmptyState — matches the workspace/feature rail's TopicSelectHint so an
          // unselected leaf reads the same everywhere.
          <TopicSelectHint title="Select an integration to configure, or add one." />
        )}
      </div>

      <AddIntegrationModal
        open={modalOpen}
        onOpenChange={setModalOpen}
        ecosystemId={ecosystemId ?? ""}
        providers={offerableProviders}
        initialFilter={addFilter}
        // Do NOT close the modal here — it stays open so the user can add another; it closes via
        // its own ✕/Escape. Selecting the new address means the created instance's detail is
        // showing once they DO close it.
        // `form.select`, not `leaf?.onSelect`: the leaf is absent whenever the host cedes no URL
        // segment for the inner entity, and the optional chain silently did nothing there — so a
        // freshly added integration was the one row whose detail never opened, while every
        // existing row selected fine. The form's own setter routes to the URL when URL-driven and
        // to internal state otherwise, so the new row opens on every host.
        onAdded={(row) => {
          void refreshConfigs();
          onChanged?.();
          form.select(addressOf(row));
        }}
      />

      {/* Delete confirm — the shared AlertModal, driven by the master-detail form's delete flow. */}
      <AlertModal
        open={form.actions.deletePrompt != null}
        tone="error"
        title="Confirm deletion"
        description={form.actions.deletePrompt ?? undefined}
        confirmLabel="Delete"
        confirmVariant="destructive"
        cancelLabel="Cancel"
        busy={form.actions.deleting}
        onConfirm={() => form.actions.onConfirmDelete?.()}
        onCancel={() => form.actions.onCancelDelete?.()}
      />
    </div>
  );
}
