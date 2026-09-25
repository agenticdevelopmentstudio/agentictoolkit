// Teams API client — wired to the real backend (generic CRUD over `team.teams`).
//
// Route: /api/team/teams (list/create), /api/team/teams/{id} (get/update/delete).
// The backend column names differ from the UI's vocabulary, so this client maps
// between them in one place and the components keep using {displayName, identifier}:
//   UI displayName  <->  backend `name`
//   UI identifier   <->  backend `slug`   (a lowercase slug; the user-facing key)
//   UI id           <->  backend `id`     (opaque server-generated UUID)
//
// Scoping: a team's `owner_id` is its owning ecosystem, and every request here names the
// workspace's ecosystem via `?ecosystemId=` (backend crud/policy.ts ECOSYSTEM_PARAM_SCOPED_TABLES).
// `list` then returns ONLY that ecosystem's teams (enforced for admins too), and `create`
// stamps the new team into it — so the Teams feature shows the workspace's teams, not the
// whole tenant. The caller resolves the id with `ecosystemsApi.ecosystemIdForSlug(slug)`.

import { authedJson, authedRequest, rethrowConflict } from "../http";
import { compact, enc, sortByText } from "../client-helpers";
import type { TeamRow, TeamCreateBody, TeamPutBody } from "./wire";

export interface Team {
  id: string;
  displayName: string;
  /** Lowercase slug, unique within the owning ecosystem, e.g. `participants`. */
  identifier: string;
  createdAt: string;
  updatedAt: string;
}

export interface TeamInput {
  displayName: string;
  identifier: string;
}

const BASE = "/api/team/teams";

export function toTeam(r: TeamRow): Team {
  return {
    id: r.id,
    displayName: r.name,
    identifier: r.slug,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
  };
}

/** Returns a human-readable error for an invalid identifier, else null.
 *
 *  A team identifier is a SLUG: lowercase letters and digits, joined by single dots or hyphens.
 *  It used to demand reverse-domain form (`com.example.platform`), which nothing behind it
 *  shares — `team.teams.slug` carries only `UNIQUE (owner_id, slug)`, and every team the backend
 *  provisions is a plain slug (`participants`, `admins`). Renaming a team to `members` was
 *  refused with Save dark, for exactly the shape the server itself writes (Mike, 2026-09-24).
 *  Well-formed dotted names stay legal, but the rule is tighter in one way: every hyphen must sit
 *  between letters or digits, so shapes the old rule let through (`com.acme-`, `com.-acme`,
 *  `com.a--b`) now fail. A team already stored in one of them stays saveable — an editor exempts
 *  an unchanged stored identifier from the format rule — and only a new or changed identifier
 *  must take the new shape. */
export function validateTeamIdentifier(identifier: string): string | null {
  if (!identifier) return "Identifier is required.";
  if (!/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/.test(identifier)) {
    return "Use lowercase letters and digits, joined by dots or hyphens, e.g. platform-team.";
  }
  return null;
}

export const teamsApi = {
  async list(ecosystemId: string): Promise<Team[]> {
    const rows = await authedJson<TeamRow[]>(`${BASE}?ecosystemId=${enc(ecosystemId)}`);
    return sortByText(rows.map(toTeam), (t) => t.displayName);
  },

  async get(id: string): Promise<Team | null> {
    try {
      return toTeam(await authedJson<TeamRow>(`${BASE}/${enc(id)}`));
    } catch {
      // Backend 404s with a thrown error; the UI contract is null-for-missing.
      return null;
    }
  },

  async create(input: TeamInput, ecosystemId: string): Promise<Team> {
    // No pre-read for duplicates: the backend's unique (owner, slug) constraint
    // is the real guard (and a pre-read can't see a soft-deleted row still
    // holding the slug). Catch the 409 → friendly, entity-named message.
    // `?ecosystemId=` stamps the new team into the workspace's ecosystem (its owner),
    // so it lands in — and is visible under — the workspace it was created in.
    try {
      const body: TeamCreateBody = {
        name: input.displayName,
        slug: input.identifier,
      };
      const row = await authedJson<TeamRow>(`${BASE}?ecosystemId=${enc(ecosystemId)}`, {
        method: "POST",
        body: JSON.stringify(body),
      });
      return toTeam(row);
    } catch (err) {
      rethrowConflict(
        err,
        `A team with identifier "${input.identifier}" already exists.`,
      );
    }
  },

  async update(id: string, input: Partial<TeamInput>): Promise<Team> {
    // Generic CRUD PUT accepts a partial body (createInsertSchema().partial()).
    const patch = compact({
      name: input.displayName,
      slug: input.identifier,
    } satisfies TeamPutBody);
    // A slug rename can collide with the unique (owner, slug) index — let the
    // backend be the guard and translate its 409, rather than pre-reading.
    try {
      const row = await authedJson<TeamRow>(`${BASE}/${enc(id)}`, {
        method: "PUT",
        body: JSON.stringify(patch),
      });
      return toTeam(row);
    } catch (err) {
      rethrowConflict(
        err,
        `A team with identifier "${input.identifier}" already exists.`,
      );
    }
  },

  delete(id: string): Promise<void> {
    return authedRequest(`${BASE}/${enc(id)}`, { method: "DELETE" });
  },
};
