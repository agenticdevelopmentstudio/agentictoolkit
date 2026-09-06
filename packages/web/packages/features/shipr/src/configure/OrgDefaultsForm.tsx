'use client';

import * as React from 'react';

import { Checkbox } from '@agenticdevelopertoolkit/ui/components/checkbox';
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
 * WHAT A NEW REPOSITORY IN THIS ORGANIZATION GETS — set once, for the org, instead of once
 * per repository.
 *
 * THE CONVENTION USED TO BE A CONSTANT IN THE SERVER. `<owner>/<name>-deployment`, decided at
 * register time, with nothing on any screen naming it and no way to say otherwise except per
 * repository, after the fact. That is how eleven repositories get eleven chances to be wrong
 * in the same direction — and how a deployment repository lands in an account nobody meant,
 * since the convention's `<owner>` is whatever org the SOURCE happens to be in.
 *
 * IT IS THE ORGANIZATION'S DETAIL PANE, not a modal (Mike: "move the org related settings to
 * org topic list"). It used to be a dialog behind a gear on the repository column's TITLE — a
 * popup over a popup, reached by a control most operators never found, hung on a heading that
 * names the org only incidentally. The rail already has a level whose subject IS the
 * organization; selecting a row there now shows what that row is configured to do, exactly as
 * selecting a repository shows what THAT is configured to do. One pattern, both levels, and
 * no surface that has to be discovered before it can be used.
 *
 * SO THERE IS ONE SAVE, AND IT IS THE DIALOG'S OK — the same rule the repository pane
 * follows. The modal's own Cancel / Apply / OK went with the modal: Apply meant
 * commit-and-stay, which only ever existed because a dialog that closes has no other way to
 * say "saved", and two committing buttons that commit different amounts is a pair nobody can
 * press confidently.
 *
 * AND COMMITTING IS TWO WRITES, DELIBERATELY. The defaults row is one, and it only ever aims
 * the NEXT repository: a default is read when a mirror is born. The other is the walk over
 * the repositories already here, which is the half the operator actually came for — "put them
 * all in the right org" is the reason to open this at all. The count of repositories that
 * walk is on screen before the press, and one that already agrees is not written.
 *
 * IT PROVISIONS NOTHING. Not one forge call: the walk is `PATCH /shipr/repos/:id` per mirror,
 * which moves where a deployment repository is going to BE, not what is there. Making them is
 * Provision's, one repository at a time, after this (Mike: "we're only configuring things,
 * it's up to the user to do the actual provisioning when the config is correct").
 */
export interface OrgDefaultsFormProps {
  /** The forge account these defaults belong to. */
  org: string;
  /** The stored row, or `undefined` for an org nobody has set defaults on — which is not an
   *  error state and is not drawn as one: it seeds the fields with the convention. */
  defaults: OrgDefaults | undefined;
  /**
   * Why the defaults could not be READ, if they could not.
   *
   * This is the one absence that must not be taken for "nobody has set any". Undefined means
   * both things — no row, and no answer — and the two seed identical fields, so a failed read
   * draws a form indistinguishable from a fresh one. Pressing OK on that would overwrite a
   * row nobody has seen with the convention, and the walk would re-aim every unprovisioned
   * mirror in the org to match. So the write is refused while this is set, and it says why.
   */
  defaultsError?: string | null;
  /**
   * The registered repositories in this org, with their deployment repositories — what the
   * walk covers.
   *
   * Structural rather than the dialog's `Row`, so the form does not reach back into the
   * screen that hosts it for a shape that is two fields wide.
   */
  rows: readonly { devRepo: DevRepo; mirrors: readonly RepoItem[] }[];
  /** For the deployment-organization menu. Optional for the same reason as everywhere else:
   *  without it the menu still offers this org and whatever is already stored. */
  catalogue?: ForgeCatalogue;
  /**
   * The id to hang on the `<form>`, so the dialog's footer OK submits it with `form=`.
   *
   * Required, and this draws no button of its own, for the reason spelled out above: the pane
   * sits inside a modal whose footer already holds the only Save on the screen.
   */
  formId: string;
  /** Upsert the defaults row. */
  onSaveDefaults: (org: string, patch: OrgDefaultsPatch) => Promise<void>;
  /** The walk. The same callback the repository pane's Save uses — one patch per deployment
   *  repository, and the console owns the writes. */
  onApply: (patches: RepoSettingsPatch[]) => Promise<void>;
  /** Both writes have landed. The dialog closes on it, which is the rest of what OK means. */
  onSaved: () => void;
}

/** What the fields hold, so seeding and diffing are one shape rather than four variables. */
interface Draft {
  /** `''` is "the same organization", which is what a null `deploymentOwner` means. */
  owner: string;
  suffix: string;
  flags: EnvFlags;
}

const ALL_ON: EnvFlags = Object.fromEntries(
  ENVIRONMENTS.map((env) => [env, true]),
) as EnvFlags;

/** The convention, spelled here because this form is where it stops being invisible. */
const DEFAULT_SUFFIX = '-deployment';

function draftOf(defaults: OrgDefaults | undefined): Draft {
  if (!defaults) return { owner: '', suffix: DEFAULT_SUFFIX, flags: { ...ALL_ON } };
  return {
    owner: defaults.deploymentOwner ?? '',
    suffix: defaults.nameSuffix,
    // An EMPTY map is the built-in ladder, not a repository that deploys nowhere — so it
    // ticks every box rather than none. Reading it the other way would let one OK press turn
    // every environment off across an entire organization.
    flags:
      Object.keys(defaults.envBranches).length > 0
        ? flagsOf({ envBranches: defaults.envBranches })
        : { ...ALL_ON },
  };
}

export function OrgDefaultsForm({
  org,
  defaults,
  defaultsError = null,
  rows,
  catalogue,
  formId,
  onSaveDefaults,
  onApply,
  onSaved,
}: OrgDefaultsFormProps): React.ReactElement {
  const [draft, setDraft] = React.useState<Draft>(() => draftOf(defaults));
  const [busy, setBusy] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  /** The owner menu: every account shipr reaches, this org, and whatever is already stored —
   *  the last because a default may name an account no installation covers, and that is
   *  precisely the row worth being able to see and change. */
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

  /**
   * WHAT THE WALK WOULD WRITE — computed before the press, so the count on screen is the
   * count that happens.
   *
   * A deployment repository that has been provisioned keeps its slug: `PATCH
   * /shipr/repos/:id` answers 409 on one, because the repository exists on the forge under
   * that name and this row is how shipr finds it again. Its environments still move, which is
   * the half that is safe to change on a live pipeline.
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

        // A SHARDED DEPLOYMENT REPOSITORY'S NAME IS NOT THIS FORM'S TO SET. It comes from
        // `[deployments]` in the repository's own `.shipr`, and the file and this form must
        // not be able to say two different things about one repository — the same rule that
        // stops the Add form overriding a declared shard. So the walk re-aims exactly the
        // ones the convention named: unsharded, and not yet provisioned.
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

  /**
   * WHY THIS CANNOT BE WRITTEN, or null.
   *
   * Both refusals are already on screen as prose, beside the field that caused them — but a
   * submit that quietly did nothing is the swallowed click all over again, and the button
   * that made it is at the bottom of a modal, a long way from either sentence. So the press
   * answers in its own place too.
   */
  const blocked = noEnvironments
    ? 'Tick at least one environment before saving.'
    : defaultsError !== null
      ? 'These defaults could not be read, so they cannot be overwritten from here.'
      : null;

  const submit = (): void => {
    if (busy) return;
    if (blocked) {
      setError(blocked);
      return;
    }
    setError(null);
    setBusy(true);
    void (async () => {
      try {
        await onSaveDefaults(org, {
          deploymentOwner: draft.owner === '' ? null : draft.owner,
          nameSuffix: draft.suffix,
          envBranches: applyFlags({}, draft.flags, ENVIRONMENTS),
        });
        if (patches.length > 0) await onApply(patches);
        onSaved();
      } catch (e) {
        setError((e as Error).message);
      } finally {
        setBusy(false);
      }
    })();
  };

  return (
    <form
      id={formId}
      onSubmit={(e) => {
        e.preventDefault();
        submit();
      }}
      className="flex min-w-0 flex-col gap-4"
    >
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
      </div>

      <fieldset className="flex flex-col gap-2">
        <legend className="mb-1 text-sm font-medium text-apt-text">Environments</legend>
        {ENVIRONMENTS.map((env) => (
          <label key={env} className="flex items-center gap-2 text-sm text-apt-text">
            {/* `aria-label` because the wrapping <label> names only labelable elements, and
                the checkbox is a button rather than an input. */}
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
        {/* Refused rather than silently reinterpreted: an empty ladder is STORED as "the
            built-in default", which is all of them — so saving zero boxes would come back as
            every box ticked, and look like the write was lost. */}
        {noEnvironments ? (
          <p className="text-sm text-apt-orange">
            At least one environment. An empty ladder is stored as the built-in default, which
            is every environment — so this cannot be written as you have it.
          </p>
        ) : null}
      </fieldset>

      {/* A count, not a description of the screen: how many stored rows this save moves is
          the one thing the fields above do not already show. */}
      {patches.length > 0 ? (
        <p className="text-xs text-apt-text-muted">
          {`Applies to ${patches.length} of ${rows.length} registered ${
            rows.length === 1 ? 'repository' : 'repositories'
          }.`}
        </p>
      ) : null}

      {defaultsError ? (
        <p className="text-sm text-apt-orange">
          shipr could not read this organization’s stored defaults ({defaultsError}), so the
          fields above are the convention rather than what is saved. Saving from here would
          overwrite a row nobody has seen — reopen Configure once the read works.
        </p>
      ) : null}

      <ErrorText error={error} />
    </form>
  );
}
