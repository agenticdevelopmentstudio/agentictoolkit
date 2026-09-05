// Monitor palette — every value references the shared ADH theme tokens (var(--color-apt-*))
// so the status board tracks the same theme as the rest of the suite. No hard-coded hex:
// a token's value is owned by @agentic-toolkit/themes, not copied here. Tints/glows apply alpha
// to a token via color-mix (the form the UI checker accepts). Shade changes vs the old
// bespoke values are intentional — the board now uses the canonical theme colors.
const GREEN = "var(--color-apt-green)"; // status: good       (= --color-success)
const YELLOW = "var(--color-apt-gold)"; // status: caution    (theme gold/amber)
const RED = "var(--color-apt-red)"; //     status: hard fail  (= --color-error)

export const HEALTH_COLORS: Record<string, string> = {
  healthy: GREEN,
  degraded: YELLOW,
  down: RED,
  unknown: YELLOW,
};

export const OVERALL_COLORS: Record<string, string> = {
  operational: GREEN,
  degraded: YELLOW,
  major_outage: RED,
  unknown: YELLOW,
};

export const DEPLOY_COLORS: Record<string, string> = {
  success: GREEN,
  failed: RED,
  building: YELLOW,
  queued: YELLOW,
  canceled: YELLOW,
  // An in-flight phase the backend expired unconfirmable — an ABSENCE of a verdict,
  // muted (never the amber of live progress). Matches row-model's `stale` RowTone.
  unknown: "var(--color-apt-text-muted)",
};

// Environment tag colors — a CATEGORICAL palette (3 distinct env hues that must read as
// "which env", never as a health signal). Uses the shared theme's CATEGORICAL hues
// (apt-cat-*, owned by @agentic-toolkit/themes) — distinct, theme-managed, and deliberately
// outside the status spectrum so an env badge never reads as a health signal. No collision
// with the platform badges (which use other apt-cat-* hues).
export const ENV_COLORS: Record<string, string> = {
  production: "var(--color-apt-cat-blue)",
  staging: "var(--color-apt-cat-violet)",
  testing: "var(--color-apt-cat-pink)",
};
export const ENV_FALLBACK_COLOR = "var(--color-apt-text-dim)";

export function envColor(env: string | null | undefined): string {
  return (env && ENV_COLORS[env]) || ENV_FALLBACK_COLOR;
}

// Short env badge text, paired with envColor for the env badge. Kept to 4 chars
// (upper-case) so the env column stays narrow.
const ENV_BADGE_LABEL: Record<string, string> = {
  production: "PROD",
  staging: "STAG",
  testing: "TEST",
};

/** Short env badge text ("PROD"/"STAG"/"TEST"); upper-cases unknowns. */
export function envBadgeLabel(env: string): string {
  return ENV_BADGE_LABEL[env] ?? env.toUpperCase();
}

// Core UI palette — all theme tokens.
export const PALETTE = {
  bg: "var(--color-apt-bg)",
  surface: "var(--color-apt-surface)",
  border: "var(--color-apt-border)",
  text: "var(--color-apt-text)",
  muted: "var(--color-apt-text-muted)",
  dim: "var(--color-apt-text-dim)",
  blue: "var(--color-apt-blue)",
  green: "var(--color-apt-green)",
  amber: "var(--color-apt-gold)",
  red: "var(--color-apt-red)",
} as const;

// Named roles mapped onto the theme's surface / border / text / status scale. The monitor
// had finer steps than the theme exposes (apt-bg < apt-surface < apt-surface-2); near
// steps collapse onto the nearest token.
export const COLORS = {
  // Border — the theme exposes a single outline level.
  border: "var(--color-apt-border)",

  // Surface steps (dark → light) — the theme exposes three levels.
  surfaceDeep: "var(--color-apt-bg)",
  surfaceMid: "var(--color-apt-surface)",
  surfacePane: "var(--color-apt-surface-2)",
  surfaceHover: "var(--color-apt-surface-2)",

  // Text variants
  textSoft: "color-mix(in srgb, var(--color-apt-text) 80%, var(--color-apt-text-muted))",
  textFaint: "var(--color-apt-text-muted)",

  // Status headline accent — only amber has a brighter role in the theme
  // (gold-bright); green/red have none, so their headline + road-sign use the
  // base PALETTE.green / PALETTE.red directly (no redundant same-value alias).
  amberLight: "var(--color-apt-gold-bright)",

  // Road-sign rim (StatusSign SVG outline)
  signRim: "var(--color-apt-text)",

  // Amber-tinted dark surfaces (DegradedBanner backgrounds)
  amberBgDeep: "color-mix(in srgb, var(--color-apt-gold) 8%, var(--color-apt-bg))",
  amberBgDeeper: "color-mix(in srgb, var(--color-apt-gold) 6%, var(--color-apt-bg))",
  amberBgMid: "color-mix(in srgb, var(--color-apt-gold) 30%, var(--color-apt-bg))",

  // Misc
  gold: "var(--color-apt-gold)",
  white: "white", // pure white for special cases (theme-independent)
  dimBlue: "var(--color-apt-text-dim)",
} as const;

// Semi-transparent tints — alpha applied to a theme token via color-mix (the alpha
// percentages mirror the old rgba opacities). Shadows stay black (theme-independent).
export const TINT = {
  // Amber (status: degraded / building)
  amberTint: "color-mix(in srgb, var(--color-apt-gold) 6%, transparent)",
  amberTintMed: "color-mix(in srgb, var(--color-apt-gold) 8%, transparent)",
  amberBg: "color-mix(in srgb, var(--color-apt-gold) 10%, transparent)",
  amberBgMed: "color-mix(in srgb, var(--color-apt-gold) 12%, transparent)",
  amberBgStrong: "color-mix(in srgb, var(--color-apt-gold) 18%, transparent)",
  amberBorder: "color-mix(in srgb, var(--color-apt-gold) 35%, transparent)",
  amberBorderStrong: "color-mix(in srgb, var(--color-apt-gold) 40%, transparent)",
  amberGlow: "color-mix(in srgb, var(--color-apt-gold) 45%, transparent)",

  // Red (status: error / failed)
  redBg: "color-mix(in srgb, var(--color-apt-red) 7%, transparent)",
  redBgMed: "color-mix(in srgb, var(--color-apt-red) 9%, transparent)",
  redBgStrong: "color-mix(in srgb, var(--color-apt-red) 16%, transparent)",
  redBorder: "color-mix(in srgb, var(--color-apt-red) 40%, transparent)",

  // Blue (status: building / info)
  blueBg: "color-mix(in srgb, var(--color-apt-blue) 7%, transparent)",
  blueBgMed: "color-mix(in srgb, var(--color-apt-blue) 14%, transparent)",

  // Black shadows / overlays (theme-independent)
  shadow: "color-mix(in srgb, black 45%, transparent)",
  shadowMed: "color-mix(in srgb, black 55%, transparent)",
  shadowStrong: "color-mix(in srgb, black 60%, transparent)",

  // White ghost
  whiteGhost: "color-mix(in srgb, white 2%, transparent)",
} as const;
