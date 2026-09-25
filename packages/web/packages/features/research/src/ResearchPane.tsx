"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Globe } from "lucide-react";

import { reportUnexpectedAuthError, useAuth } from "@agentic-toolkit/auth";
import { deriveDocumentTitle, setFrontmatterTitle } from "@agenticdevelopertoolkit/markdown";
import { AlertModal } from "@agenticdevelopertoolkit/ui/components/alert-modal";
import type { TopicDetailItem, TopicLevel } from "@agenticdevelopertoolkit/ui/blocks";
import { Field } from "@agenticdevelopertoolkit/ui/blocks";
import {
  DocumentIdentityField,
  useSlugAvailability,
} from "@agenticdevelopertoolkit/ui/blocks/document-identity-field";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { useDualModeSelection } from "@agenticdevelopertoolkit/ui/hooks/useDualModeSelection";
import { slugify } from "@agenticdevelopertoolkit/ui/lib/slug";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import {
  StackLevels,
  useRailExitGuard as useWorkspaceExitGuard,
  useDetailTitle,
  MasterDetailLeaf,
  useRecordAffordance,
  CreateResourceDialog,
  useResourceItem,
  type MasterDetailActions,
} from "@agentic-toolkit/resource";
import {
  revalidateResources,
  useResourceItemPrefetch,
  useResourceItemWriter,
  useResourceList,
} from "@agentic-toolkit/data";
import {
  markdownApi,
  type MarkdownCategoryNode,
  type MarkdownRouteAvailability,
  type ResearchDocument,
  type ResearchSummary,
} from "@agentic-toolkit/data/markdown";
import { resolveListCategory, useCategoryLevels, UNCATEGORIZED_SLUG } from "@agentic-toolkit/categories";
import {
  categoriesOf,
  researchDiffers,
  researchNormalize,
  researchToInput,
  researchValidate,
  routeFromTitle,
  tagsOf,
  toCreateBody,
  toUpdateBody,
  type ResearchInput,
} from "./research-model";
import { ResearchDetail } from "./ResearchDetail";
import { ResearchFilters, type FilterState } from "./ResearchFilters";
import { PublishSection } from "./PublishSection";

const EMPTY_FILTERS: FilterState = { q: "", category: "", tag: "" };
// Module scope: a fresh `[]` literal in a default param or as a `??` fallback would hand out a
// new array identity every render, which is exactly what `useCategoryLevels`' `chainSlugs` dep
// (joined internally, but still a prop the caller must not churn) and this pane's own local-state
// fallback below must not do.
const EMPTY_SLUGS: string[] = [];

/** The backend's reason codes, as something to read. `ok` never reaches a message. Typed
 *  against the wire union (`MarkdownRouteAvailability["reason"]`) rather than a hand-rolled
 *  string type, so a new backend reason is a compile error here rather than a silently blank
 *  message. */
const SLUG_REASON: Record<MarkdownRouteAvailability["reason"], string | undefined> = {
  ok: undefined,
  invalid: "Use lowercase letters, numbers, dashes or underscores.",
  reserved: "That word is reserved by this site.",
  taken: "Another of your papers already uses that slug.",
};

/** The create modal's draft (HTD recipe `must-create-in-modal` +
 *  `must-scope-create-modal-to-placement`): the title, plus the category that PLACES it.
 *
 *  Only what PLACES the record belongs here — the modal is not the editor. The title is a
 *  required field of its own (rather than a body left for the editor) because it is the
 *  document's NAME — its first line — so a create with no title would mint an "Untitled" row
 *  the user then has to go and find. `create` synthesizes the minimal body from it. */
interface ResearchPlacement {
  title: string;
  category: string;
}

function errorText(err: unknown, fallback: string): string {
  return err instanceof Error ? err.message : fallback;
}

/** Value equality for the filter triple. A filter typed and then retyped back to what it already
 *  was must keep the SAME applied object: a new fetcher identity is `useResourceList`'s refetch
 *  signal, and that one would spend a request to arrive back at rows already on screen. */
function sameFilters(a: FilterState, b: FilterState): boolean {
  return a.q === b.q && a.category === b.category && a.tag === b.tag;
}

/** Whether saving with `slug` as the identity field's current value would move this document's
 *  published route. ONE expression, used at BOTH the places that need to agree on it: the
 *  save-time GUARD in `onSave` (before the write, deciding whether an unavailable slug should
 *  block Save at all — a draft's slug writes nothing, so it never needs to) and the write
 *  CONDITION right after the update response comes back (deciding whether to follow up with a
 *  publish call). A round of review found the guard and the write had drifted — the guard
 *  omitted the `slug !== doc.publicRoute` term — because each spelled the same rule out
 *  separately, 30 lines apart. Naming it once is what keeps that from happening again; the two
 *  call sites differ only in WHICH document they pass in (the cached `selectedDoc` for the
 *  guard, the fresh `updated` response for the write), not in the rule itself. */
function writesPublicRoute(
  doc: Pick<ResearchDocument, "visibility" | "publicRoute"> | null | undefined,
  slug: string,
): boolean {
  return doc?.visibility === "public" && Boolean(slug) && slug !== doc?.publicRoute;
}

/**
 * The /research workspace: a master/detail surface over the signed-in user's
 * markdown research documents. This pane owns the data (list/search + the full
 * document loaded on selection) and the form state (selection, draft, dirty/
 * validity, save/delete); the fields-only editor, the publish concern, and the
 * filters are their own components, and the two-pane layout + toolbar are the
 * shared EditorSection block.
 *
 * DUAL SELECTION MODE (mirrors PersonasSection): pass `urlSelection` and the open document lives in
 * the URL + is deep-linkable — the `/<slug>/research` route wires this via {@link ResearchFeature}.
 * Omit it and selection is internal state, so opening a document happens IN PLACE without
 * navigating away. NOTHING mounts that second mode today: the hub's `renderFeaturePanel("research")`
 * arm (`sites/hub/src/components/workspace/feature-panels.tsx`) is unreached — `research` is in no
 * ecosystem or product topic list and is off the hub's workspace feature rail — so this pane is a
 * LEVEL-0 surface in practice. Its search, filters and create ride the Documents level's own
 * toolbar, so an embedded mount would carry them with the list rather than into a host's chrome.
 *
 * CATEGORY CHAIN is the SAME dual-mode idea, one prop pair rather than one object: pass
 * `onSelectCategory` (with `categorySlugs`) and the rail's chain lives in the URL, exactly as
 * `ResearchFeature` wires it. Omit `onSelectCategory` and the chain is internal state, so an
 * embedded mount still gets the shared hierarchical rail with no router underneath it. Unlike
 * `urlSelection`, these are top-level props rather than one object — matching how
 * `NotebookPane` takes them, since a future URL-driven-chain-but-internal-doc combination (or
 * vice versa) is not a shape either pane needs to rule out by construction.
 */
export function ResearchPane({
  urlSelection,
  categorySlugs: categorySlugsProp,
  onSelectCategory: onSelectCategoryProp,
  userSlug: userSlugProp,
  workspaceSlug,
}: {
  urlSelection?: {
    /** The open document's id, from the URL path segment (`/<slug>/research/<docId>`). */
    docId?: string;
    /** Route to a document (null clears back to the list). */
    onSelectDoc: (id: string | null) => void;
  };
  /** The selected category chain from the URL, outermost first. Read only when
   *  `onSelectCategory` is also passed — see the class doc above. */
  categorySlugs?: string[];
  /** Navigate to a category chain (an empty array is the whole list). Its PRESENCE, not
   *  `categorySlugs`', is what flips this pane into URL-driven-chain mode — mirrors
   *  `urlSelection`, whose own presence is the same kind of switch. */
  onSelectCategory?: (slugs: string[]) => void;
  /** Host OVERRIDE for the public-URL slug to publish under. Normally unnecessary: the
   *  signed-in user's backend-persisted profile slug (typed on the auth user shape, returned
   *  by GET /auth/me) is used directly below; a host only passes this to publish under a
   *  different namespace. */
  userSlug?: string;
  /** Pins every op to the WORKSPACE'S owning principal (backend `?workspace=`), so an org
   *  workspace shows the ORG'S documents and creates org-owned ones. Omitted: the caller's. */
  workspaceSlug?: string;
} = {}) {
  const { user } = useAuth();
  // The slug is backend-persisted (Settings → Profile writes it via PATCH /auth/me) and rides
  // the auth user, so it is authoritative here; the prop is an explicit host override, and a
  // slugified display name is the last-resort fallback for users who predate profile slugs.
  const userSlug = userSlugProp ?? user?.slug ?? slugify(user?.name ?? "");

  // Dual-mode chain, hand-rolled rather than via `useDualModeSelection` (that hook is typed for
  // a single string id, not a string array): URL-driven when a host passes `onSelectCategory`,
  // else internal state, so the pane still has a working rail with no router beneath it.
  const [localCategorySlugs, setLocalCategorySlugs] = useState<string[]>(EMPTY_SLUGS);
  const categorySlugs = onSelectCategoryProp ? (categorySlugsProp ?? EMPTY_SLUGS) : localCategorySlugs;
  const onSelectCategory = onSelectCategoryProp ?? setLocalCategorySlugs;

  // ── Data ────────────────────────────────────────────────────────────────
  // Two filter values, not one. `filters` is what the inputs show and changes on every keystroke;
  // `applied` is what the list READS, and lags it by the debounce. The debounce used to sit on the
  // request; it now sits on the query key, which is the same 200ms of typing without a request —
  // and the key is what lets a filter set returned to paint from cache instead of re-reading.
  const [filters, setFilters] = useState<FilterState>(EMPTY_FILTERS);
  const [applied, setApplied] = useState<FilterState>(EMPTY_FILTERS);
  useEffect(() => {
    const id = setTimeout(
      () => setApplied((prev) => (sameFilters(prev, filters) ? prev : filters)),
      200,
    );
    return () => clearTimeout(id);
  }, [filters]);

  // The account's category TREE — the shared hierarchical rail's rows. Distinct from
  // `categoryOptions` below (a flat name list, `markdownApi.categories()`, the editor's
  // autocomplete source) and from the Documents toolbar gear's category filter, whose options
  // come from `universe`: the rail SCOPES which part of the list you are standing in, the gear's
  // filter NARROWS within it, and they are not the same axis (see `plan` below).
  const loadCategoryTree = useCallback(async () => {
    try {
      return await markdownApi.categoryTree({ workspace: workspaceSlug });
    } catch (err) {
      reportUnexpectedAuthError(err, { feature: "research-pane", step: "taxonomy" });
      throw err instanceof Error ? err : new Error("Failed to load categories.");
    }
  }, [workspaceSlug]);
  const {
    items: categoryRows,
    error: categoryTreeError,
    reload: reloadCategoryTree,
  } = useResourceList<MarkdownCategoryNode>(
    `research:${workspaceSlug ?? ""}:category-tree`,
    loadCategoryTree,
    { reportErrors: false },
  );

  // `refresh` is keyed on the list scope THIS hook computes (via `plan`, below), so it cannot be
  // declared above the `useCategoryLevels` call that needs it as `onChanged`. The hook only ever
  // invokes `onChanged` from an event, by which time the ref is filled — and the indirection
  // keeps the identity stable, which a hook dependency array needs and a function redeclared
  // each render does not have. Mirrors NotebookPane's identical `refreshRef` dance.
  const refreshRef = useRef<() => void | Promise<void>>(() => {});
  const onCategoriesChanged = useCallback(() => refreshRef.current(), []);

  // The category levels are the shared ones — the same rail the notebook draws, from
  // @agentic-toolkit/categories. This pane contributes the documents level below them. The RAW
  // URL slugs go in; the resolved chain comes back out, and everything the pane still needs
  // about where it is standing is derived from that rather than re-resolved here.
  const {
    levels: categoryLevels,
    scope,
    chain,
    dialogs: categoryDialogs,
  } = useCategoryLevels({
    rows: categoryRows,
    error: categoryTreeError,
    chainSlugs: categorySlugs,
    onSelectChain: onSelectCategory,
    onChanged: onCategoriesChanged,
    itemNoun: "documents",
    idPrefix: "research",
    workspaceSlug,
  });

  const uncategorized = scope.kind === "uncategorized";
  const activeCategory = chain[chain.length - 1] ?? null;
  const activeCategoryName = activeCategory?.name ?? "";

  // What the rail's placement and the gear's category filter jointly ask for. Derived here rather
  // than inside the fetcher so the KEY can be built from the same answer: the plan is what
  // decides whether there is a request at all, and two different scopes must never share a key.
  // `scope`'s identity is NOT stable across every render that leaves it semantically unchanged —
  // see the identical note on NotebookPane's own `plan` memo for why this is keyed on the
  // primitives that fully determine the scope (`uncategorized`, `activeCategoryName`,
  // `applied.category`) rather than on `scope` directly.
  const plan = useMemo(
    () => resolveListCategory(scope, applied.category),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [uncategorized, activeCategoryName, applied.category],
  );

  // Every read here reports under THIS pane's step and rethrows, which is why each call site
  // passes `reportErrors: false` — one failure reported twice, under two contexts, is worse than
  // one.
  const loadDocs = useCallback(async () => {
    // The rail and the filter name two different categories: nothing can match, so there is
    // nothing worth asking the backend. An empty list, not a skipped read — under a cache the
    // rows ARE the answer, and "no request" still has to produce one.
    if (plan.empty) return [];
    try {
      // `category` is an EXACT name match on the backend, which is what makes a category hold
      // only its own documents; the subcategories are their own levels.
      const rows = await markdownApi.list(
        { q: applied.q, tag: applied.tag, category: plan.query },
        { workspace: workspaceSlug },
      );
      return plan.uncategorizedOnly ? rows.filter((row) => !row.category) : rows;
    } catch (err) {
      reportUnexpectedAuthError(err, { feature: "research-pane", step: "list" });
      throw err instanceof Error ? err : new Error("Failed to load documents.");
    }
  }, [plan, applied.q, applied.tag, workspaceSlug]);

  // Keyed by the rail's SCOPE as well as the filters and the workspace: walking into a category
  // and back out is two keys, each already read, so the second walk is a repaint rather than a
  // round trip. The scope has to be spelled out in the key — "uncategorized" is a scope no
  // category name can express, and an unfiltered list under a named category is not the whole
  // list.
  const scopeKey = uncategorized ? UNCATEGORIZED_SLUG : activeCategoryName;
  const listPrefix = `research:${workspaceSlug ?? ""}:list:`;
  const listKey = `${listPrefix}${scopeKey}|${applied.q}|${applied.category}|${applied.tag}`;
  const {
    items: docs,
    error: listError,
    reload: reloadDocs,
  } = useResourceList<ResearchSummary>(listKey, loadDocs, { reportErrors: false });

  const loadUniverse = useCallback(async () => {
    try {
      return await markdownApi.list({}, { workspace: workspaceSlug });
    } catch (err) {
      reportUnexpectedAuthError(err, { feature: "research-pane", step: "universe" });
      throw err;
    }
  }, [workspaceSlug]);

  // The unfiltered universe, only for the filter dropdown options — so narrowing
  // the list (which refetches `docs`) never empties its own category/tag menus.
  const { items: universeDocs, reload: reloadUniverse } = useResourceList<ResearchSummary>(
    `research:${workspaceSlug ?? ""}:universe`,
    loadUniverse,
    { reportErrors: false },
  );
  const universe = universeDocs ?? [];

  // The account's existing categories + tags — the editor's autocomplete/browse source
  // (distinct from the Documents toolbar gear's filter menus, whose options come from `universe`
  // above). Refetched on save so a freshly-coined category/tag appears as a suggestion next time.
  //
  // Workspace-scoped like the documents themselves: the backend scopes the category/tag
  // vocabulary to the same owner it scopes the docs to, so omitting the workspace here
  // suggested the CALLER's own labels while the list showed the ORG's documents.
  //
  // Two lists rather than the one `Promise.all` this replaced: they are two routes, they cache
  // separately, and the pair fetches in parallel either way.
  const loadCategories = useCallback(async () => {
    try {
      return await markdownApi.categories({ workspace: workspaceSlug });
    } catch (err) {
      reportUnexpectedAuthError(err, { feature: "research-pane", step: "taxonomy" });
      throw err;
    }
  }, [workspaceSlug]);
  const loadTags = useCallback(async () => {
    try {
      return await markdownApi.tags({ workspace: workspaceSlug });
    } catch (err) {
      reportUnexpectedAuthError(err, { feature: "research-pane", step: "taxonomy" });
      throw err;
    }
  }, [workspaceSlug]);

  const { items: categoryOptions, reload: reloadCategories } = useResourceList<string>(
    `research:${workspaceSlug ?? ""}:categories`,
    loadCategories,
    { reportErrors: false },
  );
  const { items: tagOptions, reload: reloadTags } = useResourceList<string>(
    `research:${workspaceSlug ?? ""}:tags`,
    loadTags,
    { reportErrors: false },
  );
  const accountCategories = categoryOptions ?? [];
  const accountTags = tagOptions ?? [];

  // Swallowing, and it has to: every caller re-reads AFTER its own write succeeded, and their
  // catch blocks say "Failed to save." / "Failed to delete.". A failed re-read is neither. The
  // list's failure still reaches the screen, as `listError`.
  const refresh = useCallback(() => {
    // The SIBLING filter keys first. `reloadDocs` re-reads the one filter set on screen, but a save
    // changes the very fields the other keys are built from — a document's category and its tags —
    // so every other cached filter set for this workspace is now potentially wrong. Without this,
    // clearing a search back to a filter visited earlier repaints the document under labels it no
    // longer has, from cache, with no read. Unmounted lists are only marked stale, so this issues
    // no request; the key on screen is excluded because `reloadDocs` already re-reads it and
    // invalidating it too would cancel that read and start a second one.
    revalidateResources((key) => key !== listKey && key.startsWith(listPrefix));
    return Promise.all([
      reloadDocs(),
      reloadUniverse(),
      reloadCategories(),
      reloadTags(),
      reloadCategoryTree(),
    ])
      .then(() => undefined)
      .catch(() => {});
  }, [
    reloadDocs,
    reloadUniverse,
    reloadCategories,
    reloadTags,
    reloadCategoryTree,
    listKey,
    listPrefix,
  ]);
  refreshRef.current = refresh;

  // ── Selection + draft ─────────────────────────────────────────────────────
  // Dual-mode selection: the open document's id lives in the URL (URL-driven, deep-linkable) when
  // `urlSelection` is passed, else internal state (embedded).
  const { selectedId, select: openDoc } = useDualModeSelection(
    urlSelection && { selectedId: urlSelection.docId ?? null, onSelect: urlSelection.onSelectDoc },
  );
  // Creating a document is a MODAL over the stack, never a blank leaf (HTD recipe
  // `must-create-in-modal`): the `+` opens it, and on save the created doc is selected so its
  // full editor (body, publish) opens.
  const [newOpen, setNewOpen] = useState(false);
  const [saving, setSaving] = useState(false);
  // A failed save or delete belongs to the DOCUMENT it was raised on, so it is stored with that
  // id and read back only while that document is still open. The loader this pane used to own
  // cleared the message on every selection change; deriving it does the same thing for the URL
  // path too (Back, a deep link), which never ran through a click handler that could clear it.
  const [raisedError, setRaisedError] = useState<{ id: string | null; text: string } | null>(null);
  const [pendingDelete, setPendingDelete] = useState(false);
  const [deleting, setDeleting] = useState(false);
  // Re-entrancy latch for `onSave`. The `saving` STATE can't do this job: it is a render value,
  // so two activations inside a single commit (a double-click on Save before React paints the
  // disabled button) both read the pre-save `false` and both PUT. A ref flips synchronously on
  // the way in and clears in `finally`.
  const savingRef = useRef(false);

  // ── The open document ─────────────────────────────────────────────────────
  // Cached per WORKSPACE, because `?workspace=` decides which principal's copy a read returns —
  // one key for a document id would let an org workspace paint the caller's own copy of it.
  const docCacheKey = `research:${workspaceSlug ?? ""}`;
  const loadDoc = useCallback(
    (id: string) => markdownApi.get(id, { workspace: workspaceSlug }),
    [workspaceSlug],
  );
  // Replaces the loader this pane used to hand-roll: a `loadBody` + an out-of-order token + a
  // "which id is the form bound to" ref + a URL-sync effect that had to remember to skip itself.
  // All four existed to answer "is what's on screen the right document"; the cache answers it, and
  // a document opened a second time now paints from memory instead of from a GET.
  //
  // No `seedFrom`: a list row is a ResearchSummary, which carries no body, so there is no partial
  // ResearchDocument to paint. And no `absent`: this list is FILTERED, so a document missing from
  // it has merely been narrowed away — announcing that as a deletion would be a lie the user
  // cannot argue with. The 404 is the honest signal, and it is the one that fires on a real one.
  const {
    item: selectedDoc,
    isSettled,
    isFetching: fetchingDoc,
    error: docError,
  } = useResourceItem<ResearchDocument>(docCacheKey, selectedId, loadDoc);
  const prefetchDoc = useResourceItemPrefetch(docCacheKey, loadDoc);
  const writeDoc = useResourceItemWriter<ResearchDocument>(docCacheKey);

  // The server's copy, as the form would hold it.
  const baseline = useMemo(
    () => (selectedDoc ? researchToInput(selectedDoc) : null),
    [selectedDoc],
  );
  // The user's in-progress edits, or null when the form is simply showing what the server has.
  //
  // It carries the id it belongs to, and the draft is DERIVED from it rather than copied into
  // state — which is what makes the whole "instant paint, revalidate behind it" flow safe with no
  // effect at all. A revalidation landing under a user who is not typing is adopted immediately;
  // one landing under a user who IS typing loses to the override; and a selection change discards
  // it, because an override for another document is not this document's draft.
  const [override, setOverride] = useState<{ id: string; value: ResearchInput } | null>(null);
  const draft = override && override.id === selectedId ? override.value : baseline;

  // ── Identity: the title, and the slug the paper will live at ───────────────
  // The title is part of the DRAFT — it is the frontmatter `title:` key inside the body, the
  // only place an author may state one (the API derives, never accepts, a title).
  //
  // `derivedTitle` is read here AND by `useDetailTitle` further down — computed once and
  // shared, rather than each call site deriving its own copy the two are free to drift.
  const derivedTitle = draft ? deriveDocumentTitle(draft.content) : "";
  // Local edit buffer, mirroring `slugEdit` just below: the input must show exactly what was
  // typed — trailing space included — even though `setFrontmatterTitle` trims on write and
  // `derivedTitle` re-derives from (also-trimmed) content on every render. Without this buffer
  // the controlled input is driven by a value that reverts the trailing space the instant it is
  // typed, corrupting every keystroke after it: type "Hello ", it writes/re-derives "Hello",
  // React forces the DOM node back to "Hello", and the next character lands as "HelloW". The
  // write still goes through the trim below, so stored frontmatter stays trimmed — only the
  // DISPLAYED value is held raw. Do not "simplify" this back into a derived value.
  const [titleEdit, setTitleEdit] = useState<{ id: string; value: string } | null>(null);
  const title = titleEdit && titleEdit.id === selectedId ? titleEdit.value : derivedTitle;

  // The slug is NOT part of the draft. `PUT /content/markdown/:id` has no route field — the
  // route column is written by publish — so a slug in the draft would make an unpublished
  // paper dirty forever, with no baseline that could ever come back carrying it. Session
  // state, keyed by document like `override`, seeded from the published route when there is
  // one and from the title when there is not.
  const [slugEdit, setSlugEdit] = useState<{ id: string; value: string } | null>(null);
  const slug =
    slugEdit && slugEdit.id === selectedId
      ? slugEdit.value
      : (selectedDoc?.publicRoute ?? routeFromTitle(title));
  const setSlug = useCallback(
    // Lowercased HERE, not in the field: `DocumentIdentityField` edits a slug for whatever route
    // space its host owns, and research's is lowercase (PUBLIC_ROUTE_RE). A field that forced
    // case would be making that decision for every other host too.
    (next: string) => {
      if (selectedId) setSlugEdit({ id: selectedId, value: next.toLowerCase() });
    },
    [selectedId],
  );

  const checkSlug = useCallback(
    async (candidate: string) => {
      if (!selectedId) return { available: true };
      const res = await markdownApi.routeAvailable(selectedId, candidate, {
        workspace: workspaceSlug,
      });
      return { available: res.available, reason: SLUG_REASON[res.reason] };
    },
    [selectedId, workspaceSlug],
  );
  // `subject`: the verdict is about this slug FOR THIS PAPER. `checkSlug` excludes
  // `selectedId`'s own route, so the same slug string is legitimately "available" on the
  // paper that already owns it and taken on any other — without the subject the hook would
  // keep the previous paper's answer when the string happens not to change across a switch.
  const slugVerdict = useSlugAvailability(slug, checkSlug, { subject: selectedId });
  const [slugAlert, setSlugAlert] = useState(false);

  // The two buffers are NOT the same kind of thing, and must NOT be cleared the same way —
  // that "symmetry" was tried once and it destroyed authors' slugs (see the comment at the
  // `slugEdit` declaration above for why the slug has no other copy to fall back to).
  //
  // `titleEdit` is a display buffer OVER a real store: the draft frontmatter is the store,
  // `derivedTitle` re-derives from it on every render, and the buffer exists only to hold
  // raw keystrokes (trailing space) between writes. Clearing it loses nothing — the title
  // comes back from the draft — and it must be cleared on selection change, because a stale
  // buffer keyed by a since-reused id would otherwise resurrect on this document too.
  //
  // `slugEdit` IS the store, not a view over one. An unpublished paper has no baseline slug
  // anywhere else — `slug` falls back to `publicRoute ?? routeFromTitle(title)`, and
  // `publicRoute` is null until publish — so clearing this buffer on selection change would
  // silently replace a slug the author deliberately typed with the title-derived one, the
  // moment they merely switched documents and switched back. That IS data loss, not hygiene:
  // do not add `setSlugEdit(null)` here to "match" the title clear below.
  useEffect(() => {
    setTitleEdit(null);
  }, [selectedId]);

  // The scoped read/write pair for `raisedError` above. Clearing is unscoped on purpose: there is
  // only ever one message, so "no error" needs no id to be about.
  const formError = raisedError && raisedError.id === selectedId ? raisedError.text : null;
  const setFormError = useCallback(
    (text: string | null) => setRaisedError(text === null ? null : { id: selectedId, text }),
    [selectedId],
  );

  const dirty = Boolean(draft && baseline && researchDiffers(draft, baseline));
  const validationError = draft ? researchValidate(draft) : null;
  // Dirty AND valid AND settled. `isSettled` is the successor to the old `!loadingDoc` term and
  // carries one more rule with it: a save composed against a CACHED copy would PUT fields the
  // server has since changed. The busy/saving term is applied at the button — `SaveCancelButtons`
  // already renders `disabled={!canSave || saving}` — so folding `!saving` in here would express
  // the same rule twice.
  const canSave = Boolean(draft && baseline) && dirty && validationError === null && isSettled;
  // Delete waits on the same signal for the same reason: it is a write against a copy that may
  // already be out of date.
  const canDelete = selectedId !== null && isSettled && !saving && !deleting;

  const select = useCallback(
    (id: string) => {
      // URL-driven: navigate, and the hook re-reads for the new URL id. Embedded: local selection,
      // same hook, same re-read. Deep-link, reload and Back all arrive the same way — there is no
      // longer a second path that loads the body, so there is nothing for the two to disagree on.
      openDoc(id);
    },
    [openDoc],
  );

  // Memoized (rather than the plain `function` declaration it used to be) so `setTitle` below
  // can depend on it honestly: an unmemoized `onChange` closing over `formError` made
  // `setTitle`'s old dependency array a lie (it listed only `[draft]`), which is why the first
  // Title keystroke after a failed save used to leave the error banner up one keystroke too
  // long — `draft` did not change when `formError` did, so the stale closure ran.
  const onChange = useCallback(
    (next: ResearchInput): void => {
      if (!selectedId) return;
      setOverride({ id: selectedId, value: next });
      if (formError) setFormError(null);
    },
    [selectedId, formError, setFormError],
  );

  // Defined here — after `onChange` — rather than beside `derivedTitle`/`titleEdit` above, so it
  // can close over the memoized `onChange` without a temporal-dead-zone error (a `const` cannot
  // be referenced before its own initializer runs, unlike the hoisted `function` this used to be).
  const setTitle = useCallback(
    (next: string) => {
      if (selectedId) setTitleEdit({ id: selectedId, value: next });
      if (draft) onChange({ ...draft, content: setFrontmatterTitle(draft.content, next) });
    },
    [draft, onChange, selectedId],
  );

  function onCancel(): void {
    openDoc(null);
    setOverride(null);
    setFormError(null);
    // Both identity fields are session state keyed by document id — clear them together here so
    // they cannot drift apart again: an abandoned edit in either must not survive Cancel and
    // reappear if the same document is reselected.
    setSlugEdit(null);
    setTitleEdit(null);
  }

  // Returns true once the draft is persisted (false on a validation/save failure) so the merged
  // stack's exit guard knows whether a gated navigation may proceed.
  async function onSave(): Promise<boolean> {
    if (!draft) return false;
    // Already in flight — swallow the duplicate. Reporting `false` is right for the exit guard
    // too: nothing has been persisted YET, so leaving now would still lose the edit.
    if (savingRef.current) return false;
    // The spec's rule, and the reason it is a modal rather than an inline hint: by the time
    // Save is pressed the user has committed, so the refusal has to interrupt. `checking` is
    // NOT refused — a verdict still in flight is not a "no", and blocking on it would make Save
    // feel broken on a slow connection.
    // Only a save that would actually MOVE the route (see `writesPublicRoute`) needs this
    // guard. An unpublished draft's slug writes nothing on save, and a published paper whose
    // slug is unchanged writes nothing either — refusing either over a collision that will
    // never happen loses the author's content edits over a field that has no effect this save.
    if (writesPublicRoute(selectedDoc, slug) && slugVerdict.status === "unavailable") {
      setSlugAlert(true);
      return false;
    }
    const problem = researchValidate(draft);
    if (problem) {
      setFormError(problem);
      return false;
    }
    const input = researchNormalize(draft);
    savingRef.current = true;
    setSaving(true);
    setFormError(null);
    try {
      // Create is a modal now (see the CreateResourceDialog below); onSave only ever UPDATES the
      // open document.
      if (selectedId) {
        const updated = await markdownApi.update(selectedId, toUpdateBody(input), {
          workspace: workspaceSlug,
        });
        await refresh();
        // The response IS the server's copy, so record it rather than invalidating — a re-read
        // would spend a request to arrive back at these exact bytes. Dropping the override then
        // hands the form straight back to `baseline`, which is now what we just saved.
        //
        // A published paper's slug IS its route, and moving it is a re-publish (POST
        // /:id/publish re-points the route in place). Only for a paper that is already
        // public: publishing a draft stays the author's explicit act, on the publish card.
        let saved = updated;
        if (writesPublicRoute(saved, slug)) {
          saved = await markdownApi.publish(saved.id, slug, { workspace: workspaceSlug });
        }
        writeDoc(saved.id, saved);
        setOverride(null);
      }
      return true;
    } catch (err) {
      reportUnexpectedAuthError(err, { feature: "research-pane", step: "save" });
      setFormError(errorText(err, "Failed to save."));
      return false;
    } finally {
      savingRef.current = false;
      setSaving(false);
    }
  }

  function requestDelete(): void {
    if (canDelete) setPendingDelete(true);
  }

  function cancelDelete(): void {
    if (!deleting) setPendingDelete(false);
  }

  async function confirmDelete(): Promise<void> {
    if (!selectedId) return;
    setDeleting(true);
    try {
      await markdownApi.remove(selectedId, { workspace: workspaceSlug });
      setPendingDelete(false);
      // Forget the body BEFORE leaving. Keeping it would paint a document we know is gone if the
      // user navigated back to its URL, and only the GET behind that paint would take it away.
      writeDoc(selectedId, null);
      openDoc(null);
      setOverride(null);
      await refresh();
    } catch (err) {
      reportUnexpectedAuthError(err, { feature: "research-pane", step: "delete" });
      setFormError(errorText(err, "Failed to delete."));
      setPendingDelete(false);
    } finally {
      setDeleting(false);
    }
  }

  // Publish/unpublish returns the updated document; keep the cached copy + list in sync.
  async function onPublishChanged(updated: ResearchDocument): Promise<void> {
    writeDoc(updated.id, updated);
    await refresh();
  }

  // ── Render ─────────────────────────────────────────────────────────────────
  const rows = docs ?? [];
  const items: TopicDetailItem[] = rows.map((d) => ({
    id: d.id,
    label: d.title || "Untitled",
    // No leading icon (the level opts out) and no "Published" tag in the sublabel: a row has
    // exactly ONE discrete state, and it is marked ONCE, at the trailing edge. The sublabel is
    // left to say what the row IS — its category, else its tags — which is the only thing the
    // title cannot. The globe is aria-hidden, so the state rides an sr-only word instead: an
    // icon alone is a colour-only signal, and `trailing` renders AFTER the label, which is
    // where an accessible name wants it.
    trailing:
      d.visibility === "public" ? (
        <>
          <span className="sr-only">, published</span>
          <Globe size={14} aria-hidden className="text-apt-text-dim" />
        </>
      ) : undefined,
    sublabel: d.category || (d.tags.length > 0 ? d.tags.join(", ") : undefined),
  }));
  const validationHint = draft && dirty ? validationError : null;
  const editing = selectedId !== null;

  // The gear's option lists, taken once: the gear draws them and `filterKey` below keys them, and
  // the two must describe the same lists.
  const filterCategories = categoriesOf(universe);
  const filterTags = tagsOf(universe);

  // PUBLISH the documents list into the workspace shell's ONE merged stack (like the sibling
  // ecosystem panes) instead of a self-contained nested master/detail pane. Its controls are the
  // list's own toolbar: `+` to create, the pop-over search, and the gear holding the category/tag
  // filters. They sat in the page-wide home bar until that strip was removed as clunky (Mike,
  // 2026-09-24).
  const documentsLevel: TopicLevel & { filterKey: string } = {
    id: "research-documents",
    title: "Documents",
    items,
    selectedId,
    onSelect: (id) => select(id),
    // Hovering (or tabbing to) a row for a moment warms its body, so the click that follows has
    // nothing left to wait for.
    onPrefetch: prefetchDoc,
    // The spinner in front of "Documents" — the one signal that a read is happening, now that the
    // editor paints the cached copy instead of blanking to "Loading…".
    busy: fetchingDoc,
    onClear: onCancel,
    // `emptyLabel` STAYS: it is the rail's own text for an empty list, not a control. A NARROWED
    // list that comes back empty is not an empty library: "No documents yet." under a search or a
    // gear filter told the user their documents were gone.
    emptyLabel:
      docs === null
        ? "Loading…"
        : filters.q || filters.category || filters.tag
          ? "No documents match these filters."
          : "No documents yet.",
    // UNCONDITIONAL, as the bar's button was: an empty list is exactly when the first create
    // matters most.
    onNew: () => setNewOpen(true),
    newLabel: "Create Document",
    newActive: newOpen,
    // CONTROLLED: the query goes to the backend list endpoint (debounced into `applied`), which
    // also searches bodies the rail's rows never show — so the rail must not filter them again.
    search: {
      query: filters.q,
      onQueryChange: (q) => setFilters((prev) => ({ ...prev, q })),
      placeholder: "Search research documents",
    },
    titleActions: (
      <ResearchFilters
        filters={filters}
        onChange={setFilters}
        categories={filterCategories}
        tags={filterTags}
      />
    ),
    // The gear's PLAIN companion, as the rail host's publish key asks of any node (`levelsKey` in
    // @agentic-toolkit/resource): the host draws the level it REGISTERED, and a node is invisible
    // to that key. Without this the gear froze at its last registration — options the universe
    // read delivered late never appeared, and a filter cleared onto a cached list with the same
    // rows stayed gold and checked. So it moves with everything the gear draws.
    filterKey: JSON.stringify([filters.category, filters.tag, filterCategories, filterTags]),
    // A document row's identity is its title; it has no icon worth a column of its own, and the
    // published state it used to show there is now the row's `trailing` mark.
    hideItemIcons: true,
  };
  // The open document names the pane it is open in. Now that the title is EDITABLE (the
  // identity field above the body), the header follows what the author is typing rather than
  // the saved document's name — Task 11's docblock gave this to `selectedDoc.title` for the
  // reason stated above; that reason still holds, only the conclusion changes with the title
  // now derived live from the draft.
  useDetailTitle(draft ? derivedTitle : null);
  // Registered only while DIRTY (see useMasterDetailLevel) so the host's guard count is a
  // render-value dirty signal. `editing` is implied: a draft cannot be dirty with no editor open.
  useWorkspaceExitGuard(dirty ? { isDirty: () => dirty } : null);

  // The host-injected per-record affordance (the hub's api-explorer button); null on
  // a standalone feature site → the trailing slot renders nothing.
  const renderRecordAffordance = useRecordAffordance();

  // The frontier leaf: a portaled Save/Cancel/Delete bar over the editor (or a placeholder). The
  // list itself lives in the published rail above, so this renders ONLY the editor half.
  const actions: MasterDetailActions = {
    onCreate: () => setNewOpen(true),
    createLabel: "New document",
    onCancel,
    canCancel: editing,
    onSave: () => void onSave(),
    canSave,
    saving,
    onDelete: requestDelete,
    canDelete,
    // ResearchPane owns its own (document-specific) delete confirm modal below, so the bar's
    // generic confirm stays off (deletePrompt null) — its Delete button just opens ours.
    deletePrompt: null,
  };

  return (
    <>
      {/* Every level in one publication: the category chain, then the documents. StackLevels
          (not useStackLevel) because the count VARIES with the depth walked into, and it
          advances the depth for the leaf below by exactly that many. Nothing precedes the
          category chain here — see NotebookPane's identical comment on why a level that
          cannot be selected can never sit in front of the rail. */}
      <StackLevels levels={[...categoryLevels, documentsLevel]}>
        <MasterDetailLeaf
          form={{ actions, editing, draft }}
          trailing={renderRecordAffordance?.({
            path: "/content/markdown/{id}",
            pathValues: { id: selectedId },
            title: "Research document API",
          })}
          error={listError ?? formError ?? docError}
          emptyTitle={
            // Reached only with nothing cached for this id — otherwise `draft` is already the cached
            // document and the editor below renders instead.
            fetchingDoc || docs === null
              ? "Loading…"
              : "Select a document to edit, or create a new one."
          }
          // Publishing is the pane's FLOOR, not the last thing under the body: it is about the
          // document as a whole, it is where the public URL is read off, and it must not walk up
          // and down the pane with the length of what you are writing.
          footer={
            selectedDoc && (
              <PublishSection
                key={selectedDoc.id}
                doc={selectedDoc}
                route={slug}
                verdict={slugVerdict}
                userSlug={userSlug}
                workspaceSlug={workspaceSlug}
                onChanged={onPublishChanged}
                disabled={!isSettled}
              />
            )
          }
          renderDetail={(d) => (
            // No "Loading…" branch: whatever is cached is on screen from the first frame, and the
            // read settles behind it. `disabled` is what makes that safe — see `isSettled`.
            <ResearchDetail
              draft={d}
              identity={
                <DocumentIdentityField
                  key={selectedId ?? "none"}
                  title={title}
                  onTitleChange={setTitle}
                  slug={slug}
                  onSlugChange={setSlug}
                  slugify={routeFromTitle}
                  verdict={slugVerdict}
                  disabled={!isSettled}
                />
              }
              onChange={onChange}
              categoryOptions={accountCategories}
              tagOptions={accountTags}
              error={validationHint}
              disabled={!isSettled}
            />
          )}
        />
      </StackLevels>

      {/* Create is a scoped modal: the title + the category that places it (HTD recipe
          `must-create-in-modal`). The editor that opens on the created doc is where the body is
          WRITTEN; it starts here only with a title because that is what the document's first
          heading — and its identity — is made of. */}
      {newOpen && (
        <CreateResourceDialog<ResearchPlacement, ResearchDocument>
          ariaLabel="New document"
          heading="New document"
          blank={() => ({ title: "", category: activeCategoryName })}
          validate={(d) =>
            !d.title.trim()
              ? "A title is required."
              : d.category.length > 200
                ? "Category must be 200 characters or fewer."
                : null
          }
          create={(d) =>
            markdownApi.create(
              toCreateBody(
                researchNormalize({
                  content: `# ${d.title.trim()}\n\n`,
                  category: d.category,
                  tags: [],
                }),
              ),
              { workspace: workspaceSlug },
            )
          }
          onClose={() => setNewOpen(false)}
          onCreated={(created) => {
            setNewOpen(false);
            void refresh();
            // Record the created document BEFORE selecting it, so the editor it opens into paints
            // from the cache with no read at all — the create response already is the server's
            // copy. (This is what the old `loadedIdRef` dance was for.)
            writeDoc(created.id, created);
            openDoc(created.id);
            setOverride(null);
            setFormError(null);
          }}
          renderForm={(draft, onChange, error) => (
            <>
              <Field
                label="Title"
                hint="The document's first heading; you can edit the rest in the editor."
              >
                <Input
                  /* eslint-disable-next-line jsx-a11y/no-autofocus -- focus the first field on open */
                  autoFocus
                  value={draft.title}
                  placeholder="My research"
                  onChange={(e) => onChange({ ...draft, title: e.target.value })}
                />
              </Field>
              <Field label="Category" hint="Optional — group the document; you can change it later.">
                <Input
                  value={draft.category}
                  placeholder="e.g. Research notes"
                  onChange={(e) => onChange({ ...draft, category: e.target.value })}
                />
              </Field>
              <ErrorText error={error} />
            </>
          )}
        />
      )}

      {/* The category gear's own dialogs — rename/move/delete/add, scoped to whichever category
          level the gear was opened from. Research has no separate flat category MANAGER the way
          the notebook does (`ResearchFilters`' gear on the Documents toolbar only NARROWS by
          category; it edits nothing) — the category levels' gear (`CategoryGearMenu`) is the only
          category editor this pane offers. */}
      {categoryDialogs}

      <AlertModal
        open={pendingDelete}
        destructive
        title="Delete document?"
        description="This soft-deletes the document. Its public route, if any, is freed."
        confirmLabel="Delete"
        cancelLabel="Cancel"
        busy={deleting}
        onConfirm={() => void confirmDelete()}
        onCancel={cancelDelete}
      />

      <AlertModal
        open={slugAlert}
        tone="error"
        title="That slug isn’t available"
        description={
          slugVerdict.reason ??
          "Another of your papers already uses that slug. Edit it and try again."
        }
        confirmLabel="OK"
        onConfirm={() => setSlugAlert(false)}
      />
    </>
  );
}
