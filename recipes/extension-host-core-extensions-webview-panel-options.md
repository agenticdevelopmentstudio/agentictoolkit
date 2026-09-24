---
id: 66759d9a-3884-42e1-acd9-5bad563e1e52
title: WebviewPanelOptions
domain: agentictoolkit://recipes/extension-host-core-extensions-webview-panel-options
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Derives a webview panel's resolved scripts/forms/resource-root options and
  its floor Content-Security-Policy from what an extension declared.
platforms:
- swift
- macos
tags:
- extensions
- webview
- content-security-policy
- resource-roots
- vscode-compatibility
depends-on:
- agenticdevelopercookbook://guidelines/implementing/security/content-security-policy
related:
- agentictoolkit://recipes/webview-panel-view-controller
- agentictoolkit://recipes/extension-host-core-extensions-extension-resource-path
references:
- packages/apple/AgenticToolkit/Core/Extensions/WebviewPanelOptions.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Extensions/WebviewPanelOptionsTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/WebviewPanelState.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/ExtensionResourcePath.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/WebviewResourceURL.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/Webview/WebviewPanelViewController.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadWebviews.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionWebviewPresenting.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/Host/ExtensionHostInstaller.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/ExtensionsCoordinator.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a data model and policy-derivation utility for webview creation options, not a visual component.

## States

Not applicable — this is a data model and policy-derivation utility for webview creation options, not a visual component.

## Accessibility

Not applicable — this is a data model and policy-derivation utility for webview creation options, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| wpo-001 | scripts-default-false | `WebviewPanelOptions(enableScripts: nil, enableForms: nil, localResourceRoots: nil)` vs. `WebviewPanelOptions(enableScripts: true, enableForms: nil, localResourceRoots: nil)` | first `.enableScripts == false`; second `.enableScripts == true` (source: `scriptsAreOffUnlessAskedFor`) |
| wpo-002 | forms-follow-scripts-default | `enableScripts: true, enableForms: nil` vs. `enableScripts: false, enableForms: nil` | first `.enableForms == true`; second `.enableForms == false` (source: `formsFollowScripts`) |
| wpo-003 | forms-explicit-overrides-default | `enableScripts: false, enableForms: true` vs. `enableScripts: true, enableForms: false` | first `.enableForms == true`; second `.enableForms == false` (source: `formsCanBeSetAgainstScripts`) |
| wpo-004 | resource-roots-default | `resourceRoots(extensionDirectory:, workspaceRoots: [workspace, secondWorkspace])` with `localResourceRoots: nil` | returns 3 roots; the first equals `extensionDirectory`; the list contains `workspace` (source: `undeclaredRootsAreTheExtensionAndTheWorkspace`) |
| wpo-005 | resource-roots-declared-replaces-default, roots-declaration-preserved | `resourceRoots(extensionDirectory:, workspaceRoots: [secondWorkspace])` with `localResourceRoots: [workspace]` | returns exactly `[workspace]`; `extensionDirectory` and `secondWorkspace` are absent (source: `declaredRootsAreTheOnlyRoots`) |
| wpo-006 | resource-roots-declared-replaces-default, roots-declaration-preserved | same call with `localResourceRoots: []` | returns an empty array, not the default `[extensionDirectory] + workspaceRoots` (source: `anEmptyDeclarationIsNoAccess`) |
| wpo-007 | resource-roots-deduplication | `resourceRoots` with `workspaceRoots: [workspace, workspace, extensionDirectory]`, `localResourceRoots: nil` | returns 2 entries; the first is `extensionDirectory` (source: `rootsAreDeduplicated`) |
| wpo-008 | resource-roots-deduplication, resource-roots-filesystem-read | `localResourceRoots` holding four differently-spelled paths to the same directory (a trailing slash, a `/./` suffix, and a `Sources` component followed by `..`) | `resourceRoots` returns exactly 1 entry (source: `spellingsOfOneDirectoryAreOneRoot`) |
| wpo-009 | content-security-policy-floor | `contentSecurityPolicy(allowingForms: true)` and `contentSecurityPolicy(allowingForms: false)` | both contain `object-src 'none'`, `base-uri 'none'`, and `frame-ancestors 'none'` (source: `theContentPolicyAlwaysShutsTheSameThreeDoors`) |
| wpo-010 | content-security-policy-form-action | `contentSecurityPolicy(allowingForms: false)` vs. `contentSecurityPolicy(allowingForms: true)` | first contains `form-action 'none'`; second contains no `form-action` directive (source: `formActionFollowsTheFormsOption`) |
| wpo-011 | content-security-policy-computed | `WebviewPanelOptions(enableScripts: true, enableForms: nil, localResourceRoots: nil).contentSecurityPolicy` | contains no `form-action` directive, because the resolved `enableForms` (`true`, following scripts) drove the policy, not the raw `nil` parameter (source: `thePolicyIsWhatThePanelAskedFor`) |
| wpo-012 | content-security-policy-directive-order | `contentSecurityPolicy(allowingForms: false)` | equals exactly the string `object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'` (traced directly to the directive array's construction order in `contentSecurityPolicy(allowingForms:)`) |
| wpo-013 | type-declaration, value-semantics | two `WebviewPanelOptions` values built with identical `enableScripts`, `enableForms`, and `declaredLocalResourceRoots` arguments | compare equal under `==`; changing any one of the three arguments makes the comparison `false` (traced to the synthesized `Equatable` conformance over the type's three stored properties) |
| wpo-014 | codable-keys, decode-missing-scripts-as-false, decode-missing-forms-follows-decoded-scripts | decode the JSON object `{}` via `JSONDecoder().decode(WebviewPanelOptions.self, from:)` | `.enableScripts == false`, `.enableForms == false`, `.declaredLocalResourceRoots == nil` (traced to `init(from:)`'s two `decodeIfPresent` fallbacks) |
| wpo-015 | decode-roots-as-paths | decode `{"enableScripts": true, "enableForms": true, "localResourceRoots": ["/a/b", "/c/d"]}` | `.declaredLocalResourceRoots == [URL(fileURLWithPath: "/a/b"), URL(fileURLWithPath: "/c/d")]` (traced to `init(from:)`'s `[String]` decode and `URL(fileURLWithPath:)` mapping) |
| wpo-016 | encode-roots-as-paths | encode a value with `declaredLocalResourceRoots: [URL(fileURLWithPath: "/a/b")]`, then decode the resulting JSON back | the encoded `localResourceRoots` array holds the plain string `"/a/b"`, not a nested keyed container; decoding it back round-trips to an equal value (traced to `encode(to:)`'s `.map(\.path)`) |
| wpo-017 | encode-roots-as-paths | encode a value with `declaredLocalResourceRoots: nil` | the resulting JSON object has no `localResourceRoots` key (traced to `encode(to:)`'s use of `encodeIfPresent`) |
| wpo-018 | resolved-initializer-no-derivation | `WebviewPanelOptions(enableScripts: false, enableForms: true, declaredLocalResourceRoots: nil)` | `.enableForms == true` even though `enableScripts` is `false` — no scripts-follow derivation runs (traced directly to the initializer's three straight assignments, none of which uses `??`) |
| wpo-019 | upstream-field-reduction, type-declaration | inspect `WebviewPanelOptions`'s stored properties and both initializers' parameter lists | exactly `enableScripts`, `enableForms`, `declaredLocalResourceRoots`/`localResourceRoots` appear; no parameter or property named `retainContextWhenHidden`, `enableFindWidget`, `enableCommandUris`, `portMapping`, or `iconPath` appears anywhere in the declaration (traced to the full type declaration and its header comment's enumeration of the five excluded fields) |
| wpo-020 | sendable-concurrency-safety | call `resourceRoots(extensionDirectory:workspaceRoots:)` and read `contentSecurityPolicy` concurrently from many detached tasks against the same `WebviewPanelOptions` value | every call completes with the result its own inputs imply; no crash and no data race occurs (traced to the value type holding no mutable stored state and its explicit `Sendable` conformance) |
| wpo-021 | resource-roots-filesystem-read | call `resourceRoots(extensionDirectory:workspaceRoots:)` against a scratch directory, then enumerate that directory's contents before and after the call | the directory's entries are unchanged — no file or folder is created, deleted, or modified (traced to the absence of any create/write call in `WebviewPanelOptions.swift`; the only file-system access is the read-only symlink resolution inside `deduplicated`) |
| wpo-022 | roots-declaration-preserved | inspect the as-declared initializer's assignment `self.declaredLocalResourceRoots = localResourceRoots` | passing `nil` yields a stored value of `nil`; passing `[]` yields a stored value of `[]` — the two are never coalesced (traced directly to the assignment performing no `??` substitution, and exercised indirectly by wpo-005/wpo-006's differing `resourceRoots` outputs) |

## Edge Cases

- **Null input on every option**: `WebviewPanelOptions(enableScripts: nil, enableForms: nil, localResourceRoots: nil)` is the fully-absent case; it resolves to the safest posture — scripts off, forms off, and the default two-root list (extension directory plus every open workspace folder) once `resourceRoots` is called. MUST.
- **Empty-array roots versus absent roots**: an empty `localResourceRoots` array is not the same input as a `nil` one — the empty array is honored as "no file access at all," while `nil` takes the extension-directory-plus-workspace default. Collapsing the two is the exact hazard the source's own comment names: a panel that deliberately renounced file access must not be handed the whole workspace. MUST.
- **Boundary — extensionDirectory duplicated in workspaceRoots**: when the default root list's two sources overlap (an open workspace folder that canonicalizes to the same directory as `extensionDirectory`), `resourceRoots` keeps only the first occurrence — `extensionDirectory` — and drops the duplicate workspace entry, per `resource-roots-deduplication`. MUST.
- **Concurrent access**: `WebviewPanelOptions` holds no mutable stored state — every stored property is a `let`, and its own methods and static functions read only their arguments and `self`. Calling any of them concurrently, from any thread or actor, against the same or different values requires no synchronization. MUST.
- **Error states**: this type defines no throwing function of its own other than the compiler-synthesized `init(from:) throws`, whose only failure path is `Decoder`'s own `DecodingError` when a present key's JSON value cannot be decoded as its declared type (for example a non-Boolean `enableScripts`); that error propagates untouched — nothing in `WebviewPanelOptions.swift` catches or discards it. Stated as fact, per the absent-feature rule: the source defines no other error condition. MUST.
- **Offline / disconnected state**: not applicable. `WebviewPanelOptions.swift` performs no networking; its only I/O is the local, read-only symlink resolution `resourceRoots` performs through `ExtensionResourcePath.canonicalDirectory`, which has no connectivity state to lose.
- **Cancellation and timeout**: `resourceRoots(extensionDirectory:workspaceRoots:)` and `contentSecurityPolicy` define no timeout and no cancellation, because both are synchronous, non-`async` calls; a slow or unresponsive mount underneath a declared root blocks the caller for as long as symlink resolution takes, with no escape hatch defined in this file. Stated as fact, per the absent-feature rule — not a marker, since nothing in a synchronous options struct's purpose calls for one.
- **A declared root that does not exist on disk**: `resourceRoots` performs no existence check on any declared or default root before canonicalizing it for deduplication; a root naming a directory that has since been deleted or was never created is passed through `ExtensionResourcePath.canonicalDirectory` (whose symlink resolution is a no-op on a path that does not resolve to anything) and returned to the caller unchanged. This is a fact about the collaborator this type delegates canonicalization to, not a gap in this file's own contract.

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

## Deep Linking

Not applicable: `WebviewPanelOptions.swift` resolves options and composes an in-memory policy string; it defines no URL scheme, route, or navigable destination.

## Localization

Not applicable: `WebviewPanelOptions.swift` produces no user-facing string. Its one string output, `contentSecurityPolicy`, is a Content-Security-Policy header value that the panel's `WebviewSchemeHandler` and `WKWebView` consume as protocol data, never text rendered for a person to read.

## Accessibility Options

Not applicable: this component has no visual or interactive surface for a system accessibility display option to affect.

## Feature Flags

Not applicable: `WebviewPanelOptions.swift` defines no feature flag, build configuration check, or remote-config lookup; every function's output is fixed entirely by the arguments it is called with.

## Analytics

Not applicable: this component emits no analytics event; it returns a `[URL]`, a `String`, or a decoded/encoded value to its caller and performs no telemetry of its own. (An extension's use of the two unbuilt fields this type excludes, `enableCommandUris` and `portMapping`, is recorded by `NotImplementedLedger` — but that recording happens in `MainThreadWebviews`, a different file, before a `WebviewPanelOptions` value is ever constructed.)

## Privacy

- **Data collected**: none in the device- or user-identifying telemetry sense. However, `declaredLocalResourceRoots`, and every `URL` that `resourceRoots(extensionDirectory:workspaceRoots:)` returns, are absolute local file-system paths; when the default (undeclared) root list is used, those paths necessarily embed wherever `extensionDirectory` and each workspace folder happen to live on the local machine, which can include the local account's home-directory name.
- **Storage**: none performed by `WebviewPanelOptions.swift` itself — it writes to no file and no database. Its `Codable` conformance exists so that a caller, specifically `WebviewPanelState` (per that type's own doc comment), can persist a `WebviewPanelOptions` value verbatim into the app's own pane-state store as part of restoring a panel after a quit; this file never performs that write itself.
- **Transmission**: none — this file performs no networking of its own.
- **Retention**: for as long as the caller (or, downstream, the pane-state store a persisted `WebviewPanelState` is written into) retains the value; `WebviewPanelOptions.swift` itself retains nothing once a call returns.

## Logging

Not applicable: `WebviewPanelOptions.swift` contains no logging call and imports no logging framework; there is nothing for this file to log, since it defines no error case of its own and every value it produces is returned directly to its caller.

## Platform Notes

- **SwiftUI**: the source (`WebviewPanelOptions.swift`) is plain Foundation (`URL`, `Codable`) with zero dependency on SwiftUI or any view-layer framework. It lives in `AgenticToolkitCore`, the tier every macOS extension-host feature (`WebviewPanelViewController`, `MainThreadWebviews`, `ExtensionHostInstaller`, `ExtensionsCoordinator`, `WebviewPanelState`) reaches down into. A port that keeps this component in Swift needs nothing beyond `Foundation`.
- **Compose**: model `WebviewPanelOptions` as a Kotlin `data class` with three `val` properties, giving structural equality and immutability for free in place of the hand-written `Equatable`. Serialize with `kotlinx.serialization`'s `@Serializable`, using a custom `Serializer` (or `@Serializable(with = ...)`) to reproduce the two `decodeIfPresent`-style defaulting rules, since `kotlinx.serialization` treats a missing key as a compile-time-declared default rather than a runtime fallback chained off a sibling field's just-decoded value. Compose the CSP string with a plain `buildString`/`joinToString` in the same fixed directive order.
- **React/Web**: model the type as a plain TypeScript interface (or a small class) mirroring upstream's own `vscode.WebviewOptions` shape, reduced to the same three fields; the defaulting logic (`enableForms` following `enableScripts`, `nil` and `[]` roots meaning different things) has to be hand-written the same way the source hand-writes it, since TypeScript's structural typing gives no default-value mechanism of its own. Compose the CSP string with `Array.prototype.join('; ')` over the same fixed directive order, and, in a browser or Electron host, apply it via a `Content-Security-Policy` response header or `<meta http-equiv="Content-Security-Policy">` tag rather than a native webview configuration object.
- **AppKit / UIKit**: identical to the SwiftUI note — the component depends on neither AppKit nor UIKit, so a macOS host consumes the same `AgenticToolkitCore` type directly with no translation needed. (No iOS target exists for this component today; every current caller is under `packages/apple/AgenticToolkit/macOS/`.)
- **WinUI 3**: there is no single .NET or Windows App SDK type that reproduces this three-field, dual-initializer shape; model it as a C# `record` (`enableScripts`/`enableForms`/`declaredLocalResourceRoots`, the latter an `IReadOnlyList<string>?`) with a static factory reproducing the `enableForms`-follows-`enableScripts` default and the `null`-versus-empty-list distinction for roots, plus `System.Text.Json`'s `JsonConverter<T>` for the same two-key-defaulting decode `WebviewPanelOptions.init(from:)` performs — `System.Text.Json`'s own missing-property handling only supports a compile-time-fixed default, not one derived from a sibling property at decode time. There is no `Microsoft.Web.WebView2.Core` equivalent of a per-navigation, editable Content-Security-Policy the way this source's `WKWebViewConfiguration`-independent CSP string is; `CoreWebView2.WebResourceRequested` (adding a `Content-Security-Policy` response header) or a `CoreWebView2Settings.IsScriptEnabled` toggle at initialization are the closest WebView2 primitives, and unlike this source's re-appliable `options` property, `CoreWebView2Settings.IsScriptEnabled` cannot be changed after the first navigation without a full reload, mirroring this source's own reload-on-change design (see `agentictoolkit://recipes/webview-panel-view-controller`) rather than avoiding it. Resource-root containment has no WebView2 equivalent either; `SetVirtualHostNameToFolderMapping` maps a single folder to a virtual host and would need to be called once per declared root. `HttpClient`, `Task`/`async`, `ObservableCollection`, and `INotifyPropertyChanged` play no role here: every operation in the source is synchronous, non-networked, and returns a value rather than raising a change notification.

## Design Decisions

- **Decision**: `enableForms` defaults to whatever `enableScripts` resolved to, rather than defaulting independently to `false`.
  **Rationale**: the source's own doc comment and the test suite's comment agree on why: a scripted page that cannot submit a form fails in a way its author cannot see — "the click does nothing and the console says only that a content policy refused it" — so the safer silent default is the one that keeps forms working wherever scripts already do.
  **Approved**: pending
- **Decision**: `declaredLocalResourceRoots` preserves the distinction between an absent declaration (`nil`) and an explicit, empty one (`[]`), rather than collapsing both into the same default root list.
  **Rationale**: the source's doc comment states the consequence of collapsing them directly — it would hand a panel that deliberately renounced file access the whole workspace instead of honoring what it asked for.
  **Approved**: pending
- **Decision**: the five upstream `WebviewOptions` fields this type omits (`retainContextWhenHidden`, `enableFindWidget`, `enableCommandUris`, `portMapping`, `iconPath`) are not represented anywhere on the type — not even as an ignored or always-`true` stored property.
  **Rationale**: the header comment gives each a distinct reason: `retainContextWhenHidden` is already permanently true of every pane here, so a field whose only honest implementation is "already true" is one nothing may read; `enableFindWidget` names a widget with no implementation to enable; `enableCommandUris` and `portMapping` are real, unbuilt capabilities tracked by `NotImplementedLedger` rather than by a flag nothing honors; and `iconPath` is pane chrome answered by the panel's own title, not by this type.
  **Approved**: pending
- **Decision**: `contentSecurityPolicy` names only `object-src`, `base-uri`, `form-action`, and `frame-ancestors`, and never touches `script-src`, `style-src`, `img-src`, or `connect-src`.
  **Rationale**: the source's comment explains that a real policy on those four directives would either be permissive theatre (`'unsafe-inline'`) to avoid breaking every extension page, or strict enough to break pages whose own CSP nonce this host's policy cannot know about; the four directives that are named are the ones "no webview gives up anything by losing," matching how VS Code itself leaves the content policy to the extension's own page.
  **Approved**: pending
- **Decision**: resolving `localResourceRoots` into a candidate list (this type's job) is kept separate from enforcing that a requested resource actually stays inside those roots (a different file's job, `WebviewResourceURL`/`ExtensionResourcePath`).
  **Rationale**: the source's own comment on `declaredLocalResourceRoots` states this plainly — resolving roots into the containment boundary needs the owning extension's directory, "which no struct here knows" — so this type only computes the candidate list, and the escape/containment check happens downstream, at request time, in a component that does have that context.
  **Approved**: pending
- **Decision**: two initializers exist — an as-declared one that derives `enableForms`'s default from `enableScripts`, and a resolved-form one (used by `Decodable` and by tests) that assigns all three values straight through with no derivation.
  **Rationale**: the source's comment on the resolved-form initializer states the reason directly: "a restored panel must come back with the answer the panel actually had," so decoding routes through straight assignment rather than back through the as-declared initializer's derivation, which would silently re-derive a stored `enableForms` from a possibly different `enableScripts` if it were ever fed already-resolved values instead of raw ones.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [content-security-policy](agenticdevelopercookbook://compliance/security#content-security-policy) | passed | Security |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | partial | Security |

`separation-of-concerns` passes because the file does exactly two jobs and nothing else: resolving an extension's declared options into stored values, and deriving a root list and a policy string from them — it parses no manifest, performs no navigation decision, and applies no policy to a running `WKWebView` itself (`scripts-default-false`, `resource-roots-default`, `content-security-policy-floor`). `unit-test-coverage` is partial: `WebviewPanelOptionsTests.swift` thoroughly exercises the as-declared initializer's defaulting rules, `resourceRoots`'s default/override/empty/deduplication behavior, and the CSP floor and `form-action` logic (wpo-001 through wpo-011), but no test in the suite exercises the resolved-form initializer, `Encodable`, or `Decodable` directly (wpo-014 through wpo-018 are traced to the source rather than to an existing test). `content-security-policy` passes: this file is precisely the component that defines and enforces the strict policy floor every panel's webview is served under, adjusted only by the one dimension (`enableForms`) an extension's own declared options control (`content-security-policy-floor`, `content-security-policy-form-action`). `explicit-error-handling` passes: the only optional-unwrapping paths in the file (`??` in the as-declared initializer, `decodeIfPresent ?? …` in `init(from:)`) each resolve to a defined, documented value rather than a silent no-op, and the one path that can actually throw — `Decodable`'s own type-mismatch failure — propagates untouched rather than being caught and discarded (`scripts-default-false`, `decode-missing-forms-follows-decoded-scripts`). `input-sanitization` is partial: `declaredLocalResourceRoots` is extension-author-supplied data that this file stores and passes through `resourceRoots` without validating that any entry is a legitimate file URL or stays inside the extension's own directory; the source's own doc comment states this is deliberate, because the actual containment check happens downstream in `WebviewResourceURL`/`ExtensionResourcePath` once the extension's own directory is known — a documented, correctly-layered deferral rather than an omission, but this file's own contract performs none of that validation itself.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
