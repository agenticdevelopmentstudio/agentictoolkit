"use client";

// The rail-host contract: a HOST (e.g. the hub's one-rail workspace shell) may
// provide this registry; feature content publishes its rail levels/guards into it
// via StackLevels/useStackLevel/useRailExitGuard/ToolbarPortal below. With NO
// provider, publishers no-op and the feature (ResourceExplorer) renders its own
// HierarchicalTopicDetail (standalone mode — what the feature sites use). The host
// side (the provider that owns `mergedLevels` / the composite `exitGuard` / the
// toolbar slot state) lives in the consuming app; this package owns only the
// contract + the publisher hooks.

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useId,
  useLayoutEffect,
  useRef,
  type ReactNode,
} from "react";
import { createPortal } from "react-dom";
import type { TopicLevel, PaneExitGuard } from "@agenticdevelopertoolkit/ui/blocks";

// The package owns the unsaved-work guard contract by re-exporting the single
// authoritative type; feature editors import it from the rail-host module they
// already use.
export type { PaneExitGuard };

export interface RegisteredLevels {
  /** Position in the merged stack — set from the surrounding {@link LevelDepthContext}, so a
   *  publisher's levels land after every ancestor's (parents render first, so their depth is
   *  known when a descendant registers). */
  depth: number;
  levels: TopicLevel[];
}

/**
 * The host-side contract this package OWNS and a host (the hub's workspace shell) provides. Trimmed
 * to exactly the members the publisher hooks below read: level (un)registration, exit-guard
 * registration, and the editor toolbar slot. The host keeps its own internal state (the merged
 * stack, the composite guard) private. `toolbarSlot` is `null` with no host, and the publisher
 * that reads it ({@link ToolbarPortal}) degrades to rendering inline.
 */
export interface RailHostRegistry {
  /** Register (or replace) a publisher's rail levels at a depth. Keyed by a stable id so the
   *  publisher can update/unregister. */
  registerLevels: (id: string, entry: RegisteredLevels) => void;
  unregisterLevels: (id: string) => void;
  /** Register/replace (guard) or withdraw (null) one publisher's guard, keyed by a stable id. */
  registerExitGuard: (id: string, guard: PaneExitGuard | null) => void;
  /** Pop the stack's LEAF: clear the deepest level that currently has a selection, backing the
   *  user out to that list with nothing chosen. Ancestors are kept. A no-op when nothing is
   *  selected anywhere. Required, not optional — a host that could not pop would leave a pane
   *  that has discovered its item is gone with no way off the screen. */
  popStack: () => void;
  /** Report (true) or withdraw (false) that the item a pane is showing no longer exists on the
   *  server, keyed by that item's id so two panes reporting different items cannot cancel each
   *  other. The HOST owns the alert and the pop that follows it — one mount, so no feature can
   *  forget it and leave the user staring at a pane whose subject is gone. Required. */
  reportMissing: (id: string, missing: boolean) => void;
  /** Report (true) or withdraw (false) that a pane is READING, so the list whose detail area it
   *  occupies can spin in front of its title. `id` names the reporting pane and `levelId` the list
   *  that owns it — keyed by both, so two panes reading at once cannot cancel each other and a
   *  report can never light the wrong list. Required, for the same reason {@link reportMissing} is:
   *  a host that quietly dropped these would show no spinner anywhere, and nothing would say so. */
  reportBusy: (id: string, levelId: string, busy: boolean) => void;
  /** Publish (`title`) or withdraw (`null`) the text shown in the DETAIL pane's top strip,
   *  keyed by the publishing pane — the open document's name, the open record's summary. The
   *  HOST owns where it lands (HTDV's `detailTitle`), so a pane names what it is showing
   *  without reaching the stack that renders it.
   *
   *  OPTIONAL, unlike its neighbours: a host that does not implement it shows no title, which
   *  is exactly what those hosts do today, and every hand-built registry in the test suites
   *  keeps compiling. A string rather than a node — see {@link useDetailTitle}. */
  setDetailTitle?: (id: string, title: string | null) => void;
  /** The DOM node of the shell's full-width button-bar slot; feature editors portal their action
   *  bar here so it spans the top instead of sitting inside the detail. Null with no host.
   *  Deliberately not the home bar (`HomeBarPortal`/`HomeBarHost`, `./home-bar`): that strip
   *  belongs to the PAGE's own controls, this one to whichever EDITOR is open (its save/cancel
   *  bar) — the two can be on screen together, and sharing one strip would have each silently
   *  displace the other. */
  toolbarSlot: HTMLElement | null;
}

/** The context a host provides (via {@link RailHostContext.Provider}, owning `value`) to publish its
 *  registry; publishers read it through the hooks below. */
export const RailHostContext = createContext<RailHostRegistry | null>(null);

/** Read the host registry (views null-check it for "am I inside a rail host?" to decide
 *  publish-vs-render-own-rail). Null when no host is mounted. */
export function useRailHost(): RailHostRegistry | null {
  return useContext(RailHostContext);
}

/**
 * The depth of the NEXT level a publisher should register at. The host's children start at 0; each
 * {@link StackLevels} adds its level count, so a nested chain (feature ▸ group ▸ list ▸ editor
 * topics) registers in tree order and the merged stack reads outermost-first. Render-time context
 * (not effects) so a descendant reads its ancestors' depth during its own render.
 */
const LevelDepthContext = createContext(0);

/**
 * The id of the level whose DETAIL AREA the surrounding content occupies — i.e. the list a
 * descendant's read belongs to, which is what {@link useReportBusy} reports against.
 *
 * An id and not a depth. A depth looks like it would work and does not: {@link StackLevels} wraps
 * its children and so advances the context, while {@link useStackLevel} is a hook with nothing to
 * wrap and leaves it alone — so "one below me" means a different list depending on which mechanism
 * the ancestor happened to use, and a reader cannot tell which it is under. The id is published by
 * whoever publishes the level, so the two can never disagree.
 */
const BusyTargetContext = createContext<string | null>(null);

/** One object's PLAIN fields — string, number, boolean — as an unambiguous string. `JSON.stringify`
 *  and not a `k=v` join so a label containing the separator can't forge another field's value.
 *  An absent or null field is simply missing from the output, which is itself a distinct string, so
 *  a selection clearing to `null` still reads as a change. */
function plainFields(o: object): string {
  const plain: Record<string, string | number | boolean> = {};
  for (const [k, v] of Object.entries(o)) {
    if (typeof v === "string" || typeof v === "number" || typeof v === "boolean") plain[k] = v;
    // A Set IS a plain value — it is a bag of scalars, allocated once per change rather than once
    // per render, so keying on its CONTENTS costs nothing and is nothing like keying on a node.
    // `checkedIds` is the one in use and it is why this arm exists: a tick changed the set and no
    // plain field beside it moved, so the level stayed registered as it was — the rail drew the
    // row unticked, and, far worse, kept the previous `onToggleChecked`, whose closure held the
    // set as it was BEFORE the first tick. Every tick after the first started from empty.
    // JSON again, and for the same reason the outer call is JSON: a `join(",")` is the `k=v`
    // forgery this function exists to avoid, one level down. `{"a,b"}` and `{"a","b"}` join to
    // the identical string, so a checked id containing a comma made two different selections
    // read as one and the tick that moved between them changed nothing.
    else if (v instanceof Set)
      plain[k] = JSON.stringify(Array.from(v as Set<unknown>).map(String).sort());
  }
  return JSON.stringify(plain);
}

/** Serialise a level array's identity so the publish effect re-runs on any change the merged stack
 *  renders — a live rename of a level's title (a persona's), a row's label or sublabel (an
 *  integration flipping from its auth method to "Configured"), a list resolving from "Loading…" to
 *  empty, a read starting — none of which change `items.length` and all of which would otherwise
 *  sit stale in the rail. Not every render's new array/closure identity, which is the churn this
 *  key exists to prevent.
 *
 *  EVERY plain field, rather than a hand-kept list of the ones known to change. The list was
 *  hand-kept and it was wrong repeatedly: `emptyLabel`, `overview` and `busy` were each appended
 *  after one of their changes was found stuck on screen, and `blocked`, `preview`/`previewLines`
 *  and `newActive` were still missing — a row's amber "needs attention" dot
 *  (`PersonaEditor`, `NotebookPane`), a note's body preview, and the gold in-progress `+` all
 *  change while the level is mounted, and all of them left the rail showing the previous value.
 *  Nothing distinguished the fields that happened to be named; the enumeration was the defect.
 *
 *  What plainness leaves out is a real limit, not an oversight: `titleActions`, `railSlot`,
 *  `headerSlot` and a row's `icon`/`trailing` are React nodes, freshly allocated on most renders,
 *  so keying on them would re-register every level on every render — and their handlers are
 *  closures, which is worse. A level whose ONLY change is inside such a node keeps the previously
 *  registered one until some plain field moves. Give such a node a plain companion field (the way
 *  `busy` carries the spinner) rather than expecting the node itself to be noticed. */
function levelsKey(levels: TopicLevel[]): string {
  return levels
    .map((l) => `${plainFields(l)}[${l.items.map(plainFields).join(",")}]`)
    .join("|");
}

/**
 * Publish a chain link's rail levels into the merged stack AND advance the depth for its children,
 * so a deeper view (a group's member, a master/detail list, an editor's topics) lands AFTER it.
 * Renders its `children` (the next-deeper content / the leaf) — the levels themselves are rendered
 * by the host's one HierarchicalTopicDetail, not inline here. No-op outside a host (the view still
 * renders standalone), so callers keep their own-HTD fallback for that case.
 */
export function StackLevels({ levels, children }: { levels: TopicLevel[]; children: ReactNode }) {
  const depth = useContext(LevelDepthContext);
  const ctx = useContext(RailHostContext);
  const outerBusyTarget = useContext(BusyTargetContext);
  const id = useId();
  const register = ctx?.registerLevels;
  const unregister = ctx?.unregisterLevels;
  // Re-runs whenever `key` (id + selection + row count per level) changes; the effect closure holds
  // the latest `levels` at that point, so no ref is needed to register fresh values.
  const key = levelsKey(levels);
  useLayoutEffect(() => {
    if (!register || !unregister) return;
    register(id, { depth, levels });
    return () => unregister(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [register, unregister, id, depth, key]);
  // The children render in the DEEPEST of these levels' detail area, so that is the list a read
  // among them belongs to. An empty publish keeps whatever the ancestor named — a link that adds
  // no level of its own does not take ownership of its descendants' reads.
  const busyTarget = levels.length > 0 ? levels[levels.length - 1]!.id : outerBusyTarget;
  return (
    <LevelDepthContext.Provider value={depth + levels.length}>
      <BusyTargetContext.Provider value={busyTarget}>{children}</BusyTargetContext.Provider>
    </LevelDepthContext.Provider>
  );
}

/**
 * Publish ONE leaf-most rail level (a master/detail list, whose detail — the editor — publishes
 * nothing deeper) at the current depth. A hook, not a wrapper, because there is no deeper child to
 * advance the depth for. Pass null to clear (single-record topics). No-op outside a host.
 *
 * Being a hook has one consequence a caller has to know: it names no {@link BusyTargetContext} for
 * this level, because it has no children to wrap. So a detail area that contains a
 * {@link useReportBusy} caller must be published with {@link StackLevels} instead — a hook cannot
 * put itself between the level and the pane reporting under it, and the report would otherwise walk
 * past this level to the nearest `StackLevels` ANCESTOR and spin the wrong list, which is worse
 * than no spinner because the user reads it as that list reloading.
 */
export function useStackLevel(level: TopicLevel | null): void {
  const depth = useContext(LevelDepthContext);
  const ctx = useContext(RailHostContext);
  const register = ctx?.registerLevels;
  const unregister = ctx?.unregisterLevels;
  const id = useId();
  const key = level ? `${depth}:${levelsKey([level])}` : "";
  useLayoutEffect(() => {
    if (!register || !unregister) return;
    if (!level) {
      unregister(id);
      return;
    }
    register(id, { depth, levels: [level] });
    return () => unregister(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [register, unregister, id, key]);
}

/**
 * A feature's leaf editor calls this to publish (or clear) its unsaved-work guard so the host can
 * prompt Discard/Stay before a Back / breadcrumb-up / re-click clears the level. Co-mountable:
 * each caller registers under its own stable id and only ever withdraws ITSELF, so a pane's form
 * guard and a topic's data-editor guard coexist (the host consults the composite). Cleared on
 * unmount. No-op outside a host.
 */
export function useRailExitGuard(guard: PaneExitGuard | null): void {
  const ctx = useContext(RailHostContext);
  const registerExitGuard = ctx?.registerExitGuard;
  const id = useId();
  // The guard object identity changes every render (its `isDirty`/`save` close over fresh state),
  // so publishing it directly would loop. Keep the live guard in a ref and publish ONE STABLE proxy
  // that reads the ref, toggled only when the guard flips between present and absent.
  const ref = useRef<PaneExitGuard | null>(guard);
  ref.current = guard;
  const present = guard !== null;
  useEffect(() => {
    if (!registerExitGuard) return;
    registerExitGuard(
      id,
      present
        ? {
            // Reads the ref null-safely: `present` is a snapshot from the render that scheduled
            // this effect, so a guard withdrawn between render and invocation must not throw.
            isDirty: () => !!ref.current?.isDirty(),
          }
        : null,
    );
    return () => registerExitGuard(id, null);
  }, [registerExitGuard, id, present]);
}

/**
 * The leaf's own way off the stack. Returns a stable function that pops the deepest SELECTED level
 * — the same move Back makes — so a pane that discovers its item no longer exists can remove
 * itself without knowing where in the stack it sits.
 *
 * It takes NO argument on purpose. Levels do not share an identity vocabulary (some are keyed by
 * uuid, some by slug), so a pop that named an id would silently do nothing for whichever caller
 * guessed the other one, leaving the user stuck on a dead pane. Position is unambiguous.
 *
 * Outside a host it is a no-op, like every other publisher here.
 */
export function useStackPop(): () => void {
  const ctx = useContext(RailHostContext);
  const pop = ctx?.popStack;
  return useCallback(() => pop?.(), [pop]);
}

/**
 * Report that the item this pane is showing is gone from the server, so the host can tell the user
 * and back them out. `id` names the item; `missing` reports (true) or withdraws (false). The
 * report is withdrawn automatically when `missing` goes false and on unmount, so a pane that
 * navigates away never leaves a stale alert armed behind it.
 *
 * The pane does NOT show the alert itself and does NOT pop — the host does both, in that order,
 * when the user acknowledges. Outside a host this is a no-op.
 */
export function useReportMissing(id: string | null, missing: boolean): void {
  const ctx = useContext(RailHostContext);
  const report = ctx?.reportMissing;
  useEffect(() => {
    if (!report || id == null || !missing) return;
    report(id, true);
    return () => report(id, false);
  }, [report, id, missing]);
}

/**
 * Report that this pane is READING, so the topic list it sits under spins in front of its title.
 *
 * For the pane that publishes NO level of its own — a settings body, a member of a group — whose
 * read is otherwise invisible: it has no list to put a spinner on, and the list that does have one
 * is published a component above, out of its reach. `busy` is the pane's own in-flight flag
 * (`isFetching`, not `isPending` — see {@link TopicLevel.busy}); the report is withdrawn when it
 * goes false and on unmount, so a pane that navigates away never leaves a list spinning.
 *
 * It names no list, exactly as {@link useStackPop} names no level: the enclosing
 * {@link StackLevels} publishes which one, so a pane cannot report against a list that isn't
 * actually showing it. Outside a host, or with no level above it at all, it is a no-op.
 *
 * Do NOT call this from a pane that publishes its own level — set `busy` on that level instead, or
 * the same read lights two spinners and asks the user to tell them apart.
 *
 * DO call it from a pane that already draws its own first-load skeleton, and pass `isFetching`
 * anyway. A skeleton answers "is there anything to show yet", which is false only on the FIRST
 * visit; the spinner answers "am I still reading", which is what the second visit needs — that
 * visit paints instantly from cache and then revalidates in complete silence without this. The two
 * are not the duplicate the paragraph above rules out: that one is two list spinners competing for
 * the same read, this one is a body saying it is empty while a list says it is reading. Pass the OR
 * of every read the pane holds, so the spinner outlasts the first one to land.
 */
export function useReportBusy(busy: boolean): void {
  const ctx = useContext(RailHostContext);
  const report = ctx?.reportBusy;
  const levelId = useContext(BusyTargetContext);
  const id = useId();
  useEffect(() => {
    if (!report || levelId == null || !busy) return;
    report(id, levelId, true);
    return () => report(id, levelId, false);
  }, [report, id, levelId, busy]);
}

/**
 * Name what THIS pane is showing, for the detail header. Pass `null` when nothing is open;
 * the title is withdrawn on unmount too, so a closed pane never leaves its name over an
 * empty one.
 *
 * A `string`, deliberately: a `ReactNode` is a new object on every render, and an effect
 * that depends on one would re-publish forever. A host that does not implement
 * {@link RailHostRegistry.setDetailTitle} — and a pane with no host at all — makes this a
 * no-op.
 */
export function useDetailTitle(title: string | null): void {
  const host = useRailHost();
  const setDetailTitle = host?.setDetailTitle;
  const id = useId();
  // TWO effects, and the split is the point. The host's tie-break is "the LAST to register
  // wins" (`host-stack.tsx`), read off the title Map's INSERTION order — and a Map preserves
  // an existing key's position on `set` but re-appends it after a `delete`. One effect with
  // `title` in its deps would run its own cleanup on every title CHANGE, so re-titling a
  // background pane would delete-and-re-append its key and steal the header from the pane
  // actually on screen. So publishing tracks `title`, and the withdrawal is its own effect
  // that runs only on unmount or an id change — the two events that really mean "this
  // publisher is gone".
  useEffect(() => {
    if (!setDetailTitle) return;
    setDetailTitle(id, title);
  }, [setDetailTitle, id, title]);
  useEffect(() => {
    if (!setDetailTitle) return;
    return () => setDetailTitle(id, null);
  }, [setDetailTitle, id]);
}

/** The DOM node a feature editor should portal its action bar into, or null when there is no
 *  enclosing host (then the editor renders the bar inline, as before). */
export function useToolbarPortal(): HTMLElement | null {
  return useContext(RailHostContext)?.toolbarSlot ?? null;
}

/** Renders its children into the host's full-width button-bar slot (a portal) when inside a
 *  rail host; otherwise renders them inline. */
export function ToolbarPortal({ children }: { children: ReactNode }) {
  const slot = useToolbarPortal();
  return slot ? createPortal(children, slot) : <>{children}</>;
}
