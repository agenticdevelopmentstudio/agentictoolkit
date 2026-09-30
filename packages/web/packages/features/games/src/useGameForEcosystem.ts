"use client";

import { reportUnexpectedAuthError } from "@agentic-toolkit/auth";
import { isForbidden, useResourceItemQuery } from "@agentic-toolkit/data";
import { gamesApi, type Game } from "@agentic-toolkit/data/games";
import { gamificationApi, type GamingMode, type RealmConfig } from "@agentic-toolkit/data/gamification";

/** The cache key the underlying game-row lookup reads/writes. Exported so
 *  `GameSettingsPane` can read the RAW (mode-independent) row — it needs to know whether a
 *  game has ever been minted regardless of the current mode, since that is what decides
 *  whether its operational fields have anything to show — and so it can push its own
 *  update result straight into the same cache entry every other pane on this rail
 *  reads through {@link useGameForEcosystem}. */
export const GAME_FOR_ECOSYSTEM_CACHE_KEY = "game-for-ecosystem";

/** The cache key the realm config lookup reads/writes — the SAME key
 *  `@agentic-toolkit/gamification`'s `RealmSettingsPane` uses for the identical
 *  `RealmConfig` row. Sharing it (rather than games keeping its own copy) is deliberate:
 *  it is what lets a realm-config save on the gamification side replace the exact entry
 *  this hook reads, with no cross-package
 *  invalidation wiring required. */
export const REALM_CONFIG_CACHE_KEY = "realm-config";

/** Raw game-row loader — resolves to `null` when no game has EVER been minted for this
 *  product, independent of the realm's current mode. Exported (not just used internally)
 *  so `GameSettingsPane` reads through the identical function rather than a near-copy that
 *  could drift from this one's error handling. */
export async function loadGameRow(ecosystemId: string): Promise<Game | null> {
  try {
    return await gamesApi.forEcosystem(ecosystemId);
  } catch (err) {
    // A 403 here means "you can't administer this product", which reads as permissions, not
    // "no game yet" — collapsing it to null would show every pane's "turn on gaming in
    // Settings" copy to someone who is actually just locked out. Thrown as a friendly message
    // instead (mirrors RealmSettingsPane's `loadRealmConfig`), so it surfaces through each
    // caller's existing `error`/`loadError` plumbing.
    if (isForbidden(err)) {
      throw new Error("You don't have access to this product's game.");
    }
    reportUnexpectedAuthError(err, { feature: "game-for-ecosystem", step: "load-game" });
    throw err instanceof Error ? err : new Error("Failed to load this product's game.");
  }
}

/** Realm-config loader, identical in shape (and error wording) to `RealmSettingsPane`'s own
 *  `loadRealmConfig` — duplicated rather than imported because that one is a module-private
 *  function of a package this one may not depend on (`features/gamification` is off limits
 *  here). */
export async function loadRealmConfig(ecosystemId: string): Promise<RealmConfig> {
  try {
    return await gamificationApi.getRealmConfig(ecosystemId);
  } catch (err) {
    if (isForbidden(err)) {
      throw new Error("You don't have access to this product's gaming settings.");
    }
    reportUnexpectedAuthError(err, { feature: "game-for-ecosystem", step: "load-mode" });
    throw err instanceof Error ? err : new Error("Failed to load this product's gaming settings.");
  }
}

export interface GameForEcosystem {
  /**
   * The live, playable game — non-null ONLY when BOTH a `game.games` row exists AND the
   * realm's `mode === 'game'`.
   *
   * Row existence alone is NOT the gate. Leaving game mode "mints nothing and deletes
   * nothing" (§2 of the product-gaming-modes design): the row outlives the mode on purpose,
   * so that switching gaming back on resumes the SAME game — its definitions and effects
   * intact — instead of starting over. That means a row can easily exist while
   * `mode !== 'game'` (gaming was turned off, or was never more than 'gamification'), so
   * every pane that shows game CONTENT must gate on the mode too, or it would show a live
   * game screen for a product whose gaming is switched off. Do not "simplify" this back to
   * a row-existence check — that is the bug this comment exists to prevent.
   */
  game: Game | null;
  /** The realm's current mode, independent of the gate above. Exposed because Settings
   *  needs it in EVERY mode — flipping it to 'game' is how a product GETS a game in the
   *  first place, not just how an existing one is hidden or shown. */
  mode: GamingMode | null;
  /** Both the game-row read and the mode read have landed. */
  isSettled: boolean;
  isFetching: boolean;
  error: string | null;
  reload: () => Promise<void>;
}

/**
 * One game per product ecosystem (§1 of the product-gaming-modes design): every pane that
 * used to key off a `gameId` handed down by a games rail now takes an `ecosystemId` and
 * resolves the single game itself. This hook is the ONE place that resolution happens —
 * five panes sharing it (rather than each repeating the lookup) is what makes turning
 * gaming on in Settings show up on Engine/Content/Connections/Effects without a
 * navigation: they all read the same two cache entries, keyed by ecosystemId.
 *
 * `game` is gated on `mode === 'game'` (see the field doc above) — this hook, not each
 * caller, owns that rule, so a caller cannot "forget" the mode check and show stale game
 * content. `GameSettingsPane` is the one place that needs the RAW row regardless of mode
 * (to decide whether it has an existing game's fields to show); it reads `loadGameRow`
 * directly rather than through this gate.
 */
export function useGameForEcosystem(ecosystemId?: string): GameForEcosystem {
  const gameQuery = useResourceItemQuery<Game | null>(
    GAME_FOR_ECOSYSTEM_CACHE_KEY,
    ecosystemId ?? null,
    loadGameRow,
    { reportErrors: false },
  );
  const configQuery = useResourceItemQuery<RealmConfig>(
    REALM_CONFIG_CACHE_KEY,
    ecosystemId ?? null,
    loadRealmConfig,
    { reportErrors: false },
  );

  const mode = configQuery.item?.mode ?? null;
  const game = mode === "game" ? (gameQuery.item ?? null) : null;

  return {
    game,
    mode,
    isSettled: gameQuery.isSettled && configQuery.isSettled,
    isFetching: gameQuery.isFetching || configQuery.isFetching,
    error: gameQuery.error ?? configQuery.error ?? null,
    reload: async () => {
      await Promise.all([gameQuery.reload(), configQuery.reload()]);
    },
  };
}
