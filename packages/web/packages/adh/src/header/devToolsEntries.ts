import { DEV_BUILD, isDevDeploymentEnv } from '@agentic-toolkit/adh-registry/deployment-env'
import { type SiteEnv } from '@agentic-toolkit/adh-registry'

// ─────────────────────────────────────────────────────────────────────────────
// The gate for the header's one remaining dev-tools door, "Debug Options" (opens the
// Debug console): who is offered it, and what its secondary text says. The door is
// drawn by AdhHeader — the avatar menu's last row signed in, a Debug Options button
// beside login / join signed out — from what `useDebugOptions` reads through these.
//
// This file used to build a whole dev-tools dropdown, a bug glyph beside the site
// name holding a "Routes" flyout, the dev-only Marketing / Main site-family flyouts
// and this row. The repo owner asked for the glyph gone and Debug Options moved to
// the account end of the header; nothing else in that menu had a reader left, so it
// went with the glyph and only the gate remains here. (The filename is kept: comments
// across the package point at this file for DEV_TOOLS_BUILD_ENABLED.)
//
// Pure (no hooks/DOM) so the env gating below — the part that must never leak a
// debug affordance to an ordinary production visitor — is unit-testable.
// `useDebugOptions` supplies the envs and the admin unlock.

/**
 * Whether this BUILD offers the dev tooling to everyone: true in the three dev
 * envs, false in production. See {@link DEV_BUILD} for the folding rules — this is
 * that same flag under the name the header's dev tooling has always used for it.
 *
 * NOT the only door: a signed-in adh admin unlocks Debug Options at runtime in ANY
 * env, production included (see {@link DebugOptionsGate}'s `adminUnlocked`, and
 * `useDebugOptions`). That admin unlock is why a dev affordance that must NOT exist
 * in production can't rely on this flag alone — the site-theme editor is gated on
 * DEV_BUILD directly for exactly that reason.
 */
export const DEV_TOOLS_BUILD_ENABLED = DEV_BUILD

export function isDevEnv(env: SiteEnv | null): boolean {
  return isDevDeploymentEnv(env)
}

/** What {@link debugOptionsAvailable} decides from. */
export type DebugOptionsGate = {
  /** Env BEFORE the dev override, never after it — so simulating production can
   *  never lock a developer out of un-simulating. */
  realEnv: SiteEnv | null
  /** The signed-in user is an adh admin: offered regardless of env — production
   *  included. Overrides the env gate (an admin simulating production keeps the door
   *  too: the simulation is for previewing what visitors get, and an admin never
   *  stops being an admin). */
  adminUnlocked: boolean
}

/**
 * Whether the Debug Options door is offered at all — the one gate both of its doors
 * read (the avatar menu's last row signed in, the header's Debug Options button
 * signed out; `useDebugOptions` wires both). Follows the REAL env, never the simulated
 * one, so previewing production can always be undone; an adh admin gets it in every
 * env.
 */
export function debugOptionsAvailable({ realEnv, adminUnlocked }: DebugOptionsGate): boolean {
  return adminUnlocked || isDevEnv(realEnv)
}

/** The door's secondary text: "Sim: prod" while the site is being viewed AS
 *  production, so that stays obvious from the door itself. Kept OUT of the door's
 *  label — it is the DESCRIPTION — so its accessible name is stably "Debug Options". */
export function debugOptionsHint(override: SiteEnv | null): string | undefined {
  return override === 'production' ? 'Sim: prod' : undefined
}
