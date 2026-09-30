"use client";

import type { ReactNode } from "react";
import { useMasterDetailForm, RecordSettingsPane } from "@agentic-toolkit/resource";
import { gamesApi, type Game, type GameInput } from "@agentic-toolkit/data/games";
import { useGameForEcosystem } from "./useGameForEcosystem";
import {
  GameEngineFields,
  gameBlank,
  gameToInput,
  gameValidate,
  gameDiffers,
  gameNormalize,
} from "./GameDetail";

/**
 * How the game runs: which engine drives it, and the JSON that configures it. The other
 * half of the same `game.games` row the Settings topic's operational fields edit — hence
 * the identical form config, differing only in which fields are rendered. adh hosts the
 * backend, not the engine, so this pane records the engine's name and hands its config
 * through untouched rather than knowing anything about it.
 *
 * Takes `ecosystemId`, not a `gameId`: a game is reached through its product now (§1 of
 * the product-gaming-modes design), so this pane resolves its own record via the shared
 * {@link useGameForEcosystem} rather than being handed one by a rail. `useMasterDetailForm`
 * is still fed the resolved record as a one-item (or zero-item, or still-loading) list —
 * `RecordSettingsPane` was built for exactly this "single active record" shape, and reusing
 * it unmodified means this pane needs no master/detail machinery of its own.
 */
export function GameEnginePane({
  ecosystemId,
  title,
}: {
  ecosystemId?: string;
  title?: ReactNode;
}) {
  const { game, isSettled, error, reload } = useGameForEcosystem(ecosystemId);
  // null while either the game or the mode read is still in flight, so RecordSettingsPane's
  // "loading" state (via useMasterDetailForm's own null-items handling) is honest — not a
  // false "no game" empty state flashing before the mode read lands.
  const items: Game[] | null = !isSettled ? null : game ? [game] : [];

  const form = useMasterDetailForm<Game, GameInput>({
    items,
    getId: (g) => g.id,
    blank: gameBlank,
    toInput: gameToInput,
    // `gameValidate` no longer takes `others` (§1: a game's slug has no uniqueness of its
    // own to check any more — see GameDetail.tsx), but the hook's shape still passes it, so
    // it is simply ignored here rather than threaded through.
    validate: (draft) => gameValidate(draft),
    differs: gameDiffers,
    normalize: gameNormalize,
    update: (id, input) => gamesApi.update(id, input),
    refresh: reload,
  });

  return (
    <RecordSettingsPane
      form={form}
      activeId={game?.id}
      items={items}
      getId={(g) => g.id}
      title={title}
      loadError={error}
      emptyLabel={
        !isSettled
          ? "Loading…"
          : "Add the Gaming feature to this product to configure its game's engine."
      }
      renderDetail={(draft) => (
        <GameEngineFields
          key={form.detailKey}
          draft={draft}
          onChange={form.onChange}
          error={form.error}
        />
      )}
    />
  );
}
