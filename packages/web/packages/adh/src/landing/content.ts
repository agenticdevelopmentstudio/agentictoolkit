import type { ReactNode } from 'react'
import type { SiteId } from '@agentic-toolkit/adh-registry'
import type {
  ChecklistGroup,
  ChipEntry,
  PointEntry,
  RuleStep,
  StatEntry,
  TourPillar,
  VersusSide,
} from '@agenticdevelopertoolkit/landing'

/**
 * A family site's landing deck, as DATA.
 *
 * Every site in the family writes one of these — `src/landing.json`, generated from that
 * site's markdown by `content-buildr update` and loaded by the `src/landing.tsx` beside it through
 * `landingFromData` — and mounts it through `<LandingDeck>` and
 * `<LandingTour>`. Which is to say: the deck's STRUCTURE lives here, in shared code, and
 * a site carries only its own copy.
 *
 * That split is the whole point. The generator used to emit the markup — a `<Deck>` of
 * `<Screen>`s of `<Wrap>`s, sixty-odd lines per site — so every site held its own copy of
 * the page's shape, and changing the shape meant regenerating thirty-eight files and
 * reviewing thirty-eight diffs to confirm they said the same thing. Now `app/page.tsx`
 * and `app/tour/page.tsx` are the same bytes in every site, the shape is one file in this
 * package, and a site's generated output holds nothing but its own words.
 *
 * The values are ReactNodes rather than strings because the copy carries markup: a
 * headline's `**bold**` is the accent colour in the deck's heading grammar, and a link in
 * a bullet is a link. The generator writes each as a small node tree in the JSON, and
 * `landingFromData` (./fromData) turns the tree back into a fragment.
 */
export interface LandingContent {
  hero: LandingHero
  sections: LandingSection[]
  /**
   * The `{tour}` blurb. Required for every site's OWN landing deck: `<LandingTour>`
   * renders `/tour` for every site in the family, and a site with no blurb would render a
   * page identical to `/` — no step counter, no way on to the next site, the walk
   * silently ending there. The generator's own validator refuses a site whose markdown
   * has no `{tour}` section, so absence there is a fact about the content, not a default
   * to fill in here.
   *
   * Absent on a site's own second deck (`/details`), which is a page rather than a stop
   * on the family walk. `<LandingTour>` is the only reader; `<LandingDeck>` never was.
   */
  tour?: LandingTourStop
}

export interface LandingHero {
  headline: ReactNode
  tagline: ReactNode
  /** The rows under the tagline — a button row, a trust row, a status pill. */
  blocks: LandingBlock[]
}

export interface LandingSection {
  /**
   * The `<Screen>`'s DOM id, and the `#href` the deck's index links to. Computed by the
   * generator (`render.screen_id`) rather than derived from `eyebrow` here, so there is
   * one slug function rather than two that agree until one changes — and so the
   * generator's validator can refuse an empty id, a duplicate, or a collision with the
   * tour strip's own `#tour` before anything is written.
   */
  id: string
  /**
   * The screen's label: the `<Head>`'s eyebrow AND the index row that scrolls to it, one
   * field, so a reader who picks "The record" always lands on a screen that says "The
   * record". Two copies of that string is how a hand-kept menu drifts from its page.
   */
  eyebrow: string
  /** The `### ` line under the eyebrow, when the section has one. */
  title?: ReactNode
  /**
   * True when a BLOCK in this section renders the section's heading itself, so the screen
   * carries no `<Head>` of its own. `{roadmap}` is the one that does — it takes the
   * section's heading as its own eyebrow, and a `<Head>` above it would label one screen
   * twice.
   */
  headingInBlock?: true
  blocks: LandingBlock[]
}

/**
 * One block on a screen. `kind` is the exact `@agenticdevelopertoolkit/landing` export name, and
 * the rest of each member is that component's props — with one deliberate difference,
 * spelled out in `LandingCard`, `LandingFaqEntry` and `Closer` below: a body arrives as a
 * LIST of paragraphs rather than a single node, because the kit styles a body through its
 * `<p>` children (`.lp-card p`, `.lp-closer p`, `.lp-faq details p`) and a body emitted as
 * a bare text child inherits the page's defaults instead.
 */
export type LandingBlock =
  | { kind: 'Lede'; children: ReactNode }
  | { kind: 'Trust'; items: ReactNode[] }
  | { kind: 'Cards'; items: LandingCard[]; pair?: true; trio?: true }
  | { kind: 'Points'; entries: PointEntry[]; ordered?: true }
  | { kind: 'Code'; text: string }
  /** `src` is a screenshot id, not a URL. The deck resolves it against the hub's own
   *  origin (`/screenshots/<id>.png`) so one image set serves the brochure and the help
   *  site, whose Markdown sanitizer accepts only absolute http/https sources.
   *
   *  OPTIONAL, because the landing kit's `Shot` calls the placeholder its primary state:
   *  "until a real capture exists, every feature section renders one". Required, the deck
   *  could only ever emit an `<img>` — and with no `public/screenshots/` anywhere in the
   *  fleet that was a broken image every time, with the frame the package draws for exactly
   *  this case unreachable. Omit `src` until the capture exists; `caption` still says what
   *  the shot will show. */
  | { kind: 'Shot'; src?: string; title: string; caption: string }
  | { kind: 'Table'; caption: ReactNode; columns: ReactNode[]; rows: ReactNode[][] }
  | { kind: 'StatusPill'; children: ReactNode; free?: true }
  | { kind: 'Rule'; steps: RuleStep[] }
  | { kind: 'Stats'; entries: StatEntry[] }
  | { kind: 'Versus'; them: VersusSide; us: VersusSide }
  | { kind: 'Chips'; entries: ChipEntry[]; soon?: true }
  | { kind: 'Checklist'; groups: ChecklistGroup[] }
  | { kind: 'Faq'; entries: LandingFaqEntry[] }
  | { kind: 'Closer'; title: ReactNode; body: ReactNode[] }
  | { kind: 'Cta'; buttons: LandingButton[] }
  | { kind: 'Roadmap'; children: LandingBlock[]; eyebrow?: ReactNode }

export interface LandingCard {
  /** Rendered in its own `<span>` outside the `<h3>`, so a card with one and a card
   *  without still produce the same heading text. */
  kicker?: ReactNode
  title: ReactNode
  body: ReactNode[]
}

export interface LandingFaqEntry {
  question: ReactNode
  answer: ReactNode[]
  open?: boolean
}

export interface LandingButton {
  href: string
  label: ReactNode
  /** Absent reads as `ghost`, which is `Btn`'s own default; the generator marks the first
   *  button of a row primary and leaves the rest alone. */
  variant?: 'primary' | 'ghost'
}

export interface LandingTourStop {
  eyebrow: string
  promise: ReactNode
  position: { step: number; total: number }
  /**
   * The three-column promise, carried by the masterbrand alone. Which site that is belongs
   * to the manifest the generator reads, not to any one site's markdown — a leaf that
   * repeated the cards would make the whole family's claim on its own page and then make
   * it again on the next site in the walk.
   */
  pillars?: TourPillar[]
  back?: LandingTourEdge
  next?: LandingTourEdge
}

export interface LandingTourEdge {
  /**
   * The SITE the edge points at, not a path: a tour edge crosses origins, and only the
   * registry knows a site's production host. `<LandingTour>` spells the href with
   * `siteProdUrl`, so the host table stays the one source of hosts.
   */
  site: SiteId
  /**
   * The other site's headline, as plain text — it lands on a button, whose label is a
   * `string`, so the markdown is stripped rather than converted.
   */
  label: string
  note?: string
}
