"use client";

import type { ReactNode } from "react";
import { TopicSelectHint } from "@agenticdevelopertoolkit/ui/blocks";

/**
 * The empty state Content/Connections/Effects show whenever `useGameForEcosystem` gates
 * `game` to null — either no `game.games` row has ever been minted, or one exists but the
 * realm isn't currently in `'game'` mode (see that hook's doc comment for why row
 * existence alone is not the gate). Both cases read the same to an author: there is
 * nothing here to edit until Settings turns gaming on, so one copy suffices rather than
 * distinguishing "never minted" from "minted, then turned off".
 *
 * `isSettled` gates a THIRD state — the read is still in flight — so this never flashes
 * "not enabled" for a product that in fact has gaming on, for the one render before the
 * mode/game reads land.
 */
export function GameNotEnabledPane({ isSettled }: { isSettled: boolean }): ReactNode {
  return (
    <TopicSelectHint
      title={isSettled ? "Gaming isn't turned on for this product yet." : "Loading…"}
      selectable={false}
    >
      {isSettled
        ? "Add the Gaming feature to this product to mint its game, then come back here."
        : null}
    </TopicSelectHint>
  );
}
