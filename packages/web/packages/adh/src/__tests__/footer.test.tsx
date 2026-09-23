import { render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { SiteFooter } from '../footer/SiteFooter'

// Stub next/link so `prefetch` — which the real component destructures away before
// spreading the rest onto the anchor (next/dist/client/link.js) and so never reaches
// the DOM on its own — can be observed here. Forwards href/onClick/className/children
// unchanged so the pre-existing href assertions below still exercise real behavior.
vi.mock('next/link', () => ({
  default: ({ href, prefetch, ...rest }: { href: string; prefetch?: boolean }) => (
    <a href={href} data-prefetch={String(prefetch)} {...rest} />
  ),
}))

describe('adh SiteFooter', () => {
  it('makes the copyright line the trigger of a menu, and names the studio in it', () => {
    render(<SiteFooter />)
    // Agentic Development Studio, which replaced FishLamp Design in the copyright.
    const trigger = screen.getByRole('button', { name: /Agentic Development Studio/ })
    expect(trigger.closest('.adh-footer__copyright')).not.toBeNull()
    expect(trigger.getAttribute('popovertarget')).toBe('adh-footer-copyright-menu')
  })

  it('puts About and Sites in the copyright menu, each opening its own popover', () => {
    const { container } = render(<SiteFooter />)
    const menu = container.querySelector('#adh-footer-copyright-menu')!
    const entries = Array.from(menu.querySelectorAll('button')).map((b) => [
      b.textContent,
      b.getAttribute('popovertarget'),
    ])
    expect(entries).toEqual([
      ['About', 'adh-about-dialog'],
      ['Sites', 'adh-sites-overview'],
    ])
    expect(
      screen.getByRole('button', { name: 'Sites — Agentic Developer family overview', hidden: true }),
    ).toBeInTheDocument()
  })

  it('renders the About dialog into the page, with both companies\' links and the version', () => {
    vi.stubEnv('NEXT_PUBLIC_ADH_SITE_VERSION', '1.0.155')
    vi.stubEnv('NEXT_PUBLIC_ADH_RELEASE', 'a73e79b7c0ffee00deadbeef1234567890abcdef')
    try {
      const { container } = render(<SiteFooter />)
      const about = container.ownerDocument.getElementById('adh-about-dialog')!
      expect(about).not.toBeNull()
      const hrefs = Array.from(about.querySelectorAll('a')).map((a) => a.getAttribute('href'))
      expect(hrefs).toContain('https://agenticdevelopmentstudio.com/')
      expect(hrefs.some((h) => h?.includes('fishlamp.com'))).toBe(true)
      expect(about.textContent).toContain('FishLamp Design')
      expect(about.textContent).toContain('v1.0.155 · a73e79b7')
    } finally {
      vi.unstubAllEnvs()
    }
  })

  it('carries no version in the bar itself — it moved into About', () => {
    const { container } = render(<SiteFooter />)
    expect(container.querySelector('.adh-footer__container .adh-footer__version')).toBeNull()
  })

  it('renders Terms and Privacy both inline (wide) and inside a Legal menu (narrow), hrefs intact', () => {
    // Both forms are in the HTML at every width and CSS picks one — so the server
    // page is right on a phone without waiting for a client measurement.
    const { container } = render(<SiteFooter />)
    const nav = screen.getByRole('navigation', { name: 'Footer' })
    const wide = Array.from(nav.querySelectorAll('.adh-footer__link--wide')).map((a) => [
      a.textContent,
      a.getAttribute('href'),
    ])
    expect(wide).toEqual([
      ['Terms', '/terms'],
      ['Privacy', '/privacy'],
    ])
    const legal = container.querySelector('.adh-footer__link--narrow')!
    expect(legal.querySelector('button')!.textContent).toBe('Legal')
    const inMenu = Array.from(legal.querySelectorAll('a')).map((a) => a.getAttribute('href'))
    expect(inMenu).toEqual(['/terms', '/privacy'])
  })

  it('keeps passed links ahead of the legal entries', () => {
    render(<SiteFooter links={[{ label: 'GitHub', href: 'https://example.com' }]} />)
    const nav = screen.getByRole('navigation', { name: 'Footer' })
    const labels = Array.from(nav.children).map((el) =>
      el.classList.contains('adh-footer__menu-host') ? el.querySelector('button')!.textContent : el.textContent,
    )
    expect(labels).toEqual(['GitHub', 'Terms', 'Privacy', 'Legal'])
  })

  it('disables prefetch on every legal link (sticky footer means they are always in-viewport), and leaves a site-passed link unaffected', () => {
    render(<SiteFooter links={[{ label: 'GitHub', href: 'https://example.com' }]} />)
    for (const link of screen.getAllByRole('link', { name: /^(terms|privacy)$/i, hidden: true })) {
      expect(link).toHaveAttribute('data-prefetch', 'false')
    }
    expect(screen.getByRole('link', { name: 'GitHub' })).toHaveAttribute('data-prefetch', 'undefined')
  })
})
