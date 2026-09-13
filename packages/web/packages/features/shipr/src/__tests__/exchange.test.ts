import { describe, expect, it, vi } from 'vitest';

import { applyImport, ImportError } from '../exchange/apply';
import {
  DocumentError,
  buildDocument,
  parseDocument,
  serializeDocument,
  writtenBy,
  type ExportableRepo,
  type ShiprDocument,
} from '../exchange/document';
import { downloadDocument } from '../exchange/files';
import { planImport, registerBodyOf } from '../exchange/plan';
import type { Group, RepoItem } from '../types';

/**
 * The file the CLI and this console both speak, and what reading one does.
 *
 * THE FIXTURE BELOW IS THE PYTHON'S OUTPUT, hand-copied from `tools/shipr/exchange.py`'s
 * `build`. That is the whole risk this file exists to cover: the format has two
 * implementations in two languages with no shared artefact between them, so the failure mode
 * is not a crash — it is a file that parses on both sides and means something different on
 * each. A round trip through code that only ever talks to itself would prove nothing about
 * that, so the parse is tested against a document written the way Python writes one.
 */
const FROM_THE_CLI = {
  schema: 'shipr-config-export',
  schema_version: 1,
  shipr_version: '25.2.0',
  exported_at: '2026-09-02T18:08:34Z',
  root: '~/Deployments',
  groups: ['billing'],
  projects: [
    {
      name: 'olylo',
      directory: 'olylo-deployment',
      group: null,
      remotes: {
        dev: { slug: 'acme/olylo', url: 'https://github.com/acme/olylo.git' },
        deployment: {
          slug: 'acme/olylo-deployment',
          url: 'https://github.com/acme/olylo-deployment.git',
        },
      },
      config: {
        version: 4,
        main_branch: 'main',
        prepared_branch: 'prepared',
        ship_branch: 'ship',
        environments: { testing: 'testing', production: 'production' },
        ci: { context: 'gate' },
      },
    },
    {
      name: 'billing-api',
      directory: 'billing-api-deployment',
      group: 'billing',
      remotes: {
        dev: { slug: 'acme/billing-api' },
        deployment: { slug: 'acme/billing-api-deployment' },
      },
      config: { version: 4, main_branch: 'main', ship_branch: 'ship' },
    },
  ],
};

const text = () => JSON.stringify(FROM_THE_CLI, null, 2) + '\n';

function repo(over: Partial<RepoItem> = {}): RepoItem {
  return {
    id: 'm1',
    devRepoId: 'd1',
    groupId: null,
    slug: 'acme/olylo-deployment',
    shard: 'all',
    shipBranch: 'ship',
    ciContext: 'gate',
    envBranches: { testing: 'testing', production: 'production' },
    registeredAt: null,
    position: 0,
    devRepo: {
      id: 'd1',
      slug: 'acme/olylo',
      mainBranch: 'main',
      preparedBranch: 'prepared',
      declarationSha: null,
      connectionId: 'c1',
    },
    state: null,
    ...over,
  };
}

const group = (over: Partial<Group> = {}): Group => ({
  id: 'g1',
  parentId: null,
  name: 'billing',
  path: 'billing',
  depth: 0,
  position: 0,
  ...over,
});

describe('the document', () => {
  it('reads a file the CLI wrote', () => {
    const doc = parseDocument(text());
    expect(doc.projects).toHaveLength(2);
    expect(doc.projects[0]!.remotes.deployment.slug).toBe('acme/olylo-deployment');
    expect(doc.projects[0]!.config.environments).toEqual({
      testing: 'testing',
      production: 'production',
    });
    // The layout, which is the half no config file holds.
    expect(doc.projects[1]!.group).toBe('billing');
    expect(doc.projects[0]!.group).toBeNull();
  });

  it('carries a config key it has never heard of through unchanged', () => {
    // A document written by a later shipr of the SAME schema version may carry keys this
    // console does not model. Dropping them silently would make a round trip lossy.
    const raw = structuredClone(FROM_THE_CLI) as typeof FROM_THE_CLI & {
      projects: { config: Record<string, unknown> }[];
    };
    raw.projects[0]!.config.something_later = ['a', 'b'];
    expect(parseDocument(JSON.stringify(raw)).projects[0]!.config.something_later).toEqual([
      'a',
      'b',
    ]);
  });

  it('refuses a file that is not one of ours, by name', () => {
    expect(() => parseDocument(JSON.stringify({ projects: [] }))).toThrow(DocumentError);
    expect(() => parseDocument(JSON.stringify({ projects: [] }))).toThrow(
      /not a shipr-config-export file/,
    );
  });

  it('refuses a newer schema rather than reading the fields it recognizes', () => {
    const newer = { ...FROM_THE_CLI, schema_version: 2 };
    expect(() => parseDocument(JSON.stringify(newer))).toThrow(/newer shipr/);
  });

  it('refuses an entry with nowhere to go', () => {
    const raw = { ...FROM_THE_CLI, projects: [{ name: 'olylo' }] };
    expect(() => parseDocument(JSON.stringify(raw))).toThrow(/no `directory`/);
  });

  it('names itself rather than inventing a shipr version', () => {
    const doc = buildDocument({ groups: [group()], items: [repo() as ExportableRepo] });
    expect(doc.shipr_version).toBeUndefined();
    expect(doc.exported_by).toBe('shipr console');
    expect(writtenBy(doc)).toBe('shipr console');
    expect(writtenBy(parseDocument(text()))).toBe('shipr 25.2.0');
  });

  it('builds one entry per deployment repository, with its folder and its config', () => {
    const doc = buildDocument({
      groups: [group()],
      items: [
        repo({ groupId: 'g1' }) as ExportableRepo,
        repo({
          id: 'm2',
          slug: 'acme/billing-api-deployment',
          groupId: 'g1',
          envBranches: {},
        }) as ExportableRepo,
      ],
      exportedAt: '2026-09-02T18:08:34Z',
    });
    expect(doc.groups).toEqual(['billing']);
    expect(doc.projects.map((p) => [p.name, p.directory, p.group])).toEqual([
      ['olylo', 'olylo-deployment', 'billing'],
      ['billing-api', 'billing-api-deployment', 'billing'],
    ]);
    expect(doc.projects[0]!.config).toEqual({
      version: 4,
      main_branch: 'main',
      prepared_branch: 'prepared',
      ship_branch: 'ship',
      environments: { testing: 'testing', production: 'production' },
      ci: { context: 'gate' },
    });
    // Slugs only: a URL built here would be `doctor`'s own fallback written down as
    // though it had been observed.
    expect(doc.projects[0]!.remotes).toEqual({
      dev: { slug: 'acme/olylo' },
      deployment: { slug: 'acme/olylo-deployment' },
    });
  });

  it('skips a mirror whose source this caller never reached', () => {
    const doc = buildDocument({ groups: [], items: [repo({ devRepo: null }) as ExportableRepo] });
    expect(doc.projects).toEqual([]);
  });

  it('is read back by its own parser', () => {
    const doc = buildDocument({ groups: [group()], items: [repo({ groupId: 'g1' }) as ExportableRepo] });
    expect(parseDocument(serializeDocument(doc))).toEqual(doc);
    expect(serializeDocument(doc).endsWith('\n')).toBe(true);
  });
});

describe('the plan', () => {
  it('marks a project this console has never seen as a registration', () => {
    const plan = planImport({ document: parseDocument(text()), groups: [], items: [] });
    expect(plan.rows.map((r) => r.state)).toEqual(['new', 'new']);
    expect(plan.counts).toEqual({ new: 2, differs: 0, same: 0, blocked: 0 });
    // The folder the second one names does not exist here, so it is queued to be made —
    // once, however many projects are filed under it.
    expect(plan.newGroups).toEqual(['billing']);
  });

  it('marks a project that is already exactly as written', () => {
    const plan = planImport({
      document: parseDocument(text()),
      groups: [],
      items: [repo()],
    });
    expect(plan.rows[0]!.state).toBe('same');
    expect(plan.rows[0]!.changes).toEqual([]);
  });

  it('names what differs, and patches only that', () => {
    const plan = planImport({
      document: parseDocument(text()),
      groups: [],
      items: [repo({ shipBranch: 'release', envBranches: { testing: 'testing' } })],
    });
    const row = plan.rows[0]!;
    expect(row.state).toBe('differs');
    expect(row.patch).toEqual({
      shipBranch: 'ship',
      envBranches: { testing: 'testing', production: 'production' },
    });
    expect(row.changes.join(' ')).toContain('ship branch');
  });

  it('says out loud what it will not carry rather than dropping it', () => {
    const raw = structuredClone(FROM_THE_CLI);
    raw.projects[0]!.config.main_branch = 'trunk';
    raw.projects[0]!.config.environments = { testing: 'testing', canary: 'canary' } as never;
    const plan = planImport({
      document: parseDocument(JSON.stringify(raw)),
      groups: [],
      items: [repo()],
    });
    const notes = plan.rows[0]!.notes.join(' ');
    // Fixed at registration: there is no route on the wire that changes it, and a file
    // that disagrees is usually the first sign the two fleets are not the same fleet.
    expect(notes).toContain('main branch');
    expect(notes).toContain('fixed at registration');
    // An environment this console does not deploy to.
    expect(notes).toContain('canary');
  });

  it('files a repository the way the document does', () => {
    const plan = planImport({
      document: parseDocument(text()),
      groups: [group()],
      items: [repo({ id: 'm2', slug: 'acme/billing-api-deployment', groupId: null })],
    });
    const row = plan.rows.find((r) => r.project.directory === 'billing-api-deployment')!;
    expect(row.state).toBe('differs');
    expect(row.patch).toMatchObject({ groupId: 'g1' });
    expect(plan.newGroups).toEqual([]);
  });

  it('makes a folder rather than guessing between two of the same name', () => {
    const plan = planImport({
      document: parseDocument(text()),
      groups: [group({ id: 'g1' }), group({ id: 'g2', parentId: 'gX', depth: 1 })],
      items: [],
    });
    expect(plan.newGroups).toEqual(['billing']);
  });

  it('refuses a source that is here under a differently-named deployment repository', () => {
    // A second deployment repository for one source is a SHARD, and shards are declared in
    // the repository's own `.shipr`. Registering the source again is what the backend
    // refuses, so the refusal is said here, where it can name the file that must change.
    const plan = planImport({
      document: parseDocument(text()),
      groups: [],
      items: [repo({ slug: 'acme/olylo-web-deployment' })],
    });
    expect(plan.rows[0]!.state).toBe('blocked');
    expect(plan.rows[0]!.reason).toContain('.shipr');
  });

  it('refuses an entry that names no development repository', () => {
    const raw = structuredClone(FROM_THE_CLI);
    raw.projects[0]!.remotes.dev = {} as never;
    const plan = planImport({
      document: parseDocument(JSON.stringify(raw)),
      groups: [],
      items: [],
    });
    expect(plan.rows[0]!.state).toBe('blocked');
    expect(plan.rows[0]!.reason).toContain('no development repository');
  });

  it('asks register for the deployment repository the file names', () => {
    const plan = planImport({ document: parseDocument(text()), groups: [], items: [] });
    expect(registerBodyOf(plan.rows[0]!, 'g1', 'c9')).toEqual({
      slug: 'acme/olylo',
      connectionId: 'c9',
      groupId: 'g1',
      mainBranch: 'main',
      preparedBranch: 'prepared',
      deploymentOwner: 'acme',
      deploymentName: 'olylo-deployment',
    });
  });
});

describe('applying a plan', () => {
  const client = (over: Partial<Parameters<typeof applyImport>[0]['client']> = {}) => ({
    createGroup: vi.fn(async ({ name }: { name: string }) => ({
      id: `g-${name}`,
      parentId: null,
      name,
      path: name,
      depth: 0,
      position: 0,
    })),
    register: vi.fn(async () => ({ runId: 'r1', devRepo: null as never })),
    updateRepo: vi.fn(async () => repo()),
    ...over,
  });

  it('makes the folders first, so the registrations have one to go in', async () => {
    const c = client();
    const plan = planImport({ document: parseDocument(text()), groups: [], items: [] });
    const result = await applyImport({ client: c as never, plan, groups: [], connectionId: 'c9' });

    expect(result.groupsCreated).toEqual(['billing']);
    expect(c.createGroup.mock.invocationCallOrder[0]).toBeLessThan(
      c.register.mock.invocationCallOrder[0]!,
    );
    expect(c.register).toHaveBeenCalledTimes(2);
    // The one filed under `billing` goes in the folder that was just made.
    expect((c.register.mock.calls[1]![0] as { groupId: string }).groupId).toBe('g-billing');
    expect(result.registered).toEqual([
      { slug: 'acme/olylo', runId: 'r1' },
      { slug: 'acme/billing-api', runId: 'r1' },
    ]);
  });

  it('writes only the settings that differ, and touches nothing that is already right', async () => {
    const c = client();
    const plan = planImport({
      document: parseDocument(text()),
      groups: [group()],
      items: [repo({ shipBranch: 'release' }), repo({
        id: 'm2',
        slug: 'acme/billing-api-deployment',
        groupId: 'g1',
        shipBranch: 'ship',
        envBranches: {},
        ciContext: '',
      })],
    });
    const result = await applyImport({ client: c as never, plan, groups: [group()] });

    expect(c.register).not.toHaveBeenCalled();
    expect(c.updateRepo).toHaveBeenCalledTimes(1);
    expect(c.updateRepo.mock.calls[0]).toEqual(['m1', { shipBranch: 'ship' }]);
    expect(result.updated).toEqual(['acme/olylo-deployment']);
  });

  it('keeps the runs it already started when a later call fails', async () => {
    // They are runs walking branches on a forge whether or not the next call succeeded. A
    // failure that reported only a message would drop them: no queue, no rail, no Cancel.
    const c = client({
      register: vi
        .fn()
        .mockResolvedValueOnce({ runId: 'r1' })
        .mockRejectedValueOnce(new Error('that installation was revoked')),
    });
    const plan = planImport({ document: parseDocument(text()), groups: [], items: [] });

    const thrown: ImportError = await applyImport({
      client: c as never,
      plan,
      groups: [],
    }).then(
      () => {
        throw new Error('the second registration was supposed to fail');
      },
      (e: ImportError) => e,
    );

    expect(thrown).toBeInstanceOf(ImportError);
    expect(thrown.message).toBe('that installation was revoked');
    expect(thrown.result.registered.map((r) => r.runId)).toEqual(['r1']);
  });

  it('never attempts a blocked row, and says which it left', async () => {
    const c = client();
    const plan = planImport({
      document: parseDocument(text()),
      groups: [],
      items: [repo({ slug: 'acme/olylo-web-deployment' })],
    });
    const result = await applyImport({ client: c as never, plan, groups: [] });

    expect(result.skipped.map((s) => s.name)).toEqual(['olylo']);
    expect(c.register).toHaveBeenCalledTimes(1); // the other one, which is not blocked
  });
});

describe('the download', () => {
  it('hands over the document as a file, and lets go of the blob', async () => {
    const created = vi.fn(() => 'blob:x');
    const revoked = vi.fn();
    vi.stubGlobal('URL', { ...URL, createObjectURL: created, revokeObjectURL: revoked });
    const click = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
    vi.useFakeTimers();

    const doc = buildDocument({ groups: [], items: [repo() as ExportableRepo] }) as ShiprDocument;
    await downloadDocument(doc);

    expect(click).toHaveBeenCalled();
    // And nothing is left in the DOM to be clicked again.
    expect(document.querySelector('a[download]')).toBeNull();
    vi.runAllTimers();
    expect(revoked).toHaveBeenCalledWith('blob:x');

    vi.useRealTimers();
    click.mockRestore();
    vi.unstubAllGlobals();
  });
});
