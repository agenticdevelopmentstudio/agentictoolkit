import type { RateLimitTier, UpdateTierBody } from "../api/usage";

/**
 * The tier editor's gate: what a row's fields are called, how their text parses, and why Save
 * can't fire.
 *
 * Pure — nothing here touches React or the DOM — because the page's table is now read-only and
 * every one of these rules is exercised by the dialog instead. They used to live inline in the
 * page beside eight inline-editable cells, where the only way to test "blank means uncapped, never
 * zero" was to drive a table.
 */

/** Editable projection of a tier row. Numbers are drafted as strings; `""` on a quota = UNCAPPED. */
export type TierDraft = {
  quotaEnforced: boolean;
  quotaRequests: string;
  quotaBytes: string;
  quotaTokens: string;
  quotaCostMicros: string;
  quotaPeriodDays: string;
  rateCapacity: string;
  rateRefillTokens: string;
  rateRefillSeconds: string;
};

/** Caps that may be left blank, which the gate reads as UNCAPPED — never as zero. */
export const NULLABLE_FIELDS = [
  "quotaRequests",
  "quotaBytes",
  "quotaTokens",
  "quotaCostMicros",
] as const;
/** Counts a tier must always carry. Every one of them is meaningless below 1. */
export const REQUIRED_FIELDS = [
  "quotaPeriodDays",
  "rateCapacity",
  "rateRefillTokens",
  "rateRefillSeconds",
] as const;
/** The numeric fields, in table (and dialog) order. */
export const NUMERIC_FIELDS = [...NULLABLE_FIELDS, ...REQUIRED_FIELDS] as const;
export type NumericField = (typeof NUMERIC_FIELDS)[number];

/** How each numeric field is labelled, sized and explained. */
export const NUMERIC_SPEC: Record<
  NumericField,
  { header: string; width: string; placeholder: string; title: string }
> = {
  quotaRequests: {
    header: "Requests",
    width: "7rem",
    placeholder: "∞",
    title: "Requests allowed per period — blank is uncapped",
  },
  quotaBytes: {
    header: "Bytes",
    width: "8rem",
    placeholder: "∞",
    title: "HTTP request + response bytes per period — blank is uncapped",
  },
  quotaTokens: {
    header: "Tokens",
    width: "8rem",
    placeholder: "∞",
    title: "LLM input + output tokens per period — blank is uncapped",
  },
  quotaCostMicros: {
    header: "Cost µUSD",
    width: "8rem",
    placeholder: "∞",
    title: "Provider spend per period in micro-dollars — blank is uncapped",
  },
  quotaPeriodDays: {
    header: "Period (d)",
    width: "6.5rem",
    placeholder: "",
    title: "Length of the accounting window, in days",
  },
  rateCapacity: {
    header: "Burst",
    width: "6rem",
    placeholder: "",
    title: "Token-bucket capacity: requests allowed back-to-back",
  },
  rateRefillTokens: {
    header: "Refill",
    width: "6rem",
    placeholder: "",
    title: "Requests added back each refill interval",
  },
  rateRefillSeconds: {
    header: "Per (s)",
    width: "6rem",
    placeholder: "",
    title: "Length of the refill interval, in seconds",
  },
};

const text = (n: number | null): string => (n === null ? "" : String(n));

export function draftFrom(tier: RateLimitTier): TierDraft {
  return {
    quotaEnforced: tier.quotaEnforced,
    quotaRequests: text(tier.quotaRequests),
    quotaBytes: text(tier.quotaBytes),
    quotaTokens: text(tier.quotaTokens),
    quotaCostMicros: text(tier.quotaCostMicros),
    quotaPeriodDays: text(tier.quotaPeriodDays),
    rateCapacity: text(tier.rateCapacity),
    rateRefillTokens: text(tier.rateRefillTokens),
    rateRefillSeconds: text(tier.rateRefillSeconds),
  };
}

/** A count that must be there. Throws rather than PUTting nonsense. */
export function count(raw: string, label: string): number {
  const trimmed = raw.trim();
  const n = Number(trimmed);
  if (trimmed === "" || !Number.isInteger(n) || n < 1) {
    throw new Error(`${label} must be a whole number of 1 or more.`);
  }
  return n;
}

/** A blankable cap: `""` ⇒ null (uncapped). Zero is legal and means "refuse everything". */
export function optionalCount(raw: string, label: string): number | null {
  const trimmed = raw.trim();
  if (trimmed === "") return null;
  const n = Number(trimmed);
  if (!Number.isInteger(n) || n < 0) {
    throw new Error(`${label} must be a whole number of 0 or more, or blank for uncapped.`);
  }
  return n;
}

/** Field-by-field comparison — a draft is dirty when any one of the nine differs. */
export function isTierFormDirty(form: TierDraft, initial: TierDraft): boolean {
  if (form.quotaEnforced !== initial.quotaEnforced) return true;
  return NUMERIC_FIELDS.some((field) => form[field].trim() !== initial[field].trim());
}

/**
 * Only the fields the user actually touched, converted for the PUT. The two groups are walked
 * separately because they parse differently — and because within each group every key agrees on
 * whether null is allowed, which is what lets the write be a loop instead of eight assignments.
 */
export function bodyFrom(changes: Partial<TierDraft>): UpdateTierBody {
  const body: UpdateTierBody = {};
  if (changes.quotaEnforced !== undefined) body.quotaEnforced = changes.quotaEnforced;
  for (const field of NULLABLE_FIELDS) {
    const raw = changes[field];
    if (raw !== undefined) body[field] = optionalCount(raw, NUMERIC_SPEC[field].header);
  }
  for (const field of REQUIRED_FIELDS) {
    const raw = changes[field];
    if (raw !== undefined) body[field] = count(raw, NUMERIC_SPEC[field].header);
  }
  return body;
}

/** What CHANGED between two drafts — the patch the PUT carries, and nothing else. */
export function tierChanges(form: TierDraft, initial: TierDraft): Partial<TierDraft> {
  const changes: Partial<TierDraft> = {};
  if (form.quotaEnforced !== initial.quotaEnforced) changes.quotaEnforced = form.quotaEnforced;
  for (const field of NUMERIC_FIELDS) {
    if (form[field].trim() !== initial[field].trim()) changes[field] = form[field].trim();
  }
  return changes;
}

/**
 * WHY Save can't fire, or null when nothing is blocking.
 *
 * A reason rather than a boolean because the gate disables the button, which is exactly what makes
 * the submit path's throw unreachable — a greyed-out Save has to say what it is waiting on, and
 * "1 000" or "1.5" in a burst field looks perfectly typed until something explains it doesn't
 * parse. Only the CHANGED fields are checked: a stored value the operator never touched is not
 * theirs to answer for, and a row seeded with a zero-length period would otherwise be unsavable.
 */
export function tierFormBlockedReason(form: TierDraft, initial: TierDraft): string | null {
  try {
    bodyFrom(tierChanges(form, initial));
    return null;
  } catch (e) {
    return e instanceof Error ? e.message : String(e);
  }
}
