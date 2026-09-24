"use client";

import { useCallback, useState } from "react";
import { Trash2 } from "lucide-react";
import { Field, FieldGroup, ButtonBar } from "@agenticdevelopertoolkit/ui/blocks";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Textarea } from "@agenticdevelopertoolkit/ui/components/textarea";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { errMsg, httpStatus, useResourceList } from "@agentic-toolkit/data";
import { specialInterestsCacheKey } from "./interests-cache";
import {
  specialInterestsApi,
  type SpecialInterestRow,
} from "@agentic-toolkit/data/personas";

// A persona's one or two DEEP interests: three narrowing levels plus the author's own opinions.
//
// The stances go into the system prompt VERBATIM, which is the entire point — a persona with
// stances argues its corner instead of agreeing with whatever the user says. Nothing here is
// generated: an empty stances box means a persona that knows the topic but has no view on it.
//
// Interests are a child table with their own routes, so each one saves on its own rather than
// riding the persona draft's save. That keeps the pane honest (an interest is either saved or
// visibly unsaved) at the cost of a Save button per card.

/** The cap the backend enforces (400 past it). Mirrored here to disable the add button. */
const MAX_INTERESTS = 2;

/** The `stances` length the backend enforces (`MAX_STANCES_CHARS` in
 *  `backend/src/adh/src/crud/pre-create-hooks.ts`, 400 past it). Mirrored here as the textarea's
 *  `maxLength` so the author is stopped while typing rather than by a save that fails after the
 *  fact — the backend's message for it is generic, and this is the one field with no visible
 *  length cue. The bound exists because stances are pasted into the system prompt on every turn. */
const MAX_STANCES_CHARS = 4000;

/** A card's editable state. `id` is null until the first successful save. `key` is a client-only
 *  identity, stable for the card's whole lifetime, that `save`/`remove` address instead of the
 *  card's position in `drafts` — see `newKey` below for why. */
interface Draft {
  key: string;
  id: string | null;
  slug: string;
  general: string;
  topical: string;
  specific: string;
  stances: string;
}

/** A stable client-side identity for a draft card. Deliberately NOT derived from `id`: a brand-new
 *  card has no id at all, and that is exactly the card that must stay addressable across its first
 *  save. Deliberately NOT the array index either — `save`/`remove` are async and capture their
 *  target before an await, and a sibling's completion in between (a faster delete, a synchronous
 *  remove of an earlier card) can shift every later card's index out from under them, landing the
 *  eventual `map`/`filter` on the wrong row. `crypto.randomUUID` needs a secure context, so this
 *  falls back to a counter — uniqueness only has to hold for one component instance's lifetime. */
let keySeq = 0;
function newKey(): string {
  const c = (globalThis as { crypto?: Crypto }).crypto;
  if (c?.randomUUID) return c.randomUUID();
  keySeq += 1;
  return `draft-${Date.now()}-${keySeq}`;
}

function toDraft(row: SpecialInterestRow, key: string): Draft {
  return {
    key,
    id: row.id,
    slug: row.slug,
    general: row.general,
    topical: row.topical ?? "",
    specific: row.specific ?? "",
    stances: row.stances ?? "",
  };
}

/** The subset of `Draft` that can actually go stale relative to the server — everything except
 *  the client-only `key` and the immutable `id`/`slug`. Compared field-by-field (not
 *  `JSON.stringify`) against `baselines[d.key]` to decide whether a loaded card is dirty. */
type DraftFields = Pick<Draft, "general" | "topical" | "specific" | "stances">;

function fieldsOf(d: Draft): DraftFields {
  return { general: d.general, topical: d.topical, specific: d.specific, stances: d.stances };
}

/** A short, stable, `[0-9a-z]` digest of a string — FNV-1a 32-bit rendered base-36. Deliberately
 *  not a cryptographic hash and not `crypto.randomUUID`: the ONLY properties needed are that the
 *  same text always digests to the same value (so a failed save retried is the same interest, not
 *  a second one) and that different texts almost never collide (so a persona's two interests can't
 *  land on one slug). `Math.imul` keeps the multiply in 32-bit; `>>> 0` keeps it unsigned. */
function digest36(s: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i += 1) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h.toString(36);
}

/** The rdid segment for a new interest, derived from its most specific level so the author
 *  never has to name one. Lower-case, [a-z0-9-] only, no leading/trailing/repeated dashes.
 *  Never returns "" — see the fallback below. */
export function slugify(...levels: string[]): string {
  const source = levels.map((l) => l.trim()).filter(Boolean).pop() ?? "";
  // Slice to the rdid segment's length limit BEFORE stripping edge dashes, not after — a cut
  // that lands mid dash-run (e.g. a 63-char word followed by " b") leaves a trailing "-" if the
  // strip already ran, which the server then 400s on as an unusable slug the author never typed.
  const derived = source
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .slice(0, 64)
    .replace(/^-+|-+$/g, "");
  // A level written entirely outside [a-z0-9] — Cyrillic, CJK, emoji, «guillemets» — has nothing
  // to keep: the replace collapses it to one dash run and the strip empties it. The backend's
  // `validateLeaf` answers "" with `slug: Required.` (400), and this editor has NO slug field, so
  // the author would be permanently stuck: no way to satisfy it, and (before the `slug:` branch in
  // `saveError`) no way to even learn what was wrong. Fall back to a digest of the level so the
  // interest is nameable at all — opaque, but the slug is an internal storage segment the author
  // never sees, while the levels they DID type are what the UI and the prompt render.
  return derived || `interest-${digest36(source)}`;
}

/** The card's heading — the most specific level the author has typed, so it reads the way the
 *  interest narrows (Battlestar Galactica, or Space Opera, or just Science Fiction while the
 *  author is still filling it in), and "New interest" before anything is typed at all. */
function cardTitle(d: Draft): string {
  return d.specific.trim() || d.topical.trim() || d.general.trim() || "New interest";
}

/** Matches the pre-create hook's exact message (`backend/src/adh/src/crud/pre-create-hooks.ts`,
 *  `specialInterestCreate`) for the two-interest cap. The slug rejection from that same hook has
 *  its own text and its own branch (`SLUG_MESSAGE` below); everything else — a level over its
 *  120-character limit, a blank General — comes back from generic CRUD's Zod-validation catch as
 *  the flat, field-blind "invalid request body", so the last branch names the length limit
 *  instead of blaming a cap the author hasn't hit. */
const CAP_MESSAGE = /at most \d+ special interests?/i;

/** The pre-create hook's slug rejection, emitted verbatim as `slug: <validateLeaf message>`
 *  (`backend/src/adh/src/crud/pre-create-hooks.ts` → `lib/rdid.ts`). A THIRD 400 sharing the
 *  status with the cap and with generic CRUD's "invalid request body", and the only one whose
 *  cause is a field the author cannot see: the slug is derived, not typed. `slugify` above should
 *  now make this unreachable — this branch is what tells us if that ever stops being true, rather
 *  than blaming the author's level lengths for it. */
const SLUG_MESSAGE = /^slug:/i;

/** The unique-violation 409 — generic CRUD answers a duplicate row with "resource already exists"
 *  and a duplicate rdid with "id already exists" (`crud/factory.ts`), the same "already exists"
 *  text `rethrowConflict` keys on elsewhere in this codebase. Matched POSITIVELY, so the
 *  PROVISIONING 409 the pre-create hook also throws ("cannot resolve a corpus ecosystem …") falls
 *  through to its own text instead of being narrated as a name clash — an owner saving their FIRST
 *  interest under a unique name was once told they already had one by that name. Positive rather
 *  than negative matching on purpose: another 409 added later falls through to the backend's
 *  words, which is merely unpolished, instead of inheriting a confident falsehood. */
const DUPLICATE_MESSAGE = /already exists/i;

/** The one save-blocking rule this editor can check BEFORE the request, in one place: it is both
 *  the reason shown beside a card's greyed-out Save and the tail of the 400's narration below, so
 *  the pre-click explanation and the post-failure one can never say different things. It has to be
 *  said up front at all because `canSaveCard` disables the button, which makes the 400 that used
 *  to explain it unreachable. */
const BLANK_GENERAL_MESSAGE = "General can't be blank.";

/** Turn a save failure into something the author can act on. 403 = no write on the table (the
 *  `x-exposure` gate — `persona.special_interests` is owner-tier, so this only fires for someone
 *  who is not the owner). 400 and 409 each cover several backend failures that share a status but
 *  not a cause — see `CAP_MESSAGE`, `SLUG_MESSAGE` and `DUPLICATE_MESSAGE` above for how they are
 *  told apart, and note that every discriminator matches the SPECIFIC case and falls through, so
 *  an unrecognized message is never mislabelled as a recognized one. */
function saveError(err: unknown): string {
  const status = httpStatus(err);
  const message = errMsg(err, "");
  if (status === 400) {
    if (CAP_MESSAGE.test(message)) return `A persona can hold at most ${MAX_INTERESTS} interests.`;
    if (SLUG_MESSAGE.test(message)) {
      return "This interest's name can't be turned into an id — give its most specific level at least one letter or digit.";
    }
    return `Each level must be 120 characters or fewer, and ${BLANK_GENERAL_MESSAGE}`;
  }
  if (status === 409 && DUPLICATE_MESSAGE.test(message)) {
    return "This persona already has an interest by that name.";
  }
  if (status === 403) return "You don't have permission to change this persona's interests.";
  return errMsg(err, "Could not save this interest.");
}

export function InterestsEditor({ personaId }: { personaId: string | null }) {
  const [drafts, setDrafts] = useState<Draft[]>([]);
  // The MUTATION error only — a failed read has its own, from the hook below.
  const [error, setError] = useState<string | null>(null);
  // A SET, not a single value: concurrent operations on DIFFERENT cards (delete B, then delete A
  // while B is still in flight) are a legitimate flow, not a same-card double-click, and each
  // card's own busy state must track only its own request regardless of what else is in flight.
  const [busyKeys, setBusyKeys] = useState<Set<string>>(new Set());
  // The stored baseline each loaded card was prefilled from, keyed by the card's stable `key` —
  // re-set to the just-saved fields on a successful save, so that card's Save goes disabled again
  // until the next edit rather than staying clickable for a no-op re-save of what's already
  // persisted. A brand-new card (`id === null`) never gets an entry here; `canSaveCard` below
  // exempts it from the dirty check entirely since it has no persisted state to diff against.
  const [baselines, setBaselines] = useState<Record<string, DraftFields>>({});

  const setBusy = (key: string, busy: boolean) =>
    setBusyKeys((prev) => {
      const next = new Set(prev);
      if (busy) next.add(key);
      else next.delete(key);
      return next;
    });

  /** Has this card diverged from what was persisted? A brand-new card is dirty the moment it holds
   *  anything at all. */
  const cardDirty = (d: Draft): boolean => {
    const baseline = baselines[d.key];
    if (d.id === null || !baseline) {
      return Boolean(d.general || d.topical || d.specific || d.stances);
    }
    return (
      d.general !== baseline.general ||
      d.topical !== baseline.topical ||
      d.specific !== baseline.specific ||
      d.stances !== baseline.stances
    );
  };

  // The stored rows, from the one entry the Knowledge facet reads too. Reopening this persona
  // paints its cards on the first frame and re-reads behind them, instead of showing an empty
  // editor for the length of a round trip. No persona reads nothing: the pane says so below.
  const loadInterests = useCallback(
    () =>
      personaId ? specialInterestsApi.list(personaId) : Promise.resolve([] as SpecialInterestRow[]),
    [personaId],
  );
  const {
    items: rows,
    error: loadError,
    isFetching,
    setItems: setRows,
  } = useResourceList<SpecialInterestRow>(specialInterestsCacheKey(personaId), loadInterests);

  // What the cards on screen were built from. The cards are DRAFTS — the author's copy — so the
  // server's rows SEED them rather than being them, and this records which seeding already
  // happened, so a read is applied exactly once, at arrival.
  const [seed, setSeed] = useState<{ personaId: string | null; rows: SpecialInterestRow[] | null }>(
    { personaId, rows: null },
  );
  // Both branches below are render-phase state sets: React re-renders before the commit, so the
  // interim never paints. The render body still runs to completion though, which is why the cards
  // are read from `cards` below rather than straight from `drafts`.
  const scopeChanged = seed.personaId !== personaId;
  if (scopeChanged) {
    // A different persona: drop the cards wholesale rather than leave one persona's interests
    // sitting under another's editor while its own rows are on their way.
    setSeed({ personaId, rows: null });
    setDrafts([]);
    setBaselines({});
  } else if (rows !== null && rows !== seed.rows) {
    // New rows — a read that landed, or this editor's own write published below. Consume them
    // either way: an offer declined is still an offer answered, and one left unconsumed would
    // apply later instead, at whatever moment the editor next happened to be clean.
    setSeed({ personaId, rows });
    // …but never OVER unsaved work. A revalidation is invisible to an author mid-edit, and
    // replacing their cards with the server's would be the worst kind of data loss — including
    // the brand-new empty card that a sibling card's save must not sweep away. When nothing is
    // dirty the rows and the cards already say the same thing, so re-seeding costs nothing.
    if (!drafts.some(cardDirty)) {
      const seeded = rows.map((row) => toDraft(row, newKey()));
      setDrafts(seeded);
      setBaselines(Object.fromEntries(seeded.map((d) => [d.key, fieldsOf(d)])));
    }
  }
  const cards = scopeChanged ? [] : drafts;

  if (!personaId) {
    return (
      <p className="text-sm text-apt-text-muted">
        Save this persona first to give it special interests.
      </p>
    );
  }

  const set = (index: number, patch: Partial<Draft>) =>
    setDrafts((prev) => prev.map((d, i) => (i === index ? { ...d, ...patch } : d)));

  // A brand-new card (`id === null`) has no persisted baseline to diff against — a filled-in
  // required field IS the change, same carve-out `CrudRecordForm`'s `canSave` and `TopicForm`'s
  // `canSubmit` use for create mode. A loaded card is gated on dirty too, so re-submitting the
  // unchanged interest (a silent no-op PUT) isn't offered.
  // The one validity rule a card's Save can check before the request, as a REASON rather than a
  // boolean: a card whose Opinions are typed but whose General is blank is dirty AND invalid, so
  // the button greys out and the only explanation — the backend's field-blind 400, narrated by
  // `saveError` — can no longer be reached, because the click can't happen.
  const cardBlockedReason = (d: Draft): string | null =>
    d.general.trim() ? null : BLANK_GENERAL_MESSAGE;

  const canSaveCard = (d: Draft): boolean => {
    if (cardBlockedReason(d) !== null) return false;
    // A brand-new card (`id === null`) has no persisted baseline to diff against — a filled-in
    // required field IS the change, so `cardBlockedReason` passing is enough.
    if (d.id === null || !baselines[d.key]) return true;
    return cardDirty(d);
  };

  const add = () =>
    setDrafts((prev) => [
      ...prev,
      { key: newKey(), id: null, slug: "", general: "", topical: "", specific: "", stances: "" },
    ]);

  // Publish a save or a delete to the shared entry, so the Knowledge facet's tab strip follows this
  // editor without waiting for a read of its own.
  //
  // Always through the UPDATER form, never a value computed from this render's `rows`: these
  // handlers are async and two can be in flight at once, so a value would carry whatever the list
  // was when the button was clicked and the slower one would republish rows its sibling has
  // already removed — the same class of bug `save`/`remove` address by key rather than by index.
  //
  // A null `prev` publishes NOTHING. Null is "this list has never been read, or its read failed",
  // and folding it to `[]` would turn one saved card into a fabricated WHOLE list — written into
  // the shared entry as a success, erasing the error with it, so the Knowledge facet would show a
  // persona's single interest where it has ten. Leaving the entry untouched keeps the next read a
  // real one; this editor's own cards are already correct without it.
  const publishRows = (next: (prev: SpecialInterestRow[]) => SpecialInterestRow[]) =>
    setRows((prev) => (prev === null ? null : next(prev)));

  // `save`/`remove` take the card's KEY, never its array index or position at call time. Both are
  // async: the array can reorder while one is in flight (a sibling's delete resolving first, a
  // synchronous remove of an earlier card), and an index captured at dispatch would then apply the
  // eventual `map`/`filter` to whatever card has slid into that slot — not the card the author
  // actually clicked. Keying by `key` makes the write land on the right row regardless of order.
  const save = async (key: string) => {
    const d = cards.find((row) => row.key === key);
    if (!d) return;
    setBusy(key, true);
    setError(null);
    try {
      let saved: SpecialInterestRow;
      if (d.id) {
        saved = await specialInterestsApi.update(d.id, {
          general: d.general,
          topical: d.topical || null,
          specific: d.specific || null,
          stances: d.stances || null,
        });
      } else {
        // The slug is an rdid segment and immutable once minted (it names the interest's
        // storage bucket), so derive it ONCE, on create, from the most specific level.
        const slug = d.slug || slugify(d.general, d.topical, d.specific);
        saved = await specialInterestsApi.create({
          personaId,
          slug,
          general: d.general,
          topical: d.topical || null,
          specific: d.specific || null,
          stances: d.stances || null,
        });
      }
      // Patch ONLY this card from the server's response, addressed by its stable key — a
      // wholesale `reload()` would replace every card with fresh server rows, silently
      // discarding any sibling card's local edits that haven't been saved yet (including a
      // brand-new card with no id at all); an index-addressed patch would land on whichever
      // card now sits at that position if the array reordered while this save was in flight.
      setDrafts((prev) => prev.map((row) => (row.key === key ? toDraft(saved, key) : row)));
      setBaselines((prev) => ({ ...prev, [key]: fieldsOf(toDraft(saved, key)) }));
      // The stored rows the same way: replace the row this card names if it is already there (an
      // update, which must keep its position), append it if it isn't (a create).
      publishRows((stored) =>
        stored.some((row) => row.id === saved.id)
          ? stored.map((row) => (row.id === saved.id ? saved : row))
          : [...stored, saved],
      );
    } catch (err) {
      setError(saveError(err));
    } finally {
      setBusy(key, false);
    }
  };

  const dropBaseline = (key: string) =>
    setBaselines((prev) => {
      const next = { ...prev };
      delete next[key];
      return next;
    });

  const remove = async (key: string) => {
    const d = cards.find((row) => row.key === key);
    if (!d) return;
    if (!d.id) {
      setDrafts((prev) => prev.filter((row) => row.key !== key));
      dropBaseline(key);
      return;
    }
    setBusy(key, true);
    setError(null);
    try {
      await specialInterestsApi.delete(d.id);
      // Drop just this card locally, addressed by key — see `save` above for why an
      // index-addressed filter is wrong once a concurrent operation can reorder the array.
      setDrafts((prev) => prev.filter((row) => row.key !== key));
      dropBaseline(key);
      publishRows((stored) => stored.filter((row) => row.id !== d.id));
    } catch (err) {
      setError(errMsg(err, "Could not remove this interest."));
    } finally {
      setBusy(key, false);
    }
  };

  return (
    <section className="flex flex-col gap-4">
      <div className="flex flex-col gap-1">
        <h3 className="text-sm font-medium">Special interests</h3>
        <p className="text-xs text-apt-text-muted">
          One or two topics this persona knows deeply and has opinions about. Narrow from general
          to specific — Science Fiction → Space Opera → Battlestar Galactica. Whatever you write
          under Opinions goes into the persona&apos;s prompt word for word, so it will argue these
          points, including with you. Declaring an interest also creates a place to put research:
          fill it from the Knowledge facet.
        </p>
      </div>

      {/* The mutation's message leads: it answers something the author just did. */}
      <ErrorText error={error ?? loadError} />

      {cards.map((d, i) => (
        <FieldGroup key={d.key} title={cardTitle(d)}>
          {/* `Field` wraps caption + hint in the SAME <label> as the input, so a hint alone would
              fold into the field's accessible name and defeat an anchored `getByLabelText`
              query. Fix is the `aria-label` idiom from `add-users-modal.tsx`: it matches the
              input directly regardless of what text the surrounding label carries, so the hint
              stays for the author while the query stays exact. */}
          <Field label="General" hint="The broad field.">
            <Input
              aria-label="General"
              value={d.general}
              onChange={(e) => set(i, { general: e.target.value })}
              placeholder="Science Fiction"
              maxLength={120}
            />
          </Field>
          {/* The levels NARROW, so they fill left to right: there is no coherent "Space Opera"
              without a field it narrows, and the slug derives from the most specific one.
              Disabled only while BOTH this field and the one it narrows are empty — never while
              it already holds a value, loaded or typed. A row can legally arrive from the server
              with `topical: null, specific: 'X'` (no CHECK constraint ties the two), and clearing
              the parent level in-session must not strand the child's still-present value behind a
              disabled input the author can no longer reach to edit or clear. */}
          <Field label="Topical" hint="The narrower area within it.">
            <Input
              aria-label="Topical"
              value={d.topical}
              onChange={(e) => set(i, { topical: e.target.value })}
              placeholder="Space Opera"
              disabled={!d.general.trim() && !d.topical.trim()}
              maxLength={120}
            />
          </Field>
          <Field label="Specific" hint="The one thing it is intense about.">
            <Input
              aria-label="Specific"
              value={d.specific}
              onChange={(e) => set(i, { specific: e.target.value })}
              placeholder="Battlestar Galactica"
              disabled={!d.topical.trim() && !d.specific.trim()}
              maxLength={120}
            />
          </Field>
          <Field
            label="Opinions"
            hint="In the persona's own voice. Written verbatim into its prompt — this is what it will defend."
          >
            <Textarea
              aria-label="Opinions"
              value={d.stances}
              onChange={(e) => set(i, { stances: e.target.value })}
              placeholder="Loves the miniseries. Hates how the Cylons libel machine minds…"
              className="min-h-32 resize-y"
              maxLength={MAX_STANCES_CHARS}
            />
          </Field>
          {/* Removing an interest is NOT destructive to the research, and the author has no way to
              tell that from a trash icon. The backend deliberately keeps the bucket and every
              document in it (`revokeInterestBucketAccess`) — a delete is often a rename-by-recreate
              and re-gathering a corpus is expensive — and withdraws only this persona's access.
              Saying so here is what makes that design legible instead of a silent surprise in
              either direction: nobody loses work they thought was gone, and nobody assumes a
              removal wiped material they wanted wiped. */}
          <p className="text-xs text-apt-text-muted">
            Removing an interest keeps its research documents — they stay in storage and only this
            persona&apos;s access to them is withdrawn.
          </p>
          <ButtonBar
            leading={
              // Say WHY this card's Save is grey when General is the blocker. Silent on a card the
              // author hasn't touched — grey there just means "nothing to save".
              cardBlockedReason(d) && cardDirty(d) ? (
                <span className="text-xs text-apt-text-muted" role="status">
                  {cardBlockedReason(d)}
                </span>
              ) : undefined
            }
          >
            <Button
              type="button"
              variant="ghost"
              onClick={() => void remove(d.key)}
              disabled={busyKeys.has(d.key)}
            >
              <Trash2 size={14} aria-hidden /> Remove
            </Button>
            <Button
              type="button"
              onClick={() => void save(d.key)}
              disabled={busyKeys.has(d.key) || !canSaveCard(d)}
            >
              Save interest
            </Button>
          </ButtonBar>
        </FieldGroup>
      ))}

      <div className="flex items-center gap-3">
        <Button
          type="button"
          variant="secondary"
          onClick={add}
          // Only the FIRST read holds Add down — a cached editor has its cards already, and a
          // revalidation behind them is not a reason to take the affordance away.
          disabled={(rows === null && isFetching) || cards.length >= MAX_INTERESTS}
        >
          Add an interest
        </Button>
        {cards.length >= MAX_INTERESTS && (
          <span className="text-xs text-apt-text-muted">
            A persona can hold at most two interests — deep beats broad.
          </span>
        )}
      </div>
    </section>
  );
}
