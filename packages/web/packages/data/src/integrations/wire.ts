// Wire types for the integrations domain — package-local mirrors of the OpenAPI-generated
// request/response shapes the hub previously imported as `RequestBody`/`SuccessBody` from
// `@agentic-toolkit/adh-api-types` (for /integrations/*). These carry full backend-schema fidelity
// (not just the fields today's call sites touch) so the toolkit stays decoupled from the
// hub's generated types without narrowing what a caller can rely on.

/** A provider catalog entry (from GET /integrations/providers). */
export interface ProviderCatalogEntryRow {
  providerId: string;
  displayName: string;
  /** Short one-line tagline shown under the display name. */
  subtitle: string;
  /** Longer marketing/help copy for the provider. */
  description: string;
  /** Related links (docs, sign-up, dashboard) rendered as anchors. */
  links: { label: string; url: string }[];
  authMethod:
    | "oauth"
    | "oauth_instance"
    | "plaid_link"
    | "api_key"
    | "app_password"
    /** A provider-hosted APP the operator installs, rather than an authorization the
     *  operator grants. The ecosystem config holds the app's own identity (id + private
     *  key); a connection holds the id of one installation of it. */
    | "github_app";
  serviceTypes: string[];
  /** read | write | auth */
  capabilities: string[];
  /** Default minimum sync interval (ms) */
  defaultPollIntervalMs: number;
  /** For api_key providers: declarative config/credential fields, rendered + validated
   *  identically at ecosystem and user scope (absent for OAuth-style providers). */
  configFields?: {
    key: string;
    label: string;
    secret: boolean;
    required: boolean;
    placeholder?: string;
  }[];
}

/**
 * The deliverability webhook an operator has to register with their email provider. The URL is
 * DERIVED by the backend from the ecosystem and returned alongside a config — never stored, so it
 * cannot drift from the URL the webhook route actually accepts.
 */
export interface DeliverabilityWebhookRow {
  /** The absolute URL, addressing this ecosystem. */
  url: string
  /** The custom header name the provider must send `secret` in. */
  secretHeader: string
  /**
   * THIS ECOSYSTEM's own inbound webhook credential — not a deployment-wide value. It is what
   * makes the webhook authenticate one tenant rather than "somebody who configured a webhook",
   * so it is per-config, server-minted and rotatable.
   *
   * `null` means no secret is stored yet (a config created before the column existed): the URL
   * is real but every call to it is refused until the operator rotates one in. Rendering the URL
   * without noticing this hands over a registration that silently 401s forever.
   */
  secret: string | null
  /** One line naming the provider's own setting, so a consumer needs no copy of its own. */
  instruction: string
}

/** A stored, secret-masked provider config for an ecosystem. */
export interface MaskedProviderConfigRow {
  id: string;
  /** Ecosystem id (the RLS owner) */
  ecosystemId: string;
  providerId: string;
  /** Human-facing name for this config. */
  name: string;
  /**
   * Resource id addressing this config (an `integration.*` rdid), or null when the row has no
   * canonical mapping — a row that predates the mint, or one whose mapping an operator freed.
   *
   * NULL RATHER THAN `""`, and the difference is not cosmetic: the empty string is a valid
   * rdid-shaped value that callers treat as one, so keying rows on it collapses every unmapped
   * config into a single identity. Callers that need a stable per-row key or a URL segment fall
   * back to `id` — every by-id integrations route accepts the uuid OR the rdid.
   */
  rdid: string | null;
  /** Non-secret config: clientId, scopes, URLs, endpoints, credentialStyle */
  config: Record<string, unknown>;
  /** Whether a client secret is stored (the value is never returned) */
  hasSecret: boolean;
  /**
   * Present on providers whose deliverability events feed suppression (postmark today), absent
   * on every other provider; `null` when the deployment has not configured a webhook secret and
   * therefore cannot build a working URL. Optional-and-nullable is the shape the backend
   * actually sends — the three cases are told apart, rather than collapsing "this provider has
   * no webhook" into "this deployment has not set one up".
   */
  deliverabilityWebhook?: DeliverabilityWebhookRow | null;
  updatedBy?: string | null;
  createdAt?: string;
  updatedAt?: string;
}

/** The PUT (upsert) body for a provider config — a blank/absent `clientSecret`
 *  preserves the stored secret. */
export interface ProviderConfigInputBody {
  clientId?: string;
  scopes?: string[];
  authUrl?: string;
  tokenUrl?: string;
  userinfoUrl?: string;
  validateUrl?: string;
  credentialStyle?: "form_body" | "basic_auth";
  endpoints?: Record<string, string>;
  /** Blank/absent preserves the existing secret */
  clientSecret?: string;
  /** api_key providers: the provider's declared config fields, keyed by field key (the one
   *  secret is split into the encrypted slot; a blank/absent secret preserves the stored one). */
  fields?: Record<string, string>;
  /** api_key providers: false pauses the provider without deleting its secret. */
  enabled?: boolean;
}

/** The POST (create) body for a new provider config: names the target provider and
 *  a human-facing config name, plus the same non-secret/secret input fields as the
 *  PUT upsert body. */
export type CreateProviderConfigBody = { providerId: string; name: string } & ProviderConfigInputBody;

/** A caller's own connection (linked account), secrets redacted. */
export interface SafeConnectionRow {
  id: string;
  /** Provider slug (e.g. google-calendar, github) */
  provider: string;
  /** Service within the provider (e.g. calendar) */
  serviceType: string;
  /** active | error | revoked | pending */
  status: string;
  displayName: string;
  username: string;
  /** Provider-side account id */
  externalAccountId: string;
  /** Last successful sync (null = never) */
  lastSyncAt?: string | null;
  /** Last recorded sync error */
  lastError?: string | null;
  createdAt: string;
  /** Caller-tunable sync settings (gmailLabelIds / redditSubreddits / …) — non-secret,
   *  returned so settings forms can prefill instead of blind-overwriting. */
  syncSettings?: Record<string, unknown> | null;
}

/** The polymorphic connect body — a discriminated union keyed by `type` (= the provider's
 *  auth method). Every variant requires `ecosystemId`: the client names the target
 *  ecosystem, and the backend authorizes the caller against it (403 otherwise) before
 *  persisting the connection under it. */
export type ConnectRequestBody =
  | {
      type: "oauth";
      providerId: string;
      serviceType: string;
      /** Target ecosystem id (the caller must manage it) */
      ecosystemId: string;
      /** OAuth authorization code */
      code: string;
      redirectUri: string;
      /** The HMAC-signed state returned by the auth-url endpoint (CSRF) */
      state: string;
    }
  | {
      type: "api_key";
      providerId: string;
      serviceType: string;
      ecosystemId: string;
      /** The provider's declared config fields (configFields), keyed by field key; validated
       *  + split into the secret vs non-secret config against the spec. */
      fields: Record<string, string>;
    }
  | {
      type: "app_password";
      providerId: string;
      serviceType: string;
      ecosystemId: string;
      /** Inline creds — supply these OR `providerConfigId` (exactly one; the XOR is
       *  enforced server-side). Omit when the handle + app-password are sourced from a
       *  saved ecosystem provider-config. */
      identifier?: string;
      password?: string;
      instanceUrl?: string;
      /** Source the handle + app-password from THIS ecosystem provider-config instead of
       *  inline creds; the resulting connection links it via provider_config_id. */
      providerConfigId?: string;
    }
  | {
      type: "plaid_link";
      providerId: string;
      serviceType: string;
      ecosystemId: string;
      publicToken: string;
    }
  | {
      type: "oauth_instance";
      providerId: string;
      serviceType: string;
      ecosystemId: string;
      code: string;
      state: string;
    }
  | {
      type: "github_app";
      providerId: string;
      serviceType: string;
      ecosystemId: string;
      /** The numeric installation id the provider redirects back with. There is no `code`
       *  here and that is the difference from `oauth`: an installation is not an
       *  authorization to exchange, it is a thing that now exists and has an id. */
      installationId: string;
      /** The HMAC-signed state returned by the install-url endpoint (CSRF). Without it a
       *  forged connect could file an ATTACKER's installation into a victim's ecosystem. */
      state: string;
    };

/** `{ url, state }` — a redirect URL (OAuth authorize, or app install) + its CSRF state. */
export interface AuthUrlResultRow {
  url: string;
  state: string;
}

/** Body for register-instance (self-hosted OAuth, e.g. Mastodon). */
export interface RegisterInstanceBodyType {
  /** Target ecosystem id (the caller must manage it) */
  ecosystemId: string;
  instanceUrl: string;
  redirectUri: string;
  serviceType?: string;
  /** When set, the per-instance clientId/clientSecret/instanceUrl come from THIS ecosystem
   *  provider-config (the connection links it via provider_config_id) instead of a dynamic
   *  per-user app registration. `instanceUrl` is still required by the schema but is ignored
   *  on this path — the config supplies it. */
  providerConfigId?: string;
}

/** `{ state, authorizeUrl, clientId }` from register-instance. */
export interface RegisterInstanceResultRow {
  state: string;
  authorizeUrl: string;
  clientId: string;
}

/** Body for adopting a GitHub App's existing installations. */
export interface AdoptInstallationsBodyType {
  /** Target ecosystem id (the caller must manage it) */
  ecosystemId: string;
  /** The saved provider-config holding the app id and private key. REQUIRED: the backend
   *  reads it by id rather than resolving, because the resolver falls through to the
   *  platform-global app, whose installations belong to other tenants. */
  providerConfigId: string;
  /** Defaults to the provider primary service type */
  serviceType?: string;
}

/** One installation, and what became of it. */
export interface AdoptedInstallationRow {
  installationId: string;
  accountLogin: string;
  targetType: string;
  /** The connection holding it — set when this call made one, or when one already did. */
  connectionId?: string;
  /** Why it was not connected. Absent on success. */
  skipped?: string;
}

/** `{ connected, skipped }` from adopt-installations. */
export interface AdoptInstallationsResultRow {
  connected: AdoptedInstallationRow[];
  skipped: AdoptedInstallationRow[];
}

/** Body for the Plaid link-token mint. */
export interface LinkTokenBodyType {
  /** Target ecosystem id (the caller must manage it) */
  ecosystemId: string;
  /** Defaults to the provider primary service type */
  serviceType?: string;
}

/** Per-connection sync settings the worker reads (gmail/reddit/mailchimp today). */
export interface SyncSettingsBodyType {
  /** Gmail label ids to sync (default INBOX). */
  gmailLabelIds?: string[];
  /** Days of history to sync (default 30, max 366). */
  gmailWindowDays?: number;
  /** Subreddits to watch (name or r/name; max 50). */
  redditSubreddits?: string[];
  /** Keywords to match within watched subreddits (max 50). */
  redditKeywords?: string[];
  /** Mailchimp/Klaviyo audience (list) ids to also sync CONTACTS for. Absent/empty = the
   *  audience roster only. */
  audienceIds?: string[];
}

/** `{ ok, syncSettings }` returned by the settings PATCH. */
export interface SyncSettingsResultRow {
  ok: boolean;
  syncSettings: Record<string, unknown>;
}
