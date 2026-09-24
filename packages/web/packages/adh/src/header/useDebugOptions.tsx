'use client'

import { useState, type ReactElement } from 'react'
import dynamic from 'next/dynamic'
import { detectEnv } from '@agentic-toolkit/adh-registry'
import { useClientHost } from '@agentic-toolkit/adh/header'
import { debugOptionsAvailable, debugOptionsHint, DEV_TOOLS_BUILD_ENABLED } from './devToolsEntries'
import { useEnvOverride } from './envOverride'

// Lazy, and in every build: a signed-in adh admin can open the console in ANY env,
// production included, so the chunk has to exist everywhere — and laziness, not
// dead-code elimination, is what keeps it off the wire until a door is actually used.
const DebugConsoleWindow = dynamic(() =>
  import('@agentic-toolkit/adh/debug-console').then((m) => m.DebugConsoleWindow),
)

export type DebugOptionsDoor = {
  /** Opens the Debug console. Absent ⇒ this visitor is not offered it, and the header
   *  draws no door: no avatar-menu row signed in, no Debug Options button signed out. */
  onOpen?: () => void
  /** The door's secondary text ("Sim: prod"), or nothing. */
  hint?: string
  /** The console itself while open, else null. Portals to document.body, so where the
   *  caller places it is irrelevant — it only has to be mounted somewhere. */
  window: ReactElement | null
}

/**
 * The Debug Options door, for both auth states: the avatar menu's last row when
 * signed in, and a Debug Options button beside login / join when signed out (AdhHeader
 * draws each from the same `onDebugOptions`). Replaces the bug-glyph dropdown that sat
 * beside the site name and existed only to hold this row (plus the dev-only site
 * family and Routes flyouts): the repo owner asked for the glyph gone and the row
 * moved to the end of the account menu, behind a divider. The signed-out button is
 * there because a signed-out visitor has no account menu, and without it the move
 * took the console away from them entirely — including the way to turn OFF a console
 * flag they had saved in localStorage (10x slow animations, say).
 *
 * The gate is exactly the dropdown's, read through the same pure helpers: offered in a
 * dev-env build, or to a signed-in adh admin in any env — and, of the two envs, the
 * REAL one, so simulating production never takes away the way back.
 */
export function useDebugOptions(userIsAdmin: boolean | undefined): DebugOptionsDoor {
  const host = useClientHost()
  const realEnv = host ? detectEnv(host) : null
  const override = useEnvOverride()
  const [open, setOpen] = useState(false)
  const adminUnlocked = userIsAdmin === true
  const offered =
    (DEV_TOOLS_BUILD_ENABLED || adminUnlocked) && debugOptionsAvailable({ realEnv, adminUnlocked })
  // The door can be withdrawn while the console is OPEN, and the console must go with
  // it. Only the admin unlock can flip at runtime (the build flag is a constant and the
  // host is read once), and it does: a cached admin is restored at page load, and the
  // background /api/auth/me check can then sign them out in place (a 401) or apply a
  // user who is no longer an admin. The dropdown this replaced unmounted the console
  // when that happened; `offered` in the window's condition below does the same.
  //
  // `open` is reset as well, not just masked, so a door that comes BACK (an admin
  // signing in again) finds the console closed rather than reopening a window nobody
  // just asked for. Reset during render against the previous value — React's
  // "adjusting state when a prop changes" — not in an effect: syncing state from an
  // effect is the pattern this toolkit bans, and it would cost a second commit to
  // arrive where this render already is.
  const [wasOffered, setWasOffered] = useState(offered)
  if (wasOffered !== offered) {
    setWasOffered(offered)
    if (!offered) setOpen(false)
  }
  return {
    onOpen: offered ? () => setOpen(true) : undefined,
    hint: offered ? debugOptionsHint(override) : undefined,
    window: open && offered ? <DebugConsoleWindow open onClose={() => setOpen(false)} /> : null,
  }
}
