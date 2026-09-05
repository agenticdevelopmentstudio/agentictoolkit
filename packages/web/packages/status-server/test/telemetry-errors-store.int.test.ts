import { describe, it, expect, beforeEach } from 'vitest';
import { eq } from 'drizzle-orm';
import * as schema from '../src/libsql/schema';
import type { Db } from '../src/libsql/client';
import { errorsStore } from '../src/telemetry/stores/errors';
import type { ErrorDTO } from '../src/telemetry/types';
import { freshDb as bootDb } from './helpers/db';

// `errorsStore.save` is a RECONCILIATION of the whole `is:unresolved` set, not an append —
// and until the sweep existed nothing in this codebase ever wrote `resolved = true`, so
// every error ever fetched stayed open forever and a Problem built on this table could go
// red and never go green. These pin the half that closes the loop.
//
// Integration rather than unit: the reconciliation IS the SQL. The interesting cases are an
// empty `notInArray` (which drizzle compiles to `not in ()`, a SQLite syntax error) and the
// `excluded.resolved` reopen inside an upsert — neither survives a fake db.

function err(over: Partial<ErrorDTO> = {}): ErrorDTO {
  return {
    id: 'gt-1',
    issueKey: 'gt-1',
    project: 'adh',
    title: 'TypeError: undefined is not a function',
    culprit: 'app/page.tsx',
    level: 'error',
    count: 7,
    userCount: 3,
    firstSeen: '2026-06-01T00:00:00.000Z',
    lastSeen: '2026-06-02T00:00:00.000Z',
    permalink: 'https://glitchtip.example/issues/1',
    ...over,
  };
}

describe('errorsStore.save reconciles the unresolved set', () => {
  let db: Db;
  beforeEach(async () => {
    db = await bootDb();
  });

  /** Every row, resolved or not — `load()` only returns the open ones. */
  async function allRows() {
    const rows = await db.select().from(schema.errors);
    return new Map(rows.map((r) => [r.issueKey, r]));
  }

  it('stores a poll and serves it back', async () => {
    await errorsStore.save(db, [err(), err({ id: 'gt-2', issueKey: 'gt-2', title: 'boom' })]);
    const loaded = await errorsStore.load(db);
    expect(loaded.map((e) => e.issueKey).sort()).toEqual(['gt-1', 'gt-2']);
    expect(loaded.find((e) => e.issueKey === 'gt-1')).toMatchObject({
      project: 'adh', count: 7, userCount: 3, level: 'error',
    });
  });

  it('updates an issue that is still present rather than duplicating it', async () => {
    await errorsStore.save(db, [err({ count: 7 })]);
    await errorsStore.save(db, [err({ count: 19, title: 'TypeError: still broken' })]);
    const loaded = await errorsStore.load(db);
    expect(loaded).toHaveLength(1);
    expect(loaded[0]).toMatchObject({ issueKey: 'gt-1', count: 19, title: 'TypeError: still broken' });
  });

  // THE BUG. Resolving an issue in GlitchTip removes it from `is:unresolved`, so the only
  // evidence we get is its absence — and absence used to mean "leave it exactly as it was".
  it('resolves an issue that VANISHED from the next poll, keeping the row', async () => {
    await errorsStore.save(db, [err(), err({ id: 'gt-2', issueKey: 'gt-2' })]);
    await errorsStore.save(db, [err({ id: 'gt-2', issueKey: 'gt-2' })]);

    expect((await errorsStore.load(db)).map((e) => e.issueKey)).toEqual(['gt-2']);
    // Resolved, not deleted: the history is what `/errors` and the ledger read back.
    const rows = await allRows();
    expect(rows.get('gt-1')?.resolved).toBe(true);
    expect(rows.get('gt-2')?.resolved).toBe(false);
  });

  // The case the old early-return made unreachable, and the reason a cleared error board
  // was permanent. Also the case `notInArray` cannot express — an empty list compiles to
  // `not in ()`, which SQLite rejects — so it takes its own branch in `resolveVanished`.
  it('an EMPTY poll resolves everything still open', async () => {
    await errorsStore.save(db, [err(), err({ id: 'gt-2', issueKey: 'gt-2' })]);
    await errorsStore.save(db, []);
    expect(await errorsStore.load(db)).toEqual([]);
    expect([...(await allRows()).values()].every((r) => r.resolved)).toBe(true);
  });

  it('an empty poll against an empty table is a no-op, not an error', async () => {
    await errorsStore.save(db, []);
    expect(await errorsStore.load(db)).toEqual([]);
  });

  // `excluded.resolved` in the upsert's set-list. A bug that comes back has to come back
  // to the BOARD, not stay invisible behind the resolution it earned last week.
  it('REOPENS a swept issue when it fires again', async () => {
    await errorsStore.save(db, [err()]);
    await errorsStore.save(db, []);
    expect(await errorsStore.load(db)).toEqual([]);

    await errorsStore.save(db, [err({ count: 40, lastSeen: '2026-06-09T00:00:00.000Z' })]);
    const loaded = await errorsStore.load(db);
    expect(loaded).toHaveLength(1);
    expect(loaded[0]).toMatchObject({ issueKey: 'gt-1', count: 40 });
    expect((await allRows()).get('gt-1')?.resolved).toBe(false);
  });

  // `fetchedAt` records when a row was last SEEN in a poll, and a swept row's defining
  // property is that it wasn't — so the sweep must not restamp it. If it did, "last seen
  // by the monitor" would read as `now` for every issue the monitor has stopped seeing.
  it('does not restamp fetchedAt on the rows it sweeps', async () => {
    await errorsStore.save(db, [err()]);
    const before = (await allRows()).get('gt-1')!.fetchedAt;

    // `fetchedAt` is a second-resolution unixepoch default, so a same-second sweep would
    // compare equal whether or not it restamped. Age the row instead of sleeping — floored
    // to a whole second, because a sub-second Date round-trips through the column as a
    // DIFFERENT instant and the assertion below compares milliseconds.
    const aged = new Date(Math.floor((Date.now() - 3600_000) / 1000) * 1000);
    await db.update(schema.errors).set({ fetchedAt: aged }).where(eq(schema.errors.issueKey, 'gt-1'));
    await errorsStore.save(db, []);

    const after = (await allRows()).get('gt-1')!.fetchedAt;
    expect(after?.getTime()).toBe(aged.getTime());
    expect(after?.getTime()).not.toBe(before?.getTime());
  });

  it('reconciles per issue, not per project — one project can gain and lose issues at once', async () => {
    await errorsStore.save(db, [err({ id: 'a', issueKey: 'a' }), err({ id: 'b', issueKey: 'b' })]);
    await errorsStore.save(db, [err({ id: 'b', issueKey: 'b' }), err({ id: 'c', issueKey: 'c' })]);
    expect((await errorsStore.load(db)).map((e) => e.issueKey).sort()).toEqual(['b', 'c']);
    expect((await allRows()).get('a')?.resolved).toBe(true);
  });
});


describe('errorsStore.save on a TRUNCATED poll', () => {
  let db: Db;
  beforeEach(async () => {
    db = await bootDb();
  });

  async function allRows() {
    const rows = await db.select().from(schema.errors);
    return new Map(rows.map((r) => [r.issueKey, r]));
  }

  // The sweep's second precondition: the answer has to be WHOLE. GlitchTip's issues
  // endpoint is paginated and the fetcher asks for one page, so a full page is presumed
  // truncated. Sweeping a page resolves everything past its edge — and the next poll
  // reopens it, so a project whose issues straddle the boundary would flap open/closed
  // every cycle, paging a recovery and then an outage, forever.
  it('upserts what it saw and sweeps NOTHING', async () => {
    await errorsStore.save(db, [err({ id: 'a', issueKey: 'a' }), err({ id: 'b', issueKey: 'b' })]);
    await errorsStore.save(db, [err({ id: 'a', issueKey: 'a', count: 99 })], { complete: false });

    // `b` is absent from the second poll — but the poll never claimed to be the whole set.
    expect((await errorsStore.load(db)).map((e) => e.issueKey).sort()).toEqual(['a', 'b']);
    expect((await allRows()).get('b')?.resolved).toBe(false);
    // What it DID see is still recorded.
    expect((await allRows()).get('a')?.count).toBe(99);
  });

  it('sweeps again as soon as a whole answer arrives', async () => {
    await errorsStore.save(db, [err({ id: 'a', issueKey: 'a' }), err({ id: 'b', issueKey: 'b' })]);
    await errorsStore.save(db, [err({ id: 'a', issueKey: 'a' })], { complete: false });
    await errorsStore.save(db, [err({ id: 'a', issueKey: 'a' })], { complete: true });
    expect((await errorsStore.load(db)).map((e) => e.issueKey)).toEqual(['a']);
  });

  // An omitted `opts` is a whole answer — every other fetcher in this codebase returns one
  // by construction, and defaulting the other way would silently disable the sweep.
  it('treats an omitted option as a whole answer', async () => {
    await errorsStore.save(db, [err()]);
    await errorsStore.save(db, []);
    expect(await errorsStore.load(db)).toEqual([]);
  });
});

describe('errorsStore.save keeps `project` current', () => {
  let db: Db;
  beforeEach(async () => {
    db = await bootDb();
  });

  // `project` used to be a display field and was left out of the upsert's set-list. It is
  // now IDENTITY — the board mints `errors|<project>` from it — and the conflict target is
  // `issueKey`, so a stored slug that stopped tracking the provider's would keep deriving a
  // target no fact mentions (its ledger row unclosable) while issues under the new slug
  // opened a second, simultaneous problem for the same app.
  it('refreshes the project when the issue moves or the project is renamed', async () => {
    await errorsStore.save(db, [err({ project: 'adh' })]);
    await errorsStore.save(db, [err({ project: 'adh-web' })]);
    const loaded = await errorsStore.load(db);
    expect(loaded).toHaveLength(1);
    expect(loaded[0]).toMatchObject({ issueKey: 'gt-1', project: 'adh-web' });
  });
});
