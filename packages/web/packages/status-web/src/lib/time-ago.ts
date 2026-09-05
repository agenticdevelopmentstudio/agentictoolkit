/** Format elapsed time as a compact string. nowMs is passed in for testability. */
export function timeAgo(iso: string, nowMs: number): string {
  const diffMs = nowMs - new Date(iso).getTime();
  const diffSecs = Math.floor(diffMs / 1_000);
  if (diffSecs < 60) return "just now";
  const diffMins = Math.floor(diffSecs / 60);
  if (diffMins < 60) return `${diffMins}m`;
  const diffHours = Math.floor(diffMins / 60);
  if (diffHours < 24) return `${diffHours}h`;
  return `${Math.floor(diffHours / 24)}d`;
}
