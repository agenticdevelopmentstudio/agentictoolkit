"use client";

import { useCallback, useMemo, useRef, useState } from "react";
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
import { BatchSelectButton, ButtonBar, TopicSelectHint, useBatchSelect } from "@agenticdevelopertoolkit/ui/blocks";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@agenticdevelopertoolkit/ui/components/dialog";
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
import { ToolbarPortal } from "@agentic-toolkit/resource";
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
import {
  IntegrationDetailBody,
  IntegrationTestReport,
  useIntegrationSubmit,
  useIntegrationTest,
  type IntegrationSubmit,
  type IntegrationTest,
} from "./IntegrationDetailView";
import { useIntegrationBulkActions } from "./integrationBulkActions";
import { useTransferTargets } from "./destinations";
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

/** What the button bar's Save and Test drive when a row is open — see {@link SelectedIntegration}. */
interface IntegrationEditor {
  submit: IntegrationSubmit;
  test: IntegrationTest;
}

/**
 * Integrations settings pane — the ecosystem's provider-config INSTANCES as a master/detail.
 * Each row is one saved integration instance (`listProviderConfigs`), addressed by `addressOf`
 * (deep links are `…/integrations/<rdid-or-uuid>`); multiple instances of the same service are allowed,
 * so the row shows the instance NAME with the provider's category subtitle. Selecting a row
 * renders the shared `IntegrationDetailBody` in `mode="saved"` (which owns its connected-accounts
 * manager and its synced-data section).
 *
 * THE PANE OWNS A BUTTON BAR, published into the rail host's toolbar slot above the list:
 * Add · Remove · Select · Export · Import · Test · Transfer, and Save at the far end. Every verb
 * but Add and Import acts on a SET of rows — the ticked ones in Select mode, the open one
 * otherwise — which is why the same button reads sensibly with one row or four.
 */
export function IntegrationsPane({
  ecosystemId,
  providerIds,
  levelTitle = "Integrations",
  workspaceSlug,
  dialogSurfaceClassName,
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
   * The workspace these integrations are being administered from, as a SLUG — which is what
   * decides whether the bar offers Transfer at all, and what the list of destinations is read
   * from (`useTransferTargets`).
   *
   * Omitted by a host that has no workspace in hand. Transfer is then absent rather than empty:
   * a disabled button with nothing behind it says "there is nowhere to move this", which is a
   * claim about the account, and this is a fact about the HOST.
   */
  workspaceSlug?: string;
  /**
   * The class a HOST's dialog surface carries, forwarded to the dialogs this pane opens.
   *
   * It exists because those dialogs render into a portal on `document.body`, so anything the host
   * set on its own dialog — shipr sets the shared button floor, `--adh-button-min-*` — cannot
   * inherit into them. A confirm opened from inside a host's dialog would otherwise be the one
   * surface in the flow with different buttons. Omitted by a host that styles nothing.
   */
  dialogSurfaceClassName?: string;
  /** Accepted for the ScopedPane prop shape; the breadcrumb + level title name the pane now. */
  title?: ReactNode;
  /** Accepted for the ScopedPane prop shape; the bar has no "?" popover. */
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
   *
   * ALSO FIRED WHEN AN INSTALLATION ADOPT LANDS, which is not a write to a provider config at all
   * and is here anyway, because it is the same question with a different subject: something about
   * this ecosystem's integrations is now true that was not true a moment ago, re-read it. Shipr is
   * the host that needs it — the adopt is what creates the connection rows its repository picker
   * is a list of, and pressing Test told nobody. A second seam for it would have exactly one
   * subscriber doing exactly what this one already does.
   */
  onChanged?: () => void;
}) {
  // Creating is a MODAL over the stack (HTD `must-create-in-modal`): the bar's Add opens it, and
  // on add the new instance is selected so its REAL detail opens once the modal is dismissed.
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
  // `providerIds` is a caller-owned array, so memoize on its SERIALIZED form rather than its
  // identity; a host writing the array inline (which the billing site does) would otherwise pass a
  // new one every render.
  //
  // JSON rather than `join(",")`, because a join is not reversible and `split` proved it twice
  // over: `[]` joined to `""` and split back to `[""]` — a filter matching the one provider id
  // that cannot exist, i.e. a pane showing nothing and offering nothing, for a host that asked
  // for nothing. (A provider id containing a comma would divide in two the same way.) The round
  // trip has to be exact, because what comes out of it IS the filter.
  const providerFilterKey = providerIds ? JSON.stringify([...providerIds]) : null;
  const providerFilter = useMemo(
    () =>
      providerFilterKey === null
        ? null
        : new Set<string>(JSON.parse(providerFilterKey) as string[]),
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
  // draft (seeded from `intToInput` on address change) and the pane-exit unsaved-work guard.
  //
  // It has NO `remove`/`confirmDelete` any more, and that is the point: deletion is the bar's
  // Remove, which takes a SET of rows and has to behave identically whether that set is one row
  // or four. Two delete paths meant two confirmations with two wordings, one of which could only
  // ever delete the open row. `create` is unused (creating is the modal).
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

  // ——— the bar ———————————————————————————————————————————————————————————————————————————

  // Select mode. The reset key is a PRIMITIVE and deliberately not `rows`: a tick set must survive
  // a background revalidation of the very list it points into, and must NOT survive the pane being
  // repointed at another ecosystem or narrowed to another provider, where the ticked addresses
  // name rows that are no longer on screen.
  const batch = useBatchSelect({ resetKey: `${ecosystemId ?? ""}|${providerFilterKey ?? ""}` });
  const toggleChecked = useCallback(
    (id: string) => {
      const next = new Set(batch.selectedIds);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      batch.setSelectedIds(next);
    },
    [batch],
  );

  const bulk = useIntegrationBulkActions({
    ecosystemId: ecosystemId ?? "",
    providerById,
    existing: configRows ?? NO_CONFIGS,
    refresh: refreshConfigs,
    onChanged,
  });

  /**
   * WHAT THE BAR ACTS ON. Ticked rows in Select mode; the open row otherwise.
   *
   * One rule for both, rather than a bulk bar and a single bar that happen to share buttons: the
   * operator who ticks one row and the operator who opens it mean the same thing by "Remove", and
   * a Remove that silently meant the open row while four were ticked is the accident this avoids.
   */
  const targetRows = useMemo<MaskedProviderConfig[]>(() => {
    if (batch.active) return (rows ?? []).filter((r) => batch.selectedIds.has(addressOf(r)));
    return cfg ? [cfg] : [];
  }, [batch.active, batch.selectedIds, rows, cfg]);

  // Only rows the catalog says can be tested — see `provider.testable`, which the backend derives
  // from the same condition its test route dispatches on. Testing the others would spend a
  // round-trip to be told the provider has no validation endpoint.
  const testableRows = useMemo(
    () => targetRows.filter((r) => providerById.get(r.providerId)?.testable),
    [targetRows, providerById],
  );

  // BOTH halves of the answer. Dropping `error` was the whole defect: a failed read leaves
  // `targets` null forever, which is indistinguishable from a read still in flight, so Transfer
  // greyed itself permanently and said nothing at all.
  const { targets: transferTargets, error: transferTargetsError } = useTransferTargets(
    workspaceSlug,
    ecosystemId,
  );
  const [transferOpen, setTransferOpen] = useState(false);
  const [transferTo, setTransferTo] = useState("");
  const [removeOpen, setRemoveOpen] = useState(false);
  const importInput = useRef<HTMLInputElement>(null);

  const barBusy = bulk.busy !== null;

  /**
   * Why the bulk Test is grey, in the operator's terms. Never reached while a row is open and
   * nothing is ticked — that arm is the EDITOR's test and has its own sentence.
   */
  const bulkTestBlockedReason =
    targetRows.length === 0
      ? "Select an integration to test."
      : testableRows.length === 0
        ? targetRows.length === 1
          ? "This provider has no test."
          : "None of the selected integrations has a test."
        : null;

  /**
   * Why Transfer is grey, when the reason is not the selection.
   *
   * `(targets?.length ?? 0) === 0` read all three of these as the same thing and printed none of
   * them: a list still loading, a list whose read FAILED, and a workspace that genuinely has
   * nowhere else to put an integration are three different answers, and only the last one is
   * about the account.
   */
  const transferBlockedReason = transferTargetsError
    ? transferTargetsError
    : transferTargets === null
      ? "Still reading where these could go."
      : transferTargets.length === 0
        ? "There is nowhere else in this workspace to move these to."
        : null;

  /**
   * Does this row answer to that address?
   *
   * A row has TWO — its rdid and its uuid — and every by-id integrations route accepts either, so
   * a URL can legitimately carry the one `addressOf` did not pick. Comparing `addressOf(row)`
   * against the raw route param therefore misses exactly the deep link that named the row by its
   * uuid, and the pane is left selected on an address the server has just deleted.
   */
  const answersTo = (r: MaskedProviderConfig, address: string): boolean =>
    address === r.id || address === r.rdid;

  /**
   * These rows have LEFT this ecosystem — deleted, or transferred away.
   *
   * Only the ones that actually went, which is the whole point. A batch settles per row, so a
   * partly refused Remove leaves rows that are still here and still ticked; unticking the whole
   * selection tells the operator their Remove succeeded, and clearing the open row throws away
   * whatever they had typed into a row nobody deleted (`useMasterDetailForm` holds the draft in
   * plain state, and its re-hydrate effect sets it back to null).
   */
  const forget = (gone: readonly MaskedProviderConfig[]) => {
    if (gone.length === 0) return;
    if (selectedId && gone.some((r) => answersTo(r, selectedId))) setSelectedId(null);
    const goneIds = new Set(gone.map(addressOf));
    batch.setSelectedIds(new Set([...batch.selectedIds].filter((id) => !goneIds.has(id))));
  };

  const confirmRemove = async () => {
    setRemoveOpen(false);
    forget(await bulk.remove(targetRows));
  };

  const confirmTransfer = async () => {
    const target = transferTo;
    setTransferOpen(false);
    forget(await bulk.transfer(targetRows, target));
  };

  /**
   * The bar, rendered into the rail host's toolbar slot — or in place, on a host that offers no
   * slot (`ToolbarPortal` falls back to its children).
   *
   * A RENDER PROP because exactly one of these may be live at a time: two portals into the same
   * node stack two toolbars. The `editor` is non-null only while a row is open, and it comes from
   * {@link SelectedIntegration} — the keyed component that owns the submit/test hooks — because
   * those hooks cannot be called here: they need a resolved provider and draft, and
   * `useIntegrationSubmit` captures its baseline once per mount.
   */
  const renderBar = (editor: IntegrationEditor | null) => (
    <ToolbarPortal>
      <ButtonBar ariaLabel="Integration actions">
        <Button size="sm" variant="ghost" onClick={() => setModalOpen(true)}>
          Add
        </Button>
        <div className="mx-1 h-5 w-px bg-apt-border" aria-hidden />
        <Button
          size="sm"
          variant="ghost"
          disabled={targetRows.length === 0 || barBusy}
          onClick={() => setRemoveOpen(true)}
        >
          Remove
        </Button>
        <BatchSelectButton batch={batch} />
        <Button
          size="sm"
          variant="ghost"
          disabled={targetRows.length === 0 || barBusy}
          onClick={() => void bulk.exportRows(targetRows)}
        >
          Export
        </Button>
        <Button
          size="sm"
          variant="ghost"
          disabled={barBusy || !ecosystemId}
          onClick={() => importInput.current?.click()}
        >
          Import
        </Button>
        <Button
          size="sm"
          variant="ghost"
          // With one row open and no ticks, Test is the EDITOR's test: it knows about an unsaved
          // edit ("Save your changes before testing them."), and its answer belongs in the card
          // beside the credentials it is about. A ticked set has no such card, so it takes the
          // bulk path and reports in the pane.
          disabled={
            editor && !batch.active
              ? !editor.test.available || editor.test.blockedReason !== null || editor.test.busy
              : bulkTestBlockedReason !== null || barBusy
          }
          title={
            (editor && !batch.active ? editor.test.blockedReason : bulkTestBlockedReason) ??
            undefined
          }
          onClick={() =>
            // The WHOLE target set, not the testable part of it: the hook skips the rest and
            // reports them by name. Filtering here is what made a four-row batch come back with
            // two answers and no account of the other two.
            void (editor && !batch.active ? editor.test.run() : bulk.test(targetRows))
          }
        >
          Test
        </Button>
        {workspaceSlug && (
          <Button
            size="sm"
            variant="ghost"
            disabled={targetRows.length === 0 || barBusy || transferBlockedReason !== null}
            title={transferBlockedReason ?? undefined}
            onClick={() => {
              setTransferTo(transferTargets?.[0]?.ecosystemId ?? "");
              setTransferOpen(true);
            }}
          >
            Transfer
          </Button>
        )}
        <div className="flex-1" />
        {editor && (
          <Button
            size="sm"
            disabled={!editor.submit.canSubmit || editor.submit.busy}
            onClick={() => void editor.submit.run()}
          >
            {editor.submit.busy ? editor.submit.busyLabel : editor.submit.label}
          </Button>
        )}
      </ButtonBar>
    </ToolbarPortal>
  );

  /**
   * What the bulk verbs had to say, INLINE in the pane rather than in a dialog.
   *
   * This pane is mounted inside shipr's Connections dialog, and a second Dialog over a Dialog is
   * a stack this does not need to take on for a report nobody has to acknowledge. It is also the
   * right shape: a test of four integrations is four answers to read side by side, not four
   * modals to dismiss in turn.
   */
  const reports =
    bulk.error || bulk.testRows || bulk.importReport || bulk.transferReport ? (
      <div className="flex flex-col gap-3 rounded-lg border border-apt-border p-4">
        <ErrorText error={bulk.error} />
        {bulk.transferReport && <p className="text-sm text-apt-green">{bulk.transferReport}</p>}
        {bulk.testRows?.map((row) => (
          <div key={row.id} className="flex flex-col gap-1">
            <p className="text-sm font-medium text-apt-text">{row.name}</p>
            {row.skipped ? (
              // Not red. Nothing failed — this provider has no validation endpoint, and the row
              // is here so a batch of four that tested two says which two.
              <p className="text-sm text-apt-text-muted">This provider has no test.</p>
            ) : row.result ? (
              <IntegrationTestReport result={row.result} />
            ) : (
              <p className="text-sm text-apt-red">{row.error}</p>
            )}
          </div>
        ))}
        {bulk.importReport && (
          <div className="flex flex-col gap-2">
            <p className="text-sm text-apt-text">
              {bulk.importReport.created.length === 0
                ? "Nothing new was imported."
                : `Imported ${bulk.importReport.created.join(", ")}.`}
            </p>
            {/* The list the operator asked to be shown at the end of an import. Duplicates are
                skipped, not merged — see `splitImport` — so this is the whole account of what
                the file contained and this ecosystem already had. */}
            {bulk.importReport.duplicates.length > 0 && (
              <div>
                <p className="text-xs font-medium text-apt-text-muted">Already here, skipped</p>
                <ul className="text-xs text-apt-text-muted">
                  {bulk.importReport.duplicates.map((e) => (
                    <li key={`${e.providerId} ${e.name}`}>{e.name}</li>
                  ))}
                </ul>
              </div>
            )}
            {bulk.importReport.unknownProviders.length > 0 && (
              <div>
                <p className="text-xs font-medium text-apt-text-muted">
                  No such provider in this console
                </p>
                <ul className="text-xs text-apt-text-muted">
                  {bulk.importReport.unknownProviders.map((e) => (
                    <li key={`${e.providerId} ${e.name}`}>
                      {e.name} ({e.providerId})
                    </li>
                  ))}
                </ul>
              </div>
            )}
            {bulk.importReport.failed.length > 0 && (
              <div>
                <p className="text-xs font-medium text-apt-red">Couldn&rsquo;t be created</p>
                <ul className="text-xs text-apt-red">
                  {bulk.importReport.failed.map((f) => (
                    <li key={f.name}>
                      {f.name}: {f.error}
                    </li>
                  ))}
                </ul>
              </div>
            )}
            {/* An import carries no secrets — the API has never echoed one back — so a row it
                created needs its credential typed in before it will do anything. WHICH rows and
                WHICH credentials, from the document's own `needsSecrets`: a provider configured
                without a client secret owes nothing and must not be listed as owing one. */}
            {bulk.importReport.needsSecrets.length > 0 && (
              <div>
                <p className="text-xs font-medium text-apt-text-muted">
                  Open these and enter their credentials
                </p>
                <ul className="text-xs text-apt-text-muted">
                  {bulk.importReport.needsSecrets.map((n) => (
                    <li key={n.name}>
                      {n.name}: {n.labels.join(", ")}
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </div>
        )}
        <div>
          <Button size="sm" variant="ghost" onClick={bulk.dismiss}>
            Dismiss
          </Button>
        </div>
      </div>
    ) : null;

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
    // The rail's `+` is GONE: the bar above it has a labelled Add, and two creators in one field
    // of view — one of them a bare glyph — is one more than anybody can name.
    showNew: false,
    checkable: batch.active,
    checkedIds: batch.selectedIds,
    onToggleChecked: toggleChecked,
  });

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <ErrorText error={loadError} className="px-6 pt-4" />
      <ErrorText error={catalogError} className="px-6 pt-4" />
      {/* Only on a host that offers Transfer at all — elsewhere this read answers about a
          workspace nothing on screen is going to ask about. */}
      {workspaceSlug && <ErrorText error={transferTargetsError} className="px-6 pt-4" />}
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
            <SelectedIntegration
              // Per ROW, because `useIntegrationSubmit` captures its baseline once per mount:
              // without this, switching rows would compare the new row's draft against the old
              // row's stored values and Save would be enabled (or greyed) on the wrong evidence.
              key={addressOf(cfg)}
              provider={provider}
              ecosystemId={ecosystemId ?? ""}
              config={cfg}
              draft={form.draft}
              onChange={form.onChange}
              // The detail owns Save and hands back the saved row directly, bypassing the
              // master-detail `form` — so its built-in re-hydrate-draft-from-saved-entity never
              // runs. Without this, a freshly-saved secret leaves `form.draft`'s secret field
              // holding the just-typed value while a re-derived baseline reads it blank (secrets
              // are never echoed back), so `intDiffers` stays true forever and the pane-exit
              // guard false-prompts "unsaved changes" on the next navigation. Reset the draft
              // here so it matches what the toolkit's own save() does.
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
              // Test, or the download a save fires behind itself, has finished enumerating the
              // provider's accounts. No config row moved, so the list is not re-read — but the
              // host's account-derived state did, and this is the only thing that says so.
              onAdopted={() => onChanged?.()}
              renderBar={renderBar}
              reports={reports}
              dialogSurfaceClassName={dialogSurfaceClassName}
            />
          </div>
        ) : (
          // NO ROW OPEN — loading, failed, or simply nothing picked. The bar is published from
          // here in every one of those states, because it is the PANE's bar and not the editor's:
          // Add and Import are exactly what an operator wants in front of an empty list and a
          // failed one, and the toolbar slot collapses when it is left empty
          // (`has-[[data-adh-toolbar-slot]:empty]:hidden`), so those were the states with no
          // action bar at all — including the first paint of every single visit.
          //
          // One `ToolbarPortal` is live at a time and this is the other one: the branch above
          // renders the editor's, through `SelectedIntegration`.
          <div className="flex min-h-0 flex-1 flex-col gap-6">
            {renderBar(null)}
            {reports}
            {/* `selectedId`, not `leaf?.leafId` — see the dual-mode hook above. With a row
                selected and only the CATALOG still loading, the leaf-only test fell through to
                the select nudge on an internal-selection host, telling the operator to select the
                thing they had just selected. */}
            {selectedId && (configRows === null || providerRows === null) ? (
              <EmptyState title="Loading…" />
            ) : loadError ? (
              <EmptyState
                title="Couldn't load integrations."
                // The read is retried from HERE, because there is nowhere else: the rail level
                // shows the same failure with no control on it, and a reload of the page is a
                // heavier answer than re-asking one endpoint.
                action={
                  <Button
                    size="sm"
                    variant="ghost"
                    disabled={configsFetching}
                    onClick={() => void refreshConfigs()}
                  >
                    {configsFetching ? "Trying…" : "Try again"}
                  </Button>
                }
              />
            ) : configRows === null ? (
              <EmptyState title="Loading…" />
            ) : (
              <TopicSelectHint title="Select an integration to configure, or add one." />
            )}
          </div>
        )}
      </div>

      {/* The import file picker. A bare native input rather than a control, because there is no
          styled file input in the shared package and this one is never seen: the bar's Import
          button clicks it. `value` is cleared on every change so that re-picking THE SAME file
          fires `change` again — a fixed export re-imported is the ordinary second attempt. */}
      <input
        ref={importInput}
        type="file"
        accept="application/json,.json"
        className="sr-only"
        onChange={(e) => {
          const file = e.target.files?.[0];
          e.target.value = "";
          if (file) void bulk.importFile(file);
        }}
      />

      <AddIntegrationModal
        dialogSurfaceClassName={dialogSurfaceClassName}
        open={modalOpen}
        onOpenChange={setModalOpen}
        ecosystemId={ecosystemId ?? ""}
        providers={offerableProviders}
        // The add's own background installation download has landed. `onAdded` already fired
        // — minutes earlier in forge time — and the host re-read its connection list then,
        // before this integration had a connection to find. THIS is the second read, and it
        // is the one that returns the new account.
        onAdopted={() => onChanged?.()}
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

      {/* Remove confirm — the one deletion path, for one row or four. */}
      <AlertModal
        contentClassName={dialogSurfaceClassName}
        open={removeOpen}
        tone="error"
        title="Confirm deletion"
        description={
          targetRows.length === 1
            ? `Remove the "${targetRows[0]!.name}" integration? This permanently deletes its stored configuration and secret.`
            : `Remove ${targetRows.length} integrations? This permanently deletes their stored configurations and secrets.`
        }
        confirmLabel="Delete"
        confirmVariant="destructive"
        destructive
        cancelLabel="Cancel"
        busy={bulk.busy === "remove"}
        onConfirm={() => void confirmRemove()}
        onCancel={() => setRemoveOpen(false)}
      />

      {/*
        Transfer confirm — a Dialog, not an `AlertModal`.

        It asks a QUESTION with a field in it, and `AlertModal` has no body slot: the chooser was
        passed as `description`, which Base UI renders as a `<p>`. A `<select>` inside a paragraph
        is legal, but the surrounding `<div>` and `<p>` are not — `<p>` may not nest, so the parser
        closes the outer one and re-parents everything after it, which is the same hazard
        `ConfirmDialog` documents in shipr's `toolbar/dialogs.tsx`. The chooser also had no label
        a screen reader could reach; `description` is read as the dialog's description, not as a
        name for the control inside it.

        `MoveDialog` is the shape: header, a labelled field in the body, actions on the bottom
        edge. Transfer and Cancel because a transfer with no destination named is not a thing to
        confirm — and because that is what was asked for.
      */}
      <Dialog open={transferOpen} onOpenChange={(next) => !next && setTransferOpen(false)}>
        <DialogContent className={dialogSurfaceClassName}>
          <DialogHeader>
            <DialogTitle>Transfer integrations</DialogTitle>
          </DialogHeader>
          <div className="flex flex-col gap-2">
            <Label htmlFor="int-transfer-target">
              {targetRows.length === 1
                ? `Move "${targetRows[0]?.name ?? ""}" — with its connected accounts — to`
                : `Move ${targetRows.length} integrations — with their connected accounts — to`}
            </Label>
            <Select
              id="int-transfer-target"
              value={transferTo}
              onChange={(e) => setTransferTo(e.target.value)}
            >
              {(transferTargets ?? []).map((t) => (
                <option key={t.ecosystemId} value={t.ecosystemId}>
                  {t.label} — {t.sublabel}
                </option>
              ))}
            </Select>
          </div>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setTransferOpen(false)}>
              Cancel
            </Button>
            <Button
              disabled={bulk.busy === "transfer" || !transferTo}
              onClick={() => void confirmTransfer()}
            >
              {bulk.busy === "transfer" ? "Transferring…" : "Transfer"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

/**
 * THE OPEN ROW — its two hooks, its button bar, and its cards.
 *
 * A component rather than three calls in the pane, for one reason that is not style:
 * `useIntegrationSubmit` captures the stored baseline ONCE per mount, so the thing that composes
 * it has to be remounted per row (`key={addressOf(cfg)}` above). It also needs a resolved
 * provider and a non-null draft, neither of which the pane has on every render — and hooks
 * cannot be called conditionally.
 *
 * It renders the bar as well as the body because the bar's Save and Test are ITS state, and
 * because exactly one `ToolbarPortal` may be live: the pane renders the other one, in the branch
 * where no row is open.
 */
function SelectedIntegration({
  provider,
  ecosystemId,
  config,
  draft,
  onChange,
  onSaved,
  onRotated,
  onAdopted,
  renderBar,
  reports,
  dialogSurfaceClassName,
}: {
  provider: ProviderCatalogEntry;
  ecosystemId: string;
  config: MaskedProviderConfig;
  draft: IntegrationInput;
  onChange: (next: IntegrationInput) => void;
  onSaved: (row: MaskedProviderConfig) => void;
  onRotated: () => void;
  onAdopted: () => void;
  renderBar: (editor: IntegrationEditor) => ReactNode;
  reports: ReactNode;
  /** Handed down to the connect / disconnect dialogs the body opens. */
  dialogSurfaceClassName?: string;
}) {
  const submit = useIntegrationSubmit({
    provider,
    ecosystemId,
    mode: "saved",
    config,
    draft,
    onChange,
    onSaved,
    onAdopted,
  });
  const test = useIntegrationTest({
    provider,
    ecosystemId,
    mode: "saved",
    config,
    draft,
    dirty: submit.dirty,
    onAdopted,
  });

  return (
    <>
      {renderBar({ submit, test })}
      {reports}
      <IntegrationDetailBody
        provider={provider}
        ecosystemId={ecosystemId}
        mode="saved"
        config={config}
        draft={draft}
        onChange={onChange}
        onRotated={onRotated}
        onAdopted={onAdopted}
        submit={submit}
        test={test}
        // Both buttons are in the bar above the list now. What stays here either way is what the
        // provider ANSWERED and why a button is grey — both are about these fields, and an
        // explanation orphaned from the field that caused it explains nothing.
        hideSubmit
        hideTest
      />
    </>
  );
}
