export function hostOf(url: string): string {
  try {
    return new URL(url).host;
  } catch {
    return url;
  }
}

/**
 * The platform PROJECT page for a deploy URL — so clicking a project name always
 * lands on the same place, regardless of which specific deploy the row is about.
 * Vercel inspector URLs are `…/<team>/<project>/<deployId>`; drop the deploy id.
 * Other platforms / unrecognised URLs pass through unchanged.
 */
export function projectPageUrl(url: string | null | undefined): string | null {
  if (!url) return null;
  try {
    const u = new URL(url);
    if (u.hostname === "vercel.com") {
      const parts = u.pathname.split("/").filter(Boolean); // [team, project, deployId, …]
      if (parts.length >= 3) return `${u.origin}/${parts[0]}/${parts[1]}`;
    }
    return url;
  } catch {
    return url;
  }
}
