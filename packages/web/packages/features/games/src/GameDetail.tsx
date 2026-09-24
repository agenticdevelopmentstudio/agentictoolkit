"use client";

import { useId } from "react";
import { Card, CardContent } from "@agenticdevelopertoolkit/ui/components/card";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { Textarea } from "@agenticdevelopertoolkit/ui/components/textarea";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { DetailSection } from "@agentic-toolkit/resource";
import type {
  Game,
  GameCharacterNames,
  GameEventLog,
  GameInput,
  GameStatus,
} from "@agentic-toolkit/data/games";
import { IntegerInput } from "./IntegerInput";
import { wholeNumberProblem } from "./fields";

/** `game.games.status` — a closed set with a `check` behind it, so a select rather than a
 *  text field. The help is the schema's own distinction: `hidden` is delisted but still
 *  startable, which is what a boolean could never have expressed. */
export const GAME_STATUSES: { value: GameStatus; label: string }[] = [
  { value: "active", label: "Active — listed, and anyone can start it" },
  { value: "hidden", label: "Hidden — delisted, but still startable from a link or a save" },
  { value: "retired", label: "Retired — neither listed nor startable" },
];

/** `game.games.character_names` — whether players get a per-game name and picture. */
export const GAME_CHARACTER_NAMES: { value: GameCharacterNames; label: string }[] = [
  { value: "off", label: "Off — players appear under their account name" },
  { value: "optional", label: "Optional — players may set a character name and picture" },
  { value: "required", label: "Required — players must set one before they can start" },
];

/** `game.games.event_log` — whether the log is the truth. The distinction is retention:
 *  `authoritative` is never swept, so the day count below stops applying to it. */
export const GAME_EVENT_LOGS: { value: GameEventLog; label: string }[] = [
  { value: "debug", label: "Debug — kept for the retention window below, then swept" },
  { value: "authoritative", label: "Authoritative — the log is the truth, and is kept forever" },
];

/** `game.games.event_retention_days` — the column's own default. */
export const DEFAULT_EVENT_RETENTION_DAYS = 90;

export function gameBlank(): GameInput {
  return {
    slug: "",
    name: "",
    description: "",
    engine: "",
    engineConfig: "",
    // The four schema defaults, not a UI preference: in `game.games`, `character_names`
    // defaults to 'off', `status` to 'active', `event_log` to 'debug' and
    // `event_retention_days` to 90.
    characterNames: "off",
    status: "active",
    eventLog: "debug",
    eventRetentionDays: DEFAULT_EVENT_RETENTION_DAYS,
  };
}

/** The WHOLE editable row, not one pane's half: Engine and Settings edit the same record
 *  (name/slug/description are no longer edited from this package at all — see
 *  `GameOperationalFields` below — but they still round-trip through every save here), so
 *  a partial input would let one pane's save blank the other's fields. */
export function gameToInput(g: Game): GameInput {
  return {
    slug: g.slug,
    name: g.name,
    description: g.description,
    engine: g.engine,
    engineConfig: g.engineConfig,
    characterNames: g.characterNames,
    status: g.status,
    eventLog: g.eventLog,
    eventRetentionDays: g.eventRetentionDays,
  };
}

export function gameNormalize(d: GameInput): GameInput {
  return {
    slug: d.slug.trim(),
    name: d.name.trim(),
    description: d.description.trim(),
    engine: d.engine.trim(),
    engineConfig: d.engineConfig.trim(),
    // The three closed sets carry no whitespace to trim — they come from a select, and
    // the retention window is already a parsed number rather than text (see `fields.ts`).
    characterNames: d.characterNames,
    status: d.status,
    eventLog: d.eventLog,
    eventRetentionDays: d.eventRetentionDays,
  };
}

export function gameDiffers(a: GameInput, b: GameInput): boolean {
  return (
    a.slug !== b.slug ||
    a.name !== b.name ||
    a.description !== b.description ||
    a.engine !== b.engine ||
    a.engineConfig !== b.engineConfig ||
    a.characterNames !== b.characterNames ||
    a.status !== b.status ||
    a.eventLog !== b.eventLog ||
    a.eventRetentionDays !== b.eventRetentionDays
  );
}

/**
 * Returns an error message, or null when the draft is valid.
 *
 * No slug/name checks here any more: `Game.id` is a plain uuid (§1 of the
 * product-gaming-modes design) — a game has no address of its own, so there is no rdid
 * leaf grammar for its slug to obey, and name/slug/description are the PRODUCT's fields
 * now (derived onto the game at mint, edited under the product's Settings, not
 * this package). What is left to validate is the operational half this package still
 * owns: the engine config's JSON and the retention window.
 */
export function gameValidate(draft: GameInput): string | null {
  const config = draft.engineConfig.trim();
  if (config) {
    try {
      JSON.parse(config);
    } catch {
      return "Engine config must be valid JSON.";
    }
  }
  // The column's own `games_event_retention_days_chk` is `> 0`, and it applies whatever
  // `event_log` says — `authoritative` stops the sweep READING the window, it does not
  // make the column accept a zero. So the bound is checked unconditionally rather than
  // only on the branch that uses it, which is what the constraint actually does.
  if (!Number.isInteger(draft.eventRetentionDays)) return wholeNumberProblem("Event retention");
  if (draft.eventRetentionDays < 1) return "Event retention must be at least one day.";
  return null;
}

function set<K extends keyof GameInput>(
  draft: GameInput,
  onChange: (next: GameInput) => void,
  key: K,
  value: GameInput[K],
) {
  onChange({ ...draft, [key]: value } as GameInput);
}

/**
 * The four operator switches adh itself READS AND ACTS ON: `status` and
 * `character_names` (the profile route rejects a blank name when names are required),
 * then `event_log` and `event_retention_days`, which the retention sweep deletes rows on
 * the strength of.
 *
 * Name, slug and description are NOT here — they are the PRODUCT's fields now (derived
 * onto the game at mint; edited under the product's own Settings, a different
 * pane in a different package entirely). This is the operational half of what used to be
 * one `GameIdentityFields` component; the identity half is gone from this package along
 * with the games rail that used to edit it (see docs/superpowers/specs/
 * 2026-08-22-product-gaming-modes-design.md §5.3, §1).
 *
 * `engine`/`engine_config` are OPAQUE to adh and belong to the Engine topic; everything
 * here is a switch adh reads. Controlled; Save/Cancel live in the pane's button bar. With
 * `title` the fields sit in a titled DetailSection (Engine's pane); without it they render
 * bare (Settings, which supplies its own section framing around the whole pane).
 */
export function GameOperationalFields({
  title,
  draft,
  onChange,
  error,
}: {
  title?: string;
  draft: GameInput;
  onChange: (next: GameInput) => void;
  error?: string | null;
}) {
  const uid = useId();
  const statusId = `${uid}-status`;
  const charactersId = `${uid}-character-names`;
  const eventLogId = `${uid}-event-log`;
  const retentionId = `${uid}-event-retention-days`;

  const body = (
    <Card>
      <CardContent className="flex flex-col gap-5">
        <div className="flex flex-col gap-2">
          <Label htmlFor={statusId}>Status</Label>
          <Select
            id={statusId}
            value={draft.status}
            onChange={(e) => set(draft, onChange, "status", e.target.value as GameStatus)}
          >
            {GAME_STATUSES.map((s) => (
              <option key={s.value} value={s.value}>
                {s.label}
              </option>
            ))}
          </Select>
        </div>
        <div className="flex flex-col gap-2">
          <Label htmlFor={charactersId}>Character names</Label>
          <Select
            id={charactersId}
            value={draft.characterNames}
            onChange={(e) =>
              set(draft, onChange, "characterNames", e.target.value as GameCharacterNames)
            }
          >
            {GAME_CHARACTER_NAMES.map((c) => (
              <option key={c.value} value={c.value}>
                {c.label}
              </option>
            ))}
          </Select>
          <p className="text-xs text-apt-text-muted">
            Whether a player gets a display name and picture that belong to THIS game, instead
            of playing under their account&rsquo;s.
          </p>
        </div>
        <div className="flex flex-col gap-2">
          <Label htmlFor={eventLogId}>Event log</Label>
          <Select
            id={eventLogId}
            value={draft.eventLog}
            onChange={(e) => set(draft, onChange, "eventLog", e.target.value as GameEventLog)}
          >
            {GAME_EVENT_LOGS.map((l) => (
              <option key={l.value} value={l.value}>
                {l.label}
              </option>
            ))}
          </Select>
        </div>
        <div className="flex flex-col gap-2">
          <Label htmlFor={retentionId}>Event retention (days)</Label>
          <IntegerInput
            id={retentionId}
            value={draft.eventRetentionDays}
            fallback={DEFAULT_EVENT_RETENTION_DAYS}
            placeholder={String(DEFAULT_EVENT_RETENTION_DAYS)}
            onChange={(eventRetentionDays) =>
              set(draft, onChange, "eventRetentionDays", eventRetentionDays)
            }
          />
          <p className="text-xs text-apt-text-muted">
            {draft.eventLog === "authoritative"
              ? "Not applied while the log is authoritative — those events are never swept — but still stored, and used again if you switch back to Debug."
              : "How long a debug game's events are kept before they are swept. Empty means the default, 90."}
          </p>
        </div>
        <ErrorText error={error} />
      </CardContent>
    </Card>
  );

  return title ? <DetailSection title={title}>{body}</DetailSection> : body;
}

/** How the game RUNS — which engine drives it and how that engine is configured. */
export function GameEngineFields({
  title,
  draft,
  onChange,
  error,
}: {
  title?: string;
  draft: GameInput;
  onChange: (next: GameInput) => void;
  error?: string | null;
}) {
  const uid = useId();
  const engineId = `${uid}-engine`;
  const configId = `${uid}-engine-config`;

  const body = (
    <Card>
      <CardContent className="flex flex-col gap-5">
        <div className="flex flex-col gap-2">
          <Label htmlFor={engineId}>Engine</Label>
          <Input
            id={engineId}
            placeholder="ink"
            value={draft.engine}
            onChange={(e) => set(draft, onChange, "engine", e.target.value)}
            autoCapitalize="none"
            autoCorrect="off"
            spellCheck={false}
          />
          <p className="text-xs text-apt-text-muted">
            The runtime this game is built for. adh hosts the backend, not the engine.
          </p>
        </div>
        <div className="flex flex-col gap-2">
          <Label htmlFor={configId}>Engine config</Label>
          <Textarea
            id={configId}
            rows={10}
            placeholder="{}"
            value={draft.engineConfig}
            onChange={(e) => set(draft, onChange, "engineConfig", e.target.value)}
            className="font-mono text-xs"
            autoCapitalize="none"
            autoCorrect="off"
            spellCheck={false}
          />
          <p className="text-xs text-apt-text-muted">
            JSON handed to the engine as-is. Leave it empty for the engine&rsquo;s defaults.
          </p>
        </div>
        <ErrorText error={error} />
      </CardContent>
    </Card>
  );

  return title ? <DetailSection title={title}>{body}</DetailSection> : body;
}
