"use client";

import { DisabledApiButton } from "@agenticdevelopertoolkit/ui/blocks";
import { useRecordAffordance, type RecordAffordanceProps } from "./record-affordance";

/**
 * The API slot every details header carries, just left of the "?" help — never empty.
 *
 * With `api` and a host renderer (the hub's RecordApiButton, via `RecordAffordanceContext`) it is
 * the host's live button for that endpoint. Otherwise — the view is not about an endpoint, the
 * host supplies nothing (a standalone site), or a path value the endpoint needs is not known yet —
 * it is {@link DisabledApiButton}, so the header keeps its shape and says why there is no API.
 */
export function HeaderApiButton({ api }: { api?: RecordAffordanceProps | null }) {
  const render = useRecordAffordance();
  if (api && render && Object.values(api.pathValues).every(Boolean)) {
    return <>{render(api)}</>;
  }
  return <DisabledApiButton />;
}
