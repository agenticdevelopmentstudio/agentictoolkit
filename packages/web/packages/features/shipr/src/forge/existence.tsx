'use client';

import * as React from 'react';

import type { ForgeCatalogue } from './useForgeCatalogue';

/**
 * IS THAT DEPLOYMENT REPOSITORY ALREADY THERE — asked before anything is created, answered
 * off the catalogue rather than by another round trip.
 *
 * THIS QUESTION COST A DAY. Registering a repository whose deployment repository already
 * exists and registering one that creates it are the same press, and the difference only
 * surfaced minutes later inside a run, as
 * `POST /orgs/DeploymentRepos/repos — the forge answered 403: Resource not accessible by
 * integration`: the App was installed on one account and the deployment repository lived in
 * another, so shipr could not SEE the repository sitting right there, reported it absent, and
 * tried to create it. Every part of that is knowable before a run is queued, so it is said
 * where the operator sets the name.
 *
 * THE ANSWER IS READ OFF THE GRANTS, NOT FETCHED. Every installation's repositories are
 * already held by {@link ForgeCatalogue} — that is what the Add picker is a list of — so
 * asking again would be a round trip to learn something already on this machine.
 *
 * FIVE ANSWERS, NOT TWO, and the three extra ones are the whole point. shipr sees exactly the
 * repositories its installations were granted, so "not in the grant" can mean the account is
 * unreachable, or that its read failed, or that the read has not landed yet — and none of
 * those is "it does not exist". Collapsing them into `absent` is precisely the reasoning that
 * produced the 403 above, one level down, in the server, with a create attached to it.
 */
export type Verdict =
  | 'checking'
  | 'present'
  | 'absent'
  /** No installation reaches that account, so the question cannot be asked at all. */
  | 'no-installation'
  /** There IS an installation and its read failed, which is a different fix. */
  | 'unreadable';

/** `owner/name` → `owner`. The wire guarantees the shape, so this is a split, not a parse. */
export function ownerOf(slug: string): string {
  return slug.slice(0, slug.indexOf('/'));
}

/** `owner/name` → `name`. */
export function nameOf(slug: string): string {
  return slug.slice(slug.indexOf('/') + 1);
}

export function verdictFor(slug: string, catalogue: ForgeCatalogue): Verdict {
  const orgs = catalogue.orgs;
  if (orgs === undefined) return 'checking';
  const org = orgs.find((o) => o.login === ownerOf(slug));
  if (!org) return 'no-installation';
  if (org.loading) return 'checking';
  if (org.repositories.some((r) => r.slug === slug)) return 'present';
  // Order matters: a grant that CONTAINS the slug answers the question even if a later
  // refresh failed, and only a list with nothing in it has to fall back to the failure.
  if (org.error !== null) return 'unreadable';
  return 'absent';
}

/** One line under the name, in the operator's words rather than the API's. */
export function Existence({
  slug,
  catalogue,
}: {
  slug: string;
  catalogue: ForgeCatalogue;
}): React.ReactElement {
  const verdict = verdictFor(slug, catalogue);
  const owner = ownerOf(slug);

  if (verdict === 'checking') {
    return (
      <p className="text-sm text-apt-text-muted">
        Checking whether <span className="text-apt-text">{slug}</span> exists…
      </p>
    );
  }
  if (verdict === 'present') {
    return (
      <p className="text-sm text-apt-text-muted">
        <span className="text-apt-text">{slug}</span> already exists — provisioning will adopt
        it.
      </p>
    );
  }
  if (verdict === 'absent') {
    return (
      <p className="text-sm text-apt-text-muted">
        <span className="text-apt-text">{slug}</span> does not exist yet — provisioning will
        create it.
      </p>
    );
  }
  if (verdict === 'unreadable') {
    const org = (catalogue.orgs ?? []).find((o) => o.login === owner);
    return (
      <p className="text-sm text-apt-orange">
        shipr could not read <span className="text-apt-text">{owner}</span>’s repositories
        {org?.error ? ` (${org.error})` : ''}, so it cannot tell whether{' '}
        <span className="text-apt-text">{slug}</span> is already there.
      </p>
    );
  }
  // Not a warning decoration for its own sake: this is the state that fails LATER, in a run,
  // with a 403 nobody reading it would connect back to an installation. Said here it is one
  // sentence and one link away from fixed.
  return (
    <p className="text-sm text-apt-orange">
      shipr holds no GitHub App installation on <span className="text-apt-text">{owner}</span>,
      so it cannot tell whether <span className="text-apt-text">{slug}</span> exists — and
      provisioning would fail trying to create it. Add an installation on that account under
      Integrations.
    </p>
  );
}
