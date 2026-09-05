// Framework-free rdid grammar — a FRONTEND MIRROR of adh's `backend/src/adh/src/lib/rdid.ts`.
// No React, no Hono. An rdid is `<type>.<scope>.<name>`; <type>+<scope> are fixed/inherited,
// only the leaf <name> is editable.
//
// Kept in lockstep with the backend by `<adh-tools>/sites/scripts/verify-rdid-parity.py`, which
// reads BOTH files as TEXT and pins the prefix map (values AND declaration order), the two
// regex literals, the length cap, and validateLeaf's messages. It cannot live on either
// side: the backend module imports hono so it can never be loaded into a test environment,
// and this package is a submodule that must not reach into adh. The guard's counterpart —
// the behaviour of buildRdid/parseRdid/isRdid, which text matching cannot see diverge —
// is pinned by golden vectors in `src/__tests__/rdid.test.ts`.

export const RDID_TYPE_TO_ENTITY_TYPE = {
  // Principals. `org.<slug>` and `user.<ecosystem path>.<slug>` are the addresses of the
  // organization / customer rows themselves. Mirrors the backend map — kept first, in the
  // same order the backend declares them.
  org: 'organization',
  user: 'customer',
  ecosystem: 'ecosystem',
  storage: 'bucket',
  app: 'application',
  persona: 'persona',
  token: 'token',
  // integration instances (integration_provider_configs) are rdid-addressed like apps/personas:
  // `integration.<ecosystem-slug>.<name>` (entity_type 'integration'). Mirrors the backend map.
  integration: 'integration',
} as const;

export type RdidType = keyof typeof RDID_TYPE_TO_ENTITY_TYPE;
export const RDID_TYPES = Object.keys(RDID_TYPE_TO_ENTITY_TYPE) as RdidType[];

export const IDENTIFIER_MAX_LENGTH = 255;

// A single dotted segment: lowercase alphanumeric, hyphens interior-only.
export const SEGMENT_RE = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/;

// A full type-prefixed rdid: a known prefix + one-or-more well-formed segments (>= 2 segments).
export const RDID_RE = new RegExp(
  `^(?:${RDID_TYPES.join('|')})(?:\\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$`,
);

export interface ParsedRdid { type: RdidType; scope: string; name: string; }
export interface RdidParts { type: RdidType; scope?: string; name: string; }

export function isRdid(value: unknown): value is string {
  return (
    typeof value === 'string' &&
    value.length > 0 &&
    value.length <= IDENTIFIER_MAX_LENGTH &&
    RDID_RE.test(value)
  );
}

export function buildRdid(parts: RdidParts): string {
  const scope = (parts.scope ?? '').trim();
  const segments = [...(scope ? scope.split('.') : []), parts.name];
  for (const seg of segments) {
    if (!SEGMENT_RE.test(seg)) {
      throw new Error(`rdid segment ${JSON.stringify(seg)} must be lowercase alphanumeric with interior hyphens only`);
    }
  }
  const rdid = [parts.type, scope, parts.name].filter(Boolean).join('.');
  if (!isRdid(rdid)) throw new Error(`invalid rdid: ${rdid}`);
  return rdid;
}

export function parseRdid(value: string): ParsedRdid {
  if (!isRdid(value)) throw new Error(`invalid rdid: ${value}`);
  const segments = value.split('.');
  return {
    type: segments[0] as RdidType,
    scope: segments.slice(1, -1).join('.'),
    // Non-null: the preceding isRdid check guarantees RDID_RE matched, so segments has
    // >= 2 entries (this package's tsconfig has noUncheckedIndexedAccess, unlike the
    // backend mirror, so the index access needs the assertion here).
    name: segments[segments.length - 1]!,
  };
}

export function tryParseRdid(value: unknown): ParsedRdid | undefined {
  return isRdid(value) ? parseRdid(value) : undefined;
}

/**
 * The fixed inherited prefix (up to and including the final dot) so an editor can show it as
 * static text and let the user type only the leaf. Scoped kinds pass a scope; top-level kinds
 * (`ecosystem`, `persona`) pass none. The legacy `org.` prefix is not an rdid type — callers
 * pass that literal string to the editor directly.
 */
export function prefixFor(type: RdidType, scope?: string): string {
  const s = (scope ?? '').trim();
  return s ? `${type}.${s}.` : `${type}.`;
}

/** Validate an editable leaf (one segment). Returns an error message or null. */
export function validateLeaf(leaf: string): string | null {
  if (!leaf) return 'Required.';
  if (!SEGMENT_RE.test(leaf)) {
    return 'Lowercase letters, digits, and interior hyphens only (no underscores).';
  }
  return null;
}

/**
 * The fixed inherited prefix of a SAVED entity's own rdid (up to and including the final dot) —
 * e.g. `persona.acme.` for `persona.acme.bob` — so an editor can show it as static text and let
 * the user type only the leaf (built from {@link parseRdid} + {@link prefixFor}, so it stays in
 * lockstep with the grammar). `""` for a non-rdid or empty/nullish `id` — including a new,
 * unsaved draft, which has no id yet and falls back to a plain, unprefixed leaf field.
 */
export function rdidPrefix(id: string | null | undefined): string {
  if (!id || !isRdid(id)) return '';
  const { type, scope } = parseRdid(id);
  return prefixFor(type, scope);
}
