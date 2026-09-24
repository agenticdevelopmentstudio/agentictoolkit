"use client";

import { useState, type ReactElement } from "react";
import { Puzzle } from "lucide-react";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
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
 * verb (Mike, 2026-09-24). It owns the dialog, so a host drops in one element and passes one id.
 */
export function ManageFeaturesButton({
  ecosystemId,
  label = "Manage features",
}: {
  /** The ecosystem the list's features belong to — what the dialog edits. */
  ecosystemId: string;
  /** The button's accessible name, and its tooltip. */
  label?: string;
}): ReactElement {
  const [managing, setManaging] = useState(false);
  return (
    <>
      <Button
        variant="ghost"
        size="icon-sm"
        aria-label={label}
        title={label}
        aria-haspopup="dialog"
        onClick={() => setManaging(true)}
      >
        <Puzzle className="adh-button__icon" />
      </Button>
      {managing ? (
        <ManageFeaturesDialog ecosystemId={ecosystemId} onClose={() => setManaging(false)} />
      ) : null}
    </>
  );
}
