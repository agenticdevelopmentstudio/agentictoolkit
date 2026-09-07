'use client';

import * as React from 'react';

import { HierarchicalTopicDetail } from '@agenticdevelopertoolkit/ui/blocks';
import { AlertModal } from '@agenticdevelopertoolkit/ui/components/alert-modal';

import { useRunningRepos } from './activity/useRunningRepos';
import { isFinished, useRuns, useSettle } from './activity/useRuns';
import { ConfigureDialog } from './configure/ConfigureDialog';
import { useForgeCatalogue } from './forge/useForgeCatalogue';
import { STATUS_MAX_AGE_MS, statusIsStale } from './freshness';
import {
  connectionsHashPresent,
  ConnectionsDialog,
} from './configure/ConnectionsDialog';
import { applyImport, ImportError } from './exchange/apply';
import type { ImportPlan } from './exchange/plan';
import { GroupDetailPane } from './GroupDetailPane';
import { RepoView } from './RepoView';
import {
  EMPTY_SELECTION,
  targetsOf,
  toggleChecked,
  type Selection,
} from './selection';
import {
  SettingsDialog,
  type RepoSettingsPatch,
  type SettingsTarget,
} from './settings/SettingsDialog';
import { scopeOf, toolbarState, type ActionId } from './toolbar/actions';
import {
  ConfirmDialog,
  DeployDialog,
  MoveDialog,
  NameDialog,
  type ConnectionOption,
  type DeployRequest,
} from './toolbar/dialogs';
import { Toolbar } from './toolbar/Toolbar';
import { descendantsOf, planLevels, type NodeRef } from './tree/levels';
import { RailMenu } from './tree/RailMenu';
import { buildLevels, repoLabel } from './tree/toLevels';
import { useTree } from './tree/useTree';
import type { ShiprClient } from './client';
import type {
  DevRepo,
  Environment,
  Operation,
  OrgDefaultsPatch,
  RegisterRequest,
  RepoPatch,
} from './types';

/**
 * The whole console: folders, and what has been done to what is in them.
 *
 * ONE VIEW, not two. It used to be a split — the tree on the left, a log on the right that
 * showed whichever run was most recent anywhere in the workspace. Two panes, two subjects:
 * the one that was selected and the one that had most recently spoken. So the output moved
 * to where its subject is. Choose a repository and the pane is that repository's ladder and
 * its latest output; choose a folder and it is every repository under it, each with its own,
 * in the order the runner walks them.
 *
 * THE BACKEND DOES THE WORK. Nothing here runs git, decides an order, or knows what
 * `prepare` means; it posts an operation and a scope and renders what comes back. That is
 * also why a folder is ONE run rather than a loop in this file — the backend expands it, in
 * the rail's own order, and a browser tab closed mid-batch does not strand it.
 *
 * THE THREE VERBS NEED A TARGET. Status, Prepare and Deploy act on what is selected and are
 * dead without a selection. The folder verbs — add, rename, move, delete, select, settings —
 * hang off the gear in a rail's own header, where "here" is unambiguous. Everything that is
 * about SETUP rather than about a folder or a run — registering a repository and removing
 * one — is behind Configure, which is a place and therefore a button on the bar rather than
 * an entry in a menu. The forge accounts both of those go out over are one door further out:
 * Integrations, on the far right of the same bar, because they belong to the ecosystem rather
 * than to this workspace's tree and every console on it shares them.
 */

/** What the ROOT rail is a list of. The breadcrumb keeps the workspace's own name. */
const ROOT_TITLE = 'Projects';

export interface ShiprConsoleProps {
  client: ShiprClient;
  /** The caller's forge connections, for the register wizard. The console does not read
   *  them itself: they live behind `/integrations`, which is the host's concern. */
  connections?: readonly ConnectionOption[];
  /** Why {@link connections} could not be read, when that is the reason it is missing. Passed
   *  through to the register wizard, which is the one surface where an operator is looking for
   *  an installation and needs to know whether "none" means none or means we could not ask. */
  connectionsError?: string | null;
  /** Re-read {@link connections}. Called when the Integrations dialog reports a write —
   *  connecting an account there is exactly what adds an installation to that list, and
   *  without this seam the wizard opened next would still be offering the installations from
   *  before it. Optional: a host with nothing to re-read may omit it and the list simply
   *  stays as it loaded. */
  onConnectionsChanged?: () => void;
  /** Breadcrumb root — the workspace's name, as the host already knows it. */
  rootLabel?: string;
  className?: string;
}

/**
 * The console, PINNED TO ONE WORKSPACE.
 *
 * Everything below this line is per-workspace state: the folder path the operator has
 * walked, the row they highlighted, the runs this tab started, the tree itself. None of it
 * means anything in a different workspace, and one of them — the tree — is another tenant's
 * data. So a workspace change is not something the console cleans up after; it is a
 * DIFFERENT CONSOLE. The key makes React unmount this one and build the next from nothing,
 * which is a guarantee no effect can be written wrongly and no future prop can defeat.
 *
 * The hooks underneath hold the same rule independently (`useTree`, `useRuns` tag their
 * rows with the workspace they read them from) so a host that mounts the inner parts
 * itself cannot lose it either.
 */
export function ShiprConsole(props: ShiprConsoleProps): React.ReactElement {
  return <Console key={props.client.workspace ?? ''} {...props} />;
}

function Console({
  client,
  connections,
  connectionsError = null,
  onConnectionsChanged,
  rootLabel = 'Repositories',
  className,
}: ShiprConsoleProps): React.ReactElement {
  /**
   * THE FORGE, READ ONCE AND HELD — see {@link useForgeCatalogue}.
   *
   * Here rather than inside the Configure dialog, because that dialog is unmounted when it
   * closes: read down there, the accounts and their repositories were fetched again on every
   * opening, and an installation whose read failed disappeared from the org menu without a
   * word. Here it starts as the console mounts, survives every close, and is the one place
   * that can answer whether an org the operator typed is even reachable.
   */
  const catalogue = useForgeCatalogue(client, connections, connectionsError);

  const tree = useTree(client);
  /**
   * WHAT THE DETAIL PANES RE-READ ON — deliberately not `tree.reads`.
   *
   * The tree is now re-read every time the runner moves from one repository to the next, so
   * that the rail's dots go out one at a time (see the walk effect below). The panes must
   * NOT follow that counter: a folder's pane holds one `RepoView` per repository, and forty
   * of them re-reading on every step transition is forty reads per repository across the
   * batch — quadratic in the size of the folder, for a pane that only changed in one place.
   *
   * This counter moves for the things that change what a pane is OF: a register, a move, a
   * rename, a settings save, a run leaving the queue. What a pane needs during a batch is
   * its own repository's turn ending, and each section watches that for itself through
   * `running`.
   */
  const [paneNonce, setPaneNonce] = React.useState(0);
  const runs = useRuns(client);
  /** Wait on a run this console started — the same live list, no second subscription. */
  const settle = useSettle(client, runs);

  const [path, setPath] = React.useState<string[]>([]);
  const [selection, setSelection] = React.useState<Selection>(EMPTY_SELECTION);
  const [error, setError] = React.useState<string | null>(null);

  /** Runs this console started, in the order it started them. Nothing renders it directly
   *  any more — each pane finds its own repository's latest run — but it is what spins the
   *  rail's rows, what stands the pipeline buttons down while work is out, and what Cancel
   *  stops. */
  const [queue, setQueue] = React.useState<string[]>([]);

  /** WHICH BUTTON is holding that work. Kept beside the queue rather than derived from it
   *  because a run does not remember which control started it: Deploy posts a `prepare` and
   *  a `deploy`, and reading the queue's head back would light Prepare for the first half of
   *  a deploy the operator never pressed Prepare for. */
  const [activeAction, setActiveAction] = React.useState<ActionId | null>(null);

  /**
   * Bumped the INSTANT a button is pressed, and used in the detail pane's `key`.
   *
   * A press posts one run per target and only then refreshes the tree, so for as long as
   * those requests take the pane went on showing the previous run's ladder and the previous
   * run's log — pressing Deploy looked, for a second or more, exactly like not pressing it
   * (Mike). `tree.reads` cannot fix this: it moves when the read LANDS, which is the moment
   * the new answer is already there.
   *
   * So this is not another nonce. It is a remount: React drops the old pane's state — the
   * detail it was keeping while re-fetching, the log it had streamed — and builds a new one
   * with nothing in it. What the operator sees is the pane going blank under their finger
   * and filling in with what they just started, which is the only honest sequence.
   */
  const [pressed, setPressed] = React.useState(0);

  // Dialogs. One at a time by construction: a single discriminated value rather than six
  // booleans that can all be true.
  type Modal =
    | { kind: 'none' }
    | { kind: 'newGroup'; parentId: string | null }
    | { kind: 'rename'; id: string; name: string }
    // IDS, NOT AN ID. Delete works on a batch for the same reason Move does: a select-mode
    // tick on four folders is one statement about four folders, and a menu item that
    // silently acted on whichever one happened to be first is worse than one that refuses.
    | { kind: 'delete'; ids: string[]; names: string[] }
    | { kind: 'move'; refs: NodeRef[] }
    // No payload. Configure is a PLACE, not an act on a row: it opens on nothing selected
    // and the operator chooses inside it, so there is nothing for this console to hand it.
    | { kind: 'configure' }
    // A SIBLING of Configure, not a child of it. The forge accounts are the ecosystem's, not
    // this tree's, and being one modal shallower is what lets that dialog own the address —
    // see `syncConnectionsHash`.
    | { kind: 'connections' }
    | { kind: 'deploy' }
    // The REF, not the row: the tree is re-read while a dialog is open (a run lands, a
    // folder's contents change), and a captured row would go stale behind it.
    | { kind: 'settings'; ref: NodeRef };
  const [modal, setModal] = React.useState<Modal>({ kind: 'none' });
  const close = React.useCallback(() => setModal({ kind: 'none' }), []);

  /**
   * Reopen Integrations when the address names it — the return leg of a forge connect.
   *
   * Connecting a GitHub App leaves the app entirely, so the document that held this state is
   * gone by the time the operator comes back; `/integrations/oauth-callback` returns them to
   * the URL the connect started on, and `CONNECTIONS_HASH` is the part of it that says where
   * in the console they were. Without this the new connection lands on a bare tree with every
   * dialog closed, which reads as the connect having failed.
   *
   * Once, on mount, and only to OPEN: the dialog itself owns the hash from then on, and a
   * console that re-asserted it would fight the operator closing it.
   */
  React.useEffect(() => {
    if (connectionsHashPresent()) setModal({ kind: 'connections' });
  }, []);

  const groups = tree.data?.groups ?? [];
  const items = tree.data?.items ?? [];
  // NO `?? []`. An unread tree is not a workspace granting nothing, and collapsing the two
  // makes every gated control claim a permission refusal for as long as the read is out —
  // see `ToolbarInput.verbs`. `undefined` travels all the way to `toolbarState`, which is
  // the one place that knows what to say instead.
  const verbs = tree.data?.verbs;

  const plans = React.useMemo(
    () =>
      planLevels({
        tree: { groups, items },
        path,
        selectedRepoId:
          selection.focus?.kind === 'repo' ? selection.focus.id : null,
        // NOT the workspace's name. The breadcrumb above already opens with it, and the
        // root rail is a list of the projects filed in it — so naming that list after the
        // person or the org printed the same word twice and answered "a list of what?"
        // with the one thing every row in it has in common.
        rootTitle: ROOT_TITLE,
      }),
    [groups, items, path, selection.focus],
  );

  // ── what the toolbar is pointed at ──────────────────────────────────────────

  const targets = React.useMemo(() => targetsOf(selection), [selection]);

  const targetLabel = React.useMemo(() => {
    if (targets.length === 0) return 'nothing';
    if (targets.length > 1) return `${targets.length} selected`;
    const only = targets[0]!;
    if (only.kind === 'group') {
      return groups.find((g) => g.id === only.id)?.name ?? 'a folder';
    }
    const item = items.find((r) => r.id === only.id);
    return item ? repoLabel(item) : 'a repository';
  }, [targets, groups, items]);

  /** Re-read the tree AND every open pane. The pair, because they answer the same question
   *  at two grains and a caller that moved a repository has changed both. */
  const refreshAll = React.useCallback(() => {
    tree.refresh();
    setPaneNonce((n) => n + 1);
  }, [tree]);

  /** Mirrors a queued run is inside RIGHT NOW — including the one a folder-wide run has
   *  reached, which is a question about the run's steps rather than about its scope. */
  const runningRepoIds = useRunningRepos(client, queue, runs);

  /**
   * THE RAIL FOLLOWS THE WALK, one repository at a time.
   *
   * The hand-off effect below fires per QUEUE ENTRY, and a run over a folder is a single
   * entry — so a batch of fourteen re-read the tree once, at the end, and all fourteen dots
   * went from running to their verdict together (Mike: "we need to finish each repo one at a
   * time ... update the status dot before moving onto the next repo").
   *
   * The runner is serial, and `useRunningRepos` already polls where it is. So the moment the
   * set of repositories it is inside CHANGES, the one it has just left has a new
   * `repo_states` row — which is the dot. Keyed on the SET rather than the poll: the poll is
   * every 750ms and the position is not.
   */
  const runningSig = [...runningRepoIds].sort().join(',');
  const lastRunningSig = React.useRef(runningSig);
  React.useEffect(() => {
    if (lastRunningSig.current === runningSig) return;
    lastRunningSig.current = runningSig;
    // The TREE only — see `paneNonce`.
    tree.refresh();
  }, [runningSig, tree]);

  // ── the queue ───────────────────────────────────────────────────────────────

  React.useEffect(() => {
    const head = queue[0];
    if (!head || !isFinished(runs, head)) return;
    setQueue((prev) => (prev[0] === head ? prev.slice(1) : prev));
    // A run that touched branches changed what the ladder says, so this is re-read at every
    // hand-off rather than once at the end. Within a single folder-wide run the walk effect
    // above is what keeps the rail moving; this is the boundary between one queued run and
    // the next.
    refreshAll();
  }, [queue, runs, refreshAll]);

  const busy = queue.length > 0;

  // The bar comes back when the last run leaves the queue — whether it succeeded, failed, or
  // was cancelled. Keyed on the LENGTH: the queue's contents change at every hand-off in a
  // batch, and the button should keep its spinner across all of them.
  React.useEffect(() => {
    if (queue.length === 0) setActiveAction(null);
  }, [queue.length]);

  // ── starting work ───────────────────────────────────────────────────────────

  const start = React.useCallback(
    async (
      /** The control that was pressed — see `activeAction`. */
      action: ActionId,
      operations: readonly {
        operation: Operation;
        environments?: Environment[];
      }[],
      /**
       * The rows to run over — the selection, unless a caller names them.
       *
       * The buttons never name them: what the toolbar acts on IS the selection, and letting
       * a control pass its own list is how a deploy lands somewhere the operator did not
       * highlight. The one caller that does is {@link autoStatus}, which is not a control at
       * all — it acts on the row that was just opened, and that row is not necessarily what
       * the toolbar is pointed at, because ticking a batch leaves `focus` free to move.
       */
      on: readonly NodeRef[] = targets,
    ) => {
      setError(null);
      if (on.length === 0) return;
      // Before the first await, so the pane is empty by the time this function yields.
      setPressed((n) => n + 1);
      const started: string[] = [];
      try {
        // Sequentially, and awaited: the backend queues by creation time, so posting these
        // in parallel would hand the runner an order the operator never chose. That is what
        // makes "prepare, then deploy to staging and production" mean those words in that
        // order rather than three runs racing.
        for (const step of operations) {
          for (const scope of on.map(scopeOf)) {
            const { runId } = await client.run({
              operation: step.operation,
              ...scope,
              ...(step.environments?.length
                ? { environments: step.environments }
                : {}),
            });
            started.push(runId);
          }
        }
      } catch (e) {
        setError((e as Error).message);
      }
      if (started.length > 0) {
        setQueue((prev) => [...prev, ...started]);
        setActiveAction(action);
        runs.refresh();
        // The panes find their run through the tree read, so refreshing it is what puts the
        // output of what was just started on the screen.
        refreshAll();
      }
    },
    [client, targets, runs, refreshAll],
  );

  const onRun = React.useCallback(
    (operation: Operation) => void start(operation as ActionId, [{ operation }]),
    [start],
  );

  const onDeploy = React.useCallback(
    ({ prepare, environments }: DeployRequest) => {
      // Each environment is a run of its own, in ladder order, and prepare goes first.
      // Splitting them here rather than sending one run with three environments keeps the
      // per-environment verdict separable in the log.
      const steps = [
        ...(prepare ? [{ operation: 'prepare' as const }] : []),
        ...environments.map((env) => ({
          operation: 'deploy' as const,
          environments: [env],
        })),
      ];
      return start('deploy', steps);
    },
    [start],
  );

  /** Registrations that have been started, into the queue every other run goes into. One
   *  helper because there are now two ways to start them — the wizard's one, and an import's
   *  nine — and they must land in exactly the same place. */
  const queueRegistrations = React.useCallback(
    (runIds: readonly string[]) => {
      if (runIds.length === 0) return;
      setQueue((prev) => [...prev, ...runIds]);
      setActiveAction('register');
      runs.refresh();
    },
    [runs],
  );

  /**
   * ADD WRITES THE CONFIGURATION DOWN, AND CREATES NOTHING.
   *
   * It used to be `register`, which queued a run that went out and made the deployment
   * repositories immediately — under whatever org the convention happened to land on, before
   * anyone had looked at it. That is not a mistake an unregister undoes: the repository on
   * the forge stays, in the wrong account, and the console's own row is the only half that
   * goes away.
   *
   * So the two halves are split. This one writes the rows synchronously with `registeredAt`
   * null, which is what puts the "not configured" mark on the repository in both the
   * Configure dialog and the tree; the operator then sets the org, the name and the
   * environments, and presses Provision — {@link onProvision} — which is the identical
   * `register` operation the queue would have run.
   *
   * Nothing is queued here, so nothing is added to {@link queue} and the toolbar does not
   * stand down: no run is in flight.
   */
  const onRegister = React.useCallback(
    async (bodies: readonly RegisterRequest[]) => {
      setPressed((n) => n + 1);
      // ONE AT A TIME, AND ONE REFRESH. The picker is multi-select — eleven repositories is
      // an ordinary press — but each configure is its own row insert, and the backend has no
      // batch form of it. Sequential rather than `Promise.all`: a failure then stops at the
      // first bad slug with everything before it written, instead of eleven parallel writes
      // whose partial outcome nobody can name. The tree read is paid once, at the end.
      for (const body of bodies) await client.configure(body);
      refreshAll();
    },
    [client, refreshAll],
  );

  /**
   * GO AND MAKE IT — the other half of Add, pressed once the configuration is right.
   *
   * The same `register` operation, against the `dev_repo` scope, which is what the wizard's
   * 202 used to queue. It is deliberately re-runnable: `register` adopts a repository that
   * already exists rather than rebuilding it, which is what makes the button read "Doctor"
   * once `registeredAt` is set — the same press, on a repository that has already had it.
   */
  const onProvision = React.useCallback(
    async (devRepoId: string) => {
      setPressed((n) => n + 1);
      const { runId } = await client.run({
        operation: 'register',
        scopeKind: 'dev_repo',
        scopeId: devRepoId,
      });
      queueRegistrations([runId]);
      refreshAll();
      // THE PRESS OWNS THE WHOLE RUN, not the 202 that queued it. Resolving here used to
      // mean the button reported success for a run that went on to 403 against the
      // deployment org, and the failure surfaced in the run queue BEHIND the modal the
      // button lives in — so from in front of that dialog, pressing it did nothing.
      // `settle` rejects with the run's own last error line, which is what the button
      // already knows how to draw.
      await settle(runId);
      // The second read is the one that matters to the dialog: `registeredAt` is written
      // by the run, so this is what turns Provision into Doctor without a manual refresh.
      refreshAll();
    },
    [client, queueRegistrations, refreshAll, settle],
  );

  /**
   * Run an import plan: the folders it needs, the registrations it asks for, the settings it
   * changes — {@link applyImport} walks them, this queues what walking them started.
   *
   * A REGISTRATION FROM A FILE IS A REGISTRATION. Each one is the same run `onRegister`
   * queues, so they go in the same queue: the rail spins, the bar stands down, and Cancel
   * stops the lot. An import that quietly started nine runs the console was not watching
   * would be the one place in this feature where work happens off-screen.
   *
   * A FAILURE HALFWAY STILL QUEUES WHAT WENT OUT. `ImportError` carries the partial result
   * for exactly this: the runs already started are on the forge whether or not the tenth
   * call succeeded, and the error is re-thrown afterwards so the dialog stays open on the
   * sentence that says which project it stopped at.
   */
  const onImport = React.useCallback(
    async (plan: ImportPlan, connectionId?: string) => {
      setPressed((n) => n + 1);
      try {
        const result = await applyImport({ client, plan, groups, connectionId });
        queueRegistrations(result.registered.map((r) => r.runId));
      } catch (e) {
        if (e instanceof ImportError) queueRegistrations(e.result.registered.map((r) => r.runId));
        refreshAll();
        throw e;
      }
      refreshAll();
    },
    [client, groups, queueRegistrations, refreshAll],
  );

  /**
   * Take a repository out again: unregister every mirror, retire the source row.
   *
   * ONE RUN over a `dev_repo` scope, not one per mirror. The backend expands the scope in
   * its own order and drops the source row as the last mirror goes, so a tab closed halfway
   * through cannot leave a repository half-removed — which a loop in this file could.
   *
   * It is queued exactly like every other run, so the rail spins, the bar stands down, and
   * Cancel stops it. Removing is a pipeline operation with a forge on the other end of it,
   * not a row deletion.
   */
  const onRemove = React.useCallback(
    async (devRepo: DevRepo) => {
      setPressed((n) => n + 1);
      const { runId } = await client.run({
        operation: 'unregister',
        scopeKind: 'dev_repo',
        scopeId: devRepo.id,
      });
      setQueue((prev) => [...prev, runId]);
      setActiveAction('unregister');
      runs.refresh();
      refreshAll();
    },
    [client, runs, refreshAll],
  );

  /**
   * Stop what is in flight.
   *
   * EVERY run in the queue, not just the one that is moving: Deploy queues a `prepare` and a
   * `deploy` per environment, and stopping only the running one would let the next start
   * half a second later — which reads, from the operator's side, as a Cancel that did not
   * work.
   *
   * ONLY WHAT WAS ACTUALLY STOPPED LEAVES THE QUEUE. A cancel that failed is a run still
   * walking branches, and dropping it here would hand the buttons back while it did — so the
   * failure keeps the bar down and says why, which is the state that matches the repository.
   */
  const onCancel = React.useCallback(async () => {
    setError(null);
    const stopped: string[] = [];
    try {
      for (const id of queue) {
        await client.cancelRun(id);
        stopped.push(id);
      }
    } catch (e) {
      setError((e as Error).message);
    }
    if (stopped.length === 0) return;
    setQueue((prev) => prev.filter((id) => !stopped.includes(id)));
    runs.refresh();
    // A cancelled deploy left some repositories carried and the rest not, and which is which
    // is the first thing anybody wants after pressing this.
    refreshAll();
  }, [client, queue, runs, refreshAll]);

  // ── folders ─────────────────────────────────────────────────────────────────

  const onCreateGroup = React.useCallback(
    async (parentId: string | null, name: string) => {
      await client.createGroup({ name, ...(parentId ? { parentId } : {}) });
      refreshAll();
    },
    [client, refreshAll],
  );

  const onRename = React.useCallback(
    async (id: string, name: string) => {
      await client.updateGroup(id, { name });
      refreshAll();
    },
    [client, refreshAll],
  );

  const onDelete = React.useCallback(
    async (ids: readonly string[]) => {
      // One at a time, first failure stops the rest — the same rule `onMove` follows, and
      // for the same reason: the backend refuses a folder that still holds anything, so a
      // batch of four where the second is non-empty must stop with two gone and say so,
      // not report a success it did not have.
      for (const id of ids) await client.deleteGroup(id);
      const gone = new Set(ids);
      // A deleted folder may be open. Truncating the path at the FIRST deleted ancestor puts
      // the operator in its surviving parent instead of on a rail of nothing.
      setPath((prev) => {
        const at = prev.findIndex((id) => gone.has(id));
        return at === -1 ? prev : prev.slice(0, at);
      });
      setSelection((prev) => ({
        ...prev,
        focus:
          prev.focus?.kind === 'group' && gone.has(prev.focus.id)
            ? null
            : prev.focus,
        // Ticks pointing at rows that no longer exist are ticks every other control is
        // still aimed at.
        checked: prev.checked.filter(
          (c) => !(c.kind === 'group' && gone.has(c.id)),
        ),
      }));
      refreshAll();
    },
    [client, refreshAll],
  );

  const onMove = React.useCallback(
    async (refs: readonly NodeRef[], destination: string | null) => {
      // One at a time, and the first failure stops the rest: a partial move the operator can
      // see half of is recoverable; one that reports success while three rows stayed put is
      // not. The error carries the backend's own sentence.
      for (const ref of refs) {
        if (ref.kind === 'group') {
          await client.updateGroup(ref.id, { parentId: destination });
        } else {
          await client.updateRepo(ref.id, { groupId: destination });
        }
      }
      setSelection((prev) => ({ ...prev, checked: [] }));
      refreshAll();
    },
    [client, refreshAll],
  );

  const onSaveSettings = React.useCallback(
    async (patches: RepoSettingsPatch[]) => {
      // Sequential for the same reason `onMove` is: a folder's save is a request per
      // repository, and a failure halfway through has to stop rather than leave the
      // remainder's outcome unknown.
      for (const patch of patches) {
        // ONE REQUEST PER REPOSITORY, not one per field: the route merges, and a second
        // PATCH for the name would be a second chance to half-apply a save the operator
        // pressed once. `body` is empty for a repository nothing was changed on, and that
        // one is skipped rather than sent as a no-op.
        const body: RepoPatch = {
          ...(patch.envBranches ? { envBranches: patch.envBranches } : {}),
          ...(patch.slug !== undefined ? { slug: patch.slug } : {}),
          ...(patch.displayName !== undefined ? { displayName: patch.displayName } : {}),
        };
        if (Object.keys(body).length > 0) await client.updateRepo(patch.repoId, body);
      }
      refreshAll();
    },
    [client, refreshAll],
  );

  /**
   * One organization's defaults, upserted.
   *
   * NO `refreshAll`, unlike every other write on this screen: the defaults row is not in the
   * tree and nothing drawn from the tree reads it. What a save does have to move is the
   * dialog that wrote it, and that dialog re-reads them itself — a tree read here would be a
   * round trip that changes nothing on screen.
   */
  const onSaveOrgDefaults = React.useCallback(
    async (org: string, patch: OrgDefaultsPatch) => {
      await client.setOrgDefaults(org, patch);
    },
    [client],
  );

  // ── rail interaction ────────────────────────────────────────────────────────

  const onSelect = React.useCallback((levelIndex: number, ref: NodeRef) => {
    setSelection((prev) => ({ ...prev, focus: ref }));
    setPath((prev) =>
      ref.kind === 'group'
        ? [...prev.slice(0, levelIndex), ref.id]
        : prev.slice(0, levelIndex),
    );
  }, []);

  const onClear = React.useCallback((levelIndex: number) => {
    setSelection((prev) => ({ ...prev, focus: null }));
    setPath((prev) => prev.slice(0, levelIndex));
  }, []);

  const onToggleCheck = React.useCallback((ref: NodeRef) => {
    setSelection((prev) => ({
      ...prev,
      checked: toggleChecked(prev.checked, ref),
    }));
  }, []);

  const onToggleSelecting = React.useCallback(() => {
    setSelection((prev) =>
      prev.selecting
        ? // Leaving select mode DROPS the batch. A hidden set of ticks that the buttons
          // still act on is the worst possible state for this console to be in.
          { ...prev, selecting: false, checked: [] }
        : {
            ...prev,
            selecting: true,
            // Seeded with the highlighted row, so turning batch mode on continues from
            // what was already chosen instead of throwing it away. Without this, Select
            // silently empties the selection the three buttons above are pointed at.
            checked: prev.focus ? [prev.focus] : [],
          },
    );
  }, []);

  // ── the rows the menu acts on ───────────────────────────────────────────────

  const soleTarget = targets.length === 1 ? targets[0]! : null;
  const soleGroup =
    soleTarget?.kind === 'group'
      ? (groups.find((g) => g.id === soleTarget.id) ?? null)
      : null;
  /** EVERY folder the menu is pointed at — Delete's targets. `soleGroup` stays what Rename
   *  and Settings use, because those genuinely are one-at-a-time. */
  const selectedGroups = React.useMemo(
    () =>
      targets.flatMap((t) =>
        t.kind === 'group' ? groups.filter((g) => g.id === t.id) : [],
      ),
    [targets, groups],
  );
  const focusedGroup =
    selection.focus?.kind === 'group'
      ? (groups.find((g) => g.id === selection.focus!.id) ?? null)
      : null;
  const selectedRepoId =
    selection.focus?.kind === 'repo' ? selection.focus.id : null;

  const buttons = React.useMemo(
    () =>
      toolbarState({
        selection,
        verbs,
        busy,
        hasGroups: groups.length > 0,
      }),
    [selection, verbs, busy, groups.length],
  );

  /**
   * OPENING A REPOSITORY READS IT, IF NOBODY HAS LOOKED IN AN HOUR.
   *
   * Mike: "clicking on a website in home should fire status if it's never been fired before,
   * or if the last check was more than an hour prior". A ladder is only worth anything if it
   * is current, and until now the only thing that made it current was an operator
   * remembering to press Status — so the usual state of this console was rows of readings
   * from whenever somebody last thought to take one, presented as if they were now.
   *
   * HERE, AND NOT IN `RepoView`, because this is the only layer that knows a single row was
   * opened. The pane is mounted once per repository inside a folder's stack, so the same
   * rule written there would fire forty reads the moment a folder is opened — which is the
   * rate limit that kept it manual in the first place. `focus` moving to ONE repository is
   * the click, and it is the whole trigger.
   *
   * Three things keep it to one read per repository per hour:
   *
   *  - `statusIsStale` on the state the tree ALREADY carries — no extra round trip to decide
   *    whether to spend a round trip, and a repository nobody has ever read (`state` null)
   *    is stale by definition, which is the case the operator named first.
   *  - `asked`, because the tree is re-read while the run is still in flight and the read it
   *    answers with is still the old one. Without this the second refresh would see a stale
   *    stamp and fire again, and so would the third.
   *  - `buttons.status.enabled`, which is the SAME answer the Status button gives, so a
   *    viewer who may not read these repositories does not silently start a run by browsing,
   *    and nothing is queued behind a run already in flight.
   */
  const asked = React.useRef(new Map<string, number>());
  React.useEffect(() => {
    if (!selectedRepoId || !buttons.status.enabled) return;
    const item = items.find((r) => r.id === selectedRepoId);
    if (!item) return;
    const now = Date.now();
    if (now - (asked.current.get(selectedRepoId) ?? -Infinity) < STATUS_MAX_AGE_MS)
      return;
    if (!statusIsStale(item.state, now)) return;
    asked.current.set(selectedRepoId, now);
    void start('status', [{ operation: 'status' }], [
      { kind: 'repo', id: selectedRepoId },
    ]);
  }, [selectedRepoId, items, buttons.status.enabled, start]);

  /** The gear menu, one per rail. Built here rather than in `toLevels` because every item
   *  in it is one of this component's own callbacks. */
  const railActions = React.useCallback(
    (groupId: string | null) => (
      <RailMenu
        state={buttons}
        groupId={groupId}
        selecting={selection.selecting}
        onNewGroup={(parentId) => setModal({ kind: 'newGroup', parentId })}
        onDelete={() =>
          selectedGroups.length > 0 &&
          setModal({
            kind: 'delete',
            ids: selectedGroups.map((g) => g.id),
            names: selectedGroups.map((g) => g.name),
          })
        }
        onRename={() =>
          soleGroup &&
          setModal({ kind: 'rename', id: soleGroup.id, name: soleGroup.name })
        }
        onMove={() => setModal({ kind: 'move', refs: [...targets] })}
        onToggleSelecting={onToggleSelecting}
        onSettings={() =>
          soleTarget && setModal({ kind: 'settings', ref: soleTarget })
        }
      />
    ),
    [
      buttons,
      targetLabel,
      soleTarget,
      soleGroup,
      selectedGroups,
      selection.selecting,
      targets,
      onToggleSelecting,
    ],
  );

  const levels = React.useMemo(
    () =>
      buildLevels({
        plans,
        selection,
        onSelect,
        onClear,
        onToggleCheck,
        railActions,
        runningRepoIds,
        busy: tree.loading,
      }),
    [
      plans,
      selection,
      onSelect,
      onClear,
      onToggleCheck,
      railActions,
      runningRepoIds,
      tree.loading,
    ],
  );

  /** What the settings dialog is looking at, re-derived from the live tree each render so a
   *  folder's contents stay current while it is open. */
  const settingsTarget = React.useMemo<SettingsTarget | null>(() => {
    if (modal.kind !== 'settings') return null;
    if (modal.ref.kind === 'repo') {
      const repo = items.find((r) => r.id === modal.ref.id);
      return repo ? { kind: 'repo', repo } : null;
    }
    const group = groups.find((g) => g.id === modal.ref.id);
    return group
      ? {
          kind: 'group',
          group,
          contents: descendantsOf(items, groups, group.id),
        }
      : null;
  }, [modal, items, groups]);

  /** A folder's pane: every repository under it, in the order a run over it walks them. */
  const focusedContents = React.useMemo(
    () => (focusedGroup ? descendantsOf(items, groups, focusedGroup.id) : []),
    [focusedGroup, items, groups],
  );

  /**
   * FAULTS ARE ALERTS, NOT FURNITURE (Mike). A failed read or a refused run used to print
   * the backend's own prose into a line above the toolbar. Two things were wrong with that:
   * it reads as a label on the bar rather than as something that went wrong, and `tree.error`
   * survives for as long as the poll keeps failing — so `Internal Server Error` became part
   * of the console's chrome, sitting over the controls until the server came back.
   *
   * RAISED ONCE PER DISTINCT FAULT. The poll re-sets the same message every few seconds, so
   * opening on truthiness alone would re-open this dialog under the operator's cursor for as
   * long as the outage lasted. `raised` holds the message already shown and is cleared the
   * moment a read succeeds — which is what lets the SAME message raise again after a
   * recovery, instead of being swallowed forever as a duplicate.
   */
  const problem = error ?? tree.error;
  const [alert, setAlert] = React.useState<string | null>(null);
  const raised = React.useRef<string | null>(null);
  // The live value of `problem`, read from a timer below rather than an effect dependency —
  // see `snoozeTimer`.
  const problemRef = React.useRef(problem);
  problemRef.current = problem;
  // How long a fault stays quiet after the operator dismisses it while it is still live. Not
  // zero: `raised.current` staying set is what stops a still-failing read from reopening the
  // SAME dialog on its very next poll, a beat after it was just closed. Not forever either:
  // "dismissed" must not become "silenced for the rest of the session" for a fault that is
  // still there — see the comment on `onConfirm` below, and the one above `raised`.
  const RERAISE_AFTER_MS = 60_000;
  const snoozeTimer = React.useRef<number | null>(null);
  React.useEffect(
    () => () => {
      if (snoozeTimer.current !== null) window.clearTimeout(snoozeTimer.current);
    },
    [],
  );
  React.useEffect(() => {
    // Truthiness, not `=== null`: `new Error()` carries an empty `message`, and the
    // catch that fills `error` copies it through unread. Keyed on null alone, that
    // empty string counts as a fault and raises a dialog with a title and no body —
    // strictly worse than the silence it replaced, since there is nothing in it to
    // act on and nothing to say what went wrong.
    if (!problem) {
      raised.current = null;
      return;
    }
    if (problem === raised.current) return;
    raised.current = problem;
    setAlert(problem);
  }, [problem]);

  return (
    <div className={`flex min-h-0 min-w-0 flex-1 flex-col ${className ?? ''}`}>
      <HierarchicalTopicDetail
        levels={levels}
        // The stack keeps memory outside React — pins, hover, and the outgoing detail pane it
        // crossfades from — and that memory is keyed by what we tell it. Unscoped, every
        // workspace's console is the same key, and the next workspace inherits this one's.
        surfaceScope={client.workspace ?? ''}
        rootLabel={rootLabel}
        // THE FOLDER'S NAME GOES IN THE PANE'S OWN TOP STRIP (Mike). It used to be a second
        // header inside the pane, sitting directly under the strip that carries the cover
        // control — two title bars stacked, the top one empty. This is the strip's whole
        // purpose, and it puts the name on the same line as the `«` that hides the rail,
        // where the reader is already looking to find out what they are looking at.
        detailTitle={
          !selectedRepoId && focusedGroup ? (
            <>
              <span className="font-semibold text-apt-gold">
                {focusedGroup.name}
              </span>{' '}
              <span className="text-apt-text-muted">
                {focusedContents.length === 1
                  ? '1 repository'
                  : `${focusedContents.length} repositories`}
              </span>
            </>
          ) : undefined
        }
        // What the repo pane actually needs: six ladder columns beside a commit subject.
        // Below this the ladder wraps and stops being readable as a ladder, which is the
        // whole point of the pane — so the rails give way first.
        minDetailWidth="32rem"
        toolbar={
          <Toolbar
            state={buttons}
            onRun={onRun}
            onDeploy={() => setModal({ kind: 'deploy' })}
            onCancel={() => void onCancel()}
            onConfigure={() => setModal({ kind: 'configure' })}
            onIntegrations={() => setModal({ kind: 'connections' })}
            active={activeAction}
          />
        }
      >
        {selectedRepoId ? (
          <RepoView
            // `pressed` in the key, not just the props: see `pressed` above — a press has to
            // BLANK this pane, and only a remount can throw away a log that has already
            // streamed.
            key={`${selectedRepoId}:${pressed}`}
            client={client}
            repoId={selectedRepoId}
            // Re-read after a run hand-off, a move, a rename, a settings save — see
            // `paneNonce`. NOT something derived from the rows: a status run changes the
            // ladder and leaves the row count identical, so a nonce built out of the rows
            // never moves and the pane sits on the ladder from before the run the operator
            // just watched finish.
            nonce={paneNonce}
            // And re-read on its OWN turn, so a repository inside a folder-wide run shows
            // its result the moment the runner leaves it rather than when the whole batch
            // ends.
            running={runningRepoIds.has(selectedRepoId)}
            // The only section on the screen, so it is the one an operator watches a run
            // in. A folder's stack sets this off — see `GroupDetailPane`.
            follow
          />
        ) : focusedGroup ? (
          <GroupDetailPane
            key={`${focusedGroup.id}:${pressed}`}
            client={client}
            title={focusedGroup.name}
            contents={focusedContents}
            nonce={paneNonce}
            // Each section re-reads on its own turn rather than all of them on every step —
            // see `paneNonce`.
            runningRepoIds={runningRepoIds}
          />
        ) : (
          <p className="p-6 text-sm text-apt-text-muted">
            Choose a repository to see where its branches are standing, or a
            folder to see what was last run across everything in it.
          </p>
        )}
      </HierarchicalTopicDetail>

      <NameDialog
        open={modal.kind === 'newGroup'}
        onClose={close}
        title="New folder"
        submitLabel="Create"
        onSubmit={(name) =>
          onCreateGroup(
            modal.kind === 'newGroup' ? modal.parentId : null,
            name,
          )
        }
      />

      <NameDialog
        open={modal.kind === 'rename'}
        onClose={close}
        title="Rename folder"
        initial={modal.kind === 'rename' ? modal.name : ''}
        submitLabel="Rename"
        onSubmit={(name) =>
          modal.kind === 'rename'
            ? onRename(modal.id, name)
            : Promise.resolve()
        }
      />

      <ConfirmDialog
        open={modal.kind === 'delete'}
        onClose={close}
        title={modal.kind === 'delete' && modal.ids.length > 1 ? 'Delete folders' : 'Delete folder'}
        body={
          modal.kind === 'delete'
            ? `${
                modal.names.length === 1
                  ? `Delete “${modal.names[0]!}”?`
                  : `Delete these ${modal.names.length} folders — ${modal.names
                      .map((n) => `“${n}”`)
                      .join(', ')}?`
              } A folder that still holds repositories or sub-folders cannot be deleted — move them out first.`
            : ''
        }
        confirmLabel="Delete"
        onConfirm={() =>
          modal.kind === 'delete' ? onDelete(modal.ids) : Promise.resolve()
        }
      />

      <MoveDialog
        open={modal.kind === 'move'}
        onClose={close}
        groups={groups}
        moving={modal.kind === 'move' ? modal.refs : []}
        movingLabel={targetLabel}
        onSubmit={(destination) =>
          modal.kind === 'move'
            ? onMove(modal.refs, destination)
            : Promise.resolve()
        }
      />

      <ConfigureDialog
        open={modal.kind === 'configure'}
        onClose={close}
        client={client}
        groups={groups}
        // The LIVE rows, so a register or a remove queued from inside it moves the list it
        // is showing as the run lands — the same refresh every other pane rides on.
        items={items}
        verbs={verbs}
        busy={busy}
        connections={connections}
        // The forge, read once at the mount rather than at every opening of this dialog.
        catalogue={catalogue}
        onProvision={onProvision}
        // The wizard's way out to the accounts it registers against. Swapping the modal
        // rather than nesting one: they are siblings, and two stacked dialogs over a console
        // is a stack an operator has to unwind twice to get back to the tree.
        onManageConnections={() => setModal({ kind: 'connections' })}
        onRegister={onRegister}
        onRemove={onRemove}
        onSaveSettings={onSaveSettings}
        onSaveOrgDefaults={onSaveOrgDefaults}
        onImport={onImport}
      />

      {/* The forge accounts every run goes out over. Mounted BESIDE Configure rather than
          inside it — see the `connections` arm of `Modal` above. */}
      <ConnectionsDialog
        open={modal.kind === 'connections'}
        onClose={close}
        client={client}
        onChanged={onConnectionsChanged}
      />

      <DeployDialog
        open={modal.kind === 'deploy'}
        onClose={close}
        targetLabel={targetLabel}
        onSubmit={onDeploy}
      />

      <SettingsDialog
        open={modal.kind === 'settings'}
        target={settingsTarget}
        onClose={close}
        onSave={onSaveSettings}
      />

      <AlertModal
        open={Boolean(alert)}
        tone="error"
        title="shipr hit a problem"
        description={alert ?? ''}
        onConfirm={() => {
          setAlert(null);
          // Dismissing hides the modal, not the fault. `raised.current` is deliberately LEFT
          // set — see the effect above — so an outage that is still going does not vanish
          // with no signal at all for the rest of the session (the case the removed inline
          // `<ErrorText>` used to cover; see the comment at the top of this block). Instead
          // the SAME fault is allowed to raise again once the snooze runs out, and only if it
          // is still the live one: a different fault already got its own dialog through the
          // effect above, and a fault that cleared needs no reminder.
          const dismissed = raised.current;
          if (!dismissed) return;
          if (snoozeTimer.current !== null) window.clearTimeout(snoozeTimer.current);
          snoozeTimer.current = window.setTimeout(() => {
            snoozeTimer.current = null;
            if (raised.current === dismissed && problemRef.current === dismissed) {
              setAlert(dismissed);
            }
          }, RERAISE_AFTER_MS);
        }}
      />
    </div>
  );
}
