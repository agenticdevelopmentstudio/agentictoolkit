<!-- leaf: implement-site/registry--part-4 · source: site-registry.md -->

# Site Registry — continued (part 4)

**Rules** (cite as `implement-site/registry--part-4#<slug>`):

- `persona-and-registry-paths-percent-encode-slugs` MUST
- `persona-profile-url-resolves-current-env` MUST
- `site-url-falls-back-to-bare-path` MUST
- `site-prod-url-ignores-current-environment` MUST
- `site-home-path-fallback` MUST

### Persona and cross-site URL helpers

- **persona-and-registry-paths-percent-encode-slugs**: `personaProfilePath`, `registryUserPath`, `registryUserPersonaPath`, and `registryOrgPath` MUST percent-encode every slug segment they place into a path via `encodeURIComponent`, since a slug is untrusted, registrant-supplied text placed directly into a URL path.
- **persona-profile-url-resolves-current-env**: `personaProfileUrl(slug)` MUST resolve the persona registry's current-environment absolute URL via `siteUrl('personaregistry', personaProfilePath(slug), hostname)`, using the current global `location.hostname` when one is available and an empty string otherwise (this file is also type-checked in a backend build with no DOM library, so it MUST NOT reference `window` directly).
- **site-url-falls-back-to-bare-path**: `siteUrl(id, path, currentHostname)` MUST return `path` unchanged when `id` resolves to no known site (via `getSite`), rather than throwing or returning a malformed URL.
- **site-prod-url-ignores-current-environment**: `siteProdUrl(id, path)` MUST always resolve `https://<prodHost><path>` regardless of the caller's current environment, since it exists specifically as the deterministic server-side-rendered default computed before the client's own hostname is known.
- **site-home-path-fallback**: `siteHomePath(id)` MUST return `/home` when the site's `hasHome` is `true`, and `/` otherwise.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `SITES` | `SiteDef[]` | fixed at build time | The whole family roster; not caller-configurable at runtime — a new site is added by editing `registry.ts` (its scaffolded `<gen:sites>` region for the mechanically-added fields, or the file directly for a hand-authored one). |
| `hostname` (`detectEnv`, `siteUrl`, `personaProfileUrl`) | `string` | caller-supplied; `personaProfileUrl` defaults to `globalThis.location?.hostname ?? ''` | The current request/browser host, used to resolve which deploy environment and, for local dev, which suite the caller is on. |
| `currentHostname` / `pathname` (`buildSiteHref`) | `string` | caller-supplied; required | The visitor's current host and path, used to resolve the target site's href in the same environment and to decide whether `/home` is carried. |
| `LOCAL_SUITE_DOMAINS` | `readonly string[]` (module-internal constant) | `['sites.localhost', 'dev.test', 'dev.local']` | The domain suffixes recognized as a `dev.local`-suite host; not caller-configurable. |
| `env` (`ssoReturnOrigins`) | `'production' \| 'staging' \| 'testing'` | caller-supplied; required | Which deploy environment's OAuth-return-origin allowlist to compute. |
| `SITE_BUILD` | `Partial<Record<SiteId, SiteBuildConfig>>` | fixed at build time | Per-site build behavior flags read by the shared Next.js config package; not caller-configurable at runtime. |

## Localization

`registry.ts`'s `SiteDef` entries carry hardcoded English `label`, `fullLabel`, `shortLabel`, and `description` strings for every site (for example `"The Agentic Developer Hub"`, `"Recipes & patterns"`), and `siteHeaderTitle`'s derived `"Agentic Developer <X>"` title is built from the same hardcoded English convention. None of these strings is routed through any localization or string-catalog layer in this file; a translated build of the switcher, footer, or header would need its own separate string source, since this registry supplies only the one, English, copy.

## Privacy

- **Data collected**: This component reads and returns only site metadata (ids, labels, hosts, environment flags, route lists, brand-story classifications) that is itself source-controlled configuration, not user data. `personaProfilePath`/`registryUserPath`/`registryOrgPath` accept a caller-supplied slug (a public handle a registrant chose) and percent-encode it into a path; no credential, token, or other secret value is read or handled anywhere in this component.
- **Storage**: This component persists nothing at runtime; every export is either a module-level constant computed once at load or a pure function with no side effect.
- **Transmission**: Not applicable — this component performs no networking of its own. `ssoReturnOrigins`'s output is consumed by a separate deploy-time sync job in another repo, which is the one that actually transmits it to a database column; that transmission is outside this component.
- **Retention**: Not applicable — nothing here is retained beyond the lifetime of the process that imported the module.

## Platform Notes

- **AppKit / UIKit**: These are TypeScript/web sources with no Apple-framework dependency; a macOS/iOS reader of this recipe would model `SiteDef`/`SiteStory` as `Codable` `struct`s, `SITES`/`SITE_STORIES` as `static let` constants (loaded from a bundled JSON or a generated Swift file rather than re-typed by hand), and `detectEnv`/`buildSiteHref`/`ssoReturnOrigins` as pure functions over `URLComponents`/`String` with no `NSObject` subclassing needed anywhere.
- **SwiftUI**: No SwiftUI dependency exists in the source. A SwiftUI consumer would typically expose the registry's derived collections (`LISTED_SITES`, `FOOTER_SITES`, `groupSitesByCategory`'s output) as plain `let` properties on an `@Observable` view model computed once at init, since none of the underlying data ever changes during a running process.
- **Compose**: A Kotlin port would model `SiteId` as a `sealed interface`/`enum class` rather than a string-literal union (closer to `isSiteId`'s narrowing contract than TypeScript's own union erasure), `SiteDef`/`SiteStory` as `data class`es, and the various derived `Set`/`Map` constants (`SITE_LANDING_SEGMENTS`, `HUB_WORKSPACE_SEGMENTS`, `SITE_TOUR_NEXT`) as `kotlinx.collections.immutable` structures built once at object-initialization time, mirroring this module's compute-once-at-load pattern.
- **React/Web**: This is the source. The files are pure TypeScript with no React import, consumed by React components (the header, switcher, and footer) that live elsewhere in the same web packages; a caller re-implementing this in another JS/TS codebase should keep the same pure-data/pure-function shape rather than folding any of it into a component or a hook, since several of the exports (`ssoReturnOrigins`, the route shares) are consumed by non-React code (a backend sync job, a sitemap generator) that would break if the logic moved into a component.
- **WinUI 3**: A .NET port would model `SiteId` as an `enum`, `SiteDef`/`SiteStory` as `record`s (immutable by default, matching this module's `readonly`-everywhere shape), the various `Set<string>`/`Record<SiteId, X>` constants as `FrozenSet<string>`/`FrozenDictionary<SiteId, X>` computed once in a static constructor, `detectEnv`/`hostForEnv`/`localOrigin` as pure `static` methods over `Uri`/`string`, and `System.Text.Json` for deserializing any of this data if it were instead shipped as a generated JSON asset rather than compiled Swift/Kotlin/C# source; no `HttpClient`, `Windows.Storage`, `Task`/`async`, `ObservableCollection`, or `INotifyPropertyChanged` is needed anywhere, since nothing in this component performs I/O, runs asynchronously, or changes after process start.

