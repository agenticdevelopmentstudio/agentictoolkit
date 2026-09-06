'use client';

import * as React from 'react';

import { Button } from '@agenticdevelopertoolkit/ui/components/button';
import { Checkbox } from '@agenticdevelopertoolkit/ui/components/checkbox';
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@agenticdevelopertoolkit/ui/components/dialog';
import { ErrorText } from '@agenticdevelopertoolkit/ui/components/error-text';
import { Input } from '@agenticdevelopertoolkit/ui/components/input';
import { Label } from '@agenticdevelopertoolkit/ui/components/label';
import { Select } from '@agenticdevelopertoolkit/ui/components/select';

import { nameOf } from '../forge/existence';
import type { ForgeCatalogue } from '../forge/useForgeCatalogue';
import { applyFlags, flagsOf, isUnchanged, type EnvFlags } from '../settings/env';
import type { RepoSettingsPatch } from '../settings/SettingsForm';
import {
  ENVIRONMENTS,
  type DevRepo,
  type OrgDefaults,
  type OrgDefaultsPatch,
  type RepoItem,
} from '../types';

/**
 * WHAT A NEW REPOSITORY IN THIS ORG GETS — set once, for the org, instead of once per
 * repository.
 *
 * THE CONVENTION USED TO BE A CONSTANT IN THE SERVER. `<owner>/<name>-deployment`, decided
 * at register time, with nothing on any screen naming it and no way to say otherwise except
 * per repository, after the fact. That is how eleven repositories get eleven chances to be
 * wrong in the same direction — and how a deployment repository lands in an account nobody
 * meant, since the convention's `<owner>` is whatever org the SOURCE happens to be in.
 *
 * So the org owns the answer, and the answer is three fields: where the deployment
 * repositories go, what their names look like, and which environments the ladder starts
 * with. `POST /shipr/register` reads them ahead of the convention and behind the form, so a
 * repository added from here is already aimed correctly before anything is provisioned.
 *
 * OK / CANCEL / APPLY, meaning what they mean everywhere else. Apply commits and stays;
 * OK commits and closes; Cancel closes and drops. There is no third behaviour hiding in
 * OK — a dialog whose two committing buttons commit different amounts is a dialog nobody
 * can press confidently.
 *
 * AND COMMITTING IS TWO WRITES, DELIBERATELY. The defaults row is one of them, and it only
 * ever aims the NEXT repository: a default is read when a mirror is born. The other is the
 * walk over the repositories already here, which is the half the operator actually came for
 * — "put them all in the right org" is the reason to open this at all. The count of
 * repositories that walk is on screen before the press, and a repository that already
 * agrees is not written.
 *
 * IT PROVISIONS NOTHING. Not one forge call: the walk is `PATCH /shipr/repos/:id` per
 * mirror, which moves where a deployment repository is going to be, not what is there.
 * Making them is Provision's, one repository at a time, after this.
 */
export interface OrgDefaultsDialogProps {
  open: boolean;
  /** The forge account these defaults belong to. */
  org: string;
  /** The stored row, or `undefined` for an org nobody has set defaults on — which is not an
   *  error state and is not drawn as one: it seeds the fields with the convention. */
  defaults: OrgDefaults | undefined;
  /**
   * Why the defaults could not be READ, if they could not.
   *
   * This is the one absence that must not be treated as "nobody has set any". Undefined
   * means both things — no row, and no answer — and the two seed the same convention
   * fields, so a failed read draws a form that looks exactly like a fresh one. Pressing OK
   * on it would overwrite a row nobody has seen with the convention, and the walk would
   * re-aim every unprovisioned mirror in the org to match. So the write is refused while
   * this is set, and the reason is on screen.
   */
  defaultsError?: string | null;
  /**
   * The registered repositories in this org, with their mirrors — what Apply walks.
   *
   * Structural rather than an imported `Row`, so the dialog does not reach back into the
   * screen that hosts it for a shape that is two fields wide.
   */
  rows: readonly { devRepo: DevRepo; mirrors: readonly RepoItem[] }[];
  /** For the deployment-organization menu. Optional for the same reason as everywhere else:
   *  without it the menu still offers this org and whatever is already stored. */
  catalogue?: ForgeCatalogue;
  onClose: () => void;
  /** Upsert the defaults row. */
  onSaveDefaults: (org: string, patch: OrgDefaultsPatch) => Promise<void>;
  /** The walk. Same callback the settings pane's Save uses — one patch per mirror, and the
   *  console owns the writes. */
  onApply: (patches: RepoSettingsPatch[]) => Promise<void>;
}

/** What the fields hold, so seeding and diffing are one shape rather than four variables. */
interface Draft {
  /** `''` is "the same org", which is what a null `deploymentOwner` means. */
  owner: string;
  suffix: string;
  flags: EnvFlags;
}

const ALL_ON: EnvFlags = Object.fromEntries(
  ENVIRONMENTS.map((env) => [env, true]),
) as EnvFlags;

/** The convention, spelled here because this dialog is where it stops being invisible. */
const DEFAULT_SUFFIX = '-deployment';

function draftOf(defaults: OrgDefaults | undefined): Draft {
  if (!defaults) return { owner: '', suffix: DEFAULT_SUFFIX, flags: { ...ALL_ON } };
  return {
    owner: defaults.deploymentOwner ?? '',
    suffix: defaults.nameSuffix,
    // An EMPTY map is the built-in ladder, not a repository that deploys nowhere — so it
    // ticks every box rather than none. Reading it the other way would let one OK press
    // turn every environment off across the org.
    flags:
      Object.keys(defaults.envBranches).length > 0
        ? flagsOf({ envBranches: defaults.envBranches })
        : { ...ALL_ON },
  };
}

export function OrgDefaultsDialog(props: OrgDefaultsDialogProps): React.ReactElement {
  const { open, org, onClose } = props;
  return (
    <Dialog open={open} onOpenChange={(next) => !next && onClose()}>
      <DialogContent className="max-w-xl">
        <DialogHeader>
          <DialogTitle>{org} defaults</DialogTitle>
        </DialogHeader>
        {/* Mounted only while open, so each opening seeds from the stored row rather than
            from whatever the last opening was left holding. */}
        {open ? <Body {...props} /> : null}
      </DialogContent>
    </Dialog>
  );
}

function Body({
  org,
  defaults,
  defaultsError = null,
  rows,
  catalogue,
  onClose,
  onSaveDefaults,
  onApply,
}: OrgDefaultsDialogProps): React.ReactElement {
  const [draft, setDraft] = React.useState<Draft>(() => draftOf(defaults));
  const [busy, setBusy] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);
  /** Said out loud after an Apply, because Apply's whole tell is that the dialog does not
   *  close — without a line the press is indistinguishable from a dead button. */
  const [applied, setApplied] = React.useState<string | null>(null);

  /** The owner menu: every account shipr reaches, this org, and whatever is already stored
   *  — the last one because a default may name an account no installation covers, and that
   *  is precisely the row worth being able to see and change. */
  const owners = React.useMemo(
    () =>
      [
        ...new Set([
          org,
          ...(catalogue?.orgs ?? []).map((o) => o.login),
          ...(defaults?.deploymentOwner ? [defaults.deploymentOwner] : []),
        ]),
      ]
        .filter(Boolean)
        .sort(),
    [org, catalogue, defaults],
  );

  const owner = draft.owner || org;
  const suffix = draft.suffix;

  /** One example, built from a repository that is actually here — an abstract
   *  `<name><suffix>` teaches nothing about whether the suffix has its dash. */
  const sample = rows[0] ? nameOf(rows[0].devRepo.slug) : 'example';

  /**
   * WHAT APPLY WOULD WRITE — computed before the press, so the count on the button is the
   * count that happens.
   *
   * A mirror with a `registeredAt` keeps its slug: `PATCH /shipr/repos/:id` answers 409 on
   * one, because the repository exists on the forge under that name and this row is how
   * shipr finds it. Its environments still move, which is the half that is safe to change
   * on a live mirror.
   */
  const patches = React.useMemo<RepoSettingsPatch[]>(() => {
    const out: RepoSettingsPatch[] = [];
    for (const row of rows) {
      for (const mirror of row.mirrors) {
        const patch: RepoSettingsPatch = { repoId: mirror.id };
        let moved = false;

        const envBranches = applyFlags(mirror.envBranches, draft.flags, ENVIRONMENTS);
        if (!isUnchanged(mirror.envBranches, envBranches)) {
          patch.envBranches = envBranches;
          moved = true;
        }

        // A SHARDED MIRROR'S NAME IS NOT THIS DIALOG'S TO SET. It comes from `[deployments]`
        // in the repository's own `.shipr`, and the file and this form must not be able to
        // say two different things about one repository — the same rule that stops the Add
        // form overriding a declared shard (`fallbackSlug` reads the org default only when
        // nothing is declared). So the walk re-aims exactly the mirrors the convention
        // named: unsharded, and not yet provisioned.
        if (!mirror.registeredAt && !mirror.shard) {
          const slug = `${owner}/${nameOf(row.devRepo.slug)}${suffix}`;
          if (slug !== mirror.slug) {
            patch.slug = slug;
            moved = true;
          }
        }

        if (moved) out.push(patch);
      }
    }
    return out;
  }, [rows, draft.flags, owner, suffix]);

  const noEnvironments = ENVIRONMENTS.every((env) => !draft.flags[env]);

  const commit = async (close: boolean): Promise<void> => {
    setError(null);
    setApplied(null);
    setBusy(true);
    try {
      await onSaveDefaults(org, {
        deploymentOwner: draft.owner === '' ? null : draft.owner,
        nameSuffix: draft.suffix,
        envBranches: applyFlags({}, draft.flags, ENVIRONMENTS),
      });
      if (patches.length > 0) await onApply(patches);
      if (close) onClose();
      else
        setApplied(
          patches.length === 0
            ? 'Saved. Every repository in this organization already agrees.'
            : `Saved, and ${patches.length} ${
                patches.length === 1 ? 'repository' : 'repositories'
              } updated.`,
        );
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      <div className="flex flex-col gap-4">
        <div className="flex flex-col gap-1">
          <Label htmlFor="shipr-org-owner">Deployment organization</Label>
          <Select
            id="shipr-org-owner"
            aria-label="Deployment organization"
            value={draft.owner}
            onChange={(e) => setDraft((d) => ({ ...d, owner: e.target.value }))}
          >
            {/* The empty value is a real answer and is stored as one: "wherever the source
                repository is" follows an org that later moves, and a copy of today's name
                would not. */}
            <option value="">The same organization as the repository</option>
            {owners.map((o) => (
              <option key={o} value={o}>
                {o}
              </option>
            ))}
          </Select>
        </div>

        <div className="flex flex-col gap-1">
          <Label htmlFor="shipr-org-suffix">Name suffix</Label>
          <Input
            id="shipr-org-suffix"
            aria-label="Name suffix"
            value={draft.suffix}
            onChange={(e) => setDraft((d) => ({ ...d, suffix: e.target.value }))}
          />
          <p className="text-xs text-apt-text-muted">
            <span className="font-mono text-apt-text">{sample}</span> deploys to{' '}
            <span className="font-mono text-apt-text">
              {owner}/{sample}
              {suffix}
            </span>
            .
          </p>
        </div>

        <fieldset className="flex flex-col gap-2">
          <legend className="mb-1 text-sm font-medium text-apt-text">Environments</legend>
          {ENVIRONMENTS.map((env) => (
            <label key={env} className="flex items-center gap-2 text-sm text-apt-text">
              {/* `aria-label` because the wrapping <label> names only labelable elements,
                  and Base UI's checkbox is a button, not an input. */}
              <Checkbox
                checked={draft.flags[env]}
                aria-label={env}
                onCheckedChange={(checked: boolean) =>
                  setDraft((d) => ({ ...d, flags: { ...d.flags, [env]: checked } }))
                }
              />
              <span>{env}</span>
            </label>
          ))}
          {/* Refused rather than silently reinterpreted: an empty ladder is stored as "the
              built-in default", which is all three — so saving zero boxes would come back
              as three ticks and look like the write was lost. */}
          {noEnvironments ? (
            <p className="text-sm text-apt-orange">
              At least one environment. An empty ladder is stored as the built-in default,
              which is every environment — so this cannot be written as you have it.
            </p>
          ) : null}
        </fieldset>

        <p className="text-xs text-apt-text-muted">
          {patches.length === 0
            ? 'Nothing here to change: every registered repository in this organization already matches.'
            : `Applies to ${patches.length} of the ${rows.length} registered ${
                rows.length === 1 ? 'repository' : 'repositories'
              } here. Nothing is created on the forge — Provision does that, one repository at a time.`}
        </p>

        {defaultsError ? (
          <p className="text-sm text-apt-orange">
            shipr could not read this organization’s stored defaults ({defaultsError}), so
            the fields above are the convention rather than what is saved. Saving from here
            would overwrite a row nobody has seen — reopen Configure once the read works.
          </p>
        ) : null}

        {applied ? <p className="text-sm text-apt-text-muted">{applied}</p> : null}
        <ErrorText error={error} />
      </div>

      <DialogFooter>
        <Button type="button" variant="ghost" onClick={onClose} disabled={busy}>
          Cancel
        </Button>
        <Button
          type="button"
          variant="ghost"
          disabled={busy || noEnvironments || defaultsError !== null}
          onClick={() => void commit(false)}
        >
          Apply
        </Button>
        <Button
          type="button"
          disabled={busy || noEnvironments || defaultsError !== null}
          onClick={() => void commit(true)}
        >
          OK
        </Button>
      </DialogFooter>
    </>
  );
}
