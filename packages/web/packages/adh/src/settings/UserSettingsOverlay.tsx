"use client";

import { useState } from "react";

import {
  Dialog,
  DialogContent,
  DialogTitle,
} from "@agenticdevelopertoolkit/ui/components/dialog";
import { UnsavedChangesAlert } from "@agenticdevelopertoolkit/ui/components/unsaved-changes-alert";
import { useMediaQuery } from "@agenticdevelopertoolkit/ui/hooks/useMediaQuery";
import { SettingsLayout } from "@agentic-toolkit/account";
import { SettingsDirtyProvider, useSettingsDirty } from "@agentic-toolkit/resource";
// The react-query runtime every panel below fetches through, mounted HERE rather than in
// settings-overlay.tsx for two independent reasons. (1) Bundle: that module is the
// always-loaded barrel, so a static `@agentic-toolkit/data/query` import there puts
// react-query in the eager graph of every page of ~45 sites, for a dialog a signed-out
// visitor cannot open — the same cost the lazy() split exists to avoid. This entry is the
// lazy chunk, so the import is paid on first open only. (2) Correctness: there it was a
// SIBLING of the app's children, not an ancestor, so ToolkitQueryProvider's
// already-mounted check (data/src/query/index.tsx) could never see a host's provider and
// every site that mounts one inside its own tree got a second client — the exact
// two-caches-one-subtree trap that check was added to close. Wrapping the overlay makes it
// a real ancestor of the panels and a real descendant of the host's shell provider.
import { ToolkitQueryProvider } from "@agentic-toolkit/data/query";
import { buildSettingsTopics } from "./registry";
// Package path, not "./topics": this is the same specifier a Server Component outside this
// package must use to reach these exports without going through the "use client"-tainted
// settings/index barrel — using it here too keeps one documented route, in and out of the
// package. See topics.ts's and settings/index.ts's own header comments.
import { DEFAULT_SETTINGS_TOPIC } from "@agentic-toolkit/adh/settings/topics";

/**
 * The User Settings master-detail (Account / Subscription / Profile) shown as a
 * centered overlay over whatever route is underneath — opened by the header's
 * settings gear. Identical UI to hub's /settings, but section switching is in-place
 * (controlled state, not routing) so the underlying route is preserved.
 */
export function UserSettingsOverlay({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  return (
    <ToolkitQueryProvider>
      <SettingsDirtyProvider>
        <UserSettingsDialog open={open} onOpenChange={onOpenChange} />
      </SettingsDirtyProvider>
    </ToolkitQueryProvider>
  );
}

function UserSettingsDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const [topic, setTopic] = useState<string>(DEFAULT_SETTINGS_TOPIC);
  // Every open starts on the default section, as it did when the whole subtree remounted per
  // open. Adjusted during render (React's documented "reset state when a prop changes"
  // pattern) rather than in an effect: an effect runs after paint, so the reopen would show
  // one frame of the previously-viewed section, and resetting on CLOSE instead would swap the
  // visible panel out from under the dialog's exit transition.
  const [openedWith, setOpenedWith] = useState(open);
  if (open !== openedWith) {
    setOpenedWith(open);
    if (open) setTopic(DEFAULT_SETTINGS_TOPIC);
  }
  const topics = buildSettingsTopics();
  const { isAnyDirty } = useSettingsDirty();

  // A close or a tab switch the user must confirm because some panel is dirty. `null` = nothing
  // pending. Held as a thunk so both exits share one alert.
  const [pendingExit, setPendingExit] = useState<(() => void) | null>(null);

  function attemptExit(action: () => void) {
    if (isAnyDirty()) setPendingExit(() => action);
    else action();
  }

  // Escape / backdrop / the close button all route through here.
  function handleOpenChange(next: boolean) {
    if (next) {
      onOpenChange(true);
      return;
    }
    attemptExit(() => onOpenChange(false));
  }

  // A phone gets the whole screen. The desktop footprint's 1rem margin and `vh` height left the
  // bottom of the dialog — and the Save bar in it — under iOS Safari's toolbar, since `vh` there is
  // measured with the toolbar hidden; `dvh` is the height actually visible.
  const compact = useMediaQuery("(max-width: 639px)");

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      {/* Sizing via inline style (not Tailwind) so it's immune to utility
          conflicts: centered by the shared dialog's fixed/translate classes.
          Fixed to a large footprint (capped to the viewport on small screens) so
          the dialog stays the same size across sections — switching panels never
          resizes it; each panel scrolls internally instead. */}
      <DialogContent
        className="flex flex-col gap-0 overflow-hidden p-0"
        style={
          compact
            ? {
                width: "100vw",
                maxWidth: "100vw",
                height: "100dvh",
                maxHeight: "100dvh",
                borderRadius: 0,
                borderWidth: 0,
                paddingTop: "env(safe-area-inset-top)",
                paddingBottom: "env(safe-area-inset-bottom)",
              }
            : {
                width: "min(72rem, calc(100vw - 2rem))",
                maxWidth: "min(72rem, calc(100vw - 2rem))",
                // Tall enough to show all subscription plans without scrolling on a
                // typical desktop; still caps to the viewport on shorter screens.
                height: "min(56rem, calc(100dvh - 2rem))",
                maxHeight: "calc(100dvh - 2rem)",
              }
        }
      >
        <DialogTitle className="shrink-0 border-b border-apt-border px-6 py-3 font-mono text-sm tracking-wide text-apt-gold">
          User Settings
        </DialogTitle>
        <div className="flex min-h-0 flex-1 flex-col">
          <SettingsLayout
            topics={topics}
            activeId={topic}
            // The active row is still a live <button> in SettingsLayout, so guard against
            // gating a navigation that would not move: without this, clicking the section you
            // are already on with edits pending raises the unsaved-changes alert, and
            // choosing Discard throws the edits away to arrive exactly where you were.
            onNavigate={(t) => {
              if (t.id === topic) return;
              attemptExit(() => setTopic(t.id));
            }}
          />
        </div>
        <UnsavedChangesAlert
          open={pendingExit !== null}
          onDiscard={() => {
            pendingExit?.();
            setPendingExit(null);
          }}
          onStay={() => setPendingExit(null)}
        />
      </DialogContent>
    </Dialog>
  );
}

// This entry is the registry's ONE public route, and it is deliberately the lazy one.
// registry.tsx — and the ~3,000 LOC of panels it assembles — is reachable only from here:
// tsup bundles an entry's whole reachable graph regardless of what a downstream consumer
// ends up using, so an `export … from "./registry"` in settings/index.ts would bake every
// panel into the barrel every site's SettingsOverlayProvider always loads.
//
// settings/index.ts used to re-export these names FROM here, which sounds free and is not:
// a static re-export in an always-loaded barrel re-anchors this whole chunk in the eager
// graph of every consuming build, undoing the split (measured — see the comment in
// settings/index.ts). So the barrel no longer names them, and a host that renders the
// settings rail as a routed page rather than as the overlay — hub's /settings, the only one —
// imports "@agentic-toolkit/adh/settings/UserSettingsOverlay" itself. That host pays for the
// panel graph on the route whose entire purpose is the panel graph; nobody else pays at all.
export { buildSettingsTopics, SettingsTab } from "./registry";
export type { Topic } from "@agentic-toolkit/account";
