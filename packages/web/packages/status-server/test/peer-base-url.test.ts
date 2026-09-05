// The peer base-URL contract, tested where it is defined. Everything that writes a peer
// row — the /config routes, the MCP add_peer tool, the config store — goes through here,
// and the board's `web/src/lib/peer-url.ts` mirrors it for client-side feedback.
import { describe, it, expect } from 'vitest';
import {
  DUPLICATE_PEER_MESSAGE,
  isDuplicatePeerError,
  isSamePeerBaseUrl,
  isValidPeerBaseUrl,
  normalizePeerBaseUrl,
} from '../src/peers/base-url';

describe('normalizePeerBaseUrl', () => {
  it('trims whitespace and strips every trailing slash', () => {
    expect(normalizePeerBaseUrl('  https://b.example.com/// ')).toBe('https://b.example.com');
  });

  // uniq_peer_base_url is byte-exact, so anything that varies WITHOUT changing which
  // monitor is meant has to fold away here or the same peer is addable twice.
  it('folds case, the default port, and query/fragment into one canonical form', () => {
    const canonical = 'https://b.example.com';
    expect(normalizePeerBaseUrl('HTTPS://B.Example.COM')).toBe(canonical);
    expect(normalizePeerBaseUrl('https://b.example.com:443')).toBe(canonical);
    expect(normalizePeerBaseUrl('https://b.example.com/?x=1#frag')).toBe(canonical);
    expect(normalizePeerBaseUrl('http://b.example.com:80')).toBe('http://b.example.com');
  });

  it('keeps a non-default port and a path — both name a different monitor', () => {
    expect(normalizePeerBaseUrl('http://localhost:3000/')).toBe('http://localhost:3000');
    expect(normalizePeerBaseUrl('https://b.example.com/status/')).toBe('https://b.example.com/status');
  });

  it('leaves an unparseable string trimmed rather than throwing', () => {
    expect(normalizePeerBaseUrl('  b.example.com/ ')).toBe('b.example.com');
  });
});

describe('isValidPeerBaseUrl', () => {
  it('accepts absolute http(s) URLs, canonical or not', () => {
    expect(isValidPeerBaseUrl('https://b.example.com')).toBe(true);
    expect(isValidPeerBaseUrl('  https://b.example.com/ ')).toBe(true);
    expect(isValidPeerBaseUrl('http://localhost:3000')).toBe(true);
  });

  it('rejects a bare host, a relative path, the empty string, and non-http schemes', () => {
    for (const bad of ['b.example.com', '/relative', '', 'ftp://b.example.com', 'javascript:alert(1)', 'file:///etc/passwd']) {
      expect(isValidPeerBaseUrl(bad), bad).toBe(false);
    }
  });
});

describe('isSamePeerBaseUrl', () => {
  it('compares canonically, so a monitor cannot slip past the self-check by respelling', () => {
    expect(isSamePeerBaseUrl('https://self.example.com', 'https://SELF.example.com:443/')).toBe(true);
    expect(isSamePeerBaseUrl('https://self.example.com', 'https://other.example.com')).toBe(false);
    // Same host, different scheme is a different endpoint — not the same monitor.
    expect(isSamePeerBaseUrl('https://self.example.com', 'http://self.example.com')).toBe(false);
  });
});

describe('isDuplicatePeerError', () => {
  it('recognizes the unique-constraint violation however deep the driver wrapped it', () => {
    expect(isDuplicatePeerError({ code: 'SQLITE_CONSTRAINT_UNIQUE' })).toBe(true);
    expect(isDuplicatePeerError(new Error('UNIQUE constraint failed: peers.base_url'))).toBe(true);
    const wrapped = new Error('write failed', { cause: { code: 'SQLITE_CONSTRAINT_UNIQUE' } });
    expect(isDuplicatePeerError(wrapped)).toBe(true);
  });

  // The narrowing is the point: a NOT NULL violation or a connection failure answered
  // with 409 "already exists" would send the operator hunting for a peer that isn't there.
  it('does not claim unrelated failures are duplicates', () => {
    expect(isDuplicatePeerError(new Error('SQLITE_CONSTRAINT_NOTNULL'))).toBe(false);
    expect(isDuplicatePeerError(new Error('connection refused'))).toBe(false);
    expect(isDuplicatePeerError(null)).toBe(false);
    expect(isDuplicatePeerError(undefined)).toBe(false);
  });

  it('exposes one message so the route and the MCP tool cannot drift apart', () => {
    expect(DUPLICATE_PEER_MESSAGE).toMatch(/already exists/i);
  });
});
