import { spawnSync } from "node:child_process";
import { existsSync, realpathSync } from "node:fs";
import { dirname, join } from "node:path";

/**
 * Sites already checked in THIS process, so a repeated config evaluation does not
 * re-fork python3.
 *
 * The `--check` run is a blocking ~350ms `spawnSync`, and `next.config` is evaluated
 * more than once per site: dev-server boot, every config reload `next dev` performs,
 * and each build worker. Bringing up the local suite's 47 sites paid for 47 of these
 * serially, for an answer that cannot change within a process — the isolate script
 * reads manifests off disk, and a manifest edit is exactly the thing that triggers the
 * config reload that re-runs it, so a stale cache within one process is only reachable
 * by editing a DIFFERENT site's manifest. Memoized per resolved site path for the same
 * reason `commitSha` memoizes its `git rev-parse` fork (`next-env/src/commit-sha.ts:40`).
 *
 * Keyed on the realpath, not the caller's string, so two spellings of one site share
 * an entry. Only a CONCLUSIVE run is recorded: a run that failed to start, or was
 * killed by a signal, leaves the key absent so the next evaluation retries it — the
 * transient conditions those represent (a fork that hit EAGAIN, an OOM kill) are
 * precisely the ones worth retrying.
 */
const checkedSites = new Set<string>();

/**
 * Where a fleet repo keeps the isolate script, relative to the directory holding its sites.
 *
 * ONE spelling covers the whole fleet, and that is a fact about the walk rather than a
 * coincidence. A split repo keeps its sites in `websites/` at the repo root, so the script is
 * `<root>/websites/tools/`; adh keeps its sites in `frontend/websites/`, so the script is
 * `<root>/frontend/websites/tools/` — which is this same relative path, matched one level
 * further down the ancestor walk, at `<root>/frontend`. The two are byte-identical members of
 * the closure fanned out from adh-tools.
 *
 * A second entry naming `frontend/src/tools/` used to sit above this one. It described a
 * layout adh has never had (there is no `frontend/src`), so it matched nothing, anywhere —
 * and matched nothing SILENTLY, because a walk that finds no script does not fail: it returns
 * `undefined` and takes the "outside adh, nothing to check" path, the same answer a legitimate
 * non-fleet consumer gets. Both halves of that bug are the same shape, which is why the fix is
 * to delete the dead spelling rather than repair it: a probe that can only ever fail open is
 * indistinguishable from a probe that is working.
 */
const ISOLATE_SCRIPT_PATH: readonly string[] = ["websites", "tools", "vercel-isolate-deps.py"];

/** Walk up from `dir` looking for a fleet repo's isolate script; `undefined` outside one. */
function findIsolateScript(dir: string): string | undefined {
  let d = dir;
  for (;;) {
    const p = join(d, ...ISOLATE_SCRIPT_PATH);
    if (existsSync(p)) return p;
    // A repo boundary the walk did not find a script at is the end of the search, not a step
    // in it. Without this the walk climbs OUT of the repo it started in and answers from an
    // enclosing one — which is not hypothetical here: a fleet repo vendors its toolkits as
    // submodules under `websites/external/`, so a site inside one of those submodules resolves
    // the OUTER repo's isolate script and is then checked against a worklist built from
    // manifests it has nothing to do with. That reproduces as five cross-workspace requirements
    // reported against a demo site that declares none of them, and no way to make it pass.
    // Checked AFTER the match so a repo whose script sits at its own root still resolves.
    if (existsSync(join(d, ".git"))) return undefined;
    const parent = dirname(d);
    if (parent === d) return undefined;
    d = parent;
  }
}

/**
 * Assert every cross-workspace `link:` requirement this site reaches is one the
 * Vercel isolate step will materialize at the site root.
 *
 * NOT "the site declared it" — adh sites are forbidden to declare the
 * `@agenticdevelopertoolkit/*` scope (<adh-tools>/sites/scripts/verify_persona_deps.py), and
 * `vercel-isolate-deps.py` materializes it for them. The property that has to hold
 * is that its worklist reaches everything; see the design spec, section 6.1.
 *
 * Delegates to that script's `--check` rather than re-deriving the worklist here:
 * one implementation of the rule, checked from the dev loop.
 *
 * Two failure modes are silent no-ops, and both are deliberate:
 *
 * - script not found (outside an adh checkout) — necessary; non-adh consumers and
 *   the toolkit's own tests must not break.
 * - `run.error` with `code === "ENOENT"` (no python3 on PATH) — this gate is not the
 *   place to fail a build over a missing interpreter, and the same check runs again
 *   on Vercel where python3 is guaranteed.
 *
 * The rest are NOT silent:
 *
 * - `run.error` with any OTHER code is a spawn that FAILED, not an interpreter that
 *   is absent. `EAGAIN` (process/thread limit), `EMFILE`/`ENFILE` (fd exhaustion) and
 *   `ENOBUFS` all arrive here, and all of them are most likely precisely when the
 *   gate matters most: a parallel build of 47 sites is what exhausts those limits.
 *   Treating them as "no python3" would disable the gate across the whole fleet at
 *   exactly the moment an undeclared dependency is cheapest to ship. Warns naming the
 *   code, and — like the signal case below — is left unmemoized so the next config
 *   evaluation retries.
 *
 * - `realpathSync` throwing means the CALLER passed a `siteDir` that does not exist
 *   — a bug in the caller's derivation, not a legitimate "nothing to check" case.
 *   Silently disabling the gate would be the worst possible response: a mis-derived
 *   `siteDir` leaves the gate permanently and invisibly off, exactly the "green
 *   locally, red on Vercel" failure class this whole check exists to catch. Throws,
 *   naming the offending path.
 * - `run.status === null` with a signal (python3 killed, e.g. OOM under a parallel
 *   build) stays non-fatal — a signal-killed interpreter must not fail a build — but
 *   `console.warn`s naming the signal, so it is visible in a build log instead of
 *   indistinguishable from a clean pass.
 */
export function assertHoistableDeps(siteDir: string): void {
  let site: string;
  try {
    site = realpathSync(siteDir);
  } catch {
    throw new Error(
      `assertHoistableDeps: siteDir does not exist: ${siteDir} (check its derivation)`,
    );
  }
  if (checkedSites.has(site)) return; // see checkedSites — same answer, ~350ms cheaper
  const script = findIsolateScript(site);
  if (!script) return;

  const run = spawnSync("python3", [script, "--check", site], { encoding: "utf8" });
  if (run.error) {
    const code = (run.error as NodeJS.ErrnoException).code;
    // ENOENT is the only one that means "no python3"; every other code is a spawn
    // that failed for a reason the gate should not swallow (see the docblock).
    if (code !== "ENOENT") {
      console.warn(
        `assertHoistableDeps: could not spawn python3 (${code ?? run.error.message}) — ` +
          "--check did not run; the hoistable-dependency gate is OFF for this evaluation",
      );
    }
    return;
  }
  if (run.status === null) {
    console.warn(
      `assertHoistableDeps: python3 was killed by signal ${run.signal} — --check did not run`,
    );
    return;
  }
  if (run.status === 0) {
    checkedSites.add(site);
    return;
  }

  throw new Error("\n" + (run.stdout ?? "") + (run.stderr ?? "") + "\n");
}
