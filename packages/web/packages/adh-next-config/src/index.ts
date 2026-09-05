import path from "node:path";
import type { NextConfig } from "next";
import {
  assertAuthApiUrl,
  assertHoistableDeps,
  assertLinkedDepsInstalled,
} from "@agentic-toolkit/next-preflight";
import { mergeHeaders } from "@agentic-toolkit/next-headers";
import { commitSha, readSiteVersion, resolveBackendUrl } from "@agentic-toolkit/next-env";
import { siteBuildConfig, type SiteRedirect } from "@agentic-toolkit/adh-registry";
// By NAME, not by relative path — the point of this package existing at all. The old
// `next-config-base.mjs:13` had to reach across the filesystem
// (`./external/agentictoolkit/packages/web/packages/themes/src/materialize-fonts.mjs`)
// because it sat at the pnpm-workspace root, which declared no dependencies and so
// could not resolve the bare specifier. This package CAN declare
// `@agenticdevelopertoolkit/themes` (see package.json), which is what makes the relative path
// obsolete. Kept EXTERNAL in tsup.config.ts, unlike the other four siblings — see the
// comment there — because the module locates its own font files relative to its own
// `import.meta.url` and must not move.
import { materializeThemeFonts } from "@agenticdevelopertoolkit/themes/materialize-fonts";
import { currentSiteId } from "./site-id.js";

export { currentSiteId };
export { workbenchNextConfig, type WorkbenchNextConfigOptions } from "./workbench.js";

/**
 * What a site may still pass at the call site.
 *
 * Empty for 45 of the 47 sites: their data lives in the fleet registry, and their
 * `next.config.ts` is byte-identical. `cookbook` and `hub` are the exceptions
 * (Ruling T4-a) — their redirects derive from site-local modules (`OVERVIEW_PATH`,
 * `featureIds`) that this package cannot import without inverting the dependency, and
 * both sites carry a comment saying the derivation is the point. Freezing those values
 * into registry data would re-create the drift those comments exist to prevent.
 */
export type AdhNextConfigOptions = {
  readonly legacyHomePaths?: boolean;
  readonly extraRedirects?: readonly SiteRedirect[];
  /**
   * Extra Next `experimental` keys, MERGED over the baseline rather than replacing it —
   * and `staleTimes` merged one level deeper still, so a caller tuning `static` keeps
   * `dynamic: 30`.
   *
   * This exists because the base is now a plain object callers SPREAD (`{ ...base, … }`)
   * instead of a wrapper they pass their config through. Spreading is last-wins per top
   * level key, so a site that wrote its own `experimental` next to `...base` would drop
   * `staleTimes` entirely — a caching regression with nothing in the config to show for
   * it. `next-config-base.mjs:471-482` merged per key for exactly this reason and said
   * so; routing the value through here is how that survives the shape change. Same for
   * {@link workspaceRoot} below.
   */
  readonly experimental?: NextConfig["experimental"];
  /**
   * The directory Turbopack and output-file tracing are pinned to, off-Vercel.
   *
   * Defaults to the site's own pnpm workspace root (two levels up from the site dir),
   * which is right for all 47 sites — they all live under `frontend/src/sites/`. It is
   * an option because Turbopack REFUSES a root that is not an ancestor of the project
   * being built, and the repo-root `local/` workbenches are not under `frontend/src`:
   * `next-config-base.mjs:488-494` let a caller's own `turbopack.root` win for that
   * reason, and its comment named those workbenches as the only callers that needed it.
   */
  readonly workspaceRoot?: string;
};

/**
 * The legacy `/home/<workspace>/...` → `/<workspace>/...` redirect. The workspace used to
 * live UNDER /home; it is now the first path segment. Every bookmark, Slack link and email
 * from the old grammar still names the old shape, and without this rule the leading "home"
 * is read as the workspace slug — it matches none, so the route seeds a workspace instead
 * and replaces the URL, silently dropping the project, the topic and the leaf the link was
 * pointing at.
 *
 * `:path+` requires at least one segment, so a site's bare /home — the workspace-resolving
 * redirect every cross-site link names — is untouched. Temporary (307), not permanent: a 308
 * is cached by the browser indefinitely and would outlive any future change to this grammar.
 *
 * Ported unchanged from `marketing.next-config.mjs:66-73`.
 */
function legacyHomeRedirects(): SiteRedirect[] {
  return [{ source: "/home/:path+", destination: "/:path+", permanent: false }];
}

/**
 * The one config every ADH site exports. Takes no arguments by design: the site
 * identifies itself by its directory, and everything that varies per site is
 * data in the fleet registry. See
 * docs/superpowers/specs/2026-08-14-next-config-packages-design.md.
 */
export function adhNextConfig(options: AdhNextConfigOptions = {}): NextConfig {
  const siteDir = process.cwd();
  const id = currentSiteId(siteDir);
  // Build data comes from `siteBuildConfig`, NOT from the `SiteDef` — the three build
  // fields are deliberately not on that interface (Ruling T4-b). Most `SITES` entries
  // live inside a `<gen:sites>` region that `<adh-tools>/sites/scripts/scaffold-sites.py`
  // regenerates wholesale from a template blind to them, so a field written there is
  // silently dropped on the next scaffold run. The side table below the close marker is
  // what makes that impossible. `siteBuildConfig` returns `{}` for sites with no build
  // data, so there is no undefined case to handle here.
  const site = siteBuildConfig(id);

  // Before anything else: restored to this order (auth check FIRST) in the Task 5 fix
  // round — `next-config-base.mjs:429-431` ran it first deliberately, with the comment
  // this one carries: a hosted build with no AS host produces a site whose header can
  // never show a signed-in visitor, and says nothing about it at build or run time. An
  // earlier draft of this file ran the dependency gate first instead, which only
  // changes which error surfaces when both would fail — but the original order was a
  // documented choice, not an accident, so it is restored rather than left reversed.
  // Validate AND pass through the AS host in one step: Task 2's `assertAuthApiUrl`
  // takes the value and hands it back unchanged (or throws on a hosted build with
  // none), so computing it here both performs the assertion and gives `env` below an
  // explicit value to wire in.
  const authApiUrl = assertAuthApiUrl(process.env.NEXT_PUBLIC_AUTH_API_URL, id);

  // …and its local counterpart, which `withAdhConfig` ran in this same slot
  // (`next-config-base.mjs:433`): a build whose toolkit workspace was never re-installed
  // fails hundreds of lines later, naming a package rather than the un-run install. It
  // runs BEFORE the gate below because it is a pure filesystem walk where that one forks
  // python3, and because a stale install is the cheaper explanation for a package the
  // other check would then also fail to find.
  assertLinkedDepsInstalled(siteDir);

  // Fail fast, before Next does any work. This is the whole point of the
  // package: an undeclared dependency is caught here, in dev, rather than in a
  // Vercel build twenty minutes later.
  assertHoistableDeps(siteDir);

  // Put the theme's self-hosted webfont faces under this site's public/ before Next
  // collects it (see the import comment above, and materialize-fonts.mjs's own header)
  // — the theme css names those faces by absolute path, so they must exist on disk
  // before the build proceeds. `withAdhConfig` ran this in this same slot, after the
  // two assertions above and before the config is assembled.
  materializeThemeFonts();

  // `requiresBackendUrl` (Task 4) is set for FIVE sites — bitbag, personaregistry,
  // projects, narratives and billing. `build-fields.test.ts` pins that exact set, so this
  // sentence and that assertion have to move together; it is a comment, so only the test
  // makes the number true.
  // Passing it from the registry rather than hardcoding `false` is what keeps this
  // uniform code able to express a per-site difference; dropping the argument would
  // silently downgrade both hosted builds from "fail with a named variable" to
  // "deploy a proxy that 502s on every call".
  //
  // ⚠️ `hub` is a third site that requires the variable, and it is NOT in the registry
  // data — deliberately. `hub/src/lib/backend-url.ts` throws UNCONDITIONALLY, not just
  // when VERCEL_ENV is set, so it is strictly stricter than
  // `resolveBackendUrl({ requireExplicit: true })`, which falls back to localhost in
  // local dev. hub is exempt (Ruling T4-a) and keeps that module. Do not "fix" the
  // apparent omission by flagging hub in the registry: that would LOOSEN hub's local
  // dev from "fail immediately" to "silently proxy to localhost:3000".
  const backendUrl = resolveBackendUrl({ requireExplicit: site.requiresBackendUrl });
  const version = readSiteVersion(siteDir);
  const sha = commitSha();
  // Two levels up from the site directory (`frontend/src/sites/<site>` → `frontend/src`),
  // matching `WEBSITES_ROOT` in the retired `next-config-base.mjs:18` — that file derived it
  // from its OWN location (it lived at `frontend/src/next-config-base.mjs`), which this
  // package cannot do: it is checked out inside the toolkit submodule, nowhere near
  // `frontend/src`. `siteDir` (this site's cwd) is the one path every caller already has,
  // and every site lives exactly two directories under the workspace root it needs pinned.
  const websitesRoot = path.resolve(siteDir, "..", "..");

  return {
    devIndicators: false,
    distDir: process.env.ADH_DIST_DIR || ".next",
    env: {
      // Promote the (server-only) DEPLOYMENT_ENV to a client-inlined build constant on
      // EVERY site, so the shared site menu's dev-only Routes / Debug Options rows gate
      // uniformly — SiteMenu's DEV_TOOLS_BUILD_ENABLED reads NEXT_PUBLIC_DEPLOYMENT_ENV,
      // which Next inlines from here. Falls back to an already-public
      // NEXT_PUBLIC_DEPLOYMENT_ENV (the local dev suite sets that ambiently). Ported from
      // next-config-base.mjs:428.
      NEXT_PUBLIC_DEPLOYMENT_ENV: process.env.DEPLOYMENT_ENV ?? process.env.NEXT_PUBLIC_DEPLOYMENT_ENV,
      // Computed above (before the dependency gate — see the "Before anything else"
      // comment), not called here, so the assertion runs in the restored original
      // order rather than lazily as part of assembling this object.
      NEXT_PUBLIC_AUTH_API_URL: authApiUrl,
      // The footer's two build-identity fields (readSiteVersion/commitSha above) so the
      // footer can show both and the shared telemetry can tag every GlitchTip error with a
      // `release`. Ported from next-config-base.mjs:428.
      NEXT_PUBLIC_ADH_SITE_VERSION: version,
      NEXT_PUBLIC_ADH_RELEASE: sha,
    },
    // `mergeHeaders` already emits the SECURITY_HEADERS, FONT_CACHE_HEADERS, and
    // (Task 5 fix round) PRERENDER_HEADERS baseline rules itself — do not re-list them
    // here, that emits each twice. It takes a NextConfig and appends that config's own
    // `headers()` AFTER the baseline (last-wins, so a site could override). No site
    // defines one today (`grep -rn "headers" frontend/src/sites/*/next.config.ts` is
    // empty), hence `{}`; the parameter stays because it is where a future override goes.
    headers: mergeHeaders({}),
    async redirects() {
      // Registry data first, then the call site's. No site supplies both today — the
      // two that use the parameter (cookbook, hub) have no registry redirects by
      // construction — so this order is not currently observable; it is fixed here so
      // that if one ever does, the registry's fleet-wide entry is matched before a
      // site-local override rather than after it.
      //
      // Both sources come BEFORE the legacy-home rule, because
      // `marketing.next-config.mjs:68-69` emits them in that order and Next matches
      // redirects first-to-last. The legacy rule is broad (`/home/:path+`), so moving
      // it earlier would let it swallow any specific `/home/...` redirect a site owns.
      const out = [...(site.extraRedirects ?? []), ...(options.extraRedirects ?? [])];
      if (site.legacyHomePaths || options.legacyHomePaths) {
        out.push(...legacyHomeRedirects());
      }
      return out;
    },
    async rewrites() {
      // Same-origin BFF proxy, ported from `marketing.next-config.mjs:49-51` — every site
      // funnels through this uniform config now, so this rule (previously marketing-only)
      // applies fleet-wide.
      //
      // `next-config-base.mjs:164`'s narrower `/api/system/*` baseline is NOT ported: it
      // is unreachable dead code, not merely redundant — this rule is listed FIRST and
      // already matches every `/api/system/*` request, producing a byte-identical
      // destination, and Next matches rewrites in array order, so the second rule could
      // never fire. Removed in the Task 5 fix round.
      return [{ source: "/api/:path*", destination: `${backendUrl}/:path*` }];
    },
    experimental: {
      ...options.experimental,
      // Next's client router cache for DYNAMIC segments defaults to 0 seconds, so navigating
      // back to a topic re-renders it from the server even when every query behind it is
      // already cached. 30 seconds makes going back free and bounds how stale a re-entered
      // pane can be. Ported from next-config-base.mjs:428.
      //
      // Merged PER KEY rather than spread whole, so a caller tuning one of Next's other
      // stale times keeps this default for the one it did not mention — a bare
      // `...options.experimental` after this line would replace the whole `staleTimes`
      // object and a caller that set only `static` would silently lose `dynamic: 30`.
      // next-config-base.mjs:471-482 did it this way and its comment says why.
      staleTimes: { dynamic: 30, ...options.experimental?.staleTimes },
    },
    ...(process.env.VERCEL
      ? {}
      : {
          // Pin Turbopack's workspace root to the frontend/src/ pnpm workspace so a stray
          // lockfile above it can't make Next infer an ancestor root and watch every sibling
          // worktree (a CPU-storm vector on a dev machine only — see websitesRoot above).
          // Off-Vercel only: each site's Vercel "Root Directory" is
          // `frontend/src/sites/<site>` already, and pinning would mis-join `.next`'s
          // location one segment too shallow. Ported from next-config-base.mjs:428's
          // off-Vercel branch.
          turbopack: { root: options.workspaceRoot ?? websitesRoot },
          outputFileTracingRoot: options.workspaceRoot ?? websitesRoot,
        }),
  };
}
