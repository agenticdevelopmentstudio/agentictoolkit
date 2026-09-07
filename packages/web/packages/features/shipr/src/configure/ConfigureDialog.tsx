'use client';

import * as React from 'react';

import { StackLevels, StandaloneRailHost } from '@agentic-toolkit/resource';
import type { TopicLevel } from '@agenticdevelopertoolkit/ui/blocks';
import { TopicSelectHint } from '@agenticdevelopertoolkit/ui/blocks';
import { AlertModal } from '@agenticdevelopertoolkit/ui/components/alert-modal';
import { Button } from '@agenticdevelopertoolkit/ui/components/button';
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@agenticdevelopertoolkit/ui/components/dialog';
import { Download, Minus, Plus, TriangleAlert, Upload } from 'lucide-react';

import { buildDocument } from '../exchange/document';
import { downloadDocument } from '../exchange/files';
import { ImportDialog } from '../exchange/ImportDialog';
import type { ImportPlan } from '../exchange/plan';
import { nameOf, ownerOf } from '../forge/existence';
import type { ForgeCatalogue } from '../forge/useForgeCatalogue';
import { SettingsForm, type RepoSettingsPatch } from '../settings/SettingsForm';
import { toolbarState, type ButtonState } from '../toolbar/actions';
import { ConfirmDialog } from '../toolbar/dialogs';
import { RegisterWizard } from '../toolbar/RegisterWizard';
import { OrgDefaultsForm } from './OrgDefaultsForm';
import type { Selection } from '../selection';
import type {
  AccessVerb,
  DevRepo,
  ForgeConnection,
  Group,
  OrgDefaults,
  OrgDefaultsPatch,
  RegisterRequest,
  RepoItem,
} from '../types';
import type { ShiprClient } from '../client';

/**
 * Configuration: the repositories this console knows about, and what each one is made of.
 *
 * ONE PLACE, because they are one subject. Registering used to be an entry in a folder's
 * gear menu, unregistering another one two lines below it, and a repository's settings a
 * third — three doors onto one question ("what is registered here, and how"), none of which
 * showed the other two.
 *
 * IT IS A DIALOG, NOT A PAGE. Configuration is not the answer to "how is this fleet doing",
 * which is the whole of the console behind it; opening this is a deliberate detour, and it
 * ends by closing. A page would have to be navigated to and back from, and the rail behind
 * it — the folders, the selected repository, the run in flight — would have to be rebuilt
 * on return.
 *
 * IT HAS ITS OWN RAIL. {@link StandaloneRailHost} rather than `RailHostBoundary`: the
 * boundary self-hosts only when nothing is hosting above it, and a dialog renders inside the
 * page, so the boundary would find the site shell's registry and publish these levels into
 * the rail BEHIND the dialog — where they would draw under it and survive its close. A
 * dialog's stack is always its own.
 *
 * THE BAR SITS ABOVE THE RAIL, not inside it. Add and Remove act on the repository list, but
 * they are the dialog's controls in the same way the console's toolbar is the console's —
 * and hung off the level as its `headerSlot` they were a second toolbar under a second
 * title, inside a column narrow enough to crowd three buttons. It also cost a lie: the rail
 * host deliberately keys re-registration on a level's PLAIN fields and never its React
 * nodes, so a bar whose buttons had just greyed out sat stale until something unrelated
 * moved, and the level had to carry a `busy` it did not otherwise need to force the issue.
 *
 * INTEGRATIONS IS NOT IN HERE AT ALL any more — it is `ConnectionsDialog`, opened from the
 * console's own toolbar. It had been a button on this bar, and that was wrong twice over.
 * Structurally, a pane published into this rail while the repository list is unselected is
 * sliced off before it can draw, which took the only "Add integration" button in the feature
 * with it. And in meaning: filed under a bar that says Add / Remove / Import / Export over a
 * list of repositories, the forge accounts read as a property of that list. They are not.
 * The list belongs to this workspace; the accounts belong to the ecosystem, and every
 * workspace on it goes out over the same ones.
 *
 * What survives of the connection here is one-way and read-only: {@link connections} is
 * passed down so the register wizard and the importer can OFFER a connection to register
 * against, and {@link onManageConnections} is the way out to the dialog that manages them —
 * the console swaps this dialog for that one, rather than stacking a third modal.
 *
 * THE RAIL IS TWO LEVELS, ORGANIZATION THEN REPOSITORY, because the deployment decisions on
 * this screen are made per organization and not per repository. One flat list of
 * `owner/name` said the owner eleven times down the left-hand side and still gave nowhere to
 * hang "what does a new repository in THIS account get" — so the owner became the level
 * above, its name is said once at the top of the column, and the repositories under it are
 * named the way a person in that account would name them. It is also what gives the org
 * defaults a home: they are the detail pane of the organization level, reached the same way
 * anything else on this screen is — by selecting the thing they are about.
 *
 * NOTHING HERE PROVISIONS. Add writes a row and stops; the account's defaults re-aim rows and
 * stop; the amber mark on an unconfigured name is what says the forge has not been touched
 * yet. Making anything is Provision's, in the detail pane, one repository at a time — which
 * is the whole reason the deployment organization is decided on a screen that cannot
 * accidentally create a repository in the wrong one.
 */

const ORGS_LEVEL_ID = 'shipr-configure-orgs';
const REPOS_LEVEL_ID = 'shipr-configure-repos';

/** The `<form>` the footer's OK submits. The boxes are a pane in the middle of this dialog
 *  and OK is at the bottom of it, which is what `form=` on a button outside the form is for. */
const SETTINGS_FORM_ID = 'shipr-configure-settings';

/** The same, for the organization pane. A SECOND id and not a shared one: both panes are
 *  mounted at different times and the footer picks between them by which level is open, so a
 *  single id would make "which form does OK submit" a question about render order. */
const ORG_FORM_ID = 'shipr-configure-org-defaults';

/** A source repository and everything cut from it — the row, and what its settings write to. */
interface Row {
  devRepo: DevRepo;
  mirrors: RepoItem[];
}

/**
 * ADDED BUT NOT YET MADE — the state Add now leaves every repository in.
 *
 * `registeredAt` is set by the run that creates or adopts the deployment repository, so a
 * null one is a row that describes a repository the forge has never been asked about. That
 * is a perfectly good state to sit in — it is the point of configuring first — but it is not
 * a state to sit in ACCIDENTALLY, and nothing else on the screen distinguishes it from a
 * repository that is fully up. Any mirror missing it marks the row: a monorepo whose second
 * shard was never provisioned is as unprovisioned as one whose first was.
 */
function unconfigured(row: Row): boolean {
  return row.mirrors.some((m) => m.registeredAt === null);
}

export interface ConfigureDialogProps {
  open: boolean;
  onClose: () => void;
  /** The wizard's two reads and its register. Nothing else here touches the client — the
   *  console owns every write, so a failed one reaches the same error line as a toolbar run. */
  client: ShiprClient;
  groups: readonly Group[];
  /** The live tree's mirrors. The rows are derived from these, so a register or a remove
   *  that lands while this is open moves the list under the operator. */
  items: readonly RepoItem[];
  /** `undefined` while the console's tree read is still out — passed through rather than
   *  defaulted, so this dialog's buttons say "still reading" where the toolbar's do. */
  verbs: readonly AccessVerb[] | undefined;
  /** A run is in flight from this console. Add and Remove stand down; settings do not — see
   *  `configure` in `toolbarState`. */
  busy?: boolean;
  /** The forge accounts the IMPORTER may register against. Read-only here — this dialog no
   *  longer manages them; see {@link onManageConnections}. The Add picker no longer reads
   *  this at all: it reads {@link catalogue}, which is these accounts plus what is in them
   *  plus why any one of them could not be read. */
  connections?: readonly ForgeConnection[];
  /** Every account shipr reaches and what is in them, read once when the console came up and
   *  held across every opening of this dialog. The Add picker is a view of it, and the
   *  detail pane answers "is that deployment repository already there" off it rather than
   *  by asking the forge again. */
  catalogue: ForgeCatalogue;
  /** Leave for the Integrations dialog, because the operator has just found that
   *  {@link connections} is empty or missing the account they want. The host is expected to
   *  CLOSE this dialog and open that one — they are siblings on the console, not nested, so
   *  there is no stack to come back to. Optional: a host with nowhere to send them simply
   *  does not offer the link. */
  onManageConnections?: () => void;
  /** CONFIGURE, not provision, and a BATCH: the picker is multi-select, so one press is
   *  however many repositories were ticked. Each becomes a row with nothing made on the
   *  forge — see the note at the top of this file. */
  onRegister: (bodies: readonly RegisterRequest[]) => Promise<void>;
  /** Unregister every mirror and retire the source row. One call, not one per mirror: the
   *  backend expands a `dev_repo` scope itself, and a browser tab closed halfway through a
   *  loop in this file would strand the rest. */
  onRemove: (devRepo: DevRepo) => Promise<void>;
  onSaveSettings: (patches: RepoSettingsPatch[]) => Promise<void>;
  /** Upsert one organization's defaults. Optional: a host that has not wired it simply does
   *  not draw the gear, rather than drawing a menu whose one entry cannot save. */
  onSaveOrgDefaults?: (org: string, patch: OrgDefaultsPatch) => Promise<void>;
  /** Make (or repair) what the configuration describes, for one source repository. The one
   *  control on this screen that touches the forge, and it is deliberately per-repository:
   *  see `ProvisionButton` in the settings pane. */
  onProvision?: (devRepoId: string) => Promise<void> | void;
  /** Run an import plan. The plan is built here (it is a comparison against the rows this
   *  dialog is already showing); the writes it describes belong to the console, like every
   *  other one on this screen. */
  onImport: (plan: ImportPlan, connectionId?: string) => Promise<void>;
}

export function ConfigureDialog(props: ConfigureDialogProps): React.ReactElement {
  const { open, onClose } = props;
  return (
    <Dialog open={open} onOpenChange={(next) => !next && onClose()}>
      {/* Wide and tall, because it holds a rail and a detail pane rather than a form. The
          height is fixed rather than fitted: the repository list grows with the fleet, and a
          dialog that changes height when a register lands is a dialog whose buttons move
          under the pointer.

          `max-w-7xl` and not `5xl`: there are THREE columns now — organizations, their
          repositories, and the settings for one — and at the old width the third was narrow
          enough to wrap `owner/name-deployment` mid-slug in the field that sets it. */}
      <DialogContent className="flex h-[80vh] max-w-7xl flex-col gap-4">
        <DialogHeader>
          <DialogTitle>Configure</DialogTitle>
        </DialogHeader>
        {/* MOUNTED ONLY WHILE OPEN. A dialog stays mounted when it closes, and everything
            below this line has a cost that must not be paid by a console nobody has opened
            it from: the rail host is a registry, and the levels it publishes are levels. It
            also means each opening starts with nothing selected, which is the only honest
            state for a screen whose subject is whatever the operator is about to choose. */}
        {open ? <ConfigureBody {...props} /> : null}
      </DialogContent>
    </Dialog>
  );
}

function ConfigureBody({
  onClose,
  client,
  groups,
  items,
  verbs,
  busy = false,
  connections,
  catalogue,
  onManageConnections,
  onRegister,
  onRemove,
  onSaveSettings,
  onSaveOrgDefaults,
  onProvision,
  onImport,
}: ConfigureDialogProps): React.ReactElement {
  const [selectedOrg, setSelectedOrg] = React.useState<string | null>(null);
  const [selectedId, setSelectedId] = React.useState<string | null>(null);
  const [wizard, setWizard] = React.useState(false);
  const [importing, setImporting] = React.useState(false);

  /** Why the bar just refused a press — see `BarButton`. Null when nothing was refused. */
  const [refused, setRefused] = React.useState<string | null>(null);

  /** The row a Remove press is waiting on an answer about. Null when nothing was pressed. */
  const [removing, setRemoving] = React.useState<Row | null>(null);

  /**
   * Unregister a repository, once the operator has said so.
   *
   * The press does not do this — it opens {@link ConfirmDialog}, and this is what the
   * confirm runs. Removing is destructive from where the operator stands: they are pressing
   * it on their own repository, and it retires the row every mirror hangs off. That the
   * forge keeps the repositories, their branches and their protection rules untouched is an
   * argument about the blast radius, not about whether to ask.
   *
   * What it is NOT is a type-to-confirm (Mike: "it doesn't need to have the dangerzone
   * confirmation dialog"). One press of an ordinary confirm, the same one the folder Delete
   * asks — the correction was about the dialog's form, never about whether to have one.
   */
  const remove = React.useCallback(
    async (row: Row) => {
      await onRemove(row.devRepo);
      // The row is gone, so the selection that was showing it has to go too.
      setSelectedId(null);
    },
    [onRemove],
  );

  /**
   * One row per SOURCE repository, sorted by slug.
   *
   * The tree is a list of mirrors, and a monorepo of separately-deployed directories is
   * several of them behind one `.shipr`. Registering, removing and the branch names all
   * belong to the source, so this screen is a list of sources — the mirrors ride along on
   * the row, because they are what the environment boxes actually write to.
   */
  const rows = React.useMemo<Row[]>(() => {
    const byId = new Map<string, Row>();
    for (const item of items) {
      if (!item.devRepo) continue;
      const existing = byId.get(item.devRepo.id);
      if (existing) existing.mirrors.push(item);
      else byId.set(item.devRepo.id, { devRepo: item.devRepo, mirrors: [item] });
    }
    const all = [...byId.values()];
    for (const row of all) {
      row.mirrors.sort((a, b) => a.shard.localeCompare(b.shard));
    }
    return all.sort((a, b) => a.devRepo.slug.localeCompare(b.devRepo.slug));
  }, [items]);

  /**
   * The rows grouped by the account they live in — the rail's root level.
   *
   * Derived from the ROWS and not from the catalogue, because this level is a list of what
   * is registered, not of what shipr can see. An account with an installation and nothing
   * registered from it belongs in the Add picker, which is a view of the catalogue; putting
   * it here would be a folder that opens on an empty list and cannot be acted on.
   */
  const orgs = React.useMemo(() => {
    const byOrg = new Map<string, Row[]>();
    for (const row of rows) {
      const login = ownerOf(row.devRepo.slug);
      const bucket = byOrg.get(login);
      if (bucket) bucket.push(row);
      else byOrg.set(login, [row]);
    }
    return [...byOrg.entries()]
      .map(([login, orgRows]) => ({ login, rows: orgRows }))
      .sort((a, b) => a.login.localeCompare(b.login));
  }, [rows]);

  /** Re-derived from the live rows every render, so an account whose last repository is
   *  removed while it is open takes the selection with it rather than leaving a level whose
   *  subject no longer exists. */
  const activeOrg = orgs.find((o) => o.login === selectedOrg) ?? null;

  /** Same, one level down — and scoped to the open account, so a stale id from the previous
   *  one cannot select through it. */
  const selected = activeOrg?.rows.find((r) => r.devRepo.id === selectedId) ?? null;

  /**
   * The stored per-organization defaults, read once per opening of this dialog.
   *
   * ON THIS SCREEN AND NOT IN THE CONSOLE, unlike the catalogue above it: the catalogue is
   * a forge read worth prefetching and holding, this is one small row per account. `reload`
   * is what a save calls, so the pane that wrote them re-seeds from what was written rather
   * than from what was read before it.
   *
   * `orgDefaultsRead` IS THE THIRD STATE, and the pane may not draw without it. The form
   * seeds its draft ONCE, on mount, and an organization can now be selected before this read
   * lands — so a pane mounted early would seed from `undefined`, which is the same seed as
   * "nobody has set any", and the footer's OK would then overwrite a stored row with the
   * convention and re-aim every unprovisioned deployment repository in the account to match.
   * A failed read counts as settled: `orgDefaultsError` is the form's own refusal, and it
   * says so rather than silently drawing the convention.
   */
  const [orgDefaults, setOrgDefaults] = React.useState<readonly OrgDefaults[]>([]);
  const [orgDefaultsError, setOrgDefaultsError] = React.useState<string | null>(null);
  const [orgDefaultsRead, setOrgDefaultsRead] = React.useState(false);

  const reloadOrgDefaults = React.useCallback(async () => {
    try {
      const res = await client.orgDefaults();
      setOrgDefaults(res.orgDefaults);
      setOrgDefaultsError(null);
    } catch (e) {
      setOrgDefaultsError((e as Error).message);
    } finally {
      setOrgDefaultsRead(true);
    }
  }, [client]);

  React.useEffect(() => {
    void reloadOrgDefaults();
  }, [reloadOrgDefaults]);

  /**
   * The account's own settings are what the detail pane should be showing.
   *
   * An account is open, nothing under it is selected, the host wired the save, and the read
   * that seeds the form has settled. All four, because each one is a different way for the
   * pane to be wrong: no account is the empty hint, a selected repository is the repository's
   * own settings, an unwired save is a form whose OK cannot write, and an unsettled read is
   * the overwrite described above.
   */
  const orgPane =
    activeOrg !== null &&
    selected === null &&
    onSaveOrgDefaults !== undefined &&
    orgDefaultsRead;

  /**
   * WHAT REMOVE ACTS ON, in the vocabulary `toolbarState` already speaks.
   *
   * The buttons here ask the identical question the toolbar and the gear menu ask — may
   * this caller do it, and if not why — so they read the identical function rather than
   * re-deriving "is something selected" a third time. The targets are the selected
   * repository's MIRRORS, because those are the rows an unregister walks; a batch rather
   * than a focus, because a source with three shards is three of them.
   */
  const selection = React.useMemo<Selection>(
    () => ({
      focus: null,
      selecting: true,
      checked: (selected?.mirrors ?? []).map((m) => ({
        kind: 'repo' as const,
        id: m.id,
      })),
    }),
    [selected],
  );

  const buttons = React.useMemo(
    () => toolbarState({ selection, verbs, busy, hasGroups: groups.length > 0 }),
    [selection, verbs, busy, groups.length],
  );

  const orgLevel = React.useMemo<TopicLevel>(
    () => ({
      id: ORGS_LEVEL_ID,
      title: 'Organizations',
      itemNoun: 'organization',
      leadsTo: 'list',
      items: orgs.map((org) => ({
        id: org.login,
        label: org.login,
        sublabel: `${org.rows.length} ${org.rows.length === 1 ? 'repository' : 'repositories'}`,
        // The mark rides up the tree: an account with an unconfigured repository under it is
        // an account with something to answer, and the level that hides it must say so or
        // the warning is only visible to whoever already opened the right folder.
        blocked: org.rows.some(unconfigured),
      })),
      selectedId: selectedOrg,
      // NO AUTO-SELECT, even for the workspace with exactly one account — and it is worth
      // saying why, because "one account means no choice to make" is the obvious argument for
      // opening it for them. The rail's `defaultSelectedId` is armed once per SURFACE, and a
      // surface outlives this dialog: it is held in a module-scope map keyed by the root
      // level, for the life of the page. This dialog is deliberately unmounted when it closes,
      // so the default would fire on the first opening and on no later one — the repositories
      // appearing by themselves once and then never again, from a control the operator cannot
      // see. A level that always has to be pressed is a smaller cost than one that behaves
      // differently the second time.
      onSelect: (id: string) => {
        setSelectedOrg(id);
        // The repository ids under the previous account mean nothing under this one, and a
        // selection that survives the switch would leave the detail pane showing a
        // repository the open level does not contain.
        setSelectedId(null);
      },
      onClear: () => {
        setSelectedOrg(null);
        setSelectedId(null);
      },
      emptyLabel: 'Nothing is registered yet — Add is how one gets here.',
      // A spinner, and only that now the bar is not hung off this level: the console
      // re-reads the tree at every hand-off while a run walks, and these rows are exactly
      // what an unregister removes.
      busy,
    }),
    [orgs, selectedOrg, busy],
  );

  const repoLevel = React.useMemo<TopicLevel | null>(() => {
    if (!activeOrg) return null;
    return {
      id: REPOS_LEVEL_ID,
      // The account's name, said ONCE at the top of the column instead of once per row.
      //
      // NO GEAR HERE ANY MORE (Mike: "move the org related settings to org topic list"). It
      // was a `titleActions` menu with one entry, and its entry opened a Dialog on top of
      // this Dialog — a modal over a modal, with two sets of OK/Cancel on screen at once,
      // hung off the title of the level BELOW the one whose subject it was. The account's
      // settings now draw where every other subject on this screen draws: in the detail
      // pane, when the account is what the rail has selected — which is also what makes them
      // reachable before a repository is chosen rather than only after one is.
      title: activeOrg.login,
      railLabel: 'Repositories',
      itemNoun: 'repository',
      items: activeOrg.rows.map((row) => ({
        id: row.devRepo.id,
        // WITHOUT THE ORGANIZATION IN IT: the column is already that account. `displayName`
        // wins where it is set, because it is the name the operator chose and the one the
        // console's own tree shows on /home.
        label: row.devRepo.displayName || nameOf(row.devRepo.slug),
        sublabel:
          row.mirrors.length === 1
            ? row.mirrors[0]!.slug
            : `${row.mirrors.length} deployment repositories`,
        // Added, not provisioned. Both marks say it — the icon is legible at a glance, the
        // amber dot carries the "needs attention" the icon cannot say to a screen reader.
        blocked: unconfigured(row),
        icon: unconfigured(row) ? (
          <TriangleAlert size={16} className="text-apt-orange" aria-hidden />
        ) : undefined,
      })),
      selectedId,
      onSelect: (id: string) => setSelectedId(id),
      onClear: () => setSelectedId(null),
      emptyLabel: 'Nothing is registered from this organization.',
      busy,
    };
  }, [activeOrg, selectedId, busy]);

  return (
    <>
      {/*
        ONE PANE, ONE THING IN IT. Registering used to open as a Dialog on top of this one —
        a popup over a popup, whose first screen was mostly prose explaining why the browser
        underneath it was empty. But registering is not an interruption of the repository
        list; it is the thing that ADDS to it, so it draws where the list draws, and the
        browser is what is on screen the moment Add is pressed.

        The bar and the footer go with the list. Add/Remove/Import/Export act on a list that
        is not being shown, and this dialog's own OK/Cancel would sit under the wizard's
        Back/Cancel/Next saying something different by two buttons that look the same. The
        wizard owns its own way out, and both of its exits — Cancel, and a completed
        registration — land back on the list.
      */}
      {wizard ? (
        <div className="flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden rounded border border-apt-border p-3">
          <RegisterWizard
            open={wizard}
            onClose={() => setWizard(false)}
            /* The prefetched catalogue, not the client: the picker makes no request at all
               now, which is what lets it open on a full list instead of a spinner. */
            catalogue={catalogue}
            registeredSlugs={rows.map((r) => r.devRepo.slug)}
            /* Closes the wizard on the way out. The console is about to swap this whole dialog
               for Integrations, so leaving the wizard open would leave it mounted behind a
               dialog it can no longer be seen from — and showing again, mid-form, if the
               operator came back to Configure. */
            onManageConnections={
              onManageConnections
                ? () => {
                    setWizard(false);
                    onManageConnections();
                  }
                : undefined
            }
            onSubmit={onRegister}
          />
        </div>
      ) : (
        <>
          {/* ABOVE the rail, and the dialog's bar rather than the list's — see the note at the
              top of this file. Every button on it acts on the repository list, which is what
              makes it the right bar for them and was what made it the wrong bar for the forge
              accounts that used to sit on its right-hand end. */}
          <div className="flex items-center gap-2">
            <BarButton
              label="Add"
              icon={<Plus />}
              state={buttons.register}
              onClick={() => setWizard(true)}
              onRefused={setRefused}
            />
            <BarButton
              label="Remove"
              icon={<Minus />}
              state={buttons.unregister}
              destructive
              onClick={() => selected && setRemoving(selected)}
              onRefused={setRefused}
            />

            {/* THE FLEET AS A FILE, both directions, on the bar that already owns the repository
                list — because that list is exactly what the file holds. Import is gated by the
                same permission as Add, since every `+` row in its plan IS an Add. Export is not
                gated at all: it writes nothing, and it is built from rows already on the screen,
                so anyone who can read this list can already read everything in the file. */}
            <BarButton
              label="Import"
              icon={<Upload />}
              state={buttons.register}
              onClick={() => setImporting(true)}
              onRefused={setRefused}
            />
            <BarButton
              label="Export"
              icon={<Download />}
              state={{ enabled: items.length > 0, reason: 'Nothing is registered yet.' }}
              onClick={() => downloadDocument(buildDocument({ groups, items }))}
              onRefused={setRefused}
            />
          </div>

          <div className="flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden rounded border border-apt-border">
            <StandaloneRailHost>
              {/* The repository level exists only while an account is open, so the array is
                  one long or two. A level published for a closed account would be a column
                  whose title names nothing. */}
              <StackLevels levels={repoLevel ? [orgLevel, repoLevel] : [orgLevel]}>
                <DetailPane
                  selected={selected}
                  catalogue={catalogue}
                  onSaveSettings={onSaveSettings}
                  onProvision={onProvision}
                  onSaved={onClose}
                  orgOpen={activeOrg !== null}
                  /* An ordinary button (Mike: "add a remove button to the sites details
                     pane", and "the remove button needs to not look like some weird ui you
                     invented") — the same shape as every other button in this dialog and the
                     same `destructive` variant the rest of the app uses for the same job, both
                     of which are now what `variant` and `size` say.

                     IT IS A BarButton FOR THE CLICK, NOT FOR THE LOOK. It reads the same
                     `buttons.unregister` gate the bar's copy reads, and that gate is
                     three-state: while the workspace's verbs are still being read it is
                     `pending`, which is "not yet" and not "no". Written as a `<Button
                     disabled>` this swallowed a press made in that window — no dialog, no
                     refusal, nothing — and then went live a moment later with the operator
                     believing they had already pressed it. BarButton arms that press and
                     spends it on whatever the answer turns out to be. */
                  remove={
                    <BarButton
                      label="Remove"
                      state={buttons.unregister}
                      variant="destructive"
                      size="default"
                      title={buttons.unregister.reason}
                      onClick={() => selected && setRemoving(selected)}
                      onRefused={setRefused}
                    />
                  }
                  orgForm={
                    orgPane && activeOrg && onSaveOrgDefaults ? (
                      <OrgDefaultsForm
                        // Re-seeded per account, the same way the repository form is re-seeded
                        // per repository: the draft is taken once on mount, so switching
                        // accounts without a remount would show one account's defaults under
                        // another one's title.
                        key={activeOrg.login}
                        org={activeOrg.login}
                        defaults={orgDefaults.find((d) => d.org === activeOrg.login)}
                        defaultsError={orgDefaultsError}
                        rows={activeOrg.rows}
                        catalogue={catalogue}
                        formId={ORG_FORM_ID}
                        onSaveDefaults={async (org, patch) => {
                          await onSaveOrgDefaults(org, patch);
                          // Read back rather than patching the held copy: the row the server
                          // stored is what the next seeding has to start from, and it is the
                          // server that fills in the fields this form did not send.
                          await reloadOrgDefaults();
                        }}
                        onApply={onSaveSettings}
                        onSaved={onClose}
                      />
                    ) : null
                  }
                />
              </StackLevels>
            </StandaloneRailHost>
          </div>

          {/*
            OK AND CANCEL MEAN SOMETHING HERE, which is the only reason they are worth drawing.
            Everything else this dialog does is committed by its own control the moment it is
            pressed — Add walks a wizard, Remove unregisters — and none of it is undone by
            closing. The environment boxes are the one thing held in hand: OK submits
            them and closes, Cancel closes and drops them, which is what a modal's two buttons
            are expected to mean and what a lone corner "×" could not say.

            `form=` rather than a click handler, and only while a pane with a form is showing: the
            boxes live in a pane in the middle of this dialog, so the browser's own mechanism for
            submitting a form from outside it is the whole implementation — the alternative is
            lifting every checkbox up here so the footer can build the patch itself, and then two
            surfaces compute the same diff. With nothing selected there is no form and no draft,
            and OK is simply the way out.

            THREE BRANCHES, because there are now two panes that hold a draft. A repository's
            settings submit `SETTINGS_FORM_ID`; an account's defaults submit `ORG_FORM_ID`, which
            is what the organization's own settings became when they left the gear. They are
            never both showing — `selected` is only ever non-null under an open account, and the
            org pane is what draws when nothing under it is chosen — so the order here is a
            statement of that, not a precedence rule.
          */}
          <DialogFooter>
            <Button type="button" variant="ghost" onClick={onClose}>
              Cancel
            </Button>
            {selected ? (
              <Button type="submit" form={SETTINGS_FORM_ID}>
                OK
              </Button>
            ) : orgPane ? (
              <Button type="submit" form={ORG_FORM_ID}>
                OK
              </Button>
            ) : (
              <Button type="button" onClick={onClose}>
                OK
              </Button>
            )}
          </DialogFooter>
        </>
      )}

      <ImportDialog
        open={importing}
        onClose={() => setImporting(false)}
        groups={groups}
        items={items}
        connections={connections}
        onImport={onImport}
      />

      {/* ONE confirm for BOTH Remove buttons — the bar's and the detail pane's — because
          they are one verb pressed from two places, and a second copy is a second chance for
          the two to answer differently. The slug is in the question: this dialog is opened
          over a list, and "Remove the repository?" names nothing the operator can check. */}
      <ConfirmDialog
        open={removing !== null}
        onClose={() => setRemoving(null)}
        title="Remove repository"
        body={
          removing
            ? `Remove ${removing.devRepo.slug}? Its ${
                removing.mirrors.length === 1
                  ? 'deployment repository is'
                  : `${removing.mirrors.length} deployment repositories are`
              } unregistered and the row retires. Nothing on the forge is deleted — the repositories, their branches and their protection rules stay exactly as they are, so registering it again adopts what is there.`
            : ''
        }
        confirmLabel="Remove"
        onConfirm={() => (removing ? remove(removing) : Promise.resolve())}
      />


      {/* The bar's refusal, said out loud — the click a greyed-out control used to swallow.
          `tone="info"` and not `"error"`: nothing went wrong, the operator asked for
          something this workspace does not let them have. */}
      <AlertModal
        open={refused !== null}
        tone="info"
        title="Not available"
        description={refused ?? ''}
        onConfirm={() => setRefused(null)}
      />
    </>
  );
}

/**
 * One button on the bar, drawn from `toolbarState` — including its refusal, which is the
 * whole point of this component. This bar's controls are refused most of the time, and a
 * refused control that swallows the click is indistinguishable from a broken one: "the
 * import button does nothing" (Mike) was Import correctly refusing a viewer who could not
 * register, with nothing on screen to say so.
 *
 * SO IT IS NEVER `disabled`. The reason used to ride on `title`, and Chrome does not
 * dispatch hover — or show a tooltip — over a natively disabled button, so the explanation
 * could only be read by someone who already knew it was there. `aria-disabled` keeps the
 * refusal for assistive tech and the greyed-out look for everyone else, while leaving the
 * button a real target: pressing it hands `state.reason` to `onRefused`, which says out
 * loud what the tooltip never got to.
 *
 * `state.pending` IS NOT A REFUSAL AND MUST NOT BE SPOKEN AS ONE. This console paints its
 * toolbar before the first tree read lands, so Add is pressable for a fraction of a second
 * while nothing yet knows whether it is allowed — and pressing it in that window used to
 * raise "Not available / Still reading what you may do in this workspace." over the dialog,
 * a modal that told the operator no to a question that had not been asked yet and would
 * have answered yes. Nor may the press simply be dropped: a swallowed click is the failure
 * this component exists to prevent, and it is worse here, because the control goes live
 * immediately afterwards and the operator is left believing they already pressed it.
 *
 * So a pending press is ARMED rather than answered. When the read lands, the intent is
 * spent on whatever the real answer turned out to be — the action if it is allowed, the
 * genuine refusal if it is not. Either way the operator gets the outcome of the press they
 * actually made, and never a refusal that was only ever "not yet".
 */
function BarButton({
  label,
  icon,
  state,
  destructive = false,
  size = 'xs',
  variant = destructive ? 'destructive-ghost' : 'ghost',
  title,
  onClick,
  onRefused,
}: {
  label: string;
  /** Optional, because a control outside the bar may be a word on its own. */
  icon?: React.ReactNode;
  state: ButtonState;
  destructive?: boolean;
  /**
   * HOW IT LOOKS — and the only thing a caller outside the toolbar ever wanted to change.
   *
   * The detail pane's Remove is an ordinary button by explicit instruction ("the remove
   * button needs to not look like some weird ui you invented"), and for a while that meant a
   * bare `<Button disabled>` written out beside this one. A `disabled` button does not fire
   * `onClick`, so that copy had none of the arming below: pressed in the fraction of a second
   * before the verbs land it did nothing at all, silently, which is the one failure the note
   * above says this component exists to prevent. Appearance was never the reason it could not
   * be a BarButton, so appearance is what moved into props.
   */
  size?: React.ComponentProps<typeof Button>['size'];
  variant?: React.ComponentProps<typeof Button>['variant'];
  /** The hover hint. The bar leaves it unset — its refusals are spoken by `onRefused`. */
  title?: string;
  onClick: () => void;
  /** Pressed while refused. Gets `state.reason`, or a stand-in when the gate named none. */
  onRefused: (reason: string) => void;
}): React.ReactElement {
  const [armed, setArmed] = React.useState(false);

  // The whole point is to act on a state this render does not have yet, so the arming has to
  // survive to the render that does. `refuse` is rebuilt each render and the effect is keyed
  // on `armed` and `state`, which is what makes it fire on the read landing rather than on a
  // press — an armed button whose state never resolves simply stays armed, which is correct.
  const refuse = (): void => onRefused(state.reason || `${label} is not available here.`);
  React.useEffect(() => {
    if (!armed || state.pending) return;
    setArmed(false);
    if (state.enabled) onClick();
    else refuse();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [armed, state.pending, state.enabled]);

  return (
    <Button
      type="button"
      size={size}
      variant={variant}
      title={title}
      aria-disabled={!state.enabled}
      aria-busy={state.pending || armed ? true : undefined}
      className={state.enabled ? undefined : 'opacity-50'}
      onClick={() => {
        if (state.enabled) onClick();
        else if (state.pending) setArmed(true);
        else refuse();
      }}
    >
      {icon}
      {label}
    </Button>
  );
}

/**
 * The detail area: whatever the rail has selected, at whichever level it selected it.
 *
 * THREE STATES AND ONE FRAME. A repository's settings, an account's defaults, or the hint
 * that nothing is chosen — this component decides which and supplies the scroll box; the
 * wiring for each is built by the dialog, which is the thing that holds the state. The
 * account's defaults reached here from a gear on the repository level's title, which is to
 * say from a modal on top of this modal, hung off the title of the level BELOW their own
 * subject.
 */
function DetailPane({
  selected,
  orgForm,
  orgOpen,
  catalogue,
  onSaveSettings,
  onProvision,
  onSaved,
  remove,
}: {
  selected: Row | null;
  /** The open account's defaults form, or null when the pane's subject is not an account —
   *  nothing is open, a repository under it is selected, or the read that seeds it is still
   *  out. Built by the dialog because that is where the read and the save live. */
  orgForm: React.ReactNode;
  /** An account is open, whether or not {@link orgForm} could be built for it. It decides
   *  which hint the empty state gives: telling an operator to choose an organization while
   *  the column of its repositories is on screen names the one thing they have already
   *  done. */
  orgOpen: boolean;
  /** Answers "is that deployment repository already there" without a round trip, and names
   *  the accounts the deployment-organization menu may offer. */
  catalogue: ForgeCatalogue;
  onSaveSettings: (patches: RepoSettingsPatch[]) => Promise<void>;
  onProvision?: (devRepoId: string) => Promise<void> | void;
  /** The save the footer's OK started has landed. Closing is the rest of what OK means. */
  onSaved: () => void;
  /** Remove, for the repository this pane is showing — the bar's own button, handed down.
   *  See the note at the call site: one gate, two places to press it. */
  remove: React.ReactNode;
}): React.ReactElement {
  if (selected) {
    return (
      <div className="flex min-h-0 min-w-0 flex-1 flex-col overflow-y-auto px-6 py-4">
        <SettingsForm
          // Remounted per repository, which re-seeds the boxes: a pane is mounted per
          // selection, so it takes `active`'s default rather than the modal's `open`.
          key={selected.devRepo.id}
          target={{
            kind: 'devRepo',
            devRepo: selected.devRepo,
            mirrors: selected.mirrors,
          }}
          // The dialog's footer is this form's Save, so it draws no buttons of its own.
          formId={SETTINGS_FORM_ID}
          catalogue={catalogue}
          onSave={onSaveSettings}
          onProvision={onProvision}
          onSaved={onSaved}
          remove={remove}
        />
      </div>
    );
  }
  if (orgForm) {
    return (
      <div className="flex min-h-0 min-w-0 flex-1 flex-col overflow-y-auto px-6 py-4">
        {orgForm}
      </div>
    );
  }
  if (orgOpen) {
    return (
      <TopicSelectHint noun="repository" listTitle="Repositories">
        Its deployment repositories, the branches they are cut from, and which environments
        each one ships to. Add registers a new one — against a forge account from
        Integrations, out on the right of the toolbar.
      </TopicSelectHint>
    );
  }
  return (
    <TopicSelectHint noun="organization" listTitle="Organizations">
      What a new repository in that account deploys to by default, and the repositories
      already registered from it. Add registers a new one — against a forge account from
      Integrations, out on the right of the toolbar.
    </TopicSelectHint>
  );
}
