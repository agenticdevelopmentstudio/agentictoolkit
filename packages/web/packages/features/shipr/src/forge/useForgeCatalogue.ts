'use client';

import * as React from 'react';

import type { ShiprClient } from '../client';
import type { ForgeConnection, ForgeRepository } from '../types';

/**
 * Every forge account the caller can reach, and every repository in it — read ONCE, held
 * above every dialog that asks.
 *
 * WHY IT IS NOT IN THE WIZARD. It used to be: an effect inside the register form, keyed on
 * the connection list, that fetched N installations' repositories every time the form was
 * mounted. Three things fell out of that, and all three are fixed by moving the read up
 * here rather than by patching it there.
 *
 * 1. IT PAID THE FORGE ROUND TRIP ON EVERY OPENING. Configure is a dialog, deliberately
 *    unmounted when it closes (see `ConfigureDialog`), so the second opening re-read what
 *    the first opening had just read. Held at the mount, the list survives every close, and
 *    the first read starts when the console does rather than when the operator gets to it.
 *
 * 2. A FAILED INSTALLATION VANISHED WITHOUT A WORD. The org menu was derived from the
 *    returned rows — `[...new Set(repos.map(ownerOf))]` — so an installation whose read
 *    failed contributed no rows and therefore no org, and the merge published
 *    `setListError(null)` whenever ANY other installation had succeeded. Four accounts
 *    connected, three in the menu, and nothing on screen naming the fourth or saying why.
 *
 *    So THE ORGS ARE SEEDED FROM THE CONNECTIONS, not from the rows. One installation is
 *    one account, so the accounts are known before a single repository is: an org whose
 *    read failed is present, empty, and carries its own {@link ForgeOrg.error}. The failure
 *    is per-org because that is the granularity it happens at — a revoked installation says
 *    nothing about the other three.
 *
 * 3. IT COULD NOT ANSWER "IS THAT ORG REACHABLE". The deployment target may be an org the
 *    source repository is not in, and whether the caller holds an installation on it is the
 *    difference between "we can create that" and "we cannot see that" — see
 *    {@link ForgeCatalogue.installedOn}. That question has no home inside a form.
 */
export interface ForgeOrg {
  /** The forge account login. */
  login: string;
  /** The installation that reaches it. One installation is one account, so this is the
   *  connection a register against any repository in this org must be made with. */
  connectionId: string;
  /** What that installation was granted, sorted by slug. Empty while the first read is out,
   *  and empty for good when {@link error} is set. */
  repositories: readonly ForgeRepository[];
  /** Why this org's list is missing or older than it looks. Null when all is well. */
  error: string | null;
  /** The first read is still out. Distinct from an empty list, which is an answer. */
  loading: boolean;
}

export interface ForgeCatalogue {
  /** Every account the caller reaches, sorted by login — INCLUDING the ones whose read
   *  failed, which is the whole point. `undefined` until the connection list itself lands. */
  orgs: readonly ForgeOrg[] | undefined;
  /** Why the connection list could not be read at all. Distinct from a per-org failure. */
  error: string | null;
  /** Any first read still out. */
  loading: boolean;
  /** Which installation granted a slug — what a register must be made with. */
  connectionOf: (slug: string) => string | undefined;
  /** Whether the caller holds an installation on an account. THE THIRD ANSWER a deployment
   *  target needs: "not there" and "cannot see" are different sentences, and only this
   *  distinguishes them. */
  installedOn: (login: string) => boolean;
  /** Ask the forge again for every installation, and store what it says. */
  refresh: () => void;
}

/** One installation's slice of the cache. */
interface Entry {
  repositories: ForgeRepository[];
  error: string | null;
  loading: boolean;
}

const bySlug = (a: ForgeRepository, b: ForgeRepository) => a.slug.localeCompare(b.slug);

/**
 * Read them, and keep them.
 *
 * `connections` is `undefined` while the caller's own read is out, and that is passed
 * through rather than defaulted: an empty catalogue and an unread one say different things
 * to every screen below.
 */
export function useForgeCatalogue(
  client: Pick<ShiprClient, 'connectionRepositories' | 'refreshConnectionRepositories'>,
  connections: readonly ForgeConnection[] | undefined,
  connectionsError: string | null = null,
): ForgeCatalogue {
  const [entries, setEntries] = React.useState<Record<string, Entry>>({});
  /** Bumped to force a re-read of installations already in {@link entries}. Nothing else
   *  re-reads them: the effect below is otherwise keyed on WHICH connections exist, so a
   *  re-render with an equal-but-new array does not spend a forge round trip. */
  const [generation, setGeneration] = React.useState(0);

  const connectionKey = (connections ?? []).map((c) => c.id).join(',');

  React.useEffect(() => {
    if (!connections) return;
    let live = true;

    const put = (id: string, next: Partial<Entry>) => {
      if (!live) return;
      setEntries((prev) => ({
        ...prev,
        [id]: {
          repositories: [],
          error: null,
          loading: false,
          ...prev[id],
          ...next,
        },
      }));
    };

    for (const connection of connections) {
      const id = connection.id;
      put(id, { loading: true });
      void (async () => {
        // The stored list first, because it is on screen without a forge round trip, and a
        // refresh that fails behind it leaves it standing. Both halves are per-connection:
        // one revoked installation must not take the other three off the menu.
        try {
          const stored = await client.connectionRepositories(id);
          put(id, {
            repositories: [...stored.repositories].sort(bySlug),
            error: null,
            loading: false,
          });
        } catch (e) {
          put(id, { error: (e as Error).message, loading: false });
        }
        try {
          const fresh = await client.refreshConnectionRepositories(id);
          put(id, {
            repositories: [...fresh.repositories].sort(bySlug),
            error: null,
            loading: false,
          });
        } catch (e) {
          // THE ROWS SURVIVE IT, and so does the reason. A refresh that failed over a good
          // stored list is a list that is OLD — replacing rows the operator can pick from
          // with a sentence about why they are gone is the trade the cache exists to stop
          // making — but dropping the reason instead would leave a list that is silently
          // stale. Both are kept, and which sentence that becomes is the reader's: an empty
          // list says it could not be read, a stored one says it is what was written down.
          if (!live) return;
          const message = (e as Error).message;
          setEntries((prev) => ({
            ...prev,
            [id]: {
              repositories: prev[id]?.repositories ?? [],
              error: message,
              loading: false,
            },
          }));
        }
      })();
    }

    return () => {
      live = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [client, connectionKey, generation]);

  const orgs = React.useMemo<ForgeOrg[] | undefined>(() => {
    if (!connections) return undefined;
    return connections
      .map((connection) => {
        const entry = entries[connection.id];
        // An installation the connect flow recorded no account for still has to appear, or
        // its repositories are reachable and its org is not. The rows know the answer even
        // when the connection row does not, so fall back to the first slug's owner.
        const login =
          connection.accountLogin ??
          entry?.repositories[0]?.slug.split('/')[0] ??
          connection.label;
        return {
          login,
          connectionId: connection.id,
          repositories: entry?.repositories ?? [],
          error: entry?.error ?? null,
          loading: entry?.loading ?? true,
        };
      })
      .sort((a, b) => a.login.localeCompare(b.login));
  }, [connections, entries]);

  const connectionOf = React.useCallback(
    (slug: string) => {
      for (const org of orgs ?? []) {
        if (org.repositories.some((r) => r.slug === slug)) return org.connectionId;
      }
      return undefined;
    },
    [orgs],
  );

  const installedOn = React.useCallback(
    (login: string) => (orgs ?? []).some((org) => org.login === login),
    [orgs],
  );

  const refresh = React.useCallback(() => setGeneration((n) => n + 1), []);

  return {
    orgs,
    error: connectionsError,
    loading: orgs === undefined || orgs.some((o) => o.loading),
    connectionOf,
    installedOn,
    refresh,
  };
}
