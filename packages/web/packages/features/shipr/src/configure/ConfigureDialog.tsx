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
import { Download, Minus, Plus, Upload } from 'lucide-react';

import { buildDocument } from '../exchange/document';
import { downloadDocument } from '../exchange/files';
import { ImportDialog } from '../exchange/ImportDialog';
import type { ImportPlan } from '../exchange/plan';
import { SettingsForm, type RepoSettingsPatch } from '../settings/SettingsForm';
import { toolbarState } from '../toolbar/actions';
import { TypeToConfirmDialog } from '../toolbar/dialogs';
import { RegisterWizard } from '../toolbar/RegisterWizard';
import type { Selection } from '../selection';
import type {
  AccessVerb,
  DevRepo,
  ForgeConnection,
  Group,
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
 */

const REPOS_LEVEL_ID = 'shipr-configure-repos';

/** The `<form>` the footer's OK submits. The boxes are a pane in the middle of this dialog
 *  and OK is at the bottom of it, which is what `form=` on a button outside the form is for. */
const SETTINGS_FORM_ID = 'shipr-configure-settings';

/** A source repository and everything cut from it — the row, and what its settings write to. */
interface Row {
  devRepo: DevRepo;
  mirrors: RepoItem[];
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
  /** The forge accounts the wizard and the importer may register AGAINST. Read-only here —
   *  this dialog no longer manages them; see {@link onManageConnections}. */
  connections?: readonly ForgeConnection[];
  /** Why {@link connections} could not be read. Handed straight to the wizard — this dialog has
   *  no empty state of its own to spend it on. */
  connectionsError?: string | null;
  /** Leave for the Integrations dialog, because the operator has just found that
   *  {@link connections} is empty or missing the account they want. The host is expected to
   *  CLOSE this dialog and open that one — they are siblings on the console, not nested, so
   *  there is no stack to come back to. Optional: a host with nowhere to send them simply
   *  does not offer the link. */
  onManageConnections?: () => void;
  onRegister: (body: RegisterRequest) => Promise<void>;
  /** Unregister every mirror and retire the source row. One call, not one per mirror: the
   *  backend expands a `dev_repo` scope itself, and a browser tab closed halfway through a
   *  loop in this file would strand the rest. */
  onRemove: (devRepo: DevRepo) => Promise<void>;
  onSaveSettings: (patches: RepoSettingsPatch[]) => Promise<void>;
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
          under the pointer. */}
      <DialogContent className="flex h-[80vh] max-w-5xl flex-col gap-4">
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
  connectionsError = null,
  onManageConnections,
  onRegister,
  onRemove,
  onSaveSettings,
  onImport,
}: ConfigureDialogProps): React.ReactElement {
  const [selectedId, setSelectedId] = React.useState<string | null>(null);
  const [wizard, setWizard] = React.useState(false);
  const [importing, setImporting] = React.useState(false);
  const [removing, setRemoving] = React.useState<Row | null>(null);

  /** Why the bar just refused a press — see `BarButton`. Null when nothing was refused. */
  const [refused, setRefused] = React.useState<string | null>(null);

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

  /** Re-derived from the live rows every render, so a row that is removed while its own
   *  settings are open takes the selection with it rather than leaving a pane whose subject
   *  no longer exists. */
  const selected = rows.find((r) => r.devRepo.id === selectedId) ?? null;

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

  const level = React.useMemo<TopicLevel>(
    () => ({
      id: REPOS_LEVEL_ID,
      title: 'Repositories',
      itemNoun: 'repository',
      items: rows.map((row) => ({
        id: row.devRepo.id,
        label: row.devRepo.slug,
        sublabel:
          row.mirrors.length === 1
            ? row.mirrors[0]!.slug
            : `${row.mirrors.length} deployment repositories`,
      })),
      selectedId,
      onSelect: (id: string) => setSelectedId(id),
      onClear: () => setSelectedId(null),
      emptyLabel: 'Nothing is registered yet — Add is how one gets here.',
      // A spinner, and only that now the bar is not hung off this level: the console
      // re-reads the tree at every hand-off while a run walks, and these rows are exactly
      // what an unregister removes.
      busy,
    }),
    [rows, selectedId, busy],
  );

  return (
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
          <StackLevels levels={[level]}>
            <DetailPane
              selected={selected}
              onSaveSettings={onSaveSettings}
              onSaved={onClose}
            />
          </StackLevels>
        </StandaloneRailHost>
      </div>

      {/*
        OK AND CANCEL MEAN SOMETHING HERE, which is the only reason they are worth drawing.
        Everything else this dialog does is committed by its own control the moment it is
        confirmed — Add walks a wizard, Remove makes you type the slug — and none of it is
        undone by closing. The environment boxes are the one thing held in hand: OK submits
        them and closes, Cancel closes and drops them, which is what a modal's two buttons
        are expected to mean and what a lone corner "×" could not say.

        `form=` rather than a click handler, and only while a repository is selected: the
        boxes live in a pane in the middle of this dialog, so the browser's own mechanism for
        submitting a form from outside it is the whole implementation — the alternative is
        lifting every checkbox up here so the footer can build the patch itself, and then two
        surfaces compute the same diff. With nothing selected there is no form and no draft,
        and OK is simply the way out.
      */}
      <DialogFooter>
        <Button type="button" variant="ghost" onClick={onClose}>
          Cancel
        </Button>
        {selected ? (
          <Button type="submit" form={SETTINGS_FORM_ID}>
            OK
          </Button>
        ) : (
          <Button type="button" onClick={onClose}>
            OK
          </Button>
        )}
      </DialogFooter>

      <RegisterWizard
        open={wizard}
        onClose={() => setWizard(false)}
        client={client}
        groups={groups}
        connections={connections}
        connectionsError={connectionsError}
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

      <ImportDialog
        open={importing}
        onClose={() => setImporting(false)}
        groups={groups}
        items={items}
        connections={connections}
        onImport={onImport}
      />

      <TypeToConfirmDialog
        open={removing !== null}
        onClose={() => setRemoving(null)}
        title="Remove repository"
        phrase={removing?.devRepo.slug ?? ''}
        body={
          removing ? (
            <>
              Unregisters{' '}
              {removing.mirrors.length === 1
                ? 'its deployment repository'
                : `all ${removing.mirrors.length} of its deployment repositories`}{' '}
              and retires <span className="font-mono">{removing.devRepo.slug}</span> from
              this console. Nothing is deleted on GitHub — the repositories, their branches
              and their protection rules are left exactly as they are, so registering again
              adopts them rather than rebuilding them.
            </>
          ) : (
            ''
          )
        }
        confirmLabel="Remove"
        onConfirm={async () => {
          if (!removing) return;
          await onRemove(removing.devRepo);
          // The row is gone, so the selection that was showing it has to go too.
          setSelectedId(null);
        }}
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
 */
function BarButton({
  label,
  icon,
  state,
  destructive = false,
  onClick,
  onRefused,
}: {
  label: string;
  icon: React.ReactNode;
  state: { enabled: boolean; reason: string };
  destructive?: boolean;
  onClick: () => void;
  /** Pressed while refused. Gets `state.reason`, or a stand-in when the gate named none. */
  onRefused: (reason: string) => void;
}): React.ReactElement {
  return (
    <Button
      type="button"
      size="xs"
      variant={destructive ? 'destructive-ghost' : 'ghost'}
      aria-disabled={!state.enabled}
      className={state.enabled ? undefined : 'opacity-50'}
      onClick={() =>
        state.enabled
          ? onClick()
          : onRefused(state.reason || `${label} is not available here.`)
      }
    >
      {icon}
      {label}
    </Button>
  );
}

/** The detail area: the selected repository's settings, or the reason there aren't any. */
function DetailPane({
  selected,
  onSaveSettings,
  onSaved,
}: {
  selected: Row | null;
  onSaveSettings: (patches: RepoSettingsPatch[]) => Promise<void>;
  /** The save the footer's OK started has landed. Closing is the rest of what OK means. */
  onSaved: () => void;
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
          onSave={onSaveSettings}
          onSaved={onSaved}
        />
      </div>
    );
  }
  return (
    <TopicSelectHint noun="repository" listTitle="Repositories">
      Its deployment repositories, the branches they are cut from, and which environments
      each one ships to. Add registers a new one — against a forge account from Integrations,
      out on the right of the toolbar.
    </TopicSelectHint>
  );
}
