<!-- leaf: implement-status-server-monitor-1/deploy-view--part-2 · source: status-server-monitor-deploy-view.md -->

# Status Server Monitor Deploy View — continued (part 2)

## Design Decisions

- **Decision**: rank the branch signal above both the project-name convention and the platform's own stored environment in `deployEnv`, rather than trusting whichever signal a given platform happens to report.
  **Rationale**: per the source's doc comment on `deployEnv`, the branch "is the pipeline's own input, so it is right by construction for any project, named however it likes, on any platform," while the project-name rule defaults to `"production"` for any name it cannot parse and Vercel's stored environment is `"production"` for every project's promotion target — both of those defaults are wrong in exactly the way that matters most, badging a live testing deploy as production. `deploy-env.test.ts`'s assertion that a Railway environment literally named `"production"` still reads `"testing"` when its branch is `"prepared"` confirms the ranking is about which signal can lie, not about which platform reported it.
  **Approved**: pending
- **Decision**: implement `BRANCH_ENV` as a `Map` rather than a plain object literal, and have `envFromBranch` look a branch up only among that map's own three entries.
  **Rationale**: the source comment explains that indexing a plain object literal reaches `Object.prototype`, so a branch literally named `"toString"` or `"__proto__"` would return a truthy inherited function or object rather than `undefined`, defeating the `?? null` fallback and handing a non-string value to a caller that a `Record<string, string>` type annotation swore was a string all the way to a rendered badge — pinned directly by `deploy-env.test.ts`'s dedicated Object.prototype test.
  **Approved**: pending
- **Decision**: give `deployEnv`'s `branch` parameter no default value, requiring every caller to pass `null` explicitly when it has no branch to offer.
  **Rationale**: the source's own doc comment states a default "would let a new call site silently take the fallible path and badge a testing project PROD, which is the exact regression this parameter was added to close" — an explicit `null` forces a new call site's no-branch state to be visible in its own code rather than inherited silently from a signature default.
  **Approved**: pending
- **Decision**: never fall back from `liveUrl` to the deploy/inspector URL when `liveHost` is `null`.
  **Rationale**: the source comment states "a link rendered as a host must point at the real site, never the build page" — so a missing live host renders as no live link at all, rather than a link that looks like it opens the live site but actually opens the provider's build/inspector page.
  **Approved**: pending
- **Decision**: keep exporting `isRealEnvDeploy`, `deployLinks`, `Indicator`, and `IndicatorState` even though, at the time of this recipe's authoring, no other file in the `status-server` package imports any of the four directly.
  **Rationale**: recorded as an observed fact of the current call graph, not a defect in this file — all four behave exactly as documented, and `isRealEnvDeployRow` (the sibling `isRealEnvDeploy` delegates to) is exercised indirectly through `providerDeployToDTO`'s tier assertions in `deploy-env.test.ts`. Nothing here is broken or unused within this file; a future caller needing a DTO-level real-deploy check, a shared `sourceUrl`/`liveUrl` builder, or the `Indicator` shape has these ready without re-deriving `projectPageUrl`'s Vercel-URL-collapsing logic itself.
  **Approved**: pending
