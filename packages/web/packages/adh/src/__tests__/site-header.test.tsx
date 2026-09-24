import { describe, it, expect, vi, afterEach } from 'vitest'
import { render, screen } from '@testing-library/react'

// The equivalence test for Task 5.6's split. `AdhHeader` (now
// `@agentic-toolkit/adh/header`) resolves NOTHING about adh — it takes a site name,
// a switcher and a pre-auth slot as props. Everything that reads the adh site
// registry stayed on this side, in `SiteHeader`. So what needs pinning is not the
// bar's markup (the toolkit's own header-contract.test.tsx covers that) but that the
// registry half still does its jobs and hands the generic half the right values.

const pathname = vi.hoisted(() => ({ current: '/' }))
vi.mock('next/navigation', () => ({
  usePathname: () => pathname.current,
  useRouter: () => ({ push: vi.fn() }),
}))

// What crossed the boundary, captured on the way out. Wrapping (rather than
// replacing) the toolkit header means the assertions below still run against the
// real bar — this only tees off the props.
const headerProps = vi.hoisted(() => ({ current: null as Record<string, unknown> | null }))
vi.mock('@agentic-toolkit/adh/header', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@agentic-toolkit/adh/header')>()
  return {
    ...actual,
    AdhHeader: (props: Record<string, unknown>) => {
      headerProps.current = props
      return <actual.AdhHeader {...(props as Parameters<typeof actual.AdhHeader>[0])} />
    },
  }
})

// adh's real switcher stands in as a probe, because its contents are already covered by
// header/__tests__/{useSiteMenu,fleetMenuGroups,workspaceMenu}.test — re-rendering the
// whole menu here would test those twice and this file's subject not at all.
//
// That is now the WHOLE reason. While this file lived in the former `@adh/chrome` it carried a
// second one: the switcher is Base-UI-backed, and @base-ui/utils resolved from the
// toolkit workspace's own store, dragging a second React copy in ("Invalid hook call").
// Inside the toolkit there is one workspace and one react, so that constraint is gone —
// the stub is a scoping choice here, not a workaround.
const switcherProps = vi.hoisted(() => ({ current: null as Record<string, unknown> | null }))
vi.mock('../header/SiteMenuSwitcher', () => ({
  SiteMenuSwitcher: (props: Record<string, unknown>) => {
    switcherProps.current = props
    return <div data-testid="adh-site-switcher" />
  },
}))

// The avatar menu, stubbed to keep this file's subject in view: `AvatarMenu` is the only
// thing the header renders when `user != null`, and a signed-in render is exactly what
// the auth source's assertions below need — its whole job is producing `user`. Stubbing
// it means those assertions read the source's output rather than Base UI's markup.
//
// Mocked at its own module path rather than through the `@agentic-toolkit/adh/header`
// barrel above: `AdhHeader.tsx` imports `./AvatarMenu` relatively, so a barrel mock never
// reaches it. A sibling relative path now, not the long `external/agentictoolkit/.../src/`
// form this file carried in the former `@adh/chrome` — that spelling existed only to name a
// file on
// the far side of a workspace boundary, and had to end at `src/` because vitest resolves
// the package's `development` export condition there. Same file either way; this one
// survives the package being consumed standalone.
vi.mock('../header/AvatarMenu', () => ({
  AvatarMenu: (props: { user: { name: string } }) => (
    <div data-testid="adh-avatar-menu">{props.user.name}</div>
  ),
}))

// The notification bell, stubbed for the third reason above and one of its own: the real
// one opens a live SSE wake channel and fetches an unread count the moment it mounts, and
// what this file owns is not the inbox's behaviour but WHO gets one — signed in, on every
// site, from one definition. Stubbing it makes the gate observable in the DOM without a
// single request. It is reached through a `next/dynamic` specifier, so every assertion on
// it has to await the lazy resolve (`findBy…`).
vi.mock('@agentic-toolkit/messaging/components/notification-bell', () => ({
  NotificationBell: () => <div data-testid="adh-notification-bell" />,
}))

import { SiteHeader } from '../header/SiteHeader'
import { getSite, siteHeaderTitle, SITES } from '@agentic-toolkit/adh-registry'
import type { HeaderAuthSourceOptions, HeaderAuthState } from '@agentic-toolkit/adh/header-auth'
import { SettingsOverlayProvider } from '@agentic-toolkit/adh/settings'

/** The centred label as it reaches the DOM. */
const centreTitle = (): string | null =>
  screen.getByRole('banner').querySelector('.adh-header__page-title')?.textContent ?? null

describe('SiteHeader', () => {
  it('resolves the brand from the registry rather than taking it as a prop', () => {
    render(<SiteHeader siteId="products" />)
    // Registry-derived, not the raw id: `getSite` + `siteHeaderTitle`, both chrome's
    // to call. adh always fills the switcher slot, so this value reaches no rendered
    // node today — which is exactly why it needs pinning at the boundary instead.
    expect(headerProps.current?.siteName).toBe(siteHeaderTitle(getSite('products')!))
  })

  // The bar says WHICH SITE you are on, centred — and it is the only thing that does:
  // the switcher trigger reads the hub brand on every site in the family.
  it("centres this site's short name — the one the site menu lists it under", () => {
    render(<SiteHeader siteId="cookbook" />)
    const site = getSite('cookbook')!
    expect(centreTitle()).toBe(site.label)
    // Non-vacuous, and the whole point of naming `label` rather than reusing the brand
    // already resolved beside it: for this site the two genuinely differ, so a header
    // that centred `siteName` would print "Agentic Developer Cookbook" and pass a bare
    // "is something centred?" check.
    expect(site.label).not.toBe(siteHeaderTitle(site))
    expect(centreTitle()).not.toBe(siteHeaderTitle(site))
  })

  // Every site, not "the ones that opted in": the name is the DEFAULT of a prop each
  // site already passes through, so the fleet-wide claim is testable in one place. This
  // also pins that no site falls through to the raw id — `site?.label ?? siteId` prints
  // an id for anything the registry has lost, which reads as a bug in the header rather
  // than as the missing entry it is.
  it('centres a registry name on every site in the fleet, never a bare id', () => {
    for (const site of SITES) {
      const { unmount } = render(<SiteHeader siteId={site.id} />)
      expect(headerProps.current?.pageTitle).toBe(site.label)
      expect(headerProps.current?.pageTitle).not.toBe(site.id)
      unmount()
    }
  })

  // The centre is ONE absolutely-positioned box, so a page that names itself takes it
  // over rather than stacking on top of the site name.
  it('lets a page title replace the site name in the centre', () => {
    render(<SiteHeader siteId="cookbook" pageTitle="Recipes" />)
    expect(centreTitle()).toBe('Recipes')
    expect(screen.queryByText(getSite('cookbook')!.label)).toBeNull()
  })

  // Same slot, same rule, for the interactive form of it.
  it('lets centre content replace the site name too', () => {
    render(<SiteHeader siteId="cookbook" center={<span>live</span>} />)
    expect(screen.getByRole('banner').querySelector('.adh-header__page-title')).toBeNull()
    expect(screen.getByText('live')).toBeTruthy()
  })

  it("fills the toolkit header's switcher slot with adh's own registry-bound menu", () => {
    render(<SiteHeader siteId="products" />)
    expect(headerProps.current?.siteSwitcher).toBeTruthy()
    expect(screen.getByTestId('adh-site-switcher')).toBeTruthy()
    // Never both, and this has to be asserted against what the default switcher
    // ACTUALLY renders here. An earlier version looked for the popover trigger's
    // `<siteName> — switch site` label, which cannot fail: `SiteHeader` never passes
    // `sites`, so the default renders its no-targets form — a plain
    // `.adh-header__title` link — and that label is absent whether the slot works or
    // not. The lead slot holding the probe and nothing title-shaped is the real pin:
    // drop `siteSwitcher` from SiteHeader and this line goes red.
    const lead = screen.getByRole('banner').querySelector('.adh-header__lead')!
    expect(lead.querySelector('.adh-header__title')).toBeNull()
    // The brand ROW, not the lead: the lead is a column that also stacks the badges,
    // so the switcher's own position is one level in (see .adh-header__brand-row).
    expect(lead.querySelector('.adh-header__brand-row')?.firstElementChild).toBe(
      screen.getByTestId('adh-site-switcher'),
    )
    // The switcher gets the current site and the registry-resolved settings target.
    expect(switcherProps.current?.currentSiteId).toBe('products')
    // `/settings` — the hub's account pages, which used to hang off `/home` and moved when
    // that segment became the family's workspace redirect. Asserted as a substring because
    // this is a satellite, so the value is the hub's absolute URL for it.
    expect(switcherProps.current?.settingsHref).toContain('/settings')
  })

  it('adds the "Details" link on a concept site and omits it elsewhere', () => {
    // `isConceptSite` and the `/details` path are adh vocabulary and stayed here; the
    // toolkit only knows it was handed some nodes for its `preAuthLinks` slot.
    const { unmount } = render(<SiteHeader siteId="products" />)
    expect(screen.getByRole('link', { name: 'Details' }).getAttribute('href')).toBe('/details')
    unmount()

    render(<SiteHeader siteId="hub" />)
    expect(screen.queryByRole('link', { name: 'Details' })).toBeNull()
  })

  it('sends signed-out auth to the hub with a return_to back to this site', () => {
    render(<SiteHeader siteId="products" />)
    // Resolved HERE (siteUrl/siteProdUrl + siteHomePath) and handed over as plain
    // strings, so the toolkit never learns what a site id is.
    for (const [name, path] of [
      ['login', '/login'],
      ['join', '/signup'],
    ] as const) {
      const href = screen.getByRole('link', { name }).getAttribute('href') ?? ''
      expect(href).toContain(path)
      expect(href).toContain('return_to=')
    }
  })

  it('lets a site override the auth hrefs the registry would otherwise supply', () => {
    render(<SiteHeader siteId="products" loginHref="/login" signupHref="/signup" />)
    expect(screen.getByRole('link', { name: 'login' }).getAttribute('href')).toBe('/login')
    expect(screen.getByRole('link', { name: 'join' }).getAttribute('href')).toBe('/signup')
  })
})

// Task 6.2: the pluggable auth source, folded in from the retired @adh-shared auth shim's SiteHeader
// (which wrapped this one purely to inject it). One component now, so a site cannot get
// the registry half without the auth half or vice versa.
describe('SiteHeader auth source injection', () => {
  it('invokes the injected source and forwards its auth state to the header', () => {
    const onAfterLogout = vi.fn()
    const useFakeSource = vi.fn(
      (_opts: HeaderAuthSourceOptions): HeaderAuthState => ({
        // Name only — AvatarMenuUser carries no email, so a source cannot hand one
        // across and no header surface can print one.
        user: { name: 'Ada' },
        userIsAdmin: true,
        onLogin: () => {},
        onLogout: () => {},
      }),
    )
    render(
      <SiteHeader
        siteId="hub"
        clientId="demo"
        onAfterLogout={onAfterLogout}
        useAuthSource={useFakeSource}
      />,
    )
    // Invoked AS a hook — unconditionally, on EVERY render, with the per-site options
    // forwarded. `siteId` rides along with the two auth props: a session-aware source
    // resolves THIS site's post-login landing from it (see makeSmartHeaderAuth's
    // defaultReturnTo), and one source instance is shared across a whole site family,
    // so it cannot be closed over at construction. Deliberately not pinned to a single
    // call: `useClientHost` resolves the hostname in a mount effect, so the header
    // renders twice here, and a source that ran only on the first render would be the
    // bug rather than the contract.
    expect(useFakeSource).toHaveBeenCalled()
    for (const [opts] of useFakeSource.mock.calls) {
      expect(opts).toEqual({ clientId: 'demo', siteId: 'hub', onAfterLogout })
    }
    // ...and everything it returned crossed into the bar: `user` to the toolkit header,
    // the derived signed-in flag on to adh's own switcher, and `userIsAdmin` both to the
    // switcher and to the avatar menu's Debug Options door. Both menus are stubbed above,
    // so what is observable here is the value each was handed — the avatar stub prints the name — not the bar's printed copy,
    // which is now the avatar alone (pinned in the toolkit's own
    // header-contract.test.tsx).
    expect(screen.getByTestId('adh-avatar-menu').textContent).toBe('Ada')
    expect(headerProps.current?.user).toEqual({ name: 'Ada' })
    expect(switcherProps.current?.authenticated).toBe(true)
    // An admin is offered Debug Options in every env — as the avatar menu's last row. The
    // bug-glyph dropdown that used to hold it in the `debugMenu` slot is deleted, and
    // SiteHeader leaves the slot empty for every visitor, signed in or out.
    expect(typeof headerProps.current?.onDebugOptions).toBe('function')
    expect(headerProps.current?.debugMenu).toBeUndefined()
    // The site menu gets it too — it is what adds the admin consoles section. What
    // must NOT reach it is `routes`, the old dev-tools list: that is a fact about the
    // BUILD, and the site menu renders the same rows in a dev build and a shipped one.
    // Who is signed in is a different question, and it is allowed to change the menu.
    expect(switcherProps.current?.userIsAdmin).toBe(true)
    expect(switcherProps.current).not.toHaveProperty('routes')
  })

  it('resolves the function form of navLinks against the signed-in flag', () => {
    const useAnonymous = (): HeaderAuthState => ({ user: null })
    render(
      <SiteHeader
        siteId="hub"
        useAuthSource={useAnonymous}
        navLinks={(signedIn) =>
          signedIn ? [{ label: 'Workspace', href: '/w' }] : [{ label: 'Pricing', href: '/pricing' }]
        }
      />,
    )
    // Resolved AFTER the source ran, so a site varies its nav by auth state without
    // reading auth itself.
    expect(screen.getByText('Pricing')).toBeTruthy()
    expect(screen.queryByText('Workspace')).toBeNull()
  })

  it('defaults to the anonymous source, which never reads a session', () => {
    // The status board renders the family bar with NO adh AuthProvider above it, so a
    // default source that called `useAuth()` would crash the whole site.
    expect(() => render(<SiteHeader siteId="status" />)).not.toThrow()
  })
})

// The signed-out half of the Debug Options door, through the whole chain: SiteHeader's
// gate, the prop it hands the bar, and the button the bar draws. Moving the door into the
// avatar menu once left a signed-out developer with no way into the console at all — on
// `status` (whose source never signs anyone in) permanently — and with no way to switch
// OFF a console flag already saved in localStorage.
describe('SiteHeader — Debug Options for a signed-out visitor', () => {
  const anonymous = (): HeaderAuthState => ({ user: null })

  afterEach(() => {
    vi.unstubAllEnvs()
    vi.resetModules()
  })

  // The build flag folds at MODULE LOAD from NEXT_PUBLIC_DEPLOYMENT_ENV, so each build
  // is a fresh module registry under a freshly-stubbed env (the mocks above survive a
  // reset). jsdom's host is `localhost`, so the REAL env is `local` in both cases: what
  // differs is only the build, which is the one thing that gates an ordinary visitor.
  async function siteHeaderBuiltFor(env: string) {
    vi.resetModules()
    vi.stubEnv('NEXT_PUBLIC_DEPLOYMENT_ENV', env)
    return (await import('../header/SiteHeader')).SiteHeader
  }

  // The real env comes from the host, which `useClientHost` resolves in a mount effect.
  // `render` flushes that effect and its re-render inside act() before it returns, so a
  // synchronous query already sees the settled bar — which is what the two positive
  // cases prove by using `getBy`, and what keeps the negative case below from passing
  // on a first render that had no host yet.
  it('draws the Debug Options button in a dev build, on the site that never signs anyone in', async () => {
    const Header = await siteHeaderBuiltFor('local')
    render(<Header siteId="status" />)
    expect(screen.getByRole('button', { name: 'Debug Options' })).toBeInTheDocument()
    expect(headerProps.current?.user).toBeNull()
  })

  it('draws it for an anonymous visitor on any other site too', async () => {
    const Header = await siteHeaderBuiltFor('staging')
    render(<Header siteId="hub" useAuthSource={anonymous} />)
    expect(screen.getByRole('button', { name: 'Debug Options' })).toBeInTheDocument()
  })

  it('draws nothing for an ordinary signed-out visitor in a production build', async () => {
    const Header = await siteHeaderBuiltFor('production')
    render(<Header siteId="hub" useAuthSource={anonymous} />)
    expect(headerProps.current?.onDebugOptions).toBeUndefined()
    expect(screen.queryByRole('button', { name: 'Debug Options' })).toBeNull()
  })
})

// The notification inbox reaches every site through THIS component, and that is the
// whole design: it is the only surface for account and announcement notifications, so it
// follows the SESSION rather than the site. A visitor signed in on `projects` has the
// same unread mail as on the hub. Mounting it per-site instead would mean 45 opt-ins and
// a bell that appears only after someone navigates to whichever site remembered to pass
// it — which is exactly the state this replaced (hub passed one; nothing else did).
describe('SiteHeader notification bell', () => {
  const signedIn = (): HeaderAuthState => ({ user: { name: 'Ada' } })

  it('mounts the bell for a signed-in visitor of a site that asks for nothing', async () => {
    // `projects` is the point: it passes no bell, knows nothing about messaging, and
    // gets one anyway. A test that used `hub` would pass on the old per-site wiring too.
    render(<SiteHeader siteId="projects" useAuthSource={signedIn} />)
    expect(await screen.findByTestId('adh-notification-bell')).toBeTruthy()
  })

  it('mounts no bell for an anonymous visitor', async () => {
    render(<SiteHeader siteId="projects" useAuthSource={(): HeaderAuthState => ({ user: null })} />)
    // Absence needs the lazy boundary to have SETTLED to be worth anything — a cold
    // query passes while the chunk is still resolving, so it would pass even if the bell
    // were mounted unconditionally. Wait on something the same render produces, then
    // assert. The header ships on every PUBLIC page in the family, so this is what keeps
    // an anonymous visitor from opening an SSE channel and fetching an inbox.
    expect(await screen.findByRole('banner')).toBeTruthy()
    expect(screen.queryByTestId('adh-notification-bell')).toBeNull()
    // Non-vacuous: the same query DOES find it once someone is signed in (above).
  })

  it('mounts no bell on the site whose auth source never reads a session', async () => {
    // `status` is the one site with no `/api` BFF rewrite, so a bell there would fetch a
    // notifications endpoint that does not exist. It never reaches that: its source is
    // the anonymous one, `user` is always null, and the gate is the same `user` the
    // avatar cluster reads — the two cannot disagree about who is signed in.
    render(<SiteHeader siteId="status" />)
    expect(await screen.findByRole('banner')).toBeTruthy()
    expect(screen.queryByTestId('adh-notification-bell')).toBeNull()
  })
})

// SiteHeader falls back to the shared SettingsOverlayProvider's openSettings when
// a site's own auth source/overrides supply no onSettings. `resolvedOnSettings` is what
// crosses into AdhHeader (the avatar menu's User Settings row) and into the switcher's own
// gear (switcherSettingsHref / SiteMenuSwitcher's onSettings) — see SiteHeader.tsx's own
// comment above that computation for the full precedence.
describe('SiteHeader — the shared settings overlay', () => {
  const useSignedIn = (): HeaderAuthState => ({ user: { name: 'Ada' } })

  it("falls back to the context's openSettings when signed in and no override was supplied", () => {
    render(
      <SettingsOverlayProvider>
        <SiteHeader siteId="hub" useAuthSource={useSignedIn} />
      </SettingsOverlayProvider>,
    )
    expect(typeof headerProps.current?.onSettings).toBe('function')
    // The brand gear follows the same rule: a real handler means the switcher gets no
    // fallback href, so it renders the in-app affordance rather than a link.
    expect(switcherProps.current?.onSettings).toBe(headerProps.current?.onSettings)
    expect(switcherProps.current?.settingsHref).toBeUndefined()
  })

  it("prefers the site's own onSettings over the context's, even when a provider is mounted", () => {
    const ownOnSettings = vi.fn()
    render(
      <SettingsOverlayProvider>
        <SiteHeader siteId="hub" useAuthSource={useSignedIn} onSettings={ownOnSettings} />
      </SettingsOverlayProvider>,
    )
    expect(headerProps.current?.onSettings).toBe(ownOnSettings)
    expect(switcherProps.current?.onSettings).toBe(ownOnSettings)
  })

  it('omits onSettings for a signed-out visitor even though a provider is mounted', () => {
    const useAnonymous = (): HeaderAuthState => ({ user: null })
    render(
      <SettingsOverlayProvider>
        <SiteHeader siteId="hub" useAuthSource={useAnonymous} />
      </SettingsOverlayProvider>,
    )
    expect(headerProps.current?.onSettings).toBeUndefined()
    expect(switcherProps.current?.onSettings).toBeUndefined()
    // The avatar row is correctly omitted — but the switcher's own gear is not left
    // dangling: with no handler to prefer, switcherSettingsHref falls back to a real
    // '/settings' link, so SiteMenu.tsx (commandTrailing, ~line 412) still renders it
    // as a live anchor rather than a dead button.
    expect(switcherProps.current?.settingsHref).toContain('/settings')
  })

  it("omits only the avatar menu's User Settings row when signed in with no provider above it — the switcher's gear still gets a real settingsHref", () => {
    // No <SettingsOverlayProvider> here: a host that renders SiteHeader outside the
    // shared AppShell (or a test like this one) must not throw. `onSettings` is
    // undefined either way, so the AVATAR menu's row is omitted (AvatarMenu.tsx has
    // nothing to call) — but the switcher is not left with a dead gear: with no
    // handler to prefer, switcherSettingsHref still resolves to a real '/settings'
    // link, and SiteMenu.tsx renders that as a live anchor (same branch as above).
    expect(() => render(<SiteHeader siteId="hub" useAuthSource={useSignedIn} />)).not.toThrow()
    expect(headerProps.current?.onSettings).toBeUndefined()
    expect(switcherProps.current?.settingsHref).toContain('/settings')
  })
})

describe('site name help', () => {
  it('asks for site-title help when the page named nothing', () => {
    render(<SiteHeader siteId="cookbook" />)
    expect(headerProps.current?.pageTitleHelp).toBe('site-title')
  })

  it('asks for no help when the page named itself', () => {
    render(<SiteHeader siteId="cookbook" pageTitle="Billing settings" />)
    expect(headerProps.current?.pageTitleHelp).toBeUndefined()
  })

  // The two props have to answer the SAME question. `pageTitle` falls back to the
  // site name with `??`, which keeps an empty string — so an empty string is a page
  // naming itself, and a truthiness test here would annotate that blank title with
  // copy about the site instead.
  it('asks for no help when the page named itself with an empty string', () => {
    render(<SiteHeader siteId="cookbook" pageTitle="" />)
    expect(headerProps.current?.pageTitle).toBe('')
    expect(headerProps.current?.pageTitleHelp).toBeUndefined()
  })

  // `admin`, `hub-help` and `status` mount no populated help provider — they have
  // no `site.config.ts`, so `defineSite` never runs for them. The registry's own
  // description is defined for every site and keeps the title explained there.
  it('offers the registry description as the fallback copy', () => {
    render(<SiteHeader siteId="cookbook" />)
    expect(headerProps.current?.pageTitleHelpFallback).toBe(getSite('cookbook')?.description)
    expect(headerProps.current?.pageTitleHelpFallback).toBeTruthy()
  })

  it('has a description in the registry for every site, so no site is left unexplained', () => {
    const missing = SITES.filter((s) => !s.description).map((s) => s.id)
    expect(missing).toEqual([])
  })
})

describe('the Details link', () => {
  afterEach(() => {
    pathname.current = '/'
  })

  it('shows on the landing page of a concept site', () => {
    pathname.current = '/'
    render(<SiteHeader siteId="projects" />)
    expect(screen.getByRole('link', { name: 'Details' })).toBeInTheDocument()
  })

  it('is absent on an inner page of the same site', () => {
    pathname.current = '/recipes'
    render(<SiteHeader siteId="projects" />)
    expect(screen.queryByRole('link', { name: 'Details' })).toBeNull()
  })

  it('is absent on the details page itself', () => {
    pathname.current = '/details'
    render(<SiteHeader siteId="projects" />)
    expect(screen.queryByRole('link', { name: 'Details' })).toBeNull()
  })
})
