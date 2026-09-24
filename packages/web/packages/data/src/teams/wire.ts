// Local wire types for the Teams clients — the backend row + request-body
// shapes the clients read/send (see projects/wire.ts for the pattern: these
// replace the hub's generated `SuccessBody<...>` / `RequestBody<...>` from
// `@agentic-toolkit/adh-api-types`, adh product vocabulary a
// generic data client must not take on). Each
// interface carries exactly the fields the mappers and call sites touch.
// Type-only file.

/** Backend row for `GET /team/teams` (and a single team). */
export interface TeamRow {
  id: string;
  name: string;
  /** Lowercase slug, unique within the owning ecosystem, e.g. `participants`. */
  slug: string;
  createdAt: string;
  updatedAt: string;
}

/** `POST /team/teams` body. */
export interface TeamCreateBody {
  name: string;
  slug: string;
}

/** `PUT /team/teams/{id}` body — generic CRUD PUT accepts a partial body
 *  (createInsertSchema().partial()). */
export interface TeamPutBody {
  name?: string;
  slug?: string;
}
