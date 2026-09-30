<!-- leaf: implement-status-web-src-lib-1/endpoint-kinds · source: status-web-src-lib-endpoint-kinds.md -->

**Rules** (cite as `implement-status-web-src-lib-1/endpoint-kinds#<slug>`):

- `kinds-members` MUST
- `kinds-order` MUST
- `kinds-readonly` MUST
- `kinds-lowercase` MUST
- `kind-type-derived` MUST
- `kind-type-single-source` MUST
- `guard-signature` MUST
- `guard-true` MUST
- `guard-false` MUST
- `guard-no-normalization` MUST
- `guard-no-throw` MUST
- `guard-no-callers` MUST
- `non-deploy-reexport` MUST
- `non-deploy-members` MUST
- `non-deploy-subset` MUST
- `non-deploy-ownership` MUST
- `pure-module` MUST

# Endpoint Kinds

## Overview

`endpoint-kinds.ts` (`packages/web/packages/status-web/src/lib/endpoint-kinds.ts`) is the status web app's single declaration of which `kind` values a monitored endpoint may carry. Its authoring comment calls it "ONE source for the editor dropdown (api/monitored-sites re-exports this), server-side validation (the endpoints routes), and the 'needs wiring' warning logic (config-status)".

It exports four things:

- `ENDPOINT_KINDS`, a readonly tuple of the six kind strings, in display order.
- `EndpointKind`, the string-literal union derived from that tuple.
- `isEndpointKind(k)`, a type guard that narrows an arbitrary string to `EndpointKind`.
- `NON_DEPLOY_KINDS`, re-exported unchanged from `@agentic-toolkit/deploy-platform/engine` (`classify.ts`). The module does not restate its members.

The module has no state, no I/O and no side effects. Inside status-web, `src/api/monitored-sites.ts` re-exports `ENDPOINT_KINDS` so existing imports from `./monitored-sites` keep working (Status Web API). The status server keeps its own copy of the same vocabulary in `status-server/src/monitor/endpoint-kinds.ts`, which it says is "kept in step" with this file.

## Behavioral Requirements

### ENDPOINT_KINDS

- **kinds-members**: `ENDPOINT_KINDS` MUST contain exactly the six strings `"http"`, `"frontend"`, `"admin"`, `"health"`, `"custom"` and `"dns"`.
- **kinds-order**: `ENDPOINT_KINDS` MUST list the kinds in the order `http`, `frontend`, `admin`, `health`, `custom`, `dns`. Consumers that render the list as a dropdown show it in this order, and a consumer that takes the first element as a default gets `"http"`.
- **kinds-readonly**: `ENDPOINT_KINDS` MUST be declared `as const`, so its type is a readonly tuple of literal strings. Any attempt to push to, splice or reassign an element MUST fail type-checking.
- **kinds-lowercase**: Every member MUST be a lowercase ASCII word with no whitespace. Matching against the list is exact and case-sensitive.

### EndpointKind

- **kind-type-derived**: `EndpointKind` MUST be derived from `ENDPOINT_KINDS` by indexed access (`(typeof ENDPOINT_KINDS)[number]`), so it is the union `"http" | "frontend" | "admin" | "health" | "custom" | "dns"`.
- **kind-type-single-source**: Adding or removing a member of `ENDPOINT_KINDS` MUST change `EndpointKind` with no second edit. The union is never written out by hand.

### isEndpointKind

- **guard-signature**: `isEndpointKind` MUST take one argument `k: string` and MUST return a `boolean` that the type system treats as the predicate `k is EndpointKind`.
- **guard-true**: `isEndpointKind` MUST return `true` when `k` is exactly equal (strict `===`, as `Array.prototype.includes` compares strings) to one of the six members.
- **guard-false**: `isEndpointKind` MUST return `false` for every other string, including the empty string, a member with different casing (`"HTTP"`), a member with surrounding whitespace (`" http"`), and kinds used by other vocabularies such as `"tcp"` or `"icmp"`.
- **guard-no-normalization**: `isEndpointKind` MUST NOT trim, lowercase or otherwise normalize `k` before comparing it.
- **guard-no-throw**: `isEndpointKind` MUST NOT throw for any string argument.
- **guard-no-callers**: No module in the repository calls this file's `isEndpointKind`. The status server validates with its own identically written `isEndpointKind` in `status-server/src/monitor/endpoint-kinds.ts`. A port MUST still provide the guard, because it is part of the exported contract.

### NON_DEPLOY_KINDS

- **non-deploy-reexport**: The module MUST re-export `NON_DEPLOY_KINDS` from `@agentic-toolkit/deploy-platform/engine` as the same object. It MUST NOT declare its own set. The authoring comment says it is "Re-exported (never restated)" so the warning badge and the engine's classification cannot disagree about `dns`.
- **non-deploy-members**: Through that re-export, `NON_DEPLOY_KINDS` MUST be a `ReadonlySet<string>` containing exactly `"health"`, `"custom"` and `"dns"`, as the engine declares it.
- **non-deploy-subset**: Every member of `NON_DEPLOY_KINDS` MUST also be a member of `ENDPOINT_KINDS`. The deploy-backed kinds are therefore `http`, `frontend` and `admin`, which the engine's `endpointNeedsWiring` returns `true` for.
- **non-deploy-ownership**: Which kinds are deploy-backed MUST be decided by the engine, not by this module. The authoring comment says this is "the CLASSIFIER's knowledge, not this list's". This module's consumers that need the classification (for example `config-status.ts`) call the engine's classifier directly.

### Purity and concurrency

- **pure-module**: The module MUST have no side effects on import and hold no mutable state. Its exports are a constant tuple, a type, a pure function and a re-exported constant.
- **single-threaded**: The module runs on the single JavaScript thread and holds no mutable state, so concurrent calls cannot interleave and it needs no ordering rule.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ENDPOINT_KINDS` | `readonly ["http", "frontend", "admin", "health", "custom", "dns"]` | compiled in | The vocabulary itself. Changing it means editing the source. |
| `NON_DEPLOY_KINDS` | `ReadonlySet<string>` | `{"health", "custom", "dns"}`, from the engine | Supplied by `@agentic-toolkit/deploy-platform/engine`. |
| `k` (argument to `isEndpointKind`) | `string` | none (required) | The candidate kind string to test. |

The module reads no environment variables and no settings keys, and takes no injected dependencies. Its one import is the re-export from `@agentic-toolkit/deploy-platform/engine`.

## Platform Notes

- **SwiftUI**: Port the vocabulary as `enum EndpointKind: String, CaseIterable, Codable, Sendable { case http, frontend, admin, health, custom, dns }`. `EndpointKind.allCases` replaces `ENDPOINT_KINDS` and keeps declaration order for a `Picker`. `EndpointKind(rawValue:)` replaces `isEndpointKind`, returning `nil` instead of `false`, and it is case-sensitive like the source. Expose `NON_DEPLOY_KINDS` as a `static let nonDeployKinds: Set<EndpointKind>` owned by the classifier module and re-exported, not restated.
- **Compose**: Use a Kotlin `enum class EndpointKind(val wire: String)` with `entries` for the ordered list, or a `val ENDPOINT_KINDS = listOf(...)`. Implement the guard as `fun isEndpointKind(k: String) = EndpointKind.entries.any { it.wire == k }`. `enumValueOf` throws on a miss, so do not use it as the guard. Keep `NON_DEPLOY_KINDS` as a `Set<String>` in the classifier module.
- **React/Web**: This is the source: `src/lib/endpoint-kinds.ts`, re-exported by `src/api/monitored-sites.ts`. It relies on `as const` to derive the literal union and on `Array.prototype.includes` for an exact, case-sensitive match. The `as readonly string[]` cast widens the tuple so `includes` accepts any string. `NON_DEPLOY_KINDS` comes from `deploy-platform/src/engine/classify.ts`. The status server holds a hand-synchronised twin in `status-server/src/monitor/endpoint-kinds.ts`.
- **AppKit / UIKit**: Use the same Swift enum as the SwiftUI port. Feed `EndpointKind.allCases` to an `NSPopUpButton` or a `UIMenu` for the editor dropdown. Nothing in the module is UI-bound, so it belongs in a shared framework target.
- **WinUI 3**: Port as a `public static class EndpointKinds` in C# with `public static readonly IReadOnlyList<string> All = ["http", "frontend", "admin", "health", "custom", "dns"];` and `public static bool IsEndpointKind(string k) => All.Contains(k, StringComparer.Ordinal);`. Use ordinal comparison to keep the source's case-sensitive match. If a strongly typed kind is wanted, add `public enum EndpointKind { Http, Frontend, Admin, Health, Custom, Dns }` with a `JsonStringEnumConverter` (lowercase naming policy) so `System.Text.Json` writes the same wire strings. C# has no type-predicate narrowing, so the guard becomes `bool TryParse(string k, out EndpointKind kind)` in that design. Bind the editor dropdown's `ComboBox.ItemsSource` to `EndpointKinds.All`; it is immutable, so no `ObservableCollection` is needed. Expose the non-deploy set as `public static readonly IReadOnlySet<string> NonDeployKinds` (for example a `FrozenSet<string>`) owned by the classifier assembly and referenced, not copied. Everything is synchronous, with no `Task`.

## Design Decisions

**Decision**: Declare the vocabulary once as an `as const` tuple and derive both the type and the guard from it.
**Rationale**: The authoring comment names three consumers (the editor dropdown, server-side validation, and the needs-wiring logic). Deriving `EndpointKind` by indexed access means one edit changes the runtime list, the type and the guard together.
**Approved**: pending

**Decision**: Re-export `NON_DEPLOY_KINDS` from the deploy engine instead of declaring it here.
**Rationale**: The authoring comment says the set "used to be three separate literal Sets, here, on the Hono server, and in the engine", and they disagreed about `dns`. The engine's `endpointNeedsWiring` acts on the set, so the engine owns it and every consumer re-exports the same object.
**Approved**: pending

**Decision**: The status server keeps its own copy of `ENDPOINT_KINDS` and `isEndpointKind` rather than importing this file.
**Rationale**: The server copy's comment says it is "kept in step with the status site's src/lib/endpoint-kinds.ts so the backend and frontend agree". The two packages do not share this module, so the list is restated and synchronised by hand, with no parity test. This contradicts this file's claim to be the "ONE source" for server-side validation; in practice the server validates with its twin.
**Approved**: pending

**Decision**: The guard compares exactly, with no normalization.
**Rationale**: `isEndpointKind` is a plain `includes` check. Kind strings are machine identifiers written by the editor's dropdown, so a case or whitespace variant is not a valid kind.
**Approved**: pending
