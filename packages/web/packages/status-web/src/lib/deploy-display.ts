import type { DeployStatus } from "./deploy-status";
import { DEPLOY_COLORS } from "./colors";

// The platform taxonomy — glyph, brand color, and badge label for each deploy
// platform (plus the http/dns health checks). One module owns "what a platform
// looks like", so adding a platform is a single edit here.

/** Unicode glyph for a deploy platform (or "http"/"dns" for the health checks). */
export function platformGlyph(platform: string): string {
  if (platform === "vercel") return "▲";
  if (platform === "cloudflare-pages") return "☁";
  if (platform === "railway") return "⬢";
  if (platform === "http") return "◉";
  if (platform === "dns") return "⌖";
  if (platform === "crunchy") return "⛁"; // database
  // U+26A0 with VARIATION SELECTOR-15 (U+FE0E). Bare, the warning sign has an emoji
  // presentation default on macOS/iOS, so it would render full-colour and double-width
  // beside six monochrome glyphs. VS15 forces the text form.
  if (platform === "glitchtip") return "\u26a0\ufe0e"; // thrown errors
  return "◆";
}

// Platform/check badge colors use the shared theme's CATEGORICAL hues (apt-cat-*) — one
// distinct hue per platform/check, kept clear of the three ENV hues (blue/violet/pink) so a
// row showing both an env and a platform reads unambiguously. (cat-orange/purple match the
// CF/Railway brand hues.) The categorical palette is fully allocated, so crunchy deliberately
// reuses http's teal check-hue rather than getting a new token — see the PLATFORM_COLOR.crunchy
// comment below for why that reuse is safe.
const PLATFORM_COLOR: Record<string, string> = {
  vercel: "var(--color-apt-text)", // brand near-white
  "cloudflare-pages": "var(--color-apt-cat-orange)", // CF brand orange
  railway: "var(--color-apt-cat-purple)", // Railway brand purple
  http: "var(--color-apt-cat-teal)", // web health check
  dns: "var(--color-apt-cat-indigo)", // DNS resolution check
  crunchy: "var(--color-apt-cat-teal)", // shares http's check hue: cat palette is fully
                                        // allocated and must not collide with an ENV hue
                                        // (blue/violet/pink); teal avoids the env clash.
  glitchtip: "var(--color-apt-cat-orange)", // shares Cloudflare's hue, the same reuse
                                            // crunchy makes above and for the same reason:
                                            // every non-ENV cat hue is already allocated.
                                            // Orange over the others because it is the one
                                            // that reads as a warning, and the two never
                                            // sit in the same LIST — a glitchtip row is an
                                            // error incident, a cloudflare row is a deploy
                                            // — so the glyph and label disambiguate them.
};

/** Categorical theme hue for a platform's badge + glyph; muted for unknowns. */
export function platformColor(platform: string): string {
  return PLATFORM_COLOR[platform] ?? "var(--color-apt-text-muted)";
}

const PLATFORM_LABEL: Record<string, string> = {
  vercel: "VERCEL",
  "cloudflare-pages": "CLOUDFLARE",
  railway: "RAILWAY",
  http: "HTTP",
  dns: "DNS",
  crunchy: "CRUNCHY",
};

/** Display label for the service badge (hosting platform, or HTTP/DNS for the checks). */
export function platformLabel(platform: string): string {
  return PLATFORM_LABEL[platform] ?? platform.toUpperCase();
}

// Compact overrides for dense strips (e.g. the KPI bar) — full label otherwise.
const PLATFORM_LABEL_SHORT: Record<string, string> = {
  "cloudflare-pages": "CF",
  crunchy: "CB",
};

/** Compact platform label for tight layouts (e.g. "CF"); falls back to platformLabel. */
export function platformLabelShort(platform: string): string {
  return PLATFORM_LABEL_SHORT[platform] ?? platformLabel(platform);
}

/** CSS hex color for a deploy status dot / label. */
export function deployStatusColor(status: DeployStatus | string): string {
  return DEPLOY_COLORS[status] ?? DEPLOY_COLORS["canceled"]!;
}

/** Short text label for a deploy status. */
export function deployStatusLabel(status: DeployStatus | string): string {
  if (status === "success") return "ready";
  if (status === "failed") return "FAILED";
  if (status === "building") return "building";
  if (status === "queued") return "queued";
  if (status === "canceled") return "canceled";
  // An in-flight phase the backend expired unconfirmable — say so, don't echo the raw enum.
  if (status === "unknown") return "outcome unknown";
  return status;
}
