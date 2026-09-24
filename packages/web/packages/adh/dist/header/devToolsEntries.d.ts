import { type SiteEnv } from '@agentic-toolkit/adh-registry';
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
export declare const DEV_TOOLS_BUILD_ENABLED: boolean;
export declare function isDevEnv(env: SiteEnv | null): boolean;
/** What {@link debugOptionsAvailable} decides from. */
export type DebugOptionsGate = {
    /** Env BEFORE the dev override, never after it — so simulating production can
     *  never lock a developer out of un-simulating. */
    realEnv: SiteEnv | null;
    /** The signed-in user is an adh admin: offered regardless of env — production
     *  included. Overrides the env gate (an admin simulating production keeps the door
     *  too: the simulation is for previewing what visitors get, and an admin never
     *  stops being an admin). */
    adminUnlocked: boolean;
};
/**
 * Whether the Debug Options door is offered at all — the one gate both of its doors
 * read (the avatar menu's last row signed in, the header's Debug Options button
 * signed out; `useDebugOptions` wires both). Follows the REAL env, never the simulated
 * one, so previewing production can always be undone; an adh admin gets it in every
 * env.
 */
export declare function debugOptionsAvailable({ realEnv, adminUnlocked }: DebugOptionsGate): boolean;
/** The door's secondary text: "Sim: prod" while the site is being viewed AS
 *  production, so that stays obvious from the door itself. Kept OUT of the door's
 *  label — it is the DESCRIPTION — so its accessible name is stably "Debug Options". */
export declare function debugOptionsHint(override: SiteEnv | null): string | undefined;
//# sourceMappingURL=devToolsEntries.d.ts.map