"use client";

import { useState, type ReactElement } from "react";
import { Puzzle } from "lucide-react";
import { ListToolButton } from "@agenticdevelopertoolkit/ui/blocks";
import { ManageFeaturesDialog } from "./ManageFeaturesDialog";

/**
 * The button in a features list's title row that opens the feature picker for the ecosystem
 * whose features that list shows, and for nothing else.
 *
 * It lives in the list's `titleActions` rather than beside the workspace switcher because what
 * it changes is THAT list. A button in page chrome had to say which ecosystem it meant, and
 * with a workspace's own features and a selected product's features on screen at once it could
 * not — the hub draws one of these on each list, each scoped to its own ecosystem.
 *
 * One click, straight to the dialog, under a puzzle piece — the features you fit into an
 * ecosystem. It was a wrench opening a one-row menu, which only added a click to reach its sole
 * verb (Mike, 2026-09-24).
 *
 * Two modes. Left to itself it owns the dialog, so a host drops in one element and passes one id.
 * Given `onOpen` it only ASKS for the dialog, and the host renders `ManageFeaturesDialog` itself:
 * the mode for a host whose toolbar remounts — ResourceExplorer's rail is torn down and rebuilt
 * across breakpoints, and a dialog owned by a button inside it went down with it, taking the
 * user's pending ticks and an apply still in flight. EcosystemsFeature uses that mode.
 */
export function ManageFeaturesButton({
  ecosystemId,
  label = "Manage features",
  onOpen,
}: {
  /** The ecosystem the list's features belong to — what the dialog edits. */
  ecosystemId: string;
  /** The button's accessible name, and its tooltip. */
  label?: string;
  /** Controlled mode: called on click instead of opening a dialog of the button's own. The host
   *  then owns the dialog — and with it the open state, the pending ticks and the in-flight
   *  apply — somewhere that outlives this button. */
  onOpen?: () => void;
}): ReactElement {
  const [managing, setManaging] = useState(false);
  return (
    <>
      {/* Drawn like the list toolbar's own search control — muted gray, 15px, no button chrome —
          rather than a ghost Button, whose icon read brighter than the +/search beside it
          (Mike, 2026-09-24). The toolbar's own tool button, not a copy of its class string: the
          copy was the rail's look on the day it was taken, and drifts on the next token change. */}
      <ListToolButton label={label} aria-haspopup="dialog" onClick={() => (onOpen ? onOpen() : setManaging(true))}
      >
        <Puzzle size={15} aria-hidden />
      </ListToolButton>
      {managing && !onOpen ? (
        <ManageFeaturesDialog ecosystemId={ecosystemId} onClose={() => setManaging(false)} />
      ) : null}
    </>
  );
}
