import { Hono } from 'hono';
import { HTTPException } from 'hono/http-exception';
import type { Db } from '../libsql/client';
import type { StatusConfig } from '../config/port';
import { createActivityPageReader, MAX_ACTIVITY_ROWS, type ActivityCursor } from '../board';

/**
 * The largest instant `new Date()` represents. Past it every `Date` is Invalid, and drizzle
 * turns an Invalid Date into `Math.floor(NaN / 1000)` — which `@libsql/client` rejects with
 * a RangeError, i.e. a 500 for what is plainly a malformed request.
 */
const MAX_CURSOR_MS = 8.64e15;

export function activityRoutes(db: Db, config: StatusConfig) {
  const app = new Hono();
  const readPage = createActivityPageReader(db, config);

  /**
   * One page of the activity feed, older than the given cursor.
   *
   * `GET /board` still carries the NEWEST page as `board.activity` — that is the live tail
   * and it is unchanged. This route exists only for scrolling BACK, so it is a cold path:
   * nothing polls it and no SSE publish touches it.
   *
   * The cursor is the (atMs, id) PAIR because a deployment's build and deploy rows share a
   * timestamp. Both halves are required together; half a cursor is a client bug, and
   * answering it with the newest page would silently restart the scroll at the top.
   */
  app.get('/activity', async (c) => {
    const beforeRaw = c.req.query('before');
    const beforeIdRaw = c.req.query('beforeId');

    if ((beforeRaw == null) !== (beforeIdRaw == null)) {
      // `HTTPException`, not a hand-built `c.json({ error: '<string>' })`: `app.onError`
      // renders every error in this service as `{ error: { message } }`, and a route that
      // spells its own 400 differently makes the client's error handling a per-route guess.
      throw new HTTPException(400, { message: 'before and beforeId must be supplied together' });
    }
    let cursor: ActivityCursor | null = null;
    if (beforeRaw != null && beforeIdRaw != null) {
      const atMs = Number(beforeRaw);
      // An empty `beforeId` is NOT malformed: `pageActivity`'s stall escape mints exactly
      // `{ atMs, id: "" }` as the next cursor when a page keeps nothing — stepping back
      // with an empty id is the only cursor that makes progress. Rejecting it here would
      // 400 a page this same route minted, wedging the reader on one page forever.
      //
      // An empty `before` IS malformed, and `Number.isFinite` alone does not say so:
      // `Number('')` and `Number(' ')` are both 0, which reads as "everything before the
      // epoch" — three empty reads, and a client that latches `exhausted` for the session
      // on the first stray request. The range check is what keeps a huge value out of
      // drizzle's `Date`; see MAX_CURSOR_MS.
      if (beforeRaw.trim() === '' || !Number.isSafeInteger(atMs) || atMs < 0 || atMs > MAX_CURSOR_MS) {
        throw new HTTPException(400, { message: 'malformed cursor' });
      }
      cursor = { atMs, id: beforeIdRaw };
    }

    const limitRaw = Number(c.req.query('limit') ?? MAX_ACTIVITY_ROWS);
    const limit = Number.isFinite(limitRaw)
      ? Math.min(Math.max(Math.trunc(limitRaw), 1), MAX_ACTIVITY_ROWS)
      : MAX_ACTIVITY_ROWS;

    return c.json(await readPage(Date.now(), { cursor, limit }));
  });

  return app;
}
