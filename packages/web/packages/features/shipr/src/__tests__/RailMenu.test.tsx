import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import { RailMenu } from '../tree/RailMenu';
import { EMPTY_SELECTION, type Selection } from '../selection';
import { toolbarState } from '../toolbar/actions';
import type { NodeRef } from '../tree/levels';
import type { AccessVerb } from '../types';

const ALL: AccessVerb[] = ['C', 'R', 'U', 'D', 'M'];
const g = (id: string): NodeRef => ({ kind: 'group', id });
const r = (id: string): NodeRef => ({ kind: 'repo', id });

function handlers() {
  return {
    onNewGroup: vi.fn(),
    onDelete: vi.fn(),
    onRename: vi.fn(),
    onMove: vi.fn(),
    onToggleSelecting: vi.fn(),
    onSettings: vi.fn(),
  };
}

/** Draw the gear for one selection and open it, since every entry is behind the trigger. */
async function open(
  over: {
    selection?: Partial<Selection>;
    verbs?: AccessVerb[];
    groupId?: string | null;
  } = {},
  h = handlers(),
): Promise<ReturnType<typeof handlers>> {
  const selection: Selection = { ...EMPTY_SELECTION, ...over.selection };
  render(
    <RailMenu
      state={toolbarState({
        selection,
        verbs: over.verbs ?? ALL,
        hasGroups: true,
      })}
      groupId={over.groupId ?? null}
      selecting={selection.selecting}
      {...h}
    />,
  );
  await userEvent.click(
    screen.getByRole('button', { name: 'Folder and selection actions' }),
  );
  return h;
}

function entry(name: RegExp | string): Promise<HTMLElement> {
  return screen.findByRole('menuitem', { name });
}

describe('RailMenu — the two scopes', () => {
  it('offers the rail’s own verb with nothing selected at all', async () => {
    // It adds something to the folder this rail IS listing, so it needs no argument — which
    // is exactly why the `+` it replaced could live in the header in the first place.
    await open();
    expect(await entry(/^Add directory/)).not.toHaveAttribute('data-disabled');
  });

  it('files what it adds in the folder the rail is listing, not at the root', async () => {
    // The gear on a sub-folder's rail is the sub-folder's gear. Passing null here would
    // silently create every folder at the top level, one level away from where the operator
    // is looking.
    const h = await open({ groupId: 'a1' });
    await userEvent.click(await entry(/^Add directory/));
    expect(h.onNewGroup).toHaveBeenCalledWith('a1');
  });

  it('greys the four selection verbs, each with its own reason', async () => {
    await open();
    for (const [label, reason] of [
      ['Delete', 'Select a folder to delete.'],
      ['Rename', 'Select a folder to rename.'],
      ['Move', 'Select something to move.'],
      ['Settings', 'Select a repository or a folder first.'],
    ] as const) {
      // The reason rides in the accessible name as well as the tooltip: a greyed row that
      // says nothing is indistinguishable from a broken one.
      expect(await entry(`${label} — ${reason}`)).toHaveAttribute('data-disabled');
    }
  });

  it('leaves Batch Select live with nothing selected — it is the way IN', async () => {
    // The defect (Mike: "batch select doesn't work"). It was greyed here, on the rail where
    // batch mode is most useful: several rows, none of them chosen yet. The mode is what
    // MAKES a selection, so it cannot be gated on having one.
    await open();
    expect(await entry('Batch Select')).not.toHaveAttribute('data-disabled');
  });

  it('wakes them once a row is highlighted', async () => {
    await open({ selection: { focus: g('a') } });
    for (const label of ['Delete', 'Rename', 'Move', 'Batch Select']) {
      expect(await entry(label)).not.toHaveAttribute('data-disabled');
    }
  });
});

describe('RailMenu — the order of the bands', () => {
  it('leads with Batch Select and ends with the housekeeping verbs', async () => {
    // The order IS the ask (Mike): the mode switch above everything it modifies. A test that
    // only checked the labels existed would pass with them scattered.
    await open({ selection: { focus: r('m1') } });
    // The content is portalled, so it arrives a tick after the click — wait for ONE entry
    // before taking the whole list, or the list is taken from an empty menu.
    await entry(/^Batch Select/);
    const labels = screen
      .getAllByRole('menuitem')
      .map((n) => (n.getAttribute('aria-label') ?? '').split(' — ')[0]);
    expect(labels).toEqual([
      'Batch Select',
      'Add directory',
      'Rename',
      'Move',
      'Delete',
      'Settings',
    ]);
  });

  it('has no forge band at all — register and unregister are the dialog’s', async () => {
    // THE POINT OF THE TRIM. Both entries reached a forge and neither was about the folder
    // they were filed under: registering CREATES a repository row, and the folder is one
    // field on it. A stale copy here would be a second door onto a question the Configure
    // dialog is meant to be the only one for.
    await open({ selection: { focus: r('m1') } });
    await entry(/^Batch Select/);
    expect(screen.queryByRole('menuitem', { name: /Register/ })).toBeNull();
    expect(screen.queryByRole('menuitem', { name: /Unregister/ })).toBeNull();
  });

  it('keeps Rename dead on a repository', async () => {
    // Renaming is a FOLDER's verb; a repository is named by the forge. `toolbarState` alone
    // decides that, and the menu draws the entry either way.
    await open({ selection: { focus: r('m1') } });
    expect(await entry(/^Rename/)).toHaveAttribute('data-disabled');
  });

  it('has it the other way round on a folder', async () => {
    await open({ selection: { focus: g('a') } });
    expect(await entry('Rename')).not.toHaveAttribute('data-disabled');
  });
});

describe('RailMenu — batch mode and settings', () => {
  it('turns Batch Select into Finish Batch Selecting, and leaves the way out open', async () => {
    // A mode whose exit is disabled is a trap, so it stays live with every tick cleared.
    const h = await open({ selection: { selecting: true, checked: [] } });
    const done = await entry('Finish Batch Selecting');
    expect(done).not.toHaveAttribute('data-disabled');
    await userEvent.click(done);
    expect(h.onToggleSelecting).toHaveBeenCalled();
  });

  it('keeps the two batch verbs live on a batch of folders', async () => {
    // THE BUG THIS REPLACED. Batch mode used to grey every entry but its own exit, which
    // inverted the point of the mode: ticking four folders is how an operator says "these
    // four", and Move and Delete — the only two entries that can act on four — were the ones
    // it switched off (Mike: "move and delete should work for batch selecting directories").
    const h = await open({
      selection: { selecting: true, checked: [g('a'), g('b')] },
    });
    for (const label of ['Move', 'Delete']) {
      expect(await entry(label)).not.toHaveAttribute('data-disabled');
    }
    await userEvent.click(await entry('Delete'));
    expect(h.onDelete).toHaveBeenCalled();
  });

  it('still refuses the entries that genuinely take one row, and says which', async () => {
    // `toolbarState` is the single answer, so the refusal is in its own words rather than a
    // blanket "finish batch selecting first" that told the operator nothing about WHY.
    await open({ selection: { selecting: true, checked: [g('a'), g('b')] } });
    expect(
      await entry(/^Rename — Rename works on one folder at a time\./),
    ).toHaveAttribute('data-disabled');
    expect(
      await entry(/^Settings — Settings opens one at a time\./),
    ).toHaveAttribute('data-disabled');
  });

  it('does not put the target’s name in the Settings entry', async () => {
    // It read `Settings — acme/site-deployment`: the name the rail is already showing,
    // repeated, on the one row that was then twice the width of every other (Mike).
    await open({ selection: { focus: r('m1') } });
    expect(await entry('Settings')).toBeTruthy();
  });
});

describe('RailMenu — it decides nothing itself', () => {
  it('greys everything a viewer may not do, from the same verbs the toolbar reads', async () => {
    await open({ verbs: ['R'], selection: { focus: g('a') } });
    expect(await entry(/^Add directory/)).toHaveAttribute('data-disabled');
    expect(await entry(/^Delete/)).toHaveAttribute('data-disabled');
    expect(await entry(/^Rename/)).toHaveAttribute('data-disabled');
    expect(await entry(/^Move/)).toHaveAttribute('data-disabled');
    // Selecting rows and reading their settings are not writes, so they stay live.
    expect(await entry('Batch Select')).not.toHaveAttribute('data-disabled');
    expect(await entry(/^Settings/)).not.toHaveAttribute('data-disabled');
  });

  it('fires nothing at all from a disabled entry', async () => {
    const h = await open();
    await userEvent.click(await entry(/^Move/));
    expect(h.onMove).not.toHaveBeenCalled();
  });
});
