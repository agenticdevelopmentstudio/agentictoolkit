// Notes API client — a LENS on the markdown-document surface, not a second surface.
//
// A note IS a markdown document: same head, same version history, same relational
// category + tags. What makes it a note is a content.notes MARKER, which is exactly
// what files it in the owner's `notes` storage bucket (bucket_types maps that bucket
// to content.notes). So this client is `markdownApi` with the marker baked in — `noted`
// on the way out, `note: true` on the way in — and nothing else. The alternative, a
// parallel `/content/notes` route set, would have had to re-derive the version-snapshot
// and classification invariants markdownDocuments.ts already owns, and would have drifted.
//
// (`/content/notes` DOES exist on the backend. It is the device-SYNC marker surface —
// content only, no title/category/tags, no workspace — and it has no web consumer. It is
// deliberately not what this client talks to.)
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

/** A note WITH its body (the detail pane). Structurally a markdown document — the
 *  alias names the role, so a notebook never has to say "research" for its own rows. */
export type Note = ResearchDocument;
/** Note metadata only — no body (the list rows). */
export type NoteSummary = ResearchSummary;
/** The same three axes the research list filters on: free text, category, tag. */
export type NoteFilters = ResearchFilters;
/** One category, with the parent ids that make the set a hierarchy. */
export type NoteCategory = MarkdownCategoryNode;
/** One tag, with the id that addresses it for a rename or a delete. */
export type NoteTag = MarkdownKeywordNode;

/** Create body. `note: true` is this client's to add — a caller cannot forget it and
 *  quietly mint a document that never lands in the notes bucket. */
export type CreateNoteBody = Omit<CreateMarkdownBody, "note">;
export type UpdateNoteBody = UpdateMarkdownBody;

export const notesApi = {
  // `workspace` pins every op to that workspace's owning principal, exactly as it does
  // for research: list returns the notes that principal OWNS, create stamps it as owner.
  // For an ORG workspace this is the whole of the ownership story today — org-SHARED note
  // semantics are still undesigned, so an org note is simply an org-owned document, and
  // the marker carries only its creator stamp.
  /** The workspace's notes (metadata only), most-recently-updated first. */
  list(filters: NoteFilters = {}, opts?: MarkdownScope): Promise<NoteSummary[]> {
    return markdownApi.list(filters, { ...opts, noted: true });
  },

  /** One note WITH its body. */
  get(id: string, opts?: MarkdownScope): Promise<Note> {
    return markdownApi.get(id, opts);
  },

  create(body: CreateNoteBody, opts?: MarkdownScope): Promise<Note> {
    return markdownApi.create({ ...body, note: true }, opts);
  },

  update(id: string, body: UpdateNoteBody, opts?: MarkdownScope): Promise<Note> {
    return markdownApi.update(id, body, opts);
  },

  /** Soft-delete; the backend tombstones the note marker with the document. */
  remove(id: string, opts?: MarkdownScope): Promise<void> {
    return markdownApi.remove(id, opts);
  },

  /** The workspace's category HIERARCHY — the notebook's rail is these rows folded by
   *  `parentIds`. Shared with research's flat category vocabulary by construction: one
   *  owner has one set of categories, seen two ways. A category may sit under several
   *  parents, so the fold draws some of them in more than one place. */
  categories(opts?: MarkdownScope): Promise<NoteCategory[]> {
    return markdownApi.categoryTree(opts);
  },

  /** Create a category, optionally under one or more others. */
  createCategory(
    body: MarkdownCategoryCreateBody,
    opts?: MarkdownScope,
  ): Promise<NoteCategory> {
    return markdownApi.createCategory(body, opts);
  },

  /** The workspace's tag labels (the tag field's autocomplete source). */
  tags(opts?: MarkdownScope): Promise<string[]> {
    return markdownApi.tags(opts);
  },

  /** The same tags WITH their ids — what the tag manager renames and deletes by. */
  tagSet(opts?: MarkdownScope): Promise<NoteTag[]> {
    return markdownApi.tagSet(opts);
  },
};

/** Renaming, filing, unfiling and retiring those categories and tags. Re-exported rather than
 *  folded into `notesApi`: unlike everything above it, the taxonomy is NOT the notebook's —
 *  one owner has one vocabulary spanning notes, research papers and board cards, so a rename
 *  here is a rename there. Keeping it a separate object is what says so at the call site.
 *  (It also takes no `workspace`; see the module comment for why the generic door cannot
 *  use one.) */
export { taxonomyApi } from "../markdown/taxonomy";
