"use client";

import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Textarea } from "@agenticdevelopertoolkit/ui/components/textarea";
import { noAutofillProps } from "@agenticdevelopertoolkit/ui/lib/autofill";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { Disclosure } from "@agenticdevelopertoolkit/ui/components/disclosure";
import type {
  CreateProviderConfig,
  MaskedProviderConfig,
  ProviderAuthMethod,
  ProviderCatalogEntry,
  ProviderConfigInput,
} from "@agentic-toolkit/data/integrations";

/**
 * The controlled draft for an ecosystem's owner-scoped provider config. The
 * `clientSecret` is WRITE-ONLY: the API only ever returns `hasSecret`, so it is
 * always empty on load — a blank value on save preserves the stored secret. The
 * non-secret `endpoints` map isn't editable here (no key/value editor yet); it is
 * carried through unchanged so a save doesn't wipe a provider's stored overrides.
 */
export interface IntegrationInput {
  providerId: string;
  /** Human-facing label for this config, set in the add/saved detail view. */
  name: string;
  clientId: string;
  /** Write-only: blank preserves the stored secret; never populated from the server. */
  clientSecret: string;
  /** Space/comma-separated in the UI; parsed to string[] on save. */
  scopes: string;
  authUrl: string;
  tokenUrl: string;
  userinfoUrl: string;
  validateUrl: string;
  credentialStyle: "" | "form_body" | "basic_auth";
  /** Opaque non-secret overrides, round-tripped unchanged so a save preserves them. */
  endpoints: Record<string, string>;
  /** api_key providers: the spec-driven config field values, keyed by field key. The
   *  secret field is WRITE-ONLY (always blank on load; blank on save preserves it). */
  fields: Record<string, string>;
  /** api_key providers: off pauses sending without deleting the stored secret. */
  enabled: boolean;
}

// ── auth-method gating ───────────────────────────────────────────────────────
// These methods are configured at the ECOSYSTEM level: OAuth-family providers store a
// client app (client id/secret + endpoints); api_key providers store their spec-driven
// credential + config fields (shared by the whole ecosystem); github_app stores the app's
// own identity (app id + private key), which every installation of it authenticates with.
// app_password providers have no ecosystem-level config — their creds are entered per
// account at connect time.
const OWNER_CONFIGURABLE: readonly ProviderAuthMethod[] = [
  "oauth",
  "oauth_instance",
  "plaid_link",
  "api_key",
  "github_app",
];

export function ownerConfigurable(authMethod: ProviderAuthMethod | undefined): boolean {
  return authMethod !== undefined && OWNER_CONFIGURABLE.includes(authMethod);
}

/**
 * Whether a provider drives its ecosystem config through spec-driven `configFields` (the
 * `ApiKeyFields` editor + the `fields` write body). This is BROADER than `authMethod ===
 * "api_key"`: bluesky (app_password) and mastodon (oauth_instance) also declare configFields,
 * so the config editor/read/write path must gate on this — not on api_key, which would render
 * the wrong fields and drop theirs. It takes PRECEDENCE over `ownerConfigurable`/OAuth. OAuth
 * providers declare no configFields and keep the clientId/secret (`OAuthFields`) path.
 */
export function hasConfigFields(provider?: ProviderCatalogEntry): boolean {
  return (provider?.configFields?.length ?? 0) > 0;
}

const AUTH_METHOD_LABEL: Record<ProviderAuthMethod, string> = {
  oauth: "OAuth",
  oauth_instance: "OAuth (self-hosted instance)",
  plaid_link: "Plaid Link",
  api_key: "API key",
  app_password: "App password",
  github_app: "GitHub App",
};

export function authMethodLabel(authMethod: ProviderAuthMethod | undefined): string {
  return (authMethod && AUTH_METHOD_LABEL[authMethod]) || "Unknown";
}

// ── config-object <-> input mapping ──────────────────────────────────────────
type ConfigObject = MaskedProviderConfig["config"];

function readString(config: ConfigObject, key: string): string {
  const v = config[key];
  return typeof v === "string" ? v : "";
}

function readStringArray(config: ConfigObject, key: string): string[] {
  const v = config[key];
  return Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : [];
}

function readEndpoints(config: ConfigObject): Record<string, string> {
  const v = config.endpoints;
  if (!v || typeof v !== "object") return {};
  const out: Record<string, string> = {};
  for (const [k, val] of Object.entries(v as Record<string, unknown>)) {
    if (typeof val === "string") out[k] = val;
  }
  return out;
}

function readCredentialStyle(config: ConfigObject): IntegrationInput["credentialStyle"] {
  const v = config.credentialStyle;
  return v === "form_body" || v === "basic_auth" ? v : "";
}

/** Scopes text → a clean, order-preserving list (split on whitespace/commas). */
export function parseScopes(text: string): string[] {
  return text
    .split(/[\s,]+/)
    .map((s) => s.trim())
    .filter(Boolean);
}

/** A blank draft for a chosen provider (the add-integration flow). */
export function intBlank(providerId: string): IntegrationInput {
  return {
    providerId,
    name: "",
    clientId: "",
    clientSecret: "",
    scopes: "",
    authUrl: "",
    tokenUrl: "",
    userinfoUrl: "",
    validateUrl: "",
    credentialStyle: "",
    endpoints: {},
    fields: {},
    enabled: true,
  };
}

export function intToInput(
  row: MaskedProviderConfig,
  provider?: ProviderCatalogEntry,
): IntegrationInput {
  const c = row.config;
  // `fields` drives the configField editor only; for OAuth providers (no configFields) it stays
  // empty (they use the clientId/secret/scopes shape), so we don't carry a dead copy here.
  const fields: Record<string, string> = {};
  if (hasConfigFields(provider)) {
    // The non-secret field values live directly in `config` (the secret is never returned).
    for (const [k, v] of Object.entries(c)) {
      if (k !== "enabled" && typeof v === "string") fields[k] = v;
    }
  }
  return {
    providerId: row.providerId,
    name: row.name,
    clientId: readString(c, "clientId"),
    clientSecret: "",
    scopes: readStringArray(c, "scopes").join(" "),
    authUrl: readString(c, "authUrl"),
    tokenUrl: readString(c, "tokenUrl"),
    userinfoUrl: readString(c, "userinfoUrl"),
    validateUrl: readString(c, "validateUrl"),
    credentialStyle: readCredentialStyle(c),
    endpoints: readEndpoints(c),
    fields,
    enabled: c.enabled !== false,
  };
}

/** True when a draft's fields differ from a baseline. `name` is excluded by default — this
 *  is what the master/detail pane-exit guard uses, and it only needs to catch the
 *  credential/config edits it would otherwise lose (the saved-instance detail view enables its
 *  own Save button on any valid edit, so a name-only change is still saveable there without
 *  tripping the "unsaved changes" exit prompt). Pass `includeName: true` for a Save-button gate,
 *  where a name-only edit should also count as a change worth enabling Save for. */
export function intDiffers(
  a: IntegrationInput,
  b: IntegrationInput,
  opts?: { includeName?: boolean },
): boolean {
  return (
    (opts?.includeName === true && a.name.trim() !== b.name.trim()) ||
    a.clientId.trim() !== b.clientId.trim() ||
    a.clientSecret.trim() !== b.clientSecret.trim() ||
    parseScopes(a.scopes).join(" ") !== parseScopes(b.scopes).join(" ") ||
    a.authUrl.trim() !== b.authUrl.trim() ||
    a.tokenUrl.trim() !== b.tokenUrl.trim() ||
    a.userinfoUrl.trim() !== b.userinfoUrl.trim() ||
    a.validateUrl.trim() !== b.validateUrl.trim() ||
    a.credentialStyle !== b.credentialStyle ||
    JSON.stringify(a.endpoints) !== JSON.stringify(b.endpoints) ||
    JSON.stringify(a.fields) !== JSON.stringify(b.fields) ||
    a.enabled !== b.enabled
  );
}

/** The PUT body for a draft. configField providers send the spec-driven `fields` map (+
 *  `enabled`); OAuth providers (no configFields) send clientId/scopes/…/clientSecret. A blank
 *  secret is OMITTED so the stored secret is preserved. */
export function intToBody(
  draft: IntegrationInput,
  provider?: ProviderCatalogEntry,
): ProviderConfigInput {
  if (hasConfigFields(provider)) {
    const fields: Record<string, string> = {};
    for (const f of provider?.configFields ?? []) {
      const v = (draft.fields[f.key] ?? "").trim();
      // Non-secret fields always go (config_json is replaced); the secret only when the
      // user entered one (blank → omitted → the backend preserves the stored secret).
      if (!f.secret || v) fields[f.key] = v;
    }
    return { fields, enabled: draft.enabled };
  }
  const body: ProviderConfigInput = {};
  const clientId = draft.clientId.trim();
  if (clientId) body.clientId = clientId;
  const scopes = parseScopes(draft.scopes);
  if (scopes.length) body.scopes = scopes;
  const authUrl = draft.authUrl.trim();
  if (authUrl) body.authUrl = authUrl;
  const tokenUrl = draft.tokenUrl.trim();
  if (tokenUrl) body.tokenUrl = tokenUrl;
  const userinfoUrl = draft.userinfoUrl.trim();
  if (userinfoUrl) body.userinfoUrl = userinfoUrl;
  const validateUrl = draft.validateUrl.trim();
  if (validateUrl) body.validateUrl = validateUrl;
  if (draft.credentialStyle) body.credentialStyle = draft.credentialStyle;
  if (Object.keys(draft.endpoints).length) body.endpoints = draft.endpoints;
  const secret = draft.clientSecret.trim();
  if (secret) body.clientSecret = secret; // blank → omitted → preserve stored secret
  return body;
}

/** The POST (create) body for a new provider config: the target provider + a trimmed
 *  human-facing name, plus the same field mapping as {@link intToBody}. The exported
 *  create-body type is aliased as `CreateProviderConfig` (= `CreateProviderConfigBody`). */
export function intToCreateBody(
  draft: IntegrationInput,
  provider?: ProviderCatalogEntry,
): CreateProviderConfig {
  return { providerId: draft.providerId, name: draft.name.trim(), ...intToBody(draft, provider) };
}

/** Returns an error message, or null when the draft is valid for its provider. */
export function intValidate(
  draft: IntegrationInput,
  provider: ProviderCatalogEntry | undefined,
  config: MaskedProviderConfig | null,
): string | null {
  const authMethod = provider?.authMethod;
  // configFields providers (api_key + bluesky/mastodon) validate their spec fields — this
  // takes PRECEDENCE over the OAuth/non-configurable branches below.
  if (hasConfigFields(provider)) {
    for (const f of provider?.configFields ?? []) {
      if (!f.required) continue;
      const v = (draft.fields[f.key] ?? "").trim();
      if (v) continue;
      // The secret is only required on CREATE — an edit keeps the stored one when blank.
      if (f.secret && config?.hasSecret) continue;
      return `${f.label} is required.`;
    }
    return null;
  }
  // Non-configurable providers have no owner-level fields, so there is nothing to
  // validate (Save stays disabled anyway — the draft can't differ from blank).
  if (!ownerConfigurable(authMethod)) return null;
  // Named from the same shape the form labels itself with. Hard-coding "Client ID" here
  // told a GitHub App operator that a field they cannot see is required, while the empty
  // one in front of them said "App ID".
  if (!draft.clientId.trim()) return `${credentialShape(authMethod).idLabel} is required.`;
  return null;
}

// ── extracted field blocks ───────────────────────────────────────────────────
// The three auth-method branches, each a bare fragment (no Card/section wrapper) so
// they compose inside `IntegrationDetailView`'s single config Card. Each block owns only
// its fields; the surrounding Card/section + any error line belong to the caller.

/** Props shared by every extracted field block. `provider` may be undefined while the
 *  provider catalog is still loading. */
export interface IntegrationFieldProps {
  provider: ProviderCatalogEntry | undefined;
  draft: IntegrationInput;
  onChange: (next: IntegrationInput) => void;
  /** The saved config when editing an existing one (null while adding). */
  config: MaskedProviderConfig | null;
}

/** api_key / app_password (and the loading state): no ecosystem-level client app. */
export function NonConfigurableNote({ provider, draft }: IntegrationFieldProps) {
  const authMethod = provider?.authMethod;
  const displayName = provider?.displayName ?? draft.providerId;
  return (
    <>
      <p className="text-sm text-apt-text">
        {displayName} uses {authMethodLabel(authMethod).toLowerCase()} authentication.
      </p>
      <p className="text-sm text-apt-text-muted">
        There is no ecosystem-level client app to configure here. Credentials for{" "}
        {displayName} are entered when a member connects their own account.
      </p>
    </>
  );
}

/** api_key providers: the spec-driven `configFields` + the Enabled toggle. */
export function ApiKeyFields({ provider, draft, onChange, config }: IntegrationFieldProps) {
  const authMethod = provider?.authMethod;
  const displayName = provider?.displayName ?? draft.providerId;
  const specFields = provider?.configFields ?? [];
  return (
    <>
      <p className="text-xs text-apt-text-muted">
        {authMethodLabel(authMethod)} — these credentials are configured once for the
        whole ecosystem; {displayName} uses them to send on the ecosystem&apos;s behalf.
      </p>

      {specFields.map((f) => {
        const fieldId = `int-field-${draft.providerId}-${f.key}`;
        return (
          <div key={f.key} className="flex flex-col gap-2">
            <Label htmlFor={fieldId}>{f.label}</Label>
            {/* The one place in the fleet that names an autofill token DEFENSIVELY
                rather than because it wants a manager. `new-password` is what stops
                Chrome offering the reader's saved site password here — but a token is
                also how a field asks `noAutofillPropsFor` to hand it back, so on its
                own it would opt this field IN, and every manager would offer to save
                an ecosystem's third-party provider secret as the account credential.
                Spreading the bag first and re-asserting the token after is both:
                `Input` sees a token and adds nothing of its own, and the five vendor
                ignore attributes arrive from here. */}
            <Input
              id={fieldId}
              type={f.secret ? "password" : "text"}
              {...noAutofillProps}
              autoComplete={f.secret ? "new-password" : "off"}
              value={draft.fields[f.key] ?? ""}
              placeholder={
                f.secret && config?.hasSecret
                  ? "Secret set — leave blank to keep"
                  : (f.placeholder ?? "")
              }
              onChange={(e) =>
                onChange({ ...draft, fields: { ...draft.fields, [f.key]: e.target.value } })
              }
            />
            {f.secret && (
              <p className="text-xs text-apt-text-muted">
                {config?.hasSecret
                  ? "A secret is stored. Leave blank to keep it, or enter a new one to replace it."
                  : "Stored encrypted; it is never shown again after you save."}
              </p>
            )}
          </div>
        );
      })}

      <label className="flex items-center gap-2 text-sm text-apt-text">
        <input
          type="checkbox"
          className="size-4 accent-apt-gold"
          checked={draft.enabled}
          onChange={(e) => onChange({ ...draft, enabled: e.target.checked })}
        />
        Enabled
      </label>
      <p className="text-xs text-apt-text-muted">
        When off, {displayName} is paused for this ecosystem without deleting its
        stored credentials.
      </p>
    </>
  );
}

/**
 * What an ecosystem-level credential PAIR is called, and what shape it has, for one auth
 * method. `clientId`/`clientSecret` are the storage keys either way — only the words and
 * the input change.
 *
 * This exists because a GitHub App's pair is an app id and a multi-line PEM private key.
 * Labelling those "Client ID" and "Client secret" on a one-line password input is how an
 * operator pastes a PEM into a field that visibly refuses newlines and then cannot tell
 * whether it saved.
 */
export interface CredentialShape {
  /** One line under the heading, given the provider's display name. */
  blurb: (displayName: string) => string;
  idLabel: string;
  idPlaceholder: string;
  secretLabel: string;
  secretPlaceholder: string;
  /** A PEM has newlines; a client secret does not. */
  secretMultiline?: boolean;
  /** Shown once a secret is stored — same promise, different noun. */
  storedHelp: string;
  newHelp: string;
  /** OAuth negotiates scopes per authorization; an app's permissions live ON the app. */
  scopes: boolean;
  /** The endpoint overrides only mean something to an OAuth token exchange. */
  advanced: boolean;
}

const OAUTH_CREDENTIALS: CredentialShape = {
  blurb: (name) =>
    `your ecosystem's own client credentials drive every ${name} connection here.`,
  idLabel: "Client ID",
  idPlaceholder: "your-oauth-client-id",
  secretLabel: "Client secret",
  secretPlaceholder: "your-oauth-client-secret",
  storedHelp: "A secret is stored. Leave blank to keep it, or enter a new one to replace it.",
  newHelp: "Stored encrypted; it is never shown again after you save.",
  scopes: true,
  advanced: true,
};

const GITHUB_APP_CREDENTIALS: CredentialShape = {
  blurb: (name) =>
    `the ${name} you registered on GitHub. Its app id and private key authenticate every` +
    " installation of it, so an installer never enters a credential.",
  idLabel: "App ID",
  idPlaceholder: "123456",
  secretLabel: "Private key",
  secretPlaceholder: "-----BEGIN PRIVATE KEY-----\n…\n-----END PRIVATE KEY-----",
  secretMultiline: true,
  storedHelp:
    "A private key is stored. Leave blank to keep it, or paste a new one to replace it.",
  newHelp:
    "Paste the whole .pem GitHub downloaded, BEGIN and END lines included. Stored encrypted;" +
    " it is never shown again after you save.",
  scopes: false,
  advanced: false,
};

/** Which credential pair a non-configField provider asks for. Exported because the EXPORT
 *  needs the secret's NAME without drawing its field: a document saying "this one needs a
 *  Private key" and one saying "this one needs a Client secret" are the difference between
 *  an operator who can finish the import and one who is guessing. */
export function credentialShape(authMethod: ProviderAuthMethod | undefined): CredentialShape {
  return authMethod === "github_app" ? GITHUB_APP_CREDENTIALS : OAUTH_CREDENTIALS;
}

/** OAuth-family providers: client id/secret/scopes + the Advanced endpoint overrides.
 *  Also github_app, whose pair is an app id + a private key — see {@link CredentialShape}. */
export function OAuthFields({ provider, draft, onChange, config }: IntegrationFieldProps) {
  const authMethod = provider?.authMethod;
  const displayName = provider?.displayName ?? draft.providerId;
  const secretId = `int-secret-${draft.providerId}`;
  const shape = credentialShape(authMethod);
  return (
    <>
      <p className="text-xs text-apt-text-muted">
        {authMethodLabel(authMethod)} — {shape.blurb(displayName)}
      </p>

      <div className="flex flex-col gap-2">
        <Label htmlFor="int-client-id">{shape.idLabel}</Label>
        <Input
          id="int-client-id"
          value={draft.clientId}
          placeholder={shape.idPlaceholder}
          autoComplete="off"
          onChange={(e) => onChange({ ...draft, clientId: e.target.value })}
        />
      </div>

      <div className="flex flex-col gap-2">
        <Label htmlFor={secretId}>{shape.secretLabel}</Label>
        {/* Defensive token, bag spread first — see the note on the spec-driven
            secret field above. */}
        {shape.secretMultiline ? (
          // Not type="password": a PEM is 25 lines and pasting one blind is unverifiable.
          // It is still write-only — the server returns `hasSecret`, never the key — so
          // there is nothing on screen to mask once the page has loaded.
          <Textarea
            id={secretId}
            rows={6}
            spellCheck={false}
            className="font-mono text-xs"
            {...noAutofillProps}
            autoComplete="new-password"
            value={draft.clientSecret}
            placeholder={
              config?.hasSecret ? "Key set — leave blank to keep" : shape.secretPlaceholder
            }
            onChange={(e) => onChange({ ...draft, clientSecret: e.target.value })}
          />
        ) : (
          <Input
            id={secretId}
            type="password"
            {...noAutofillProps}
            autoComplete="new-password"
            value={draft.clientSecret}
            placeholder={
              config?.hasSecret ? "Secret set — leave blank to keep" : shape.secretPlaceholder
            }
            onChange={(e) => onChange({ ...draft, clientSecret: e.target.value })}
          />
        )}
        <p className="text-xs text-apt-text-muted">
          {config?.hasSecret ? shape.storedHelp : shape.newHelp}
        </p>
      </div>

      {shape.scopes && (
        <div className="flex flex-col gap-2">
          <Label htmlFor="int-scopes">Scopes</Label>
          <Input
            id="int-scopes"
            value={draft.scopes}
            placeholder="e.g. read write"
            onChange={(e) => onChange({ ...draft, scopes: e.target.value })}
          />
          <p className="text-xs text-apt-text-muted">
            Space- or comma-separated. Leave blank to use the provider defaults.
          </p>
        </div>
      )}

      {shape.advanced && (
      <Disclosure title="Advanced" subtitle="Endpoint & credential overrides">
        <div className="flex flex-col gap-5">
          <p className="text-xs text-apt-text-muted">
            Optional. Leave blank to use the provider&apos;s built-in endpoints.
          </p>
          <div className="flex flex-col gap-2">
            <Label htmlFor="int-auth-url">Authorization URL</Label>
            <Input
              id="int-auth-url"
              value={draft.authUrl}
              placeholder="https://provider.example/oauth/authorize"
              onChange={(e) => onChange({ ...draft, authUrl: e.target.value })}
            />
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor="int-token-url">Token URL</Label>
            <Input
              id="int-token-url"
              value={draft.tokenUrl}
              placeholder="https://provider.example/oauth/token"
              onChange={(e) => onChange({ ...draft, tokenUrl: e.target.value })}
            />
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor="int-userinfo-url">Userinfo URL</Label>
            <Input
              id="int-userinfo-url"
              value={draft.userinfoUrl}
              placeholder="https://provider.example/userinfo"
              onChange={(e) => onChange({ ...draft, userinfoUrl: e.target.value })}
            />
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor="int-validate-url">Validate URL</Label>
            <Input
              id="int-validate-url"
              value={draft.validateUrl}
              placeholder="https://provider.example/validate"
              onChange={(e) => onChange({ ...draft, validateUrl: e.target.value })}
            />
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor="int-cred-style">Credential style</Label>
            <Select
              id="int-cred-style"
              value={draft.credentialStyle}
              onChange={(e) =>
                onChange({
                  ...draft,
                  credentialStyle: e.target.value as IntegrationInput["credentialStyle"],
                })
              }
            >
              <option value="">Provider default</option>
              <option value="form_body">Form body</option>
              <option value="basic_auth">Basic auth</option>
            </Select>
            <p className="text-xs text-apt-text-muted">
              How the client id/secret are sent to the token endpoint.
            </p>
          </div>
        </div>
      </Disclosure>
      )}
    </>
  );
}

