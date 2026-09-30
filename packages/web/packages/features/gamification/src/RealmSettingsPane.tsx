"use client";

import { useCallback, useState } from "react";
import type { ReactNode } from "react";

import { reportUnexpectedAuthError } from "@agentic-toolkit/auth";
import { isForbidden, useResourceItemQuery, useResourceItemWriter } from "@agentic-toolkit/data";
import { gamificationApi, type RealmConfig, type RealmConfigInput } from "@agentic-toolkit/data/gamification";
import {
  DetailsPane,
  SettingsDirtyProvider,
  useDetailsSection,
  useInDetailsPane,
  useSettingsDraft,
} from "@agentic-toolkit/resource";
import { FeatureSwitch } from "@agentic-toolkit/ecosystems";
import { Field } from "@agenticdevelopertoolkit/ui/blocks";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { Switch } from "@agenticdevelopertoolkit/ui/components/switch";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";

/**
 * The product's GAMIFICATION REALM config (each product IS an ecosystem = a "realm"). A
 * single-record config section over /gamification/realms/:eco/config: a `skin` select
 * (rpg / plain), a reference `timezone`, four per-surface toggles (badges / leaderboards /
 * streaks / recaps), and the optional seasons window.
 *
 * The realm's `mode` follows the ecosystem's features — Gaming held means `game`, Gamification
 * alone means `gamification`, neither means `none` — and the backend sets it when a feature is
 * added or removed. So the Gamification on/off switch at the top is a {@link FeatureSwitch}: it
 * adds or removes the Gamification FEATURE (the same write as Manage features), never the mode
 * directly, and is held on while the product has Gaming. A mode change can still backfill
 * members server-side; a save that reports one says so under the bar.
 *
 * It registers with the enclosing {@link DetailsPane}'s one bar. Standing alone (the
 * gamification site's Settings topic, the hub's combined pane) it draws that pane itself; inside
 * a bigger one (the product's Gaming ▸ Settings) it is one section of it.
 *
 * `children` render at the end of the same scroller, under the same bar — the hub passes the
 * catalog, ladder, backfill and event types ({@link GamificationPane}); the gamification site,
 * where each is its own topic, passes none.
 */

const SKINS: { value: "rpg" | "plain"; label: string; help: string }[] = [
  { value: "rpg", label: "RPG", help: "Adventurer framing — levels, quests, and badges." },
  { value: "plain", label: "Plain", help: "Neutral progress framing without the RPG dressing." },
];

// A short, curated list of common IANA zones — plain-text `timezone/timezone.json` coverage
// is overkill for a Select; the realm always has SOME real zone name stored (default 'UTC').
const TIMEZONES = [
  "UTC",
  "America/New_York",
  "America/Chicago",
  "America/Denver",
  "America/Los_Angeles",
  "America/Sao_Paulo",
  "Europe/London",
  "Europe/Berlin",
  "Europe/Moscow",
  "Africa/Cairo",
  "Asia/Dubai",
  "Asia/Kolkata",
  "Asia/Shanghai",
  "Asia/Tokyo",
  "Australia/Sydney",
  "Pacific/Auckland",
] as const;

const ANCHOR_RE = /^\d{4}-\d{2}-\d{2}$/;

/** A real YYYY-MM-DD date, rejecting values JS's lenient Date parsing would otherwise
 *  normalize (e.g. 2026-02-30 → 2026-03-02) — mirrors the backend's parseAnchorMs
 *  (gamification-seasons.ts), so a value that passes here also passes there. */
function seasonAnchorError(anchor: string): string | null {
  if (!ANCHOR_RE.test(anchor)) return "Enter a date as YYYY-MM-DD.";
  const ms = Date.parse(`${anchor}T00:00:00.000Z`);
  if (Number.isNaN(ms) || new Date(ms).toISOString().slice(0, 10) !== anchor) {
    return "Not a real calendar date.";
  }
  return null;
}

/** A whole number of days, 1..366 (one leap year) — mirrors MAX_SEASON_LENGTH_DAYS. */
function seasonLengthError(raw: string): string | null {
  if (!/^\d+$/.test(raw.trim())) return "Enter a whole number of days.";
  const n = Number(raw);
  if (n < 1 || n > 366) return "Must be between 1 and 366 days.";
  return null;
}

// A surface is ON unless explicitly set false, so each toggle initializes from
// `surfaces[key] !== false` and the config's stored map is the source of truth.
const SURFACES: { key: SurfaceKey; label: string; help: string }[] = [
  { key: "badges", label: "Badges", help: "Award and display achievement badges." },
  { key: "leaderboards", label: "Leaderboards", help: "Rank members on public boards." },
  { key: "streaks", label: "Streaks", help: "Track and reward consecutive-day activity." },
  { key: "recaps", label: "Recaps", help: "Periodic progress recaps for members." },
];

type SurfaceKey = "badges" | "leaderboards" | "streaks" | "recaps";

interface Draft {
  skin: "rpg" | "plain";
  timezone: string;
  surfaces: Record<SurfaceKey, boolean>;
  // Seasons' anchor/lengthDays are held as strings (like the level ladder's rungs) so the
  // inputs can be cleared mid-edit; they're coerced + validated on save.
  seasonsOn: boolean;
  seasonsAnchor: string;
  seasonsLengthDays: string;
}

function toDraft(cfg: RealmConfig): Draft {
  return {
    skin: cfg.skin,
    // Defensive default: keeps the Select controlled even if a caller's config predates
    // `timezone` (unset realms still get 'UTC' server-side).
    timezone: cfg.timezone ?? "UTC",
    surfaces: {
      badges: cfg.surfaces.badges !== false,
      leaderboards: cfg.surfaces.leaderboards !== false,
      streaks: cfg.surfaces.streaks !== false,
      recaps: cfg.surfaces.recaps !== false,
    },
    seasonsOn: cfg.seasons != null,
    seasonsAnchor: cfg.seasons?.anchor ?? "",
    seasonsLengthDays: cfg.seasons ? String(cfg.seasons.lengthDays) : "",
  };
}

/**
 * Read one realm's gamification config, classifying the failure itself.
 *
 * A 403 is EXPECTED here — it is what a realm the caller cannot administer returns — so it becomes
 * a sentence about permissions and is deliberately NOT reported as an incident. That is why the
 * call site passes `reportErrors: false`: this function reports the failures worth reporting, and
 * one failure reported twice under two contexts would be worse than none.
 *
 * Module scope, so one identity serves every mount. The realm is the query key's id, not something
 * closed over.
 */
async function loadRealmConfig(ecosystemId: string): Promise<RealmConfig> {
  try {
    return await gamificationApi.getRealmConfig(ecosystemId);
  } catch (err) {
    if (isForbidden(err)) {
      throw new Error("You don't have access to this realm's gamification settings.");
    }
    reportUnexpectedAuthError(err, { feature: "gamification-realm", step: "load" });
    // A non-Error rejection would otherwise reach the user as the hook's generic wording; keep the
    // sentence this pane has always shown for it.
    throw err instanceof Error ? err : new Error("Failed to load gamification settings.");
  }
}

/** The realm config endpoint, for the pane's API button. */
export function realmConfigApi(ecosystemId: string | undefined) {
  return {
    method: "PUT",
    path: "/gamification/realms/{ecosystemId}/config",
    pathValues: { ecosystemId },
    title: "Realm config API",
  };
}

export function RealmSettingsPane({
  ecosystemId,
  help,
  children,
}: {
  ecosystemId?: string;
  /** Unused: the breadcrumb names the pane (kept for the ScopedPane prop shape). */
  title?: ReactNode;
  /** The pane's "?" help, when this draws its own pane. Inside a bigger pane, that pane's help
   *  speaks for it. */
  help?: ReactNode;
  /** Rendered at the END of this pane's scroller, under its save bar — see the file doc. */
  children?: ReactNode;
}) {
  const inPane = useInDetailsPane();
  const body = <RealmSettingsSection ecosystemId={ecosystemId}>{children}</RealmSettingsSection>;
  if (inPane) return body;
  return (
    <DetailsPane help={help} api={realmConfigApi(ecosystemId)}>
      {body}
    </DetailsPane>
  );
}

/** The realm config's fields, registered as one section of the enclosing DetailsPane. */
function RealmSettingsSection({ ecosystemId, children }: { ecosystemId?: string; children?: ReactNode }) {
  // Cached per realm, so coming back to this topic paints the saved settings on the first frame
  // and revalidates behind them, instead of blanking to "Loading…" on every visit.
  const { item: config, error: loadError } = useResourceItemQuery<RealmConfig>(
    "realm-config",
    ecosystemId ?? null,
    loadRealmConfig,
    { reportErrors: false },
  );
  const writeConfig = useResourceItemWriter<RealmConfig>("realm-config");

  // A backfill the last save triggered. "Saved." is the pane's; this is the part only this
  // section knows.
  const [replayedNote, setReplayedNote] = useState<string | null>(null);

  // Seeding, dirty-tracking and the base a partial save diffs against all live in the hook —
  // see `useSettingsDraft` for why each of those is subtler than it looks under caching.
  const {
    draft,
    patch: patchDraft,
    seed,
    dirty,
    commit,
    reset,
  } = useSettingsDraft<RealmConfig, Draft>(config, toDraft);

  // Validated only while seasons are ON, so a save with seasons untouched (or turned off) is
  // never blocked by a stale anchor/lengthDays left over from a prior edit.
  const seasonsAnchorError = draft?.seasonsOn ? seasonAnchorError(draft.seasonsAnchor) : null;
  const seasonsLengthError = draft?.seasonsOn ? seasonLengthError(draft.seasonsLengthDays) : null;
  const blockedReason = seasonsAnchorError ?? seasonsLengthError;

  const patch = useCallback(
    (next: Partial<Draft>) => {
      setReplayedNote(null);
      patchDraft(next);
    },
    [patchDraft],
  );

  const setSurface = useCallback(
    (key: SurfaceKey, on: boolean) => {
      if (!draft) return;
      setReplayedNote(null);
      patchDraft({ surfaces: { ...draft.surfaces, [key]: on } });
    },
    [draft, patchDraft],
  );

  const save = useCallback(async () => {
    if (!ecosystemId || !draft || !seed || blockedReason) return;

    // Send only the changed fields — diffed against `seed`, the snapshot this draft was seeded
    // from, NOT against the server's current copy. A field the user never touched must not be
    // sent just because somebody else changed it meanwhile.
    //
    // When any surface changed, send the FULL 4-key map so the persisted state matches the UI
    // regardless of the backend's merge-vs-replace semantics (a surface is ON unless explicitly
    // false, so an explicit `true` is always harmless).
    const body: RealmConfigInput = {};
    if (draft.skin !== seed.skin) body.skin = draft.skin;
    if (draft.timezone !== seed.timezone) body.timezone = draft.timezone;
    const surfacesChanged = SURFACES.some((s) => draft.surfaces[s.key] !== seed.surfaces[s.key]);
    if (surfacesChanged) body.surfaces = { ...draft.surfaces };
    // seasons: undefined (omitted) = leave unchanged; null = clear; an object sets the window.
    // Already blocked from reaching here while invalid (`blockedReason` above).
    const seasonsChanged =
      draft.seasonsOn !== seed.seasonsOn ||
      (draft.seasonsOn &&
        (draft.seasonsAnchor !== seed.seasonsAnchor ||
          draft.seasonsLengthDays !== seed.seasonsLengthDays));
    if (seasonsChanged) {
      body.seasons = draft.seasonsOn
        ? { anchor: draft.seasonsAnchor, lengthDays: Number(draft.seasonsLengthDays) }
        : null;
    }

    try {
      const res = await gamificationApi.updateRealmConfig(ecosystemId, body);
      // The server's own answer, written straight into the cache rather than invalidated: it is
      // already in hand, so a re-read would spend a request to arrive back at these bytes.
      writeConfig(ecosystemId, res.config);
      commit(res.config);
      setReplayedNote(
        res.replayed
          ? `Backfilled ${res.replayed.subjects} members, ${res.replayed.badges} badges.`
          : null,
      );
    } catch (err) {
      if (!isForbidden(err)) {
        reportUnexpectedAuthError(err, { feature: "gamification-realm", step: "save" });
      }
      // The pane shows what this throws, and stops its save here.
      throw new Error(
        isForbidden(err)
          ? "You don't have access to change this realm's gamification settings."
          : err instanceof Error
            ? err.message
            : "Failed to save gamification settings.",
      );
    }
  }, [ecosystemId, draft, seed, blockedReason, commit, writeConfig]);

  const cancel = useCallback(() => {
    reset();
    setReplayedNote(null);
  }, [reset]);

  useDetailsSection({ dirty, canSave: !blockedReason, blockedReason, save, reset: cancel });

  // The feature switch changes the realm's mode server-side; re-read the config so every reader
  // of it (this section, the Gaming rail, the Gaming ▸ Settings pane) follows on the same tick.
  const rereadConfig = useCallback(async () => {
    if (!ecosystemId) return;
    writeConfig(ecosystemId, await gamificationApi.getRealmConfig(ecosystemId));
  }, [ecosystemId, writeConfig]);

  return (
    <div className="max-w-3xl space-y-7">
      <FeatureSwitch
        ecosystemId={ecosystemId}
        featureKey="gamification"
        label="Gamification"
        description="When off, telemetry keeps flowing but awards and gamification UI are suppressed. Turning it on backfills existing members."
        lockedBy="gaming"
        lockedDescription="On, because this product has Gaming — gamification comes with it."
        onApplied={rereadConfig}
      />
      <ErrorText error={loadError} />
      {!draft && !loadError && <p className="text-sm text-apt-text-muted">Loading…</p>}
      {replayedNote && !dirty && <p className="text-sm text-apt-text-muted">{replayedNote}</p>}

      {draft && (
        <>
          {/* Skin */}
          <div className="flex flex-col gap-2 border-t border-apt-border pt-6 sm:flex-row sm:items-start sm:justify-between sm:gap-6">
            <div className="min-w-0">
              <Label htmlFor="gamification-skin" className="text-sm font-medium text-apt-text">
                Skin
              </Label>
              <p className="mt-0.5 text-xs text-apt-text-muted">
                {SKINS.find((s) => s.value === draft.skin)?.help}
              </p>
            </div>
            <Select
              id="gamification-skin"
              value={draft.skin}
              onChange={(e) => patch({ skin: e.target.value as "rpg" | "plain" })}
            >
              {SKINS.map((s) => (
                <option key={s.value} value={s.value}>
                  {s.label}
                </option>
              ))}
            </Select>
          </div>

          {/* Timezone */}
          <div className="flex flex-col gap-2 border-t border-apt-border pt-6 sm:flex-row sm:items-start sm:justify-between sm:gap-6">
            <div className="min-w-0">
              <Label htmlFor="gamification-timezone" className="text-sm font-medium text-apt-text">
                Timezone
              </Label>
              <p className="mt-0.5 text-xs text-apt-text-muted">
                Reference zone for the realm&apos;s late-night (Night Owl) window. Day and
                streak rollups stay UTC.
              </p>
            </div>
            <Select
              id="gamification-timezone"
              value={draft.timezone}
              onChange={(e) => patch({ timezone: e.target.value })}
            >
              {/* A realm's stored zone can be any IANA name (set via the API), not just one of
                  the curated 16 — surface it as its own option so the Select never silently
                  misrepresents (or, on save, overwrites) a zone outside the shortlist. */}
              {((TIMEZONES as readonly string[]).includes(draft.timezone)
                ? TIMEZONES
                : [draft.timezone, ...TIMEZONES]
              ).map((tz) => (
                <option key={tz} value={tz}>
                  {tz}
                </option>
              ))}
            </Select>
          </div>

          {/* Surfaces */}
          <div className="border-t border-apt-border pt-6">
            <p className="text-sm font-medium text-apt-text">Surfaces</p>
            <p className="mt-0.5 text-xs text-apt-text-muted">
              Which gamification surfaces are shown to members. Each is on unless turned off.
            </p>
            <div className="mt-4 flex flex-col gap-5">
              {SURFACES.map((s) => (
                <div key={s.key} className="flex items-start justify-between gap-6">
                  <div className="min-w-0">
                    <Label
                      htmlFor={`gamification-surface-${s.key}`}
                      className="text-sm font-medium text-apt-text"
                    >
                      {s.label}
                    </Label>
                    <p className="mt-0.5 text-xs text-apt-text-muted">{s.help}</p>
                  </div>
                  <Switch
                    id={`gamification-surface-${s.key}`}
                    checked={draft.surfaces[s.key]}
                    onCheckedChange={(on) => setSurface(s.key, on)}
                  />
                </div>
              ))}
            </div>
          </div>

          {/* Seasons — a read-model window over existing stats; off (null) leaves the
              season board absent. Wired into THIS pane's draft/save bar, not a second one. */}
          <div className="border-t border-apt-border pt-6">
            <div className="flex items-start justify-between gap-6">
              <div className="min-w-0">
                <Label htmlFor="gamification-seasons-on" className="text-sm font-medium text-apt-text">
                  Seasons
                </Label>
                <p className="mt-0.5 text-xs text-apt-text-muted">
                  Opt into a recurring season board, resetting every N days from an anchor
                  date.
                </p>
              </div>
              <Switch
                id="gamification-seasons-on"
                checked={draft.seasonsOn}
                onCheckedChange={(on) => patch({ seasonsOn: on })}
              />
            </div>
            {draft.seasonsOn && (
              <div className="mt-4 flex flex-col gap-4 sm:flex-row">
                <Field label="Season 0 anchor" error={seasonsAnchorError ?? undefined} className="flex-1">
                  <Input
                    type="date"
                    value={draft.seasonsAnchor}
                    aria-invalid={!!seasonsAnchorError}
                    onChange={(e) => patch({ seasonsAnchor: e.target.value })}
                  />
                </Field>
                <Field label="Length (days)" error={seasonsLengthError ?? undefined} className="w-36">
                  <Input
                    type="number"
                    min={1}
                    max={366}
                    value={draft.seasonsLengthDays}
                    aria-invalid={!!seasonsLengthError}
                    onChange={(e) => patch({ seasonsLengthDays: e.target.value })}
                  />
                </Field>
              </div>
            )}
          </div>

          {children}
        </>
      )}
    </div>
  );
}

/** The Settings TOPIC (the gamification site's fourth topic): the realm config alone, in its
 *  own guard registry. The provider goes here rather than around the whole feature because it
 *  has to sit INSIDE the rail host ResourceExplorer mounts — outside it, `useRailExitGuard`
 *  finds no host and the rail's own level-switch guard never learns the pane is dirty. Nested
 *  inside a host that already has one (the hub), the provider defers, so this is safe to
 *  compose anywhere. */
export function GamificationSettingsTopicPane(props: { ecosystemId?: string; help?: ReactNode }) {
  return (
    <SettingsDirtyProvider>
      <RealmSettingsPane {...props} />
    </SettingsDirtyProvider>
  );
}
