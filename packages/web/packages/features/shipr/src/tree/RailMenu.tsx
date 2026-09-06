'use client';

import * as React from 'react';
import {
  CheckSquare,
  FolderInput,
  FolderPlus,
  Pencil,
  Settings,
  SlidersHorizontal,
  Trash2,
} from 'lucide-react';

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@agenticdevelopertoolkit/ui/components/dropdown-menu';

import type { ActionId, ToolbarState } from '../toolbar/actions';

/**
 * The gear in a rail's header: everything that is housekeeping rather than pipeline.
 *
 * IT REPLACED THE `+`. The rail header used to carry one control, which made one of these
 * jobs discoverable and hid the rest in a toolbar above a tree they were not about. A menu
 * on the rail is where a folder's own verbs belong — the rail IS the folder, so "add a
 * directory here" needs no argument, and the four that act on a row act on the row this tree
 * has selected.
 *
 * EVERY ENTRY HERE IS ABOUT THE RAIL. That is the rule the menu is now trimmed to, and it is
 * why `Register` and `Unregister` are gone: they had a forge on the other end of them, and
 * they did not belong to the folder they were filed under — registering creates a repository
 * row, and the folder is one field on it. They are the Configure dialog's now (`Toolbar`).
 *
 * TWO BANDS, TOP TO BOTTOM, separated by a rule (Mike):
 *
 *  1. `Batch Select` — FIRST, because it is the only entry that changes what every entry
 *     below it is pointed at. Choosing it turns the menu into a mode, and a mode's switch
 *     belongs above the things it modifies, not buried among them.
 *  2. The housekeeping verbs, which act on the selection.
 *
 * It decides nothing. Every entry's enabled/disabled comes from `toolbarState`, the same
 * pure function the toolbar's buttons read, so the surfaces cannot disagree about what is
 * selected.
 */
export interface RailMenuProps {
  state: ToolbarState;
  /** The rail's own folder — null on the root rail. `Add directory` files what it makes
   *  HERE, which is the only reading that puts it where the operator is looking. */
  groupId: string | null;
  selecting: boolean;
  onNewGroup: (parentId: string | null) => void;
  onDelete: () => void;
  onRename: () => void;
  onMove: () => void;
  onToggleSelecting: () => void;
  onSettings: () => void;
}

/** One entry. A disabled entry keeps its REASON as the tooltip — a menu that greys a row
 *  and says nothing is a menu the operator has to guess at, and the guess is usually
 *  "it's broken".
 *
 *  THERE IS NO BATCH LOCK ANY MORE (Mike: "move and delete should work for batch selecting
 *  directories"). Every entry below used to go dead the moment batch mode came on, which
 *  inverted the point of the mode: ticking four folders is how you say "these four", and the
 *  two verbs that can act on four were the ones it switched off. `toolbarState` already
 *  refuses the genuinely one-at-a-time entries — Rename and Settings say so in their own
 *  words — so it is the single answer here, as this file's own rule says it should be. */
function Entry({
  id,
  state,
  label,
  icon,
  onClick,
}: {
  id: ActionId;
  state: ToolbarState;
  label: string;
  icon: React.ReactNode;
  onClick: () => void;
}): React.ReactElement {
  const { enabled, reason } = state[id];
  return (
    <DropdownMenuItem
      disabled={!enabled}
      onClick={onClick}
      title={reason || label}
      aria-label={reason ? `${label} — ${reason}` : label}
    >
      {icon}
      {label}
    </DropdownMenuItem>
  );
}

export function RailMenu({
  state,
  groupId,
  selecting,
  onNewGroup,
  onDelete,
  onRename,
  onMove,
  onToggleSelecting,
  onSettings,
}: RailMenuProps): React.ReactElement {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        render={
          <button
            type="button"
            aria-label="Folder and selection actions"
            title="Folder and selection actions"
            className="flex shrink-0 items-center justify-center rounded p-0.5 text-apt-text-muted outline-none hover:text-apt-text focus-visible:ring-2 focus-visible:ring-apt-gold/40"
          />
        }
      >
        <Settings size={16} aria-hidden />
      </DropdownMenuTrigger>

      <DropdownMenuContent align="end">
        {/* ONE entry in ONE position, in both states: the way out of batch mode has to be
            where the way in was, or the checkboxes feel stuck. */}
        <Entry
          id="select"
          state={state}
          label={selecting ? 'Finish Batch Selecting' : 'Batch Select'}
          icon={<CheckSquare className="size-4" />}
          onClick={onToggleSelecting}
        />

        <DropdownMenuSeparator />

        <Entry
          id="newGroup"
          state={state}
          label="Add directory"
          icon={<FolderPlus className="size-4" />}
          onClick={() => onNewGroup(groupId)}
        />
        <Entry
          id="rename"
          state={state}
          label="Rename"
          icon={<Pencil className="size-4" />}
          onClick={onRename}
        />
        <Entry
          id="move"
          state={state}
          label="Move"
          icon={<FolderInput className="size-4" />}
          onClick={onMove}
        />
        <Entry
          id="delete"
          state={state}
          label="Delete"
          icon={<Trash2 className="size-4" />}
          onClick={onDelete}
        />
        {/* No target in the label. It read `Settings — acme/site-deployment`, which put the
            same name the rail is already showing into a menu row and made that row twice the
            width of every other one (Mike). */}
        <Entry
          id="settings"
          state={state}
          label="Settings"
          icon={<SlidersHorizontal className="size-4" />}
          onClick={onSettings}
        />
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
