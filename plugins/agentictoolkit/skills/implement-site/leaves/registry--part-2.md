<!-- leaf: implement-site/registry--part-2 · source: site-registry.md -->

# Site Registry — continued (part 2)

**Rules** (cite as `implement-site/registry--part-2#<slug>`):

- `site-id-closed-union` MUST
- `unique-site-ids` MUST
- `site-def-minimum-fields` MUST
- `workspace-route-not-derived-from-has-home` MUST
- `external-site-excluded-from-sso` MUST
- `admin-only-derives-admin-ids-and-drops-footer` MUST
- `listed-sites-filter` MUST
- `footer-sites-filter` MUST
- `get-site-lookup` MUST
- `is-site-id-derived-from-sites` MUST
- `dir-name-strips-tld` MUST
- `site-id-for-dir-bare-id-first` MUST
- `main-marketing-ids-are-disjoint-curated-lists` MUST
- `site-categories-exactly-one-membership` MUST
- `group-by-category-preserves-order-and-collects-leftovers` MUST
- `header-title-explicit-fulllabel-wins` MUST
- `header-title-derives-from-apex-pattern` MUST
- `split-title-prefix-detection` MUST
- `detect-env-classification` MUST
- `host-for-env-fallback` MUST
- `local-origin-suite-domain-priority` MUST
- `carry-path-home-only` MUST
- `build-site-href-env-aware` MUST
- `sso-return-origins-partitioned-by-env` MUST
- `sso-flag-flip-is-a-one-way-door` MUST
- `sso-external-exclusion-fail-closed` MUST

## Behavioral Requirements

### Site identity and roster (`SiteId`, `SiteDef`, `SITES`)

- **site-id-closed-union**: `SiteId` MUST be a closed TypeScript string-literal union naming every site the family currently knows about; a string value obtained from outside the type system (a directory name, a CLI argument, a DB column) MUST be narrowed through `isSiteId` or `siteIdForDir` before it can index `SITES` or any table keyed by `SiteId`.
- **unique-site-ids**: Every entry in `SITES` MUST have a unique `id`, and `SITES` MUST NOT contain an entry for the backend service itself.
- **site-def-minimum-fields**: Every `SITES` entry MUST declare `id`, `label`, and `prodHost`, and MUST declare `hasStaging`, `hasTesting`, and `hasHome` as explicit booleans (never omitted, since `hostForEnv`, `ssoReturnOrigins`, and `buildSiteHref`'s home-carry all branch on their literal `true`/`false` value).
- **workspace-route-not-derived-from-has-home**: `SiteDef.workspaceRoute` MUST NOT be inferred from `SiteDef.hasHome`; the two are independent facts about a site's route tree (`bitbag`, `status`, and `admin` have `hasHome: false` and no `workspaceRoute`, while `hub-help` and `personaregistry` have `hasHome` true or false independently of having no `workspaceRoute` at all), and a caller deriving one from the other risks sending a workspace switch to a route that 404s.
- **external-site-excluded-from-sso**: A `SITES` entry with `external: true` MUST be excluded from `ssoReturnOrigins`'s allowlist in every environment, because such a site (FishLamp Design) has no `/auth/callback` and never begins an ADH login.
- **admin-only-derives-admin-ids-and-drops-footer**: `ADMIN_SITE_IDS` MUST be exactly the `id`s of every `SITES` entry with `adminOnly: true`, and every such entry MUST be excluded from `FOOTER_SITES`.
- **listed-sites-filter**: `LISTED_SITES` MUST be exactly the `SITES` entries whose `listed` field is not literally `false`; a `listed: false` entry MUST remain resolvable by `getSite`/`isSiteId` and MUST only be excluded from the roster, never from the registry itself.
- **footer-sites-filter**: `FOOTER_SITES` MUST be exactly the `LISTED_SITES` entries whose `crawlable` is not `false` and whose `adminOnly` is not `true`, in the same order as `LISTED_SITES`.

### Lookup and identification (`getSite`, `isSiteId`, `siteIdForDir`)

- **get-site-lookup**: `getSite(id)` MUST return the `SITES` entry whose `id` equals the argument, or `undefined` when no such entry exists.
- **is-site-id-derived-from-sites**: `isSiteId(value)` MUST return `true` if and only if some entry in `SITES` has that `id`; it MUST be derived from `SITES` directly rather than from a second, separately maintained list, so it can never diverge from the ids the registry actually declares.
- **dir-name-strips-tld**: `dirNameOf` (the folder-name convention used internally by `siteIdForDir`) MUST derive a site's Next.js app-folder name by stripping the trailing `.<tld>` from `prodHost` (e.g. `help.agenticdeveloperhub.com` → `help.agenticdeveloperhub`).
- **site-id-for-dir-bare-id-first**: `siteIdForDir(name)` MUST return `name` unchanged (narrowed to `SiteId`) when `name` is already a valid site id, before falling back to a `prodHost`-derived folder-name match; it MUST return `undefined` when `name` matches neither a site id nor any site's derived folder name.

### Family groupings (`MAIN_SITE_IDS`, `MARKETING_SITE_IDS`, `SITE_CATEGORIES`, `groupSitesByCategory`)

- **main-marketing-ids-are-disjoint-curated-lists**: `MAIN_SITE_IDS` and `MARKETING_SITE_IDS` MUST each be a hand-curated, non-overlapping array of site ids; an id present in one MUST NOT appear in the other, and `mcp` and `builds` (which have no Next.js app folder anywhere) MUST appear in neither.
- **site-categories-exactly-one-membership**: Every id appearing in any `SITE_CATEGORIES` group's `ids` MUST appear in exactly one group's `ids`, never zero and never more than one.
- **group-by-category-preserves-order-and-collects-leftovers**: `groupSitesByCategory(sites)` MUST emit groups in `SITE_CATEGORIES` order, with members in each group's declared `ids` order, MUST omit any group with no matching member in `sites`, and MUST collect every site in `sites` that matches no category's `ids` into a single trailing group labelled `"More"`, so that a newly scaffolded site can never be silently dropped from a menu built on this function.

### Display title (`siteHeaderTitle`, `splitSiteTitle`)

- **header-title-explicit-fulllabel-wins**: `siteHeaderTitle(site)` MUST return `site.fullLabel` when it is set, taking priority over any derivation from `prodHost`.
- **header-title-derives-from-apex-pattern**: When `fullLabel` is absent and `prodHost` matches `agenticdeveloper<x>.com`, `siteHeaderTitle(site)` MUST return `"Agentic Developer <X>"` with `<x>` capitalized, and MUST fall back to `site.label` when `prodHost` matches neither an explicit `fullLabel` nor that pattern.
- **split-title-prefix-detection**: `splitSiteTitle(site)` MUST split `siteHeaderTitle(site)` into `{ titleLead: "Agentic Developer", titleAccent: <rest> }` when the header title begins with `"Agentic Developer "`, and MUST return `{ titleLead: "", titleAccent: <whole title> }` for an off-pattern brand name (for example the Persona Registry).

### Environment and cross-site navigation (`detectEnv`, `hostForEnv`, `localOrigin`, `carryPath`, `buildSiteHref`)

- **detect-env-classification**: `detectEnv(hostname)` MUST lower-case and strip any trailing `:<port>` before classifying, MUST classify a hostname as `'local'` when it is exactly `localhost`, starts with `127.`, is `::1`, or ends in `.local`, `.test`, or `.localhost`; MUST classify a hostname starting with `testing.` as `'testing'` and one starting with `staging.` as `'staging'`; and MUST classify every other hostname as `'production'`.
- **host-for-env-fallback**: `hostForEnv(site, env)` MUST resolve `testing.<prodHost>` when `env === 'testing'` and `site.hasTesting`; otherwise for `'testing'` it MUST fall back to `staging.<prodHost>` when `site.hasStaging`, and otherwise to the bare `prodHost`. For `env === 'staging'` it MUST resolve `staging.<prodHost>` when `site.hasStaging` and otherwise the bare `prodHost`. For `'production'` it MUST always resolve the bare `prodHost`.
- **local-origin-suite-domain-priority**: `localOrigin(target, currentHost)` MUST first check whether the lower-cased, port-stripped `currentHost` ends in one of `LOCAL_SUITE_DOMAINS` (`sites.localhost`, `dev.test`, `dev.local`, checked in that order for readability only); when it does, the target's local origin MUST be `https://<sub>.<suite>.<domain>` (no subdomain for `hub`) reusing the current host's own `<suite>` label. When `currentHost` matches none of `LOCAL_SUITE_DOMAINS`, `localOrigin` MUST fall back to `http://<sub>localhost<:port>`, carrying the current port when one is present.
- **carry-path-home-only**: `carryPath(target, pathname)` MUST return the target's landing path (`/`) for any `pathname` other than `/home` or a path starting with `/home/`; for `pathname === '/home'` it MUST return `/home` when `target.hasHome` and `/` otherwise; for a deeper `/home/*` path it MUST return the same path with the `#site-switch` hash appended (so the target's not-found page knows to walk the path up), or `/` when the target has no `/home` route at all.
- **build-site-href-env-aware**: `buildSiteHref(target, currentHostname, pathname)` MUST classify the current environment via `detectEnv(currentHostname)`; for `'local'` it MUST return `localOrigin(target, currentHostname)` concatenated with `carryPath(target, pathname)`; for every other environment it MUST return `https://<hostForEnv(target, env)>` concatenated with `carryPath(target, pathname)`.

### Cross-Site SSO Origin Allowlist (security-relevant)

- **sso-return-origins-partitioned-by-env**: `ssoReturnOrigins(env)` MUST return, for `env === 'production'`, the bare `https://<prodHost>` origin of every `SITES` entry that is not `external`; for `env === 'staging'`, only the `https://staging.<prodHost>` origin of every non-`external` entry with `hasStaging: true`; for `env === 'testing'`, only the `https://testing.<prodHost>` origin of every non-`external` entry with `hasTesting: true`.
- **sso-flag-flip-is-a-one-way-door**: `hasStaging` and `hasTesting` are the OAuth redirect surface this function names, and flipping either from `false` to `true` MUST be treated as permanently widening that environment's allowlist: the deploy-time sync job (`backend/src/adh/src/lib/sync-return-origins.ts`) that reads this function's output into the enforcing DB column is additive-only and never prunes a row that a later flag flip back to `false` would otherwise remove. A caller changing an existing row's flag back to `false` MUST NOT assume the corresponding origin stops being a valid OAuth `return` target without a separate, deliberate, hand-run pruning pass against that environment.
- **sso-external-exclusion-fail-closed**: An origin belonging to a `SITES` entry with `external: true` MUST NOT appear in `ssoReturnOrigins`'s result for any environment, on a fail-closed basis: an origin that cannot complete an ADH login has no legitimate reason to be a legal `return` target, so the absence is deliberate rather than an oversight to fill in.

