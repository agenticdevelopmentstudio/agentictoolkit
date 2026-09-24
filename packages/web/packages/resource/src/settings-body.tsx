import type { ReactNode } from "react";

import { cn } from "@agenticdevelopertoolkit/ui/lib/utils";

/**
 * The scrolling body every User Settings section renders under its `FeatureTitle` — one padding,
 * one gap between sections, one left edge.
 *
 * Here because each panel used to spell its own: `px-6 py-6` in most, `p-4 sm:p-6` in two,
 * `max-w-2xl`, `max-w-3xl` and `max-w-5xl` in different ones, and `mx-auto` in Notifications and
 * Security — which CENTRED those two on a wide overlay while every sibling hugged the left edge.
 * Fourteen sections sitting in one rail read as fourteen different sites. A body that never
 * centres is what keeps them one.
 *
 * `width` is the one real difference, and it is named rather than left to a class per panel:
 *   • `"form"` caps the column so a label and its input stay within reach of each other — a text
 *     box stretched across a 1400px overlay is a line nobody can read to the end of.
 *   • `"full"` lets an `EditableList` take the pane's width, the same as admin's tables do — a
 *     table capped at a form's width truncates the very columns it was resized to show.
 */
export function SettingsBody({
  width = "form",
  children,
}: {
  width?: "form" | "full";
  children: ReactNode;
}) {
  return (
    <div className="min-h-0 flex-1 overflow-y-auto px-6 py-6">
      <div className={cn("flex min-w-0 flex-col gap-8", width === "form" && "max-w-3xl")}>
        {children}
      </div>
    </div>
  );
}
