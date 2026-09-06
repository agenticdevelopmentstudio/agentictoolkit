import { describe, it, expect } from 'vitest';
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { existsSync, mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createClient } from '@libsql/client';
import { drizzle } from 'drizzle-orm/libsql';
import { migrate } from 'drizzle-orm/libsql/migrator';
import * as schema from '../src/libsql/schema';
import { MIGRATIONS_FOLDER } from '../src/libsql/client';
import { envConfig } from '../src/config/env';

// Regression guard for the lewis crash-loop of 2026-07-11: the monitor worker must
// come up and answer a cycle under BARE node — without tsx's loader arriving via
// execArgv inheritance, which Node 22 (the container runtime) does not honor for
// worker threads. There is no container tsx and no `.mjs` bootstrap anymore — the
// PACKAGE'S OWN `exports` map is what resolves the worker entry, exactly as
// `MonitorWorkerClient.spawn` resolves it in production, so this test fails the
// same way prod would if the built dist ever stopped being resolvable under bare
// node: every cycle errors, /health goes stale, and the supervisor restarts the
// container forever.
/** Run the driver with `workerData` piped over stdin. Resolves with the child's output
 *  on exit 0; rejects on any other exit (or on a 60s hang) with a message built from the
 *  exit status and the child's stdout/stderr ONLY — never the command line, never the
 *  payload, so a failure report can't leak `config.secrets`. */
function runDriver(
  driver: string,
  entry: string,
  workerData: string,
  env: NodeJS.ProcessEnv,
): Promise<{ stdout: string; stderr: string }> {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(process.execPath, [driver, entry], { env, cwd: resolve('.'), stdio: 'pipe' });
    let stdout = '';
    let stderr = '';
    child.stdout.setEncoding('utf8').on('data', (chunk: string) => (stdout += chunk));
    child.stderr.setEncoding('utf8').on('data', (chunk: string) => (stderr += chunk));
    const killer = setTimeout(() => child.kill('SIGKILL'), 60_000);
    child.on('error', (err) => {
      clearTimeout(killer);
      reject(new Error(`driver could not be spawned: ${err.message}`));
    });
    child.on('close', (code, signal) => {
      clearTimeout(killer);
      if (code === 0) resolvePromise({ stdout, stderr });
      else reject(new Error(`driver failed (exit ${code ?? signal})\nstdout: ${stdout}\nstderr: ${stderr}`));
    });
    child.stdin.end(workerData);
  });
}

describe('worker-boot under bare node (no inherited loader)', () => {
  it('completes a cycle round-trip via the package-resolved worker entry', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'worker-boot-'));
    const url = `file:${join(dir, 'status.db')}`;
    const db = drizzle(createClient({ url }), { schema });
    await migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });

    // The entry is the package's OWN `exports["./worker"]` target — the same map
    // `MonitorWorkerClient.spawn` resolves through — read from whichever copy of the
    // package this test file belongs to (the workspace package here, the vendored
    // copy under websites/main/src/vendor when the host runs it). It is looked up
    // by hand rather than via `require.resolve('…/worker')` because the test
    // runner's resolver honours the `development` export condition and would hand
    // back worker.ts — the one form that CANNOT run under bare node in prod.
    const require = createRequire(import.meta.url);
    const pkgPath = require.resolve('@agentic-toolkit/status-server/package.json');
    const pkg = JSON.parse(readFileSync(pkgPath, 'utf8')) as { exports: Record<string, { default: string }> };
    const entry = resolve(dirname(pkgPath), pkg.exports['./worker']!.default);
    if (!existsSync(entry)) {
      throw new Error(`built worker entry missing at ${entry} — run \`pnpm build\` in status-server first`);
    }

    const driver = fileURLToPath(new URL('./helpers/worker-boot-driver.mjs', import.meta.url));
    // The workerData carries the resolved config, and `config.secrets` IS the process
    // env (every token the shell exports) — so it goes to the driver over STDIN, never
    // as an argv element that `ps` can read and that an error message would echo back.
    const workerData = JSON.stringify({ db: { url }, config: envConfig(process.env) });
    // NODE_OPTIONS stripped so no test-runner loader leaks in — the child must
    // prove the resolved entry is runnable stand-alone, as it must be in prod.
    const { NODE_OPTIONS: _omitted, ...env } = process.env;

    const { stdout, stderr } = await runDriver(driver, entry, workerData, env);

    const replyLine = stdout.split('\n').find((l) => l.startsWith('REPLY:'));
    expect(replyLine, `no REPLY line in driver output\nstdout: ${stdout}\nstderr: ${stderr}`).toBeDefined();
    const reply = JSON.parse(replyLine!.slice('REPLY:'.length)) as { seq: number; ok: boolean; error?: string };
    expect(reply.seq).toBe(1);
    expect(reply.ok, `cycle errored: ${reply.error}`).toBe(true);
  }, 90_000);
});
