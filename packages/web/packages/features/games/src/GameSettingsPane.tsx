"use client";

import { useCallback, useMemo, useState } from "react";
import type { ReactNode } from "react";

import { reportUnexpectedAuthError } from "@agentic-toolkit/auth";
import { isForbidden, useResourceItemQuery, useResourceItemWriter } from "@agentic-toolkit/data";
import { gamesApi, type Game, type GameInput } from "@agentic-toolkit/data/games";
import { gamificationApi, type GamingMode, type RealmConfig } from "@agentic-toolkit/data/gamification";
import {
  EditActionBar,
  SettingsDirtyProvider,
  useReportSettingsDirty,
  useSettingsDraft,
} from "@agentic-toolkit/resource";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { Switch } from "@agenticdevelopertoolkit/ui/components/switch";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import {
  GAME_FOR_ECOSYSTEM_CACHE_KEY,
  REALM_CONFIG_CACHE_KEY,
  loadGameRow,
  loadRealmConfig,
} from "./useGameForEcosystem";
import { GameOperationalFields, gameDiffers, gameNormalize, gameToInput, gameValidate } from "./GameDetail";

/**
 * Replaces GameOverviewPane. Two resources, one save bar: the realm's `mode` (whether this
 * product's game is on) and the game row's own operational fields (status, character
 * names, event log, retention). Name/slug/description are GONE from here — they are the
 * PRODUCT's fields now, edited under the product's own Settings (§1, §5.3 of the
 * product-gaming-modes design) — so a save from this pane still submits the game's WHOLE
 * `GameInput` (via `gameToInput`/`gameNormalize`/`gameDiffers`, unchanged from Engine's),
 * it just never lets the operational fields' `onChange` touch the identity ones.
 *
 * Modeled on `RealmSettingsPane` (manual draft/dirty/save/cancel over `EditActionBar`, NOT
 * `useMasterDetailForm` — that hook is for one list-shaped resource, and this pane composes
 * two: `RealmConfig` and `Game`) rather than on `RecordSettingsPane`. It reads BOTH the raw
 * game row and the realm config directly — not through the mode-gated `useGameForEcosystem`
 * — because this is the one pane that must show an existing game's fields even when the
 * mode is (or is being switched) away from `'game'`, and must show the Enable Gaming switch
 * in every mode, since flipping it on is how a product gets a game in the first place.
 */

interface Draft {
  mode: GamingMode;
  /** null only when no `game.games` row has ever been minted for this product — the
   *  operational fields render only once this is non-null (see the file doc: the mint
   *  happens server-side on save, so switching Enable Gaming on does not itself reveal
   *  fields there is nothing yet to show). */
  game: GameInput | null;
}

/** The two records this pane edits as one. `useSettingsDraft` takes a single loaded record;
 *  what this pane loads is a pair, so the pair is the record. */
interface Loaded {
  config: RealmConfig;
  game: Game | null;
}

/**
 * What the Enable Gaming switch writes when it is turned OFF.
 *
 * NOT unconditionally `none`: `mode` is one ordered axis (`none` < `gamification` < `game`)
 * and this switch owns only its top value. A product carrying gamification support — set from
 * the Products site's three-valued control, and invisible from this pane — renders the switch
 * off, so flipping it on and back off has to put the product back where it started rather than
 * silently strip a mode nothing here shows. `game` is the only value this control may take
 * away, and the SEEDED mode is the one to return to because it is what the user saw before
 * touching the switch.
 *
 * The gamification pane makes the same rule from the other end: its switch is checked AND
 * disabled while mode is `game`, so neither control can spend the other's half of the axis.
 */
export function modeAfterGamingOff(seeded: GamingMode | null): GamingMode {
  return seeded !== null && seeded !== "game" ? seeded : "none";
}

function toDraft({ config, game }: Loaded): Draft {
  return { mode: config.mode, game: game ? gameToInput(game) : null };
}

export function GameSettingsPane({
  ecosystemId,
  help,
}: {
  ecosystemId?: string;
  /** Unused: the breadcrumb names the pane (kept for the ScopedPane prop shape, matching
   *  `RealmSettingsPane`'s `title`). */
  title?: ReactNode;
  help?: ReactNode;
}) {
  const { item: config, error: configError } = useResourceItemQuery<RealmConfig>(
    REALM_CONFIG_CACHE_KEY,
    ecosystemId ?? null,
    loadRealmConfig,
    { reportErrors: false },
  );
  const {
    item: gameRow,
    isSettled: gameSettled,
    error: gameError,
  } = useResourceItemQuery<Game | null>(GAME_FOR_ECOSYSTEM_CACHE_KEY, ecosystemId ?? null, loadGameRow, {
    reportErrors: false,
  });
  const writeConfig = useResourceItemWriter<RealmConfig>(REALM_CONFIG_CACHE_KEY);
  const writeGame = useResourceItemWriter<Game | null>(GAME_FOR_ECOSYSTEM_CACHE_KEY);

  const [saveError, setSaveError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [savedNote, setSavedNote] = useState<string | null>(null);

  // Held back until BOTH reads land, not just the config: a save fired before the game-row
  // read settles could not tell "no game yet" from "still loading", and would risk treating
  // an existing row as absent. Null until then, which is also what keeps the draft unseeded.
  const loaded = useMemo<Loaded | null>(
    () => (config != null && gameSettled ? { config, game: gameRow ?? null } : null),
    [config, gameSettled, gameRow],
  );
  const {
    draft,
    patch: patchDraft,
    seed,
    dirty,
    commit,
    reset,
  } = useSettingsDraft<Loaded, Draft>(loaded, toDraft);

  const gamingOff = modeAfterGamingOff(seed?.mode ?? null);

  const gameValidationError = draft?.game ? gameValidate(draft.game) : null;
  const canSave = dirty && !gameValidationError;

  useReportSettingsDirty("games-settings", dirty);

  const patchMode = useCallback(
    (mode: GamingMode) => {
      setSavedNote(null);
      patchDraft({ mode });
    },
    [patchDraft],
  );

  const patchGame = useCallback(
    (next: GameInput) => {
      setSavedNote(null);
      patchDraft({ game: next });
    },
    [patchDraft],
  );

  const save = useCallback(async () => {
    if (!ecosystemId || !draft || !seed || !canSave) return;
    setSaving(true);
    setSaveError(null);
    setSavedNote(null);

    // Diffed against `seed` — what this draft was seeded from — and not against the current
    // server copy, so "did the user change it" cannot be confused with "did it change under
    // us". Mode is where that matters: another admin flipping this product to `game` while
    // the pane sits open would otherwise read as an edit here and be written straight back.
    const modeChanged = draft.mode !== seed.mode;
    const gameFieldsChanged = !!seed.game && !!draft.game && gameDiffers(draft.game, seed.game);

    try {
      let nextConfig = config!;
      let nextGameRow = gameRow ?? null;
      let replayedNote: string | null = null;

      if (modeChanged) {
        const res = await gamificationApi.updateRealmConfig(ecosystemId, { mode: draft.mode });
        writeConfig(ecosystemId, res.config);
        nextConfig = res.config;
        replayedNote = res.replayed
          ? `Backfilled ${res.replayed.subjects} members, ${res.replayed.badges} badges.`
          : null;
        // Flipping mode may mint (or leave alone) the game row server-side. Re-fetch it
        // directly — `reload()` returns no data — and push the answer into the SAME cache
        // key every other pane on this rail reads, so Engine/Content/Connections/Effects
        // reflect the flip without a navigation.
        nextGameRow = await loadGameRow(ecosystemId);
        writeGame(ecosystemId, nextGameRow);
      }

      // The WHOLE GameInput goes over the wire, not just the operational fields: a partial
      // body would let this save blank out the engine/name/slug/description columns Engine
      // (and, at mint, the product) own. `draft.game` already carries those unchanged,
      // since `GameOperationalFields`' onChange never touches them.
      if (gameFieldsChanged && nextGameRow && draft.game) {
        const normalized = gameNormalize(draft.game);
        const updated = await gamesApi.update(nextGameRow.id, normalized);
        writeGame(ecosystemId, updated);
        nextGameRow = updated;
      }

      commit({ config: nextConfig, game: nextGameRow });
      setSavedNote(replayedNote ?? "Saved.");
    } catch (err) {
      if (!isForbidden(err)) {
        reportUnexpectedAuthError(err, { feature: "games-settings", step: "save" });
      }
      setSaveError(
        isForbidden(err)
          ? "You don't have access to change this product's gaming settings."
          : err instanceof Error
            ? err.message
            : "Failed to save gaming settings.",
      );
    } finally {
      setSaving(false);
    }
  }, [ecosystemId, draft, seed, canSave, config, gameRow, commit, writeConfig, writeGame]);

  const cancel = useCallback(() => {
    reset();
    setSaveError(null);
    setSavedNote(null);
  }, [reset]);

  const loadError = configError ?? gameError;

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <EditActionBar
        dirty={dirty}
        canSave={canSave}
        saving={saving}
        onCancel={cancel}
        onSave={save}
        status={
          saveError ? (
            <span className="text-apt-red">{saveError}</span>
          ) : savedNote && !dirty ? (
            <span className="text-apt-text-muted">{savedNote}</span>
          ) : null
        }
      />
      <div className="min-h-0 flex-1 overflow-y-auto px-6 py-6">
        <div className="max-w-3xl space-y-7">
          {help && <p className="text-sm text-apt-text-muted">{help}</p>}
          <ErrorText error={loadError} />
          {!draft && !loadError && <p className="text-sm text-apt-text-muted">Loading…</p>}

          {draft && (
            <>
              {/* Enable Gaming — the ONE writer of mode 'game'. Renders in every mode (unlike
                  every other pane on this rail, which is gated behind it): this switch is how
                  a product ENTERS game mode, so it cannot itself be hidden by that gate. */}
              <div className="flex items-start justify-between gap-6">
                <div className="min-w-0">
                  <Label htmlFor="games-enabled" className="text-sm font-medium text-apt-text">
                    Enable Gaming
                  </Label>
                  <p className="mt-0.5 text-xs text-apt-text-muted">
                    Turning this on mints this product&rsquo;s game and its realm, and backfills
                    existing members. Turning it off keeps the game&rsquo;s configuration —
                    nothing is deleted, and turning it back on resumes the same game.
                    {gamingOff === "gamification" && (
                      <>
                        {" "}
                        This product has gamification support, so turning gaming off returns it to
                        that rather than switching everything off.
                      </>
                    )}
                  </p>
                </div>
                <Switch
                  id="games-enabled"
                  checked={draft.mode === "game"}
                  onCheckedChange={(on) => patchMode(on ? "game" : gamingOff)}
                />
              </div>

              <div className="border-t border-apt-border pt-6">
                {draft.game ? (
                  <GameOperationalFields
                    draft={draft.game}
                    onChange={patchGame}
                    error={gameValidationError}
                  />
                ) : (
                  <p className="text-sm text-apt-text-muted">
                    This product has no game yet — turn on Enable Gaming and save to mint one.
                    Its status, character names, event log and retention will appear here once it
                    exists.
                  </p>
                )}
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

/** The Settings TOPIC: the switch plus the game's operational fields, in its own guard
 *  registry — same reasoning as `GamificationSettingsTopicPane` (the provider has to sit
 *  INSIDE the rail host so `useRailExitGuard` finds it; nested inside a host that already
 *  has one it safely defers). */
export function GameSettingsTopicPane(props: { ecosystemId?: string; help?: ReactNode }) {
  return (
    <SettingsDirtyProvider>
      <GameSettingsPane {...props} />
    </SettingsDirtyProvider>
  );
}
