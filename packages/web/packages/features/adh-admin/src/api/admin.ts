"use client";

import { useMemo } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import type { RequestBody, SuccessBody } from "@agentic-toolkit/adh-api-types";
import { authedJson, authedRequest } from "./http";
import { fetchMemberships, type UserEcosystem } from "./memberships";
import { useWindowedList } from "./windowed";

// The Hono backend has no `/api/admin/*` surface (admin === auth scoping via
// sibling paths gated by isAdmin(), not a URL prefix). The hooks below target
// the real backend routes: hand-written admin routes where they exist, and the
// generic CRUD endpoints (`/api/<schema>/<table>`) otherwise. Where the old
// Kotlin API returned a purpose-built shape (paginated pages, key→value maps),
// the adaptation happens here so the consuming pages stay unchanged.

// ── Users ────────────────────────────────────────────────────────────────
//
// Platform users (hub developers + staff) are customers of ecosystem zero
// (`com.agenticdeveloperhub`) after the identity collapse — the retired
// `auth.users` table is now `customer.customers`. `GET /api/customer/customers`
// (generic CRUD) is filtered to the hub ecosystem so this page keeps its old
// meaning: a developer's END-USERS are also customers (of their own ecosystem),
// and an admin caller (who bypasses tenant scoping) would otherwise see every
// ecosystem's customers mixed in. The whole list is fetched once and narrowed
// in the browser — there is no server-side page.
//
// Capabilities for the Roles column come from the admin-gated
// `GET /api/auth/capabilities` (returns every {userId, capability}); the join
// by id still holds because the collapse preserved each developer's UUID.

export interface AdminUserSummary {
  id: string;
  email: string;
  name: string;
  avatarUrl: string;
  capabilities: string[];
  createdAt: string;
  /** The customer's canonical address, or null when the registry has none for them. */
  rdid: string | null;
  /**
   * Every ecosystem this person is a customer of, hub account first.
   *
   * A SET, not a field: `customer.customers` is per-ecosystem, so the same human has one row per
   * ecosystem joined by email. Empty until the membership lookup lands — the rows themselves
   * arrive first and the column fills in.
   */
  ecosystems: UserEcosystem[];
}

// The raw `customer.customers` row from `GET /api/customer/customers`, sourced
// from the OpenAPI spec (@agentic-toolkit/adh-api-types) rather than hand-written —
// so a backend schema change surfaces here as a type error, not at runtime.
type BackendUser = SuccessBody<"/customer/customers", "get">[number];

// Ecosystem zero — the hub's own ecosystem (`com.agenticdeveloperhub`). Its
// well-known UUID is fixed infra (backend src/lib/ecosystem.ts HUB_ECOSYSTEM_ID);
// hardcoded here because that backend constant isn't importable from the frontend.
const HUB_ECOSYSTEM_ID = "00000000-0000-4000-8000-00000000a001";

/** One row of `GET /registry/identifiers` — see backend src/routes/identifiers.ts. */
export interface RdidMapping {
  rdid: string;
  entityType: string;
  entityId: string;
}

/**
 * The hub ecosystem's canonical address — the users' SOURCE for a transfer, and the exact string
 * the operator has to type to release one.
 *
 * RESOLVED, never hardcoded, and that is not caution for its own sake: this address has already
 * been renamed once (`com.agenticdeveloperhub` → `ecosystem.agenticdeveloperhub`, migration 0056),
 * and the confirmation gate compares against it CASE-SENSITIVELY. A stale constant would not fail
 * loudly — it would make the Transfer button impossible to enable, with the dialog showing the
 * operator a string that is not the one it is checking.
 *
 * `null` while it is unresolved (or if the hub somehow holds no mapping); the gate stays shut on
 * an empty source rather than treating "nothing typed" as a match.
 */
export function useHubEcosystemRdid() {
  return useQuery({
    queryKey: ["admin", "hub-ecosystem-rdid"],
    // An ecosystem's address changes about once a migration. Refetching it per mount buys nothing
    // and costs a request on every visit to the page.
    staleTime: Infinity,
    queryFn: async (): Promise<string | null> => {
      const found = await authedJson<RdidMapping[]>(
        `/api/registry/identifiers?entityType=ecosystem&entityIds=${HUB_ECOSYSTEM_ID}`,
      );
      return found[0]?.rdid ?? null;
    },
  });
}

/** entityId → rdid, for joining a page of users to their addresses. */
export function rdidMapFrom(mappings: RdidMapping[]): Map<string, string> {
  return new Map(mappings.map((m) => [m.entityId, m.rdid]));
}

/**
 * The JOIN, and nothing else: one raw customer row plus its capabilities, its address and its
 * ecosystems becomes one `AdminUserSummary`.
 *
 * Searching, filtering, sorting and paging all used to live here, because the page paginated in
 * the browser and every one of them had to run BEFORE the slice or it would arrange page one
 * rather than the list. Nothing pages now — `useEditableList` narrows and orders the whole list on
 * screen — so this is back to being what its name says, and the ordering hazard is gone with the
 * slice that created it.
 */
export function toUserRows(
  rows: BackendUser[],
  caps: { userId: string; capability: string }[],
  // OPTIONAL and last, so a call site that has only the rows still compiles. Absent, every row's
  // rdid is null and its ecosystems empty — which is what a page rendered before those two
  // lookups land should show.
  rdidByUserId?: Map<string, string>,
  ecosystemsByUserId?: Map<string, UserEcosystem[]>,
): AdminUserSummary[] {
  const capsByUser = new Map<string, string[]>();
  for (const { userId, capability } of caps) {
    const list = capsByUser.get(userId);
    if (list) list.push(capability);
    else capsByUser.set(userId, [capability]);
  }
  return rows.map((u) => ({
    id: u.id,
    email: u.email ?? "",
    name: u.displayName ?? "",
    avatarUrl: u.avatarUrl ?? "",
    capabilities: capsByUser.get(u.id) ?? [],
    createdAt: u.createdAt,
    rdid: rdidByUserId?.get(u.id) ?? null,
    ecosystems: ecosystemsByUserId?.get(u.id) ?? [],
  }));
}

/**
 * The backend's `LIST_LIMIT` from `crud/factory.ts`, restated.
 *
 * Restated rather than fetched because there is nowhere to fetch it from — the generated list
 * route sends a bare array with no envelope, so the cap is invisible in the response. Kept in step
 * by hand; a stale copy here under-reports truncation, which is why the comparison is `>=`.
 */
const CUSTOMERS_LIST_LIMIT = 500;

/** Everything the users page needs from the network, before any of it is arranged. */
export interface AdminUserSource {
  rows: BackendUser[];
  caps: { userId: string; capability: string }[];
  rdidByUserId: Map<string, string>;
  ecosystemsByUserId: Map<string, UserEcosystem[]>;
}

/**
 * The FETCH, keyed by nothing the operator can type.
 *
 * The search box, the role filter, the ecosystem filter and the sort are all applied in the
 * browser, so none of them changes what has to be downloaded — and none of them belongs in the
 * query key. It used to be keyed by page/search/pageSize, which made every keystroke in the search
 * box a fresh miss: two requests plus one per chunk of user ids, against a full list this hook had
 * already fetched and cached under a neighbouring key.
 */
export function useAdminUsersSource() {
  return useQuery({
    queryKey: ["admin", "users", "source"],
    queryFn: async (): Promise<AdminUserSource> => {
      const [rows, caps] = await Promise.all([
        authedJson<BackendUser[]>(
          `/api/customer/customers?ecosystemId=${HUB_ECOSYSTEM_ID}`,
        ),
        authedJson<{ userId: string; capability: string }[]>(
          "/api/auth/capabilities",
        ),
      ]);
      const userIds = rows.map((u) => u.id);
      // Both lookups are keyed on the SAME id list and neither feeds the other, so they run
      // together rather than in series. Both degrade internally, so `Promise.all` here cannot
      // reject and take the rows down with a column.
      const [rdidByUserId, ecosystemsByUserId] = await Promise.all([
        fetchRdids(userIds),
        fetchMemberships(userIds),
      ]);
      return { rows, caps, rdidByUserId, ecosystemsByUserId };
    },
  });
}

/**
 * ONE lookup for the whole set, not one per row. The registry's prefix search cannot answer "what
 * is THIS user's address", so the reverse shape resolves them a batch at a time; a per-row fetch
 * would be a request per visible user against a table with no RLS.
 *
 * Resolved for every user, not just the visible page, because the search matches on the rdid —
 * filtering to the page first would make an address findable only once it was already on screen.
 *
 * ⚠️ CHUNK is bounded by the URL, not by the backend's cap. The backend accepts 500 ids, but 500
 * uuids percent-encode to roughly 19.5 KB of query string and Node's default `maxHeaderSize` is
 * 16 KB — a request that never reaches a handler and fails as a socket error rather than a 431.
 * 200 keeps the line near 8 KB with room for the rest of the URL and the auth header.
 */
async function fetchRdids(userIds: string[]): Promise<Map<string, string>> {
  const CHUNK = 200;
  const mappings: RdidMapping[] = [];
  for (let i = 0; i < userIds.length; i += CHUNK) {
    const ids = userIds.slice(i, i + CHUNK).join(",");
    try {
      mappings.push(
        ...(await authedJson<RdidMapping[]>(
          `/api/registry/identifiers?entityType=customer&entityIds=${encodeURIComponent(ids)}`,
        )),
      );
    } catch (err) {
      // DEGRADE, don't fail. An unguarded await here made the address column's lookup able to
      // take the user list down with it: one chunk erroring left the page with no users at all,
      // reported as a failed query, when the rows themselves had already arrived. A missing
      // address renders as the em dash the column already draws for a user who has none.
      console.warn("admin users: rdid lookup failed for a chunk of users", err);
    }
  }
  return rdidMapFrom(mappings);
}

/**
 * The users page's ONE list, joined — every user, in fetch order.
 *
 * Takes no arguments any more. Narrowing and ordering belong to `useEditableList` on the page,
 * which holds the search text, the role facet, the ecosystem filter and the sort; this hook's job
 * ends at "here is everybody". Recomputed only when the fetch changes, so typing in the search box
 * re-runs the filter and not the join.
 */
export function useAdminUsers() {
  const { data: source, isLoading, isError, error, refetch } = useAdminUsersSource();
  const data = useMemo(
    () =>
      source
        ? toUserRows(source.rows, source.caps, source.rdidByUserId, source.ecosystemsByUserId)
        : undefined,
    [source],
  );
  // A FULL PAGE IS THE ONLY SIGNAL THERE IS. `/customer/customers` is a generated CRUD list and
  // slices at the backend's `LIST_LIMIT` without reporting a total, so "did we get everybody" can
  // only be answered by "did we get exactly the cap". Conservative on purpose: a tenant with
  // exactly 500 users reports possibly-truncated, which costs a strip; the other error costs the
  // operator a person they searched for and concluded does not exist.
  const truncated = source != null && source.rows.length >= CUSTOMERS_LIST_LIMIT;
  return { data, truncated, isLoading, isError, error, refetch };
}

// Grant/revoke a capability via the admin-gated capabilities endpoints. Generic
// CRUD can't do this (POST stamps user_id = caller and granted_at is required),
// so the backend exposes dedicated routes that target any user.

export function useGrantRole() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (data: { userId: string; role?: string; capability?: string }) => {
      const capability = data.capability ?? data.role;
      if (!capability) throw new Error("grant requires a capability or role");
      const body: RequestBody<"/auth/capabilities/grant", "post"> = {
        userId: data.userId,
        capability,
      };
      return authedJson("/api/auth/capabilities/grant", {
        method: "POST",
        body: JSON.stringify(body),
      });
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin", "users"] }),
  });
}

export function useRevokeRole() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ userId, role }: { userId: string; role: string }) => {
      const body: RequestBody<"/auth/capabilities/revoke", "post"> = {
        userId,
        capability: role,
      };
      return authedJson("/api/auth/capabilities/revoke", {
        method: "POST",
        body: JSON.stringify(body),
      });
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin", "users"] }),
  });
}

export function useDeleteUser() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) =>
      authedRequest(`/api/customer/customers/${encodeURIComponent(id)}`, { method: "DELETE" }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin", "users"] }),
  });
}

// ── Feature Flags ────────────────────────────────────────────────────────
//
// Hand-written split-auth routes at `/api/system/feature-flags`
// (system.feature_flags — global, no owner scope; public GET, admin mutations).
// The table is keyed by a serial `id`, which the list response includes, so
// mutations address rows by id directly — `key` can't be the row identity
// because the UI edits it in place.
//
// Types are spec-derived (@agentic-toolkit/adh-api-types) now that the route is documented
// in the OpenAPI surface — a backend schema change surfaces here as a type error.

/** A system.feature_flags row (id, key, description, enabled, createdAt, updatedAt). */
export type FeatureFlag = SuccessBody<"/system/feature-flags", "get">[number];
/** The create body: `key` required, `description`/`enabled` optional. */
export type CreateFlagBody = RequestBody<"/system/feature-flags", "post">;
/** The update body: every field optional (partial patch). */
export type UpdateFlagBody = RequestBody<"/system/feature-flags/{id}", "put">;

export function useAdminFlags() {
  return useQuery({
    queryKey: ["admin", "flags"],
    // ?scope=system: this management view edits rows by serial `id`, so it must read ONLY
    // the site-wide system.feature_flags rows. The public GET default also unions in the hub
    // ecosystem's own product flags (relocated to ecosystem.feature_flags by migration 0123),
    // which carry id 0 and are managed via the per-ecosystem Feature Flags UI, not here.
    queryFn: () => authedJson<FeatureFlag[]>("/api/system/feature-flags?scope=system"),
  });
}

export function useCreateFlag() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (data: CreateFlagBody) =>
      authedJson<FeatureFlag>("/api/system/feature-flags", {
        method: "POST",
        body: JSON.stringify(data),
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin", "flags"] }),
  });
}

export function useUpdateFlag() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, changes }: { id: number; changes: UpdateFlagBody }) =>
      authedJson<FeatureFlag>(`/api/system/feature-flags/${id}`, {
        method: "PUT",
        body: JSON.stringify(changes),
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin", "flags"] }),
  });
}

export function useDeleteFlag() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: number) =>
      authedRequest(`/api/system/feature-flags/${id}`, { method: "DELETE" }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin", "flags"] }),
  });
}

// ── Server Bag ─────────────────────────────────────────────────────────────
//
// Hand-written split-auth routes at `/api/system/server-bag` (system.server_bag —
// global, no owner scope; public GET, admin mutations). The sibling of feature
// flags, but the value is arbitrary JSON instead of a boolean toggle. Rows are
// addressed by their `key` (the table's PK), which — unlike a flag's key — is
// immutable: set once at create, and PUT changes only value/description.

/** A system.server_bag row (key, value, description, createdAt, updatedAt). */
export type ServerBag = SuccessBody<"/system/server-bag", "get">[number];
/** The create body: `key` + `value` required, `description` optional. */
export type CreateBagBody = RequestBody<"/system/server-bag", "post">;
/** The update body: `value`/`description`, both optional (partial patch). */
export type UpdateBagBody = RequestBody<"/system/server-bag/{key}", "put">;

export function useServerBags() {
  return useQuery({
    queryKey: ["admin", "server-bag"],
    queryFn: () => authedJson<ServerBag[]>("/api/system/server-bag"),
  });
}

export function useCreateBag() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (data: CreateBagBody) =>
      authedJson<ServerBag>("/api/system/server-bag", {
        method: "POST",
        body: JSON.stringify(data),
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin", "server-bag"] }),
  });
}

export function useUpdateBag() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ key, changes }: { key: string; changes: UpdateBagBody }) =>
      authedJson<ServerBag>(`/api/system/server-bag/${encodeURIComponent(key)}`, {
        method: "PUT",
        body: JSON.stringify(changes),
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin", "server-bag"] }),
  });
}

export function useDeleteBag() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (key: string) =>
      authedRequest(`/api/system/server-bag/${encodeURIComponent(key)}`, { method: "DELETE" }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin", "server-bag"] }),
  });
}

// ── Access Audit ───────────────────────────────────────────────────────────
//
// Admin-only READ of the access audit trail via `GET /api/system/access-audit`
// (paginated, newest first). Rows are written by the `/access` mutations (workspace
// role & assignment changes); this is the cross-workspace admin view. Not in the
// OpenAPI surface, so the row shape is hand-written here to mirror the backend route
// (backend/src/adh/src/routes/accessAudit.ts).

/** One `team.access_audit` row, with the acting customer's email resolved server-side. */
export interface AccessAuditEvent {
  id: string;
  ownerKind: string;
  ownerId: string;
  actorKind: string;
  actorId: string;
  /** The acting customer's email; null for a persona actor (or an unresolved id). */
  actorEmail: string | null;
  action: string;
  subjectKind: string;
  subjectId: string;
  targetFeature: string;
  targetItemId: string;
  roleId: string;
  before: string;
  after: string;
  at: string;
}

export interface AccessAuditPage {
  items: AccessAuditEvent[];
  page: number;
  pageSize: number;
  total: number;
}

/**
 * The audit trail as a GROWING WINDOW rather than a page at a time.
 *
 * The trail is append-only and unbounded, so it is the one admin list that cannot be fetched
 * whole; `useWindowedList` is what lets it still be filtered and sorted like every other one. The
 * server's own cap is 200 rows a request, so that is the step — see backend accessAudit.ts, whose
 * count saturates deliberately to keep a full scan off the table.
 */
export function useAccessAudit() {
  return useWindowedList<AccessAuditEvent>({
    key: ["admin", "access-audit"],
    getRowId: (e) => e.id,
    pageSize: 200,
    fetchPage: (page, pageSize) =>
      authedJson<AccessAuditPage>(
        `/api/system/access-audit?page=${page}&pageSize=${pageSize}`,
      ),
  });
}

// ── Messaging ────────────────────────────────────────────────────────────
//
// Admin messaging routes are sibling paths under `/api/messaging` gated by
// isAdmin(): `GET /api/messaging/log` (paginated) and `POST /api/messaging/send`.

// Spec-typed (was hand-written and had drifted: the log entry claimed `userId`,
// but the backend returns `ecosystemId`). Names kept so call sites read the same.
export type MessageLogPage = SuccessBody<"/messaging/log", "get">;
export type MessageLogEntry = MessageLogPage["items"][number];
export type AdminSendMessageRequest = RequestBody<"/messaging/send", "post">;

export function useMessageLog(page = 1, pageSize = 20) {
  return useQuery({
    queryKey: ["admin", "messaging", "log", page, pageSize],
    queryFn: () =>
      authedJson<MessageLogPage>(
        `/api/messaging/log?page=${page}&pageSize=${pageSize}`,
      ),
  });
}

export function useSendMessage() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (data: AdminSendMessageRequest) =>
      authedJson<SuccessBody<"/messaging/send", "post">>("/api/messaging/send", {
        method: "POST",
        body: JSON.stringify(data),
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin", "messaging"] }),
  });
}

// ── Feedback ─────────────────────────────────────────────────────────────
//
// Generic CRUD at `/api/content/feedback`, fetched whole. The endpoint has no
// paging parameters — the page and status arguments this hook used to take were
// applied to an already-complete array, which is a pager that hid rows the
// caller had already paid for. The list filters and sorts client-side now.
//
// LIMITATION: content.feedback carries a `user_id` column, so CRUD
// owner-scopes the list to the caller — an admin currently sees only their OWN
// feedback, not every user's. A tenant-wide admin feedback panel needs an
// admin-gated backend endpoint; swap the URL here once it exists.

// Raw `content.feedback` row from generic CRUD — sourced from the
// spec. (The spec resolves the old email/userEmail ambiguity: it's `userEmail`.)
export type FeedbackSubmission = SuccessBody<
  "/content/feedback",
  "get"
>[number];

/** Every submission, newest first. */
export function useFeedback() {
  return useQuery({
    queryKey: ["admin", "feedback"],
    queryFn: async (): Promise<FeedbackSubmission[]> => {
      const rows = await authedJson<FeedbackSubmission[]>(
        "/api/content/feedback",
      );
      // Copied before sorting: the array the fetch returned becomes the query
      // cache's own value, and sorting in place would mutate cached state.
      return [...rows].sort((a, b) =>
        a.createdAt < b.createdAt ? 1 : a.createdAt > b.createdAt ? -1 : 0,
      );
    },
  });
}

export function useUpdateFeedback() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({
      id,
      status,
      adminNotes,
    }: {
      id: string;
      status?: string;
      adminNotes?: string;
    }) => {
      // Only send fields the caller explicitly set, so an absent field is never
      // coerced to null by the partial update. Typed against the spec's update body.
      const body: Partial<RequestBody<"/content/feedback/{id}", "put">> = {};
      if (status !== undefined) body.status = status;
      if (adminNotes !== undefined) body.adminNotes = adminNotes;
      return authedJson(
        `/api/content/feedback/${encodeURIComponent(id)}`,
        {
          method: "PUT",
          body: JSON.stringify(body),
        },
      );
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin", "feedback"] }),
  });
}

// ── Messaging status + templates ─────────────────────────────────────────
export type MessagingStatus = SuccessBody<"/messaging/status", "get">;
export type MessagingTemplateList = SuccessBody<"/messaging/templates", "get">;

export function useMessagingStatus() {
  return useQuery({
    queryKey: ["admin", "messaging", "status"],
    queryFn: () => authedJson<MessagingStatus>("/api/messaging/status"),
  });
}

export function useMessagingTemplates() {
  return useQuery({
    queryKey: ["admin", "messaging", "templates"],
    queryFn: () => authedJson<MessagingTemplateList>("/api/messaging/templates"),
  });
}
