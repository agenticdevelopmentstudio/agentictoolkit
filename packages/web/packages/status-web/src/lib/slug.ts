/** Lowercase, hyphenate runs of non-alphanumerics, trim leading/trailing hyphens.
 * The one shared slug form for groups and sites. */
export function slugify(s: string): string {
  return s
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}
