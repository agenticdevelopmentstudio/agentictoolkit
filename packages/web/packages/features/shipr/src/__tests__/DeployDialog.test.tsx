import { describe, expect, it, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import { DeployDialog } from '../toolbar/dialogs';

/** A box in the form. Matched loosely: the box carries its own `aria-label` AND sits inside
 *  a <label> saying the same word, so the computed name says it twice — a fact about the
 *  name computation, not about the control. */
function tick(name: RegExp): Promise<HTMLElement> {
  return screen.findByRole('checkbox', { name });
}

function deployButton(): HTMLElement {
  return screen.getByRole('button', { name: 'Deploy' });
}

function draw(over: { onSubmit?: () => Promise<void>; onClose?: () => void } = {}) {
  const onSubmit = vi.fn(over.onSubmit ?? (() => Promise.resolve()));
  const onClose = vi.fn(over.onClose ?? (() => {}));
  const view = render(
    <DeployDialog
      open
      onClose={onClose}
      targetLabel="acme/site-deployment"
      onSubmit={onSubmit}
    />,
  );
  return { onSubmit, onClose, ...view };
}

describe('DeployDialog — nothing happens until it is answered', () => {
  it('names what it is about to deploy', async () => {
    draw();
    expect(
      await screen.findByRole('heading', { name: 'Deploy acme/site-deployment' }),
    ).toBeTruthy();
  });

  it('opens with every box clear, and Deploy dead', async () => {
    // There is no such thing as a deploy to nowhere, and a dialog that opens pre-ticked is
    // one Return away from shipping a decision nobody made.
    draw();
    for (const name of [/Prepare/, /testing/, /staging/, /production/]) {
      expect(await tick(name)).toHaveAttribute('aria-checked', 'false');
    }
    expect(deployButton()).toBeDisabled();
  });

  it('wakes on a single tick — prepare alone is a complete request', async () => {
    // Prepare is not one of the environments: it is the step on the way there, so it can be
    // the whole answer.
    draw();
    await userEvent.click(await tick(/Prepare/));
    expect(deployButton()).toBeEnabled();
  });

  it('goes dead again when the last box is cleared', async () => {
    draw();
    const staging = await tick(/staging/);
    await userEvent.click(staging);
    expect(deployButton()).toBeEnabled();
    await userEvent.click(staging);
    expect(deployButton()).toBeDisabled();
  });
});

describe('DeployDialog — All and None', () => {
  it('ticks every environment without touching Prepare', async () => {
    // All is about the environments it sits over. Sweeping Prepare in with them would make
    // the one control that is not an environment behave like one.
    draw();
    await userEvent.click(screen.getByRole('button', { name: 'All' }));
    for (const name of [/testing/, /staging/, /production/]) {
      expect(await tick(name)).toHaveAttribute('aria-checked', 'true');
    }
    expect(await tick(/Prepare/)).toHaveAttribute('aria-checked', 'false');
  });

  it('clears the environments and leaves Prepare standing', async () => {
    draw();
    await userEvent.click(await tick(/Prepare/));
    await userEvent.click(screen.getByRole('button', { name: 'All' }));
    await userEvent.click(screen.getByRole('button', { name: 'None' }));
    expect(await tick(/production/)).toHaveAttribute('aria-checked', 'false');
    expect(await tick(/Prepare/)).toHaveAttribute('aria-checked', 'true');
    // Prepare on its own is still a request, so the button stays live.
    expect(deployButton()).toBeEnabled();
  });
});

describe('DeployDialog — what it submits', () => {
  it('hands back the environments in LADDER order, not tick order', async () => {
    // Ticking production first does not deploy production first: the backend walks testing,
    // staging, production, and the request has to say what it means in that order.
    const { onSubmit } = draw();
    await userEvent.click(await tick(/production/));
    await userEvent.click(await tick(/testing/));
    await userEvent.click(deployButton());
    await waitFor(() =>
      expect(onSubmit).toHaveBeenCalledWith({
        prepare: false,
        environments: ['testing', 'production'],
      }),
    );
  });

  it('closes once the runs are away', async () => {
    const { onClose } = draw();
    await userEvent.click(await tick(/staging/));
    await userEvent.click(deployButton());
    await waitFor(() => expect(onClose).toHaveBeenCalled());
  });

  it('stays open, saying why, when the request is refused', async () => {
    // Closing on a failure loses both the error and the choice that produced it.
    const { onClose } = draw({
      onSubmit: () => Promise.reject(new Error('a run is already in flight')),
    });
    await userEvent.click(await tick(/staging/));
    await userEvent.click(deployButton());
    expect(await screen.findByText('a run is already in flight')).toBeTruthy();
    expect(onClose).not.toHaveBeenCalled();
  });
});

describe('DeployDialog — the keyboard', () => {
  it('sends the request on Return, because Deploy is the form’s default action', async () => {
    const { onSubmit } = draw();
    await userEvent.click(await tick(/testing/));
    await userEvent.keyboard('{Enter}');
    await waitFor(() =>
      expect(onSubmit).toHaveBeenCalledWith({
        prepare: false,
        environments: ['testing'],
      }),
    );
  });

  it('does nothing on Return while Deploy is dead', async () => {
    const { onSubmit } = draw();
    await userEvent.keyboard('{Enter}');
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it('leaves on Escape without running anything', async () => {
    // The property that makes pressing Deploy safe to do by accident.
    const { onSubmit, onClose } = draw();
    await userEvent.click(await tick(/production/));
    await userEvent.keyboard('{Escape}');
    await waitFor(() => expect(onClose).toHaveBeenCalled());
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it('runs nothing when Cancel is pressed', async () => {
    const { onSubmit, onClose } = draw();
    await userEvent.click(await tick(/production/));
    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));
    expect(onClose).toHaveBeenCalled();
    expect(onSubmit).not.toHaveBeenCalled();
  });
});

describe('DeployDialog — it remembers nothing between openings', () => {
  it('clears last time’s ticks when it opens again', async () => {
    // A dialog that remembers is a dialog that deploys to production because of a decision
    // made an hour ago.
    const { rerender } = draw();
    await userEvent.click(await tick(/production/));
    rerender(
      <DeployDialog
        open={false}
        onClose={() => {}}
        targetLabel="acme/site-deployment"
        onSubmit={() => Promise.resolve()}
      />,
    );
    rerender(
      <DeployDialog
        open
        onClose={() => {}}
        targetLabel="acme/site-deployment"
        onSubmit={() => Promise.resolve()}
      />,
    );
    expect(await tick(/production/)).toHaveAttribute('aria-checked', 'false');
    expect(deployButton()).toBeDisabled();
  });
});
