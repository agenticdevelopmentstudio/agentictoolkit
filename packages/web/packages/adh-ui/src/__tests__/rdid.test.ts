import { describe, it, expect } from 'vitest'
import {
  buildRdid,
  parseRdid,
  isRdid,
  prefixFor,
  rdidPrefix,
  tryParseRdid,
  validateLeaf,
  type RdidParts,
} from '../lib/rdid'

// GOLDEN ROUND-TRIP VECTORS for the rdid grammar this package owns.
//
// The rdid grammar has two implementations that must agree exactly: this one and adh's
// backend (`backend/src/adh/src/lib/rdid.ts`). Those two are pinned against each other by
// `<adh-tools>/sites/scripts/verify-rdid-parity.py`, which reads BOTH files as TEXT — the backend
// module imports hono, so it can never be loaded into a test environment, and this package
// lives in a submodule that must not reach into adh at all.
//
// Text matching can only pin CONSTANTS. It cannot see a function body diverge: a changed
// join, an inverted branch, a different error message inside buildRdid/parseRdid/isRdid
// would leave every pinned literal byte-identical. That gap is what this file closes, from
// the side that can actually import the code. The backend keeps the mirror-image vectors in
// its own suite, over the identical `<type>.<scope>.<name>` grammar these exercise: segment
// shape, the scope-vs-leaf split, and reject-on-malformed.

const VALID_VECTORS: readonly { readonly parts: RdidParts; readonly rdid: string }[] = [
  { parts: { type: 'persona', scope: 'acme', name: 'bob' }, rdid: 'persona.acme.bob' },
  { parts: { type: 'app', scope: 'acme', name: 'cookbook' }, rdid: 'app.acme.cookbook' },
  { parts: { type: 'ecosystem', name: 'acme' }, rdid: 'ecosystem.acme' },
  { parts: { type: 'storage', name: 'acme' }, rdid: 'storage.acme' },
  { parts: { type: 'storage', scope: 'acme', name: 'docs' }, rdid: 'storage.acme.docs' },
]

// A legacy reverse-domain id (no rdid type prefix), a bare type with no leaf, an uppercase/
// underscore leaf, an empty interior segment, and an edge-hyphen segment.
const INVALID_RDIDS: readonly string[] = [
  'com.example',
  'persona.',
  'persona.Bad_slug',
  'persona..x',
  'persona.-x.y',
]

describe('rdid golden vectors — buildRdid/parseRdid/isRdid behavior', () => {
  it.each(VALID_VECTORS)('builds, validates, and round-trips $rdid', ({ parts, rdid }) => {
    expect(buildRdid(parts)).toBe(rdid)
    expect(isRdid(rdid)).toBe(true)
    expect(parseRdid(rdid)).toEqual({
      type: parts.type,
      scope: (parts.scope ?? '').trim(),
      name: parts.name,
    })
  })

  it.each(INVALID_RDIDS)('rejects %j: isRdid is false and parseRdid throws', (value) => {
    expect(isRdid(value)).toBe(false)
    expect(() => parseRdid(value)).toThrow()
  })

  it('tryParseRdid is the non-throwing parseRdid', () => {
    expect(tryParseRdid('app.acme.cookbook')).toEqual({ type: 'app', scope: 'acme', name: 'cookbook' })
    expect(tryParseRdid('com.example')).toBeUndefined()
    expect(tryParseRdid(null)).toBeUndefined()
  })
})

describe('validateLeaf — the editable leaf check', () => {
  // The backend mint boundary and this client-side check must accept and reject the SAME
  // set: both funnel through SEGMENT_RE, and the parity guard pins that both still do and
  // that the two messages are identical. What it cannot pin is the behaviour, so that is here.
  it('accepts a well-formed segment', () => {
    expect(validateLeaf('ci-sync')).toBeNull()
    expect(validateLeaf('a')).toBeNull()
    expect(validateLeaf('a1')).toBeNull()
  })

  it('rejects empty, uppercase, underscores, and edge hyphens', () => {
    expect(validateLeaf('')).toBe('Required.')
    expect(validateLeaf('Bad_Name')).not.toBeNull()
    expect(validateLeaf('-lead')).not.toBeNull()
    expect(validateLeaf('trail-')).not.toBeNull()
    // A dot is a SEPARATOR, never part of a leaf — a leaf that smuggled one in would
    // silently become an extra scope level in the assembled rdid.
    expect(validateLeaf('a.b')).not.toBeNull()
  })
})

describe('prefix helpers — the static text an editor shows beside the leaf field', () => {
  it('prefixFor includes the scope only when there is one', () => {
    expect(prefixFor('persona', 'acme')).toBe('persona.acme.')
    expect(prefixFor('ecosystem')).toBe('ecosystem.')
    expect(prefixFor('storage', '  ')).toBe('storage.')
  })

  it('rdidPrefix derives the same prefix from a saved id, and empties for a draft', () => {
    expect(rdidPrefix('persona.acme.bob')).toBe('persona.acme.')
    expect(rdidPrefix('ecosystem.acme')).toBe('ecosystem.')
    // A new, unsaved draft has no id yet and falls back to a plain, unprefixed leaf field.
    expect(rdidPrefix(null)).toBe('')
    expect(rdidPrefix('')).toBe('')
    expect(rdidPrefix('com.example')).toBe('')
  })
})
