"use client";

import { useCallback } from "react";
import type { ReactNode } from "react";

import { reportUnexpectedAuthError } from "@agentic-toolkit/auth";
import { isForbidden, useResourceItemQuery, useResourceItemWriter } from "@agentic-toolkit/data";
import { gamesApi, type Game, type GameInput } from "@agentic-toolkit/data/games";
import { DetailsPane, SettingsDirtyProvider, useSettingsDraft } from "@agentic-toolkit/resource";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { gamificationApi, type RealmConfig } from "@agentic-toolkit/data/gamification";
import { FeatureSwitch } from "@agentic-toolkit/ecosystems";
import { GAME_FOR_ECOSYSTEM_CACHE_KEY, REALM_CONFIG_CACHE_KEY, loadGameRow } from "./useGameForEcosystem";
import { GameOperationalFields, gameDiffers, gameNormalize, gameToInput, gameValidate } from "./GameDetail";

/**
 * The games site's Settings topic: the game row's operational fields (status, character
 * names, event log, retention) under the pane's one bar. Name/slug/description are GONE from
 * here — they are the PRODUCT's fields now, edited under the product's own Settings (§1, §5.3 of
 * the product-gaming-modes design) — so a save from this pane still submits the game's WHOLE
 * `GameInput` (via `gameToInput`/`gameNormalize`/`gameDiffers`, unchanged from Engine's), it just
 * never lets the operational fields' `onChange` touch the identity ones.
 *
 * The Gaming on/off switch at the top is a {@link FeatureSwitch}: it adds or removes the Gaming
 * FEATURE (the same write as Manage features), and the realm's mode follows the features —
 * adding Gaming makes it `game` and mints the game, server-side. It reads
 * the RAW game row, not the mode-gated `useGameForEcosystem`, so a game kept after Gaming was
 * removed still shows its settings.
 */
export function GameSettingsPane({
  ecosystemId,
  help,
}: {
  ecosystemId?: string;
  /** Unused: the breadcrumb names the pane (kept for the ScopedPane prop shape). */
  title?: ReactNode;
  help?: ReactNode;
}) {
  const {
    item: game,
    isSettled,
    error: loadError,
  } = useResourceItemQuery<Game | null>(GAME_FOR_ECOSYSTEM_CACHE_KEY, ecosystemId ?? null, loadGameRow, {
    reportErrors: false,
  });
  const writeGame = useResourceItemWriter<Game | null>(GAME_FOR_ECOSYSTEM_CACHE_KEY);

  const { draft, replace: setDraft, dirty, commit, reset } = useSettingsDraft<Game, GameInput>(
    game,
    gameToInput,
    (a, b) => !gameDiffers(a, b),
  );

  const validationError = draft ? gameValidate(draft) : null;

  const save = useCallback(async () => {
    if (!ecosystemId || !game || !draft || validationError) return;
    try {
      // The WHOLE GameInput goes over the wire, not just the operational fields: a partial
      // body would let this save blank out the engine/name/slug/description columns Engine
      // (and, at mint, the product) own. `draft` already carries those unchanged, since
      // `GameOperationalFields`' onChange never touches them.
      const updated = await gamesApi.update(game.id, gameNormalize(draft));
      // The SAME cache key every other pane on this rail reads, so Engine/Content/Connections/
      // Effects see the change without a navigation.
      writeGame(ecosystemId, updated);
      commit(updated);
    } catch (err) {
      if (!isForbidden(err)) {
        reportUnexpectedAuthError(err, { feature: "games-settings", step: "save" });
      }
      // The pane shows what this throws, and stops its save here.
      throw new Error(
        isForbidden(err)
          ? "You don't have access to change this product's gaming settings."
          : err instanceof Error
            ? err.message
            : "Failed to save gaming settings.",
      );
    }
  }, [ecosystemId, game, draft, validationError, commit, writeGame]);

  // Adding Gaming mints the game and moves the realm's mode server-side: re-read both, so this
  // pane and every other reader on the rail follow.
  const writeRealm = useResourceItemWriter<RealmConfig>(REALM_CONFIG_CACHE_KEY);
  const rereadAfterFeatureChange = useCallback(async () => {
    if (!ecosystemId) return;
    const [row, realm] = await Promise.all([loadGameRow(ecosystemId), gamificationApi.getRealmConfig(ecosystemId)]);
    writeGame(ecosystemId, row);
    writeRealm(ecosystemId, realm);
  }, [ecosystemId, writeGame, writeRealm]);

  return (
    <DetailsPane
      help={help}
      api={{ method: "PUT", path: "/game/games/{id}", pathValues: { id: game?.id }, title: "Game API" }}
      section={{ dirty, canSave: !validationError, blockedReason: validationError, save, reset }}
    >
      <div className="max-w-3xl space-y-6">
        <div className="border-b border-apt-border pb-6">
          <FeatureSwitch
            ecosystemId={ecosystemId}
            featureKey="gaming"
            label="Gaming"
            description="Turning this on gives this product a game (and gamification with it) and backfills existing members. Turning it off keeps the game's configuration — nothing is deleted, and turning it back on resumes the same game."
            onApplied={rereadAfterFeatureChange}
          />
        </div>
        <ErrorText error={loadError} />
        {!isSettled && !loadError && <p className="text-sm text-apt-text-muted">Loading…</p>}
        {draft ? (
          <GameOperationalFields draft={draft} onChange={setDraft} error={validationError} />
        ) : (
          isSettled &&
          !loadError && (
            <p className="text-sm text-apt-text-muted">
              This product has no game yet — add the Gaming feature to mint one. Its status,
              character names, event log and retention will appear here once it exists.
            </p>
          )
        )}
      </div>
    </DetailsPane>
  );
}

/** The Settings TOPIC: the game's operational fields, in its own guard registry — same
 *  reasoning as `GamificationSettingsTopicPane` (the provider has to sit INSIDE the rail host so
 *  `useRailExitGuard` finds it; nested inside a host that already has one it safely defers). */
export function GameSettingsTopicPane(props: { ecosystemId?: string; help?: ReactNode }) {
  return (
    <SettingsDirtyProvider>
      <GameSettingsPane {...props} />
    </SettingsDirtyProvider>
  );
}
