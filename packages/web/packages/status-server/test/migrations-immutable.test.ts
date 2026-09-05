import { describe, it, expect } from 'vitest';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { MIGRATIONS_FOLDER } from '../src/libsql/client';
import journal from '../src/libsql/migrations/meta/_journal.json';
import pinnedHashes from './fixtures/migration-hashes.json';

// Applied migrations are immutable (see the repo CLAUDE.md): every entry below has
// already run against production, so editing its .sql in place would silently change
// history for hosts that migrated before the edit and diverge from hosts that migrate
// after it — a drift no test running against a fresh DB could ever observe, since a
// fresh DB only ever sees the CURRENT file. This pins each shipped migration's content
// by hash so an edit to an already-recorded file fails here instead of shipping.
//
// A NEW migration is added by appending both a `.sql` file and its hash to
// `test/fixtures/migration-hashes.json` in the same change — the loop below is driven
// by the journal (not the fixture), so a migration added without a pinned hash fails
// immediately rather than shipping unprotected.

const hashByTag = new Map(pinnedHashes.map((h) => [h.tag, h.sha256]));

describe('migrations are immutable once shipped', () => {
  for (const entry of journal.entries) {
    it(`${entry.tag} matches its pinned hash`, () => {
      const pinned = hashByTag.get(entry.tag);
      expect(pinned, `no pinned hash for ${entry.tag} — add one to test/fixtures/migration-hashes.json`).toBeDefined();

      const sql = readFileSync(join(MIGRATIONS_FOLDER, `${entry.tag}.sql`), 'utf8');
      const actual = createHash('sha256').update(sql).digest('hex');
      expect(actual, `${entry.tag}.sql has changed since it shipped — migrations are append-only, never edited`).toBe(
        pinned,
      );
    });
  }

  it('every pinned hash still names a migration the journal knows about', () => {
    // Catches the opposite drift: a stale fixture entry for a migration that was
    // renamed or removed, which would otherwise never fail (the loop above only
    // walks the journal).
    const journalTags = new Set(journal.entries.map((e) => e.tag));
    const orphaned = pinnedHashes.map((h) => h.tag).filter((tag) => !journalTags.has(tag));
    expect(orphaned).toEqual([]);
  });
});
