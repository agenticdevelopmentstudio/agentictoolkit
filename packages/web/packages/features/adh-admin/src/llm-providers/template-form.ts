// Pure form-state <-> wire logic for the provider-template dialog, split out
// from the component so the (subtle) submit-body assembly is unit-testable
// without a DOM — mirrors connection-spec-draft.ts's pure-conversion split.

import type { ProviderTemplate, TemplateSyncKeys } from "../api/llm-providers";
import {
  draftFromConnectionSpec,
  connectionSpecFromDraft,
  validateConnectionSpecDraft,
  type ConnectionSpecDraft,
} from "./connection-spec-draft";

// Derived from the generated schema rather than hand-declared, so adding a
// modality backend-side fails this file's tsc (MODALITIES stops being complete)
// instead of drifting silently.
export type Modality = NonNullable<ProviderTemplate["modalities"]>[number];
export const MODALITIES: Modality[] = ["chat", "image", "video"];

/**
 * Modalities in the fixed MODALITIES order, deduped. Both the seeded `initial`
 * state and every checkbox toggle run through this so the array is ORDER-STABLE:
 * dirtiness is a `JSON.stringify` comparison against `initial`, so appending a
 * re-checked modality at the end (`["image","chat"]`) would report unsaved
 * changes — and rewrite the jsonb column reordered — for a no-op edit.
 */
export function canonicalModalities(values: readonly Modality[]): Modality[] {
  return MODALITIES.filter((m) => values.includes(m));
}

/** Check/uncheck one modality, keeping the canonical order (see above). */
export function toggleModality(
  current: readonly Modality[],
  modality: Modality,
  checked: boolean,
): Modality[] {
  return canonicalModalities(
    checked ? [...current, modality] : current.filter((m) => m !== modality),
  );
}

export interface TemplateFormState {
  providerKind: ProviderTemplate["providerKind"];
  name: string;
  baseUrl: string;
  documentationUrl: string;
  statusUrl: string;
  models: string[];
  modalities: Modality[];
  availableViaNote: string;
  availableViaTemplates: string;
  syncModelsDev: string;
  syncOpenrouter: string;
  syncArenaVendor: string;
  spec: ConnectionSpecDraft;
}

/** The three form fields mirroring the stored sync mapping. */
export type SyncKeyField = "syncModelsDev" | "syncOpenrouter" | "syncArenaVendor";

/**
 * The ONE place the wire sync mapping maps onto form fields — used both to seed
 * `initial` and to push a (re)loaded mapping into the live form, so the two can't
 * drift. A cleared (`null`) mapping blanks the fields rather than leaving stale
 * text behind.
 */
export function syncKeyFields(
  syncKeys: TemplateSyncKeys | undefined,
): Pick<TemplateFormState, SyncKeyField> {
  return {
    syncModelsDev: syncKeys?.modelsDev ?? "",
    syncOpenrouter: syncKeys?.openrouter ?? "",
    syncArenaVendor: syncKeys?.arenaVendor ?? "",
  };
}

/** Overwrite the form's sync-key fields with a freshly loaded mapping. */
export function applySyncKeys(
  form: TemplateFormState,
  syncKeys: TemplateSyncKeys | undefined,
): TemplateFormState {
  return { ...form, ...syncKeyFields(syncKeys) };
}

/**
 * Identity of a loaded mapping, so the dialog can tell a REFRESHED fetch (apply
 * it — the operator just saved a new mapping, or another admin changed it) from
 * a redundant one (skip — don't clobber an in-progress edit). Compared against
 * the last applied signature; a one-shot "applied already" latch would instead
 * pin the form to the first, possibly stale, cached fetch.
 */
export function syncKeysSignature(syncKeys: TemplateSyncKeys | undefined): string {
  const { syncModelsDev, syncOpenrouter, syncArenaVendor } = syncKeyFields(syncKeys);
  return JSON.stringify([syncModelsDev, syncOpenrouter, syncArenaVendor]);
}

export const NAME_REQUIRED_MESSAGE = "A name is required.";
export const BASE_URL_REQUIRED_MESSAGE = "A base URL is required.";

/**
 * WHY Save can't fire, or null when nothing is blocking — the same checks (in the same
 * order) `ProviderTemplateDialog`'s `handleSubmit` throws on, so the dialog can both
 * disable Save BEFORE a doomed click AND say what it is waiting on. A reason rather than
 * a boolean because disabling the button is precisely what makes those throws
 * unreachable; the dialog's submit path throws these very strings.
 */
export function templateFormBlockedReason(form: TemplateFormState): string | null {
  if (form.name.trim() === "") return NAME_REQUIRED_MESSAGE;
  if (form.baseUrl.trim() === "") return BASE_URL_REQUIRED_MESSAGE;
  return validateConnectionSpecDraft(form.spec);
}

export function stateFromTemplate(
  template: ProviderTemplate | null,
  syncKeys: TemplateSyncKeys | undefined,
): TemplateFormState {
  return {
    providerKind: template?.providerKind ?? "openai",
    name: template?.name ?? "",
    baseUrl: template?.baseUrl ?? "",
    documentationUrl: template?.documentationUrl ?? "",
    statusUrl: template?.statusUrl ?? "",
    // Curated rows only — synced rows are catalog-managed and rendered read-only
    // in the dialog. A PUT with `models` syncs the curated set only (Task 4
    // semantics), so seeding the editor from synced names would fight the sync.
    models: (template?.models ?? [])
      .filter((m) => m.source !== "synced")
      .map((m) => m.name),
    modalities: canonicalModalities(template?.modalities ?? []),
    availableViaNote: template?.availableVia?.note ?? "",
    availableViaTemplates: (template?.availableVia?.templates ?? []).join(", "),
    ...syncKeyFields(syncKeys),
    spec: draftFromConnectionSpec(template?.connectionSpec ?? null),
  };
}

export interface BuildTemplateBodyOptions {
  /** True when editing an existing template (vs. create). */
  editing: boolean;
  /**
   * True once the operator sync-key mapping has loaded (edit mode only). Drives
   * the one subtle rule below — see the note on `syncKeys`.
   */
  syncKeysLoaded: boolean;
}

/**
 * Assemble the POST/PUT body from form state (all values normalized/trimmed
 * here). The load-bearing rule: `syncKeys` is OMITTED entirely in EDIT mode
 * until the stored mapping has loaded. Under the PUT convention absent = leave
 * untouched, whereas an explicit `null` = CLEAR — so submitting a name-only edit
 * before the sync-keys fetch settles (or after it errors) must not send `null`
 * and silently wipe the template's stored mapping. On create there is nothing
 * stored to clobber, so it is always present.
 *
 * "Omit" is expressed as `undefined`, which `JSON.stringify` drops — so the key
 * never reaches the wire (absent = untouched), while `null` is a real cleared
 * value the operator gets only once the mapping has loaded.
 */
export function buildTemplateBody(
  form: TemplateFormState,
  { editing, syncKeysLoaded }: BuildTemplateBodyOptions,
) {
  const syncModelsDev = form.syncModelsDev.trim();
  const syncOpenrouter = form.syncOpenrouter.trim();
  const syncArenaVendor = form.syncArenaVendor.trim();
  const syncKeys: TemplateSyncKeys =
    syncModelsDev || syncOpenrouter || syncArenaVendor
      ? {
          ...(syncModelsDev ? { modelsDev: syncModelsDev } : {}),
          ...(syncOpenrouter ? { openrouter: syncOpenrouter } : {}),
          ...(syncArenaVendor ? { arenaVendor: syncArenaVendor } : {}),
        }
      : null;
  const includeSyncKeys = !editing || syncKeysLoaded;

  return {
    providerKind: form.providerKind,
    name: form.name.trim(),
    baseUrl: form.baseUrl.trim(),
    documentationUrl: form.documentationUrl.trim() || null,
    statusUrl: form.statusUrl.trim() || null,
    connectionSpec: connectionSpecFromDraft(form.spec),
    models: form.models.map((m) => m.trim()).filter(Boolean),
    modalities: form.modalities.length ? form.modalities : null,
    availableVia: form.availableViaNote.trim()
      ? {
          note: form.availableViaNote.trim(),
          templates: form.availableViaTemplates
            .split(",")
            .map((s) => s.trim())
            .filter(Boolean),
        }
      : null,
    syncKeys: includeSyncKeys ? syncKeys : undefined,
  };
}
