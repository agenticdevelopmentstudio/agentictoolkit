import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import { ShiprConsole } from '../ShiprConsole';
import type { ShiprClient } from '../client';
import type { RepoItem, TreeResponse } from '../types';

// The live channels are the one thing in this component that reaches outside the process.
// Stubbed to inert handles: what is under test here is the SHAPE of the console — which
// panes exist and what the controls do — and a real EventSource in jsdom is just a failure
// mode with no bearing on that.
vi.mock('../live', () => ({
  watchRun: () => ({ close: vi.fn() }),
  watchWorkspaceRuns: () => ({ close: vi.fn() }),
}));

/**
 * The Connections dialog's two outside edges, stubbed — because two specs below open it.
 *
 * `#connections` in the address opens that dialog, whose body resolves the workspace's
 * infrastructure ecosystem, which is a real `GET /api/ecosystem/ecosystems` against an unmocked
 * `fetch`. It never made the spec fail: the assertion resolves first and react-query swallows
 * the rejection, so the request left as an unhandled fetch to a host jsdom has no route to —
 * passing, then, for a reason unrelated to what is under test, and failing later against
 * whatever a future runner does with real network calls.
 *
 * `CONNECTIONS_HASH` is the REAL one (`importOriginal`): it is the string both ends of the OAuth
 * round-trip must agree on, and this file's whole point is that the console recognises it. A
 * spelled copy here would agree with itself while the product disagreed.
 */
vi.mock('@agentic-toolkit/data/ecosystems', () => ({
  useWorkspaceDefaultEcosystemId: () => ({
    ecosystemId: 'eco-1',
    canManage: true,
    isPending: false,
    isFetching: false,
    isError: false,
  }),
}));

vi.mock('@agentic-toolkit/integrations', async (importOriginal) => ({
  CONNECTIONS_HASH: (
    await importOriginal<typeof import('@agentic-toolkit/integrations')>()
  ).CONNECTIONS_HASH,
  IntegrationsPane: () => <div data-testid="integrations-pane" />,
}));

const repo: RepoItem = {
  id: 'm1',
  devRepoId: 'd1',
  groupId: null,
  slug: 'acme/site-deployment',
  shard: 'all',
  shipBranch: 'ship',
  ciContext: 'deploy/ci',
  envBranches: { testing: 'testing', staging: 'staging', production: 'production' },
  registeredAt: null,
  position: 0,
  devRepo: null,
  state: null,
};

const tree: TreeResponse = {
  workspace: { kind: 'customer', ownerId: 'c1' },
  verbs: ['C', 'R', 'U', 'D', 'M'],
  groups: [],
  items: [repo],
};

function stubClient(over: Partial<ShiprClient> = {}): ShiprClient {
  return {
    workspace: undefined,
    tree: vi.fn().mockResolvedValue(tree),
    runs: vi.fn().mockResolvedValue({ items: [] }),
    run: vi.fn().mockResolvedValue({ runId: 'run1' }),
    repo: vi.fn().mockResolvedValue({
      repo,
      devRepo: null,
      group: null,
      ladder: null,
      runs: [],
    }),
    ...over,
  } as unknown as ShiprClient;
}

/** A checkbox in the deploy form. Matched loosely: the box carries its own `aria-label`
 *  AND sits inside a <label> whose text says the same word, so the computed name says it
 *  twice — which is a fact about the name computation, not about the control. */
function tick(name: RegExp): Promise<HTMLElement> {
  return screen.findByRole('checkbox', { name });
}

/** Click the one repository row in the rail, which is how everything else gets a target. */
async function chooseRepo(): Promise<void> {
  await userEvent.click(
    await screen.findByRole('button', { name: /site-deployment/ }),
  );
}

beforeEach(() => {
  window.localStorage.clear();
});

describe('ShiprConsole — one view, not two', () => {
  it('has no activity pane and no divider of its own', async () => {
    // The log used to be a second column showing whichever run was most recent anywhere in
    // the workspace — a pane about a different subject than the one selected beside it. The
    // output moved to where its subject is, and the split went with it.
    render(<ShiprConsole client={stubClient()} />);
    await screen.findByRole('button', { name: /site-deployment/ });
    expect(screen.queryByRole('region', { name: 'Activity log' })).toBeNull();
    expect(
      screen.queryByRole('separator', { name: 'Repositories and activity' }),
    ).toBeNull();
  });

  it('asks for a choice before it shows anything', async () => {
    render(<ShiprConsole client={stubClient()} />);
    expect(
      await screen.findByText(/Choose a repository to see where its branches/),
    ).toBeTruthy();
  });

  it('shows the chosen repository’s ladder, and nothing under it to say there is nothing', async () => {
    // Nothing has been run against this repository, so there is no output — and an absence
    // is not output. The ladder says "Never read"; a grey shelf below it saying the same
    // thing in different words is the pane reporting a problem it does not have.
    render(<ShiprConsole client={stubClient()} />);
    await chooseRepo();
    expect(await screen.findByText(/Never read/)).toBeTruthy();
    expect(screen.queryByRole('region', { name: 'Latest output' })).toBeNull();
  });
});

describe('ShiprConsole — the three verbs need a target', () => {
  it('will not run anything while nothing is selected', async () => {
    const client = stubClient();
    render(<ShiprConsole client={client} />);
    const status = await screen.findByRole('button', {
      name: 'Status — Select a repository or a folder first.',
    });
    expect(status).toBeDisabled();
    await userEvent.click(status);
    expect(client.run).not.toHaveBeenCalled();
  });

  it('runs the chosen repository once a row is picked', async () => {
    const client = stubClient();
    render(<ShiprConsole client={client} />);
    await chooseRepo();
    await userEvent.click(screen.getByRole('button', { name: 'Status' }));
    await waitFor(() =>
      expect(client.run).toHaveBeenCalledWith({
        operation: 'status',
        scopeKind: 'deploy_repo',
        scopeId: 'm1',
      }),
    );
  });
});

describe('ShiprConsole — the gear menu', () => {
  it('carries the housekeeping verbs the toolbar used to', async () => {
    render(<ShiprConsole client={stubClient()} />);
    await userEvent.click(
      await screen.findByRole('button', { name: 'Folder and selection actions' }),
    );
    for (const label of [/^Add directory/, /^Move/, /^Settings/]) {
      expect(await screen.findByRole('menuitem', { name: label })).toBeTruthy();
    }
  });

  it('greys the selection entries out until something is selected', async () => {
    render(<ShiprConsole client={stubClient()} />);
    await userEvent.click(
      await screen.findByRole('button', { name: 'Folder and selection actions' }),
    );
    expect(
      await screen.findByRole('menuitem', {
        name: 'Move — Select something to move.',
      }),
    ).toHaveAttribute('data-disabled');
  });

  it('kills Rename once the row is a repository, and offers no way out of the forge', async () => {
    // Rename is a FOLDER's verb — a repository is named by the forge — and the entry is drawn
    // either way so the menu keeps its height and its entries under the pointer as rows are
    // clicked. Unregister is not drawn AT ALL any more: taking a repository back out is the
    // Configure dialog's, beside the Add that put it in, behind a typed confirmation.
    render(<ShiprConsole client={stubClient()} />);
    await chooseRepo();
    await userEvent.click(
      screen.getByRole('button', { name: 'Folder and selection actions' }),
    );
    expect(
      await screen.findByRole('menuitem', { name: /^Rename/ }),
    ).toHaveAttribute('data-disabled');
    expect(screen.queryByRole('menuitem', { name: /Unregister/ })).toBeNull();
  });

  it('puts Configure on the bar instead, live with nothing selected', async () => {
    // The one control on this bar that is not about the selection, and therefore the one that
    // is never refused for the lack of one.
    render(<ShiprConsole client={stubClient()} />);
    expect(
      await screen.findByRole('button', { name: 'Configure' }),
    ).not.toBeDisabled();
  });

  /**
   * The far end of a forge connect. Connecting a GitHub App leaves the app entirely, so this
   * console is torn down and rebuilt; `/integrations/oauth-callback` routes back to the URL
   * the connect started on, and `#connections` is the part of it that says where in here the
   * operator was. Without this the new connection lands on a bare tree with every dialog
   * closed, which reads as the connect having failed rather than succeeded.
   */
  it('reopens Connections when the address names it', async () => {
    window.history.replaceState(null, '', '/acme?workspace=acme#connections');
    try {
      render(<ShiprConsole client={stubClient()} />);
      expect(await screen.findByText('Integrations', { selector: '[data-slot="dialog-title"]' }))
        .toBeTruthy();
      // And ONLY that one. Connections used to be a child of Configure, so the return leg
      // opened both and landed the operator on repository settings they had not asked for,
      // with the dialog they left to fill stacked on top of it.
      expect(
        screen.queryByText('Configure', { selector: '[data-slot="dialog-title"]' }),
      ).toBeNull();
    } finally {
      window.history.replaceState(null, '', '/');
    }
  });

  it('opens Connections from Integrations on the bar, with nothing selected', async () => {
    // The forge accounts are the ecosystem's, not this tree's — so the button that opens them
    // is live from the moment the console is, and it is a sibling of Configure rather than
    // something inside it.
    render(<ShiprConsole client={stubClient()} />);
    const integrations = await screen.findByRole('button', { name: 'Integrations' });
    expect(integrations).not.toBeDisabled();
    await userEvent.click(integrations);
    expect(
      await screen.findByText('Integrations', { selector: '[data-slot="dialog-title"]' }),
    ).toBeTruthy();
    expect(
      screen.queryByText('Configure', { selector: '[data-slot="dialog-title"]' }),
    ).toBeNull();
  });

  it('leaves Configure shut on an ordinary load', async () => {
    render(<ShiprConsole client={stubClient()} />);
    await screen.findByRole('button', { name: 'Configure' });
    expect(
      screen.queryByText('Configure', { selector: '[data-slot="dialog-title"]' }),
    ).toBeNull();
  });
});

describe('ShiprConsole — deploy asks first', () => {
  it('opens a form, and stays dead until something is ticked', async () => {
    const client = stubClient();
    render(<ShiprConsole client={client} />);
    await chooseRepo();
    await userEvent.click(screen.getByRole('button', { name: 'Deploy' }));

    const submit = await screen.findByRole('button', { name: 'Deploy' });
    expect(submit).toBeDisabled();
    expect(client.run).not.toHaveBeenCalled();
  });

  it('turns prepare + two environments into three runs, in that order', async () => {
    // Splitting them here rather than posting one run with three environments is what keeps
    // each environment's verdict separable — and the order is the ladder's, not the order
    // the boxes were ticked.
    const client = stubClient();
    render(<ShiprConsole client={client} />);
    await chooseRepo();
    await userEvent.click(screen.getByRole('button', { name: 'Deploy' }));

    await userEvent.click(await tick(/production/));
    await userEvent.click(await tick(/testing/));
    await userEvent.click(await tick(/Prepare/));
    await userEvent.click(screen.getByRole('button', { name: 'Deploy' }));

    await waitFor(() => expect(client.run).toHaveBeenCalledTimes(3));
    const calls = (client.run as ReturnType<typeof vi.fn>).mock.calls.map(
      ([body]) => [body.operation, body.environments?.[0]],
    );
    expect(calls).toEqual([
      ['prepare', undefined],
      ['deploy', 'testing'],
      ['deploy', 'production'],
    ]);
  });

  it('runs nothing when the form is cancelled', async () => {
    const client = stubClient();
    render(<ShiprConsole client={client} />);
    await chooseRepo();
    await userEvent.click(screen.getByRole('button', { name: 'Deploy' }));
    await userEvent.click(await tick(/staging/));
    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));
    expect(client.run).not.toHaveBeenCalled();
  });
});


/**
 * A settable container width plus a hand-fired ResizeObserver.
 *
 * jsdom lays nothing out: every `clientWidth` is 0 and no ResizeObserver ever fires, so a
 * component that decides its layout by measuring itself sits forever at whatever it does
 * with 0. Both halves are stubbed so a width can be chosen before the render and then
 * MOVED after it — one frame of a window drag, which is the thing Mike described.
 *
 * A local copy of the harness in `ui`'s hierarchicalTopicDetail.test.tsx, not an import:
 * a test helper crossing a package boundary would make that file's private scaffolding
 * public API, and this is fifteen lines.
 */
function installResizeHarness(initial: number) {
  let width = initial;
  const observers: (() => void)[] = [];
  const realRO = globalThis.ResizeObserver;
  const realWidth = Object.getOwnPropertyDescriptor(HTMLElement.prototype, 'clientWidth');
  globalThis.ResizeObserver = class {
    constructor(private cb: () => void) {}
    observe() {
      observers.push(this.cb);
    }
    unobserve() {}
    disconnect() {}
  } as unknown as typeof globalThis.ResizeObserver;
  Object.defineProperty(HTMLElement.prototype, 'clientWidth', {
    configurable: true,
    get: () => width,
  });
  return {
    resizeTo(next: number) {
      width = next;
      act(() => {
        observers.forEach((cb) => cb());
      });
    },
    restore() {
      globalThis.ResizeObserver = realRO;
      if (realWidth) Object.defineProperty(HTMLElement.prototype, 'clientWidth', realWidth);
      else delete (HTMLElement.prototype as unknown as Record<string, unknown>).clientWidth;
    },
  };
}

/** The wide stack renders the detail pane as its own element; the narrow one folds it into
 *  the `data-htd-col` sequence and shows exactly one at a time. So the presence of
 *  `[data-htd-detail]` IS the answer to "did it collapse", read off the DOM rather than off
 *  a class name or a prop. */
const isNarrow = () => document.querySelector('[data-htd-detail]') === null;

describe('ShiprConsole — the rail gives way on a phone', () => {
  // "this completely breaks the site on iPhone" (Mike). The threshold itself is pinned in
  // the ui package; what those tests cannot see is whether THIS composition reaches it.
  // Three things here are shipr's and not the block's: `minDetailWidth="32rem"`, the
  // `flex min-h-0 min-w-0 flex-1 flex-col` wrapper the console renders around the block,
  // and adh's 12px root — and all three feed the same arithmetic. A regression in any of
  // them shows up as a site that does not collapse while every ui test stays green.
  let harness: ReturnType<typeof installResizeHarness>;
  let realRootFont: string;

  beforeEach(() => {
    // adh sets `html` to 12px, and the floor is computed from it: `minDetailWidth="32rem"`
    // is 384px here, not 512. Left at jsdom's 16px this suite would be measuring a floor
    // no browser on the site ever uses.
    realRootFont = document.documentElement.style.fontSize;
    document.documentElement.style.fontSize = '12px';
    harness = installResizeHarness(1200);
  });

  afterEach(() => {
    harness.restore();
    document.documentElement.style.fontSize = realRootFont;
  });

  it('shows rail and detail together on a desktop column', async () => {
    render(<ShiprConsole client={stubClient()} />);
    await screen.findByRole('button', { name: /site-deployment/ });
    expect(isNarrow()).toBe(false);
  });

  it('folds to one pane when the window is dragged down to a phone', async () => {
    render(<ShiprConsole client={stubClient()} />);
    await screen.findByRole('button', { name: /site-deployment/ });
    expect(isNarrow()).toBe(false);
    // 390 is an iPhone's CSS width. The floor is max(384 + 32, 480) = 480, so this is
    // under it by 90px and there is no reading of the arithmetic that leaves it wide.
    harness.resizeTo(390);
    expect(isNarrow()).toBe(true);
    // One pane REACHABLE, not two side by side — the actual complaint. The narrow stack
    // keeps every pane mounted and slides between them, so counting `[data-htd-col]` would
    // count the ones parked off-screen too; the honest question is how many a reader can
    // reach, and `aria-hidden` is where that is written down.
    expect(document.querySelectorAll('[data-htd-col]:not([aria-hidden])')).toHaveLength(1);
  });

  it('lands narrow when the phone is the width it STARTS at, not only when dragged there', async () => {
    // The drag above and this are different code paths: one is a resize callback, the other
    // is the first measurement. A phone visitor only ever takes this one.
    harness.resizeTo(390);
    render(<ShiprConsole client={stubClient()} />);
    await screen.findByRole('button', { name: /site-deployment/ });
    expect(isNarrow()).toBe(true);
  });

  it('comes back to two panes when the window is dragged wide again', async () => {
    render(<ShiprConsole client={stubClient()} />);
    await screen.findByRole('button', { name: /site-deployment/ });
    harness.resizeTo(390);
    expect(isNarrow()).toBe(true);
    harness.resizeTo(1200);
    expect(isNarrow()).toBe(false);
  });
});

/**
 * A FAULT IS AN ALERT, NOT PART OF THE BAR (Mike: "do not randomly show error messages in
 * thing like toolbars, create alerts or something"). A failed read used to print the
 * backend's own prose — `Internal Server Error` — into a line directly above the toolbar,
 * where it read as a label on the controls and, because a failing poll re-sets it forever,
 * stayed there for the length of the outage.
 */
describe('ShiprConsole — faults are raised, not printed into the chrome', () => {
  it('raises the failure as a dismissable alert', async () => {
    render(
      <ShiprConsole
        client={stubClient({
          tree: vi.fn().mockRejectedValue(new Error('Internal Server Error')),
        })}
      />,
    );

    const alert = await screen.findByRole('dialog', { name: /shipr hit a problem/ });
    expect(alert).toHaveTextContent('Internal Server Error');

    await userEvent.click(within(alert).getByRole('button', { name: 'OK' }));
    await waitFor(() =>
      expect(screen.queryByRole('dialog', { name: /shipr hit a problem/ })).toBeNull(),
    );
    // And it is GONE, not moved into the frame: the message must not survive the dismissal
    // anywhere on screen.
    expect(screen.queryByText('Internal Server Error')).toBeNull();
  });

  it('raises nothing at all for a failure that carries no message', async () => {
    // `new Error()` has an empty `message`, and the catch that fills `error` copies it
    // through unread. Keyed on null alone, that empty string counts as a fault and opens a
    // dialog with a title and no body — strictly worse than the silence it replaced, since
    // there is nothing in it to act on and nothing to say what went wrong.
    render(
      <ShiprConsole
        client={stubClient({ tree: vi.fn().mockRejectedValue(new Error()) })}
      />,
    );

    await waitFor(() => expect(screen.queryAllByRole('dialog')).toHaveLength(0));
  });
});
