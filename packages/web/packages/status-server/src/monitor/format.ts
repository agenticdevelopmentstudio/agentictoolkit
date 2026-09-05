// Commit-display formatting — the single source for the sha-truncation and
// first-line extraction that was otherwise copy-pasted across the fetchers and
// the row builders.

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

/**
 * The full commit message (subject + body), with trailing whitespace stripped
 * and capped at `max` chars, or null. Unlike `commitFirstLine` this KEEPS
 * newlines so the details pane can show the whole "git comment"; the row still
 * derives the subject with `commitFirstLine`.
 */
export function commitFullMessage(message: string | null | undefined, max = 4000): string | null {
  if (!message) return null;
  const trimmed = message.replace(/\s+$/, "");
  if (!trimmed) return null;
  return trimmed.length > max ? trimmed.slice(0, max) : trimmed;
}
