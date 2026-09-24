"use client";

import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type ReactElement,
} from "react";

import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import {
  chordFromEvent,
  formatChord,
  sameChord,
  useRegisteredShortcuts,
} from "@agenticdevelopertoolkit/ui/hooks/useShortcut";
import { SettingRow } from "@agentic-toolkit/account";

// The PACKAGE PATH, not "../header/hub-preferences" — the store holds module-level mutable
// state and has its own tsup entry + `external` pairing for it. A relative import here would
// inline a SECOND copy into this entry, and the fork would be invisible in exactly the way
// that matters: this panel would write the new chord into its own private snapshot while the
// header kept listening on the old one, with nothing wrong in dev (which resolves the
// `development` condition to src/, where there is only ever one module). Same rule, same
// reason, as AppearancePanel's note on `@agentic-toolkit/adh/auth`.
import {
  DEFAULT_SITE_MENU_SHORTCUT,
  setSiteMenuShortcut,
  useHubPreferences,
} from "@agentic-toolkit/adh/header/hub-preferences";
import { DetailSection, SettingsBody } from "@agentic-toolkit/resource";
import { Card, CardContent } from "@agenticdevelopertoolkit/ui/components/card";

/** The site menu's own registration, so the conflict check does not report the shortcut
 *  colliding with itself. Must match the `label` SiteMenu passes as `openShortcut`. */
const SITE_MENU_LABEL = "Site menu";

type Recording =
  | { state: "idle" }
  | { state: "listening" }
  | { state: "conflict"; keys: string; with: string };

/**
 * Hub Preferences: the per-device choices about the hub's own chrome. One setting today —
 * the chord that opens the site menu.
 *
 * Saved to THIS BROWSER, not to the account, and the panel says so rather than leaving the
 * user to discover it: every other section here writes through to the user, so a section
 * that doesn't is the surprising one. The reasoning is in the store
 * (`header/hub-preferences.ts`); the short version is that a chord is a property of the
 * keyboard in front of you.
 *
 * Recording captures the NEXT keystroke rather than parsing a typed chord, because a chord
 * is only meaningful as the event it has to match: what "⌥S" produces depends on the layout
 * (on macOS, `ß`), so a chord typed into a text box can be one the keyboard can never
 * reproduce. Pressing the keys cannot be wrong in that way.
 */
export function HubPreferencesPanel(): ReactElement {
  const { siteMenuShortcut } = useHubPreferences();
  const registered = useRegisteredShortcuts();
  const [recording, setRecording] = useState<Recording>({ state: "idle" });

  // formatChord asks the platform whether it is Apple, and the server has no answer — so a
  // chord rendered into server HTML ("Ctrl+Shift+K") would hydrate into a different string
  // ("⌘⇧K"). Hold the row until mount rather than gambling on which one is right.
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  // Read through a ref so the capture listener below can see the current registrations
  // without re-subscribing on every registry change (which would drop the recording).
  const registeredRef = useRef(registered);
  registeredRef.current = registered;

  const save = useCallback((keys: string) => {
    setSiteMenuShortcut(keys);
    setRecording({ state: "idle" });
  }, []);

  useEffect(() => {
    if (recording.state !== "listening") return;
    const onKeyDown = (event: KeyboardEvent) => {
      // CAPTURE phase, and everything is swallowed: while recording, a keystroke is data,
      // not a command. Without this the shortcut registry's own document listener would fire
      // whatever the user just pressed — including, for a user re-recording the site menu's
      // chord, the site menu itself, over the settings panel doing the recording.
      event.preventDefault();
      event.stopPropagation();
      if (event.key === "Escape") {
        setRecording({ state: "idle" });
        return;
      }
      const keys = chordFromEvent(event);
      // null = a bare modifier (the user is mid-chord), or a key that cannot be bound.
      // Keep listening rather than treating it as an answer.
      if (keys === null) return;
      const clash = registeredRef.current.find(
        (s) => s.label !== SITE_MENU_LABEL && sameChord(s.keys, keys)
      );
      if (clash) {
        setRecording({ state: "conflict", keys, with: clash.label });
        return;
      }
      setSiteMenuShortcut(keys);
      setRecording({ state: "idle" });
    };
    document.addEventListener("keydown", onKeyDown, true);
    return () => document.removeEventListener("keydown", onKeyDown, true);
  }, [recording.state]);

  const isDefault = siteMenuShortcut === DEFAULT_SITE_MENU_SHORTCUT;
  const isOff = siteMenuShortcut === "";

  return (
    <SettingsBody>
      <p className="text-sm text-apt-text-muted">
        Preferences for the hub&rsquo;s own chrome. Unlike the rest of your
        settings, these are saved to this browser rather than to your account
        &mdash; a keyboard shortcut belongs to the keyboard in front of you.
      </p>

      {/* A section in a Card, as Account and Profile draw theirs — see AppearancePanel. */}
      <DetailSection title="Keyboard shortcuts">
        <Card>
          <CardContent className="flex flex-col gap-3">
            <SettingRow
              label="Site menu shortcut"
              description="Opens and closes the site menu from anywhere, including while you are typing."
            >
              <div className="flex items-center gap-2">
                <span
                  className="min-w-24 rounded-md border border-apt-border px-3 py-1.5 text-center font-mono text-sm text-apt-text"
                  aria-live="polite"
                >
                  {recording.state === "listening"
                    ? "Press keys…"
                    : !mounted
                    ? " "
                    : isOff
                    ? "Off"
                    : formatChord(siteMenuShortcut)}
                </span>
                {recording.state === "listening" ? (
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => setRecording({ state: "idle" })}
                  >
                    Cancel
                  </Button>
                ) : (
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => setRecording({ state: "listening" })}
                  >
                    {isOff ? "Set" : "Change"}
                  </Button>
                )}
                <Button
                  variant="ghost"
                  size="sm"
                  disabled={isDefault}
                  onClick={() => save(DEFAULT_SITE_MENU_SHORTCUT)}
                >
                  Reset
                </Button>
                <Button
                  variant="ghost"
                  size="sm"
                  disabled={isOff}
                  onClick={() => save("")}
                >
                  Turn off
                </Button>
              </div>
            </SettingRow>

            {recording.state === "listening" && (
              <p className="text-xs text-apt-text-muted">
                Press the combination you want. Escape cancels; Escape and Tab
                cannot be bound.
              </p>
            )}

            {recording.state === "conflict" && (
              <p className="text-xs text-apt-red" role="alert">
                {formatChord(recording.keys)} is already{" "}
                <span className="font-medium">{recording.with}</span>. Pick
                another combination.
              </p>
            )}
          </CardContent>
        </Card>
      </DetailSection>
    </SettingsBody>
  );
}
