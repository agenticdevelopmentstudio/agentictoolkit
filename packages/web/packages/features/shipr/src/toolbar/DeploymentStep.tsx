'use client';

import * as React from 'react';

import { Input } from '@agenticdevelopertoolkit/ui/components/input';
import { Label } from '@agenticdevelopertoolkit/ui/components/label';
import { Select } from '@agenticdevelopertoolkit/ui/components/select';

import type { DeclarationResponse } from '../types';

/**
 * REGISTER, SECOND SCREEN: where this repository's mirror goes, and whether it is already there.
 *
 * The picker before it answers "which repository"; this answers "and deploy it to what". They
 * are two questions and this is two screens, because the picker is a list you scan and this is
 * three facts you read — putting them on one pane made the list the loser every time.
 *
 * THE THIRD FACT IS THE ONE THAT COST A DAY. A register whose deployment repository already
 * exists and a register that creates one are the same two clicks, and the difference only
 * surfaces minutes later inside a run. It surfaced as
 * `POST /orgs/DeploymentRepos/repos — the forge answered 403: Resource not accessible by
 * integration`: the App was installed on one account and the deployment repository lives in
 * another, so shipr could not SEE the repository that was sitting right there, reported it
 * absent, and tried to create it. Every part of that is knowable here, before anything is
 * queued, so it is said here.
 *
 * The existence answer is READ OFF THE GRANTS, not fetched. Every installation's repositories
 * are already on screen behind this — that is what the picker is a list of — so asking again
 * would be a round trip to learn something this component was handed. It also makes the third
 * state honest and free: a slug we cannot find in an account we hold NO installation on is not
 * an absent repository, it is an unanswered question, and those must not wear the same
 * sentence. {@link Verdict} is that distinction.
 *
 * WHAT THE FILE SAYS WINS, and this screen says so rather than pretending to offer a choice.
 * A dev repo whose committed `.shipr` declares `[deployments]` already named every mirror, and
 * the server reads the file — `fallbackSlug` is consulted only when it declares none. So a form
 * that let an operator type an org over a declared shard would be a control whose value is
 * discarded on submit, which is worse than no control. Declared: the shards are shown, and
 * there is nothing to fill in.
 */

/** `owner/name` → `owner`. The wire guarantees the shape, so this is a split, not a parse. */
function ownerOf(slug: string): string {
  return slug.slice(0, slug.indexOf('/'));
}

/** `owner/name` → `name`. */
function nameOf(slug: string): string {
  return slug.slice(slug.indexOf('/') + 1);
}

/**
 * The three answers to "is it there already?", which are three and not two.
 *
 * `unknowable` is the whole reason this is an enum: shipr sees exactly the repositories its
 * installations were granted, so an account with no installation yields an empty grant, and
 * "not in the grant" there means "we cannot look", not "it does not exist". Collapsing that
 * into `absent` is precisely the reasoning that produced the 403 above — one level down, in the
 * server, and with a create attached to it.
 */
type Verdict = 'present' | 'absent' | 'unknowable';

function verdictFor(
  slug: string,
  granted: ReadonlySet<string>,
  installedOn: ReadonlySet<string>,
): Verdict {
  if (granted.has(slug)) return 'present';
  return installedOn.has(ownerOf(slug)) ? 'absent' : 'unknowable';
}

/** One line under the slug, in the operator's words rather than the API's. */
function Existence({ slug, verdict }: { slug: string; verdict: Verdict }): React.ReactElement {
  if (verdict === 'present') {
    return (
      <p className="text-sm text-apt-text-muted">
        <span className="text-apt-text">{slug}</span> already exists — registering will use it.
      </p>
    );
  }
  if (verdict === 'absent') {
    return (
      <p className="text-sm text-apt-text-muted">
        <span className="text-apt-text">{slug}</span> does not exist yet — registering will
        create it.
      </p>
    );
  }
  // Not a warning decoration for its own sake: this is the state that fails LATER, in a run,
  // with a 403 nobody reading it would connect back to an installation. Said here it is one
  // sentence and one link away from fixed.
  return (
    <p className="text-sm text-apt-orange">
      shipr holds no GitHub App installation on <span className="text-apt-text">{ownerOf(slug)}</span>
      , so it cannot tell whether <span className="text-apt-text">{slug}</span> exists — and a
      run would fail trying to create it. Add an installation on that account under Integrations.
    </p>
  );
}

export interface DeploymentStepProps {
  /** The dev repo the picker settled on — `owner/name`. Shown, never edited: changing it means
   *  going back to the list, which is what Cancel is for. */
  devSlug: string;
  /** What the dev repo's `.shipr` declares, `null` while the read is still out. */
  declaration: DeclarationResponse | null;
  /** Why the declaration could not be read. The screen still works without it — the convention
   *  is computable here — but it says so rather than showing a fallback as if it were the file. */
  declarationError?: string | null;
  /** Every repository every installation granted, by slug. The picker's own list, deduped —
   *  see the note above on why this is handed over rather than re-fetched. */
  granted: ReadonlySet<string>;
  /** The accounts shipr holds an installation on. Both the org menu's options and the thing
   *  that separates "not there" from "cannot look". */
  installedOn: readonly string[];
  owner: string;
  name: string;
  onOwnerChange: (owner: string) => void;
  onNameChange: (name: string) => void;
}

export function DeploymentStep({
  devSlug,
  declaration,
  declarationError = null,
  granted,
  installedOn,
  owner,
  name,
  onOwnerChange,
  onNameChange,
}: DeploymentStepProps): React.ReactElement {
  const accounts = React.useMemo(() => new Set(installedOn), [installedOn]);

  /**
   * The org menu's options.
   *
   * The installations, plus the dev repo's own owner and whatever is currently selected. The
   * last two are not padding: a declared shard or a `.shipr` convention can name an account
   * shipr holds no installation on — which is the case worth showing most of all — and a menu
   * that silently dropped it would answer the question by hiding it.
   */
  const orgs = React.useMemo(
    () => [...new Set([...installedOn, ownerOf(devSlug), owner])].filter(Boolean).sort(),
    [installedOn, devSlug, owner],
  );

  // Still out. The read is the only thing that can answer which of the two branches below is
  // the truth, so there is nothing honest to draw yet.
  if (declaration === null && declarationError === null) {
    return (
      <div className="flex min-h-0 flex-1 flex-col gap-3">
        <p className="text-sm text-apt-text-muted">Reading {devSlug}’s .shipr…</p>
      </div>
    );
  }

  // THE DECLARED BRANCH. Read-only on purpose — see the header. Each shard still gets its
  // existence line, because "the file names it" and "it is there" are different claims and the
  // second one is the one a run acts on.
  if (declaration !== null && declaration.deployments !== null) {
    return (
      <div className="flex min-h-0 flex-1 flex-col gap-3 overflow-auto">
        <p className="text-sm text-apt-text-muted">
          <span className="text-apt-text">{devSlug}</span>’s committed <code>.shipr</code> names
          its deployment repositories, so shipr uses those and there is nothing to choose here.
        </p>
        {declaration.deployments!.map((shard) => (
          <div key={shard.shard} className="flex flex-col gap-1">
            <Label>{shard.shard}</Label>
            <Existence
              slug={shard.slug}
              verdict={verdictFor(shard.slug, granted, accounts)}
            />
          </div>
        ))}
        {declaration.note ? (
          <p className="text-xs text-apt-text-muted">{declaration.note}</p>
        ) : null}
      </div>
    );
  }

  // THE FALLBACK BRANCH: the file declares nothing, so these two fields are what the server
  // will use. `fallbackSlug` seeded them (in the wizard, on the read landing) rather than a
  // convention spelled again here — the server computes it so a console and a workstation
  // cannot land on two different deployment repositories.
  const slug = `${owner}/${name}`;
  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3 overflow-auto">
      {declarationError !== null ? (
        // A FAILED READ IS NOT A DEAD END, and it is not a licence to guess either. The fields
        // come up empty rather than pre-filled with a convention spelled here — that string is
        // the server's to compute — and the sentence says why they are empty and what still
        // outranks them.
        <p className="text-sm text-apt-orange">
          Could not read <span className="text-apt-text">{devSlug}</span>’s <code>.shipr</code>:{' '}
          {declarationError}. Name the deployment repository yourself — if the file turns out to
          declare its own, what it says still wins.
        </p>
      ) : (
        <p className="text-sm text-apt-text-muted">
          <span className="text-apt-text">{devSlug}</span> declares no deployments, so shipr will
          mirror it to:
        </p>
      )}

      <div className="flex flex-col gap-1">
        <Label htmlFor="shipr-deploy-owner">Deployment organization</Label>
        <Select
          id="shipr-deploy-owner"
          aria-label="Deployment organization"
          value={owner}
          onChange={(e) => onOwnerChange(e.target.value)}
        >
          {orgs.map((o) => (
            <option key={o} value={o}>
              {o}
            </option>
          ))}
        </Select>
      </div>

      <div className="flex flex-col gap-1">
        <Label htmlFor="shipr-deploy-name">Deployment repository</Label>
        <Input
          id="shipr-deploy-name"
          aria-label="Deployment repository"
          value={name}
          onChange={(e) => onNameChange(e.target.value)}
        />
      </div>

      {name.trim() === '' ? (
        <p className="text-sm text-apt-orange">A deployment repository needs a name.</p>
      ) : (
        <Existence slug={slug} verdict={verdictFor(slug, granted, accounts)} />
      )}

      {declaration?.note ? (
        <p className="text-xs text-apt-text-muted">{declaration.note}</p>
      ) : null}
    </div>
  );
}

export { nameOf as deploymentNameOf, ownerOf as deploymentOwnerOf };
