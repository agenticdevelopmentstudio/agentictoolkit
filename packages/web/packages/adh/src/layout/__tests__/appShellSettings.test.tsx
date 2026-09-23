import { describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { AppShell } from '../AppShell'
import { useSettingsOverlay } from '../../settings/settings-overlay'

// AdhAppShell mounts SlideTransitions, which takes the app router's push; there is no app
// router under vitest, so stand one in.
vi.mock('next/navigation', () => ({ usePathname: () => '/', useRouter: () => ({ push: () => {} }) }))

// AppShell's footer slot renders SiteFooter, and SiteFooter.tsx itself self-references
// '@agentic-toolkit/adh/footer' for the toolkit's AdhFooter primitive — which resolves to the
// WHOLE footer/index.ts barrel, including its `useChatTheme` export from chat-theme-store.ts,
// which statically imports @agentic-toolkit/bitbag, which re-exports theme vocabulary from the
// sibling `agenticdevelopertoolkit` submodule. That submodule has no built dist in this
// worktree — the same pre-existing gap `src/__tests__/footerDock.test.tsx` and
// `footerBitbag.test.tsx` already carry (confirmed: both fail on the identical
// "@agenticdevelopertoolkit/themes" resolution error, even footerBitbag.test.tsx despite it
// already stubbing FooterChat down to a marker — the barrel self-reference reaches bitbag by a
// path that mock doesn't cover). None of it is what this file tests (settings context
// propagation to the header and children slots), so stub the whole footer barrel rather than
// let an already-known-broken, unrelated chain turn this new test red too.
vi.mock('@agentic-toolkit/adh/footer', () => ({
  SiteFooter: () => null,
}))

function Probe() {
  return <span>{useSettingsOverlay() ? 'has settings' : 'no settings'}</span>
}

// Task 8: AppShell mounts SettingsOverlayProvider once so every one of the 45 header-bearing
// sites inherits it from a single seam, rather than each site wiring its own. The provider
// must wrap BOTH the header slot and the children — a page's own useSettingsOverlay() call
// and the avatar menu's User Settings row have to resolve to the SAME context instance.
describe('AppShell', () => {
  it('puts the settings overlay in context for the page', () => {
    render(
      <AppShell header={null}>
        <Probe />
      </AppShell>,
    )
    expect(screen.getByText('has settings')).toBeInTheDocument()
  })

  // The one that matters: the header arrives as a PROP (rendered by the caller before
  // AppShell ever sees it, e.g. SiteHeader) but is rendered INSIDE AdhAppShell — so context
  // only reaches it if the provider wraps at a level that covers the `header` slot too, not
  // just `children`. A provider mounted only around `<main>` would pass the first case above
  // and fail this one.
  it('puts it in context for the header too', () => {
    render(<AppShell header={<Probe />}>{null}</AppShell>)
    expect(screen.getByText('has settings')).toBeInTheDocument()
  })
})
