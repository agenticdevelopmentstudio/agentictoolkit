import { describe, expect, it, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import { SettingsForm, type SettingsTarget } from '../settings/SettingsForm';
import type { DevRepo, RepoItem } from '../types';

/**
 * THE OTHER HALF OF "the provision button did nothing".
 *
 * `useSettle.test.tsx` pins the waiting; this pins what the operator SEES because of it —
 * that the button stays busy for the whole run rather than flicking back on the 202, and
 * that a failed run's own words land under the button that was pressed instead of in a run
 * queue behind the modal.
 */

const DEV: DevRepo = {
  id: 'dev-1',
  slug: 'agenticdevelopmentstudio/thing',
  displayName: null,
  mainBranch: 'main',
  preparedBranch: 'prepared',
  declarationSha: null,
  connectionId: 'conn-1',
};

function mirror(registeredAt: string | null): RepoItem {
  return {
    id: 'm1',
    devRepoId: DEV.id,
    groupId: null,
    slug: 'DeploymentRepos/thing-deployment',
    shard: 'all',
    shipBranch: 'ship',
    ciContext: 'gate',
    envBranches: {},
    registeredAt,
    position: 0,
    devRepo: null,
    state: null,
  };
}

function draw(
  onProvision: (devRepoId: string) => Promise<void> | void,
  registeredAt: string | null = null,
) {
  const target: SettingsTarget = {
    kind: 'devRepo',
    devRepo: DEV,
    mirrors: [mirror(registeredAt)],
  };
  return render(
    <SettingsForm
      target={target}
      onSave={() => Promise.resolve()}
      onSaved={() => {}}
      onProvision={onProvision}
    />,
  );
}

const provision = () => screen.getByRole('button', { name: /^(Provision|Doctor)$/ });

describe('the Provision button', () => {
  it('stays busy for the whole run, not just the request that queued it', async () => {
    // Nothing ever settles this — the state the button was previously WRONG about, because
    // it resolved on the 202 and went back to reading "Provision" while the forge was
    // still being written to.
    const onProvision = vi.fn(() => new Promise<void>(() => {}));
    draw(onProvision);

    await userEvent.click(provision());

    await waitFor(() =>
      expect(screen.getByRole('button', { name: 'Provisioning…' })).toBeDisabled(),
    );
    expect(onProvision).toHaveBeenCalledWith(DEV.id);
  });

  it('draws the run’s own failure under the button that was pressed', async () => {
    const said =
      'POST /orgs/DeploymentRepos/repos — the forge answered 403: Resource not accessible by integration';
    draw(() => Promise.reject(new Error(said)));

    await userEvent.click(provision());

    // The whole defect in one assertion: the operator learns the run failed, and why,
    // without leaving the dialog they pressed the button in.
    expect(await screen.findByText(said)).toBeInTheDocument();
    await waitFor(() => expect(provision()).not.toBeDisabled());
  });

  it('says Checking… while re-running against a pipeline that already exists', async () => {
    // Provision and Doctor are the same run; only the label differs, off `registeredAt`.
    draw(() => new Promise<void>(() => {}), '2026-09-01T10:00:00Z');
    expect(provision()).toHaveAccessibleName('Doctor');

    await userEvent.click(provision());

    await waitFor(() =>
      expect(screen.getByRole('button', { name: 'Checking…' })).toBeDisabled(),
    );
  });

  it('clears a previous verdict when it is pressed again', async () => {
    const onProvision = vi
      .fn<(devRepoId: string) => Promise<void>>()
      .mockRejectedValueOnce(new Error('the forge said no'))
      .mockImplementationOnce(() => new Promise<void>(() => {}));
    draw(onProvision);

    await userEvent.click(provision());
    expect(await screen.findByText('the forge said no')).toBeInTheDocument();

    await waitFor(() => expect(provision()).not.toBeDisabled());
    await userEvent.click(provision());

    // A stale failure sitting under a running button is a verdict on the wrong run.
    await waitFor(() =>
      expect(screen.queryByText('the forge said no')).not.toBeInTheDocument(),
    );
  });
});
