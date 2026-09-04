import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import { Toolbar } from '../toolbar/Toolbar';
import { toolbarState } from '../toolbar/actions';
import { EMPTY_SELECTION, type Selection } from '../selection';
import type { ActionId } from '../toolbar/actions';
import type { AccessVerb } from '../types';

const ALL: AccessVerb[] = ['C', 'R', 'U', 'D', 'M'];
const REPO: Partial<Selection> = { focus: { kind: 'repo', id: 'r1' } };

function handlers() {
  return {
    onRun: vi.fn(),
    onDeploy: vi.fn(),
    onCancel: vi.fn(),
    onConfigure: vi.fn(),
    onIntegrations: vi.fn(),
  };
}

function draw(
  opts: {
    selection?: Partial<Selection>;
    verbs?: AccessVerb[];
    busy?: boolean;
    active?: ActionId | null;
  } = {},
) {
  const h = handlers();
  render(
    <Toolbar
      state={toolbarState({
        selection: { ...EMPTY_SELECTION, ...(opts.selection ?? REPO) },
        verbs: opts.verbs ?? ALL,
        busy: opts.busy,
        hasGroups: true,
      })}
      active={opts.active ?? null}
      {...h}
    />,
  );
  return h;
}

describe('Toolbar', () => {
  it('does not repeat the target the breadcrumb underneath it already names', () => {
    // The bar sits directly above a breadcrumb that ends in the selected row's own name,
    // so "on <target>" beside the buttons was that name printed twice an inch apart. What
    // is irreversible still says its target: the deploy dialog heads with it.
    draw();
    expect(screen.queryByTestId('shipr-toolbar-target')).toBeNull();
    expect(screen.queryByText(/^on /)).toBeNull();
  });

  it('carries the three pipeline verbs, the way back out, and the way in', () => {
    // The folder verbs moved into the rail's gear menu, where they sit beside the row they
    // act on. What is left is what the bar was for — plus Cancel, which is not a fourth verb
    // but the inverse of the other three, and Configure, which is not a verb at all: it is
    // the door to where the rows came from. Order is asserted, not just membership: the two
    // doors come after the four verbs, and Integrations comes last of all — it is the only
    // control here that is about neither the selection nor this console's own contents.
    draw();
    const labels = screen
      .getAllByRole('button')
      .map((b) => b.getAttribute('aria-label'));
    expect(labels).toEqual([
      'Status',
      'Prepare',
      'Deploy',
      'Cancel — Nothing is running.',
      'Configure',
      'Integrations',
    ]);
  });

  it('stands the verbs down and Cancel up while work is out', () => {
    // The whole point of the pair: a bar where every control is dead has taken the console
    // away for as long as the run lasts, and "I pressed Deploy on the wrong folder" needs an
    // answer that is a button rather than the browser's stop. Configure stays live beside it
    // because reading which repositories are registered is not a second run — and the dialog
    // refuses its OWN writes while the console is busy, which is the honest place for that.
    // Integrations stays live for the same reason, and a harder one: a run that failed to
    // reach the forge is exactly when an operator goes looking at the credentials.
    draw({ busy: true });
    const enabled = screen
      .getAllByRole('button')
      .filter((b) => !(b as HTMLButtonElement).disabled)
      .map((b) => b.textContent);
    expect(enabled).toEqual(['Cancel', 'Configure', 'Integrations']);
  });

  it('opens Configure for a viewer who may not change a thing', async () => {
    // A grey Configure would be the wrong refusal in the wrong place: what a viewer cannot do
    // is Add and Remove, and both are inside, each with its own reason on it. Locking them
    // out of the LIST as well would hide the settings they are allowed to read.
    const h = draw({ verbs: ['R'] });
    const configure = screen.getByRole('button', { name: 'Configure' });
    expect(configure).not.toBeDisabled();
    await userEvent.click(configure);
    expect(h.onConfigure).toHaveBeenCalledTimes(1);
    expect(h.onRun).not.toHaveBeenCalled();
  });

  it('opens Integrations from the bar, without going through Configure first', async () => {
    // The whole point of moving it out. It used to be a button on Configure's repository
    // list, two clicks in and filed under the rows that depend on it; a viewer who cannot
    // register anything still gets in, because reading which forges this console can reach
    // is not a write and the dialog refuses its own.
    const h = draw({ verbs: ['R'] });
    const integrations = screen.getByRole('button', { name: 'Integrations' });
    expect(integrations).not.toBeDisabled();
    await userEvent.click(integrations);
    expect(h.onIntegrations).toHaveBeenCalledTimes(1);
    expect(h.onConfigure).not.toHaveBeenCalled();
  });

  it('stops the work when Cancel is pressed', async () => {
    const h = draw({ busy: true });
    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));
    expect(h.onCancel).toHaveBeenCalledTimes(1);
  });

  it('spins the button that started the work, and only that one', () => {
    // Four grey buttons say a run is happening but not WHICH, and greyed out the three verbs
    // are the same shape. The spinner rides IN PLACE OF the icon, so the bar does not reflow
    // under a pointer that is still resting on the button that was just clicked.
    draw({ busy: true, active: 'deploy' });
    const running = screen
      .getAllByRole('button')
      .filter((b) => b.getAttribute('data-running') === 'true')
      .map((b) => b.textContent);
    expect(running).toEqual(['Deploy']);
    expect(
      screen.getByRole('button', { name: 'Deploy — running' }),
    ).toBeTruthy();
  });

  it('runs status on the current target', async () => {
    const h = draw();
    await userEvent.click(screen.getByRole('button', { name: 'Status' }));
    expect(h.onRun).toHaveBeenCalledWith('status');
  });

  it('puts the refusal in the accessible name of a dead button', async () => {
    // A disabled control with no explanation is indistinguishable from a broken one, and
    // `title` on a disabled button is not announced everywhere.
    draw({ verbs: ['R'] });
    expect(
      screen.getByRole('button', {
        name: 'Prepare — You cannot move branches in this workspace.',
      }),
    ).toBeDisabled();
  });

  it('hides no button a caller lacks the verb for — it explains it instead', () => {
    draw({ verbs: [] });
    expect(screen.getByRole('button', { name: /^Status — / })).toBeTruthy();
  });

  it('greys all three out until something is selected', () => {
    draw({ selection: {} });
    for (const label of ['Status', 'Prepare', 'Deploy']) {
      expect(
        screen.getByRole('button', {
          name: `${label} — Select a repository or a folder first.`,
        }),
      ).toBeDisabled();
    }
  });

  it('opens the deploy form rather than firing straight at an environment', async () => {
    // Deploy is the only verb that takes an argument, so it asks. A control with
    // production one click away is a control that eventually gets clicked by accident.
    const h = draw();
    await userEvent.click(screen.getByRole('button', { name: 'Deploy' }));
    expect(h.onDeploy).toHaveBeenCalledTimes(1);
    expect(h.onRun).not.toHaveBeenCalled();
  });

  it('will not open the deploy form while a run is in flight', async () => {
    const h = draw({ busy: true });
    const deploy = screen.getByRole('button', {
      name: 'Deploy — A run is already in flight.',
    });
    expect(deploy).toBeDisabled();
    await userEvent.click(deploy);
    expect(h.onDeploy).not.toHaveBeenCalled();
  });
});
