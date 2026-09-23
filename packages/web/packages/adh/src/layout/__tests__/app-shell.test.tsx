import { render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { setHtdvLayoutLog, setSlowAnimations, slowAnimationVars } from '@agenticdevelopertoolkit/ui/blocks'
import { AdhAppShell } from '../AdhAppShell'

// AdhAppShell mounts SlideTransitions, which takes the app router's push; there is no app
// router under vitest, so stand one in.
vi.mock('next/navigation', () => ({ usePathname: () => '/', useRouter: () => ({ push: () => {} }) }))

/**
 * The custom properties `DevAnimScale` writes onto <html>. Read from the implementation rather
 * than hard-coded, so a rename over there can't leave this test asserting on a dead name.
 *
 * These ARE the observable: `DevAnimScale` returns null and renders no element, so there is no
 * markup to query for. Asserting on a DOM node or attribute would pass under every possible
 * implementation — including one with no `devTools` gate at all — and so prove nothing.
 */
const ANIM_VARS = Object.keys(slowAnimationVars())
const appliedAnimVars = (): string[] =>
  ANIM_VARS.filter((name) => document.documentElement.style.getPropertyValue(name) !== '')

afterEach(() => {
  setSlowAnimations(false)
  setHtdvLayoutLog(false)
  for (const name of ANIM_VARS) document.documentElement.style.removeProperty(name)
})

describe('AdhAppShell', () => {
  it('renders header, main and footer in order', () => {
    const { container } = render(
      <AdhAppShell header={<header>H</header>} footer={<footer>F</footer>}>
        <p>body</p>
      </AdhAppShell>,
    )
    expect(screen.getByText('body')).toBeTruthy()
    expect(container.querySelector('main')).toBeTruthy()
    expect(container.textContent).toBe('HbodyF')
  })

  // The next two cases are a matched pair, and only the pair has any force: the SLOW ANIMATIONS
  // switch is on in BOTH, so the only difference between them is the `devTools` prop. Were the
  // gate to regress to unconditional, the false case would find the variables applied and fail.
  it('mounts the dev switches when devTools is true — the slow-animation vars land on <html>', () => {
    setSlowAnimations(true)
    render(
      <AdhAppShell header={null} devTools>
        <p>body</p>
      </AdhAppShell>,
    )
    expect(appliedAnimVars()).toEqual(ANIM_VARS)
  })

  it('omits the dev switches when devTools is false — nothing writes the vars', () => {
    setSlowAnimations(true)
    render(
      <AdhAppShell header={null} devTools={false}>
        <p>body</p>
      </AdhAppShell>,
    )
    expect(appliedAnimVars()).toEqual([])
  })

  it('catches a render crash in children without unmounting the header', () => {
    const Boom = () => {
      throw new Error('boom')
    }
    render(
      <AdhAppShell header={<header>H</header>}>
        <Boom />
      </AdhAppShell>,
    )
    expect(screen.getByText('H')).toBeTruthy()
  })
})
