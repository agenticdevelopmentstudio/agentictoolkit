// Ecosystem users client — the end-customers who authenticate to an ecosystem.
// Wired to the real backend generic CRUD over `customer.customers`
// (/api/customer/customers). `customer.customers` is the platform's end-customer
// identity / login store, scoped to an ecosystem by `ecosystemId`.
//
// Field map (UI <-> backend row):
//   email       <->  email          displayName <-> displayName
//   externalId  <->  externalId     slug        <-> slug (a short handle)
//   avatarUrl   <->  avatarUrl      ecosystemId <-> ecosystemId
//
// `tokenVersion` (session-invalidation counter) and `deletedAt` (soft delete) are
// internal auth bookkeeping and intentionally not surfaced on the form.

import type { RequestBody, SuccessBody } from "@agentic-toolkit/adh-api-types";
import { authedJson, authedRequest } from "@agentic-toolkit/auth/client";
import { compact, enc, scopeByOwner, sortByText } from "@agentic-toolkit/data";

export interface EcosystemUser {
  id: string;
  ecosystemId: string;
  email: string;
  displayName: string;
  externalId: string;
  slug: string;
  avatarUrl: string;
  createdAt: string;
  updatedAt: string;
}

export interface EcosystemUserInput {
  email: string;
  displayName: string;
  externalId: string;
  slug: string;
  avatarUrl: string;
}

const BASE = "/api/customer/customers";

/** The backend `customer.customers` row, sourced from the OpenAPI spec. */
type CustomerRow = SuccessBody<"/customer/customers", "get">[number];

export function toUser(r: CustomerRow): EcosystemUser {
  return {
    id: r.id,
    ecosystemId: r.ecosystemId,
    email: r.email ?? "",
    displayName: r.displayName ?? "",
    externalId: r.externalId ?? "",
    slug: r.slug ?? "",
    avatarUrl: r.avatarUrl ?? "",
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
  };
}

export const ecosystemUsersApi = {
  async list(ecosystemId?: string): Promise<EcosystemUser[]> {
    // Generic-CRUD list is unscoped, so narrow to the active ecosystem here.
    const rows = await authedJson<CustomerRow[]>(BASE);
    return sortByText(
      scopeByOwner(rows, ecosystemId, (r) => r.ecosystemId).map(toUser),
      (u) => u.displayName || u.email,
    );
  },

  async get(id: string): Promise<EcosystemUser | null> {
    try {
      return toUser(await authedJson<CustomerRow>(`${BASE}/${enc(id)}`));
    } catch {
      // Backend 404s with a thrown error; the UI contract is null-for-missing.
      return null;
    }
  },

  async create(input: EcosystemUserInput, ecosystemId: string): Promise<EcosystemUser> {
    // Fail fast rather than silently mis-scoping: an absent ecosystemId would let
    // the backend assign the new customer to the caller's own ecosystem.
    if (!ecosystemId) {
      throw new Error("Cannot create a user without a selected ecosystem.");
    }
    const body: RequestBody<"/customer/customers", "post"> = {
      ecosystemId,
      email: input.email || undefined,
      displayName: input.displayName || undefined,
      externalId: input.externalId || undefined,
      // Required: the backend refuses a create with no handle (it has no default to fall
      // back on), so it is sent as given — `userValidate` has already refused an empty one.
      slug: input.slug,
      avatarUrl: input.avatarUrl || undefined,
    };
    const row = await authedJson<CustomerRow>(BASE, {
      method: "POST",
      body: JSON.stringify(compact(body)),
    });
    return toUser(row);
  },

  async update(id: string, input: Partial<EcosystemUserInput>): Promise<EcosystemUser> {
    const fields: Partial<RequestBody<"/customer/customers/{id}", "put">> = {
      email: input.email,
      displayName: input.displayName,
      externalId: input.externalId,
      slug: input.slug,
      avatarUrl: input.avatarUrl,
    };
    const row = await authedJson<CustomerRow>(`${BASE}/${enc(id)}`, {
      method: "PUT",
      body: JSON.stringify(compact(fields)),
    });
    return toUser(row);
  },

  delete(id: string): Promise<void> {
    return authedRequest(`${BASE}/${enc(id)}`, { method: "DELETE" });
  },
};
