'use client'

import { useCallback, useEffect, useRef, type ReactNode, type RefObject } from 'react'
import dynamic from 'next/dynamic'
import { MessagesSquare, Palette, SlidersHorizontal, SquareTerminal } from 'lucide-react'
import type { TopicLevel } from '@agenticdevelopertoolkit/ui/blocks'
import { HierarchicalDetailView } from '@agenticdevelopertoolkit/ui/blocks'
import { EmptyState } from '@agenticdevelopertoolkit/ui/components/empty-state'
import { DEV_BUILD } from '@agentic-toolkit/adh-registry/deployment-env'
import { FloatingWindow } from './FloatingWindow'
import { useDebugConsoleConfig } from './DebugConsoleProvider'
import { EnvironmentPanel } from './EnvironmentPanel'
import { SettingsPanel } from './SettingsPanel'
import { buildChatThemeLevel, ChatThemePreview } from './ChatThemePanel'
import { usePersistedSelection } from './selection-store'
import type { LeaveGuardRef } from './SiteThemeConsole'
import type { EnvOverrideSurface, ThemeAreasLoader } from './seams'

type Top = 'environment' | 'settings' | 'site-theme' | 'chat-theme'

const TOP_ITEMS = [
  { id: 'settings', label: 'Settings', icon: <SlidersHorizontal /> },
  { id: 'environment', label: 'Environment', icon: <SquareTerminal /> },
  { id: 'site-theme', label: 'Site theme', icon: <Palette /> },
  { id: 'chat-theme', label: 'Chat theme', icon: <MessagesSquare /> },
] as const

/**
 * Which root topics this build offers. Pure, and takes both facts as arguments, so the
 * production gate is directly assertable — the alternative (reading DEV_BUILD inline) can
 * only be checked by rendering the whole console, and a gate that is awkward to test is a
 * gate that silently stops holding.
 *
 * `devBuild` decides whether Site theme exists AT ALL: production has no site-theme editor,
 * admin or not (see {@link SiteThemeConsole} for why the door can't be the gate).
 * `hasChatTheme` follows the host's injected config.
 */
export function rootTopicsFor({
  devBuild,
  hasChatTheme,
}: {
  devBuild: boolean
  hasChatTheme: boolean
}): readonly (typeof TOP_ITEMS)[number][] {
  return TOP_ITEMS.filter(
    (t) => (t.id !== 'chat-theme' || hasChatTheme) && (t.id !== 'site-theme' || devBuild),
  )
}

/**
 * The site-theme editor, loaded on demand — and ONLY in a build that carries dev tooling.
 *
 * Production's bundle contains none of what hangs off it: the theme-editor state, the
 * persistence client, the host's injected THEME_AREAS taxonomy, and Monaco. Both halves of
 * the gate are load-bearing and both are spelled out in the chunk-gate contract in
 * adh-registry's deployment-env — the comparisons are written out (rather than `DEV_BUILD`) so webpack
 * folds them while parsing and never registers the import(), and the specifier is the
 * package subpath (`external` + its own tsup entry) so the boundary survives the dist
 * build. Written the obvious way — `DEV_BUILD ? dynamic(() => import('./SiteThemeConsole'))`
 * — this shipped the editor and a ~110 KB Monaco chunk to production while looking exactly
 * like a gate.
 *
 * This is a SECOND, independent gate, and it is the load-bearing one. The console's own
 * door — the "Debug Options" row at the end of the avatar menu (`useDebugOptions`, and
 * the same row in {@link DevToolsMenu} for a host that still mounts it) — also opens
 * for a signed-in adh admin in production, which used to hand that admin a half-working site-theme
 * editor: no alt-theme <style> nodes exist in production, so nothing could actually be
 * switched, but the editor still opened and still applied live override CSS. Gating on the
 * BUILD rather than on the viewer removes the feature from production outright.
 */
const SiteThemeConsole =
  process.env.NEXT_PUBLIC_DEPLOYMENT_ENV === 'local' ||
  process.env.NEXT_PUBLIC_DEPLOYMENT_ENV === 'testing' ||
  process.env.NEXT_PUBLIC_DEPLOYMENT_ENV === 'staging'
    ? dynamic(() =>
        import('@agentic-toolkit/adh/debug-env/SiteThemeConsole').then((m) => m.SiteThemeConsole),
      )
    : null

/**
 * The unified Debug console window — a backdrop-less {@link FloatingWindow} whose
 * {@link HierarchicalDetailView} stack hosts every debug topic (Settings / Environment /
 * Site theme / Chat theme), cascading or covered as the platform's hierarchical-view flag
 * decides. Fully controlled: the caller (the shared SiteMenu's "Debug Options" row) owns
 * `open` state and decides WHO may open the console — this component has no trigger of its
 * own and makes no runtime judgement about the viewer. The caller also INJECTS the two host
 * surfaces this package deliberately does not own: the environment-override store and the
 * theme taxonomy (see `./seams`).
 *
 * It does apply one gate of its own, and deliberately: which TOPICS this build contains.
 * The caller's door opens for a production admin, so a topic that must not exist in
 * production cannot be gated at the door — see {@link SiteThemeConsole}.
 *
 * The heavy work (theme editor + env fetch) lives in {@link DebugConsoleBody}, which
 * only mounts while the window is open (FloatingWindow returns `null` when closed).
 */
export type DebugConsoleWindowProps = {
  open: boolean
  onClose: () => void
  /** The host's environment-override store — see {@link EnvOverrideSurface}. */
  envOverride: EnvOverrideSurface
  /** Loads the host's theme taxonomy + CSS editor — see {@link ThemeAreasLoader}. Passed
   *  straight through to the (env-gated) site-theme topic; never called here. */
  themeAreas: ThemeAreasLoader
}

export function DebugConsoleWindow({
  open,
  onClose,
  envOverride,
  themeAreas,
}: DebugConsoleWindowProps) {
  // The window's close action, owned by the body so a dirty Site-theme draft can guard it
  // (set via effect below). Defaults to the caller's plain close for the window's own
  // Escape/× before the body has mounted.
  const closeRef = useRef<() => void>(onClose)
  closeRef.current = onClose

  return (
    <FloatingWindow open={open} onClose={() => closeRef.current()} title="Debug Options">
      <DebugConsoleBody
        onClose={onClose}
        closeRef={closeRef}
        envOverride={envOverride}
        themeAreas={themeAreas}
      />
    </FloatingWindow>
  )
}

/** Rendered only while the window is open (FloatingWindow returns null when closed), so the
 *  theme fetch / env fetch stay lazy. */
function DebugConsoleBody({
  onClose,
  closeRef,
  envOverride,
  themeAreas,
}: {
  onClose: () => void
  closeRef: RefObject<() => void>
  envOverride: EnvOverrideSurface
  themeAreas: ThemeAreasLoader
}) {
  const config = useDebugConsoleConfig()

  // Available root topics — see rootTopicsFor. This feeds the stored-selection validator
  // below, so a persisted topic that this build doesn't offer falls back instead of selecting
  // a row that isn't there.
  const rootItems = rootTopicsFor({ devBuild: DEV_BUILD, hasChatTheme: config.chatTheme != null })

  // Nullable, and it MUST stay that way: the root topic is a real level of the stack, so it has to
  // be clearable like any other. In NARROW mode the visible pane is the deepest one the selection
  // reaches — a permanently-selected root means the detail is always the top pane, the topic list
  // sits inert behind it, and Back (which pops by clearing the deepest selected level) has nothing
  // to clear. Restored from the last time the window was shown; Environment on a first visit, as
  // the wide layout always has. Validated against `rootItems`, so a stored `chat-theme` on a host
  // that no longer injects a chat config falls back rather than selecting a topic that isn't there.
  const [top, setTop] = usePersistedSelection<Top>(
    'top',
    (id) => rootItems.some((t) => t.id === id),
    'environment',
  )
  // The unsaved-changes guard of whichever topic is mounted, lent upward by that topic
  // (only Site theme has a draft to lose). Held in a ref rather than state because the
  // topic that owns the draft is now a lazily-loaded child: the body has to be able to ask
  // "may I unmount you?" without knowing what is mounted or re-rendering to find out.
  const leaveRef: LeaveGuardRef = useRef<((run: () => void) => void) | null>(null)
  const leave = useCallback((run: () => void) => {
    const guard = leaveRef.current
    if (guard) guard(run)
    else run()
  }, [])

  // Leaving the topic with a dirty draft prompts (via the topic's guard).
  const setTopGuarded = (next: Top | null) => leave(() => setTop(next))

  // Route the window's close (Escape / × / onClose) through the same guard: closing a dirty
  // Site-theme draft prompts (save / discard / stay) before the window disappears.
  useEffect(() => {
    closeRef.current = () => leave(onClose)
  }, [leave, onClose, closeRef])

  const rootLevel: TopicLevel = {
    id: 'root',
    // A titled header — like every other level — so this first list reserves the same header
    // height and its rows align with Themes/Areas, reading as the HTD's first column rather than
    // a bare flat list floating above the others. (Matches the breadcrumb's "Debug Options" root.)
    title: 'Debug Options',
    items: rootItems.map((t) => ({ id: t.id, label: t.label, icon: t.icon })),
    selectedId: top,
    onSelect: (id) => setTopGuarded(id as Top),
    // Deselect the topic — the same clear the breadcrumb root, a re-click, and (in narrow mode)
    // Back all route through. Guarded, so a dirty Site-theme draft still prompts first.
    onClear: () => setTopGuarded(null),
  }

  // Site theme renders its own HierarchicalDetailView (it is a separate, dev-build-only
  // module — see SiteThemeConsole), so it short-circuits the level composition below. The
  // host's theme taxonomy travels with it: the editor is the only topic that reads it, and
  // it must not be reachable from this always-loaded module.
  if (top === 'site-theme' && SiteThemeConsole) {
    return (
      <div className="flex min-h-0 min-w-0 flex-1 flex-col">
        <SiteThemeConsole rootLevel={rootLevel} leaveRef={leaveRef} themeAreas={themeAreas} />
      </div>
    )
  }

  let levels: TopicLevel[] = [rootLevel]
  // No topic chosen (the console was opened fresh and cleared, or Back popped the last one): the
  // detail pane shows the hint, exactly as every other stack does with an unselected leaf.
  let leaf: ReactNode = (
    <EmptyState
      className="m-4"
      title="No topic selected"
      description="Choose a debug topic to inspect."
    />
  )
  if (top === 'environment') {
    leaf = <EnvironmentPanel />
  } else if (top === 'settings') {
    leaf = <SettingsPanel envOverride={envOverride} />
  } else if (top === 'chat-theme' && config.chatTheme) {
    levels = [rootLevel, buildChatThemeLevel(config.chatTheme)]
    leaf = <ChatThemePreview chat={config.chatTheme} />
  }

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <HierarchicalDetailView
        levels={levels}
        rootLabel="Debug Options"
        disclosureStyle="cascading"
        exitGuard={null}
      >
        {leaf}
      </HierarchicalDetailView>
    </div>
  )
}
