import { describe, it, expect } from 'vitest';
import {
  isRdid, buildRdid, parseRdid, tryParseRdid, prefixFor, validateLeaf, RDID_TYPES,
} from '@agentic-toolkit/adh-ui/rdid';

describe('rdid grammar', () => {
  it('accepts type-prefixed rdids and rejects legacy/invalid', () => {
    expect(isRdid('ecosystem.foo')).toBe(true);
    expect(isRdid('app.my-eco.my-app')).toBe(true);
    expect(isRdid('persona.bob')).toBe(true);
    expect(isRdid('com.agenticdeveloperhub')).toBe(false); // legacy reverse-domain
    expect(isRdid('persona')).toBe(false);                 // needs >= 2 segments
    expect(isRdid('app.My-App')).toBe(false);              // uppercase
    expect(isRdid('persona.bad_slug')).toBe(false);        // underscore
  });

  it('builds and parses round-trip', () => {
    expect(buildRdid({ type: 'persona', name: 'bob' })).toBe('persona.bob');
    expect(buildRdid({ type: 'app', scope: 'my-eco', name: 'cookbook' })).toBe('app.my-eco.cookbook');
    expect(parseRdid('app.my-eco.cookbook')).toEqual({ type: 'app', scope: 'my-eco', name: 'cookbook' });
    expect(parseRdid('persona.bob')).toEqual({ type: 'persona', scope: '', name: 'bob' });
  });

  it('buildRdid rejects a leaf that is not a single segment', () => {
    expect(() => buildRdid({ type: 'persona', name: 'a.b' })).toThrow();
    expect(() => buildRdid({ type: 'persona', name: 'Bad' })).toThrow();
  });

  it('tryParseRdid returns undefined on bad input instead of throwing', () => {
    expect(tryParseRdid('nope')).toBeUndefined();
    expect(tryParseRdid('persona.bob')).toEqual({ type: 'persona', scope: '', name: 'bob' });
  });

  it('prefixFor gives the fixed prefix (scoped and top-level)', () => {
    expect(prefixFor('ecosystem')).toBe('ecosystem.');
    expect(prefixFor('persona')).toBe('persona.');
    expect(prefixFor('app', 'my-eco')).toBe('app.my-eco.');
    expect(prefixFor('storage', 'my-eco')).toBe('storage.my-eco.');
  });

  it('validateLeaf enforces the segment rule (no underscore)', () => {
    expect(validateLeaf('cookbook')).toBeNull();
    expect(validateLeaf('my-app')).toBeNull();
    expect(validateLeaf('')).toMatch(/required/i);
    expect(validateLeaf('bad_slug')).toMatch(/hyphen|underscore|lowercase/i);
    expect(validateLeaf('-bad')).toMatch(/hyphen|underscore|lowercase/i);
  });

  // The set the backend declares, in the backend's order — `<adh-tools>/sites/scripts/verify-rdid-parity.py`
  // pins the two maps to each other as TEXT, and this pins the exported array to the same list so
  // a type that leaves one side cannot linger in the other. `game` was here until a game stopped
  // being something you address: it is now "the game of ecosystem X", reached through
  // `realm_config`, and it left the prefix map on both sides.
  it('RDID_TYPES is the fixed set', () => {
    expect(RDID_TYPES).toEqual([
      'org', 'user', 'ecosystem', 'storage', 'app', 'persona', 'token', 'integration',
    ]);
  });
});
