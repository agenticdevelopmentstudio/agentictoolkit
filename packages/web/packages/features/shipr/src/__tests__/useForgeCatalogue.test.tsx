import { renderHook, waitFor } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';

import { useForgeCatalogue } from '../forge/useForgeCatalogue';
import type { ForgeConnection, ForgeRepository } from '../types';

/**
 * THE READ, WHICH USED TO BE INSIDE THE ADD PICKER.
 *
 * Every assertion here was a `RegisterWizard` test until the read moved up to the console —
 * they are the same three failures, asked of the thing that now owns them. The move is the
 * fix for all three: the round trip is paid once when the console comes up rather than on
 * every opening of a dialog, a failed installation keeps its place in the menu, and "is that
 * account reachable at all" becomes a question with an answer.
 *
 * The one behaviour with no ancestor is {@link ForgeCatalogue.installedOn}: the deployment
 * target may be an org the source repository is not in, and "we cannot see that account" and
 * "that repository is not there" are different sentences. Collapsing them is what produced
 * `POST /orgs/DeploymentRepos/repos — 403: Resource not accessible by integration`.
 */

const CONNECTIONS: ForgeConnection[] = [
  { id: 'c1', label: 'acme app', accountLogin: 'acme' },
  { id: 'c2', label: 'sandbox app', accountLogin: 'sandbox' },
];

const ACME: ForgeRepository[] = [
  { slug: 'acme/site', defaultBranch: 'trunk', private: true },
  { slug: 'acme/taken', defaultBranch: 'main', private: false },
];

const SANDBOX: ForgeRepository[] = [
  { slug: 'sandbox/toys', defaultBranch: 'main', private: false },
];

/** A moment ago, in the shape the wire uses. The value never matters — what matters is that
 *  both reads carry one, because a stored list announcing its age is what makes showing it
 *  honest rather than a guess. */
const READ_AT = '2026-09-01T12:00:00.000Z';

function clientOf(over: {
  stored?: Record<string, ForgeRepository[]>;
  storedError?: Record<string, string>;
  refreshed?: Record<string, ForgeRepository[]>;
  refreshError?: Record<string, string>;
}) {
  return {
    connectionRepositories: vi.fn(async (id: string) => {
      const failure = over.storedError?.[id];
      if (failure) throw new Error(failure);
      return { repositories: over.stored?.[id] ?? [], readAt: READ_AT };
    }),
    refreshConnectionRepositories: vi.fn(async (id: string) => {
      const failure = over.refreshError?.[id];
      if (failure) throw new Error(failure);
      return {
        repositories: over.refreshed?.[id] ?? over.stored?.[id] ?? [],
        readAt: READ_AT,
      };
    }),
  };
}

const slugsOf = (repos: readonly ForgeRepository[]) => repos.map((r) => r.slug);

describe('useForgeCatalogue', () => {
  it('reads every installation, unprompted, rather than asking which one', async () => {
    // There used to be a dropdown, and the wizard read only whichever installation it
    // happened to open on — so a repository granted to the other one was invisible until the
    // operator guessed which of two identical-looking apps to switch to.
    const client = clientOf({ stored: { c1: ACME, c2: SANDBOX } });
    const { result } = renderHook(() => useForgeCatalogue(client, CONNECTIONS));

    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(client.connectionRepositories).toHaveBeenCalledWith('c1');
    expect(client.connectionRepositories).toHaveBeenCalledWith('c2');
    expect(result.current.orgs!.map((o) => o.login)).toEqual(['acme', 'sandbox']);
  });

  it('draws on what was written down, and asks the forge behind it', async () => {
    const client = clientOf({ stored: { c1: ACME } });
    const { result } = renderHook(() => useForgeCatalogue(client, [CONNECTIONS[0]!]));

    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(client.connectionRepositories).toHaveBeenCalledWith('c1');
    expect(client.refreshConnectionRepositories).toHaveBeenCalledWith('c1');
  });

  it('swaps in what the refresh returned', async () => {
    const client = clientOf({
      stored: { c1: ACME },
      refreshed: { c1: [{ slug: 'acme/newly-granted', defaultBranch: 'main', private: false }] },
    });
    const { result } = renderHook(() => useForgeCatalogue(client, [CONNECTIONS[0]!]));

    await waitFor(() =>
      expect(slugsOf(result.current.orgs![0]!.repositories)).toEqual(['acme/newly-granted']),
    );
  });

  it('leaves the stored list standing when the refresh fails, with the reason beside it', async () => {
    // A list read an hour ago is a list you can pick from. An empty box is not, and replacing
    // one with the other is the trade the cache exists to stop making — but a stale list that
    // says nothing is the other half of the same mistake, so both survive.
    const client = clientOf({
      stored: { c1: ACME },
      refreshError: { c1: 'installation suspended' },
    });
    const { result } = renderHook(() => useForgeCatalogue(client, [CONNECTIONS[0]!]));

    await waitFor(() => expect(result.current.orgs![0]!.error).toBe('installation suspended'));
    expect(slugsOf(result.current.orgs![0]!.repositories)).toEqual([
      'acme/site',
      'acme/taken',
    ]);
  });

  it('keeps an installation whose read failed in the list, with its own reason', async () => {
    // THE BUG THIS HOOK WAS EXTRACTED FOR. The org menu was derived from the returned rows,
    // so an installation whose read failed contributed no rows and therefore no org — four
    // accounts connected, three on screen, and nothing naming the fourth or saying why.
    const client = clientOf({
      stored: { c1: ACME },
      storedError: { c2: 'installation suspended' },
      refreshError: { c2: 'installation suspended' },
    });
    const { result } = renderHook(() => useForgeCatalogue(client, CONNECTIONS));

    await waitFor(() => expect(result.current.loading).toBe(false));
    const [acme, sandbox] = result.current.orgs!;
    expect(acme!.login).toBe('acme');
    expect(slugsOf(acme!.repositories)).toEqual(['acme/site', 'acme/taken']);
    // Present, empty, and carrying its own reason — the failure is per-account because that
    // is the granularity it happens at.
    expect(sandbox!.login).toBe('sandbox');
    expect(sandbox!.repositories).toEqual([]);
    expect(sandbox!.error).toBe('installation suspended');
    // And the CATALOGUE's own error stays null: the connection list was read fine.
    expect(result.current.error).toBeNull();
  });

  it('holds the accounts unread rather than empty until the connections land', async () => {
    // `undefined` and `[]` say different things to every screen below — "still reading" and
    // "nothing is connected" — so the unread state is passed through rather than defaulted.
    const client = clientOf({});
    const { result } = renderHook(() => useForgeCatalogue(client, undefined));

    expect(result.current.orgs).toBeUndefined();
    expect(result.current.loading).toBe(true);
    expect(client.connectionRepositories).not.toHaveBeenCalled();
  });

  it('carries the reason the connection list itself could not be read', async () => {
    const client = clientOf({});
    const { result } = renderHook(() =>
      useForgeCatalogue(client, undefined, 'network is down'),
    );
    expect(result.current.error).toBe('network is down');
  });

  it('names the installation a slug came out of, not the first one read', async () => {
    // A register needs an installation that can actually reach the repository, and which one
    // that is is not something anybody knows by heart.
    const client = clientOf({ stored: { c1: ACME, c2: SANDBOX } });
    const { result } = renderHook(() => useForgeCatalogue(client, CONNECTIONS));

    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.connectionOf('sandbox/toys')).toBe('c2');
    expect(result.current.connectionOf('acme/site')).toBe('c1');
    expect(result.current.connectionOf('elsewhere/thing')).toBeUndefined();
  });

  it('answers whether an account is reachable at all, which absence cannot', async () => {
    // THE THIRD ANSWER a deployment target needs. `DeploymentRepos` granting nothing and
    // `DeploymentRepos` being unreachable look identical from the rows.
    const client = clientOf({ stored: { c1: ACME, c2: SANDBOX } });
    const { result } = renderHook(() => useForgeCatalogue(client, CONNECTIONS));

    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.installedOn('sandbox')).toBe(true);
    expect(result.current.installedOn('DeploymentRepos')).toBe(false);
  });

  it('does not spend a round trip on a re-render that changed nothing', async () => {
    // The effect is keyed on WHICH connections exist, not on the array's identity: a console
    // that re-renders on every tree read would otherwise re-read the forge each time.
    const client = clientOf({ stored: { c1: ACME } });
    const { result, rerender } = renderHook(
      ({ connections }: { connections: ForgeConnection[] }) =>
        useForgeCatalogue(client, connections),
      { initialProps: { connections: [CONNECTIONS[0]!] } },
    );

    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(client.connectionRepositories).toHaveBeenCalledTimes(1);

    rerender({ connections: [{ ...CONNECTIONS[0]! }] });
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(client.connectionRepositories).toHaveBeenCalledTimes(1);
  });

  it('asks again when told to', async () => {
    const client = clientOf({ stored: { c1: ACME } });
    const { result } = renderHook(() => useForgeCatalogue(client, [CONNECTIONS[0]!]));

    await waitFor(() => expect(result.current.loading).toBe(false));
    result.current.refresh();
    await waitFor(() => expect(client.refreshConnectionRepositories).toHaveBeenCalledTimes(2));
  });

  it('falls back to the rows for an account the connect flow never named', async () => {
    // An installation whose `accountLogin` was never recorded still has to appear under a
    // name, or its repositories are reachable and its org is not.
    const client = clientOf({ stored: { c1: ACME } });
    const { result } = renderHook(() =>
      useForgeCatalogue(client, [{ id: 'c1', label: 'some app', accountLogin: null }]),
    );

    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.orgs![0]!.login).toBe('acme');
  });
});
