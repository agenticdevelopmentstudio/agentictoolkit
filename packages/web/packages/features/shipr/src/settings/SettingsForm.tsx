'use client';

import * as React from 'react';

import { Button } from '@agenticdevelopertoolkit/ui/components/button';
import { Checkbox } from '@agenticdevelopertoolkit/ui/components/checkbox';
import { ErrorText } from '@agenticdevelopertoolkit/ui/components/error-text';
import { Input } from '@agenticdevelopertoolkit/ui/components/input';
import { Label } from '@agenticdevelopertoolkit/ui/components/label';
import { Select } from '@agenticdevelopertoolkit/ui/components/select';

import { Existence, nameOf, ownerOf } from '../forge/existence';
import type { ForgeCatalogue } from '../forge/useForgeCatalogue';
import { useSubmit } from '../toolbar/dialogs';
import { repoLabel } from '../tree/toLevels';
import type { Descendant } from '../tree/levels';
import {
  ENVIRONMENTS,
  type DevRepo,
  type Environment,
  type Group,
  type RepoItem,
} from '../types';
import {
  applyFlags,
  changed,
  commonFlags,
  flagsOf,
  isUnchanged,
  mixedFlags,
  type EnvFlags,
} from './env';

/**
 * Settings, as a FORM rather than as a dialog — the reference block for whatever is
 * selected, and the environment boxes that write to it.
 *
 * IT IS A FORM AND NOT A DIALOG BECAUSE IT HAS TWO HOSTS. The rail's gear menu opens it in
 * a modal ({@link SettingsDialog}), and the Configure dialog puts the same thing in its
 * detail pane, where a second modal on top of the first would be a dialog inside a dialog.
 * Both hosts ask the identical question — which environments does this ship to — so it is
 * one implementation with a frame around it, not two that must be kept agreeing.
 *
 * ONE FORM, THREE SHAPES, one question. On a MIRROR it shows that mirror's names and its
 * environment boxes. On a FOLDER the names would be meaningless — a folder has no branches —
 * so it shows what is in the folder instead, and the boxes speak for everything inside it.
 * On a DEV REPO it shows the repository's own branches and the mirrors cut from them, and
 * the boxes speak for every mirror. Splitting these would make the environment boxes, which
 * are the point, into three implementations of one rule.
 *
 * A save writes only the boxes the operator MOVED (`changed`). A folder whose repositories
 * disagree about `staging` shows that as mixed and leaves it that way unless it is touched —
 * the alternative is that opening a folder's settings and pressing Save silently imposes one
 * repository's answer on ten others.
 */

/**
 * One repository's settings after the form.
 *
 * The key is optional and a patch carries only what actually moved: a Save that touched
 * nothing on THIS repository is not a write, and a folder of eleven where one already reads
 * the way the boxes do is ten writes, not eleven.
 */
export interface RepoSettingsPatch {
  repoId: string;
  envBranches?: Partial<Record<Environment, string>>;
  /**
   * Where the mirror goes — `owner/name`, the whole thing.
   *
   * Accepted only while that mirror is unprovisioned; the server answers 409 afterwards,
   * because re-pointing a live mirror strands its ladder and its history on a repository
   * nothing now names. So the form offers the fields only up to that moment.
   */
  slug?: string;
  /**
   * The SOURCE repository's label, carried on a mirror because a mirror is the only thing
   * this console has an id for. Null clears it, and a cleared label is not the same as one
   * set to the slug: null means no opinion, and every reader falls back to the slug on its
   * own, which keeps working when the repository is renamed.
   */
  displayName?: string | null;
}

export type SettingsTarget =
  | { kind: 'repo'; repo: RepoItem }
  | { kind: 'group'; group: Group; contents: readonly Descendant[] }
  /** A source repository and every mirror cut from it — the Configure dialog's rail. The
   *  mirrors ride along because they are what the boxes write to: a dev repo has no
   *  `envBranches` of its own, it has shards that do. */
  | { kind: 'devRepo'; devRepo: DevRepo; mirrors: readonly RepoItem[] };

/** The mirrors a target's boxes write to, in one place: the whole difference between the
 *  three shapes, once the reference block above them has been drawn. */
export function reposOf(target: SettingsTarget | null): RepoItem[] {
  if (!target) return [];
  if (target.kind === 'repo') return [target.repo];
  if (target.kind === 'group') return target.contents.map((d) => d.repo);
  return [...target.mirrors];
}

/** What to call the thing being configured, for a heading or a dialog title. */
export function settingsTitle(target: SettingsTarget | null): string {
  if (!target) return 'Settings';
  if (target.kind === 'repo') return repoLabel(target.repo);
  if (target.kind === 'group') return target.group.name;
  return target.devRepo.slug;
}

/** One name/value line. Monospace, because every value here is a branch or a slug and the
 *  question being asked of it is usually "is that the exact string". */
function Fact({
  name,
  value,
}: {
  name: string;
  value: React.ReactNode;
}): React.ReactElement {
  return (
    <div className="flex gap-2 text-xs">
      <dt className="w-28 shrink-0 text-apt-text-muted">{name}</dt>
      <dd className="min-w-0 break-all font-mono text-apt-text">{value}</dd>
    </div>
  );
}

/** The frame every reference block shares, so three blocks are one box. */
function Facts({ children }: { children: React.ReactNode }): React.ReactElement {
  return (
    <dl className="flex flex-col gap-1 rounded border border-apt-border bg-apt-surface-2 px-3 py-2">
      {children}
    </dl>
  );
}

/** The reference block: what this deployment repository's pipeline is actually made of. */
function RepoFacts({ repo }: { repo: RepoItem }): React.ReactElement {
  return (
    <Facts>
      <Fact name="deployment repository" value={repo.slug} />
      {repo.devRepo ? (
        <>
          <Fact name="main" value={repo.devRepo.mainBranch} />
          <Fact name="prepared" value={repo.devRepo.preparedBranch} />
        </>
      ) : null}
      <Fact name="ship" value={repo.shipBranch} />
      {ENVIRONMENTS.map((env) =>
        repo.envBranches[env] ? (
          <Fact key={env} name={`${env} branch`} value={repo.envBranches[env]} />
        ) : null,
      )}
      <Fact name="gate context" value={repo.ciContext} />
      <Fact name="registered" value={repo.registeredAt ?? 'not provisioned yet'} />
    </Facts>
  );
}

/** The SOURCE repository's own block. Not the mirror's: nothing here is cut, everything
 *  here is what the mirrors are cut FROM. */
function DevRepoFacts({ devRepo }: { devRepo: DevRepo }): React.ReactElement {
  return (
    <Facts>
      <Fact name="repository" value={devRepo.slug} />
      <Fact name="main" value={devRepo.mainBranch} />
      <Fact name="prepared" value={devRepo.preparedBranch} />
    </Facts>
  );
}

/** A list of repositories, by whatever distinguishes them. Two repositories called `web` in
 *  two sub-folders are one word apart, and the word is the sub-folder — the one qualifier
 *  that is still drawn beside a name here. The shard is not: a row shows the name that was
 *  configured for it and nothing else, the same rule the rail and the detail heading follow. */
function ContentsList({
  contents,
  emptyLabel,
}: {
  contents: readonly Descendant[];
  emptyLabel: string;
}): React.ReactElement {
  if (contents.length === 0) {
    return (
      <p className="rounded border border-apt-border bg-apt-surface-2 px-3 py-2 text-xs text-apt-text-muted">
        {emptyLabel}
      </p>
    );
  }
  return (
    <ul className="flex max-h-56 flex-col gap-1 overflow-auto rounded border border-apt-border bg-apt-surface-2 px-3 py-2">
      {contents.map(({ repo, relativePath }) => (
        <li key={repo.id} className="flex gap-2 text-xs">
          <span className="min-w-0 break-all font-mono text-apt-text">
            {relativePath ? `${relativePath}/` : ''}
            {repoLabel(repo)}
          </span>
        </li>
      ))}
    </ul>
  );
}

/**
 * WHERE ONE MIRROR GOES, and whether it is already there.
 *
 * This is the screen the Add wizard used to be. Add now writes the rows and creates nothing,
 * so the org and the name are set HERE — beside the repository they belong to, with
 * {@link Existence} under them saying what the forge actually holds, and with Provision the
 * separate press that acts on it. That ordering is the entire point: the deployment
 * repository is the one setting whose default can create a repository in somebody else's
 * organization, and it is now read and corrected before anything is queued rather than
 * discovered from a failed run.
 *
 * ONCE PROVISIONED IT IS READ-ONLY. `PATCH /shipr/repos/:id` answers 409 on a `slug` for a
 * mirror with a `registeredAt`, and a control whose value the server refuses is worse than no
 * control.
 */
function DeploymentTarget({
  mirror,
  draft,
  catalogue,
  onChange,
}: {
  mirror: RepoItem;
  draft: { owner: string; name: string };
  catalogue: ForgeCatalogue | undefined;
  onChange: (next: { owner: string; name: string }) => void;
}): React.ReactElement {
  const slug = `${draft.owner}/${draft.name.trim()}`;

  /**
   * The org menu's options: every account shipr reaches, plus whatever is currently
   * selected. The second is not padding — a mirror can already name an account shipr holds
   * no installation on, which is the case worth showing most of all, and a menu that
   * silently dropped it would answer the question by hiding it.
   */
  const orgs = React.useMemo(
    () =>
      [...new Set([...(catalogue?.orgs ?? []).map((o) => o.login), draft.owner])]
        .filter(Boolean)
        .sort(),
    [catalogue, draft.owner],
  );

  if (mirror.registeredAt) {
    return (
      <div className="flex flex-col gap-1">
        {mirror.shard ? <Label>{mirror.shard}</Label> : null}
        <p className="text-sm text-apt-text-muted">
          Deploys to <span className="font-mono text-apt-text">{mirror.slug}</span>, provisioned{' '}
          {mirror.registeredAt}. Where a live deployment repository points is not editable.
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-2">
      {mirror.shard ? <Label>{mirror.shard}</Label> : null}
      <div className="flex flex-col gap-1">
        <Label htmlFor={`shipr-deploy-owner-${mirror.id}`}>Deployment organization</Label>
        <Select
          id={`shipr-deploy-owner-${mirror.id}`}
          aria-label="Deployment organization"
          value={draft.owner}
          onChange={(e) => onChange({ ...draft, owner: e.target.value })}
        >
          {orgs.map((o) => (
            <option key={o} value={o}>
              {o}
            </option>
          ))}
        </Select>
      </div>
      <div className="flex flex-col gap-1">
        <Label htmlFor={`shipr-deploy-name-${mirror.id}`}>Deployment repository</Label>
        <Input
          id={`shipr-deploy-name-${mirror.id}`}
          aria-label="Deployment repository"
          value={draft.name}
          onChange={(e) => onChange({ ...draft, name: e.target.value })}
        />
      </div>
      {draft.name.trim() === '' ? (
        <p className="text-sm text-apt-orange">A deployment repository needs a name.</p>
      ) : catalogue ? (
        <Existence slug={slug} catalogue={catalogue} />
      ) : null}
    </div>
  );
}

export interface SettingsFormProps {
  /** Null draws nothing but the frame — a pane with no row selected. */
  target: SettingsTarget | null;
  /**
   * Re-seed the boxes from `target`. A host that MOUNTS this fresh per selection can leave
   * it true; the modal passes its own `open`, because a dialog is mounted while closed and
   * a parent re-render must not untick a box someone has just ticked.
   */
  active?: boolean;
  /** The repositories to write. Empty when nothing moved, and this does not call it then: a
   *  Save that writes nothing should still not spend eleven round trips saying so. */
  onSave: (patches: RepoSettingsPatch[]) => Promise<void>;
  /** Runs after a save RESOLVES. The modal closes on it; a pane stays put. */
  onSaved: () => void;
  /** Drawn beside Save. The settings modal passes Cancel; a host that draws its own
   *  buttons — see {@link SettingsFormProps.formId} — passes nothing, and neither does a
   *  pane, because a pane has no state to abandon: the boxes are the state, and leaving
   *  them is the cancel. */
  cancel?: React.ReactNode;
  /**
   * Every account and every repository shipr can reach.
   *
   * Optional because the two hosts differ: the Configure dialog holds it, the rail's gear
   * modal does not. Without it the deployment fields still edit — the org menu falls back to
   * what the mirror already names — and only the existence line, which is the part that
   * needs the grants, is left unsaid rather than guessed at.
   */
  catalogue?: ForgeCatalogue;
  /**
   * GO AND MAKE IT. Absent, the button is not drawn — a host with no way to run the
   * operation must not offer it.
   */
  onProvision?: (devRepoId: string) => Promise<void> | void;
  /**
   * The id to hang on the `<form>`, so a button OUTSIDE it can submit it with `form=`.
   *
   * Given, this draws NO buttons of its own: the host's button is the Save, and two Saves
   * for one patch is two things to keep in step and two answers to "did that write". It is
   * how the Configure dialog's OK commits the boxes — the form is a pane in the middle of
   * that dialog and the footer is at the bottom of it, which is exactly the shape `form=`
   * exists for; the alternative is lifting every checkbox into the dialog so it can build
   * the patch itself, and then the modal and the pane compute the same diff twice.
   *
   * Undefined keeps the inline Save, which is what a pane with no footer under it needs.
   */
  formId?: string;
}

/**
 * THE ONE PRESS THAT TOUCHES THE FORGE. Everything else on this form writes a row.
 *
 * PROVISION AND DOCTOR ARE THE SAME REQUEST — `POST /shipr/runs` with `register` against
 * this dev repo — and the same run: `register` adopts what is already there rather than
 * rebuilding it, so re-running it on a live pipeline repairs the parts that drifted. Only
 * the LABEL differs, off `registeredAt`, because "Provision" on something already
 * provisioned reads like a second one is about to be made.
 *
 * It refuses while there are unsaved changes rather than saving them for you: provisioning
 * acts on what the server holds, and a press that silently wrote three fields and then
 * created a repository from them is the failure mode this whole configure-then-provision
 * split exists to prevent.
 */
function ProvisionButton({
  devRepo,
  mirrors,
  unsaved,
  onProvision,
}: {
  devRepo: DevRepo;
  mirrors: readonly RepoItem[];
  unsaved: boolean;
  onProvision: (devRepoId: string) => Promise<void> | void;
}): React.ReactElement {
  const [busy, setBusy] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);
  const provisioned = mirrors.length > 0 && mirrors.every((m) => m.registeredAt !== null);

  return (
    <div className="flex flex-col gap-1 border-t border-apt-border pt-3">
      <div className="flex items-center gap-3">
        <Button
          type="button"
          disabled={busy || unsaved || mirrors.length === 0}
          onClick={() => {
            setBusy(true);
            setError(null);
            void Promise.resolve(onProvision(devRepo.id))
              .catch((e: unknown) => setError(e instanceof Error ? e.message : String(e)))
              .finally(() => setBusy(false));
          }}
        >
          {busy ? 'Starting…' : provisioned ? 'Doctor' : 'Provision'}
        </Button>
        <span className="text-xs text-apt-text-muted">
          {unsaved
            ? 'Save the changes above first — provisioning acts on what is stored.'
            : provisioned
              ? 'Re-runs the registration against what is already there, and repairs what drifted.'
              : 'Creates the deployment repositories named above and starts the pipeline.'}
        </span>
      </div>
      <ErrorText error={error} />
    </div>
  );
}

export function SettingsForm({
  target,
  active = true,
  onSave,
  onSaved,
  cancel,
  catalogue,
  onProvision,
  formId,
}: SettingsFormProps): React.ReactElement {
  // What the boxes said when this opened. Kept beside the live flags because the diff
  // between them is the whole write — see `changed`.
  const repos = React.useMemo(() => reposOf(target), [target]);
  const seed = React.useMemo<EnvFlags>(() => {
    if (!target) return commonFlags([]);
    return target.kind === 'repo' ? flagsOf(target.repo) : commonFlags(repos);
  }, [target, repos]);
  // Mixed is a statement about a SET, so it is only ever asked of the two shapes that are
  // one: a single mirror agrees with itself.
  const many = target !== null && target.kind !== 'repo';
  const mixed = React.useMemo<EnvFlags>(
    () => (many ? mixedFlags(repos) : mixedFlags([])),
    [many, repos],
  );

  const [flags, setFlags] = React.useState<EnvFlags>(seed);

  /** The dev repo shape, or null — every field below this line exists only on it. */
  const dev = target?.kind === 'devRepo' ? target : null;

  /** What the operator calls it. Seeded from the stored label and NOT from the slug: an
   *  empty box means "no opinion", and pre-filling it with the slug would turn every save
   *  into a stored copy that goes stale the moment the repository is renamed. */
  const [displayName, setDisplayName] = React.useState('');
  /** Where each mirror goes, split the way its two controls are, keyed by mirror id. */
  const [deploy, setDeploy] = React.useState<
    Record<string, { owner: string; name: string }>
  >({});

  const deploySeed = React.useMemo(() => {
    const next: Record<string, { owner: string; name: string }> = {};
    for (const mirror of dev?.mirrors ?? []) {
      next[mirror.id] = { owner: ownerOf(mirror.slug), name: nameOf(mirror.slug) };
    }
    return next;
  }, [dev]);

  // Re-seed on OPEN and on a change of target, never on every render: a parent that
  // re-renders while a box is ticked must not untick it.
  React.useEffect(() => {
    if (!active) return;
    setFlags(seed);
    setDisplayName(dev?.devRepo.displayName ?? '');
    setDeploy(deploySeed);
  }, [active, seed, dev, deploySeed]);

  const touched = changed(seed, flags);

  /**
   * ONE PATCH PER REPOSITORY, however many fields moved.
   *
   * The three answers this form collects land on different tables and, for the label, on a
   * different row entirely — but they are all `PATCH /shipr/repos/:id`, so a mirror whose
   * environments and whose slug both changed is one request, not two racing each other.
   */
  const patches = React.useMemo<RepoSettingsPatch[]>(() => {
    const byId = new Map<string, RepoSettingsPatch>();
    const at = (id: string) => {
      const found = byId.get(id);
      if (found) return found;
      const made: RepoSettingsPatch = { repoId: id };
      byId.set(id, made);
      return made;
    };

    if (touched.length > 0) {
      for (const repo of repos) {
        const envBranches = applyFlags(repo.envBranches, flags, touched);
        // Dropped if THIS repository was already the way the boxes say — a folder of
        // eleven where one already reads that way is ten writes, not eleven.
        if (!isUnchanged(repo.envBranches, envBranches)) at(repo.id).envBranches = envBranches;
      }
    }

    if (dev) {
      const stored = dev.devRepo.displayName ?? '';
      const anchor = dev.mirrors[0];
      // THE LABEL RIDES ON ANY MIRROR: it belongs to the dev repo, and a mirror id is the
      // only id this route takes. Sending it once, on the first, is what keeps eleven
      // shards from writing one column eleven times.
      if (anchor && displayName.trim() !== stored) {
        at(anchor.id).displayName = displayName.trim() === '' ? null : displayName.trim();
      }
      for (const mirror of dev.mirrors) {
        // 409 once it is live — the form does not offer the fields, so this only guards
        // against a stale draft left behind by a provision that landed under it.
        if (mirror.registeredAt) continue;
        const draft = deploy[mirror.id];
        if (!draft || draft.name.trim() === '') continue;
        const slug = `${draft.owner}/${draft.name.trim()}`;
        if (slug !== mirror.slug) at(mirror.id).slug = slug;
      }
    }

    return [...byId.values()];
  }, [repos, flags, touched, dev, displayName, deploy]);

  const submit = React.useCallback(
    () => (patches.length === 0 ? Promise.resolve() : onSave(patches)),
    [onSave, patches],
  );
  const { busy, error, run } = useSubmit(submit, onSaved);

  return (
    <form
      id={formId}
      onSubmit={(e) => {
        e.preventDefault();
        if (!busy) run();
      }}
      className="flex min-w-0 flex-col gap-3"
    >
      {target?.kind === 'repo' ? (
        <RepoFacts repo={target.repo} />
      ) : target?.kind === 'group' ? (
        <ContentsList
          contents={target.contents}
          emptyLabel="Nothing is filed in this folder yet."
        />
      ) : dev ? (
        <>
          <DevRepoFacts devRepo={dev.devRepo} />

          <div className="flex flex-col gap-1">
            <Label htmlFor="shipr-display-name">Name</Label>
            <Input
              id="shipr-display-name"
              aria-label="Name"
              placeholder={dev.devRepo.slug}
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
            />
            {/* A LABEL AND NOTHING MORE. Said out loud because a field beside a slug reads
                like a rename, and one that renamed the repository would be a very
                expensive misunderstanding. */}
            <p className="text-xs text-apt-text-muted">
              What this is called on the home page. Empty shows{' '}
              <span className="font-mono">{dev.devRepo.slug}</span>; nothing on the forge is
              renamed either way.
            </p>
          </div>

          <fieldset className="flex flex-col gap-3">
            <legend className="pb-1 text-xs font-semibold text-apt-text-muted">
              Deployment
            </legend>
            {dev.mirrors.length === 0 ? (
              <p className="text-sm text-apt-text-muted">
                No deployment repository is configured for this repository yet.
              </p>
            ) : (
              dev.mirrors.map((mirror) => (
                <DeploymentTarget
                  key={mirror.id}
                  mirror={mirror}
                  draft={deploy[mirror.id] ?? { owner: ownerOf(mirror.slug), name: nameOf(mirror.slug) }}
                  catalogue={catalogue}
                  onChange={(next) => setDeploy((prev) => ({ ...prev, [mirror.id]: next }))}
                />
              ))
            )}
          </fieldset>
        </>
      ) : null}

      <fieldset className="flex flex-col gap-2">
        <legend className="pb-1 text-xs font-semibold text-apt-text-muted">
          Environments
        </legend>
        {ENVIRONMENTS.map((env) => (
          <label key={env} className="flex items-center gap-2 text-sm text-apt-text">
            {/* `aria-label` because the wrapping <label> names only labelable elements,
                and Base UI's checkbox is a button, not an input. */}
            <Checkbox
              checked={flags[env]}
              aria-label={env}
              onCheckedChange={(checked: boolean) =>
                setFlags((prev) => ({ ...prev, [env]: checked }))
              }
            />
            <span>{env}</span>
            {/* Mixed is stated, not averaged. It disappears the moment the box is
                touched, because from then on the box IS the answer for all of them. */}
            {many && mixed[env] && !touched.includes(env) ? (
              <span className="text-xs text-apt-text-muted">
                some of these repositories
              </span>
            ) : null}
          </label>
        ))}
      </fieldset>

      {dev && onProvision ? (
        <ProvisionButton
          devRepo={dev.devRepo}
          mirrors={dev.mirrors}
          unsaved={patches.length > 0}
          onProvision={onProvision}
        />
      ) : null}

      <ErrorText error={error} />
      {/* The error stays, the buttons go: a host that submits this from outside still needs
          the failure rendered where the boxes are, and it has no way to draw it itself. */}
      {formId ? null : (
        <div className="flex items-center justify-end gap-3 pt-1">
          {cancel}
          <Button type="submit" disabled={busy || patches.length === 0}>
            {busy
              ? 'Saving…'
              : patches.length > 1
                ? `Save ${patches.length} repositories`
                : 'Save'}
          </Button>
        </div>
      )}
    </form>
  );
}
