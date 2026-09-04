// Integrations API client — wired to the real backend integrations subsystem
// (/api/integrations). Covers two surfaces:
//   • the provider CATALOG (GET /integrations/providers) — every provider the
//     platform can integrate, with its auth method + capabilities; and
//   • an ecosystem's own, owner-scoped provider CONFIGS — its OAuth client
//     credentials + optional endpoint overrides, secrets masked to `hasSecret`.
//
// `ecosystemId` == the ecosystem id (the RLS owner). The backend 403s if it isn't
// the caller's own ecosystem; that surfaces as a thrown AuthHttpError the pane
// renders inline (it never crashes).
//
// It also covers an ecosystem's CONNECTIONS (linked accounts): list / connect
// (all five auth methods) / disconnect / sync-now / per-connection sync settings,
// plus the OAuth start endpoints (auth-url, register-instance, link-token). Every
// call names the target ecosystem (list/auth-url/link-token/register-instance take
// `ecosystemId`; connect names it in `ecosystemId`); the backend authorizes the caller
// against that ecosystem (403 otherwise). Connection-scoped ops (disconnect / sync /
// settings) derive the ecosystem from the connection, so they take only its id.

import { authedJson, authedRequest, decodeBase64UrlJson, isNotFound } from "../http";
import { enc } from "../client-helpers";
import type {
  AdoptInstallationsBodyType,
  AdoptInstallationsResultRow,
  AuthUrlResultRow,
  ConnectRequestBody,
  CreateProviderConfigBody,
  DeliverabilityWebhookRow,
  LinkTokenBodyType,
  MaskedProviderConfigRow,
  ProviderCatalogEntryRow,
  ProviderConfigInputBody,
  RegisterInstanceBodyType,
  RegisterInstanceResultRow,
  SafeConnectionRow,
  SyncSettingsBodyType,
  SyncSettingsResultRow,
} from "./wire";

/** A provider catalog entry (from GET /integrations/providers). */
export type ProviderCatalogEntry = ProviderCatalogEntryRow;

/** The provider auth methods that gate the config editor's field set. */
export type ProviderAuthMethod = ProviderCatalogEntry["authMethod"];

/** A stored, secret-masked provider config for an ecosystem. */
export type MaskedProviderConfig = MaskedProviderConfigRow;

/** The registration details for a provider's deliverability webhook (postmark today). */
export type DeliverabilityWebhook = DeliverabilityWebhookRow;

/** The PUT (upsert) body for a provider config — a blank/absent
 *  `clientSecret` preserves the stored secret. */
export type ProviderConfigInput = ProviderConfigInputBody;

/** The POST (create) body for a new provider config — names the target provider
 *  and a human-facing config name, plus the same input fields as the upsert body. */
export type CreateProviderConfig = CreateProviderConfigBody;

/** A caller's own connection (linked account), secrets redacted. */
export type SafeConnection = SafeConnectionRow;

/** The polymorphic connect body — a discriminated union keyed by `type`
 *  (= the provider's auth method). Every variant requires `ecosystemId`: the
 *  client names the target ecosystem, and the backend authorizes the caller
 *  against it (403 otherwise) before persisting the connection under it. */
export type ConnectRequest = ConnectRequestBody;

/** `{ url, state }` — the OAuth authorize URL + the round-trip CSRF state. */
export type AuthUrlResult = AuthUrlResultRow;
export type AdoptInstallationsBody = AdoptInstallationsBodyType;
export type AdoptInstallationsResult = AdoptInstallationsResultRow;

/** Body for register-instance (self-hosted OAuth, e.g. Mastodon). */
export type RegisterInstanceBody = RegisterInstanceBodyType;

/** `{ state, authorizeUrl, clientId }` from register-instance. */
export type RegisterInstanceResult = RegisterInstanceResultRow;

/** Optional body for the Plaid link-token mint (`{ serviceType? }`). */
export type LinkTokenBody = LinkTokenBodyType;

/** Per-connection sync settings the worker reads (gmail today). */
export type SyncSettingsBody = SyncSettingsBodyType;

/** `{ ok, syncSettings }` returned by the settings PATCH. */
export type SyncSettingsResult = SyncSettingsResultRow;

const BASE = "/api/integrations";

/** The client route the OAuth/oauth_instance provider redirects back to with the
 *  authorization `code`. Kept as one constant so the connect flow and the callback
 *  page agree on the path. The backend must allow this path for the hub's origins
 *  (see `redirectAllowlist.ts`). */
export const OAUTH_CALLBACK_PATH = "/integrations/oauth-callback";

/** The absolute callback URL for the current origin (client-only). */
export function oauthCallbackUrl(): string {
  return `${window.location.origin}${OAUTH_CALLBACK_PATH}`;
}

/**
 * The claims the backend signs into an integration OAuth `state`.
 *
 * The backend mints `state` as `base64url(JSON(claims)) + "." + base64url(HMAC)` — the
 * claims travel IN the token, in the clear, and the signature is what makes them
 * trustworthy (`integration/oauthState.ts`). That shape is what lets
 * {@link decodeOAuthStateClaims} exist at all.
 */
export interface IntegrationOAuthStateClaims {
  /** The user the flow was started by; the backend re-checks it against the caller. */
  customerId: string;
  providerId: string;
  serviceType: string;
  /** The ecosystem uuid the connect must be filed under. */
  ecosystemId: string;
  /** Issued-at, epoch-ms. */
  iat: number;
}

/**
 * Read (never TRUST) the claims a `state` carries, or null when it is not one of ours.
 *
 * It decodes the payload half and ignores the signature ON PURPOSE, because nothing here is
 * a security decision: every value it recovers goes straight back to
 * `POST /integrations/connect`, which re-verifies the signature, that the state was minted
 * for THIS caller, and that it names this ecosystem, before it writes anything. A forged
 * state gets the same 400 it would have got without this function.
 *
 * It exists because a GitHub App has ONE Setup URL for the whole app: an installation
 * started on any origin in the family returns to the SAME origin, where the pending-connect
 * stash — `sessionStorage`, which is per-origin — is empty. The state is the only thing
 * that crosses that boundary, and it already names the provider, the service type and the
 * ecosystem, which is everything the connect needs.
 */
export function decodeOAuthStateClaims(state: string): IntegrationOAuthStateClaims | null {
  const dot = state.indexOf(".");
  if (dot <= 0 || dot === state.length - 1) return null;
  // Decoded by `auth`'s shared base64url-JSON reader rather than by an `atob` here. The
  // backend serializes these claims with `JSON.stringify` and base64s the UTF-8 bytes, and
  // `atob` hands those bytes back one per code unit — so a non-ASCII serviceType or
  // ecosystem id decoded naively becomes mojibake in the very fields that are echoed to
  // `POST /integrations/connect`, where they match nothing. That decode is identical to the
  // one a JWT payload needs, and it was written three times before it was written once.
  const parsed = decodeBase64UrlJson(state.slice(0, dot));
  if (!parsed || typeof parsed !== "object") return null;
  const c = parsed as Record<string, unknown>;
  const str = (v: unknown): v is string => typeof v === "string" && v.length > 0;
  if (!str(c.customerId) || !str(c.providerId) || !str(c.serviceType) || !str(c.ecosystemId)) {
    return null;
  }
  if (typeof c.iat !== "number" || !Number.isFinite(c.iat)) return null;
  return {
    customerId: c.customerId,
    providerId: c.providerId,
    serviceType: c.serviceType,
    ecosystemId: c.ecosystemId,
    iat: c.iat,
  };
}

/**
 * How long a minted `state` stays valid, and how far ahead of us an issuer's clock may be.
 *
 * These MIRROR `OAUTH_STATE_TTL_MS` and `FUTURE_SKEW_MS` in the hub backend's
 * `integration/oauthState.ts`, which is the authority: the backend re-checks freshness on
 * every connect, and this copy is a COURTESY — it exists to say "start again" in a sentence
 * instead of forwarding the backend's rejection prose, and it must never be the thing that
 * decides a connect.
 *
 * Which is why the pre-flight window is deliberately WIDER than the backend's by
 * {@link OAUTH_STATE_CLOCK_GRACE_MS}, in both directions. The two clocks are the operator's
 * browser and a server, so mirrored bounds do not agree: they differ by whatever the drift
 * plus the round-trip is, and a client that is even a second STRICTER refuses a state the
 * backend would have taken — telling an operator to redo an installation that was about to
 * succeed, with no way to tell that from a real expiry. Being wider only ever costs the POST
 * that would have happened anyway before this check existed, answered by the backend's own
 * verdict. The grace is the drift this can absorb; past it the backend answers, as it always
 * did.
 *
 * They live here, beside the claims they judge, because the claims are the only reason a
 * client can ask the question at all.
 */
export const OAUTH_STATE_TTL_MS = 10 * 60 * 1000;
/** @see {@link OAUTH_STATE_TTL_MS} */
export const OAUTH_STATE_FUTURE_SKEW_MS = 60_000;
/** How far the two clocks may disagree before this pre-flight and the backend can differ on
 *  the same state. Added to BOTH bounds, so the client's window strictly contains the
 *  backend's and this check can only ever be the more permissive of the two.
 *  @see {@link OAUTH_STATE_TTL_MS} */
export const OAUTH_STATE_CLOCK_GRACE_MS = 30_000;

/**
 * Whether a decoded `state` is still within the window the backend will accept.
 *
 * The case this exists for is not an edge: `setup_action=request` tells the operator that an
 * org owner has to approve the installation, and an approval that arrives more than ten
 * minutes later comes back with a state the backend is certain to reject. Without this the
 * callback POSTs anyway and reports the rejection as an unexpected error — a Sentry event and
 * a line of backend prose — for the outcome its own message told the operator to expect.
 */
export function isOAuthStateFresh(
  claims: Pick<IntegrationOAuthStateClaims, "iat">,
  now: number = Date.now(),
): boolean {
  const age = now - claims.iat;
  return (
    age <= OAUTH_STATE_TTL_MS + OAUTH_STATE_CLOCK_GRACE_MS &&
    age >= -(OAUTH_STATE_FUTURE_SKEW_MS + OAUTH_STATE_CLOCK_GRACE_MS)
  );
}

const configPath = (ecosystemId: string, providerId?: string) =>
  providerId
    ? `${BASE}/ecosystems/${enc(ecosystemId)}/provider-configs/${enc(providerId)}`
    : `${BASE}/ecosystems/${enc(ecosystemId)}/provider-configs`;

/** The id/rdid-addressed path for one provider config within an ecosystem. */
const configByIdPath = (ecosystemId: string, configId: string) =>
  `${BASE}/ecosystems/${enc(ecosystemId)}/provider-configs/${enc(configId)}`;

export const integrationsApi = {
  /** The provider catalog — every provider the platform can integrate. */
  async listProviders(): Promise<ProviderCatalogEntry[]> {
    const { providers } = await authedJson<{ providers: ProviderCatalogEntry[] }>(
      `${BASE}/providers`,
    );
    return providers;
  },

  /** The ecosystem's configured providers (secrets masked to `hasSecret`). */
  async listProviderConfigs(ecosystemId: string): Promise<MaskedProviderConfig[]> {
    const { configs } = await authedJson<{ configs: MaskedProviderConfig[] }>(
      configPath(ecosystemId),
    );
    return configs;
  },

  /** One masked config, or null when none is stored yet (backend 404). */
  async getProviderConfig(
    ecosystemId: string,
    providerId: string,
  ): Promise<MaskedProviderConfig | null> {
    try {
      return await authedJson<MaskedProviderConfig>(configPath(ecosystemId, providerId));
    } catch (err) {
      if (isNotFound(err)) return null;
      throw err;
    }
  },

  /** Upsert the config. A blank/absent `clientSecret` in `body` preserves the
   *  stored secret; a present one replaces it. Returns the masked row. */
  async putProviderConfig(
    ecosystemId: string,
    providerId: string,
    body: ProviderConfigInput,
  ): Promise<MaskedProviderConfig> {
    return authedJson<MaskedProviderConfig>(configPath(ecosystemId, providerId), {
      method: "PUT",
      body: JSON.stringify(body),
    });
  },

  async deleteProviderConfig(ecosystemId: string, providerId: string): Promise<void> {
    await authedRequest(configPath(ecosystemId, providerId), { method: "DELETE" });
  },

  // ── id/rdid-addressed provider-config CRUD ───────────────────────────────────

  /** Create a new provider config under the ecosystem. POSTs to the collection path
   *  with a `providerId` + `name` and the config input fields; returns the masked row. */
  async createProviderConfig(
    ecosystemId: string,
    body: CreateProviderConfigBody,
  ): Promise<MaskedProviderConfig> {
    return authedJson<MaskedProviderConfig>(configPath(ecosystemId), {
      method: "POST",
      body: JSON.stringify(body),
    });
  },

  /** One masked config addressed by its id/rdid, or null when it doesn't exist
   *  (backend 404). */
  async getProviderConfigById(
    ecosystemId: string,
    configId: string,
  ): Promise<MaskedProviderConfig | null> {
    try {
      return await authedJson<MaskedProviderConfig>(configByIdPath(ecosystemId, configId));
    } catch (err) {
      if (isNotFound(err)) return null;
      throw err;
    }
  },

  /** Update an existing provider config addressed by its id/rdid. A blank/absent
   *  `clientSecret` in `body` preserves the stored secret. Returns the masked row. */
  async updateProviderConfig(
    ecosystemId: string,
    configId: string,
    body: ProviderConfigInput & { name?: string },
  ): Promise<MaskedProviderConfig> {
    return authedJson<MaskedProviderConfig>(configByIdPath(ecosystemId, configId), {
      method: "PUT",
      body: JSON.stringify(body),
    });
  },

  /** Delete a provider config addressed by its id/rdid. */
  async deleteProviderConfigById(ecosystemId: string, configId: string): Promise<void> {
    await authedRequest(configByIdPath(ecosystemId, configId), { method: "DELETE" });
  },

  /**
   * Mint a NEW inbound webhook secret for this config and return the updated masked row (the
   * value arrives on `deliverabilityWebhook.secret` — it is never echoed anywhere else).
   *
   * DESTRUCTIVE, in the same sense as rotating a list's embed key: the previous secret stops
   * authenticating the moment this returns, so a provider still configured with it starts
   * failing silently — Postmark logs a 401 its own side and nothing in the product notices.
   * Callers must confirm before firing it.
   *
   * It is also the ONLY way a config created before per-config secrets existed gets one, so it
   * doubles as "generate" for a webhook whose `secret` is null.
   */
  async rotateWebhookSecret(
    ecosystemId: string,
    configId: string,
  ): Promise<MaskedProviderConfig> {
    return authedJson<MaskedProviderConfig>(
      `${configByIdPath(ecosystemId, configId)}/rotate-webhook-secret`,
      { method: "POST" },
    );
  },

  // ── connections (linked accounts for the caller's active ecosystem) ──────────

  /** The connections OWNED by ecosystem `ecosystemId` (secrets redacted), across all
   *  providers. The backend authorizes the caller against the ecosystem (403 otherwise). */
  async listConnections(ecosystemId: string): Promise<SafeConnection[]> {
    const { connections } = await authedJson<{ connections: SafeConnection[] }>(
      `${BASE}?ecosystemId=${enc(ecosystemId)}`,
    );
    return connections;
  },

  /** Finish a connect for any auth method and persist the connection. The `body`
   *  names the owning ecosystem in `ecosystemId`; the backend authorizes the caller
   *  against it (403 otherwise) before persisting the connection under it. */
  async connect(body: ConnectRequest): Promise<SafeConnection> {
    return authedJson<SafeConnection>(`${BASE}/connect`, {
      method: "POST",
      body: JSON.stringify(body),
    });
  },

  /** Disconnect (soft-delete) a connection the caller owns. */
  async disconnect(connectionId: string): Promise<void> {
    await authedRequest(`${BASE}/${enc(connectionId)}`, { method: "DELETE" });
  },

  /** Trigger an immediate sync. Throws AuthHttpError(503) when no worker is
   *  registered for the provider yet (caller shows an inline "not available" note). */
  async sync(connectionId: string): Promise<void> {
    await authedRequest(`${BASE}/${enc(connectionId)}/sync`, { method: "POST" });
  },

  /** Update a connection's caller-tunable sync settings (gmail today). */
  async patchSettings(
    connectionId: string,
    body: SyncSettingsBody,
  ): Promise<SyncSettingsResult> {
    return authedJson<SyncSettingsResult>(`${BASE}/${enc(connectionId)}/settings`, {
      method: "PATCH",
      body: JSON.stringify(body),
    });
  },

  // ── OAuth / install / instance / link-token start endpoints ─────────────────

  /** Get the provider's OAuth authorize URL + the signed round-trip `state`, for the
   *  target ecosystem (its client id drives the URL; caller authorized against it). */
  async getAuthUrl(
    providerId: string,
    params: { ecosystemId: string; redirectUri: string; serviceType?: string; scopes?: string },
  ): Promise<AuthUrlResult> {
    const qs = new URLSearchParams({
      ecosystemId: params.ecosystemId,
      redirectUri: params.redirectUri,
    });
    if (params.serviceType) qs.set("serviceType", params.serviceType);
    if (params.scopes) qs.set("scopes", params.scopes);
    return authedJson<AuthUrlResult>(
      `${BASE}/providers/${enc(providerId)}/auth-url?${qs.toString()}`,
    );
  },

  /**
   * Get the provider's app-INSTALLATION URL + the signed round-trip `state` (`github_app`
   * providers only; 400 otherwise).
   *
   * No `redirectUri`, and that absence is the whole difference from {@link getAuthUrl}: an
   * app returns to the setup URL configured ON THE APP at the provider, so there is nothing
   * here for a caller to point somewhere else — and no `scopes` either, because an app's
   * permissions are declared on the app, not negotiated per request.
   */
  async getInstallUrl(
    providerId: string,
    params: { ecosystemId: string; serviceType?: string },
  ): Promise<AuthUrlResult> {
    const qs = new URLSearchParams({ ecosystemId: params.ecosystemId });
    if (params.serviceType) qs.set("serviceType", params.serviceType);
    return authedJson<AuthUrlResult>(
      `${BASE}/providers/${enc(providerId)}/install-url?${qs.toString()}`,
    );
  },

  /**
   * Connect every installation the saved GitHub App can already see — `github_app`
   * providers only (400 otherwise).
   *
   * This is the redirect-free connect, and it is also the credential test: the backend can
   * only answer by signing a JWT the provider accepts, so a wrong app id or an unreadable
   * private key fails HERE, at the moment they were entered, rather than at the first
   * deploy. An installation already in service is reported under `skipped` rather than
   * taken, so calling it twice is safe.
   */
  async adoptInstallations(
    providerId: string,
    body: AdoptInstallationsBody,
  ): Promise<AdoptInstallationsResult> {
    return authedJson<AdoptInstallationsResult>(
      `${BASE}/providers/${enc(providerId)}/adopt-installations`,
      { method: "POST", body: JSON.stringify(body) },
    );
  },

  /** Register a self-hosted OAuth instance (Mastodon) → `{ state, authorizeUrl, clientId }`. */
  async registerInstance(
    providerId: string,
    body: RegisterInstanceBody,
  ): Promise<RegisterInstanceResult> {
    return authedJson<RegisterInstanceResult>(
      `${BASE}/providers/${enc(providerId)}/register-instance`,
      { method: "POST", body: JSON.stringify(body) },
    );
  },

  /** Mint a Plaid Link token for the provider. */
  async createLinkToken(
    providerId: string,
    body?: LinkTokenBody,
  ): Promise<{ linkToken: string }> {
    return authedJson<{ linkToken: string }>(
      `${BASE}/providers/${enc(providerId)}/link-token`,
      { method: "POST", body: JSON.stringify(body ?? {}) },
    );
  },
};
