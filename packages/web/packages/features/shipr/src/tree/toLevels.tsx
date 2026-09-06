'use client';

import * as React from 'react';
import { Folder, GitBranch, TriangleAlert } from 'lucide-react';

import { Checkbox } from '@agenticdevelopertoolkit/ui/components/checkbox';
import { Spinner } from '@agenticdevelopertoolkit/ui/components/spinner';
import { StatusDot } from '@agenticdevelopertoolkit/ui/components/status-dot';
import type {
  TopicDetailItem,
  TopicLevel,
} from '@agenticdevelopertoolkit/ui/blocks';

import { isChecked, type Selection } from '../selection';
import type { DevRepo, Group, RepoItem } from '../types';
import type { LevelPlan, NodeRef } from './levels';

/**
 * `LevelPlan[]` → the rails the HTDV draws.
 *
 * The split is deliberate: `levels.ts` decides WHAT is in each rail and knows no React;
 * this decides what a row LOOKS like and knows no sorting. Every rule worth testing lives
 * on the other side of it, and this file is left with the two things that genuinely need a
 * component — the select-mode checkbox and the settled dot.
 *
 * The checkbox goes in the row's `icon` slot rather than in a variant of the rail: the HTDV
 * gives every row an icon and collapses rails to an icon strip, so a checkbox that lives
 * there is the one thing that stays visible in a narrow window — which is exactly when a
 * batch is easiest to lose track of.
 */

/** How a mirror is NAMED in the rail: the development repository people actually push to,
 *  short — the mirror's own `owner/name-deployment` is machinery, and putting it in a
 *  240px rail buries the one word that tells two rows apart.
 *
 *  `displayName` WINS WHERE IT IS SET, because it is the only name on the row anybody chose.
 *  It is set in Configure and it is set for exactly this: two repositories called `web` in
 *  two accounts are two identical rows here, and the slug they differ by is the half this
 *  function drops. */
export function repoLabel(item: {
  slug: string;
  devRepo?: DevRepo | null;
}): string {
  const chosen = item.devRepo?.displayName;
  if (chosen) return chosen;
  const slug = item.devRepo?.slug ?? item.slug;
  const short = slug.includes('/') ? slug.slice(slug.indexOf('/') + 1) : slug;
  return short;
}

function repoTone(item: RepoItem): 'success' | 'orange' | 'muted' {
  if (!item.state) return 'muted';
  return item.state.settled ? 'success' : 'orange';
}

function repoStatusLabel(item: RepoItem): string {
  if (!item.state) return 'never read';
  return item.state.settled ? 'settled' : 'behind';
}

export interface LevelsOptions {
  plans: readonly LevelPlan[];
  selection: Selection;
  /** A row was clicked at `levelIndex`. The console decides what that does to the path. */
  onSelect: (levelIndex: number, ref: NodeRef) => void;
  /** The rail's selection was cleared (Back, breadcrumb, re-click). */
  onClear: (levelIndex: number) => void;
  onToggleCheck: (ref: NodeRef) => void;
  /** The gear in a rail's header, built by the console for the folder THIS RAIL IS LISTING
   *  (null = the top level). A render prop rather than a component and its dozen callbacks,
   *  because every one of those callbacks would be passing straight through this file
   *  untouched — this module knows what a row looks like, not what a menu does. */
  railActions?: (groupId: string | null) => React.ReactNode;
  /** Mirrors a run is walking right now — the rail says so while the log scrolls. */
  runningRepoIds?: ReadonlySet<string>;
  /** A read is in flight for the whole tree. */
  busy?: boolean;
}

function checkboxIcon(
  ref: NodeRef,
  selection: Selection,
  onToggleCheck: (ref: NodeRef) => void,
  label: string,
): React.ReactNode {
  const checked = isChecked(selection.checked, ref);
  return (
    <Checkbox
      checked={checked}
      aria-label={`Select ${label}`}
      // The row underneath is a select — a tick must not also move the highlight and swap
      // the detail pane, which is the difference between "I marked this" and "I opened it".
      onClick={(e: React.MouseEvent) => e.stopPropagation()}
      onCheckedChange={() => onToggleCheck(ref)}
    />
  );
}

function groupItem(
  group: Group,
  opts: LevelsOptions,
): TopicDetailItem {
  const ref: NodeRef = { kind: 'group', id: group.id };
  return {
    id: `group:${group.id}`,
    label: group.name,
    // Folders disclose another rail; mirrors are the final choice. Declared, because the
    // HTDV holds the detail pane through a `"list"` click and swaps it on a `"detail"` one.
    leadsTo: 'list',
    icon: opts.selection.selecting
      ? checkboxIcon(ref, opts.selection, opts.onToggleCheck, group.name)
      : <Folder className="size-4" />,
  };
}

function repoItem(item: RepoItem, opts: LevelsOptions): TopicDetailItem {
  const ref: NodeRef = { kind: 'repo', id: item.id };
  const label = repoLabel(item);
  const running = opts.runningRepoIds?.has(item.id) ?? false;
  // CONFIGURED, BUT NOT MADE. Add writes the row and stops, so a repository can sit here
  // fully described and with nothing behind it on the forge — and every other mark on this
  // row would report that state as an ordinary one. The status dot says "never read", which
  // is true of a freshly registered repository too and is not the same problem; this is the
  // only one Provision fixes.
  const unconfigured = item.registeredAt === null;
  return {
    id: `repo:${item.id}`,
    label,
    // ONE NAME, NOT A NAME AND A QUALIFIER (Mike). The shard used to ride here as a second
    // gold token, so a row read as two things — `adhmarketingwebsites` and `group3` — and
    // the eye had to put them back together. The row now shows exactly the name that was
    // configured for it and nothing else; where two rows would otherwise read alike, the
    // answer is to name them, which is what `displayName` is for.
    leadsTo: 'detail',
    // The amber dot and its sr-only "needs attention" — the half of the mark that survives a
    // rail collapsed to icons, and the only half a screen reader gets.
    blocked: unconfigured,
    icon: opts.selection.selecting
      ? checkboxIcon(ref, opts.selection, opts.onToggleCheck, label)
      : unconfigured ? (
          <TriangleAlert className="size-4 text-apt-orange" aria-hidden />
        ) : (
          <GitBranch className="size-4" />
        ),
    // A SPINNER, NOT A BLUE DOT. The trailing slot is where this row says how it stands,
    // and while a run is inside it the honest answer is "ask again in a moment" — a dot in
    // a fourth colour is still a settled-looking mark, indistinguishable at a glance from
    // the green and orange ones it sits in a column with. Something that MOVES is the one
    // way a rail of forty rows tells the operator which one the runner is in without them
    // reading a single label.
    trailing: running ? (
      <Spinner className="size-3 text-apt-blue" aria-label={`${label} is running`} />
    ) : (
      <StatusDot tone={repoTone(item)} size={8} label={repoStatusLabel(item)} />
    ),
  };
}

/**
 * Build the rails.
 *
 * Row ids are PREFIXED with their kind (`group:` / `repo:`) because a rail holds both and
 * the two id spaces are independent — an unprefixed id could collide and select two rows.
 * The prefix is also what `onSelect` reads back to know which kind was clicked, so the
 * mapping is one string in one place rather than a lookup on every click.
 */
export function buildLevels(opts: LevelsOptions): TopicLevel[] {
  return opts.plans.map((plan, index) => {
    const items = [
      ...plan.groups.map((g) => groupItem(g, opts)),
      ...plan.repos.map((r) => repoItem(r, opts)),
    ];
    return {
      id: plan.id,
      title: plan.title,
      railLabel: `${plan.title} contents`,
      items,
      selectedId: plan.selected
        ? `${plan.selected.kind}:${plan.selected.id}`
        : null,
      leadsTo: 'list',
      itemNoun: 'repository',
      busy: index === 0 ? opts.busy : false,
      emptyLabel: 'Nothing filed here yet',
      onSelect: (id) => {
        const [kind, ...rest] = id.split(':');
        opts.onSelect(index, {
          kind: kind === 'group' ? 'group' : 'repo',
          id: rest.join(':'),
        });
      },
      onClear: () => opts.onClear(index),
      // The gear replaces the `+`. One control in a rail header made one of seven jobs
      // discoverable; a menu makes all seven, and it hangs off the rail so "here" is never
      // ambiguous — a folder added from this rail lands in the folder this rail is listing.
      titleActions: opts.railActions?.(plan.groupId),
      // The HTDV's own overview would hide our detail pane whenever the deepest rail has
      // rows in it — which is every rail with a folder in it, i.e. almost always. We draw
      // the pane ourselves off the SELECTION, so a folder can have a pane of its own rather
      // than a "pick something" hint standing where its repositories' output belongs.
      overview: false,
    };
  });
}
