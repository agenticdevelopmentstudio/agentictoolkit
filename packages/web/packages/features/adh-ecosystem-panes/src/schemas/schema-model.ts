// Structure-only model for a schema DEFINITION.
//
// A schema definition describes WHICH ADH tables it contains and what they're
// called — pure structure, no permissions. Permissions are a separate concern
// applied per-application when an app adds a schema (see
// applications/permission-model.ts). This split is deliberate: the same schema
// definition can be granted to many applications, each with its own permission
// overlay.
//
// Persisted via the backend `bucket.schemas` + `bucket.schema_tables`
// tables (see api/schemas.ts). Each table's `type` is one of the
// `content`/`personal` table types the DB exposes (see available-types.ts).

/**
 * The cache key the ecosystem's bucket catalog lives under — ONE entry, shared by the Buckets pane
 * that edits it and by every reader that only wants to pick from it (an application's Schema
 * Permissions section).
 *
 * A function, and exported, because the sharing IS the behaviour: `useResourceList` entries are
 * identified by this string, so a reader that spells its own key gets a SECOND copy of the same
 * catalog — one the Buckets pane's create/delete re-read never touches, which then serves a bucket
 * list missing the bucket just made for up to the full `staleTime` and lingers for the whole
 * `gcTime` after that. Two literals in two files are one edit away from being that second copy;
 * one function cannot be.
 *
 * Every caller must pair it with the matching fetch — `schemasApi.list(ecosystemId)` for the same
 * id. The id is part of the key because `list` FILTERS by it client-side: the unscoped call answers
 * every bucket the caller can see across ecosystems, which is a different list, not a fresher one.
 */
export function bucketsCacheKey(ecosystemId: string | undefined): string {
  return `ecosystem:${ecosystemId ?? ""}:buckets`;
}

/** One ADH table within a schema definition. Structure only. */
export interface SchemaTable {
  /** Stable client id for React keys / cross-referencing grants. */
  id: string;
  /** User-defined slug, e.g. "contacts" — no spaces. */
  name: string;
  /** The underlying sql-table type id (e.g. "content.contacts"). */
  type: string;
}

export interface SchemaDefinition {
  id: string;
  /** Unique display name. */
  name: string;
  /** The rdid leaf — unique among siblings; editing it moves `id`. */
  slug: string;
  description: string;
  tables: SchemaTable[];
  ecosystemId: string;
  /** `default` = the auto-seeded "all available tables" bucket every ecosystem gets (undeletable —
   *  the backend 409s a non-custom delete); `custom` = a developer-created bucket. */
  kind: string;
  createdAt: string;
  updatedAt: string;
}

export interface SchemaDefinitionInput {
  name: string;
  slug: string;
  description: string;
  tables: SchemaTable[];
}

/** Slugify a table name to the allowed shape (lowercase, underscores, no spaces). */
export function slugifyTableName(raw: string): string {
  return raw
    .toLowerCase()
    .replace(/[^a-z0-9_]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

/**
 * A bucket's slug derived from its display name — the same derivation the backend backfilled every
 * existing bucket with (`addressSegment(name)`), so a name typed today yields the address an older
 * bucket of that name already has. 64 is the column's width; the trim runs after the cut so a word
 * split at the edge leaves no trailing hyphen.
 */
export function slugifyBucketName(raw: string): string {
  return raw
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 64)
    .replace(/-+$/, "");
}

export function newSchemaTableId(): string {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) {
    return `tbl_${crypto.randomUUID()}`;
  }
  return `tbl_${Math.floor(performance.now() * 1000).toString(36)}`;
}

export function newSchemaTable(type: string, name = ""): SchemaTable {
  return { id: newSchemaTableId(), name, type };
}
