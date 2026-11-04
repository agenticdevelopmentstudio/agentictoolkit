import type { CSSProperties, ReactNode } from 'react'

export type SiteLandingProps = {
  /** Small uppercase mono line above the title (e.g. the site's tagline). */
  eyebrow: string
  /** Non-accented lead of the headline. Defaults to "Agentic Developer". */
  titleLead?: string
  /** The accented (gold, italic) word(s) ending the headline. */
  titleAccent: string
  /** Body copy under the headline. */
  blurb: ReactNode
}

// Renders against the shared theme tokens, but every token carries a fallback so
// the hero looks right even before/without <AdhThemeStyle/> (consumer sites keep
// no local palette).
//
// The type below reads the shared LANDING scale (--type-landing-*), the same one
// the .text-landing-* classes carry, so this hero and a site that hand-writes its
// own landing render the identical tier. The scale is defined once in the toolkit
// (external/adhsdk/packages/web/packages/themes/tokens/semantic/typography.json) — resize it THERE.
//
// THE FALLBACK CONVENTION, for every consumer of this scale in the repo: the literal
// after a --type-landing-* var is THE VALUE THE DEFAULT THEME SETS FOR THAT TOKEN, so
// the unthemed render is the themed one. It is NOT "whatever this file used to
// hard-code" — that reading is unverifiable (nothing can check a value against a
// deleted one) and it re-creates, in the no-theme case, exactly the per-site drift
// this scale replaced. `landingTypeScale.test.ts` pins the equality repo-wide.
// The one exemption is `-font`: the token's own value is a nested var(--font-serif),
// while a consumer's fallback has to be a real family stack for the case where no
// theme is present at all, so the two cannot be equal by construction.
const SERIF = 'var(--font-serif, ui-serif, Georgia, serif)'
const SANS = 'var(--font-sans, ui-sans-serif, system-ui, sans-serif)'
const MONO = 'var(--font-mono, ui-monospace, monospace)'
const TEXT = 'var(--color-text-primary, #e8e6e3)'
const MUTED = 'var(--color-text-secondary, #8a8a9a)'
const ACCENT = 'var(--color-accent, #c4a35a)'
const BORDER = 'var(--color-border, #2a2a35)'

const wrap: CSSProperties = {
  flex: 1,
  display: 'flex',
  flexDirection: 'column',
  alignItems: 'center',
  justifyContent: 'center',
  textAlign: 'center',
  padding: '5rem 1.5rem',
  fontFamily: SERIF,
  color: TEXT,
}

/**
 * The shared landing hero for the ADH family's sites. Renders entirely against
 * the shared theme tokens injected by <AdhThemeStyle/> (--color-*, --font-*), so
 * consumer sites need no local palette. One source of truth for all family
 * landings — see websites/scripts/scaffold-sites.py.
 *
 * The hero carries no "placeholder / coming soon" marker: the family's pre-launch
 * status is stated once, by the "Developer Preview Release" strip the shared header
 * draws above the bar, so repeating it per landing is noise.
 */
export function SiteLanding({
  eyebrow,
  titleLead = 'Agentic Developer',
  titleAccent,
  blurb,
}: SiteLandingProps) {
  return (
    <main style={wrap}>
      <div style={{ maxWidth: 720 }}>
        <div
          style={{
            fontFamily: `var(--type-landing-eyebrow-font, ${MONO})`,
            fontSize: 'var(--type-landing-eyebrow-size, 0.7rem)',
            lineHeight: 'var(--type-landing-eyebrow-line-height, 1.4)',
            letterSpacing: 'var(--type-landing-eyebrow-tracking, 0.24em)',
            fontWeight: 'var(--type-landing-eyebrow-weight, 500)',
            textTransform: 'var(--type-landing-eyebrow-transform, uppercase)',
            color: MUTED,
            marginBottom: '1.75rem',
          }}
        >
          {eyebrow}
        </div>

        <h1
          style={{
            fontFamily: `var(--type-landing-title-font, ${SERIF})`,
            fontSize: 'var(--type-landing-title-size, clamp(2.6rem, 6vw, 4.5rem))',
            lineHeight: 'var(--type-landing-title-line-height, 1.04)',
            letterSpacing: 'var(--type-landing-title-tracking, -0.02em)',
            fontWeight: 'var(--type-landing-title-weight, 400)',
            margin: '0 0 1.5rem',
          }}
        >
          {titleLead}{' '}
          <span style={{ color: ACCENT, fontStyle: 'italic' }}>
            {titleAccent}
          </span>
        </h1>

        <p
          style={{
            fontFamily: `var(--type-landing-lede-font, ${SANS})`,
            fontSize: 'var(--type-landing-lede-size, 1.1rem)',
            lineHeight: 'var(--type-landing-lede-line-height, 1.7)',
            fontWeight: 'var(--type-landing-lede-weight, 400)',
            letterSpacing: 'var(--type-landing-lede-tracking, 0)',
            color: MUTED,
            margin: '0 auto 2.75rem',
            maxWidth: 560,
          }}
        >
          {blurb}
        </p>

        {/* Decorative closer for the hero — with the note gone it separates the
            hero from whatever the page stacks below it (e.g. StorySections). */}
        <div
          role="separator"
          aria-hidden="true"
          style={{
            height: 1,
            background:
              `linear-gradient(to right, transparent, ${BORDER}, transparent)`,
            margin: '1rem 0 0',
          }}
        />
      </div>
    </main>
  )
}
