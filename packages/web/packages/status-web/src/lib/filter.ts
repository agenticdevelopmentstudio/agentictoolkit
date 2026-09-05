/**
 * Case-insensitive, token-AND substring match. Every whitespace-separated token
 * in `query` must appear somewhere in `haystack`. An empty query matches all.
 */
export function matchesQuery(haystack: string, query: string): boolean {
  const q = query.trim().toLowerCase();
  if (!q) return true;
  const h = haystack.toLowerCase();
  return q.split(/\s+/).every((t) => h.includes(t));
}
