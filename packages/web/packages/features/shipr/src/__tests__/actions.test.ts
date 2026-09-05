import { describe, expect, it } from 'vitest';

import { scopeOf, toolbarState } from '../toolbar/actions';
import { EMPTY_SELECTION, type Selection } from '../selection';
import type { NodeRef } from '../tree/levels';
import type { AccessVerb } from '../types';

const ALL: AccessVerb[] = ['C', 'R', 'U', 'D', 'M'];
const g = (id: string): NodeRef => ({ kind: 'group', id });
const r = (id: string): NodeRef => ({ kind: 'repo', id });

function state(
  selection: Partial<Selection> = {},
  verbs: AccessVerb[] = ALL,
  extra: { busy?: boolean; hasGroups?: boolean } = {},
) {
  return toolbarState({
    selection: { ...EMPTY_SELECTION, ...selection },
    verbs,
    hasGroups: true,
    ...extra,
  });
}

describe('toolbarState — the pipeline buttons', () => {
  it('stands status, prepare and deploy down with NOTHING selected', () => {
    // They used to treat an empty selection as "the whole workspace", the way
    // `shipr status` with no argument does in a terminal. A button does not show
    // its argument the way a typed command does, so an absent one disables it.
    const s = state();
    for (const id of ['status', 'prepare', 'deploy'] as const) {
      expect(s[id].enabled, id).toBe(false);
      expect(s[id].reason, id).toBe('Select a repository or a folder first.');
    }
  });

  it('wakes them for a repository and for a folder alike', () => {
    expect(state({ focus: r('r1') }).status.enabled).toBe(true);
    expect(state({ focus: g('a') }).deploy.enabled).toBe(true);
  });

  it('stands them down while a run is in flight, and says why', () => {
    const s = state({ focus: r('r1') }, ALL, { busy: true });
    expect(s.deploy.enabled).toBe(false);
    expect(s.deploy.reason).toBe('A run is already in flight.');
    expect(s.register.enabled).toBe(false);
    expect(s.unregister.enabled).toBe(false);
  });

  it('never leaves a disabled button without a reason', () => {
    const s = state({}, []);
    for (const [id, button] of Object.entries(s)) {
      if (!button.enabled) expect(button.reason, id).not.toBe('');
      else expect(button.reason, id).toBe('');
    }
  });

  it('offers prepare and deploy only to a caller who may move branches', () => {
    const s = state({ focus: r('r1') }, ['R']);
    expect(s.status.enabled).toBe(true);
    expect(s.prepare.enabled).toBe(false);
    expect(s.deploy.enabled).toBe(false);
  });

  it('names the missing verb ahead of the missing target', () => {
    // Both are wrong at once; the one the operator cannot fix by clicking a row is
    // the one worth saying.
    const s = state({}, ['R']);
    expect(s.deploy.reason).toBe('You cannot move branches in this workspace.');
  });
});

describe('toolbarState — register and unregister', () => {
  it('offers register regardless of the selection — it invents a row', () => {
    expect(state().register.enabled).toBe(true);
    expect(state({ focus: g('a') }).register.enabled).toBe(true);
  });

  it('withholds register from a caller without create', () => {
    expect(state({}, ['R', 'U', 'D']).register.enabled).toBe(false);
  });

  it('requires a target for unregister — "everything" is not an unregister scope', () => {
    expect(state().unregister.enabled).toBe(false);
    expect(state({ focus: r('r1') }).unregister.enabled).toBe(true);
  });

  it('withholds unregister from a caller without delete', () => {
    expect(state({ focus: r('r1') }, ['C', 'R', 'U']).unregister.enabled).toBe(false);
  });

  it('reads the Configure dialog’s own selection, which is a batch of mirrors', () => {
    // The dialog has no `focus` — its rail highlights a DEV repo, and what that stands for is
    // the mirrors hanging off it. So it hands `toolbarState` a batch, and the same rule that
    // serves the console's tick-boxes answers it, with no second rule anywhere.
    const batch = state({ selecting: true, checked: [r('m1'), r('m2')] });
    expect(batch.unregister.enabled).toBe(true);
    // And nothing highlighted in the dialog is the ordinary refusal, said the ordinary way.
    const none = state({ selecting: true, checked: [] });
    expect(none.unregister.enabled).toBe(false);
    expect(none.unregister.reason).toBe('Select a repository to unregister.');
  });
});

describe('toolbarState — configure', () => {
  it('is live with nothing selected, no verbs at all, and a run in flight', () => {
    // THE ONE ALWAYS-LIVE ENTRY, and deliberately: it opens a place rather than doing
    // something to a row, so there is no target it could be missing. A viewer gets in and
    // finds Add and Remove refused INSIDE, each with its own reason on it — which is a
    // better answer than a grey button on the bar, and it still lets them read the settings
    // they are allowed to read. Refusing at the door would hide those too.
    expect(state().configure.enabled).toBe(true);
    expect(state({}, []).configure.enabled).toBe(true);
    expect(state({ focus: r('r1') }, ALL, { busy: true }).configure.enabled).toBe(true);
  });

  it('carries no reason, because it never refuses', () => {
    expect(state({}, []).configure.reason).toBeFalsy();
  });
});

describe('toolbarState — the folder buttons', () => {
  it('renames exactly one folder, and says so when asked for more', () => {
    expect(state({ focus: g('a') }).rename.enabled).toBe(true);
    expect(state({}).rename.reason).toBe('Select a folder to rename.');
    const many = state({ selecting: true, checked: [g('a'), g('b')] });
    expect(many.rename.enabled).toBe(false);
    expect(many.rename.reason).toBe('Rename works on one folder at a time.');
  });

  it('refuses rename when a repository is in the batch', () => {
    const mixed = state({ selecting: true, checked: [g('a'), r('r1')] });
    expect(mixed.rename.enabled).toBe(false);
  });

  it('deletes folders only, and names the repositories as the obstacle', () => {
    expect(state({ focus: g('a') }).delete.enabled).toBe(true);
    expect(state({ focus: r('r1') }).delete.reason).toBe(
      'Select a folder to delete.',
    );
    const mixed = state({ selecting: true, checked: [g('a'), r('r1')] });
    expect(mixed.delete.reason).toBe(
      'Unregister removes a repository — delete only removes folders.',
    );
  });

  it('offers newGroup with nothing selected', () => {
    expect(state().newGroup.enabled).toBe(true);
    expect(state({}, ['R']).newGroup.enabled).toBe(false);
  });

  it('will not offer move when there is nowhere to move to', () => {
    const s = state({ focus: r('r1') }, ALL, { hasGroups: false });
    expect(s.move.enabled).toBe(false);
    expect(s.move.reason).toBe('There are no folders to move into yet.');
  });

  it('requires something to move', () => {
    expect(state().move.reason).toBe('Select something to move.');
  });
});

describe('toolbarState — select and settings', () => {
  it('needs a row to start a batch from, but never traps you in one', () => {
    expect(state().select.enabled).toBe(false);
    expect(state().select.reason).toBe('Highlight a row to start a batch from.');
    expect(state({ focus: r('r1') }).select.enabled).toBe(true);
    // Batch mode with a disabled exit is a trap — Done is always live, even with
    // every tick cleared.
    expect(state({ selecting: true, checked: [] }).select.enabled).toBe(true);
  });

  it('opens settings for one thing at a time', () => {
    expect(state().settings.reason).toBe(
      'Select a repository or a folder first.',
    );
    expect(state({ focus: g('a') }).settings.enabled).toBe(true);
    const many = state({ selecting: true, checked: [g('a'), g('b')] });
    expect(many.settings.enabled).toBe(false);
    expect(many.settings.reason).toBe('Settings opens one at a time.');
  });
});

describe('scopeOf', () => {
  it('names a folder as a group scope and a mirror as a deploy_repo scope', () => {
    expect(scopeOf(g('a'))).toEqual({ scopeKind: 'group', scopeId: 'a' });
    expect(scopeOf(r('r1'))).toEqual({
      scopeKind: 'deploy_repo',
      scopeId: 'r1',
    });
  });
});

/**
 * The verbs are not known YET, which is not the same as being denied.
 *
 * The console reads its tree — groups, items and verbs together — after it mounts, and for
 * the length of that read it held `[]`. Every gated control then answered with a sentence
 * about permission: click Configure and then Add in that window and shipr said "You cannot
 * register repositories here" to an operator who could, then quietly changed its mind. A
 * refusal that retracts itself is worse than a wait, because only the wait is true.
 */
describe('toolbarState — before the verbs have been read', () => {
  const PENDING = 'Still reading what you may do in this workspace.';

  it.each([
    'status',
    'prepare',
    'deploy',
    'cancel',
    'register',
    'unregister',
    'newGroup',
    'rename',
    'delete',
    'move',
  ] as const)('says %s is still being read, not refused', (id) => {
    // Every one of these is gated on a verb, so with no verbs to gate on there is nothing
    // to say about permission. The selection is deliberately full: a reason about the
    // selection would be just as wrong, and pre-empting it is the point.
    // NOT through `state()`: its `verbs` parameter has a default, and a default fires on an
    // explicit `undefined` — so the helper cannot express the very state under test.
    const s = toolbarState({
      selection: { ...EMPTY_SELECTION, focus: r('repo-1') },
      verbs: undefined,
      hasGroups: true,
      busy: true,
    });
    expect(s[id].enabled).toBe(false);
    expect(s[id].reason).toBe(PENDING);
  });

  it('leaves the two ungated controls alone', () => {
    // Configure and Integrations ask no verb, so there is nothing about them left to read.
    // Disabling them here would lock an operator out of the one dialog that explains, per
    // control, why the rest are refused.
    const s = toolbarState({
      selection: EMPTY_SELECTION,
      verbs: undefined,
      hasGroups: true,
    });
    expect(s.configure).toEqual({ enabled: true, reason: '' });
    expect(s.integrations).toEqual({ enabled: true, reason: '' });
  });

  it('still says a workspace that granted NOTHING is a refusal', () => {
    // The distinction only holds if the empty read keeps its own sentence: a viewer with no
    // `C` is genuinely refused, and telling them to wait for a read that already landed
    // would leave them waiting forever.
    const s = state({}, []);
    expect(s.register.reason).toBe('You cannot register repositories here.');
  });
});
