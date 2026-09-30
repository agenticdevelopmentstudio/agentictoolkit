// Applications settings client — wired to the real backend generic CRUD over
// `ecosystems.applications` (/api/ecosystem/applications).
//
// NOTE: the file/export still carries the "prototype" name for now to avoid
// churning the three consuming components; it is NO LONGER a localStorage
// prototype for the core entity. Renaming `applicationsPrototypeApi` ->
// `applicationsApi` is a tracked cosmetic follow-up (the name `applicationsApi`
// is currently taken by the separate data-hub OAuth client in ./applications.ts).
//
// `ecosystems.applications` is RDID-addressed: the public `id` IS the
// reverse-domain identifier (rdid), stored in platform.identifiers. So `id` and
// `identifier` are the same value here (mirrors api/ecosystems.ts). The required
// NOT-NULL `slug` column has no UI field, so it is derived from the identifier.
//
// Field mapping (UI <-> backend row):
//   identifier / id  <->  id (rdid)            name  <->  displayName
//   ecosystemId      <->  ecosystemId
//
// The row's `consumerKind` is not modelled: nothing reads it. A create sends the fixed
// CONSUMER_KIND the backend's NOT NULL column needs; an update never sends it.
//
// schemaGrants are PERSISTED (no longer session-only): an application's schema permissions ARE its
// per-app bucket access-groups (the model `canBucketAccess` enforces), managed via the hand-written
// /ecosystem/applications/:id/schema-grants route (backend routes/applicationSchemaGrants.ts). This
// client maps the UI's `Crud` objects ↔ the route's "C,R,U,D" wire and loads/saves them alongside
// the application row. (tokens remain a separate real backend — AccessTokensSection.)

import type { RequestBody, SuccessBody } from "@agentic-toolkit/adh-api-types";
import { authedJson, authedRequest } from "@agentic-toolkit/auth/client";
import { rethrowConflict } from "@agentic-toolkit/data";
import { identifiersApi } from "@agentic-toolkit/data/ecosystems";
import {
  APPLICATION_PLATFORMS,
  type ApplicationPlatform,
} from "@agentic-toolkit/data/ecosystem-config";
import { compact, enc, narrow, scopeByOwner, sortByText } from "@agentic-toolkit/data";
import {
  CRUD_KEYS,
  type Crud,
  type SchemaGrant,
} from "../applications/permission-model";

// What a create writes to the backend's required `consumer_kind` column (CHECK 'staff' |
// 'developer' | 'customer'). Nothing reads the column, so it is not a field.
const CONSUMER_KIND = "developer";

export interface AccessToken {
  id: string;
  /** Shown in the list; the full secret is only returned once at creation. */
  prefix: string;
  name: string;
  createdAt: string;
}

export interface PrototypeApplication {
  /** Equals `identifier` (the rdid is the public id for this table). */
  id: string;
  /** Reverse-domain identifier, e.g. com.acme.myapp. User-facing key. */
  identifier: string;
  name: string;
  /** Web or native: what its login registration accepts. */
  platform: ApplicationPlatform;
  /** STUB (session-only): schemas this app granted itself, each with perms. */
  schemaGrants: SchemaGrant[];
  /** STUB (session-only): access tokens. */
  tokens: AccessToken[];
  ecosystemId: string;
  createdAt: string;
  updatedAt: string;
}

export interface ApplicationInput {
  identifier: string;
  name: string;
  platform: ApplicationPlatform;
  schemaGrants: SchemaGrant[];
}

const BASE = "/api/ecosystem/applications";

// The backend `ecosystems.applications` row, sourced from the OpenAPI spec.
// (`id` is the rdid — the backend swaps the uuid for the rdid on the way out.)
type ApplicationRow = SuccessBody<"/ecosystem/applications", "get">[number];

export function toApp(r: ApplicationRow, schemaGrants: SchemaGrant[] = []): PrototypeApplication {
  return {
    id: r.id,
    identifier: r.id,
    name: r.displayName,
    platform: narrow(r.platform, APPLICATION_PLATFORMS, "web"),
    schemaGrants,
    // Tokens are fetched on demand by the detail's AccessTokensSection (real backend),
    // not carried on the list row — avoids an N+1 token fetch across the list.
    tokens: [],
    ecosystemId: r.ecosystemId,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
  };
}

// ── schema-grants (persisted) — the app's per-app bucket access-groups, via the schema-grants route.
// The wire is a serialized CRUD string ("C,R,U,D") per bucket + per table; the UI uses `Crud` objects.
const CRUD_LETTER: Record<(typeof CRUD_KEYS)[number], string> = {
  create: "C",
  read: "R",
  update: "U",
  delete: "D",
};
function crudToWire(c: Crud): string {
  return CRUD_KEYS.filter((k) => c[k]).map((k) => CRUD_LETTER[k]).join(",");
}
function crudFromWire(s: string): Crud {
  return {
    create: s.includes("C"),
    read: s.includes("R"),
    update: s.includes("U"),
    delete: s.includes("D"),
  };
}
interface SchemaGrantWire {
  schemaId: string;
  crud: string;
  tables: { tableId: string; crud: string }[];
}
const grantsBase = (appId: string) => `${BASE}/${enc(appId)}/schema-grants`;

/** Load an application's schema grants (empty on any error — grants are secondary to the row). */
async function getGrants(appId: string): Promise<SchemaGrant[]> {
  try {
    const body = await authedJson<{ grants: SchemaGrantWire[] }>(grantsBase(appId));
    return body.grants.map((g) => ({
      schemaId: g.schemaId,
      permissions: crudFromWire(g.crud),
      tables: Object.fromEntries(
        g.tables.map((t) => [t.tableId, { level: "table" as const, permissions: crudFromWire(t.crud) }]),
      ),
    }));
  } catch {
    return [];
  }
}
/** Reconcile an application's schema grants to `grants` (drops no-access tables — no grant row). */
async function putGrants(appId: string, grants: SchemaGrant[]): Promise<void> {
  const body = {
    grants: grants.map((g) => ({
      schemaId: g.schemaId,
      crud: crudToWire(g.permissions),
      tables: Object.entries(g.tables)
        .map(([tableId, tg]) => ({ tableId, crud: crudToWire(tg.permissions) }))
        .filter((t) => t.crud !== ""),
    })),
  };
  await authedRequest(grantsBase(appId), { method: "PUT", body: JSON.stringify(body) });
}

// auth.api_tokens metadata the backend returns for an application token. The mint
// response additionally carries the raw `token` (revealed exactly once).
interface ApiTokenRow {
  id: string;
  name: string;
  prefix: string;
  createdAt: string;
}
const toToken = (r: ApiTokenRow): AccessToken => ({
  id: r.id,
  prefix: r.prefix,
  name: r.name,
  createdAt: r.createdAt,
});
const tokensBase = (appId: string) => `${BASE}/${enc(appId)}/tokens`;

export const applicationsPrototypeApi = {
  async list(ecosystemId?: string): Promise<PrototypeApplication[]> {
    // No server-side list filter, so narrow to the chosen ecosystem here. The editor reads
    // schemaGrants off the list row (useMasterDetailForm.toInput), so load each app's grants here —
    // one call per app, in parallel. Fine at settings volume (a handful of apps).
    const rows = await authedJson<ApplicationRow[]>(BASE);
    const scoped = scopeByOwner(rows, ecosystemId, (r) => r.ecosystemId);
    const apps = await Promise.all(scoped.map(async (r) => toApp(r, await getGrants(r.id))));
    return sortByText(apps, (a) => a.name);
  },

  async get(id: string): Promise<PrototypeApplication | null> {
    try {
      const [row, grants] = await Promise.all([
        authedJson<ApplicationRow>(`${BASE}/${enc(id)}`),
        getGrants(id),
      ]);
      return toApp(row, grants);
    } catch {
      return null;
    }
  },

  async create(input: ApplicationInput, ecosystemId: string): Promise<PrototypeApplication> {
    // No pre-read for duplicates: the backend's unique rdid + unique
    // (ecosystem, slug) index are the real guards. Catch the 409 → friendly msg.
    try {
      // The rdid is DERIVED server-side as app.<ecosystem-slug>.<slug>; we send the slug
      // (the leaf the user chose) + the ecosystem, not a client-built id. `id` is sent for
      // type-compat but ignored server-side for applications (the deriver is authoritative).
      const leaf = input.identifier.slice(input.identifier.lastIndexOf(".") + 1);
      const appBody: RequestBody<"/ecosystem/applications", "post"> = {
        id: input.identifier,
        slug: leaf.slice(0, 64),
        displayName: input.name,
        consumerKind: CONSUMER_KIND,
        platform: input.platform,
        ecosystemId: ecosystemId || undefined, // absent → caller's ecosystem
      };
      const row = await authedJson<ApplicationRow>(BASE, {
        method: "POST",
        body: JSON.stringify(appBody),
      });
      if (input.schemaGrants.length > 0) await putGrants(row.id, input.schemaGrants);
      return toApp(row, input.schemaGrants);
    } catch (err) {
      rethrowConflict(
        err,
        `An application with identifier "${input.identifier}" already exists.`,
      );
    }
  },

  async update(id: string, input: Partial<ApplicationInput>): Promise<PrototypeApplication> {
    // The rdid (the app's id) is editable only in its LEAF. The entity PUT can't re-key it,
    // so a leaf rename goes through the registry.identifiers route; the backend rejects any
    // type/scope change with a 400 (the UI only exposes the leaf, so it can't send one).
    // Rename FIRST so the field PUT lands under the new id.
    const nextId = input.identifier && input.identifier !== id ? input.identifier : null;
    // The app's schema-grant groups are keyed by its id (name `app-<id>`, memberId = id), so a
    // rename would orphan them AND break enforcement. Re-home them: capture the grants, drop the
    // OLD-id groups while the old id still resolves, rename, then recreate under the new id below.
    const carried = nextId ? (input.schemaGrants ?? (await getGrants(id))) : null;
    if (nextId) {
      await putGrants(id, []).catch(() => {});
      await identifiersApi.rename(id, nextId);
    }
    const effectiveId = nextId ?? id;
    const fields: Partial<RequestBody<"/ecosystem/applications/{id}", "put">> = {
      displayName: input.name,
      platform: input.platform,
    };
    const row = await authedJson<ApplicationRow>(`${BASE}/${enc(effectiveId)}`, {
      method: "PUT",
      body: JSON.stringify(compact(fields)),
    });
    if (nextId) {
      await putGrants(effectiveId, carried ?? []);
    } else if (input.schemaGrants !== undefined) {
      await putGrants(effectiveId, input.schemaGrants);
    }
    const grants = nextId ? (carried ?? []) : input.schemaGrants ?? (await getGrants(effectiveId));
    return toApp(row, grants);
  },

  async delete(id: string): Promise<void> {
    // Drop the app's schema-grant groups first — no FK cascade from a group member to the app row.
    await putGrants(id, []).catch(() => {});
    await authedRequest(`${BASE}/${enc(id)}`, { method: "DELETE" });
  },

  // ── Access tokens — real backend (/ecosystem/applications/:appId/tokens) ──────
  async listTokens(appId: string): Promise<AccessToken[]> {
    const rows = await authedJson<ApiTokenRow[]>(tokensBase(appId));
    return rows.map(toToken);
  },

  /** Mint a token; the raw `secret` is returned exactly once (reveal-once UX). */
  async createToken(appId: string, name: string): Promise<{ token: AccessToken; secret: string }> {
    const row = await authedJson<ApiTokenRow & { token: string }>(tokensBase(appId), {
      method: "POST",
      body: JSON.stringify({ name: name.trim() || "Token" }),
    });
    return { token: toToken(row), secret: row.token };
  },

  async revokeToken(appId: string, tokenId: string): Promise<void> {
    await authedRequest(`${tokensBase(appId)}/${enc(tokenId)}`, { method: "DELETE" });
  },
};
