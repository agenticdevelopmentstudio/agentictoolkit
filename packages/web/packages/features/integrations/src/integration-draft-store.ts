// The add-integration modal (client-side only) remembers an unsaved, partially-filled
// draft per (ecosystem, provider) and offers to resume it. Secrets must NEVER be
// persisted: `clientSecret` is always blanked, and any `fields[k]` the caller flags as
// secret (via `secretFieldKeys`, derived from the provider's `configFields`) is blanked
// too, before the draft ever reaches `JSON.stringify`. Every function is SSR-safe (a
// no-op / null when there is no `window`) and never throws — storage can be unavailable
// (private mode, disabled, quota) or hold malformed JSON (a stale shape from a previous
// version), and none of that should break the caller.
import { intBlank, type IntegrationInput } from "./IntegrationDetail";

const KEY_PREFIX = "adh.int-draft.";

interface DraftWrapper {
  v: 1;
  providerId: string;
  /** PARTIAL on the way back in. It is written whole, but what `localStorage` hands back is
   *  whatever survived — see {@link completeDraft}. */
  draft: Partial<IntegrationInput>;
}

function keyFor(ecosystemId: string, providerId: string): string {
  return `${KEY_PREFIX}${ecosystemId}.${providerId}`;
}

function ecosystemPrefix(ecosystemId: string): string {
  return `${KEY_PREFIX}${ecosystemId}.`;
}

/** Deep-copies `draft` with `clientSecret` and every `secretFieldKeys` entry in
 *  `fields` blanked — the only shape that is ever written to storage. */
function stripSecrets(draft: IntegrationInput, secretFieldKeys: string[]): IntegrationInput {
  const fields: Record<string, string> = { ...draft.fields };
  for (const key of secretFieldKeys) {
    fields[key] = "";
  }
  return {
    ...draft,
    clientSecret: "",
    endpoints: { ...draft.endpoints },
    fields,
  };
}

function isWrapper(value: unknown): value is DraftWrapper {
  return (
    typeof value === "object" &&
    value !== null &&
    "draft" in value &&
    typeof (value as { draft: unknown }).draft === "object" &&
    (value as { draft: unknown }).draft !== null &&
    "providerId" in value &&
    typeof (value as { providerId: unknown }).providerId === "string"
  );
}

/** Persist the in-progress draft for (ecosystem, provider), stripped of secrets.
 *  `secretFieldKeys` = the keys in `draft.fields` that are secret (caller derives from
 *  provider.configFields). `clientSecret` is ALWAYS dropped. */
export function saveDraft(
  ecosystemId: string,
  providerId: string,
  draft: IntegrationInput,
  secretFieldKeys: string[],
): void {
  if (typeof window === "undefined") return;
  try {
    const wrapper: DraftWrapper = {
      v: 1,
      providerId,
      draft: stripSecrets(draft, secretFieldKeys),
    };
    window.localStorage.setItem(keyFor(ecosystemId, providerId), JSON.stringify(wrapper));
  } catch {
    // Storage unavailable (private mode / disabled) or quota exceeded — the draft simply
    // isn't persisted; the caller's in-memory state is unaffected either way.
  }
}

/** A `Record<string, string>` of only the entries that really are strings. */
function stringMap(value: unknown): Record<string, string> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return {};
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
    if (typeof v === "string") out[k] = v;
  }
  return out;
}

/**
 * EVERY FIELD `IntegrationInput` DECLARES, whatever the stored object happened to carry.
 *
 * `loadDraft` has always promised a complete `IntegrationInput` and its readers take the promise
 * literally: the Add dialog SUBSTITUTES the loaded draft for `intBlank` rather than merging onto
 * it, and `useIntegrationTest` reads `draft.fields` and `draft.clientSecret` during render. But
 * the guard below only ever checked that `draft` was an object — so a wrapper written by an older
 * shape, truncated by a quota failure, or edited by hand reached the dialog missing `fields`, and
 * Add white-screened for that provider on `Cannot read properties of undefined`, thrown from
 * render. Clearing it took devtools, because the dialog that clears the draft is the one
 * crashing. Merging onto the blank makes the promise true instead of assumed.
 */
function completeDraft(providerId: string, stored: Partial<IntegrationInput>): IntegrationInput {
  return {
    ...intBlank(providerId),
    ...stored,
    // The provider is the KEY this was filed under, never whatever the payload claims.
    providerId,
    // Secrets were never stored — re-inflate them as blank.
    clientSecret: "",
    endpoints: stringMap(stored.endpoints),
    fields: stringMap(stored.fields),
  };
}

/** Load a saved draft, or null if none / malformed. */
export function loadDraft(ecosystemId: string, providerId: string): IntegrationInput | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.localStorage.getItem(keyFor(ecosystemId, providerId));
    if (!raw) return null;
    const parsed: unknown = JSON.parse(raw);
    if (!isWrapper(parsed)) return null;
    return completeDraft(providerId, parsed.draft);
  } catch {
    return null;
  }
}

/** Remove a saved draft. */
export function clearDraft(ecosystemId: string, providerId: string): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.removeItem(keyFor(ecosystemId, providerId));
  } catch {
    // ignore
  }
}

/** The providers with a saved draft for this ecosystem. */
export function listDrafts(ecosystemId: string): { providerId: string }[] {
  if (typeof window === "undefined") return [];
  const prefix = ecosystemPrefix(ecosystemId);
  const out: { providerId: string }[] = [];
  try {
    const storage = window.localStorage;
    for (let i = 0; i < storage.length; i++) {
      const key = storage.key(i);
      if (!key || !key.startsWith(prefix)) continue;
      try {
        const raw = storage.getItem(key);
        if (!raw) continue;
        const parsed: unknown = JSON.parse(raw);
        if (isWrapper(parsed)) out.push({ providerId: parsed.providerId });
      } catch {
        // Skip a malformed entry rather than failing the whole listing.
      }
    }
  } catch {
    return out;
  }
  return out;
}
