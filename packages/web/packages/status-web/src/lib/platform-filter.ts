// The Sites config list's Platform filter taxonomy — extracted as a pure function so
// the option rows (and the "all" reset set) are unit-testable and can't silently drop
// a platform. The bug this owns: a purely data-driven list only showed platforms
// PRESENT among endpoints, so `railway` vanished from the filter whenever no site was
// wired to a railway project (which is the steady state — railway hosts backends, not
// the monitored frontends). The known platforms are now ALWAYS offered.
import { PLATFORMS } from "../api/monitored-sites";
import type { MultiSelectOption } from "../components/MultiSelectFilter";

/** Sentinel key for an endpoint with no hosting platform set (an unwired site), so it
 *  stays a selectable filter row rather than being silently dropped from "all". */
export const PLATFORM_NONE = "__none__";

/** The set the platform filter treats as "all selected" — every known platform plus
 *  the "no platform" bucket — so the "all" reset can never omit one. */
export const allPlatformKeys = (): Set<string> => new Set<string>([...PLATFORMS, PLATFORM_NONE]);

/**
 * The platform filter's option rows for a given set of monitored endpoints. The KNOWN
 * platforms (`PLATFORMS`) are ALWAYS offered, in their canonical order, even when zero
 * endpoints use one today — so e.g. `railway` stays filterable before any railway site
 * is wired. After the known platforms come any UNKNOWN platform value actually present
 * (legacy/odd data), then a trailing "no platform" row only when some endpoint is
 * unwired (that bucket is meaningful as a filter only when such sites exist).
 */
export function platformFilterOptions(endpoints: { platform: string | null }[]): MultiSelectOption[] {
  const present = new Set(endpoints.map((e) => e.platform ?? PLATFORM_NONE));
  const opts: MultiSelectOption[] = [];
  for (const p of PLATFORMS) opts.push({ key: p, label: p });
  for (const k of present) {
    if (k !== PLATFORM_NONE && !(PLATFORMS as readonly string[]).includes(k)) opts.push({ key: k, label: k });
  }
  if (present.has(PLATFORM_NONE)) opts.push({ key: PLATFORM_NONE, label: "no platform" });
  return opts;
}
