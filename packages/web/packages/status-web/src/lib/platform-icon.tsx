import { Cloud, GitBranch, TrainFront, Triangle } from "lucide-react";
import type { ReactNode } from "react";

/** Canonical platform → brand-flavored icon with a theme-safe accent color.
 *  Colors are visible in both the HMDV cascade and the classic stack. */
const ICONS: Record<string, ReactNode> = {
  vercel: <Triangle size={16} aria-hidden className="text-apt-text" />,
  railway: <TrainFront size={16} aria-hidden className="text-violet-500 dark:text-violet-400" />,
  cloudflare: <Cloud size={16} aria-hidden className="text-orange-500 dark:text-orange-400" />,
  "cloudflare-pages": <Cloud size={16} aria-hidden className="text-orange-500 dark:text-orange-400" />,
  github: <GitBranch size={16} aria-hidden className="text-apt-text-muted" />,
  crunchy: <Cloud size={16} aria-hidden className="text-sky-500 dark:text-sky-400" />,
};

/** Icon for a deploy platform, or null when the platform is absent/unknown —
 *  the caller chooses its own fallback (Globe for site rows, Cloud for platform rows). */
export function platformIcon(platform: string | null | undefined): ReactNode | null {
  if (!platform) return null;
  return ICONS[platform.toLowerCase()] ?? null;
}
