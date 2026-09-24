"use client";

import { useState, type ReactElement } from "react";
import { Wrench } from "lucide-react";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@agenticdevelopertoolkit/ui/components/dropdown-menu";
import { ManageFeaturesDialog } from "./ManageFeaturesDialog";

/**
 * The tool menu in a features list's title row: acts on the ecosystem whose features that list
 * shows, and on nothing else.
 *
 * It lives in the list's `titleActions` rather than beside the workspace switcher because what
 * it changes is THAT list. A button in page chrome had to say which ecosystem it meant, and
 * with a workspace's own features and a selected product's features on screen at once it could
 * not — the hub draws one of these on each list, each scoped to its own ecosystem.
 *
 * A menu rather than a bare button so the list has one place for the verbs that act on it.
 * It owns the dialog too, so a host drops in one element and passes one id.
 */
export function FeaturesToolMenu({
  ecosystemId,
  label = "Features tools",
}: {
  /** The ecosystem the list's features belong to — what "Manage features" edits. */
  ecosystemId: string;
  /** The trigger's accessible name. */
  label?: string;
}): ReactElement {
  const [managing, setManaging] = useState(false);
  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger
          render={<Button variant="ghost" size="icon-sm" aria-label={label} />}
        >
          <Wrench className="adh-button__icon" />
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem onClick={() => setManaging(true)}>Manage features…</DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
      {managing ? (
        <ManageFeaturesDialog ecosystemId={ecosystemId} onClose={() => setManaging(false)} />
      ) : null}
    </>
  );
}
