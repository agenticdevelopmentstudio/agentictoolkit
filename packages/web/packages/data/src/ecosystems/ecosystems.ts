// Ecosystems API client — wired to the real backend (generic CRUD over
// `ecosystems.ecosystems`, an RDID-addressed table).
//
// Routes: /api/ecosystem/ecosystems (list/create),
//         /api/ecosystem/ecosystems/{id} (get/update/delete).
//
// `ecosystems.ecosystems` is RDID-addressed: its public `id` is the
// reverse-domain identifier (rdid) — the backend resolves rdid<->uuid at the
// request edge, so every response already carries the rdid as `id`. The UI
// models the same value under two names (`id` for routing/handles, `identifier`
// for display + uniqueness); both map to the one backend `id`.
//
// Field map:
//   UI identifier / id  <->  backend `id`            (the rdid — the STORED handle)
//   UI slug             <->  backend `slug`          (the row's own last segment)
//   UI name             <->  backend `name`
//   UI description      <->  backend `description`
//   UI region           <->  backend `region`
//   UI domain           <->  backend `primaryDomain`
//
// CREATE DOES NOT SET THE ADDRESS. The server DERIVES it from (the owner's parent
// chain, `slug`) and mints it — so `slug` is the address's LAST SEGMENT, one rdid
// segment, and the `id` we send is only an ASSERTION that the caller and the server
// agree on what that address will be (the backend 400s when `id`'s leaf and `slug`
// disagree). This client used to send `slug = identifier` — the whole dotted rdid,
// clamped to the column's 64 chars — which was correct only under the pre-Task-5
// contract where the client's `id` was stored verbatim and `slug` was a cosmetic
// mirror of it. Under the current contract that shape fails EVERY create, because a
// dotted rdid can never equal its own leaf.
//
// The `identifier` (rdid) IS mutable, and moving it is the SAME `slug` field: update()
// sends the new last segment in the ordinary PUT, and the route re-derives the address and
// cascades it onto the handle and every descendant. There is no second call — see update()'s
// own doc for why the registry.identifiers PATCH this client used to chase the PUT with was
// the wrong (non-structural) rename.

import { authedJson, authedRequest, isNotFound, rethrowConflict } from "../http";
import { compact, enc, sortByText } from "../client-helpers";
import type { EcosystemRow, EcosystemCreateBody, EcosystemPutBody } from "./wire";

/**
 * An address's LAST SEGMENT — the one part of an rdid a create or a rename supplies.
 *
 * Deliberately a pure `lastIndexOf('.')` slice, mirroring the backend's own `rdidLeaf`
 * character for character, rather than `tryParseRdid(id)?.name`. The two agree on every
 * WELL-FORMED rdid and disagree on exactly the malformed ones — an unknown type prefix, an
 * over-length address, a bad segment — where the parser returns undefined and a `?? identifier`
 * fallback would put the whole dotted string in `slug`. That is the original bug in miniature:
 * the server compares its own leaf of `id` against `slug`, so a dotted `slug` can never match
 * and the request 400s with "id X does not match slug X" — a message about an agreement that
 * was never the problem, hiding whatever is actually wrong with the address. Sending the true
 * leaf keeps the assertion satisfied so the server rejects (or accepts) on the address itself.
 */
function addressLeaf(identifier: string): string {
  return identifier.slice(identifier.lastIndexOf(".") + 1);
}

export interface Ecosystem {
  id: string;
  identifier: string;
  /**
   * The stored slug — the row's OWN last segment, and the ONLY thing that moves its address.
   *
   * Exposed (rather than left to `identifier`'s last segment) because the two can disagree, and
   * a settings form that edits "the slug" has to show the value the server will actually compare
   * against. `identifier` is the STORED HANDLE; the address the row DERIVES to is
   * `<parent chain>.<slug>`. A handle renamed on its own — `PATCH /registry/identifiers/{rdid}`,
   * a backfill, or (before the 2026-08-10 fix) a rename whose cascade left the row's own handle
   * behind — leaves the two divergent until the next slug write heals them. While they are
   * divergent, presenting the handle's leaf as "the slug" makes retyping the row's REAL slug look
   * like a rename and land as a no-op.
   */
  slug: string;
  name: string;
  description: string;
  region: string;
  domain: string;
  createdAt: string;
  updatedAt: string;
  /** Workspace-scoped lists only: whether the caller may manage this ecosystem's
   *  contents (the org-admin bar). Absent (undefined) outside `?workspace=` mode,
   *  where every listed ecosystem is manageable by construction. */
  canManage?: boolean;
}

export interface EcosystemInput {
  identifier: string;
  name: string;
  description: string;
  region: string;
  domain: string;
}

/** The explicit per-ecosystem auth policy (backend `ecosystem.auth_settings`), served by
 *  the bespoke /ecosystem/auth-settings route (not generic CRUD → hand-declared, like
 *  `capabilities` below, rather than sourced from the OpenAPI spec). */
export type SignupMode = "open" | "invite_only" | "closed";
export interface AuthSettings {
  signupMode: SignupMode;
  loginEnabled: boolean;
  /** Email + password sign-in and sign-up for the customer realm. */
  passwordEnabled: boolean;
  /** null = all configured providers. */
  allowedProviders: string[] | null;
}

const BASE = "/api/ecosystem/ecosystems";

export function toEcosystem(r: EcosystemRow): Ecosystem {
  return {
    id: r.id,
    identifier: r.id,
    slug: r.slug,
    name: r.name,
    description: r.description ?? "",
    region: r.region ?? "",
    domain: r.primaryDomain ?? "",
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
    ...(r.canManage !== undefined ? { canManage: r.canManage } : {}),
  };
}

export const ecosystemsApi = {
  async list(): Promise<Ecosystem[]> {
    const rows = await authedJson<EcosystemRow[]>(BASE);
    // Hide the auto-provisioned default ecosystems (`<rdid>.ecosystem`): they're managed
    // infrastructure, not ecosystems the user created, so listing them would just double
    // the list with "X (default)" siblings. They stay addressable directly by rdid.
    return sortByText(
      rows.filter((r) => !r.isDefault).map(toEcosystem),
      (e) => e.name,
    );
  },

  /** The ecosystems a WORKSPACE directly OWNS (`owner_id` = the workspace's principal —
   *  the caller's customer for a personal workspace, an org they belong to for an org
   *  workspace) — the hub's Products list. Ownership, not access: scoped server-side
   *  (`?workspace=`), never admin-widened; the server also excludes both the structural
   *  defaults AND the principal's auto-provisioned infrastructure row, so no client
   *  filter is needed (unlike the unscoped {@link list}). Rows carry `canManage`. */
  async listForWorkspace(workspaceSlug: string): Promise<Ecosystem[]> {
    const rows = await authedJson<EcosystemRow[]>(`${BASE}?workspace=${enc(workspaceSlug)}`);
    return sortByText(rows.map(toEcosystem), (e) => e.name);
  },

  /** The default (account-infrastructure) ecosystem id — the auto-provisioned own ecosystem the
   *  workspace-level Storage/Integrations panes scope to, and the parent a new ecosystem hangs
   *  under. Resolved server-side by OWNERSHIP (`infrastructure=true`), never client-side:
   *  an org's own ecosystem is a ROOT while a person's is itself a child of their home realm,
   *  so no string built from a slug is right for both.
   *
   *  With a `workspaceSlug` it is the WORKSPACE PRINCIPAL's row (`?workspace=`, membership-gated)
   *  — never the caller's own, which is a different principal's ecosystem on an org workspace.
   *  WITHOUT one it is the CALLER's own row, which is what a slug-less host (a feature-site mount)
   *  needs and what that host's unscoped create actually parents under; the two calls mirror the
   *  two create scopes exactly, which is what keeps a previewed address equal to the minted one.
   *
   *  `null` when there is no infrastructure row (never `undefined`, which react-query rejects as
   *  query data). */
  async workspaceDefaultEcosystemId(
    workspaceSlug?: string,
  ): Promise<{ id: string; canManage: boolean } | null> {
    const scope = workspaceSlug != null ? `workspace=${enc(workspaceSlug)}&` : "";
    const rows = await authedJson<EcosystemRow[]>(`${BASE}?${scope}infrastructure=true`);
    const row = rows[0];
    // `canManage` is annotated by the workspace-mode list: a member can READ the org's infra
    // ecosystem (membership-gated) but only an org admin can MANAGE its contents — the host uses
    // this to show an honest "ask an admin" notice instead of a wall of per-pane 403s.
    return row ? { id: row.id, canManage: row.canManage !== false } : null;
  },

  /** The CHILD ecosystems of `parentId` (an ecosystem rdid/uuid): the ecosystems whose owner IS
   *  that ecosystem — the "Child Ecosystems" view. Scoped server-side (`?parent=`, which also
   *  excludes the structural defaults), so admins get the same node-scoped set here rather
   *  than every ecosystem. */
  async listChildren(parentId: string): Promise<Ecosystem[]> {
    const rows = await authedJson<EcosystemRow[]>(`${BASE}?parent=${enc(parentId)}`);
    return sortByText(rows.map(toEcosystem), (e) => e.name);
  },

  async get(id: string): Promise<Ecosystem | null> {
    try {
      return toEcosystem(
        await authedJson<EcosystemRow>(`${BASE}/${enc(id)}`),
      );
    } catch (err) {
      // 404 → null (the UI contract is null-for-missing). Rethrow anything else so a
      // transient failure isn't mistaken for a deleted ecosystem (callers redirect on a
      // confirmed null, so a network blip must not masquerade as "does not exist").
      if (isNotFound(err)) return null;
      throw err;
    }
  },

  /** Create an ecosystem. Pass `parent` (an ecosystem rdid/uuid) to create it as a CHILD of
   *  that ecosystem (owner = the parent, landed in the parent's child namespace); pass
   *  `workspace` (a workspace slug) to stamp the WORKSPACE's principal as owner (the org for
   *  an org workspace — membership-gated server-side), so the product shows up in that
   *  workspace's list instead of the creator's personal one; omit both for a top-level,
   *  developer-owned ecosystem. `parent` wins when both are given (they never are today). */
  async create(
    input: EcosystemInput,
    opts?: { parent?: string; workspace?: string },
  ): Promise<Ecosystem> {
    // No pre-read for duplicates: the backend's unique rdid + unique slug are the
    // real guards (and a pre-read can't see a soft-deleted row still holding the
    // key). Catch the 409 and surface a friendly, entity-named message instead.
    try {
      const body: EcosystemCreateBody = {
        id: input.identifier,
        // The address's LAST SEGMENT — see the contract note at the top of this file and
        // {@link addressLeaf}. The server asserts `id`'s leaf === `slug`, so anything but the
        // leaf is a guaranteed 400; a malformed identifier still sends its true leaf, so the
        // SERVER names what is wrong with the ADDRESS instead of reporting a mismatch.
        slug: addressLeaf(input.identifier),
        name: input.name,
        description: input.description,
        region: input.region,
        primaryDomain: input.domain,
      };
      const url = opts?.parent
        ? `${BASE}?parent=${enc(opts.parent)}`
        : opts?.workspace
          ? `${BASE}?workspace=${enc(opts.workspace)}`
          : BASE;
      const row = await authedJson<EcosystemRow>(url, {
        method: "POST",
        body: JSON.stringify(body),
      });
      return toEcosystem(row);
    } catch (err) {
      rethrowConflict(
        err,
        `An ecosystem with identifier "${input.identifier}" already exists.`,
      );
    }
  },

  /**
   * Update the mutable fields, and RENAME when `identifier` changes.
   *
   * A rename is a `slug` change in this one PUT, not a second call: the address is DERIVED from
   * (parent chain, slug), so the stored slug is the only thing that moves it, and this route
   * cascades the new address onto the handle and every descendant — child ecosystems, apps,
   * buckets, integrations, the customers scoped under it. This client used to PUT the fields and
   * then PATCH `registry.identifiers`, which is the OTHER, non-structural rename: it retitles the
   * handle and leaves the slug column behind, so the row went on deriving its OLD address, its
   * descendants kept deriving off the old segment, and the next ancestor cascade re-leafed the
   * handle back — silently undoing the rename. That shape was correct only under the pre-Task-5
   * contract, where the handle WAS the stored address.
   *
   * The old two-call sequence needed a 404-recovery branch (the first call could land, the second
   * fail, and the old id stop resolving). One call has no such window — a failed PUT changes
   * nothing — so there is nothing left to recover.
   */
  async update(id: string, input: Partial<EcosystemInput>): Promise<Ecosystem> {
    // The submitted address's LEAF, whenever the caller supplied an address at all. The
    // identifier's prefix is the parent's own address and is not the caller's to change (the form
    // fixes it), so what can differ is the last segment — taken with {@link addressLeaf}, which is
    // the server's own slice, so a malformed identifier still lets the route reject the ADDRESS
    // rather than a manufactured leaf/slug mismatch.
    //
    // SENT ON PRESENCE, NOT ON A DIFF AGAINST `id`, because `id` is the wrong baseline to diff
    // against. `id` is the STORED HANDLE; what a settings form edits is the address the row DERIVES
    // to (`<parent chain>.<slug>` — see {@link Ecosystem.slug}), and the two disagree on exactly the
    // drifted rows. Skipping the field when they happen to match silently drops the save that
    // matters most there: a row whose handle says `…mike` while its slug column says `chosen`,
    // renamed BACK to the `…mike` every other surface shows it under, is a real slug change that
    // equals `id` — withheld, it 200s having changed nothing. Sending it also declares the save a
    // rename to the route (`patchRenamesLeaf`), which is what licenses re-deriving the row's own
    // handle rather than rescoping it as a descendant.
    //
    // Sending an unchanged slug costs nothing: the route's locked value diff (`addressPatchMoves`)
    // compares the stored slug against the submitted one and rules the write out before any cascade.
    const body = compact({
      slug: input.identifier != null ? addressLeaf(input.identifier) : undefined,
      name: input.name,
      description: input.description,
      region: input.region,
      primaryDomain: input.domain,
    } satisfies EcosystemPutBody);
    // The echoed row carries the address the server DERIVED, which is the authority — never the
    // identifier the caller typed. They agree for a legal leaf; where they don't, the derived one
    // is what exists, and returning the typed one would hand callers an id that resolves to nothing.
    return toEcosystem(
      await authedJson<EcosystemRow>(`${BASE}/${enc(id)}`, {
        method: "PUT",
        body: JSON.stringify(body),
      }),
    );
  },

  delete(id: string): Promise<void> {
    return authedRequest(`${BASE}/${enc(id)}`, { method: "DELETE" });
  },

  /** Resolve the ecosystem id (rdid) for a WORKSPACE slug — the workspace principal's OWN
   *  ecosystem, else (for a slug that names no workspace) the caller's default ecosystem, else
   *  the first row. Surfaces that carry no ecosystem in their URL — the standalone
   *  `/[slug]/messaging` route — gate on this, so an arbitrary pick is a wrong tenant.
   *
   *  Ownership first, via {@link workspaceDefaultEcosystemId}, because a client-side
   *  `slug ===` scan is no longer unambiguous: slugs are unique only WITHIN a parent
   *  (`uq_ecosystems_parent_slug`), so once products hang under their owner rather than at the
   *  root, any product named `<slug>` under any OTHER workspace matches the workspace's own row
   *  just as well — and whichever the list happened to return first would win. The scan survives
   *  only as the fallback for a slug the server does not resolve as a workspace at all (a 404
   *  there is "not a workspace", not a failure), reading the RAW rows — unlike {@link list},
   *  which hides default ecosystems and sorts alphabetically.
   *
   *  `null` (never `undefined`, which react-query rejects as query data) when nothing resolves. */
  async ecosystemIdForSlug(slug: string): Promise<string | null> {
    try {
      // By name, not `this`: callers pass these as bare function references
      // (`queryFn: ecosystemsApi.x`), where `this` would be undefined.
      const own = await ecosystemsApi.workspaceDefaultEcosystemId(slug);
      if (own) return own.id;
    } catch (err) {
      // Only a 404 means "this slug names no workspace" and licenses the fallback below.
      // Anything else is a real failure and must not be papered over with an arbitrary row.
      if (!isNotFound(err)) throw err;
    }
    const rows = await authedJson<EcosystemRow[]>(BASE);
    return (
      (rows.find((r) => r.slug === slug) ??
        rows.find((r) => r.isDefault) ??
        rows[0])?.id ?? null
    );
  },

  /** The explicit per-ecosystem AUTH POLICY governing this ecosystem's vended customer
   *  realm. Absent server-side ⇒ documented defaults (invite_only + login enabled); the
   *  route always returns a full object. `id` is the ecosystem's rdid (or uuid). */
  async authSettings(id: string): Promise<AuthSettings> {
    return authedJson<AuthSettings>(`/api/ecosystem/auth-settings/${enc(id)}`);
  },

  /** Update the auth policy (partial patch; `compact` drops undefined keys but preserves an
   *  explicit `allowedProviders: null` = "all providers"). Returns the effective policy. */
  async updateAuthSettings(id: string, patch: Partial<AuthSettings>): Promise<AuthSettings> {
    return authedJson<AuthSettings>(`/api/ecosystem/auth-settings/${enc(id)}`, {
      method: "PUT",
      body: JSON.stringify(compact(patch)),
    });
  },
};
