// Local wire types for the Markdown (research documents) and Buckets clients —
// the backend row + request-body shapes the clients read/send (see
// projects/wire.ts for the pattern: these replace the hub's generated
// `SuccessBody<...>` / `RequestBody<...>` from `@agentic-toolkit/adh-api-types`, adh product
// vocabulary a generic data client must not take on). Each interface carries exactly
// the fields the mappers/call sites touch.
// Type-only file.

/* ── Markdown (research documents) ───────────────────────────────────────
 * Backend surface: /content/markdown (see websites/backend/src/routes/
 * markdownDocuments.ts). Narrowed to the fields the hub's ResearchPane /
 * ResearchDetail / PublishSection / ResearchFilters / research-model.ts
 * actually read: id, title, content, category, tags, visibility, publicRoute.
 */

/** A full document, body included (GET /content/markdown/:id, and the
 *  create/update/publish responses). */
export interface MarkdownDocumentRow {
  id: string;
  title: string;
  content: string;
  category?: string | null;
  tags: string[];
  visibility: "private" | "public";
  publicRoute?: string | null;
}

/** Document metadata only — no body (the list/search rows). */
export interface MarkdownDocumentSummaryRow {
  id: string;
  title: string;
  /** Server-derived preview: up to four body lines FOLLOWING the title line, newline-separated.
   *  It is the only body text a list row has — this projection carries no `content` — so a
   *  preview under the title costs nothing extra. OPTIONAL here though the backend always sends
   *  it: a deploy older than this frontend omits it, and a preview is an aid, not a requirement. */
  excerpt?: string;
  category?: string | null;
  tags: string[];
  visibility: "private" | "public";
  publicRoute?: string | null;
}

/** `GET /content/markdown` response — only `items` is read here. */
export interface MarkdownListResponse {
  items: MarkdownDocumentSummaryRow[];
}

/** `POST /content/markdown` body. `author` exists on the backend but no hub
 *  call site ever sets it, so it's omitted. `note: true` files the new document in
 *  the owner's `notes` storage bucket — the ONLY thing that distinguishes a note
 *  from any other markdown document (see the notes client). `doc: true` is the same
 *  gesture for the owner's `docs` bucket, and the two are independent rather than one
 *  `corpus` field because the markers they mint are independent rows: nothing in the
 *  schema stops one text from sitting on both shelves.
 *
 *  There is no `title` here or on the update body, deliberately: the backend DERIVES
 *  it from the content (frontmatter, else the first line), so one document reads the
 *  same way in every client instead of each inventing its own convention. It stays on
 *  the row types below — reading a title is not writing one. */
export interface MarkdownCreateBody {
  content: string;
  category?: string;
  tags?: string[];
  note?: boolean;
  doc?: boolean;
}

/** `PUT /content/markdown/{id}` body — `category` may be explicitly nulled to
 *  clear it (vs. omitted to leave unchanged). */
export interface MarkdownUpdateBody {
  content?: string;
  category?: string | null;
  tags?: string[];
}

/** `POST /content/markdown/{id}/publish` body. */
export interface MarkdownPublishBody {
  route: string;
}

/** `GET /content/markdown/{id}/route-available/{route}` response. `reason` explains a
 *  `false`, and is `'ok'` when available — so a UI can say WHY a slug is refused
 *  (malformed vs. a word the site's routes reserve vs. already used by this author). */
export interface MarkdownRouteAvailability {
  available: boolean;
  reason: "ok" | "invalid" | "reserved" | "taken";
}

/** `{ items: string[] }` — shared shape of the categories/tags list responses. */
export interface StringListBody {
  items: string[];
}

/** One row of `GET /content/markdown/categories`'s `nodes`. `parentIds` is what makes the
 *  category set a DAG rather than a tree: a category may sit under ANY number of parents,
 *  or none — an empty array, never a null sentinel. A consumer folding it into a tree
 *  therefore renders the same category in more than one place, which is the point.
 *
 *  The backend filters out parent ids that are not themselves in `nodes`, and refuses the
 *  edge that would close a cycle, so a fold terminates. A defensive guard is still worth
 *  keeping: this data crosses a network, and a client that hangs is worse than one that
 *  draws a branch twice. */
export interface MarkdownCategoryNode {
  id: string;
  name: string;
  parentIds: string[];
  sortOrder: number;
}

/** One row of `content.category_edges` — a single parent→child link, as the generic CRUD
 *  door returns it. It is what a link REMOVAL addresses: a {@link MarkdownCategoryNode}
 *  carries the parent ids but not the edge ids, so `taxonomyApi.categoryParents` fetches
 *  these at write time. */
export interface MarkdownCategoryEdge {
  id: string;
  parentId: string;
  childId: string;
  sortOrder: number;
}

/** `GET /content/markdown/categories` — the flat NAME list every existing consumer
 *  reads, plus the same set with its structure kept. */
export interface MarkdownCategoryTreeBody {
  items: string[];
  nodes: MarkdownCategoryNode[];
}

/** One row of `GET /content/markdown/tags`'s `nodes` — the tag counterpart of
 *  {@link MarkdownCategoryNode}. The id is what ADDRESSES the tag for a rename or a
 *  delete (`/content/keywords/{id}`); a label cannot, because the links point at the id. */
export interface MarkdownKeywordNode {
  id: string;
  label: string;
}

/** `GET /content/markdown/tags` — the flat LABEL list every existing consumer reads, plus
 *  the same set with each label's row id. */
export interface MarkdownTagSetBody {
  items: string[];
  nodes: MarkdownKeywordNode[];
}

/** `POST /content/markdown/categories` body. Omit `parentIds` (or send an empty array) for
 *  an unfiled category. A name is unique per owner across the WHOLE hierarchy, so this
 *  never RE-FILES a category: re-posting a name is idempotent when every parent it asks
 *  for is already one of that category's parents, and a 409 otherwise. Adding a parent to
 *  a category that already exists is an edge write (`POST /content/category-edges`). */
export interface MarkdownCategoryCreateBody {
  name: string;
  parentIds?: string[];
}

/* ── Buckets (bucket.buckets + bucket.bucket_types) ──────────────────────
 * Backend surface: /bucket/buckets, /bucket/bucket-types. `metadata` is an
 * untyped jsonb column on the generated spec; BucketRow keeps the refined
 * `{ description? }` shape this client actually reads.
 */

/** Backend row for `GET /bucket/buckets` (and a single bucket). */
export interface BucketRow {
  id: string;
  ecosystemId: string;
  name: string;
  /** The rdid leaf — `storage.<eco path>.<slug>`; unique among the bucket's siblings. */
  slug: string;
  kind: string;
  metadata: { description?: string } | null;
  createdAt: string;
  updatedAt: string;
}

/** `POST /bucket/buckets` body. */
export interface BucketCreateBody {
  name: string;
  slug: string;
  metadata: { description?: string };
  ecosystemId?: string;
}

/** `PUT /bucket/buckets/{id}` body. */
export interface BucketPutBody {
  name?: string;
  slug?: string;
  metadata?: { description?: string };
}

/** Backend row for `GET /bucket/bucket-types` (and a single bucket-type). */
export interface BucketTypeRow {
  id: string;
  bucketId: string;
  sqlTableName: string;
  name: string;
}

/** `POST /bucket/bucket-types` body. */
export interface BucketTypeCreateBody {
  bucketId: string;
  ecosystemId: string;
  sqlTableName: string;
  name: string;
}
