/// <reference types="@testing-library/jest-dom/vitest" />
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { AdhHeader } from '../AdhHeader'

// The dropdown behind the switcher is base-ui backed: its portal returns null while
// closed (keepMounted defaults false), so a closed menu's rows are absent from the DOM
// entirely. Every assertion about menu CONTENT below therefore opens the menu first —
// a cold getByText would either fail, or (worse) pass off the trigger's own label.
const openSwitcher = async (siteName: string): Promise<void> => {
  fireEvent.click(screen.getByRole('button', { name: `${siteName} — switch site` }))
  await waitFor(() => expect(screen.getByRole('menu')).toBeInTheDocument())
}

describe('AdhHeader (registry-free)', () => {
  // ── brief test 1, unchanged ──
  it('renders the site name it was given, with no registry lookup', () => {
    render(<AdhHeader siteName="Agentic Developer Hub" siteNameHref="/" />)
    expect(screen.getByText('Agentic Developer Hub')).toBeTruthy()
  })

  // ── brief test 2, rewritten: SiteLink is { id?, label, href, description? }, and the
  //    menu must be OPENED before its rows exist (see openSwitcher above). ──
  it('renders caller-supplied sites in the switcher, with or without an id', async () => {
    render(
      <AdhHeader
        siteName="Hub"
        sites={[
          { id: 'fishlamp', label: 'FishLamp', href: 'https://example.test' },
          //  `id` is OPTIONAL on the published SiteLink. A target without one must
          //  still render and still key stably (SiteSwitcher falls back to the href);
          //  requiring it would have broken every existing SiteOptionsMenu caller.
          { label: 'Lampfish', href: 'https://other.test' },
        ]}
      />,
    )
    // Cold, the sites are genuinely not in the DOM — that is the portal, not a bug.
    expect(screen.queryByText('FishLamp')).toBeNull()
    await openSwitcher('Hub')
    expect(screen.getByText('FishLamp')).toBeTruthy()
    expect(screen.getByText('Lampfish')).toBeTruthy()
  })

  //  The id-less fallback (`key: site.id ?? site.href`) is contract, not detail — but
  //  it is invisible in the DOM: NavigationPopover consumes `item.key` only as a React
  //  key and renders it nowhere. Its one observable surface is the argument handed to
  //  `onSwitchSite`, so that is what this pins. Without the fallback a later `site.id!`
  //  sends `undefined` to a consumer's SSO rewriter, which silently declines to rewrite
  //  and lets the switcher navigate to a raw href while signed out.
  it('hands onSwitchSite the href of a target that has no id', async () => {
    //  Returning a hash keeps jsdom to a same-document navigation; window.location
    //  .assign to a real origin raises "Not implemented: navigation" instead.
    const onSwitchSite = vi.fn(() => '#switched')
    render(
      <AdhHeader
        siteName="Hub"
        sites={[{ label: 'Lampfish', href: 'https://other.test' }]}
        onSwitchSite={onSwitchSite}
      />,
    )
    await openSwitcher('Hub')
    fireEvent.click(screen.getByText('Lampfish'))
    expect(onSwitchSite).toHaveBeenCalledWith('https://other.test')
  })

  // ── brief test 3, rewritten: `badges` is HeaderBadge[], not a ReactNode. The brief's
  //    own normative rule says so; only its sample test disagreed. ──
  it('renders the badges, center and leadingActions slots ported from the adh header', () => {
    render(
      <AdhHeader
        siteName="Hub"
        badges={[{ label: 'badge' }]}
        center={<span>center</span>}
        leadingActions={<span>leading</span>}
      />,
    )
    for (const text of ['badge', 'center', 'leading']) {
      expect(screen.getByText(text)).toBeTruthy()
    }
  })

  // `badges` used to default to a "Preview Release" badge under the site name. The
  // preview notice is the strip above the bar now, so the slot defaults to EMPTY —
  // a site that passes nothing must get nothing, or the retired badge comes back
  // fleet-wide by default.
  it('renders no badges by default', () => {
    const { container } = render(<AdhHeader siteName="Hub" />)
    expect(container.querySelector('.adh-header__badges')).toBeNull()
    expect(screen.queryByText('Preview Release')).toBeNull()
  })

  // The strip is unconditional: it is a statement about the whole family, not a
  // per-site prop, so every header must carry it with no opt-in. Asserting the text
  // (not just the class) keeps a silently-emptied strip from passing.
  it('renders the family preview strip above the bar on every header', () => {
    const { container } = render(<AdhHeader siteName="Hub" />)
    const strip = container.querySelector('.adh-header__preview')
    expect(strip).not.toBeNull()
    expect(strip).toHaveTextContent('Developer Preview Release')
    // Above the bar, and inside the banner — so it shares the header's sticky box
    // rather than scrolling away from the bar it qualifies.
    const banner = screen.getByRole('banner')
    expect(strip!.parentElement).toBe(banner)
    expect(banner.firstElementChild).toBe(strip)
  })

  // ── brief test 4, rewritten. There is no `routes`/`adminOnly` prop here and there
  //    must not be one: the admin-gated route map is adh registry vocabulary. The intent
  //    the brief was pinning — admin-only navigation never appears in a header that was
  //    not given one — is pinned at its real seam: this header renders no admin surface
  //    of its own, and `userIsAdmin` reaches only what a caller puts in a slot — adh
  //    hands it to its site-menu switcher, which appends the admin consoles. (`userIsAdmin`
  //    stays on AdhHeaderAuthProps because shared/auth's HeaderAuthState is derived from
  //    that type and must keep its shape.) ──
  it('exposes no admin surface of its own — userIsAdmin only reaches a caller-supplied switcher', () => {
    const { rerender } = render(<AdhHeader siteName="Hub" />)
    expect(screen.queryByText('Admin')).toBeNull()
    rerender(<AdhHeader siteName="Hub" userIsAdmin />)
    expect(screen.queryByText('Admin')).toBeNull()
    rerender(
      <AdhHeader siteName="Hub" userIsAdmin siteSwitcher={<button type="button">Admin</button>} />,
    )
    expect(screen.getByText('Admin')).toBeTruthy()
  })

  // ── brief test 5, rewritten: auth props are flat (there is no `auth` object and no
  //    `status` field — shared/auth's HeaderAuthState is derived FROM the flat type). ──
  it("defaults the signup label to adh's shipped copy", () => {
    render(<AdhHeader siteName="Hub" onLogin={() => {}} onSignup={() => {}} />)
    expect(screen.getByText('join')).toBeTruthy()
  })

  // ── beyond the brief: the two constraints attached to the siteSwitcher slot ──
  it('renders the caller-supplied switcher INSTEAD OF the default, never both', () => {
    render(
      <AdhHeader
        siteName="Hub"
        sites={[{ id: 'fishlamp', label: 'FishLamp', href: 'https://example.test' }]}
        siteSwitcher={<button type="button">Custom switcher</button>}
      />,
    )
    expect(screen.getByText('Custom switcher')).toBeTruthy()
    // The default switcher's trigger is gone entirely — not merely hidden, and not
    // sitting alongside. A slot that silently DOUBLES the switcher passes a naive
    // "is the custom one there?" check and shows up in a screenshot later.
    expect(screen.queryByRole('button', { name: 'Hub — switch site' })).toBeNull()
    // Exactly one node claims the brand row, and it is the caller's. (The row, not the
    // lead: the lead is a column that also stacks the badges, so the switcher's own
    // position is one level in — see .adh-header__brand-row.)
    const row = screen.getByRole('banner').querySelector('.adh-header__brand-row')!
    expect(row.children).toHaveLength(1)
    expect(row.firstElementChild?.textContent).toBe('Custom switcher')
  })

  // SiteHeader fills nothing here any more (its dev-tools dropdown was deleted), but the
  // slot is public API and its one promise — beside, not under — is still the contract.
  it('renders debugMenu AFTER the switcher, on the same row', () => {
    render(
      <AdhHeader
        siteName="Hub"
        siteSwitcher={<button type="button">Custom switcher</button>}
        debugMenu={<button type="button">Second menu</button>}
        badges={[{ label: 'preview' }]}
      />,
    )
    const row = screen.getByRole('banner').querySelector('.adh-header__brand-row')!
    // BESIDE the switcher, not under it. The lead is a column (the badge below proves
    // it), so a slot rendered as a bare sibling of the switcher would stack instead —
    // a layout bug no assertion on mere presence can see, and the reason the row exists.
    expect(Array.from(row.children).map((c) => c.textContent)).toEqual([
      'Custom switcher',
      'Second menu',
    ])
    expect(row.contains(screen.getByText('preview'))).toBe(false)
  })

  it('renders preAuthLinks after the nav links and before the auth cluster', () => {
    render(
      <AdhHeader
        siteName="Hub"
        navLinks={[{ label: 'Docs', href: '/docs' }]}
        // A deliberately GENERIC fixture. adh routes its concept-site link through
        // this slot, but hard-coding that link's path or label here would put adh
        // vocabulary in the toolkit's test tree — the exact coupling the slot exists
        // to prevent. Any placeholder proves the same positional contract.
        preAuthLinks={<a href="/slot-target">Slot link</a>}
        onLogin={() => {}}
        onSignup={() => {}}
      />,
    )
    const nav = screen.getByRole('navigation', { name: 'Primary' })
    const order = (el: Element): number => Array.prototype.indexOf.call(nav.children, el)
    const links = nav.querySelector('.adh-header__links')!
    const slotLink = screen.getByText('Slot link')
    const login = screen.getByText('login')
    // Position is behaviour: the slot is the last thing a signed-out visitor reads
    // before "login / join", and it must not be folded into the ordinary navLinks.
    expect(links.contains(slotLink)).toBe(false)
    expect(order(links)).toBeLessThan(order(slotLink))
    expect(order(slotLink)).toBeLessThan(order(login))
  })

  it('renders accountActions last of the slots, immediately before the auth cluster', () => {
    render(
      <AdhHeader
        siteName="Hub"
        navLinks={[{ label: 'Docs', href: '/docs' }]}
        preAuthLinks={<a href="/slot-target">Slot link</a>}
        // Generic for the same reason `preAuthLinks` above is: adh puts the
        // notification bell here, but naming it would drag adh vocabulary into the
        // registry-free header's tests. The position is the whole contract.
        accountActions={<button type="button">Account thing</button>}
        onLogin={() => {}}
        onSignup={() => {}}
      />,
    )
    const nav = screen.getByRole('navigation', { name: 'Primary' })
    const order = (el: Element): number => Array.prototype.indexOf.call(nav.children, el)
    const links = nav.querySelector('.adh-header__links')!
    const account = screen.getByText('Account thing')
    // Outside `.adh-header__links` — that box is display:none under 768px, and this
    // slot holds account chrome that has to survive a phone.
    expect(links.contains(account)).toBe(false)
    expect(order(screen.getByText('Slot link'))).toBeLessThan(order(account))
    expect(order(account)).toBeLessThan(order(screen.getByText('login')))
  })

  // Nothing renders in the slot's place when a caller passes nothing — an empty slot
  // must not add a wrapper that lands between the links and the auth cluster and
  // spaces them apart on every site in the fleet that passes no account chrome.
  it('renders nothing for an absent accountActions', () => {
    const { container, rerender } = render(
      <AdhHeader siteName="Hub" onLogin={() => {}} onSignup={() => {}} />,
    )
    const nav = (): Element => container.querySelector('.adh-header__nav')!
    const before = nav().children.length
    rerender(
      <AdhHeader
        siteName="Hub"
        accountActions={<button type="button">Account thing</button>}
        onLogin={() => {}}
        onSignup={() => {}}
      />,
    )
    expect(nav().children.length).toBe(before + 1)
  })

  // The site title IS a link to `siteNameHref`, so a navLink pointing at the same place
  // would put one destination in the bar twice. Every family site passes a nav list that
  // starts with its own home entry, so this fires on essentially every page — which is
  // also why nothing screamed when the filter was dropped: a duplicate link looks
  // deliberate.
  it('drops a nav link that just points at the site title', () => {
    render(
      <AdhHeader
        siteName="Hub"
        siteNameHref="/home"
        navLinks={[
          { label: 'Home', href: '/home' },
          { label: 'Docs', href: '/docs' },
        ]}
      />,
    )
    const links = screen.getByRole('banner').querySelector('.adh-header__links')!
    expect(links.textContent).toContain('Docs')
    expect(links.textContent).not.toContain('Home')
    // Non-vacuous: the title itself still renders, so the assertion above is about the
    // nav list and not about an empty header.
    expect(screen.getByText('Hub')).toBeTruthy()
  })

  // …and KEEPS it when the title is not a link at all. A caller-supplied `siteSwitcher`
  // is a menu trigger, which is what every adh site passes — so there is nothing in the
  // bar the link would duplicate, and filtering it deleted hub's signed-out `home → /`
  // outright.
  it('keeps that same link when a caller-supplied switcher replaced the title link', () => {
    render(
      <AdhHeader
        siteName="Hub"
        siteNameHref="/"
        siteSwitcher={<button type="button">Hub menu</button>}
        navLinks={[
          { label: 'home', href: '/' },
          { label: 'Docs', href: '/docs' },
        ]}
      />,
    )
    const links = screen.getByRole('banner').querySelector('.adh-header__links')!
    expect(links.textContent).toContain('home')
    expect(links.textContent).toContain('Docs')
    // Non-vacuous the other way: the default switcher's anchor really is absent, which
    // is the whole reason the link has to stay.
    expect(screen.queryByRole('link', { name: 'Hub' })).toBeNull()
  })

  it('shows a spinner instead of the auth buttons while auth is still resolving', () => {
    render(<AdhHeader siteName="Hub" authLoading onLogin={() => {}} onSignup={() => {}} />)
    expect(screen.getByRole('status', { name: 'Checking sign-in' })).toBeTruthy()
    expect(screen.queryByText('join')).toBeNull()
  })

  // Signing in used to EMPTY the bar, because the avatar dropdown absorbed the whole
  // nav list. The dropdown is an account menu now, so if the bar still emptied a
  // signed-in visitor would have no nav anywhere. Both halves are asserted together:
  // the links are in the bar, and the dropdown is not where they went.
  it('keeps the nav links in the bar when signed in, and out of the account menu', async () => {
    render(
      <AdhHeader
        siteName="Hub"
        navLinks={[{ label: 'Docs', href: '/docs' }]}
        user={{ name: 'Mike Fullerton' }}
        settingsHref="/settings"
        onLogout={() => {}}
      />,
    )
    const links = screen.getByRole('banner').querySelector('.adh-header__links')!
    expect(links.textContent).toContain('Docs')

    fireEvent.click(screen.getByRole('button', { name: 'Open Mike Fullerton menu' }))
    await waitFor(() => expect(screen.getByRole('menu')).toBeInTheDocument())
    const menu = screen.getByRole('menu')
    expect(menu.textContent).toContain('Mike Fullerton')
    expect(
      Array.from(menu.querySelectorAll('[role="menuitem"]')).map((el) => el.textContent),
    ).toEqual(['Home', 'User Settings', 'Log out'])
  })

  // `name` alone is what an account is CALLED, which may be a slug — so it is
  // printed as-is. Only `fullName` asserts "this is a person's name", and only
  // that turns the row into a greeting.
  it('greets by first name when the source supplied one', async () => {
    render(
      <AdhHeader siteName="Hub" user={{ name: 'Mike Fullerton', fullName: 'Mike Fullerton' }} />,
    )
    fireEvent.click(screen.getByRole('button', { name: 'Open Mike Fullerton menu' }))
    await waitFor(() => expect(screen.getByRole('menu')).toBeInTheDocument())
    const name = screen.getByRole('menu').querySelector('.adh-avatar-menu__name')!
    // The FIRST word only, and the whole row's text — `toContain('Welcome')` would
    // pass on "Welcome Mike Fullerton!", which is the form-letter shape.
    expect(name.textContent).toBe('Welcome Mike!')
  })

  it('prints the bare handle when there is no name to greet', async () => {
    // What hub hands over for a user with a slug and no name: the slug labels the
    // account, and nothing claims it is a name. Greeting "Welcome mikefullerton!"
    // is the regression this asserts against.
    render(<AdhHeader siteName="Hub" user={{ name: 'mikefullerton' }} />)
    fireEvent.click(screen.getByRole('button', { name: 'Open mikefullerton menu' }))
    await waitFor(() => expect(screen.getByRole('menu')).toBeInTheDocument())
    const name = screen.getByRole('menu').querySelector('.adh-avatar-menu__name')!
    expect(name.textContent).toBe('mikefullerton')
  })

  // The trigger is the avatar ALONE. The name is still its accessible name (asserted by
  // the getByRole above), so this is about the printed copy, not about a11y.
  //
  // Asserted as an EQUALITY on the trigger's whole text, not as "does it contain the
  // name": the only characters the trigger may print are the avatar's own initials
  // fallback, so any re-introduced name/slug/email span fails this line whatever it
  // is called. (`toContain('Mike Fullerton')` would pass a trigger that printed the
  // slug instead.)
  it('prints only the avatar beside the trigger — no name, slug or email', () => {
    render(<AdhHeader siteName="Hub" user={{ name: 'Mike Fullerton' }} />)
    const trigger = screen.getByRole('button', { name: 'Open Mike Fullerton menu' })
    expect(trigger.textContent).toBe('MF')
  })
})

// The Debug Options door, in each auth state. The bug-glyph dropdown it came from sat
// in the bar for signed-in and signed-out visitors alike; moving its row into the avatar
// menu alone left a signed-out developer no way into the console — including the way to
// switch OFF a console flag saved in localStorage (10x slow animations, say). So the
// header draws one door per state from the one `onDebugOptions`, and never two.
describe('AdhHeader — the Debug Options door', () => {
  const signedOut = { onLogin: () => {}, onSignup: () => {} }

  it('is a Debug Options button after login / join when signed out, and opens the console', () => {
    const onDebugOptions = vi.fn()
    render(<AdhHeader siteName="Hub" {...signedOut} onDebugOptions={onDebugOptions} />)
    const nav = screen.getByRole('navigation', { name: 'Primary' })
    const door = screen.getByRole('button', { name: 'Debug Options' })
    // At the account end of the bar, where the avatar and its row stand signed in:
    // after the auth buttons, not beside the site name where the old glyph was.
    expect(nav.contains(door)).toBe(true)
    const order = (el: Element): number => Array.prototype.indexOf.call(nav.children, el)
    expect(order(screen.getByText('join'))).toBeLessThan(order(door))
    expect(screen.getByRole('banner').querySelector('.adh-header__brand-row')!.contains(door)).toBe(false)

    fireEvent.click(door)
    expect(onDebugOptions).toHaveBeenCalledTimes(1)
  })

  it('keeps the hint out of the name: "Debug Options", described by the hint', () => {
    render(
      <AdhHeader siteName="Hub" {...signedOut} onDebugOptions={() => {}} debugOptionsHint="Sim: prod" />,
    )
    // The name is what a test, a screen reader and a voice command all ask for, and
    // it must not change with the env the developer is simulating.
    const door = screen.getByRole('button', { name: 'Debug Options' })
    expect(door).toHaveAccessibleDescription('Sim: prod')
  })

  it('carries no description without a hint — not even its own name read back', () => {
    render(<AdhHeader siteName="Hub" {...signedOut} onDebugOptions={() => {}} />)
    expect(screen.getByRole('button', { name: 'Debug Options' })).toHaveAccessibleDescription('')
  })

  it('is the avatar-menu row instead when signed in — never a second door in the bar', async () => {
    render(<AdhHeader siteName="Hub" user={{ name: 'Mike Fullerton' }} onDebugOptions={() => {}} />)
    expect(screen.queryByRole('button', { name: 'Debug Options' })).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'Open Mike Fullerton menu' }))
    await waitFor(() => expect(screen.getByRole('menu')).toBeInTheDocument())
    expect(screen.getByRole('menuitem', { name: 'Debug Options' })).toBeInTheDocument()
  })

  it('draws no door while the session is still resolving', () => {
    // Which door applies is not known yet, and a button that vanished as a cached
    // session landed would shift the bar under the visitor's pointer.
    render(<AdhHeader siteName="Hub" authLoading {...signedOut} onDebugOptions={() => {}} />)
    expect(screen.queryByRole('button', { name: 'Debug Options' })).toBeNull()
  })

  it('draws no door for a visitor the caller did not offer it to', () => {
    render(<AdhHeader siteName="Hub" {...signedOut} />)
    expect(screen.queryByRole('button', { name: 'Debug Options' })).toBeNull()
  })
})
