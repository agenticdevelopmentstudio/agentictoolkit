"use client";

import { useEffect, useState, type ReactElement, type ReactNode } from "react";

import { ecosystemsApi, type Ecosystem, type EcosystemInput } from "@agentic-toolkit/data/ecosystems";
import {
  useMasterDetailForm,
  RecordSettingsPane,
  useRecordAffordance,
  unchangedFromStored,
} from "@agentic-toolkit/resource";
import { DeleteEntitySection } from "@agentic-toolkit/adh-ui/blocks";
import { isRdid, parseRdid, prefixFor } from "@agentic-toolkit/adh-ui/rdid";
import { ecoBlank, ecoToInput, ecoDiffers, ecoNormalize } from "./EcosystemDetail";
import {
  EcosystemFields,
  ecoCreateRdidValid,
  useRdidAvailability,
  type RdidAvailability,
} from "./EcosystemForm";

import { an } from "./lib/an";

/**
 * Settings editor for the active ecosystem — the SAME form as the New-Product dialog
 * (EcosystemFields: Display Name / Slug / derived read-only Identifier + availability
 * status / Description / disabled Geographic Region) plus the Danger Zone. The
 * identifier's type+scope are fixed (parsed from the saved rdid); editing the SLUG
 * re-derives it, live-probes availability, and saving sends that slug in the ordinary
 * PUT — which IS the rename, since the address is derived from the stored slug and the
 * route cascades the new one onto the handle and every descendant. The id this pane then
 * re-keys to is the server's derived answer (`updated.id`), not the typed identifier.
 *
 * THE FORM'S BASELINE IS THE DERIVED ADDRESS (prefix + the row's STORED SLUG), not the
 * stored rdid — see `savedIdentifier` below. The distinction is invisible on a healthy
 * row, where they are the same string, and it is the whole behaviour on a row whose
 * handle drifted from its slug.
 */
export function EcosystemSettingsPane({
  noun = "Ecosystem",
  ecosystemId,
  items,
  refresh,
  loadError,
  title,
  help,
  onDelete,
  onRenamed,
  renderTransferOwnership,
}: {
  /** The presented entity noun (capitalized) — see EcosystemsFeature's `labels` prop. */
  noun?: string;
  ecosystemId?: string;
  /** The ecosystems list, owned by the parent feature (shared with the selector). */
  items: Ecosystem[] | null;
  /** Re-read the list after a mutation (the parent feature's reload). */
  refresh: () => void | Promise<void>;
  loadError?: string | null;
  title?: ReactNode;
  help?: ReactNode;
  /** Delete the active ecosystem (and navigate away). Renders the Danger section. */
  onDelete?: () => Promise<void>;
  /** Called after a successful identifier rename with the new rdid, so the parent
   *  can refresh the selector list and navigate to the new id. */
  onRenamed?: (newId: string) => void | Promise<void>;
  /** Host-injected Transfer Ownership section, rendered above the Danger Zone. Absent on a
   *  standalone feature site — the hub owns the workspace list and the mutation. */
  renderTransferOwnership?: (ecosystem: { id: string; identifier: string }) => ReactNode;
}): ReactElement {
  // The host-injected per-record affordance (the hub's api-explorer button); null on
  // a standalone feature site → the trailing slot renders nothing.
  const renderRecordAffordance = useRecordAffordance();

  const active = items?.find((e) => e.id === ecosystemId);

  // The fixed identifier prefix: an rdid's own type+scope (so an owner-scoped product keeps
  // `ecosystem.<owner>.` and a legacy top-level row keeps `ecosystem.`). A rdid-less id
  // (uuid-addressed) falls back to top-level.
  //
  // Taken PER ROW rather than once from `active`, because `savedIdentifier` below is rebuilt from
  // it for whichever row the form hydrates from — and immediately after a rename that row is the
  // one the hook re-selected, while `active` (keyed off the `ecosystemId` PROP) is briefly absent
  // until the host navigates. Reading one row's slug through another row's prefix there would
  // report a save that succeeded as still-changed.
  const prefixForId = (id: string) =>
    isRdid(id) ? prefixFor("ecosystem", parseRdid(id).scope) : prefixFor("ecosystem");
  const prefixOf = (e: Ecosystem) => prefixForId(e.id);
  // The PANE's own prefix (what `leafOf`, `scope` and the probe target are built from) falls back
  // to the id the host is still pointing at, NOT to top-level, for that same gap: a rename moves a
  // row's leaf and never its scope, so the outgoing id carries the prefix the incoming row will
  // have. Collapsing to `ecosystem.` there would re-split a scoped address as if it were
  // top-level — `leafOf` would stop stripping the owner, and the form would call the row's own
  // identifier invalid the instant it saved successfully.
  const prefix = active ? prefixOf(active) : ecosystemId ? prefixForId(ecosystemId) : prefixFor("ecosystem");
  const scope = prefix.slice("ecosystem.".length).replace(/\.$/, "");
  const leafOf = (identifier: string) =>
    identifier.startsWith(prefix) ? identifier.slice(prefix.length) : identifier;

  // THE ADDRESS THE ROW DERIVES TO — its parent chain plus its STORED SLUG — which is what
  // this form edits and what a save is compared against. NOT `e.identifier`, the stored
  // handle: the two agree for every row whose handle was last written by a slug rename, and
  // disagree wherever a handle was written on its own (`PATCH /registry/identifiers/{rdid}`,
  // a backfill, or a pre-2026-08-10 rename that cascaded the descendants and left this row's
  // own handle behind — the hub's own product was in exactly that state). Seeding from the
  // handle showed a "Slug" that was not the slug: typing the row's REAL slug read as a
  // rename here, sent a value the server found unchanged, and saved nothing at all.
  const savedIdentifier = (e: Ecosystem) => prefixOf(e) + e.slug;

  // The probe verdict the form's `validate` reads. It is STATE (not the derived value
  // below) because validate runs INSIDE useMasterDetailForm during render — before the
  // derived value exists — and because a verdict change must re-render the pane so the
  // Save gate (canSave = dirty && valid) tracks it. The effect below keeps it current.
  const [status, setStatus] = useState<RdidAvailability>("idle");

  const form = useMasterDetailForm<Ecosystem, EcosystemInput>({
    items,
    getId: (e) => e.id,
    blank: ecoBlank,
    toInput: (e) => ({ ...ecoToInput(e), identifier: savedIdentifier(e) }),
    validate: (draft, others, base) => {
      if (!draft.name.trim()) return "Display name is required.";
      const slug = leafOf(draft.identifier.trim());
      if (!slug) return "Slug is required.";
      // WHETHER THIS IS A RENAME IS A FACT ABOUT THE INPUT BEING VALIDATED, never about the
      // render-scoped `status` (see the probe-gate comment below — that's the bug this fact was
      // introduced to fix). The same fact now ALSO gates the rdid-format check just below: a
      // stored identifier that predates today's format rule (or that used a legacy top-level
      // scope) must not block Save the instant an unrelated field is edited. `useMasterDetailForm`
      // used to grandfather that for us, by re-running `validate` on the stored record and waiving
      // a reason it reproduced — but that compared MESSAGES, so a stored failure could mask an
      // unrelated new one; grandfathering moved into each validator, rule by rule, hence this
      // explicit check (Mike, 2026-09-25).
      const renaming = !unchangedFromStored(draft.identifier, base?.identifier);
      if (renaming && !ecoCreateRdidValid(scope, slug))
        return `"${draft.identifier}" is not a valid identifier — lowercase letters, digits, and interior hyphens only.`;
      if (others.some((o) => o.identifier === draft.identifier))
        return `Identifier "${draft.identifier}" is already in use.`;
      // A rename (or a create) needs the probe's go-ahead — same bar as the create
      // dialog. An unchanged identifier skips it.
      //
      // Gated on `status` alone, the stored row reproduced "Waiting for the identifier
      // availability check." whenever the probe was checking or had errored, the old hook-level
      // waiver cleared it, and Save sent the rename without the probe's go-ahead — hence `renaming`
      // rather than `status` deciding whether these two rules apply at all.
      if (renaming && status === "unavailable") return `Identifier "${draft.identifier}" is already in use.`;
      if (renaming && status !== "idle" && status !== "available")
        return "Waiting for the identifier availability check.";
      return null;
    },
    differs: ecoDiffers,
    normalize: ecoNormalize,
    // No `create`: RecordSettingsPane passes `showCreate={false}` and nothing calls `startCreate`,
    // so this pane edits ONE existing record and its create was unreachable — a top-level
    // (unscoped) create at that, which since address derivation moved to the parent chain is not
    // even the shape this pane's own prefix describes. Creates live in EcosystemsFeature's dialogs.
    update: async (id, input) => {
      const updated = await ecosystemsApi.update(id, input);
      if (updated.id !== id) await onRenamed?.(updated.id);
      return updated;
    },
    // Delete is owned by the Danger-zone DeleteEntitySection (onDelete), not the hook.
    refresh,
  });

  // Availability probe over the DERIVED identifier — skipped (null → "idle") while it matches
  // the saved ADDRESS, so opening Settings shows no status until the slug changes.
  const draft = form.draft;
  const draftSlug = draft ? leafOf(draft.identifier.trim()) : "";
  // NOTHING TO COMPARE AGAINST IS NOT A CHANGE. `active` is absent for the moment between a
  // successful rename and the host navigating to the new id, and treating that as "changed" fired
  // the probe at the address the save had just minted — which of course exists, so the pane
  // answered a rename that WORKED with "already in use" and disabled its own Save. Dirtiness is
  // the form's (`form.dirty`); this flag only gates the availability probe, so withholding it
  // while the baseline is unknown withholds a question that has no meaning yet.
  const changed = draft != null && active != null && draft.identifier.trim() !== savedIdentifier(active);
  const grammarOk = draftSlug !== "" && ecoCreateRdidValid(scope, draftSlug);
  // AN ADDRESS THIS ROW ALREADY HOLDS IS NOT A COLLISION. `identifiersApi.exists` answers "does
  // anything own this rdid", and on a drifted row the answer for the row's OWN handle is yes —
  // itself. Probing it would report "already in use" and refuse the one save that heals the
  // drift (setting the slug to what the handle already says), which is the most likely thing a
  // user does when the two disagree. Unreachable on a healthy row: there the handle IS the saved
  // address, so `changed` is already false and nothing is probed.
  const targetsOwnHandle = active != null && grammarOk && prefix + draftSlug === active.id;
  const probe = useRdidAvailability(changed && grammarOk && !targetsOwnHandle ? prefix + draftSlug : null);
  const derivedStatus: RdidAvailability = !draft || !changed
    ? "idle"
    : !grammarOk
      ? "invalid"
      : targetsOwnHandle
        ? "available"
        : probe;
  useEffect(() => {
    if (derivedStatus !== status) setStatus(derivedStatus);
  }, [derivedStatus, status]);

  return (
    <RecordSettingsPane
      form={form}
      activeId={ecosystemId}
      items={items}
      getId={(e) => e.id}
      title={title}
      help={help}
      trailing={renderRecordAffordance?.({
        path: "/ecosystem/ecosystems/{id}",
        pathValues: { id: ecosystemId },
        title: `${noun} API`,
      })}
      loadError={loadError}
      emptyLabel={
        items === null
          ? "Loading…"
          : `Select ${an(noun.toLowerCase())} in the sidebar, or create a new one.`
      }
      renderDetail={(d) => (
        <div className="flex flex-col gap-6" key={form.detailKey}>
          <EcosystemFields
            prefix={prefix}
            name={d.name}
            slug={leafOf(d.identifier.trim())}
            description={d.description}
            region={d.region}
            status={derivedStatus}
            error={form.error}
            noun={noun.toLowerCase()}
            onName={(v) => form.onChange({ ...d, name: v })}
            onSlug={(v) => form.onChange({ ...d, identifier: prefix + v })}
            onDescription={(v) => form.onChange({ ...d, description: v })}
          />
          {active && renderTransferOwnership && renderTransferOwnership(active)}
          {active && onDelete && (
            <DeleteEntitySection
              entityNoun={noun}
              confirmValue={active.identifier}
              childEntities="applications, buckets, and users"
              onConfirm={onDelete}
            />
          )}
        </div>
      )}
    />
  );
}
