"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactElement,
  type ReactNode,
} from "react";
import { HierarchicalDetailView } from "@agenticdevelopertoolkit/ui/blocks";
import { UnsavedChangesGuard } from "@agenticdevelopertoolkit/ui/components/unsaved-changes-guard";
import {
  RailHostContext,
  useRailHost,
  type PaneExitGuard,
  type RailHostRegistry,
  type RegisteredLevels,
} from "./rail-host";
import {
  useHostBusyReports,
  useHostMissingAlert,
  useHostPopStack,
  useHostDetailTitle,
} from "./host-stack";

/**
 * The standalone rail host: when a feature renders OUTSIDE a host (a feature site's /home),
 * this provides its OWN {@link RailHostContext} so the topic panes' publishers work exactly as
 * they do inside the hub shell — the master/detail lists register as deeper rail levels, and the
 * leaf editor's unsaved-work guard flows into the one HTD's exit gate (so Back / breadcrumb-up /
 * re-click prompts Discard/Stay instead of silently discarding). Mirrors the hub's
 * WorkspaceChromeProvider semantics (local registry + composite guard + depth-merged stack + the
 * breadcrumb bar), trimmed to the standalone case: no shell workspace/feature levels above the
 * feature's own. It owns the rails and the exit gate only — a list's own controls (search,
 * filters, create) ride that list's rail toolbar (`TopicLevel.onNew` / `search` / `titleActions`).
 * Extracted from ResourceExplorer (which always self-hosted this way) so the
 * publisher-only feature entries — research/dashboards/knowledgebases/personas — get the same
 * standalone behavior through {@link RailHostBoundary}.
 *
 * MOUNT THIS DIRECTLY ONLY INSIDE A MODAL. Every other caller wants the boundary, which
 * self-hosts only when there is no host above; an unconditional wrap under the hub shell
 * shadows the workspace registry and renders a second rail inside the frontier pane. A
 * dialog is the exception in both directions: it renders inside the page, so the boundary
 * would find the shell's host and pass through — publishing the dialog's levels into the
 * page's rail, where they draw behind the dialog and survive its close. A dialog's stack is
 * its own, always, so it takes this component and not the boundary.
 */
export function StandaloneRailHost({
  children,
  onDirtyChange,
  onNavigate,
}: {
  children: ReactNode;
  /** Reports this host's dirtiness — `guards.size > 0` — to a caller that has no other way to
   *  see into its private `guards` map, e.g. an app-level left-rail section switch (this host
   *  owns the only guard that switch cannot otherwise observe). Called on every flip, and once
   *  more with `false` on unmount, so an unmounting host never leaves the caller believing it is
   *  still dirty. Optional: omit it and the host behaves exactly as before. */
  onDirtyChange?: (dirty: boolean) => void;
  /** Forwarded to the {@link UnsavedChangesGuard} this host mounts, so a Discard that follows an
   *  intercepted in-app link click routes through the caller's own router instead of the guard's
   *  default `window.location.assign` fallback — see its doc. This package still owns no router
   *  instance and still never calls `next/navigation`'s `useRouter` itself: the prop lets a caller
   *  that has one (the hub shell, or a feature site's own layout) supply it, the same way
   *  `onDirtyChange` is supplied rather than read from context. Optional: omit it and Discard
   *  falls back to a full document load, exactly as before this prop existed. */
  onNavigate?: (href: string) => void;
}): ReactElement {
  const [registry, setRegistry] = useState<ReadonlyMap<string, RegisteredLevels>>(new Map());
  const [guards, setGuards] = useState<ReadonlyMap<string, PaneExitGuard>>(new Map());

  const registerLevels = useCallback((id: string, entry: RegisteredLevels) => {
    setRegistry((prev) => {
      const next = new Map(prev);
      next.set(id, entry);
      return next;
    });
  }, []);
  const unregisterLevels = useCallback((id: string) => {
    setRegistry((prev) => {
      if (!prev.has(id)) return prev;
      const next = new Map(prev);
      next.delete(id);
      return next;
    });
  }, []);
  // Register/replace or (guard === null) withdraw one publisher's guard — the withdraw path is how a
  // guard clears when its editor unmounts (useRailExitGuard's cleanup), mirroring the hub host.
  const registerExitGuard = useCallback((id: string, guard: PaneExitGuard | null) => {
    setGuards((prev) => {
      if (guard === null && !prev.has(id)) return prev;
      const next = new Map(prev);
      if (guard === null) next.delete(id);
      else next.set(id, guard);
      return next;
    });
  }, []);

  // The one guard the HTD consults: dirty when ANY publisher is dirty.
  const exitGuard = useMemo<PaneExitGuard | null>(() => {
    if (guards.size === 0) return null;
    const all = [...guards.values()];
    return {
      isDirty: () => all.some((g) => g.isDirty()),
    };
  }, [guards]);

  // Report dirtiness upward, on every flip of `guards.size > 0`. `onDirtyChange` is read through a
  // ref (not a dep) — same idiom useRailExitGuard uses for its guard — so a caller passing a fresh
  // closure each render (the common case: `onDirtyChange={setPaneDirty}` is stable, but an inline
  // arrow wouldn't be) never re-fires this on an unrelated render.
  const onDirtyChangeRef = useRef(onDirtyChange);
  onDirtyChangeRef.current = onDirtyChange;
  const dirty = guards.size > 0;
  useEffect(() => {
    onDirtyChangeRef.current?.(dirty);
  }, [dirty]);
  // Cleanup only, on unmount: a host that unmounts while still dirty (e.g. its enclosing pane was
  // itself swapped out from further up) must not leave the caller believing it still is — the
  // effect above cannot cover this, since it never re-runs once `dirty` stops changing.
  useEffect(() => {
    return () => onDirtyChangeRef.current?.(false);
  }, []);

  const registered = useMemo(
    () => [...registry.values()].sort((a, b) => a.depth - b.depth).flatMap((e) => e.levels),
    [registry],
  );

  // The host-side stack duties, shared with the hub's WorkspaceChromeProvider so a feature site's
  // /home and the same feature inside the hub shell cannot drift. See `host-stack.tsx`.
  // The busy fold comes FIRST: everything below renders `mergedLevels`, and a stack that had the
  // reports folded in only at the view would leave the breadcrumb and the frontier reading a
  // different array than the rails.
  const { reportBusy, levels: mergedLevels } = useHostBusyReports(registered);
  const popStack = useHostPopStack(mergedLevels);
  const { reportMissing, missingAlert } = useHostMissingAlert(popStack, guards.size > 0);
  const { setDetailTitle, detailTitle } = useHostDetailTitle();

  // The editor toolbar slot: a real DOM node this host mounts in the HTD's top strip, so a pane's
  // action bar spans the full width above the rails instead of sitting inside its own detail. It
  // is STATE, not a ref — a ref's `.current` lands during commit without re-rendering, so the
  // context would publish `null` on the mount that matters and the pane's `ToolbarPortal` would
  // fall back to rendering inline forever. Panes that portal nothing are unaffected: the strip
  // collapses while the slot is empty (see `data-adh-toolbar-slot`).
  const [toolbarSlot, setToolbarSlot] = useState<HTMLDivElement | null>(null);

  const host = useMemo<RailHostRegistry>(
    () => ({
      registerLevels,
      unregisterLevels,
      registerExitGuard,
      popStack,
      reportMissing,
      reportBusy,
      setDetailTitle,
      toolbarSlot,
    }),
    [
      registerLevels,
      unregisterLevels,
      registerExitGuard,
      popStack,
      reportMissing,
      reportBusy,
      setDetailTitle,
      toolbarSlot,
    ],
  );

  return (
    <RailHostContext.Provider value={host}>
      {missingAlert}
      {/* Browser-level exits (reload, tab close, in-app link click, Back/Forward, and any chrome
          that awaits confirmNavigation) for every pane this host carries, from ONE mount — the same
          line the hub's WorkspaceChromeProvider carries, so a feature site's /home is guarded
          exactly as the same pane is inside the hub shell. `guards` is non-empty exactly when some
          pane is dirty (publishers register on dirty, not on "editor open"), which is what makes
          this a render value. IN-PANE exits (row switch, breadcrumb, re-click) are guarded
          separately by the HTD below via `exitGuard`.
          `onNavigate` is forwarded straight through, unmodified, to whatever this host's caller
          supplied — see the prop's doc above. */}
      <UnsavedChangesGuard when={guards.size > 0} onNavigate={onNavigate} />
      {/* `rootLabel` is the leading crumb, and passing it is what makes the breadcrumb bar EXIST
          here: the bar draws only when the trail is non-empty, and a standalone host's trail is
          empty until something is selected — so without a root the bar would appear on click and
          vanish on Back, which is worse than never having one. The first published level's own
          title is that root, which is exactly what the hub's WorkspaceShell does (its `rootLabel`
          and its level 0's title are the same `workspaceListLabel(active)` string): it is the one
          label this package already holds — the feature's landing, e.g. "All projects" — and
          clicking it runs `levels[0].onClear()`, which is the feature's own return-to-landing. The
          `|| undefined` is for a feature that publishes an empty title (ResourceExplorer defaults
          `landing?.title ?? ""`): `rootLabel=""` is still a crumb, and would draw a bar holding a
          blank chevron-less nothing. `showBreadcrumb` is left at its default `true`. */}
      <HierarchicalDetailView
        levels={mergedLevels}
        rootLabel={mergedLevels[0]?.title || undefined}
        detailTitle={detailTitle}
        exitGuard={exitGuard}
        toolbar={
          <div
            data-adh-toolbar-slot=""
            ref={setToolbarSlot}
            className="flex w-full min-w-0 items-center gap-2"
          />
        }
      >
        {children}
      </HierarchicalDetailView>
    </RailHostContext.Provider>
  );
}

/**
 * Host-or-standalone boundary: inside an existing rail host (the hub's workspace chrome) it is a
 * pure pass-through, so the feature's levels merge into the shell's one HTD; without one it
 * becomes a {@link StandaloneRailHost}. Every feature ENTRY (the component a site mounts at
 * /home) wraps its published content in this, so the same entry works under the hub shell and on
 * a bare feature site — an UNCONDITIONAL StandaloneRailHost would shadow the hub's registry and
 * render a second nested rail inside the frontier pane, which is why the conditional exists.
 */
export function RailHostBoundary({
  children,
  onDirtyChange,
  onNavigate,
}: {
  children: ReactNode;
  /** Forwarded to the {@link StandaloneRailHost} this creates when there is no host above —
   *  see its doc. Inert in the pass-through case (a host already exists): that host owns its
   *  own dirty-gating, so nothing here would be safe to report to a caller-supplied callback
   *  without double-prompting whatever already gates the ancestor host's exits. */
  onDirtyChange?: (dirty: boolean) => void;
  /** Forwarded to the {@link StandaloneRailHost} this creates when there is no host above — see
   *  its doc. Inert in the pass-through case (a host already exists): that host's own guard mount
   *  already owns whichever `onNavigate` it was given, so there is nothing here to forward it to. */
  onNavigate?: (href: string) => void;
}): ReactElement {
  const host = useRailHost();
  return host ? (
    <>{children}</>
  ) : (
    <StandaloneRailHost onDirtyChange={onDirtyChange} onNavigate={onNavigate}>
      {children}
    </StandaloneRailHost>
  );
}
