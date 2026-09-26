"use client";

import { useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@agenticdevelopertoolkit/ui/components/dialog";
import { DialogActions } from "@agenticdevelopertoolkit/ui/components/dialog-actions";
import { UnsavedChangesAlert } from "@agenticdevelopertoolkit/ui/components/unsaved-changes-alert";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { Textarea } from "@agenticdevelopertoolkit/ui/components/textarea";
import { Checkbox } from "@agenticdevelopertoolkit/ui/components/checkbox";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { Field } from "@agenticdevelopertoolkit/ui/blocks/field";
import { FieldGroup } from "@agenticdevelopertoolkit/ui/blocks/field-group";
import { useAction } from "@agenticdevelopertoolkit/ui/hooks/useAction";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import {
  useCreateProviderTemplate,
  useUpdateProviderTemplate,
  useTemplateSyncKeys,
  type ProviderTemplate,
} from "../api/llm-providers";
import { formatRelativeTime } from "./sync-format";
import { ConnectionSpecFields } from "./ConnectionSpecFields";
import { ModelsEditor } from "./ModelsEditor";
import {
  MODALITIES,
  applySyncKeys,
  buildTemplateBody,
  templateFormBlockedReason,
  stateFromTemplate,
  syncKeysSignature,
  toggleModality,
  type SyncKeyField,
  type TemplateFormState,
} from "./template-form";

type ProviderKind = ProviderTemplate["providerKind"];
const PROVIDER_KINDS: ProviderKind[] = ["openai", "anthropic", "gemini", "external"];

/** The catalog-sync mapping inputs — one row each, identical but for their copy. */
const SYNC_KEY_FIELDS: Array<{
  field: SyncKeyField;
  label: string;
  hint: string;
  placeholder: string;
}> = [
  {
    field: "syncModelsDev",
    label: "models.dev id",
    hint: "Provider id in the models.dev catalog.",
    placeholder: "openai",
  },
  {
    field: "syncOpenrouter",
    label: "OpenRouter prefix",
    hint: "Model-id prefix on OpenRouter, e.g. openai.",
    placeholder: "openai",
  },
  {
    field: "syncArenaVendor",
    label: "Arena vendor",
    hint: "Vendor name in the model-arena leaderboard.",
    placeholder: "OpenAI",
  },
];

/**
 * Create/edit form for one provider template. Always renders the FULL current
 * state of the nested `models` list and `connectionSpec` sub-fields (rather
 * than tracking per-field dirtiness on them), because the PUT contract wants
 * the full desired set for `models` and an explicit replace/`null`/omit for
 * `connectionSpec` — see `connection-spec-draft.ts`.
 */
export function ProviderTemplateDialog({
  open,
  template,
  onClose,
  onDirtyChange,
}: {
  open: boolean;
  /** The template being edited, or null in create mode. */
  template: ProviderTemplate | null;
  onClose: () => void;
  /** Reports whether the form holds unsaved input, so the page's guard covers it. */
  onDirtyChange: (dirty: boolean) => void;
}) {
  const createTemplate = useCreateProviderTemplate();
  const updateTemplate = useUpdateProviderTemplate();
  const save = useAction();
  const editingMode = template !== null;

  // The operator-only sync keys aren't on the public template DTO, so they load
  // separately (edit mode only). Folding them into `initial` keeps the form from
  // reading dirty the moment they arrive.
  const syncKeysQuery = useTemplateSyncKeys(template?.id ?? null);
  const loadedSyncKeys = syncKeysQuery.data?.syncKeys;

  const initial = useMemo(
    () => stateFromTemplate(template, loadedSyncKeys ?? undefined),
    [template, loadedSyncKeys],
  );
  const [form, setForm] = useState<TemplateFormState>(initial);
  const formRef = useRef<HTMLFormElement>(null);

  function patch(p: Partial<TemplateFormState>) {
    setForm((f) => ({ ...f, ...p }));
  }

  // Named separately because a computed key (`patch({ [field]: v })`) widens to an
  // index signature and stops being type-checked; the explicit params keep it honest.
  function patchSyncKey(field: SyncKeyField, value: string) {
    setForm((f) => ({ ...f, [field]: value }));
  }

  // Push a loaded mapping into the live form whenever a fetch brings a DIFFERENT
  // one than was last applied — not merely the first time. Reopening the dialog
  // inside the app's 30s staleTime serves the cached mapping first and the
  // refetched one a moment later (the update mutation invalidates this query), so
  // a one-shot latch would pin the form to pre-save values and silently re-save
  // them. Skipping an UNCHANGED mapping keeps a background refetch from clobbering
  // an in-progress edit. `initial` tracks the same data, so this leaves the form
  // clean; the field mapping itself lives once in `applySyncKeys`.
  const appliedSyncKeys = useRef<string | null>(null);
  useEffect(() => {
    if (!syncKeysQuery.isSuccess) return;
    const sk = syncKeysQuery.data.syncKeys ?? undefined;
    const signature = syncKeysSignature(sk);
    if (appliedSyncKeys.current === signature) return;
    appliedSyncKeys.current = signature;
    setForm((f) => applySyncKeys(f, sk));
  }, [syncKeysQuery.isSuccess, syncKeysQuery.data]);

  // Synced model rows are catalog-managed: shown read-only, never in the editor.
  const syncedModels = useMemo(
    () => (template?.models ?? []).filter((m) => m.source === "synced"),
    [template],
  );

  // In edit mode the sync keys aren't editable until their stored value has
  // loaded — while loading, and permanently on a fetch error. Submission omits
  // them in that state (buildTemplateBody), so keep the inputs read-only too.
  const syncKeysLocked = editingMode && !syncKeysQuery.isSuccess;

  const dirty = useMemo(
    () => JSON.stringify(form) !== JSON.stringify(initial),
    [form, initial],
  );
  useEffect(() => onDirtyChange(open && dirty), [open, dirty, onDirtyChange]);
  // Why Save can't fire (null = nothing blocking). Save's own gate is `dirty && no reason`;
  // `save.busy` is applied at each button rather than folded in here.
  const blockedReason = useMemo(() => templateFormBlockedReason(form), [form]);
  const canSave = dirty && blockedReason === null;

  const [confirmingClose, setConfirmingClose] = useState(false);

  // Escape, the backdrop, the × and Cancel all land here. A dirty draft asks first;
  // the post-save path calls onClose() directly and is deliberately not gated.
  function close() {
    if (save.busy) return;
    if (dirty) {
      setConfirmingClose(true);
      return;
    }
    onClose();
  }

  function handleSubmit(e: FormEvent) {
    e.preventDefault();
    void save.run(async () => {
      // One authority for "why this can't be saved", shared with the button gate and the
      // sentence rendered next to it — so the disabled Save and a forced submit can't
      // disagree about the rule or its wording.
      const blocked = templateFormBlockedReason(form);
      if (blocked) throw new Error(blocked);

      // Edit mode omits `syncKeys` until the stored mapping has loaded, so a
      // name-only edit (or one saved after the fetch errored) can't send `null`
      // and clear the mapping — see buildTemplateBody.
      const body = buildTemplateBody(form, {
        editing: editingMode,
        syncKeysLoaded: syncKeysQuery.isSuccess,
      });

      if (template) {
        await updateTemplate.mutateAsync({ id: template.id, ...body });
      } else {
        await createTemplate.mutateAsync(body);
      }
      onClose();
    });
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !next && close()}>
      <DialogContent className="max-w-2xl max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{editingMode ? "Edit provider template" : "New provider template"}</DialogTitle>
          <DialogDescription>
            {editingMode
              ? "Update the connection details, models, or auth spec used to connect this provider."
              : "Define a provider a persona can connect to — kind, base URL, models, and how the connect UI authenticates."}
          </DialogDescription>
        </DialogHeader>
        <form ref={formRef} onSubmit={handleSubmit} className="flex flex-col gap-4">
          <div className="flex flex-col gap-3 sm:flex-row">
            <Field label="Provider kind" className="sm:w-48">
              <Select
                aria-label="Provider kind"
                value={form.providerKind}
                onChange={(e) => patch({ providerKind: e.target.value as ProviderKind })}
              >
                {PROVIDER_KINDS.map((kind) => (
                  <option key={kind} value={kind}>
                    {kind}
                  </option>
                ))}
              </Select>
            </Field>
            <Field label="Name" className="flex-1">
              <Input
                value={form.name}
                onChange={(e) => patch({ name: e.target.value })}
                placeholder="e.g. OpenAI"
              />
            </Field>
          </div>

          <Field
            label="Base URL"
            hint="May contain {placeholders} (e.g. https://{region}.example.com) — declare them as URL variables below."
          >
            <Input
              value={form.baseUrl}
              onChange={(e) => patch({ baseUrl: e.target.value })}
              placeholder="https://api.openai.com/v1"
              className="font-mono"
            />
          </Field>

          <div className="flex flex-col gap-3 sm:flex-row">
            <Field label="Documentation URL" className="flex-1">
              <Input
                value={form.documentationUrl}
                onChange={(e) => patch({ documentationUrl: e.target.value })}
                placeholder="https://platform.openai.com/docs (optional)"
              />
            </Field>
            <Field label="Status URL" className="flex-1">
              <Input
                value={form.statusUrl}
                onChange={(e) => patch({ statusUrl: e.target.value })}
                placeholder="https://status.openai.com (optional)"
              />
            </Field>
          </div>

          <FieldGroup title="Modalities">
            <div className="flex flex-wrap gap-4">
              {MODALITIES.map((m) => (
                <Label key={m} className="font-normal capitalize">
                  <Checkbox
                    checked={form.modalities.includes(m)}
                    // Order-stable: unchecking then re-checking must yield the SAME
                    // array, or the dialog reports unsaved changes for a no-op.
                    onCheckedChange={(v) =>
                      patch({ modalities: toggleModality(form.modalities, m, v === true) })
                    }
                    disabled={save.busy}
                  />
                  {m}
                </Label>
              ))}
            </div>
            <p className="text-xs text-apt-text-dim">
              Output types this provider serves. Defaults to chat when none are checked.
            </p>
          </FieldGroup>

          <ModelsEditor
            models={form.models}
            onChange={(models) => patch({ models })}
            disabled={save.busy}
          />

          {syncedModels.length > 0 && (
            <div className="space-y-1 text-xs text-apt-text-muted">
              <div>Synced models (managed by catalog sync — edit curated rows only):</div>
              {syncedModels.map((m) => (
                <div key={m.id} className="flex items-center gap-2">
                  <span className="rounded bg-apt-surface-2 px-1 font-mono">synced</span>
                  <span className="font-mono text-apt-text">{m.name}</span>
                  {/* last_synced_at is naive-UTC PG text — formatRelativeTime normalizes
                      the zone before formatting (see sync-format.ts), so the label is
                      correct for a non-UTC operator, not skewed by their offset. */}
                  {m.lastSyncedAt && <span>· {formatRelativeTime(m.lastSyncedAt)}</span>}
                </div>
              ))}
            </div>
          )}

          <FieldGroup title="Informational availability">
            <Field
              label="Note"
              hint="Set this to mark the provider informational — no first-party API; personas connect via the named templates instead."
            >
              <Textarea
                value={form.availableViaNote}
                onChange={(e) => patch({ availableViaNote: e.target.value })}
                placeholder="e.g. Available through OpenRouter or a Vertex gateway."
                disabled={save.busy}
              />
            </Field>
            <Field label="Templates" hint="comma-separated template names">
              <Input
                value={form.availableViaTemplates}
                onChange={(e) => patch({ availableViaTemplates: e.target.value })}
                placeholder="OpenRouter, Vertex AI"
                disabled={save.busy}
              />
            </Field>
          </FieldGroup>

          <FieldGroup title="Catalog sync keys">
            {editingMode && syncKeysQuery.isError && (
              <ErrorText error="Couldn’t load the stored sync mapping — it can’t be edited this session, and saving will leave it unchanged." />
            )}
            {SYNC_KEY_FIELDS.map(({ field, label, hint, placeholder }) => (
              <Field key={field} label={label} hint={hint}>
                <Input
                  value={form[field]}
                  onChange={(e) => patchSyncKey(field, e.target.value)}
                  placeholder={placeholder}
                  className="font-mono"
                  disabled={save.busy || syncKeysLocked}
                />
              </Field>
            ))}
          </FieldGroup>

          <ConnectionSpecFields
            draft={form.spec}
            onChange={(p) => patch({ spec: { ...form.spec, ...p } })}
            disabled={save.busy}
          />

          {save.error ? (
            <ErrorText error={save.error} />
          ) : (
            // Why Save is grey. Gated on `dirty` so an untouched form doesn't open by scolding
            // the user about input they haven't given yet; "nothing to save" is
            // self-explanatory, "a base URL is required" is not.
            blockedReason &&
            dirty && (
              <p className="text-sm text-apt-text-muted" role="status">
                {blockedReason}
              </p>
            )
          )}
          {/* A submit button is what lets Enter submit the form; hidden because the visible
              confirm lives in DialogActions and calls form.requestSubmit(). It must carry the
              same disabled state as the visible confirm — being the form's implicit default
              button, Enter in any text field submits THIS button regardless of `hidden`/
              `display:none`; only `disabled` stops it. That includes `save.busy`:
              DialogActions drops the visible confirm while saving, leaving THIS the only
              reachable submit path, so without the busy term Enter mid-save fires a second
              write. */}
          <button
            type="submit"
            className="hidden"
            aria-hidden
            tabIndex={-1}
            disabled={!canSave || save.busy}
          />
        </form>
        <DialogActions
          cancelLabel="Cancel"
          onCancel={close}
          confirmLabel="Save"
          onConfirm={() => formRef.current?.requestSubmit()}
          busy={save.busy}
          confirmDisabled={!canSave}
          focusOnMount={false}
        />
        <UnsavedChangesAlert
          open={confirmingClose}
          onDiscard={() => {
            setConfirmingClose(false);
            onClose();
          }}
          onStay={() => setConfirmingClose(false)}
        />
      </DialogContent>
    </Dialog>
  );
}
