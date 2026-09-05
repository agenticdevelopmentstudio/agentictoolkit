import { targetsOf, type Selection } from '../selection';
import type { NodeRef } from '../tree/levels';
import type { AccessVerb } from '../types';

/**
 * Which controls are live, and — when one is not — WHY.
 *
 * Pure, and separated from the two surfaces that draw it, because "why is Deploy grey" is
 * the question this view gets asked most and a function that answers it in one line is a
 * function a test can pin. The reason is not decoration: a disabled control with no
 * explanation is indistinguishable from a broken one.
 *
 * ONE function for ALL THREE surfaces. The toolbar draws the pipeline verbs, the rail's gear
 * menu draws the housekeeping ones, and the Configure dialog's button bar draws `register`
 * and `unregister` — but "is this allowed, and why not" is one question about one selection,
 * and splitting it is how a toolbar and a menu end up disagreeing about whether a folder is
 * selected.
 *
 * The dialog asks the same question about its OWN selection: it passes a `Selection` whose
 * targets are the mirrors of the dev repo its rail has highlighted, because that is what
 * Remove acts on. So `unregister`'s "select a repository first" reads correctly there
 * without a second rule.
 *
 * NOT A SECURITY BOUNDARY. Every route re-derives the caller's verbs server-side; this only
 * decides what is worth offering. A verb absent from `verbs` means "do not offer" — never
 * "everything else is therefore safe to offer".
 */
export interface ButtonState {
  enabled: boolean;
  /** Empty when enabled. One short sentence otherwise, shown as the control's tooltip. */
  reason: string;
}

export type ActionId =
  | 'status'
  | 'prepare'
  | 'deploy'
  | 'cancel'
  | 'configure'
  | 'integrations'
  | 'register'
  | 'unregister'
  | 'newGroup'
  | 'rename'
  | 'delete'
  | 'move'
  | 'select'
  | 'settings';

export type ToolbarState = Record<ActionId, ButtonState>;

const OK: ButtonState = { enabled: true, reason: '' };

function no(reason: string): ButtonState {
  return { enabled: false, reason };
}

function has(verbs: readonly AccessVerb[] | undefined, verb: AccessVerb): boolean {
  return verbs !== undefined && verbs.includes(verb);
}

export interface ToolbarInput {
  selection: Selection;
  /**
   * What this operator may do — or `undefined` while that is still being read.
   *
   * THE TWO ARE NOT THE SAME and `[]` cannot stand in for the second, which is what it was
   * doing: a console whose tree read has not landed yet held no verbs, so every gated control
   * below answered a question nobody had asked with a sentence about permission — "You cannot
   * register repositories here" — and then silently became false a moment later. An operator
   * who reads that and stops has been turned away from something they were always allowed to
   * do, by a refusal that never admits it was wrong.
   */
  verbs: readonly AccessVerb[] | undefined;
  /** A run is already in flight from this console. The pipeline buttons stand down rather
   *  than queue a second walk over rows the first one is still moving. */
  busy?: boolean;
  /** There is somewhere to move things TO — at least one folder exists. */
  hasGroups?: boolean;
}

/**
 * THE PIPELINE VERBS NEED A TARGET.
 *
 * They used to treat an empty selection as "the whole workspace", the way `shipr status`
 * with no argument does in a terminal. A terminal is not this: there the command is typed
 * out and the absent argument is visible in what was typed, while here it is a button that
 * looks identical whether it is about to read one repository or ninety. So an empty
 * selection DISABLES them, and the reason says what to do about it.
 *
 * Everything else divides in two. `newGroup` and `register` are about the RAIL the gear
 * menu sits on — they add something to the folder that rail is listing, so nothing has to
 * be selected for them to mean something. The other five act on the selection, and are
 * dead without one.
 */
export function toolbarState(input: ToolbarInput): ToolbarState {
  const { verbs, busy = false, hasGroups = false } = input;
  const targets = targetsOf(input.selection);
  const groups = targets.filter((t) => t.kind === 'group');
  const repos = targets.filter((t) => t.kind === 'repo');

  const running = busy ? no('A run is already in flight.') : null;
  // Pre-empts every verb-gated control below, and none of the ungated ones: Configure and
  // Integrations are always live precisely because they ask no verb, so there is nothing about
  // them left to be reading.
  const pending =
    verbs === undefined ? no('Still reading what you may do in this workspace.') : null;
  const nothing = targets.length === 0;
  const pipeline = (verb: AccessVerb, need: string): ButtonState =>
    pending ??
    running ??
    (!has(verbs, verb)
      ? no(need)
      : nothing
        ? no('Select a repository or a folder first.')
        : OK);

  return {
    status: pipeline('R', 'You cannot read these repositories.'),
    prepare: pipeline('U', 'You cannot move branches in this workspace.'),
    deploy: pipeline('U', 'You cannot move branches in this workspace.'),

    // THE EXACT INVERSE OF THE THREE ABOVE, and the only control here that is live BECAUSE
    // something is running. It needs no selection and no target: what it stops is the work
    // this console started, whatever that was pointed at — asking the operator to re-select
    // the folder a deploy is walking before they may stop it is a control that arrives too
    // late to be one. `U` because stopping a run mid-fleet decides which repositories were
    // carried, which is the same authority that started it.
    cancel: pending
      ? pending
      : !busy
      ? no('Nothing is running.')
      : has(verbs, 'U')
        ? OK
        : no('You cannot stop runs in this workspace.'),

    // ALWAYS LIVE, deliberately, and the only entry here that is. It opens a dialog, and
    // everything the dialog can do is gated inside the dialog by the same function — so a
    // viewer who opens it finds Add and Remove refused with a reason, which is strictly more
    // informative than a greyed button whose tooltip has to explain a surface they cannot
    // reach. It also stays reachable while a run is in flight: reading a repository's
    // settings is not a write, and locking the operator out of them for the duration of a
    // deploy is a mode with nothing to gain from it.
    configure: OK,

    // ALWAYS LIVE for the same reason, and it is a different question from Configure's.
    // Configure asks "which repositories does this console know about"; this asks "which
    // forges can it reach at all", which is the answer an operator wants when a run failed
    // to get out — and the person most likely to be asked that is a viewer who can register
    // nothing. Reading which credentials exist is not a write, and the dialog refuses its
    // own writes, so there is nothing out here for a grey button to protect.
    integrations: OK,

    // Register INVENTS a row, so it is about the rail rather than about the selection: the
    // bar it now hangs in belongs to the dialog's list of repositories, and a folder is one
    // field on the row it creates. Nothing needs to be selected for that to be a complete
    // sentence.
    register:
      pending ??
      running ??
      (has(verbs, 'C') ? OK : no('You cannot register repositories here.')),

    unregister: pending
      ? pending
      : running
      ? running
      : !has(verbs, 'D')
        ? no('You cannot unregister repositories here.')
        : repos.length === 0
          ? no('Select a repository to unregister.')
          : OK,

    // A folder is created INSIDE the folder the rail is listing — which is the only reading
    // that puts the new folder where the operator is looking.
    newGroup: pending ?? (has(verbs, 'C') ? OK : no('You cannot add folders here.')),

    rename: pending
      ? pending
      : !has(verbs, 'U')
      ? no('You cannot rename folders here.')
      : groups.length === 1 && repos.length === 0
        ? OK
        : groups.length === 0
          ? no('Select a folder to rename.')
          : no('Rename works on one folder at a time.'),

    // Deleting a folder is not deleting what is in it; the backend refuses a folder that
    // still has contents, and the confirmation says so. A repository is removed by
    // UNREGISTERING it, which is a pipeline operation with a run behind it — so delete
    // stays about folders, and its refusal names the control the other job belongs to.
    delete: pending
      ? pending
      : !has(verbs, 'D')
      ? no('You cannot delete folders here.')
      : groups.length === 0
        ? no('Select a folder to delete.')
        : repos.length > 0
          ? no('Unregister removes a repository — delete only removes folders.')
          : OK,

    move: pending
      ? pending
      : !has(verbs, 'U')
      ? no('You cannot move things in this workspace.')
      : nothing
        ? no('Select something to move.')
        : !hasGroups
          ? no('There are no folders to move into yet.')
          : OK,

    // Turning batch mode ON seeds it with the highlighted row, so Select genuinely acts on
    // the selection rather than merely sitting beside it. Turning it OFF must always be
    // possible: a mode with a disabled exit is a trap, and the ticks it holds are what every
    // other control is pointed at.
    select: input.selection.selecting
      ? OK
      : nothing
        ? no('Highlight a row to start a batch from.')
        : OK,

    settings: nothing
      ? no('Select a repository or a folder first.')
      : targets.length > 1
        ? no('Settings opens one at a time.')
        : OK,
  };
}

/** The one thing a run request needs from a selection: what to name as its scope. Several
 *  targets are several runs — the backend takes ONE scope per run, and a batch that silently
 *  became a single "all" would touch rows nobody ticked. */
export function scopeOf(ref: NodeRef): {
  scopeKind: 'group' | 'deploy_repo';
  scopeId: string;
} {
  return ref.kind === 'group'
    ? { scopeKind: 'group', scopeId: ref.id }
    : { scopeKind: 'deploy_repo', scopeId: ref.id };
}
