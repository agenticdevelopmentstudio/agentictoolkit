// Docs API client — the third LENS on the markdown-document surface, beside notes.
//
// A doc IS a markdown document: same head, same version history, same relational category
// + tags. What makes it a doc is a content.docs MARKER, which files it in the owner's
// `docs` storage bucket (bucket_types maps that bucket to content.docs). So this client is
// `markdownApi` with the marker baked in — `doc` on the way out and on the way in — and
// nothing else, for the same reason notes.ts is: a parallel route set would have to
// re-derive the version-snapshot and classification invariants markdownDocuments.ts
// already owns, and would drift from them.
//
// What separates a doc from a note is the SHELF, not the shape. A note is something
// jotted; a doc is something written down that is not composed enough to be a paper —
// and, from v2, an uploaded file of any kind. The upload is why docs got a corpus and a
// bucket of their own rather than a second view of the notes rows: a file needs somewhere
// to land, and the bucket is that somewhere.
import { markdownApi, type MarkdownScope } from "../markdown/markdown";
import type {
  ResearchDocument,
  ResearchSummary,
  ResearchFilters,
  CreateMarkdownBody,
  UpdateMarkdownBody,
} from "../markdown/markdown";
import type {
  MarkdownCategoryNode,
  MarkdownCategoryCreateBody,
  MarkdownKeywordNode,
} from "../markdown/wire";

/** A doc WITH its body (the detail pane). Structurally a markdown document — the alias
 *  names the role, so a docs surface never has to say "research" for its own rows. */
export type Doc = ResearchDocument;
/** Doc metadata only — no body (the list rows). */
export type DocSummary = ResearchSummary;
/** The same three axes every markdown list filters on: free text, category, tag. */
export type DocFilters = ResearchFilters;
/** One category, with the parent ids that make the set a hierarchy. */
export type DocCategory = MarkdownCategoryNode;
/** One tag, with the id that addresses it for a rename or a delete. */
export type DocTag = MarkdownKeywordNode;

/** Create body. `doc: true` is this client's to add — a caller cannot forget it and
 *  quietly mint a document that never lands in the docs bucket. */
export type CreateDocBody = Omit<CreateMarkdownBody, "doc">;
export type UpdateDocBody = UpdateMarkdownBody;

export const docsApi = {
  // `workspace` pins every op to that workspace's owning principal, exactly as it does for
  // notes and research: list returns the docs that principal OWNS, create stamps it owner.
  /** The workspace's docs (metadata only), most-recently-updated first. */
  list(filters: DocFilters = {}, opts?: MarkdownScope): Promise<DocSummary[]> {
    return markdownApi.list(filters, { ...opts, doc: true });
  },

  /** One doc WITH its body. */
  get(id: string, opts?: MarkdownScope): Promise<Doc> {
    return markdownApi.get(id, opts);
  },

  create(body: CreateDocBody, opts?: MarkdownScope): Promise<Doc> {
    return markdownApi.create({ ...body, doc: true }, opts);
  },

  update(id: string, body: UpdateDocBody, opts?: MarkdownScope): Promise<Doc> {
    return markdownApi.update(id, body, opts);
  },

  /** Soft-delete; the backend tombstones the doc marker with the document. */
  remove(id: string, opts?: MarkdownScope): Promise<void> {
    return markdownApi.remove(id, opts);
  },

  /** The workspace's category HIERARCHY — the docs rail is these rows folded by
   *  `parentIds`. Shared with notes and research by construction: one owner has one set of
   *  categories, seen three ways. A category may sit under several parents, so the fold
   *  draws some of them in more than one place. */
  categories(opts?: MarkdownScope): Promise<DocCategory[]> {
    return markdownApi.categoryTree(opts);
  },

  /** Create a category, optionally under one or more others. */
  createCategory(
    body: MarkdownCategoryCreateBody,
    opts?: MarkdownScope,
  ): Promise<DocCategory> {
    return markdownApi.createCategory(body, opts);
  },

  /** The workspace's tag labels (the tag field's autocomplete source). */
  tags(opts?: MarkdownScope): Promise<string[]> {
    return markdownApi.tags(opts);
  },

  /** The same tags WITH their ids — what the tag manager renames and deletes by. */
  tagSet(opts?: MarkdownScope): Promise<DocTag[]> {
    return markdownApi.tagSet(opts);
  },
};

/** Renaming, filing, unfiling and retiring those categories and tags. Re-exported rather
 *  than folded into `docsApi` for the reason notes.ts gives: the taxonomy is not any one
 *  corpus's — one owner has one vocabulary spanning docs, notes and research papers, so a
 *  rename here is a rename there. */
export { taxonomyApi } from "../markdown/taxonomy";
