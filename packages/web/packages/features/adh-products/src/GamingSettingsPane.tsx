"use client";

import { useCallback, useState } from "react";
import type { ReactNode } from "react";

import { reportUnexpectedAuthError } from "@agentic-toolkit/auth";
import { isForbidden, useResourceItemQuery, useResourceItemWriter } from "@agentic-toolkit/data";
import {
  gamificationApi,
  type GamingMode,
  type RealmConfig,
  type RealmConfigInput,
} from "@agentic-toolkit/data/gamification";
import { type Game, type GameInput, gamesApi } from "@agentic-toolkit/data/games";
import {
  EditActionBar,
  SettingsDirtyProvider,
  useReportSettingsDirty,
  useSettingsDraft,
} from "@agentic-toolkit/resource";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import {
  GAME_FOR_ECOSYSTEM_CACHE_KEY,
  GameOperationalFields,
  gameDiffers,
  gameNormalize,
  gameToInput,
  gameValidate,
  loadGameRow,
  REALM_CONFIG_CACHE_KEY,
  useGameForEcosystem,
} from "@agentic-toolkit/games";
import { GamificationSettingsTopicPane } from "@agentic-toolkit/gamification";

const GAMING_SUPPORT_OPTIONS: { value: GamingMode; label: string }[] = [
  { value: "none", label: "None — no game mechanics" },
  { value: "gamification", label: "Gamification — badges, levels and streaks on a regular product" },
  { value: "game", label: "Dedicated game — a playable game, with gamification tuned for it" },
];

/**
 * Read one realm's gaming mode — a private copy of `RealmSettingsPane`'s (and
 * `GamingGroup.tsx`'s) own `loadRealmConfig`: `@agentic-toolkit/games` keeps its own version of
 * this loader package-internal (its `GameSettingsPane` reaches it via a relative import to
 * `useGameForEcosystem.ts`, not that package's barrel), so there is no shared function to import
 * here — only `REALM_CONFIG_CACHE_KEY` (imported above) is a real, public export, and it is what
 * keeps all three copies of this loader pointed at the SAME cache entry.
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
 * The "Gaming support" select, top of the pane (§4.4): its own draft/save cycle over just the
 * `mode` field, sharing `REALM_CONFIG_CACHE_KEY` with `RealmSettingsPane` /
 * `GamingGroup` so a save here is instantly visible to both (which members show, and what the
 * embedded realm settings below say about the switch that also writes this field).
 *
 * A field of its own rather than folded into `RealmSettingsPane`'s draft: `RealmSettingsPane` is
 * reused WHOLESALE below (see the pane's own doc comment) for its skin/timezone/surfaces/seasons
 * fields, and that component owns its own save bar. Two controls that read/write the same column
 * — a 3-way Select here, a 2-way Switch inside the reused pane — is the same "two views of one
 * stored value" the games site's own Enable Gaming switch and this popup already are (design doc
 * §5.3); the Select is the one that can express `game`, so it is this pane's real control and the
 * embedded switch reads checked-and-disabled while `mode === 'game'`, same as it does everywhere
 * else. Two independent EditActionBars is the visible cost, and it is the SAME cost
 * `GamificationPane.tsx`'s own children (Catalog / Levels / backfill) already pay for the same
 * reason — a shared save bar would need to reach into a component this pane does not own.
 */
function GamingModeSection({ ecosystemId }: { ecosystemId?: string }) {
  const { item: config, error: loadError } = useResourceItemQuery<RealmConfig>(
    REALM_CONFIG_CACHE_KEY,
    ecosystemId ?? null,
    loadRealmConfig,
    { reportErrors: false },
  );
  const writeConfig = useResourceItemWriter<RealmConfig>(REALM_CONFIG_CACHE_KEY);
  const writeGame = useResourceItemWriter<Game | null>(GAME_FOR_ECOSYSTEM_CACHE_KEY);

  const [saveError, setSaveError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [savedNote, setSavedNote] = useState<string | null>(null);

  // One field, but the same seeding rules as any settings draft — and this one shares its
  // cache entry with two other controls over the same column (the reused realm switch below,
  // the games site's own), so "the server's copy moved while I was looking at it" is the
  // ordinary case here rather than the exotic one. See `useSettingsDraft`.
  const { draft, replace: setDraft, dirty, commit, reset } = useSettingsDraft<RealmConfig, GamingMode>(
    config,
    (c) => c.mode,
  );

  useReportSettingsDirty("gaming-mode", dirty);

  const save = useCallback(async () => {
    if (!ecosystemId || draft === null || !dirty) return;
    setSaving(true);
    setSaveError(null);
    setSavedNote(null);
    const body: RealmConfigInput = { mode: draft };
    try {
      const res = await gamificationApi.updateRealmConfig(ecosystemId, body);
      writeConfig(ecosystemId, res.config);
      // Entering `game` mode MINTS this product's game server-side, and the PUT's own response
      // carries only `{config, replayed}` — so the section below, which reads the game row
      // through the shared cache entry, would go on rendering the `null` it cached before the
      // mint and tell the operator there is no game to configure. Re-read it through the same
      // loader that entry is populated by, exactly as `GameSettingsPane` does after its own
      // mode write. Unconditional rather than only on `→ game`: leaving the mode does not
      // delete the row, but this is also the moment a row deleted elsewhere becomes visible,
      // and one request on an explicit save is not worth a condition that can go stale.
      writeGame(ecosystemId, await loadGameRow(ecosystemId));
      commit(res.config);
      setSavedNote(
        res.replayed
          ? `Enabled — backfilled ${res.replayed.subjects} members, ${res.replayed.badges} badges.`
          : "Saved.",
      );
    } catch (err) {
      if (!isForbidden(err)) {
        reportUnexpectedAuthError(err, { feature: "gaming-settings", step: "save-mode" });
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
  }, [ecosystemId, draft, dirty, commit, writeConfig, writeGame]);

  const cancel = useCallback(() => {
    reset();
    setSaveError(null);
    setSavedNote(null);
  }, [reset]);

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <EditActionBar
        dirty={dirty}
        canSave={dirty}
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
      <div className="px-6 py-6">
        <div className="max-w-3xl">
          <ErrorText error={loadError} />
          {!draft && !loadError && <p className="text-sm text-apt-text-muted">Loading…</p>}
          {draft && (
            <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between sm:gap-6">
              <div className="min-w-0">
                <Label htmlFor="gaming-support" className="text-sm font-medium text-apt-text">
                  Gaming support
                </Label>
                <p className="mt-0.5 text-xs text-apt-text-muted">
                  Whether this product has game mechanics, and what shape they take.
                </p>
              </div>
              <Select
                id="gaming-support"
                value={draft}
                onChange={(e) => {
                  setSavedNote(null);
                  setDraft(e.target.value as GamingMode);
                }}
              >
                {GAMING_SUPPORT_OPTIONS.map((o) => (
                  <option key={o.value} value={o.value}>
                    {o.label}
                  </option>
                ))}
              </Select>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

/**
 * The game's own operational fields (§4.4: status, character names, event log, event
 * retention) — everything `GameOperationalFields` renders, and nothing `features/games/` no
 * longer edits (name/slug/description are the PRODUCT's, under its Settings). Its own
 * draft/save cycle, resolving "the" game via `useGameForEcosystem` rather than being handed one
 * — the one-game-per-product design (§1) is what makes that resolution safe.
 *
 * The save sends the WHOLE `GameInput` (`gameToInput`/`gameNormalize`), same as every pane in
 * `features/games/` that edits this row — the draft is seeded from the loaded record and this
 * section never touches `engine`/`engineConfig`, so the Engine topic's fields round-trip
 * untouched even though this pane never renders them.
 */
function GameOperationalFieldsSection({ ecosystemId }: { ecosystemId?: string }) {
  const { game, error: loadError } = useGameForEcosystem(ecosystemId);
  const writeGame = useResourceItemWriter<Game | null>(GAME_FOR_ECOSYSTEM_CACHE_KEY);

  const [saveError, setSaveError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [savedNote, setSavedNote] = useState<string | null>(null);

  // `gameDiffers` rather than the hook's JSON default: a `GameInput`'s optional fields differ
  // structurally in ways that are not differences (see `GameDetail`), and this is the same
  // comparison every other pane editing this row already dirties on.
  const { draft, replace: setDraft, dirty, commit, reset } = useSettingsDraft<Game, GameInput>(
    game,
    gameToInput,
    (a, b) => !gameDiffers(a, b),
  );

  const validationError = draft ? gameValidate(draft) : null;
  const canSave = dirty && !validationError;

  useReportSettingsDirty("game-operational-fields", dirty);

  const save = useCallback(async () => {
    if (!ecosystemId || !game || !draft || !canSave) return;
    setSaving(true);
    setSaveError(null);
    setSavedNote(null);
    try {
      const updated = await gamesApi.update(game.id, gameNormalize(draft));
      // Keyed by ECOSYSTEM id, not the game's own uuid: `useGameForEcosystem` (and every other
      // pane sharing it — Engine, Content, Connections, Effects) reads this cache under
      // `ecosystemId`, per §1's "no address of its own". `Game` itself carries no `ecosystemId`
      // field to read back off `updated`, which is exactly why the id written here is the prop,
      // not anything pulled from the response.
      writeGame(ecosystemId, updated);
      commit(updated);
      setSavedNote("Saved.");
    } catch (err) {
      if (!isForbidden(err)) {
        reportUnexpectedAuthError(err, { feature: "gaming-settings", step: "save-game" });
      }
      setSaveError(
        isForbidden(err)
          ? "You don't have access to change this game's settings."
          : err instanceof Error
            ? err.message
            : "Failed to save this game's settings.",
      );
    } finally {
      setSaving(false);
    }
  }, [ecosystemId, game, draft, canSave, commit, writeGame]);

  const cancel = useCallback(() => {
    reset();
    setSaveError(null);
    setSavedNote(null);
  }, [reset]);

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
      <div className="px-6 py-6">
        <div className="max-w-3xl">
          <ErrorText error={loadError} />
          {!draft && !loadError && <p className="text-sm text-apt-text-muted">Loading…</p>}
          {draft && <GameOperationalFields draft={draft} onChange={setDraft} error={validationError} />}
        </div>
      </div>
    </div>
  );
}

/**
 * The Gaming group's Settings member (§4.4) — always the last item `GamingGroup` builds, and the
 * only one shown while `mode === 'none'`. Composed of up to three independently-saved sections
 * (`GamingModeSection`'s own doc comment explains why they are independent rather than one
 * shared draft):
 *
 *   - The "Gaming support" select, always shown.
 *   - The game's own operational fields, only while `mode === 'game'`.
 *   - The realm settings (`RealmSettingsPane`, via `GamificationSettingsTopicPane` so it keeps
 *     its own `SettingsDirtyProvider` — which defers to this pane's own, below, exactly as its
 *     doc comment says a nested one does), while `mode !== 'none'`.
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
  // The read that decides which of the two lower sections to show — a third read of the same
  // `REALM_CONFIG_CACHE_KEY` cache entry `GamingModeSection` and `GamingGroup` also read, so all
  // three land on whichever value is currently cached (or in flight) rather than one lagging.
  const { item: config } = useResourceItemQuery<RealmConfig>(
    REALM_CONFIG_CACHE_KEY,
    ecosystemId ?? null,
    loadRealmConfig,
    { reportErrors: false },
  );
  const mode = config?.mode ?? "none";

  return (
    <SettingsDirtyProvider>
      <div className="flex min-h-0 min-w-0 flex-1 flex-col overflow-y-auto">
        {help && <p className="px-6 pt-6 text-sm text-apt-text-muted">{help}</p>}
        <GamingModeSection ecosystemId={ecosystemId} />
        {mode === "game" && (
          <div className="border-t border-apt-border">
            <GameOperationalFieldsSection ecosystemId={ecosystemId} />
          </div>
        )}
        {mode !== "none" && (
          <div className="border-t border-apt-border">
            <GamificationSettingsTopicPane ecosystemId={ecosystemId} />
          </div>
        )}
      </div>
    </SettingsDirtyProvider>
  );
}
