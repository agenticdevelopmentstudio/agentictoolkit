"use client";

import { useCallback } from "react";
import type { ReactNode } from "react";

import { reportUnexpectedAuthError } from "@agentic-toolkit/auth";
import { isForbidden, useResourceItemQuery, useResourceItemWriter } from "@agentic-toolkit/data";
import { gamificationApi, type RealmConfig } from "@agentic-toolkit/data/gamification";
import { type Game, type GameInput, gamesApi } from "@agentic-toolkit/data/games";
import {
  DetailsPane,
  SettingsDirtyProvider,
  useDetailsSection,
  useSettingsDraft,
} from "@agentic-toolkit/resource";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import {
  GAME_FOR_ECOSYSTEM_CACHE_KEY,
  GameOperationalFields,
  gameDiffers,
  gameNormalize,
  gameToInput,
  gameValidate,
  REALM_CONFIG_CACHE_KEY,
  useGameForEcosystem,
} from "@agentic-toolkit/games";
import { RealmSettingsPane, realmConfigApi } from "@agentic-toolkit/gamification";
import { FeatureSwitch } from "@agentic-toolkit/ecosystems";

/**
 * Read one realm's gaming mode — a private copy of `RealmSettingsPane`'s (and
 * `GamingGroup.tsx`'s) own `loadRealmConfig`: `@agentic-toolkit/games` keeps its own version of
 * this loader package-internal, so there is no shared function to import here — only
 * `REALM_CONFIG_CACHE_KEY` (imported above) is a real, public export, and it is what keeps all
 * three copies of this loader pointed at the SAME cache entry.
 */
async function loadRealmConfig(ecosystemId: string): Promise<RealmConfig> {
  try {
    return await gamificationApi.getRealmConfig(ecosystemId);
  } catch (err) {
    if (isForbidden(err)) {
      throw new Error("You don't have access to this product's gaming settings.");
    }
    reportUnexpectedAuthError(err, { feature: "gaming-settings", step: "load" });
    throw err instanceof Error ? err : new Error("Failed to load this product's gaming settings.");
  }
}

/**
 * The game's own operational fields (§4.4: status, character names, event log, event
 * retention) — everything `GameOperationalFields` renders, and nothing `features/games/` no
 * longer edits (name/slug/description are the PRODUCT's, under its Settings). One section of
 * the pane's bar, resolving "the" game via `useGameForEcosystem` rather than being handed one —
 * the one-game-per-product design (§1) is what makes that resolution safe.
 *
 * The save sends the WHOLE `GameInput` (`gameToInput`/`gameNormalize`), same as every pane in
 * `features/games/` that edits this row — the draft is seeded from the loaded record and this
 * section never touches `engine`/`engineConfig`, so the Engine topic's fields round-trip
 * untouched even though this pane never renders them.
 */
function GameOperationalFieldsSection({ ecosystemId }: { ecosystemId?: string }) {
  const { game, error: loadError } = useGameForEcosystem(ecosystemId);
  const writeGame = useResourceItemWriter<Game | null>(GAME_FOR_ECOSYSTEM_CACHE_KEY);

  // `gameDiffers` rather than the hook's JSON default: a `GameInput`'s optional fields differ
  // structurally in ways that are not differences (see `GameDetail`), and this is the same
  // comparison every other pane editing this row already dirties on.
  const { draft, replace: setDraft, dirty, commit, reset } = useSettingsDraft<Game, GameInput>(
    game,
    gameToInput,
    (a, b) => !gameDiffers(a, b),
  );

  const validationError = draft ? gameValidate(draft) : null;

  const save = useCallback(async () => {
    if (!ecosystemId || !game || !draft || validationError) return;
    try {
      const updated = await gamesApi.update(game.id, gameNormalize(draft));
      // Keyed by ECOSYSTEM id, not the game's own uuid: `useGameForEcosystem` (and every other
      // pane sharing it — Engine, Content, Connections, Effects) reads this cache under
      // `ecosystemId`, per §1's "no address of its own". `Game` itself carries no `ecosystemId`
      // field to read back off `updated`, which is exactly why the id written here is the prop,
      // not anything pulled from the response.
      writeGame(ecosystemId, updated);
      commit(updated);
    } catch (err) {
      if (!isForbidden(err)) {
        reportUnexpectedAuthError(err, { feature: "gaming-settings", step: "save-game" });
      }
      // The pane shows what this throws, and stops its save here.
      throw new Error(
        isForbidden(err)
          ? "You don't have access to change this game's settings."
          : err instanceof Error
            ? err.message
            : "Failed to save this game's settings.",
      );
    }
  }, [ecosystemId, game, draft, validationError, commit, writeGame]);

  useDetailsSection({ dirty, canSave: !validationError, blockedReason: validationError, save, reset });

  return (
    <div className="max-w-3xl">
      <ErrorText error={loadError} />
      {!draft && !loadError && <p className="text-sm text-apt-text-muted">Loading…</p>}
      {draft && <GameOperationalFields draft={draft} onChange={setDraft} error={validationError} />}
    </div>
  );
}

/**
 * The Gaming group's Settings member (§4.4) — always the last item `GamingGroup` builds. ONE
 * pane with ONE bar: every section below registers with it, so Save and Cancel act on all of it.
 *
 * The realm's mode follows the product's features (Gaming held → `game`, Gamification alone →
 * `gamification`, neither → `none`), set by the backend when a feature is added or removed. The
 * Gaming on/off switch at the top is therefore a {@link FeatureSwitch} — it adds or removes the
 * Gaming FEATURE, the same write as Manage features — and the pane reads the mode that follows
 * only to decide what else to show:
 *
 *   - The Gaming switch, always: it is how a product with none gets a game from here.
 *   - The realm's switches and settings (`RealmSettingsPane`, a section of this pane — its own
 *     Gamification switch first), while `mode !== 'none'`.
 *   - Then the game's own status box (`GameOperationalFieldsSection`), only while
 *     `mode === 'game'`.
 *
 * Name, slug and description are never rendered here — they are the product's fields, edited
 * under the product's Settings (§4.4), a different pane in a different package entirely.
 */
export function GamingSettingsPane({
  ecosystemId,
  help,
}: {
  ecosystemId?: string;
  help?: ReactNode;
}) {
  // The read that decides which sections to show — the same `REALM_CONFIG_CACHE_KEY` entry
  // `RealmSettingsPane` and `GamingGroup` read, so all three land on whichever value is currently
  // cached (or in flight) rather than one lagging.
  const { item: config, error: loadError } = useResourceItemQuery<RealmConfig>(
    REALM_CONFIG_CACHE_KEY,
    ecosystemId ?? null,
    loadRealmConfig,
    { reportErrors: false },
  );
  const mode = config?.mode ?? null;
  const writeConfig = useResourceItemWriter<RealmConfig>(REALM_CONFIG_CACHE_KEY);
  // Turning Gaming on or off moves the realm's mode server-side; re-read it so this pane, the
  // realm section and the Gaming rail all follow.
  const rereadConfig = useCallback(async () => {
    if (!ecosystemId) return;
    writeConfig(ecosystemId, await gamificationApi.getRealmConfig(ecosystemId));
  }, [ecosystemId, writeConfig]);

  return (
    <SettingsDirtyProvider>
      <DetailsPane help={help} api={realmConfigApi(ecosystemId)}>
        <div className="max-w-3xl border-b border-apt-border pb-6">
          <FeatureSwitch
            ecosystemId={ecosystemId}
            featureKey="gaming"
            label="Gaming"
            description="Turning this on gives this product a game (and gamification with it) and backfills existing members. Turning it off keeps the game's configuration — nothing is deleted, and turning it back on resumes the same game."
            onApplied={rereadConfig}
          />
        </div>
        <ErrorText error={loadError} />
        {mode === null && !loadError && <p className="text-sm text-apt-text-muted">Loading…</p>}
        {mode === "none" && (
          <p className="max-w-3xl text-sm text-apt-text-muted">
            This product has no gaming. Turn Gaming on above, or add Gamification under Manage
            features.
          </p>
        )}
        {mode !== null && mode !== "none" && <RealmSettingsPane ecosystemId={ecosystemId} />}
        {mode === "game" && (
          <div className="border-t border-apt-border pt-6">
            <GameOperationalFieldsSection ecosystemId={ecosystemId} />
          </div>
        )}
      </DetailsPane>
    </SettingsDirtyProvider>
  );
}
