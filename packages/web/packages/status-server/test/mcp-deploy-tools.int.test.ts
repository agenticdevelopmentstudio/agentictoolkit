import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { deployProjectMeta } from '../src/libsql/schema';
import { ALL_TOOLS } from '../src/mcp/tools';
import { freshDb, type Db } from './helpers/db';
import { stubVercelAccount, type FakeVercelAccount } from './helpers/vercel-account';
import { testConfig } from './helpers/config';

// The MCP tools are TWINS of GET /deploy-projects and /deploy-projects/unconfigured — an
// agent asking "what's deployed" must get the same answer a human does. When only the REST
// routes re-verified the Vercel project table, the tools kept serving the stale mirror, so
// an agent could act on a project that no longer exists (and re-create a site the operator
// had just deleted). Both now go through the same refresh-then-enumerate read.

const tool = (name: string) => {
  const t = ALL_TOOLS.find((x) => x.name === name);
  if (!t) throw new Error(`no such tool: ${name}`);
  return t;
};

describe('MCP deploy-project tools re-verify the project mirror', () => {
  let db: Db;
  let account: FakeVercelAccount;

  beforeEach(async () => {
    db = await freshDb();
    account = await stubVercelAccount(db);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.unstubAllEnvs();
  });

  it('list_platform_projects drops a project deleted at the platform', async () => {
    account.add('mcp-live');
    await db.insert(deployProjectMeta).values({ platform: 'vercel', projectName: 'mcp-ghost', domain: 'ghost.example.test' });

    const out = (await tool('list_platform_projects').execute(db, {}, testConfig())) as { projectName: string }[];

    expect(out.map((p) => p.projectName)).toEqual(['mcp-live']);
    // The refresh corrected the mirror itself, exactly as the REST read does.
    expect((await db.select().from(deployProjectMeta)).map((r) => r.projectName)).toEqual(['mcp-live']);
  });

  it('find_unconfigured_sites never offers a project deleted at the platform', async () => {
    account.add('mcp-live');
    await db.insert(deployProjectMeta).values({ platform: 'vercel', projectName: 'mcp-ghost', domain: 'ghost.example.test' });

    const out = (await tool('find_unconfigured_sites').execute(db, {}, testConfig())) as {
      pending: { projectName: string }[];
      addable: { projectName: string }[];
    };

    expect(out.pending.map((p) => p.projectName)).toEqual(['mcp-live']);
    expect(out.addable.map((p) => p.projectName)).toEqual(['mcp-live']);
  });
});
