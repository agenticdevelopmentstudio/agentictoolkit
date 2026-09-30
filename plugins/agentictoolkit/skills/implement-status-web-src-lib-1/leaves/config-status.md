<!-- leaf: implement-status-web-src-lib-1/config-status · source: status-web-src-lib-config-status.md -->

**Rules** (cite as `implement-status-web-src-lib-1/config-status#<slug>`):

- `endpoint-like-shape` MUST
- `is-active-optional` MUST
- `opt-out-ignore-flag` MUST
- `opt-out-paused` MUST
- `opt-out-strict-false` MUST
- `opt-out-strict-true` MUST
- `opt-out-default` MUST
- `opt-out-minimal-input` MUST
- `status-folds-before-classify` MUST
- `status-no-mutation` MUST
- `status-delegates-to-engine` MUST
- `status-infra-kind` MUST
- `status-wired` MUST
- `status-paused-wired-stays-configured` MUST
- `status-unwired-opted-out` MUST
- `status-unwired-not-opted-out` MUST
- `status-empty-string-unwired` MUST
- `unconfigured-derived` MUST
- `unconfigured-uses-wrapper` MUST
- `pure-synchronous` MUST
- `no-validation` MUST
- `no-errors` MUST
- `server-twin` MUST

# Config Status Opt-Out Fold

## Overview

`packages/web/packages/status-web/src/lib/config-status.ts` is the status board's one addition to the shared configuration-status model. The model itself (`endpointConfigStatus`, `projectStatus`, `partitionPending`, `ConfigStatus`) lives in `@agentic-toolkit/deploy-platform/engine` (`src/engine/classify.ts`), the same classifier the Hono server runs behind `POST /auto-configure`. The header comment says a second copy is "how the front page's banner and the Config badges came to count different things in the first place", so this module does not restate the classification rules.

What the module adds is the board's second way for an operator to say "leave this monitor alone": `isActive: false`, the site's master monitoring switch (the editor's "Monitoring enabled"). It folds that into the engine's single `ignoreProjectWarning` flag at the boundary where the app's rows meet the engine's view of an endpoint. It exports:

- `EndpointLike` — the engine's `EndpointLike` plus an optional `isActive?: boolean`.
- `autoConfigureOptedOut(e)` — the fold itself, shared with the auto-configure adapter.
- `endpointConfigStatus(e)` — the engine's three-way classification of the folded endpoint.
- `endpointUnconfigured(e)` — the boolean "should be wired but isn't, and not dismissed" predicate, derived from the wrapper above.

Use it wherever the board classifies an endpoint row (for example the Sites editor's config filter in `EndpointsSection.tsx`) instead of calling the engine's classifier on the raw row.

## Behavioral Requirements

**Data shape**

- **endpoint-like-shape**: `EndpointLike` MUST carry the engine's fields `kind: string`, `platform: string | null`, `deployProject: string | null` and optional `ignoreProjectWarning?: boolean`, plus an optional `isActive?: boolean`.
- **is-active-optional**: `isActive` MUST be optional, so that a caller that does not carry the field (the engine's `EndpointLite`, a test fixture) type-checks as an `EndpointLike`.

**autoConfigureOptedOut**

- **opt-out-ignore-flag**: `autoConfigureOptedOut` MUST return `true` when `ignoreProjectWarning === true`.
- **opt-out-paused**: `autoConfigureOptedOut` MUST return `true` when `isActive === false`.
- **opt-out-strict-false**: `autoConfigureOptedOut` MUST treat only an explicit `false` in `isActive` as paused; an absent or `undefined` `isActive` MUST NOT count as an opt-out.
- **opt-out-strict-true**: `autoConfigureOptedOut` MUST treat only an explicit `true` in `ignoreProjectWarning` as an opt-out; `false` or absent MUST NOT count.
- **opt-out-default**: `autoConfigureOptedOut` MUST return `false` in every case not covered by opt-out-ignore-flag or opt-out-paused.
- **opt-out-minimal-input**: `autoConfigureOptedOut` MUST read only `ignoreProjectWarning` and `isActive`; its parameter type is `Pick<EndpointLike, "ignoreProjectWarning" | "isActive">`.

**endpointConfigStatus**

- **status-folds-before-classify**: `endpointConfigStatus` MUST classify a copy of the endpoint whose `ignoreProjectWarning` is replaced by `autoConfigureOptedOut(e)`, with every other field passed through unchanged.
- **status-no-mutation**: `endpointConfigStatus` MUST NOT modify the caller's endpoint object; the fold is applied to a shallow spread copy.
- **status-delegates-to-engine**: `endpointConfigStatus` MUST return exactly what the engine's `endpointConfigStatus` returns for the folded copy; the result type is `EndpointConfigStatus` (`"configured" | "unconfigured" | "ignored"`).
- **status-infra-kind**: An endpoint whose `kind` is in the engine's `NON_DEPLOY_KINDS` (`health`, `custom`, `dns`) MUST classify as `configured`, whatever its wiring or opt-out fields.
- **status-wired**: A deploy-backed endpoint with a truthy `platform` and a truthy `deployProject` MUST classify as `configured`.
- **status-paused-wired-stays-configured**: A wired deploy-backed endpoint with `isActive: false` MUST classify as `configured`, not `ignored`; the opt-out is consulted only in the engine's unwired branch, so pausing a site does not un-configure it.
- **status-unwired-opted-out**: A deploy-backed endpoint missing its platform or deploy project MUST classify as `ignored` when `autoConfigureOptedOut` is `true`.
- **status-unwired-not-opted-out**: A deploy-backed endpoint missing its platform or deploy project MUST classify as `unconfigured` when `autoConfigureOptedOut` is `false`.
- **status-empty-string-unwired**: An empty-string `platform` or `deployProject` MUST count as missing, because the engine tests them by truthiness.

**endpointUnconfigured**

- **unconfigured-derived**: `endpointUnconfigured` MUST return `true` exactly when this module's `endpointConfigStatus(e)` returns `"unconfigured"`.
- **unconfigured-uses-wrapper**: `endpointUnconfigured` MUST derive from this module's wrapper, not from the engine's own `endpointUnconfigured`, so that the two predicates agree about a paused endpoint.

**Execution and side effects**

- **pure-synchronous**: Every export MUST be a pure, synchronous function: same input, same output, no I/O, no network, no storage, no logging.
- **no-validation**: The functions MUST NOT validate their input at runtime; the `EndpointLike` type signature is the caller's precondition, and the engine applies the same assumption.
- **no-errors**: Every export MUST return without throwing for any input that satisfies `EndpointLike`; there is no error return path.
- **server-twin**: `autoConfigureOptedOut` MUST give the same answer as the server's adapter function of the same name (`src/routes/auto-configure.ts`); the name is shared so a divergence shows up as two answers to one question. The server's behavior is owned by that route, outside this module.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `e` (every export) | `EndpointLike` (or the two-field `Pick` for `autoConfigureOptedOut`) | none (required) | The endpoint row to fold or classify |
| `e.isActive` | `boolean \| undefined` | `undefined` (treated as active) | The site's master monitoring switch; only `false` means paused |
| `e.ignoreProjectWarning` | `boolean \| undefined` | `undefined` (treated as not ignored) | The per-endpoint "Ignore" opt-out |
| engine classifier | module import `@agentic-toolkit/deploy-platform/engine` | the shared engine | Supplies `endpointConfigStatus`, `EndpointConfigStatus` and the base `EndpointLike`; not injectable |

No environment variables, settings keys or injected dependencies are read.

## Platform Notes

- **SwiftUI**: No UI is involved. Port `EndpointLike` as a `Sendable` struct with `isActive: Bool?` and `ignoreProjectWarning: Bool?`, and write the fold as `ignoreProjectWarning == true || isActive == false` so `nil` keeps its warning. Return an `enum EndpointConfigStatus: String { case configured, unconfigured, ignored }`. Build the folded copy with a `var copy = e` value copy rather than a spread.
- **Compose**: No UI is involved. Use a Kotlin `data class` with nullable `Boolean?` fields, `copy(ignoreProjectWarning = autoConfigureOptedOut(e))` for the folded view, and an `enum class` for the status. Kotlin's `== true` / `== false` on `Boolean?` reproduces the strict checks.
- **React/Web**: Source platform. `config-status.ts` is plain TypeScript with no React; it imports `endpointConfigStatus` (renamed `classifyEndpoint`), `EndpointConfigStatus` and `EndpointLike` from `@agentic-toolkit/deploy-platform/engine`. The fold uses an object spread. Consumers include `components/configure/EndpointsSection.tsx` and the auto-configure adapter in `lib/auto-configure.ts`. Tests use Vitest in `config-status.test.ts`.
- **AppKit / UIKit**: Same as SwiftUI — a plain Swift value type and free functions in a shared framework, with no AppKit or UIKit dependency.
- **WinUI 3**: No XAML control is involved. Port `EndpointLike` as a C# `record` with `bool? IsActive` and `bool? IgnoreProjectWarning`, and produce the folded view with a `with` expression (`e with { IgnoreProjectWarning = AutoConfigureOptedOut(e) }`), which also leaves the original unmodified. Write the fold as `e.IgnoreProjectWarning == true || e.IsActive == false` so `null` is not an opt-out. Return an `enum EndpointConfigStatus { Configured, Unconfigured, Ignored }`; if the rows arrive as JSON, map the lowercase strings with `System.Text.Json` and a `JsonStringEnumConverter` using a camel-case naming policy. Keep the functions synchronous and static — no `Task`/`async` is needed. A view model that shows the status in a filtered `ObservableCollection` recomputes it through this function rather than storing a second copy, and raises `INotifyPropertyChanged` when `IsActive` or the wiring fields change.

## Design Decisions

**Decision**: The paused switch folds into the engine's single `ignoreProjectWarning` flag at the app boundary, not as a new field in the engine.
**Rationale**: The header comment says `isActive` "means nothing to the engine's other consumers; giving the classifier a field per host vocabulary is how a shared model stops being shared." Paused means out of the auto-configure conversation, which is exactly what the per-endpoint opt-out means.
**Approved**: pending

**Decision**: `isActive` is optional and checked with `=== false`, not by falsiness.
**Rationale**: The field comment says a caller that does not carry it "must not have `undefined` read as 'disabled' and silently lose its warning". The test "an ABSENT isActive is not read as disabled" pins it.
**Approved**: pending

**Decision**: `endpointUnconfigured` delegates to this module's wrapper rather than the engine's predicate of the same name.
**Rationale**: The engine's predicate "would classify the raw row and miss the paused fold, so the two predicates would disagree about the same endpoint."
**Approved**: pending

**Decision**: The fold is exported as `autoConfigureOptedOut`, named after the server's twin.
**Rationale**: One expression of the fold serves both the classifier here and the auto-configure adapter's `EndpointLite` mapping, and sharing the server function's name makes a divergence "visible as two different answers to one question rather than two unrelated helpers."
**Approved**: pending

**Decision**: A paused but wired site stays `configured`.
**Rationale**: The engine reads the opt-out only in its unwired branch, so "pausing a site does not un-configure it"; the test says downgrading it "would misreport a healthy setup" in the Config badge. Its deploy project likewise stays claimed (the backend's `listEndpointsForWiring`).
**Approved**: pending
