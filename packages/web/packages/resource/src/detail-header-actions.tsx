"use client";

import type { ReactNode } from "react";

import { DetailHeaderPortal, DisabledHelpButton, useHasDetailHeader } from "@agenticdevelopertoolkit/ui/blocks";

import { HeaderApiButton } from "./header-api-button";
import { HelpPopover } from "./HelpPopover";
import type { RecordAffordanceProps } from "./record-affordance";

/**
 * A details view's API button and "?" help, sent to the DETAIL HEADER — the stack's one header row
 * over the detail — with help on the far right and the API button just left of it. Every shared
 * pane header ({@link ButtonBar}, {@link FeatureTitle}, and so {@link DetailsPane}) draws its API
 * and help through this, so no view carries its own copy inside the detail.
 *
 * The header is the nearest stack's (HTDV / HMDV own one each). Outside any stack (a bare page)
 * both render inline where this is declared, API then help — the order they keep in the header —
 * and a view with no help draws the disabled "?" there, so the pair is always whole. Inside one,
 * no help leaves the stack's slot to its own fallback.
 */
export function DetailHeaderActions({
  api,
  showApi = true,
  help,
  helpClassName,
}: {
  /** The endpoint the view is about; omit (or null) for a view with none — the button is then
   *  drawn disabled, saying so. */
  api?: RecordAffordanceProps | null;
  /** Claim the API slot. Off only where another header in the same view already names it. */
  showApi?: boolean;
  /** The view's help text. Omitted, the header keeps the host's own help (or a disabled "?"). */
  help?: ReactNode;
  /** Row metrics for the inline (no-host) help trigger. */
  helpClassName?: string;
}) {
  const hosted = useHasDetailHeader();
  return (
    <>
      {showApi && (
        <DetailHeaderPortal kind="api">
          <HeaderApiButton api={api} />
        </DetailHeaderPortal>
      )}
      {help ? (
        <DetailHeaderPortal kind="help">
          <HelpPopover triggerClassName={helpClassName}>{help}</HelpPopover>
        </DetailHeaderPortal>
      ) : (
        !hosted && <DisabledHelpButton triggerClassName={helpClassName} />
      )}
    </>
  );
}
