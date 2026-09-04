'use client';

import * as React from 'react';
import { Plug, RefreshCw, Rocket, SlidersHorizontal, Square, Wrench } from 'lucide-react';

import { Button } from '@agenticdevelopertoolkit/ui/components/button';
import { Spinner } from '@agenticdevelopertoolkit/ui/components/spinner';

import type { ActionId, ToolbarState } from './actions';

/**
 * The button bar: the verbs that MOVE COMMITS, then the two doors that are not verbs at all
 * — Configure, and Integrations out on the right.
 *
 * It used to carry the folder verbs too — new folder, rename, move, delete, select,
 * register, unregister — nine controls above a tree, most of them dead most of the time.
 * Those are housekeeping on a row in a rail, so they moved into that rail's own gear menu
 * (`tree/RailMenu`), where they sit beside the thing they act on. What is left is what the
 * bar was for: read the pipeline, prepare it, ship it.
 *
 * Register and unregister then went one step further and left the gear menu too. They were
 * never about the rail: the menu is otherwise add-a-folder, rename-it, move-it, delete-it,
 * while those two are about a forge on the other end of a network call, and neither belongs
 * to the folder it happened to be filed under. Configure is where they live now, and it is
 * on this bar rather than in a menu because it is a place rather than an act.
 *
 * Integrations came back OUT of Configure for the mirror of that reason. It had been a button
 * on the repository list's bar, two clicks in, filed under the rows that depend on it — which
 * made the forge credentials read as a per-repository setting rather than as the one thing
 * every run in the workspace goes out over. It is a place too, and a different place, so it
 * gets its own door.
 *
 * It draws and nothing else — every button is a callback, and whether a button is live is
 * `toolbarState`'s answer, computed elsewhere and passed in. That split is what lets the
 * rules be tested without rendering anything.
 *
 * WHAT IT ACTS ON IS NOT WRITTEN HERE. The bar sits directly above the breadcrumb, which
 * already ends in the selected row's own name — so an "on <target>" beside the buttons was
 * that name printed twice, an inch apart, in two typefaces. It is still SAID before anything
 * irreversible happens: Deploy names its target in the dialog heading, and Move and Settings
 * name theirs. With nothing selected all three buttons are disabled — see `toolbarState`.
 */
export interface ToolbarProps {
  state: ToolbarState;
  onRun: (operation: 'status' | 'prepare') => void;
  /** Opens the deploy form. Deploy always names its environments — there is no "deploy to
   *  the usual place" — so the button asks rather than does. */
  onDeploy: () => void;
  /** Stop the work in flight. Live only while there IS work — see `toolbarState`. */
  onCancel: () => void;
  /** Open the Configure dialog: the list of registered repositories, their settings, and
   *  the register wizard. Always live — what may be done in there is gated in there. */
  onConfigure: () => void;
  /** Open Integrations: the forge accounts every run goes out over. Always live — see
   *  `integrations` in `toolbarState`. */
  onIntegrations: () => void;
  /**
   * Which button started the work that is in flight, if any.
   *
   * The bar goes dead the moment a run is queued, and a bar of four grey buttons says a run
   * is happening but not WHICH — and the three verbs look identical greyed out. Marking the
   * one that was pressed turns the disabling into the answer: the operator sees the button
   * they clicked still holding the click.
   */
  active?: ActionId | null;
  className?: string;
}

/** One button, disabled with its reason as the tooltip rather than disabled in silence. */
function Action({
  id,
  state,
  label,
  icon,
  active = false,
  onClick,
}: {
  id: ActionId;
  state: ToolbarState;
  label: string;
  icon: React.ReactNode;
  /** This button's own work is in flight: it spins IN PLACE OF its icon. In place, not
   *  beside — the button keeps its width, so a bar that starts working does not reflow
   *  under the pointer that is still over it. */
  active?: boolean;
  onClick: () => void;
}): React.ReactElement {
  const { enabled, reason } = state[id];
  return (
    <Button
      variant="ghost"
      size="sm"
      disabled={!enabled}
      onClick={onClick}
      // `title` on a DISABLED button is not read by every browser, so the reason is also the
      // accessible description — a keyboard user tabbing past a dead button still hears why.
      title={active ? `${label} — running` : reason || label}
      aria-label={
        active
          ? `${label} — running`
          : reason
            ? `${label} — ${reason}`
            : label
      }
      data-running={active ? 'true' : undefined}
    >
      {active ? (
        <Spinner className="adh-button__icon animate-spin text-apt-blue" />
      ) : (
        icon
      )}
      <span className="hidden sm:inline">{label}</span>
    </Button>
  );
}

export function Toolbar({
  state,
  onRun,
  onDeploy,
  onCancel,
  onConfigure,
  onIntegrations,
  active = null,
  className,
}: ToolbarProps): React.ReactElement {
  return (
    <div
      className={`flex w-full flex-wrap items-center gap-1 ${className ?? ''}`}
      role="toolbar"
      aria-label="Pipeline actions"
    >
      <Action
        id="status"
        state={state}
        label="Status"
        icon={<RefreshCw className="adh-button__icon" />}
        active={active === 'status'}
        onClick={() => onRun('status')}
      />
      <Action
        id="prepare"
        state={state}
        label="Prepare"
        icon={<Wrench className="adh-button__icon" />}
        active={active === 'prepare'}
        onClick={() => onRun('prepare')}
      />

      {/* Deploy is the only verb that takes an argument, so it is the only one that asks
          before it acts. It opens a form rather than firing a menu entry: a control where
          production is one click away with nothing in between is a control that eventually
          gets clicked by accident. */}
      <Action
        id="deploy"
        state={state}
        label="Deploy"
        icon={<Rocket className="adh-button__icon" />}
        active={active === 'deploy'}
        onClick={onDeploy}
      />

      {/* THE WAY BACK. Every other control here is dead while a run is out, which is right —
          a second walk over rows the first one is still moving is not a thing to offer — but
          a bar with no live control at all is a bar that has taken the operator's console
          away for as long as the work lasts. Cancel is the one that comes alive instead, and
          it is what makes the other three safe to disable: the answer to "I pressed Deploy on
          the wrong folder" is a button, not the browser's stop. */}
      <Action
        id="cancel"
        state={state}
        label="Cancel"
        icon={<Square className="adh-button__icon" />}
        onClick={onCancel}
      />

      {/* Always live. It is not a verb: the three before it do something to what is
          selected, this one opens the place where what is selected came from. A viewer who
          cannot register anything still gets in — and finds Add and Remove refused with a
          reason, which is more of an answer than a grey button out here could give them. */}
      <Action
        id="configure"
        state={state}
        label="Configure"
        icon={<SlidersHorizontal className="adh-button__icon" />}
        onClick={onConfigure}
      />

      {/* PUSHED TO THE FAR RIGHT, and alone over there, because it is the only control on
          this bar that is not about this console's own contents. Status, Prepare, Deploy and
          Cancel act on the selected rows; Configure opens the list those rows come from. This
          one opens the credentials all of it runs out over — the same accounts every other
          shipr workspace uses, owned by the ecosystem rather than by this tree — so it sits
          across the gap rather than fifth in a row of five.

          It used to be two clicks inside Configure, on a bar under a repository list it has
          nothing to do with. That placement was the reason it was hard to find and the reason
          it read as a setting on the repositories rather than the thing they all depend on. */}
      <div className="flex-1" />
      <Action
        id="integrations"
        state={state}
        label="Integrations"
        icon={<Plug className="adh-button__icon" />}
        onClick={onIntegrations}
      />
    </div>
  );
}
