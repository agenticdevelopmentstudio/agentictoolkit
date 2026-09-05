// Display formatting — the single source for small string shapes that were
// otherwise copy-pasted across the fetchers, row builders, and config surfaces.

/** "1 site" / "3 sites" — count plus a correctly-pluralized noun. ONE definition
 *  so the banner, the Auto Configure summary, and the Config badges agree on copy. */
export function plural(n: number, singular: string, pluralForm = `${singular}s`): string {
  return `${n} ${n === 1 ? singular : pluralForm}`;
}

/** Short commit sha (GitHub's 7-char form), or null. */
export function shortSha(hash: string | null | undefined): string | null {
  return hash ? hash.slice(0, 7) : null;
}

/**
 * First line of a commit message, capped at `max` chars, or null. Commit
 * messages are "subject\n\nbody"; rows show only the subject.
 */
export function commitFirstLine(message: string | null | undefined, max = 200): string | null {
  if (!message) return null;
  const first = message.split("\n")[0] ?? "";
  return first.length > max ? first.slice(0, max) : first;
}
