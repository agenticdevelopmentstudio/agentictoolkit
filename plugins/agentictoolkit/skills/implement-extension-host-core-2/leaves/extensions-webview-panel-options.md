<!-- leaf: implement-extension-host-core-2/extensions-webview-panel-options · source: extension-host-core-extensions-webview-panel-options.md -->

**Rules** (cite as `implement-extension-host-core-2/extensions-webview-panel-options#<slug>`):

- `type-declaration` MUST
- `upstream-field-reduction` MUST
- `scripts-default-false` MUST
- `forms-follow-scripts-default` MUST
- `forms-explicit-overrides-default` MUST
- `roots-declaration-preserved` MUST
- `resolved-initializer-no-derivation` MUST
- `codable-keys` MUST
- `decode-missing-scripts-as-false` MUST
- `decode-missing-forms-follows-decoded-scripts` MUST
- `decode-roots-as-paths` MUST
- `encode-roots-as-paths` MUST
- `resource-roots-default` MUST
- `resource-roots-declared-replaces-default` MUST
- `resource-roots-deduplication` MUST
- `resource-roots-filesystem-read` MUST
- `content-security-policy-computed` MUST
- `content-security-policy-floor` MUST
- `content-security-policy-form-action` MUST
- `content-security-policy-directive-order` MUST
- `value-semantics` MUST
- `sendable-concurrency-safety` MUST

# WebviewPanelOptions

## Overview

`WebviewPanelOptions`, declared in `packages/apple/AgenticToolkit/Core/Extensions/WebviewPanelOptions.swift`, is what `vscode.window.createWebviewPanel`'s `WebviewOptions` argument amounts to once this host's defaults are applied. Upstream's `WebviewOptions` has eight fields; this type carries three — `enableScripts`, `enableForms`, `declaredLocalResourceRoots` — and, per the type's own header comment, each of the other five is missing for its own distinct reason rather than a shared "not yet": `retainContextWhenHidden` is already permanently true of every pane this host hosts, `enableFindWidget` names a widget that does not exist, `enableCommandUris` and `portMapping` are real, unbuilt capabilities recorded elsewhere (in `NotImplementedLedger`, by `MainThreadWebviews`) rather than carried here as an inert flag, and `iconPath` is answered by the pane's own title rather than by this type.

The type is a plain `Codable`, `Equatable`, `Sendable` value type with no side effects of its own beyond one read-only file-system consultation. It is constructed twice, through two different initializers with two different jobs: the as-declared initializer (`init(enableScripts:enableForms:localResourceRoots:)`) turns what an extension actually wrote — including three possible states of "absent" — into resolved values, while the resolved-form initializer (`init(enableScripts:enableForms:declaredLocalResourceRoots:)`) and `Decodable`'s `init(from:)` assign already-resolved values straight through, because a restored panel (`WebviewPanelState`, which stores a `WebviewPanelOptions` verbatim in the app's pane-state store) must come back with the answer the panel actually had, not a value re-derived from it. Beyond storage, the type does two things a caller relies on: `resourceRoots(extensionDirectory:workspaceRoots:)` turns the declared-or-default root list into the deduplicated list of directories a panel's scheme handler may read from, and `contentSecurityPolicy` composes the floor CSP string every panel's webview is served under, adjusted only by whether forms are enabled. `ExtensionWebviewPanel.options` (in `ExtensionWebviewPresenting.swift`) is the one place a webview *view* provider can turn scripts on after the fact — its panel is handed to it already built — and `WebviewPanelViewController.options`'s `didSet` is what re-applies a changed value, by re-assigning the scheme handler's `contentSecurityPolicy` and reloading the host document; that re-application is a different component's contract (see `agentictoolkit://recipes/webview-panel-view-controller`) and is only described here as the reason `WebviewPanelOptions` itself needs no mutable state of its own.

## Behavioral Requirements

- **type-declaration**: `WebviewPanelOptions` MUST be a `public struct` conforming to `Codable`, `Equatable`, and `Sendable`, with exactly three stored properties: `enableScripts: Bool`, `enableForms: Bool`, `declaredLocalResourceRoots: [URL]?`.
- **upstream-field-reduction**: The type MUST expose only `enableScripts`, `enableForms`, and `declaredLocalResourceRoots`, and MUST NOT declare any stored property, initializer parameter, or computed value named `retainContextWhenHidden`, `enableFindWidget`, `enableCommandUris`, `portMapping`, or `iconPath`.
- **scripts-default-false**: `init(enableScripts:enableForms:localResourceRoots:)` MUST set `enableScripts` to `false` when its `enableScripts` parameter is `nil`, and to that parameter's value otherwise.
- **forms-follow-scripts-default**: `init(enableScripts:enableForms:localResourceRoots:)` MUST set `enableForms` to the just-resolved `enableScripts` value when its `enableForms` parameter is `nil`.
- **forms-explicit-overrides-default**: `init(enableScripts:enableForms:localResourceRoots:)` MUST set `enableForms` to its `enableForms` parameter's value, independent of `enableScripts`, whenever that parameter is non-`nil`.
- **roots-declaration-preserved**: `init(enableScripts:enableForms:localResourceRoots:)` MUST store its `localResourceRoots` parameter into `declaredLocalResourceRoots` unchanged: a `nil` argument MUST remain `nil` and an empty-array argument MUST remain an empty array, with neither coerced into the other.
- **resolved-initializer-no-derivation**: `init(enableScripts:enableForms:declaredLocalResourceRoots:)` MUST assign each of its three parameters directly to the like-named stored property and MUST NOT perform the `??`-based derivation the as-declared initializer performs.
- **codable-keys**: `Codable` conformance MUST encode and decode exactly the three keys named in `CodingKeys` — `enableScripts`, `enableForms`, `localResourceRoots` — and no others.
- **decode-missing-scripts-as-false**: `init(from:)` MUST decode `enableScripts` as `false` when the container has no `enableScripts` key.
- **decode-missing-forms-follows-decoded-scripts**: `init(from:)` MUST decode `enableForms` as the value it just decoded for `enableScripts` when the container has no `enableForms` key.
- **decode-roots-as-paths**: `init(from:)` MUST decode `localResourceRoots` as an optional `[String]` and construct `declaredLocalResourceRoots` by mapping each string through `URL(fileURLWithPath:)`; it MUST NOT decode the roots through `URL`'s own `Codable` conformance.
- **encode-roots-as-paths**: `encode(to:)` MUST encode `declaredLocalResourceRoots`, when non-`nil`, as an array of each URL's `.path` string under the `localResourceRoots` key via `encodeIfPresent`, and MUST omit the `localResourceRoots` key entirely when `declaredLocalResourceRoots` is `nil`.
- **resource-roots-default**: `resourceRoots(extensionDirectory:workspaceRoots:)` MUST return the deduplicated concatenation of `[extensionDirectory]` followed by `workspaceRoots`, in that order, whenever `declaredLocalResourceRoots` is `nil`.
- **resource-roots-declared-replaces-default**: `resourceRoots(extensionDirectory:workspaceRoots:)` MUST return the deduplicated `declaredLocalResourceRoots` value, ignoring both `extensionDirectory` and `workspaceRoots` entirely, whenever `declaredLocalResourceRoots` is non-`nil` — including when it is an empty array.
- **resource-roots-deduplication**: `resourceRoots(extensionDirectory:workspaceRoots:)` MUST drop every later root whose `ExtensionResourcePath.canonicalDirectory(_:).path` matches a root already kept, preserving the order and the spelling of each distinct directory's first occurrence.
- **resource-roots-filesystem-read**: `resourceRoots(extensionDirectory:workspaceRoots:)` MUST consult the file system, through `ExtensionResourcePath.canonicalDirectory`'s symlink resolution inside `deduplicated`, to compare candidate roots canonically, but MUST NOT create, delete, or write to any file or directory.
- **content-security-policy-computed**: The `contentSecurityPolicy` computed property MUST return `Self.contentSecurityPolicy(allowingForms: enableForms)` — the resolved `enableForms` value stored on `self`, never a raw, possibly-`nil` initializer parameter.
- **content-security-policy-floor**: `contentSecurityPolicy(allowingForms:)` MUST always include the directives `object-src 'none'`, `base-uri 'none'`, and `frame-ancestors 'none'`, regardless of `allowingForms`.
- **content-security-policy-form-action**: `contentSecurityPolicy(allowingForms:)` MUST include `form-action 'none'` when `allowingForms` is `false`, and MUST include no `form-action` directive at all when `allowingForms` is `true`.
- **content-security-policy-directive-order**: `contentSecurityPolicy(allowingForms:)` MUST join its directives with the separator `"; "` in the fixed order `object-src`, `base-uri`, `form-action` (present only when `allowingForms` is `false`), `frame-ancestors`.
- **value-semantics**: Two `WebviewPanelOptions` values MUST compare equal under `==` if and only if their `enableScripts`, `enableForms`, and `declaredLocalResourceRoots` are each equal.
- **sendable-concurrency-safety**: Because `WebviewPanelOptions` declares `Sendable` conformance and holds no mutable stored state reachable from more than one call, every instance and static member on it MUST be safe to invoke concurrently, from any thread or actor, without additional synchronization.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enableScripts` | `Bool?` | `nil` (resolves to `false`) | The option as the extension wrote it, passed to `init(enableScripts:enableForms:localResourceRoots:)`; `nil` means the option was absent. |
| `enableForms` | `Bool?` | `nil` (resolves to the resolved `enableScripts` value) | The option as the extension wrote it; `nil` means the option was absent and follows `enableScripts`. |
| `localResourceRoots` | `[URL]?` | `nil` (resolves to `[extensionDirectory] + workspaceRoots` once `resourceRoots` is called) | The option as the extension wrote it; `nil` means absent, `[]` means an explicit, honored declaration of no file access. |
| `extensionDirectory` | `URL` | none (required) | The owning extension's install directory, passed to `resourceRoots(extensionDirectory:workspaceRoots:)`; the first element of the default root list when `declaredLocalResourceRoots` is `nil`. |
| `workspaceRoots` | `[URL]` | none (required; empty when no project is open) | Every open workspace folder, passed to `resourceRoots(extensionDirectory:workspaceRoots:)`; appended after `extensionDirectory` in the default root list. |
| `allowingForms` | `Bool` | none (required) | Passed to the static `contentSecurityPolicy(allowingForms:)`; in practice always the resolved `enableForms` of the `WebviewPanelOptions` value asking for a policy. |

There are no environment variables or settings keys involved: every input arrives as a plain function or initializer argument, or — for the `Decodable` path — as one of the three `CodingKeys` read from whatever JSON the caller (`WebviewPanelState`, via the app's own pane-state store) hands the decoder.

