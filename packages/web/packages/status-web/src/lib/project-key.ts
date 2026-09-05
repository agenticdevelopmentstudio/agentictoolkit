/**
 * The stable identity key for a deploy project: `${platform}|${projectName}`, using
 * the RAW (un-canonicalized) platform — the same value carried in DeployProject and
 * persisted as an ignored-project row. Single source of truth so the key the review
 * modal builds its ignore Set from is byte-identical to the key the provider tests it
 * against (a separator/field drift would otherwise silently make every ignore a no-op).
 */
export const projectKeyOf = (p: { platform: string; projectName: string }): string => `${p.platform}|${p.projectName}`;

/**
 * Collapse entries sharing a (platform, projectName) to the FIRST-seen one. Railway
 * enumerates one deploy-project entry PER environment (production/staging/testing), so
 * surfaces that treat a project as a single unit — the manual "Set Platform Project"
 * picker (env comes from the endpoint, not the project) and the project-level ignore
 * review — collapse to one row per project with this. First-seen wins, and the backend
 * orders a project's envs production-first, so the kept entry carries the production
 * representative domain.
 */
export function uniqueByProject<T extends { platform: string; projectName: string }>(entries: T[]): T[] {
  const seen = new Set<string>();
  return entries.filter((p) => {
    const k = projectKeyOf(p);
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
}
