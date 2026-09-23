'use client'

import type { ReactNode } from 'react'
import { getSite, siteProdUrl } from '@agentic-toolkit/adh-registry'
import { AdhModalPopover } from './AdhModalPopover'

/** DOM id of the footer's About dialog, opened from the copyright menu. */
export const ABOUT_DIALOG_ID = 'adh-about-dialog'

// The company the copyright belongs to — Agentic Development Studio, which is also
// the wordmark closing the site menu (see StudioWordmark). NOT FishLamp Design, which
// the copyright used to name and which is still a family site with its own row.
//
// A literal href rather than `siteProdUrl(...)`: the studio deliberately has no
// registry entry (a `registry.test.ts` case pins that agenticdevelopmentstudio.com is
// not a registry host, because an entry would re-add the origin to the OAuth
// return-origin allowlist and to the generated route map). Same reason the menu's
// studio row is an absolute `{ href }`.
export const BRAND_LABEL = 'Agentic Development Studio'
export const BRAND_HREF = 'https://agenticdevelopmentstudio.com/'

/** The address as a reader would type it — the link's visible text. */
function hostOf(href: string): string {
  return new URL(href).host
}

function Entry({ name, href, children }: { name: string; href: string; children: ReactNode }) {
  return (
    <section className="adh-about__entry">
      <h3 className="adh-about__name">{name}</h3>
      <p className="adh-about__blurb">{children}</p>
      <a className="adh-about__link" href={href}>
        {hostOf(href)}
      </a>
    </section>
  )
}

/**
 * The footer's About dialog: who makes these sites, and which build you are looking at.
 *
 * Rendered in full into the server HTML, unlike the legal modals (which mount their prose on
 * first open): it is a few lines, not several KB, and its two links are the family's links
 * OUT to the companies behind it — exactly what a crawler reading any page should find.
 *
 * FishLamp Design's name, description and address come from its registry entry rather than
 * being restated here, so the About box cannot drift from the sites overview's own row.
 *
 * @param version the build identity ({@link buildVersionLabel}); null when neither the
 *   version nor the SHA was baked, which is said rather than left as an empty row.
 */
export function AboutModal({ version }: { version: ReactNode }) {
  const fishlamp = getSite('fishlamp')
  return (
    <AdhModalPopover id={ABOUT_DIALOG_ID} title="About" bodyClassName="adh-modal__body--about">
      <Entry name={BRAND_LABEL} href={BRAND_HREF}>
        The company behind the Agentic Developer family of sites, and the name on their
        copyright.
      </Entry>
      {fishlamp && (
        <Entry name={fishlamp.label} href={siteProdUrl('fishlamp', '/')}>
          {fishlamp.description}.
        </Entry>
      )}
      <dl className="adh-about__build">
        <dt>Site version</dt>
        <dd>{version ?? 'Not recorded in this build'}</dd>
      </dl>
    </AdhModalPopover>
  )
}
