import { render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { AdhFooter, FooterMenu } from '../AdhFooter'
import { buildVersionLabel } from '../SiteFooter'

// Stub next/link so the (otherwise DOM-invisible) `prefetch` prop can be observed —
// the real component destructures `prefetch` before spreading the rest onto the
// anchor (next/dist/client/link.js), so it never reaches the DOM on its own. The
// stub forwards everything else (href, onClick, className, children) unchanged so
// every other assertion in this file still exercises real link behavior.
vi.mock('next/link', () => ({
  default: ({ href, prefetch, ...rest }: { href: string; prefetch?: boolean }) => (
    <a href={href} data-prefetch={String(prefetch)} {...rest} />
  ),
}))

describe('AdhFooter (identity-free)', () => {
  it('renders the copyright it is given, with no hardcoded brand', () => {
    render(<AdhFooter copyright={<span>© 2026 Example Co</span>} />)
    expect(screen.getByText('© 2026 Example Co')).toBeTruthy()
  })

  it('renders trailing as the last child of <footer>, a sibling of the container — not nested inside it', () => {
    render(<AdhFooter trailing={<span>chat</span>} />)
    const footer = screen.getByRole('contentinfo')
    const trailing = screen.getByText('chat')
    // Node identity, not a substring match: if `trailing` were moved inside
    // .adh-footer__container, footer.lastElementChild would be the container div
    // (whose textContent would still happen to include "chat"), not the trailing
    // node itself — a toHaveTextContent check alone would not catch that.
    expect(footer.lastElementChild).toBe(trailing)
  })

  it('renders a native popover trigger for popoverTarget entries', () => {
    render(<AdhFooter links={[{ label: 'Sites', popoverTarget: 'panel-1', ariaLabel: 'Sites — overview' }]} />)
    const btn = screen.getByRole('button', { name: 'Sites — overview' })
    expect(btn.getAttribute('popovertarget')).toBe('panel-1')
    expect(btn.className).toContain('adh-footer__sites-trigger')
  })

  it('keeps the href on onSelect entries so they still work without JS', () => {
    let opened = false
    render(
      <AdhFooter
        links={[{ label: 'Terms', href: '/terms', onSelect: (e) => { e.preventDefault(); opened = true } }]}
      />,
    )
    const link = screen.getByRole('link', { name: 'Terms' })
    expect(link.getAttribute('href')).toBe('/terms')
    link.click()
    expect(opened).toBe(true)
  })

  it('renders nothing brand-specific when given no props', () => {
    const { container } = render(<AdhFooter />)
    expect(container.textContent).not.toMatch(/FishLamp/)
  })

  it('renders no navigation links at all when unconfigured — there is no hard-coded default set', () => {
    render(<AdhFooter />)
    expect(screen.queryByRole('navigation')).toBeNull()
    expect(screen.queryAllByRole('link')).toHaveLength(0)
    expect(screen.queryAllByRole('button')).toHaveLength(0)
  })

  it('passes prefetch through to the rendered anchor when given, and leaves it alone otherwise', () => {
    render(
      <AdhFooter
        links={[
          { label: 'Terms', href: '/terms', prefetch: false },
          { label: 'GitHub', href: 'https://example.com' },
        ]}
      />,
    )
    expect(screen.getByRole('link', { name: 'Terms' }).getAttribute('data-prefetch')).toBe('false')
    expect(screen.getByRole('link', { name: 'GitHub' }).getAttribute('data-prefetch')).toBe('undefined')
  })

  it('renders no version of its own — the build identity lives in the host\'s About dialog', () => {
    // The bar used to carry a `.adh-footer__version` slot; SiteFooter moved the version
    // into About (see AboutModal). A leftover slot would be an empty flex item taking a
    // gap in a bar that has to fit bitbag's face in its middle on a phone.
    const { container } = render(<AdhFooter copyright={<span>© 2026</span>} links={[{ label: 'Terms', href: '/terms' }]} />)
    expect(container.querySelector('.adh-footer__version')).toBeNull()
  })

  it('keeps the links nav as the container\'s last child, so the links sit at the trailing edge', () => {
    render(<AdhFooter copyright={<span>© 2026</span>} links={[{ label: 'Terms', href: '/terms' }]} trailing={<span>chat</span>} />)
    const container = screen.getByRole('contentinfo').firstElementChild!
    expect(container.lastElementChild!.className).toBe('adh-footer__links')
  })
})

describe('FooterMenu', () => {
  const items = [
    { label: 'About', popoverTarget: 'about-dialog' },
    { label: 'Terms', href: '/terms', prefetch: false },
  ]

  it('is a native popover: a popovertarget button and its panel, both in the rendered HTML', () => {
    // In the markup even while closed — that is what keeps the menu's links crawlable
    // (server-rendered, hidden by CSS), rather than existing only after a click.
    const { container } = render(<FooterMenu id="m1" label="© 2026" items={items} />)
    const trigger = screen.getByRole('button', { name: '© 2026' })
    expect(trigger.getAttribute('popovertarget')).toBe('m1')
    expect(trigger.getAttribute('aria-haspopup')).toBe('menu')
    const panel = container.querySelector('#m1')!
    expect(panel.getAttribute('popover')).toBe('auto')
    expect(panel.querySelector('a[href="/terms"]')).not.toBeNull()
    expect(panel.querySelector('button[popovertarget="about-dialog"]')).not.toBeNull()
  })

  it('shows a popup indicator on its trigger, hidden from the accessible name', () => {
    // Without it the copyright line reads as plain text and Legal as a link to a page.
    render(<FooterMenu id="m1" label="Legal" items={items} />)
    const trigger = screen.getByRole('button', { name: 'Legal' })
    const caret = trigger.querySelector('.adh-footer__menu-caret')
    expect(caret).not.toBeNull()
    expect(caret).toHaveAttribute('aria-hidden')
  })

  it('anchors each menu to its own trigger, so two menus in one bar do not share a position', () => {
    const { container } = render(
      <>
        <FooterMenu id="m1" label="One" items={items} />
        <FooterMenu id="m2" label="Two" items={items} />
      </>,
    )
    const anchors = Array.from(container.querySelectorAll<HTMLElement>('.adh-footer__menu-host')).map((el) =>
      el.style.getPropertyValue('--adh-footer-menu-anchor'),
    )
    expect(anchors).toEqual(['--m1', '--m2'])
  })

  it('passes prefetch and onSelect through to a link item', () => {
    let selected = false
    render(
      <FooterMenu
        id="m1"
        label="Legal"
        items={[{ label: 'Terms', href: '/terms', prefetch: false, onSelect: (e) => { e.preventDefault(); selected = true } }]}
      />,
    )
    const link = screen.getByRole('link', { name: 'Terms', hidden: true })
    expect(link.getAttribute('data-prefetch')).toBe('false')
    link.click()
    expect(selected).toBe(true)
  })

  it('renders a menu entry of the bar from a `menuId` link, carrying its className to the host', () => {
    const { container } = render(
      <AdhFooter links={[{ label: 'Legal', menuId: 'legal', items, className: 'narrow-only' }]} />,
    )
    const host = container.querySelector('.adh-footer__menu-host')!
    expect(host.classList.contains('narrow-only')).toBe(true)
    expect(screen.getByRole('button', { name: 'Legal' }).getAttribute('popovertarget')).toBe('legal')
  })
})

describe('SiteFooter (build constants → version)', () => {
  // In `afterEach`, not at the end of each body: a failing assertion aborts the body,
  // so an in-body unstub never runs on the one occasion it matters and leaves both
  // constants set for every test after it. That turns one real failure into a cascade
  // of misattributed ones — and the last case here ("neither constant is set") would
  // only pass because its own stubs happened to overwrite the leak.
  afterEach(() => {
    vi.unstubAllEnvs()
  })

  it('joins the version and the short SHA with a middot, and titles it with the full SHA', () => {
    // Next inlines NEXT_PUBLIC_* at build time; in vitest they are ordinary env
    // reads, which is exactly what makes this composition testable here.
    vi.stubEnv('NEXT_PUBLIC_ADH_SITE_VERSION', '1.0.155')
    vi.stubEnv('NEXT_PUBLIC_ADH_RELEASE', 'a73e79b7c0ffee00deadbeef1234567890abcdef')
    const el = buildVersionLabel()
    expect(el).not.toBeNull()
    render(<div>{el}</div>)
    expect(screen.getByText('v1.0.155 · a73e79b7')).toBeTruthy()
    expect(screen.getByTitle('a73e79b7c0ffee00deadbeef1234567890abcdef')).toBeTruthy()
  })

  it('shows the SHA alone when the site has no VERSION file', () => {
    vi.stubEnv('NEXT_PUBLIC_ADH_SITE_VERSION', '')
    vi.stubEnv('NEXT_PUBLIC_ADH_RELEASE', 'a73e79b7c0ffee00deadbeef1234567890abcdef')
    render(<div>{buildVersionLabel()}</div>)
    expect(screen.getByText('a73e79b7')).toBeTruthy()
  })

  it('shows the version alone, with no trailing middot, when every SHA source failed', () => {
    // Reachable outside Vercel/Railway when the build also isn't a git checkout:
    // VERCEL_GIT_COMMIT_SHA -> RAILWAY_GIT_COMMIT_SHA -> git rev-parse HEAD -> "" all miss.
    vi.stubEnv('NEXT_PUBLIC_ADH_SITE_VERSION', '1.0.155')
    vi.stubEnv('NEXT_PUBLIC_ADH_RELEASE', '')
    render(<div>{buildVersionLabel()}</div>)
    expect(screen.getByText('v1.0.155')).toBeTruthy()
  })

  it('renders nothing at all when neither constant is set', () => {
    vi.stubEnv('NEXT_PUBLIC_ADH_SITE_VERSION', '')
    vi.stubEnv('NEXT_PUBLIC_ADH_RELEASE', '')
    expect(buildVersionLabel()).toBeNull()
  })

  // The dev-mode override. The constants above are baked when Next evaluates
  // `next.config.ts` — once, at dev-server boot — so across a long session the footer
  // kept reporting the commit the session started on and a bumped VERSION moved
  // nothing. AppShell (a Server Component) resolves the real pair per render and
  // passes it here; see `liveBuildIdentity` and its own tests.
  describe('the live override', () => {
    it('wins over both baked constants', () => {
      vi.stubEnv('NEXT_PUBLIC_ADH_SITE_VERSION', '1.0.0')
      vi.stubEnv('NEXT_PUBLIC_ADH_RELEASE', '618f848dfeedfacecafebabe1234567890abcdef')
      render(<div>{buildVersionLabel({ version: '1.1.0', sha: 'a73e79b7c0ffee00deadbeef1234567890abcdef' })}</div>)
      expect(screen.getByText('v1.1.0 · a73e79b7')).toBeTruthy()
      // The title carries the LIVE full sha too — copying it has to yield a commit that
      // exists in the tree you are looking at, which is the field's only job.
      expect(screen.getByTitle('a73e79b7c0ffee00deadbeef1234567890abcdef')).toBeTruthy()
    })

    it('falls back per field, so a value it could not read leaves the baked one standing', () => {
      // This is what makes the override safe to apply unconditionally: it can only ever
      // CORRECT a field, never blank one. A site with no VERSION file, or a dev server
      // outside a git checkout, keeps whatever the config managed to bake.
      vi.stubEnv('NEXT_PUBLIC_ADH_SITE_VERSION', '1.0.0')
      vi.stubEnv('NEXT_PUBLIC_ADH_RELEASE', '618f848dfeedfacecafebabe1234567890abcdef')
      render(<div>{buildVersionLabel({ version: undefined, sha: 'a73e79b7c0ffee00deadbeef1234567890abcdef' })}</div>)
      expect(screen.getByText('v1.0.0 · a73e79b7')).toBeTruthy()
    })

    it('changes nothing when it is absent — the production path is untouched', () => {
      vi.stubEnv('NEXT_PUBLIC_ADH_SITE_VERSION', '1.0.155')
      vi.stubEnv('NEXT_PUBLIC_ADH_RELEASE', 'a73e79b7c0ffee00deadbeef1234567890abcdef')
      render(<div>{buildVersionLabel(undefined)}</div>)
      expect(screen.getByText('v1.0.155 · a73e79b7')).toBeTruthy()
    })
  })
})
