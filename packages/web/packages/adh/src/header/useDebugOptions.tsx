'use client'

import { useState, type ReactElement } from 'react'
import dynamic from 'next/dynamic'
import { detectEnv } from '@agentic-toolkit/adh-registry'
import { useClientHost } from '@agentic-toolkit/adh/header'
import { debugOptionsAvailable, debugOptionsHint, DEV_TOOLS_BUILD_ENABLED } from './devToolsEntries'
import { useEnvOverride } from './envOverride'

// Same lazy chunk DevToolsMenu opens, for the same reason: a signed-in adh admin can
// open the console in ANY env, so the chunk exists in every build, and laziness — not
// dead-code elimination — keeps it off the wire until the row is actually used.
const DebugConsoleWindow = dynamic(() =>
  import('@agentic-toolkit/adh/debug-console').then((m) => m.DebugConsoleWindow),
)

export type DebugOptionsDoor = {
  /** Opens the Debug console. Absent ⇒ this visitor is not offered it, and the avatar
   *  menu renders no Debug Options row. */
  onOpen?: () => void
  /** The row's secondary text ("Sim: prod"), or nothing. */
  hint?: string
  /** The console itself while open, else null. Portals to document.body, so where the
   *  caller places it is irrelevant — it only has to be mounted somewhere. */
  window: ReactElement | null
}

/**
 * The Debug Options door for the avatar menu's last row. Replaces the bug-glyph
 * dropdown in the header bar, which existed only to hold it (plus the dev-only site
 * family and Routes flyouts): the repo owner asked for the glyph gone and the row
 * moved to the end of the account menu, behind a divider.
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
  return {
    onOpen: offered ? () => setOpen(true) : undefined,
    hint: offered ? debugOptionsHint(override) : undefined,
    window: open ? <DebugConsoleWindow open onClose={() => setOpen(false)} /> : null,
  }
}
