// @vitest-environment jsdom
import { render, screen, fireEvent, cleanup, renderHook } from '@testing-library/react'
import { describe, it, expect, afterEach, vi } from 'vitest'
import { UserSettingsOverlay } from '../UserSettingsOverlay'
import { useSettingsOverlay } from '../settings-overlay'
import { useSettingsDirty } from '@agentic-toolkit/resource'

// This package's vitest config sets `globals: true` but has no auto-cleanup setup file, so
// — same as workspaceChromeGuard.test.tsx — each test's render must be torn down explicitly
// or the next test's queries see BOTH mounted trees.
afterEach(cleanup)

// SettingsLayout calls useRouter() unconditionally (it only falls back to router.push
// when onNavigate is absent, but the hook itself always runs), and there's no app router
// context under vitest. The overlay always supplies onNavigate, so push is never invoked.
vi.mock('next/navigation', () => ({ useRouter: () => ({ push: vi.fn() }) }))

// Stand-in for the real Account/Subscription/... topic list (buildSettingsTopics), which
// pulls in live API/context-bound panels this test has no business rendering. Topic "a"'s
// content reports dirty on click, the same shape a real panel uses (reportDirty from a
// form's onChange) — so the test controls exactly when the overlay is dirty. Split across
// two mocks, registry and topics, because UserSettingsOverlay.tsx imports them from two
// separate modules now (hub had both co-located in one file). topics is mocked by its
// PACKAGE-PATH specifier, not './topics' — UserSettingsOverlay.tsx imports it that way (see
// that file's own comment: it's the one route a Server Component outside this package may
// also use, so this file matches it rather than importing relatively), and vitest mocks
// match the exact specifier string a module imports, not the file it resolves to.
vi.mock('../registry', () => ({
  buildSettingsTopics: () => [
    { id: 'a', label: 'Topic A', href: '/a', content: <PanelA /> },
    { id: 'b', label: 'Topic B', href: '/b', content: <div>Topic B content</div> },
  ],
}))
vi.mock('@agentic-toolkit/adh/settings/topics', () => ({ DEFAULT_SETTINGS_TOPIC: 'a' }))

function PanelA() {
  const { reportDirty } = useSettingsDirty()
  return (
    <div>
      <p>Topic A content</p>
      <button type="button" onClick={() => reportDirty('a', true)}>
        Edit A
      </button>
    </div>
  )
}

function makeDirty() {
  fireEvent.click(screen.getByRole('button', { name: 'Edit A' }))
}

describe('UserSettingsOverlay — tab switch and close both route through the unsaved-changes alert', () => {
  it('switches topics immediately when nothing is dirty', () => {
    render(<UserSettingsOverlay open onOpenChange={vi.fn()} />)
    fireEvent.click(screen.getByRole('button', { name: 'Topic B' }))
    expect(screen.getByText('Topic B content')).toBeTruthy()
    expect(screen.queryByRole('button', { name: 'Discard' })).toBeNull()
  })

  it('guards a dirty tab switch instead of changing topic immediately', () => {
    render(<UserSettingsOverlay open onOpenChange={vi.fn()} />)
    makeDirty()
    fireEvent.click(screen.getByRole('button', { name: 'Topic B' }))
    expect(screen.queryByText('Topic B content')).toBeNull()
    expect(screen.getByText('Topic A content')).toBeTruthy()
    expect(screen.getByRole('button', { name: 'Discard' })).toBeTruthy()
    expect(screen.getByRole('button', { name: 'Stay' })).toBeTruthy()
  })

  it('Discard on a guarded tab switch proceeds to the new topic', () => {
    render(<UserSettingsOverlay open onOpenChange={vi.fn()} />)
    makeDirty()
    fireEvent.click(screen.getByRole('button', { name: 'Topic B' }))
    fireEvent.click(screen.getByRole('button', { name: 'Discard' }))
    expect(screen.getByText('Topic B content')).toBeTruthy()
  })

  it('Stay on a guarded tab switch keeps the original topic', () => {
    render(<UserSettingsOverlay open onOpenChange={vi.fn()} />)
    makeDirty()
    fireEvent.click(screen.getByRole('button', { name: 'Topic B' }))
    fireEvent.click(screen.getByRole('button', { name: 'Stay' }))
    expect(screen.queryByRole('button', { name: 'Discard' })).toBeNull()
    expect(screen.getByText('Topic A content')).toBeTruthy()
  })

  it('does not use window.confirm on close', () => {
    const confirmSpy = vi.spyOn(window, 'confirm')
    const onOpenChange = vi.fn()
    render(<UserSettingsOverlay open onOpenChange={onOpenChange} />)
    makeDirty()
    fireEvent.click(screen.getByRole('button', { name: 'Close' }))
    expect(confirmSpy).not.toHaveBeenCalled()
    expect(onOpenChange).not.toHaveBeenCalled()
    expect(screen.getByRole('button', { name: 'Discard' })).toBeTruthy()
    expect(screen.getByRole('button', { name: 'Stay' })).toBeTruthy()
  })

  it('Discard on a guarded close proceeds to close the overlay', () => {
    const onOpenChange = vi.fn()
    render(<UserSettingsOverlay open onOpenChange={onOpenChange} />)
    makeDirty()
    fireEvent.click(screen.getByRole('button', { name: 'Close' }))
    fireEvent.click(screen.getByRole('button', { name: 'Discard' }))
    expect(onOpenChange).toHaveBeenCalledWith(false)
  })

  it('Stay on a guarded close keeps the overlay open', () => {
    const onOpenChange = vi.fn()
    render(<UserSettingsOverlay open onOpenChange={onOpenChange} />)
    makeDirty()
    fireEvent.click(screen.getByRole('button', { name: 'Close' }))
    fireEvent.click(screen.getByRole('button', { name: 'Stay' }))
    expect(onOpenChange).not.toHaveBeenCalled()
    expect(screen.getByText('Topic A content')).toBeTruthy()
  })
})

describe('UserSettingsOverlay — sized by the shared dialog’s classes, never an inline style', () => {
  // It used to carry its own copy of the phone sheet as an inline style behind a hand-typed
  // `(max-width: 639px)` query. A style beats every class at every width, so that copy overrode
  // the shared dialog wholesale, and flipped at a different width than Tailwind's `sm`. The sheet
  // is now DialogContent's `sheetOnPhone`, and the desktop footprint `sm:` classes that give way
  // to it at exactly that line.
  it('asks the shared dialog for its phone sheet and sizes the desktop footprint with sm: classes', () => {
    render(<UserSettingsOverlay open onOpenChange={vi.fn()} />)
    const popup = screen.getByRole('dialog')
    const classes = popup.className.split(/\s+/)
    expect(classes).toContain('max-sm:inset-0')
    expect(classes).toContain('max-sm:h-dvh')
    expect(classes).toContain('sm:w-[min(72rem,calc(100vw-2rem))]')
    expect(classes).toContain('sm:h-[min(56rem,calc(100dvh-2rem))]')
    for (const prop of ['width', 'height', 'maxWidth', 'maxHeight', 'borderWidth', 'paddingTop'] as const)
      expect(popup.style[prop], prop).toBe('')
  })
})

describe('useSettingsOverlay — the `| null` contract', () => {
  it('returns null when there is no provider above it', () => {
    const { result } = renderHook(() => useSettingsOverlay())
    expect(result.current).toBeNull()
  })
})
