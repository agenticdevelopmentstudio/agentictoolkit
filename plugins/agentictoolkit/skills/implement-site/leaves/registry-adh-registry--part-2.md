<!-- leaf: implement-site/registry-adh-registry--part-2 · source: site-registry-adh-registry.md -->

# DeploymentEnv — continued (part 2)

## Platform Notes

- **SwiftUI**: There is no bundler-level, text-substitution build step in a
  compiled Swift app, so the `DEV_BUILD`-vs.-`isDevDeploymentEnv` split has
  no direct motivation. Model `DevDeploymentEnv` as a
  `CaseIterable enum: String { case local, testing, staging }` and replace
  both exports with one function, `isDevDeploymentEnv(_ env: String?) ->
  Bool { env.flatMap(DevDeploymentEnv.init(rawValue:)) != nil }`, read from
  `ProcessInfo.processInfo.environment["DEPLOYMENT_ENV"]`. Keep the fail-closed
  contract (an unrecognized or missing value returns `false`) rather than
  inverting to `!= "production"`.
- **Compose**: `enum class DevDeploymentEnv { LOCAL, TESTING, STAGING }` with
  a `companion object` `fromEnv(env: String?): DevDeploymentEnv?` doing an
  exact, case-sensitive lookup against the enum's declared names (not a
  case-insensitive `equalsIgnoreCase`, to preserve the source's case-sensitive
  fail-closed behavior). Gradle build variants (`buildConfigField`) are the
  build-time-inlined analog of `NEXT_PUBLIC_*`, resolved per build
  type/flavor at compile time rather than per module-load; there is no
  Kotlin/Gradle equivalent of the chunk-gate contract's dynamic-`import()`
  concern, since Gradle's dead-code elimination (R8/ProGuard) works on
  compiled bytecode, not on textual environment-variable substitution.
- **React/Web**: (source) `packages/web/packages/adh-registry/src/deployment-env.ts`,
  with its own tests in `src/__tests__/deploymentEnv.test.ts`; exposed
  outside the package through the `./deployment-env` subpath declared in
  `package.json`'s `exports`, and re-verified from outside the package by
  `@agentic-toolkit/adh`'s `productionBundleGates.test.ts` and, across a repo
  boundary, by `adhbackend`'s `src/adh/test/themeSurfaceEnv.test.ts`. What is
  specific to this platform: the entire `DEV_BUILD`-vs.-`isDevDeploymentEnv`
  split, and the whole chunk-gate contract, exist only because Next.js/webpack
  inlines `process.env.NEXT_PUBLIC_*` as text before bundling and then
  performs dead-code elimination purely on syntactic literal comparisons — a
  constraint with no equivalent on a platform without build-time text
  substitution.
- **AppKit / UIKit**: Same approach as SwiftUI — a `CaseIterable` enum (or a
  small `Set<String>` allowlist) behind one pure function; AppKit/UIKit code
  would call it identically to SwiftUI code, since this is UI-framework-agnostic
  logic with no view dependency. There is no chunk-gating concern the way
  there is in a Next.js bundle, because Xcode performs no build-time textual
  substitution of environment variables followed by dead-code elimination.
- **WinUI 3**: This is the platform this recipe exists to steer. Read the
  deployment tier from an environment variable at startup
  (`Environment.GetEnvironmentVariable("DEPLOYMENT_ENV")`, or an app-config
  setting for a packaged MSIX app), and expose the equivalent of
  `DEV_DEPLOYMENT_ENVS` as an `enum DevDeploymentEnv { Local, Testing, Staging }`
  with a static `IsDevDeploymentEnv(string? env)` method doing the same
  exact, case-sensitive, fail-closed membership test — never `!= "production"`.
  Because a WinUI 3/MSIX app has no bundler-level, build-time text
  substitution and dead-code-elimination step analogous to webpack's
  `NEXT_PUBLIC_*` fold, the `DEV_BUILD`-vs.-`isDevDeploymentEnv` duplication
  and the chunk-gate contract (inlined comparisons, package-subpath imports)
  have no direct equivalent; a WinUI 3 port needs only ONE gate, most
  naturally exposed as a `Lazy<bool>` (no `Task`/`async` needed — this is a
  synchronous environment read) evaluated once at app startup and passed down
  to whichever XAML `Page`/`Frame` decides whether to show dev-only UI (a
  settings toggle, a debug menu item), gated with an `x:Bind`/`Visibility`
  binding rather than a dynamic module load. If a future WinUI 3 build
  genuinely needs to keep an entire dev-only page or assembly out of the
  shipped MSIX package, that is a packaging/project-reference concern (a
  project reference included only for Debug/Staging build configurations via
  a conditional `<ItemGroup Condition="...">` in the `.csproj`), not a
  runtime import-site gate — WinUI 3 has no equivalent of a JavaScript
  dynamic `import()` chunk boundary.

## Design Decisions

- **Decision**: Duplicate the "is this a dev env" fact as two separate
  declarations — `isDevDeploymentEnv` reading `DEPLOYMENT_ENV`, and
  `DEV_BUILD` reading `NEXT_PUBLIC_DEPLOYMENT_ENV` via three literal `===`
  comparisons — rather than deriving one from the other.
  **Rationale**: per the source's own comment, they answer different
  questions for different audiences (what a server RENDERS vs. what a dev
  BUILD DOES), and `DEV_BUILD` additionally has to stay in a form the
  bundler's constant folder can reduce to a literal, which
  `DEV_DEPLOYMENT_ENVS.includes(...)` would defeat; the duplication is
  therefore load-bearing, not an oversight, and it is pinned by
  `deploymentEnv.test.ts`'s "stays written as constant-foldable literal
  comparisons" test.
  **Approved**: pending
- **Decision**: Reserve `DEV_BUILD`/`isDevDeploymentEnv` for what gets
  rendered or what a dev build does, and require any consumer that gates a
  dynamic `import()` on the dev/production distinction to follow a separate
  four-leg chunk-gate contract (inline literal comparisons at the import
  site, a package-subpath specifier, a matching bundler entry plus
  `external`, and a package.json export) instead of importing `DEV_BUILD` at
  that site.
  **Rationale**: the source's own top-of-file comment states this is why an
  earlier `DEV_BUILD ? dynamic(() => import('./X'))` shipped the whole
  site-theme editor, Monaco included, into every production build of every
  site — a bundler's dead-code elimination for a dynamic import resolves
  only a literal comparison visible while parsing that exact call site, and
  does not follow an imported identifier back to its definition.
  **Approved**: pending
- **Decision**: Place this module in `@agentic-toolkit/adh-registry` rather
  than in `@agentic-toolkit/adh`, where most of its consumers live.
  **Rationale**: `adh` depends on `adh-registry`, so a home in `adh-registry`
  is readable from both sides of that dependency edge — including
  `adh-registry`'s own `seo/metadata.ts`, which needs the same fact — while a
  home inside `adh` could not be read from `seo/metadata.ts` without
  introducing a dependency cycle.
  **Approved**: pending
- **Decision**: Guard the cross-repo copy of this allowlist
  (`adhbackend`'s `isThemeSurfaceEnv`) by having
  `adhbackend/src/adh/test/themeSurfaceEnv.test.ts` regex-extract
  `DEV_DEPLOYMENT_ENVS`'s literal array text out of this file's source text,
  rather than importing the module.
  **Rationale**: `adhbackend` is a standalone pnpm package that must not take
  a build dependency on the frontend package this file lives in; reading the
  source text instead lets the two lists be checked for drift in both
  directions without creating that dependency, at the cost of coupling the
  check to this file staying at its current path and keeping the array
  written as a literal the regex can match — the test's own comment states
  it "fails loudly if that file moves."
  **Approved**: pending
- **Decision**: Allowlist the three dev environments explicitly
  (`=== 'local' || === 'testing' || === 'staging'`) rather than testing the
  inverse (`!== 'production'`), in both `isDevDeploymentEnv` and
  `DEV_BUILD`.
  **Rationale**: per the source comment, this makes an unset or misspelled
  environment fail SAFE (dev tooling hidden) instead of failing OPEN (dev
  tooling exposed to real visitors) — the asymmetry matters because a
  wrongly-"dev" gate does not crash and is not noticed by CI, it just ships
  extra code and behavior to production silently.
  **Approved**: pending
