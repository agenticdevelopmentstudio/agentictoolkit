"use client";

import { useCallback, useState } from "react";
import { Boxes } from "lucide-react";
import { reportUnexpectedAuthError } from "@agentic-toolkit/auth";
import { useDirtyDraft } from "@agenticdevelopertoolkit/ui/hooks/useDirtyDraft";
import { useDualModeSelection } from "@agenticdevelopertoolkit/ui/hooks/useDualModeSelection";
import {
  HierarchicalDetailView,
  type TopicDetailItem,
  type TopicLevel,
  FieldGroup,
  Field,
  ButtonBar,
  SectionHeader,
} from "@agenticdevelopertoolkit/ui/blocks";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import {
  StackLevels,
  ToolbarPortal,
  useRailExitGuard,
  useRailHost,
  useRecordAffordance,
  CreateResourceDialog,
} from "@agentic-toolkit/resource";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { useResourceList } from "@agentic-toolkit/data";
import { fmtDate } from "./format";
import { useUserServices } from "./useUserServices";
import {
  api,
  type UserService,
  type ModelInfo,
  type Template,
  type PatchServiceBody,
  type ConnectionSpec,
  type ConnectionSpecUrlVar,
  type ConnectionSpecHeaderVar,
} from "@agentic-toolkit/data/personas";

// ─── helpers ──────────────────────────────────────────────────────────────────

/** The stand-in while the template catalog is outstanding. Module scope so it keeps one identity. */
const EMPTY_TEMPLATES: Template[] = [];

/* The read below is a MODULE-SCOPE function, which is what `useResourceList` requires of a
 * fetcher: a new identity means "the scope changed, read again", so an inline closure would read on
 * every render. It is caller-scoped — it closes over nothing — so one cache entry serves every
 * mount. The services list itself is read through the shared {@link useUserServices}, which is the
 * one cache both this pane and the persona editor's service picker share. */

/** The service templates. A failure is REPORTED and then answered with an empty catalog: the
 *  picker is an accelerator, and losing it must not stop anyone typing a service in by hand. */
function loadServiceTemplates(): Promise<Template[]> {
  return api.templates().catch((err) => {
    reportUnexpectedAuthError(err, { feature: "services", step: "templates" });
    return EMPTY_TEMPLATES;
  });
}

/** Replace `{name}` tokens in a base-URL pattern with the user's url-var values.
 *  Unfilled vars stay as `{name}` so the resolved URL visibly prompts for them. */
function substituteUrlVars(pattern: string, values: Record<string, string>): string {
  return pattern.replace(/\{(\w+)\}/g, (m, name: string) => {
    const v = values[name];
    return v && v.trim() !== "" ? v.trim() : m;
  });
}

/** A one-line hint about how a template authenticates, shown in the connect form
 *  (only for the non-obvious, non-bearer cases). */
function authHintFor(spec: Template["connectionSpec"]): string | undefined {
  const auth = spec?.auth;
  if (!auth || auth.type === "bearer") return undefined;
  if (auth.type === "header") return `Authenticates via the \`${auth.header}\` header.`;
  if (auth.type === "sigv4") return "Uses AWS SigV4 signing — not yet supported by this client.";
  if (auth.type === "oauth2") return "Uses OAuth — not yet supported by this client.";
  return undefined;
}

function fmtNum(n: number | undefined): string {
  if (n === undefined || n === null) return "—";
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(0)}K`;
  return String(n);
}

/** A template's list/card label, suffixed with its non-chat modalities (e.g.
 *  `Fal (image)`, `ElevenLabs (audio)`). Chat — the default when `modalities` is
 *  null/omitted — carries no suffix, so plain LLM providers read unchanged. */
function templateLabel(t: Template): string {
  const media = (t.modalities ?? []).filter((m) => m !== "chat");
  return media.length > 0 ? `${t.name} (${media.join("/")})` : t.name;
}

// ─── ModelsTable ──────────────────────────────────────────────────────────────

function CapChip({ label }: { label: string }) {
  return (
    <span className="rounded bg-apt-surface-2 px-1 py-0.5 font-mono text-[0.6rem] text-apt-text-muted">
      {label}
    </span>
  );
}

function ModelsTable({ models }: { models: ModelInfo[] }) {
  if (models.length === 0) {
    return (
      <p className="text-sm text-apt-text-muted">No models yet — Connect or Refresh.</p>
    );
  }
  return (
    <div className="overflow-hidden rounded-lg border border-apt-border">
      <table className="w-full border-collapse text-sm">
        <thead>
          <tr className="border-b border-apt-border bg-apt-surface-2/40 text-left font-mono text-[0.7rem] uppercase tracking-wider text-apt-text-muted">
            <th className="px-3 py-2 font-medium">Model</th>
            <th className="px-3 py-2 font-medium">Family</th>
            <th className="px-3 py-2 font-medium">Context</th>
            <th className="px-3 py-2 font-medium">Max out</th>
            <th className="px-3 py-2 font-medium">$/1M in</th>
            <th className="px-3 py-2 font-medium">$/1M out</th>
            <th className="px-3 py-2 font-medium">Caps</th>
          </tr>
        </thead>
        <tbody>
          {models.map((m, i) => (
            <tr key={m.id} className={i > 0 ? "border-t border-apt-border" : ""}>
              <td className="px-3 py-2 text-apt-text">{m.displayName ?? m.id}</td>
              <td className="px-3 py-2 font-mono text-xs text-apt-text-muted">{m.family ?? "—"}</td>
              <td className="px-3 py-2 font-mono text-xs text-apt-text-muted">
                {fmtNum(m.contextWindow)}
              </td>
              <td className="px-3 py-2 font-mono text-xs text-apt-text-muted">
                {fmtNum(m.maxOutputTokens)}
              </td>
              <td className="px-3 py-2 font-mono text-xs text-apt-text-muted">
                {m.inputUsdPerMTokens !== undefined ? `$${m.inputUsdPerMTokens.toFixed(2)}` : "—"}
              </td>
              <td className="px-3 py-2 font-mono text-xs text-apt-text-muted">
                {m.outputUsdPerMTokens !== undefined ? `$${m.outputUsdPerMTokens.toFixed(2)}` : "—"}
              </td>
              <td className="px-3 py-2">
                <div className="flex flex-wrap gap-1">
                  {m.supportsTools && <CapChip label="tools" />}
                  {m.supportsVision && <CapChip label="vision" />}
                  {m.supportsThinking && <CapChip label="thinking" />}
                  {!m.supportsTools && !m.supportsVision && !m.supportsThinking && (
                    <span className="font-mono text-xs text-apt-text-dim">—</span>
                  )}
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// ─── ServiceEditor ────────────────────────────────────────────────────────────

type ServiceDraft = {
  templateId: string | undefined;
  name: string;
  providerKind: string;
  baseUrl: string;
  apiKeyInput: string;
  /** When the chosen template parameterizes its URL, the pattern (with
   *  `{placeholders}`) plus the vars to prompt for and the user's values; baseUrl
   *  is kept in sync as the resolved URL. Absent for plain templates. */
  baseUrlPattern?: string;
  urlVars?: ConnectionSpecUrlVar[];
  urlVarValues: Record<string, string>;
  /** When the chosen template parameterizes headers (Portkey's provider header, a
   *  gateway virtual key), the headers to prompt for and the user's values — folded
   *  into the connection's extraHeaders on submit. Absent for plain templates. */
  headerVars?: ConnectionSpecHeaderVar[];
  headerVarValues: Record<string, string>;
  /** The chosen template's full spec, carried so submit can send it verbatim (an
   *  explicit spec REPLACES the template's copy server-side, so auth/urlVars must
   *  ride along) with the collected header values merged in. Absent for custom. */
  templateSpec?: ConnectionSpec | null;
  /** One-line hint about non-bearer auth, shown under the fields. */
  authHint?: string;
};

const BLANK_DRAFT: ServiceDraft = {
  templateId: undefined,
  name: "",
  providerKind: "",
  baseUrl: "",
  apiKeyInput: "",
  urlVarValues: {},
  headerVarValues: {},
};

/** Fields to reset when a template is de-selected (back to a custom connection). */
const CLEAR_TEMPLATE: Partial<ServiceDraft> = {
  templateId: undefined,
  baseUrlPattern: undefined,
  urlVars: undefined,
  urlVarValues: {},
  headerVars: undefined,
  headerVarValues: {},
  templateSpec: undefined,
  authHint: undefined,
};

/**
 * `ServiceDraft.urlVarValues`/`headerVarValues` are `Record<string,string>` — object-valued
 * fields `useDirtyDraft`'s `sameValue` compares by `Object.is`, same hazard as `WorkItemEditor`'s
 * assignee field. It's silently safe here ONLY because edit mode never re-enables url-var/header
 * prompting: this function always seeds `urlVars`/`headerVars` as `undefined`, so the branches in
 * `ServiceFields` that render those fields (and would call `onChange` with a FRESH
 * `{...draft.urlVarValues, [name]: value}` object every keystroke — never `===` the baseline's)
 * never render in edit mode. If someone re-enables url-var/header prompting on edit (recovering
 * `urlVars`/`headerVars`/`templateSpec` from the service's stored template), Save will read as
 * permanently dirty the instant the first such field renders and is touched — encode those two
 * Records as primitives (e.g. a sorted `k=v&k=v` string) the same way `WorkItemEditor` encodes its
 * object-valued assignee field, rather than storing the Record itself in the draft.
 */
function fromService(s: UserService): ServiceDraft {
  return {
    templateId: s.templateId ?? undefined,
    name: s.name,
    providerKind: s.providerKind,
    baseUrl: s.baseUrl,
    apiKeyInput: "",
    // Edit mode works on the already-resolved base URL (url vars can't be
    // recovered from a concrete URL), so no url-var prompting here. Header vars are
    // likewise not re-prompted on edit — the stored extraHeaders already carry them.
    urlVarValues: {},
    headerVarValues: {},
  };
}

const PROVIDER_LABELS: Record<string, string> = {
  openai: "OpenAI",
  anthropic: "Anthropic",
  gemini: "Google Gemini",
};

/**
 * The service's editable fields (name, provider, base URL, API key) — one shared FieldGroup used by
 * BOTH the "New service" create modal and the edit editor, so the field set lives in one place
 * (DRY). The provider is fixed after creation, so the edit editor passes `providerDisabled`; the
 * API-key hint/placeholder differ between create and edit (an existing key is masked, not shown).
 */
function ServiceFields({
  draft,
  onChange,
  providerDisabled,
  apiKeyHint,
  apiKeyPlaceholder,
  autoFocusName,
}: {
  draft: ServiceDraft;
  onChange: (next: ServiceDraft) => void;
  /** Provider can't change after creation, so the edit form disables it. */
  providerDisabled?: boolean;
  apiKeyHint?: string;
  apiKeyPlaceholder?: string;
  /** Focus the Name field on mount (the create modal opens straight into it). */
  autoFocusName?: boolean;
}) {
  return (
    <FieldGroup title="Service">
      <Field label="Name">
        <Input
          /* eslint-disable-next-line jsx-a11y/no-autofocus -- focus the first field when the modal opens */
          autoFocus={autoFocusName}
          value={draft.name}
          onChange={(e) => onChange({ ...draft, name: e.target.value })}
          placeholder="My OpenAI service"
        />
      </Field>
      <Field label="Provider" hint={providerDisabled ? "Cannot change after creation." : undefined}>
        <Select
          value={draft.providerKind}
          onChange={(e) => onChange({ ...draft, providerKind: e.target.value })}
          disabled={providerDisabled}
        >
          <option value="">Select a provider</option>
          {Object.entries(PROVIDER_LABELS).map(([val, label]) => (
            <option key={val} value={val}>
              {label}
            </option>
          ))}
        </Select>
      </Field>
      {draft.urlVars && draft.urlVars.length > 0 ? (
        <>
          {draft.urlVars.map((v) => (
            <Field
              key={v.name}
              label={v.label ?? v.name}
              hint={v.example ? `e.g. ${v.example}` : undefined}
            >
              <Input
                value={draft.urlVarValues[v.name] ?? ""}
                onChange={(e) => {
                  const urlVarValues = { ...draft.urlVarValues, [v.name]: e.target.value };
                  onChange({
                    ...draft,
                    urlVarValues,
                    baseUrl: substituteUrlVars(
                      draft.baseUrlPattern ?? draft.baseUrl,
                      urlVarValues,
                    ),
                  });
                }}
                placeholder={v.example}
              />
            </Field>
          ))}
          <Field label="Base URL" hint="Filled in from the values above.">
            <Input value={draft.baseUrl} readOnly />
          </Field>
        </>
      ) : (
        <Field label="Base URL">
          <Input
            value={draft.baseUrl}
            onChange={(e) => onChange({ ...draft, baseUrl: e.target.value })}
            placeholder="https://api.openai.com/v1"
          />
        </Field>
      )}
      {draft.headerVars?.map((v) => (
        <Field
          key={v.header}
          label={v.label ?? v.header}
          hint={v.example ? `e.g. ${v.example}` : undefined}
        >
          <Input
            type={v.secret ? "password" : "text"}
            value={draft.headerVarValues[v.header] ?? ""}
            onChange={(e) =>
              onChange({
                ...draft,
                headerVarValues: { ...draft.headerVarValues, [v.header]: e.target.value },
              })
            }
            placeholder={v.example}
          />
        </Field>
      ))}
      {draft.authHint && <p className="text-xs text-apt-text-muted">{draft.authHint}</p>}
      <Field label="API key" hint={apiKeyHint}>
        <Input
          type="password"
          value={draft.apiKeyInput}
          onChange={(e) => onChange({ ...draft, apiKeyInput: e.target.value })}
          placeholder={apiKeyPlaceholder ?? "sk-…"}
        />
      </Field>
    </FieldGroup>
  );
}

/** Build the per-connection spec to POST when a template parameterizes headers.
 *  Returns undefined for a plain template (submit sends no spec → the backend copies
 *  the template's). When header vars ARE present, an explicit spec REPLACES the
 *  template's copy server-side, so the template's whole spec is sent verbatim (auth,
 *  urlVars, defaultQuery) with the collected header values folded into extraHeaders.
 *  extraHeaders is built fresh from the entered values — a template's own static
 *  extraHeaders would arrive redacted, so it is not forwarded (no template today
 *  carries both). */
function connectionSpecForCreate(d: ServiceDraft): ConnectionSpec | undefined {
  if (!d.headerVars || d.headerVars.length === 0) return undefined;
  const extraHeaders: Record<string, string> = {};
  for (const v of d.headerVars) {
    const value = (d.headerVarValues[v.header] ?? "").trim();
    if (value) extraHeaders[v.header] = value;
  }
  return { ...(d.templateSpec ?? { specVersion: 1 }), specVersion: 1, extraHeaders };
}

/** The three required-field rules shared by the create modal and the edit pane, as a REASON rather
 *  than a boolean: the edit pane's Save is disabled while any of them fails, so without a message
 *  the user gets a grey button and no way to learn which field is holding it down. The create
 *  modal's own validator below starts from the same three so the two can never disagree about
 *  what "required" means or how it is worded. */
function requiredFieldsBlock(d: ServiceDraft): string | null {
  if (d.name.trim() === "") return "A name is required.";
  if (d.providerKind === "") return "Select a provider.";
  if (d.baseUrl.trim() === "") return "A base URL is required.";
  return null;
}

/** Returns an error message, or null when the create draft is valid. */
function validateServiceDraft(d: ServiceDraft): string | null {
  const required = requiredFieldsBlock(d);
  if (required) return required;
  if (/\{\w+\}/.test(d.baseUrl)) return "Fill in all the URL fields.";
  if (d.headerVars?.some((v) => (d.headerVarValues[v.header] ?? "").trim() === ""))
    return "Fill in all the header fields.";
  return null;
}

/** The "New service" modal's form: an optional template picker (which prefills the fields) above the
 *  shared {@link ServiceFields}. A component (not inline JSX) so its template-catalog fetch hook is
 *  stable across the dialog's renders. */
function NewServiceForm({
  draft,
  onChange,
  error,
}: {
  draft: ServiceDraft;
  onChange: (next: ServiceDraft) => void;
  error: string | null;
}) {
  // Read once per browser tab and served from cache after that: this catalog is the same for every
  // caller and changes about as often as the product ships, so reopening the dialog shows its
  // picker already populated instead of re-reading it every time.
  const { items } = useResourceList<Template>("persona-service-templates", loadServiceTemplates);
  const templates = items ?? EMPTY_TEMPLATES;

  // Apply a template: prefill name, providerKind, baseUrl — and, when the
  // template parameterizes its URL, the url-var prompts + auth hint.
  function applyTemplate(templateId: string) {
    const tpl = templates.find((t) => t.id === templateId);
    if (!tpl) {
      onChange({ ...draft, ...CLEAR_TEMPLATE });
      return;
    }
    const urlVars = tpl.connectionSpec?.urlVars ?? [];
    const hasVars = urlVars.length > 0;
    const headerVars = tpl.connectionSpec?.headerVars ?? [];
    const hasHeaderVars = headerVars.length > 0;
    onChange({
      ...draft,
      templateId,
      name: tpl.name,
      providerKind: tpl.providerKind,
      baseUrl: tpl.baseUrl,
      baseUrlPattern: hasVars ? tpl.baseUrl : undefined,
      urlVars: hasVars ? urlVars : undefined,
      urlVarValues: {},
      headerVars: hasHeaderVars ? headerVars : undefined,
      headerVarValues: {},
      templateSpec: tpl.connectionSpec,
      authHint: authHintFor(tpl.connectionSpec),
    });
  }

  // Split the catalog: `connectable` templates have a first-party API and go in the
  // picker (their label suffixed with any non-chat modalities); `informational` ones
  // (availableVia set) have no API of their own, so they can't be connected — they
  // render as read-only cards below that point at their gateway templates instead.
  const connectable = templates.filter((t) => !t.availableVia);
  const informational = templates.filter((t) => t.availableVia);

  return (
    <div className="flex flex-col gap-4">
      {templates.length > 0 && (
        <FieldGroup title="Start from a template">
          <Field label="Template">
            <Select
              value={draft.templateId ?? ""}
              onChange={(e) => {
                if (e.target.value) applyTemplate(e.target.value);
                else onChange({ ...draft, ...CLEAR_TEMPLATE });
              }}
            >
              <option value="">Custom (no template)</option>
              {connectable.map((t) => (
                <option key={t.id} value={t.id}>
                  {templateLabel(t)}
                </option>
              ))}
            </Select>
          </Field>
          {informational.length > 0 && (
            <div className="mt-3 flex flex-col gap-2">
              <div className="font-mono text-[0.65rem] uppercase tracking-wider text-apt-text-muted">
                No first-party API
              </div>
              {informational.map((t) => (
                <div key={t.id} className="rounded-lg border border-apt-border p-3 text-sm">
                  <div className="font-medium text-apt-text">{templateLabel(t)}</div>
                  <p className="mt-1 text-apt-text-muted">{t.availableVia?.note}</p>
                  {(t.availableVia?.templates ?? []).length > 0 && (
                    <div className="mt-2 flex flex-wrap gap-2">
                      {t.availableVia?.templates.map((name) => {
                        // Resolve the named gateway within `connectable` only — a
                        // "Use" button must apply a template that actually has a
                        // first-party API. A name that resolves to another
                        // informational row (or nothing) renders no button.
                        const target = connectable.find((x) => x.name === name);
                        return target ? (
                          <Button
                            key={name}
                            size="sm"
                            variant="outline"
                            onClick={() => applyTemplate(target.id)}
                          >
                            Use {name}
                          </Button>
                        ) : null;
                      })}
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </FieldGroup>
      )}
      <ServiceFields draft={draft} onChange={onChange} autoFocusName />
      {error && <ErrorText error={error} />}
    </div>
  );
}

/**
 * The service editor — the shared {@link ServiceFields} plus a Connection + Models section and a
 * ButtonBar, for EDITING an existing service. Creating is a modal now (see the CreateResourceDialog
 * in ServicesSection), so this always has a real service. The caller owns the list; this pane owns
 * the draft, validation, save, delete, connect, and refresh.
 */
function ServiceEditor({
  service,
  onSaved,
  onDeleted,
  onCancel,
}: {
  /** The service to edit (never null — create is a modal). */
  service: UserService;
  onSaved: (saved: UserService) => void;
  onDeleted: () => void;
  onCancel: () => void;
}) {
  const renderRecordAffordance = useRecordAffordance();

  // Derive the initial draft from the service prop; keyed remount per id in the
  // parent gives each service a fresh editor, so seeding state here is safe.
  const { draft, patch, dirty, commit } = useDirtyDraft<ServiceDraft>(() => fromService(service));
  // That same `dirty` gates Save (`canSave` below) — and until now gated NOTHING else, so every
  // exit that does not go through Save discarded the draft in silence: a rail row switch, the
  // breadcrumb up, an in-app link, a reload. Publishing it into the host's guard registry is what
  // the sibling PersonaEditor does with its own dirt (via useExitGuardChannel), and it costs one
  // line because `useDirtyDraft` already diffs against the baseline `commit()` re-seeds on save.
  // Null while clean: registration is gated on dirt, never on "an editor is mounted", or browsing
  // services would prompt on the way out of every one of them.
  useRailExitGuard(dirty ? { isDirty: () => true } : null);
  // Live service state: updated after connect/refresh without a full remount.
  const [liveService, setLiveService] = useState<UserService>(service);
  const [saving, setSaving] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  // Exactly the rules the old boolean encoded, as the reason they failed — the edit pane never
  // renders the url-var/header fields `validateServiceDraft` additionally checks (see
  // `fromService`), so reusing the shared required-field block keeps the gate byte-identical in
  // behaviour while giving the bar something to say.
  const block = requiredFieldsBlock(draft);
  const valid = block === null;

  async function handleSave() {
    if (!valid) return;
    setSaving(true);
    setFormError(null);
    try {
      const body: PatchServiceBody = {
        name: draft.name.trim(),
        baseUrl: draft.baseUrl.trim(),
        ...(draft.apiKeyInput ? { apiKey: draft.apiKeyInput } : {}),
      };
      const saved = await api.services.patch(service.id, body);
      // Adopt the saved row as the new baseline so Save re-disables until the next edit —
      // this instance stays mounted (onSaved re-selects the SAME id, no remount).
      commit(fromService(saved));
      onSaved(saved);
    } catch (err) {
      reportUnexpectedAuthError(err, { feature: "services", step: "save" });
      setFormError(err instanceof Error ? err.message : "Failed to save service.");
    } finally {
      setSaving(false);
    }
  }

  async function handleDelete() {
    if (!window.confirm(`Delete service "${draft.name}"? This cannot be undone.`)) return;
    setSaving(true);
    setFormError(null);
    try {
      await api.services.delete(service.id);
      onDeleted();
    } catch (err) {
      reportUnexpectedAuthError(err, { feature: "services", step: "delete" });
      setFormError(err instanceof Error ? err.message : "Failed to delete service.");
      setSaving(false);
    }
  }

  async function handleConnect() {
    setConnecting(true);
    try {
      const updated = await api.services.connect(service.id);
      setLiveService(updated);
      onSaved(updated);
    } catch (err) {
      reportUnexpectedAuthError(err, { feature: "services", step: "connect" });
    } finally {
      setConnecting(false);
    }
  }

  async function handleRefreshModels() {
    setRefreshing(true);
    try {
      const updated = await api.services.refreshModels(service.id);
      setLiveService(updated);
      onSaved(updated);
    } catch (err) {
      reportUnexpectedAuthError(err, { feature: "services", step: "refreshModels" });
    } finally {
      setRefreshing(false);
    }
  }

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      {/* The affordance rides SectionHeader's own `actions`, not a sibling in a justify-between row:
          once the title hoists into the stack strip that row had one child and the API button
          jumped to the left edge (and with no affordance it was an empty padded band). */}
      <SectionHeader
        paneTitle
        title={draft.name || "Service"}
        className="items-center px-6 pt-4 pb-2"
        actions={renderRecordAffordance?.({
          path: "/persona/services/{id}",
          pathValues: { id: service.id },
          title: "Service API",
        })}
      />
      <ToolbarPortal>
        <ButtonBar
          actions={{
            onCreate: () => {},
            onCancel,
            canCancel: true,
            onSave: () => void handleSave(),
            canSave: dirty && valid,
            saving,
            onDelete: () => void handleDelete(),
            canDelete: true,
          }}
          showCreate={false}
          leading={
            // Say WHY Save is grey when a required field is the blocker; silent when the only
            // reason is "nothing changed yet", which the grey button already communicates.
            block && dirty ? (
              <span className="text-xs text-apt-text-muted" role="status">
                {block}
              </span>
            ) : undefined
          }
        />
      </ToolbarPortal>
      <div className="flex min-h-0 min-w-0 flex-1 flex-col gap-4 overflow-y-auto px-6 py-4">
        <ErrorText error={formError} />

        <ServiceFields
          draft={draft}
          onChange={(next) => patch(next)}
          providerDisabled
          apiKeyHint={liveService.hasApiKey ? "Leave blank to keep the existing key." : undefined}
          apiKeyPlaceholder={liveService.hasApiKey ? "•••• set" : "sk-…"}
        />

        <FieldGroup
          title="Connection"
          trailing={
            liveService.lastConnectedAt ? (
              <span className="font-mono text-[0.65rem] text-apt-text-dim">
                Last: {fmtDate(liveService.lastConnectedAt)}
              </span>
            ) : undefined
          }
        >
          <div className="flex flex-col gap-2">
            <Button size="sm" onClick={() => void handleConnect()} disabled={connecting}>
              {connecting ? "Connecting…" : "Connect"}
            </Button>
            {liveService.connectStatus === "failed" && liveService.connectError && (
              <ErrorText error={liveService.connectError} />
            )}
            {liveService.connectStatus === "connected" && (
              <p className="text-sm text-apt-green">Connected successfully.</p>
            )}
          </div>
        </FieldGroup>

        <FieldGroup
          title="Models"
          trailing={
            liveService.modelsFetchedAt ? (
              <span className="font-mono text-[0.65rem] text-apt-text-dim">
                Fetched: {fmtDate(liveService.modelsFetchedAt)}
              </span>
            ) : undefined
          }
        >
          <Button size="sm" onClick={() => void handleRefreshModels()} disabled={refreshing}>
            {refreshing ? "Refreshing…" : "Refresh"}
          </Button>
          <ModelsTable models={liveService.models} />
        </FieldGroup>
      </div>
    </div>
  );
}

// ─── ServicesSection ──────────────────────────────────────────────────────────

/**
 * The Services section: a HierarchicalTopicDetail whose rail is the service list
 * and whose pane is the editor (the frame's select hint while nothing is open).
 * "New Service" lives in the top bar; the breadcrumb names the open service.
 *
 * DUAL SELECTION MODE (mirrors PersonasSection): pass `urlSelection` and the open service is
 * URL-driven + deep-linkable — a host's persona-services route wires this (see the hub's
 * `ServicesRoute`). Omit it — as an embedded ecosystem topic rail does — and selection is internal
 * state, so opening a service happens IN PLACE without navigating out of the surrounding surface.
 */
export function ServicesSection({
  urlSelection,
  title = "Persona Services",
}: {
  /** The rail level's heading — the label this list appears under in the stack (e.g.
   *  "LLM Providers" when hosted as a workspace Settings topic). Defaults to the feature's
   *  own name so standalone/embedded callers are unchanged. */
  title?: string;
  urlSelection?: {
    /** The open service's id, from the URL path segment (`/<slug>/persona-services/<id>`). */
    serviceId?: string;
    /** Route to a service (null clears back to the list). */
    onSelectService: (id: string | null) => void;
  };
} = {}) {
  // Creating a service is a MODAL over the stack, never a blank editor leaf (HTD recipe
  // `must-create-in-modal`): the `+` opens it, and on save the created service is selected so its
  // editor (Connection, Models) opens.
  const [newOpen, setNewOpen] = useState(false);
  // Dual-mode selection: URL-driven (deep-linkable) when `urlSelection` is passed, else internal.
  const { selectedId: openServiceId, select } = useDualModeSelection(
    urlSelection && {
      selectedId: urlSelection.serviceId ?? null,
      onSelect: urlSelection.onSelectService,
    },
  );

  // Open a service (or null to close): URL-driven callers navigate, embedded callers set state.
  const selectService = (id: string | null) => {
    select(id);
  };

  // The services, cached: coming back to this pane paints the list on the first frame and re-reads
  // behind that paint, instead of showing "Loading…" for the length of a round trip every time.
  const { items: services, reload, error, isFetching } = useUserServices();

  // Swallowing: every caller below re-reads AFTER its own write succeeded, so a failed re-read must
  // not surface as an unhandled rejection. It still reaches the screen — as `error`.
  const refresh = useCallback(() => {
    void reload().catch(() => {});
  }, [reload]);

  const rows = services ?? [];
  const items: TopicDetailItem[] = rows.map((s) => ({
    id: s.id,
    label: s.name,
    sublabel: s.providerKind,
    icon: <Boxes size={16} aria-hidden />,
  }));

  // The open service: the selected id resolved against the loaded rows. An unknown/deleted id (or
  // none) is "nothing open" → the select hint (fail-fast, never a blank screen).
  const openService = openServiceId ? rows.find((s) => s.id === openServiceId) ?? null : null;
  const levels: TopicLevel[] = [
    {
      id: "services",
      title,
      items,
      selectedId: openService?.id ?? null,
      onSelect: (id) => selectService(id),
      onClear: () => selectService(null),
      emptyLabel: "No services yet.",
      // The spinner in this list's title while a read is in flight — including the re-read behind a
      // cached paint, which is the only sign that rows already on screen are being checked.
      busy: isFetching,
      // "New Service" is a right-justified `+` in the list header; it opens the create modal.
      onNew: () => setNewOpen(true),
      newLabel: "New Service",
      // The unselected pane is the frame's select hint and nothing else (docs/ui/fleet-ui-audit.md
      // §1.5) — the rail beside it already lists every service (mirrors PersonasSection).
      itemNoun: "service",
      // The failure rides INSIDE the hint: the frontier overview hides the pane's children with
      // `display: none`, so the `<ErrorText>` below is unreadable whenever any row is listed.
      overviewHelp: error ? <ErrorText error={error} /> : undefined,
    },
  ];

  // DUAL MODE: under a rail host, PUBLISH the service level into the host's merged stack (its
  // selected row becomes the breadcrumb tail — Acme ▸ Persona Services ▸ Anthropic); standalone, own HTD.
  const railHost = useRailHost();

  const content =
    // A failed read leaves the rows null too, so "nothing yet" must not go on claiming the list is
    // still on its way: fall through to the table, which renders the failure above an empty one.
    services === null && error === null ? (
      <p className="p-6 text-sm text-apt-text-muted">Loading…</p>
    ) : openService ? (
      <ServiceEditor
        key={openService.id}
        service={openService}
        onSaved={(saved) => {
          selectService(saved.id);
          refresh();
        }}
        onDeleted={() => {
          selectService(null);
          refresh();
        }}
        onCancel={() => selectService(null)}
      />
    ) : (
      // Nothing open: the frame's select hint owns this pane. It only yields to these children
      // when the list is EMPTY — which is exactly when a load failure has to be readable.
      <ErrorText error={error} className="px-6 pt-4" />
    );

  // Create is a scoped modal: an optional template picker + the service's fields (HTD recipe
  // `must-create-in-modal`). Connecting and refreshing models live in the service's editor, which
  // opens once the created service is selected.
  const newDialog = newOpen ? (
    <CreateResourceDialog<ServiceDraft, UserService>
      ariaLabel="New service"
      heading="New service"
      blank={() => ({ ...BLANK_DRAFT })}
      validate={validateServiceDraft}
      create={(d) => {
        const connectionSpec = connectionSpecForCreate(d);
        return api.services.create({
          name: d.name.trim(),
          providerKind: d.providerKind as UserService["providerKind"],
          baseUrl: d.baseUrl.trim(),
          ...(d.templateId ? { templateId: d.templateId } : {}),
          ...(d.apiKeyInput ? { apiKey: d.apiKeyInput } : {}),
          ...(connectionSpec ? { connectionSpec } : {}),
        });
      }}
      onClose={() => setNewOpen(false)}
      onCreated={(saved) => {
        setNewOpen(false);
        selectService(saved.id);
        refresh();
      }}
      renderForm={(draft, onChange, error) => (
        <NewServiceForm draft={draft} onChange={onChange} error={error} />
      )}
    />
  ) : null;

  // Under a rail host: PUBLISH the service level and render the leaf. Standalone: own stack.
  if (railHost)
    return (
      <>
        <StackLevels levels={levels}>{content}</StackLevels>
        {newDialog}
      </>
    );
  return (
    <>
      <HierarchicalDetailView levels={levels} showBreadcrumb={false}>
        {content}
      </HierarchicalDetailView>
      {newDialog}
    </>
  );
}
