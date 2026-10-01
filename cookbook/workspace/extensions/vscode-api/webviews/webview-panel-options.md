---
id: 66759d9a-3884-42e1-acd9-5bad563e1e52
title: Webview Panel Options
domain: agentictoolkit://cookbook/workspace/extensions/vscode-api/webviews/webview-panel-options
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
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
- agentictoolkit://cookbook/workspace/extensions/vscode-api/webviews/webview-panel-view
- agentictoolkit://cookbook/workspace/extensions/manifest/extension-resource-path
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

# Webview Panel Options

## Overview

This component is what `vscode.window.createWebviewPanel`'s `WebviewOptions` argument amounts to once this host's defaults are applied. Upstream's `WebviewOptions` has eight fields; this component carries three — `enableScripts`, `enableForms`, `declaredLocalResourceRoots` — and, per its own documentation, each of the other five is missing for its own distinct reason rather than a shared "not yet": `retainContextWhenHidden` is already permanently true of every pane this host hosts, `enableFindWidget` names a widget that does not exist, `enableCommandUris` and `portMapping` are real, unbuilt capabilities recorded elsewhere (in the shared not-implemented ledger, by the webviews bridge adaptor) rather than carried here as an inert flag, and `iconPath` is answered by the pane's own title rather than by this component.

This component is an immutable value type with no side effects of its own beyond one read-only file-system consultation. It is constructed twice, through two different construction paths with two different jobs: constructing it from as-declared values turns what an extension actually wrote — including three possible states of "absent" — into resolved values, while constructing it from already-resolved values (used both directly and when decoding it) assigns already-resolved values straight through, because a restored panel (the pane-state persistence layer, which stores a copy of this component's value verbatim in the app's pane-state store) must come back with the answer the panel actually had, not a value re-derived from it. Beyond storage, this component does two things a caller relies on: resolving local resource roots turns the declared-or-default root list into the deduplicated list of directories a panel's scheme handler may read from, and building the Content-Security-Policy string composes the floor CSP string every panel's webview is served under, adjusted only by whether forms are enabled. The webview object's `options` property is the one place a webview *view* provider can turn scripts on after the fact — its panel is handed to it already built — and the panel view's own handling of an `options` change is what re-applies a changed value, by re-assigning the scheme handler's policy and reloading the host document; that re-application is a different component's contract (see `agentictoolkit://cookbook/workspace/extensions/vscode-api/webviews/webview-panel-view`) and is only described here as the reason this component itself needs no mutable state of its own.

## Behavioral Requirements

- **type-declaration**: This component MUST have exactly three fields: `enableScripts` (a boolean), `enableForms` (a boolean), and `declaredLocalResourceRoots` (an optional list of resource-root locations).
- **upstream-field-reduction**: This component MUST expose only `enableScripts`, `enableForms`, and `declaredLocalResourceRoots`, and MUST NOT expose any field or computed value named `retainContextWhenHidden`, `enableFindWidget`, `enableCommandUris`, `portMapping`, or `iconPath`.
- **scripts-default-false**: Constructing this component from as-declared values MUST set `enableScripts` to `false` when its `enableScripts` argument is absent, and to that argument's value otherwise.
- **forms-follow-scripts-default**: Constructing this component from as-declared values MUST set `enableForms` to the just-resolved `enableScripts` value when its `enableForms` argument is absent.
- **forms-explicit-overrides-default**: Constructing this component from as-declared values MUST set `enableForms` to its `enableForms` argument's value, independent of `enableScripts`, whenever that argument is present.
- **roots-declaration-preserved**: Constructing this component from as-declared values MUST store its `localResourceRoots` argument into `declaredLocalResourceRoots` unchanged: an absent argument MUST remain absent and an empty-list argument MUST remain an empty list, with neither coerced into the other.
- **resolved-initializer-no-derivation**: Constructing this component from already-resolved values MUST assign each of its three arguments directly to the like-named field and MUST NOT perform the defaulting derivation the as-declared construction path performs.
- **serialization-keys**: Decoding and encoding this component MUST use exactly three keys — `enableScripts`, `enableForms`, `localResourceRoots` — and no others.
- **decode-missing-scripts-as-false**: Decoding this component MUST decode `enableScripts` as `false` when the source data has no `enableScripts` key.
- **decode-missing-forms-follows-decoded-scripts**: Decoding this component MUST decode `enableForms` as the value it just decoded for `enableScripts` when the source data has no `enableForms` key.
- **decode-roots-as-paths**: Decoding this component MUST decode `localResourceRoots` as an optional list of plain path strings and construct `declaredLocalResourceRoots` by converting each string to a file location; it MUST NOT decode the roots through a file-location type's own built-in decoding logic.
- **encode-roots-as-paths**: Encoding this component MUST encode `declaredLocalResourceRoots`, when present, as a list of each location's path string under the `localResourceRoots` key, and MUST omit the `localResourceRoots` key entirely when `declaredLocalResourceRoots` is absent.
- **resource-roots-default**: Resolving local resource roots MUST return the deduplicated concatenation of the extension directory followed by the workspace roots, in that order, whenever `declaredLocalResourceRoots` is absent.
- **resource-roots-declared-replaces-default**: Resolving local resource roots MUST return the deduplicated `declaredLocalResourceRoots` value, ignoring both the extension directory and the workspace roots entirely, whenever `declaredLocalResourceRoots` is present — including when it is an empty list.
- **resource-roots-deduplication**: Resolving local resource roots MUST drop every later root whose canonical directory matches a root already kept, preserving the order and the spelling of each distinct directory's first occurrence.
- **resource-roots-filesystem-read**: Resolving local resource roots MUST consult the file system, through canonical-directory symlink resolution, to compare candidate roots canonically, but MUST NOT create, delete, or write to any file or directory.
- **content-security-policy-computed**: The Content-Security-Policy value MUST be built from the resolved `enableForms` value stored on this component, never a raw, possibly-absent construction argument.
- **content-security-policy-floor**: Building the Content-Security-Policy string MUST always include the directives `object-src 'none'`, `base-uri 'none'`, and `frame-ancestors 'none'`, regardless of whether forms are allowed.
- **content-security-policy-form-action**: Building the Content-Security-Policy string MUST include `form-action 'none'` when forms are not allowed, and MUST include no `form-action` directive at all when forms are allowed.
- **content-security-policy-directive-order**: Building the Content-Security-Policy string MUST join its directives with the separator `"; "` in the fixed order `object-src`, `base-uri`, `form-action` (present only when forms are not allowed), `frame-ancestors`.
- **value-semantics**: Two instances of this component MUST compare equal if and only if their `enableScripts`, `enableForms`, and `declaredLocalResourceRoots` are each equal.
- **safe-for-concurrent-access**: Because this component holds no mutable stored state reachable from more than one call, every instance and every operation on it MUST be safe to invoke concurrently, from any execution context, without additional synchronization.

## Appearance

Not applicable — this is a data model and policy-derivation utility for webview creation options, not a visual component.

## States

Not applicable — this is a data model and policy-derivation utility for webview creation options, not a visual component.

## Accessibility

Not applicable — this is a data model and policy-derivation utility for webview creation options, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| wpo-001 | scripts-default-false | Construct from as-declared values with `enableScripts` absent, `enableForms` absent, `localResourceRoots` absent, vs. the same with `enableScripts` present as `true` | first resolves `enableScripts` to `false`; second resolves `enableScripts` to `true` |
| wpo-002 | forms-follow-scripts-default | Construct from as-declared values with `enableScripts: true, enableForms` absent, vs. `enableScripts: false, enableForms` absent | first resolves `enableForms` to `true`; second resolves `enableForms` to `false` |
| wpo-003 | forms-explicit-overrides-default | Construct from as-declared values with `enableScripts: false, enableForms: true`, vs. `enableScripts: true, enableForms: false` | first resolves `enableForms` to `true`; second resolves `enableForms` to `false` |
| wpo-004 | resource-roots-default | Resolve local resource roots with workspace roots `[workspace, secondWorkspace]` and `localResourceRoots` absent | returns 3 roots; the first equals the extension directory; the list contains `workspace` |
| wpo-005 | resource-roots-declared-replaces-default, roots-declaration-preserved | Resolve local resource roots with workspace roots `[secondWorkspace]` and `localResourceRoots: [workspace]` | returns exactly `[workspace]`; the extension directory and `secondWorkspace` are absent |
| wpo-006 | resource-roots-declared-replaces-default, roots-declaration-preserved | Same call with `localResourceRoots: []` | returns an empty list, not the default extension-directory-plus-workspace list |
| wpo-007 | resource-roots-deduplication | Resolve local resource roots with workspace roots `[workspace, workspace, extensionDirectory]`, `localResourceRoots` absent | returns 2 entries; the first is the extension directory |
| wpo-008 | resource-roots-deduplication, resource-roots-filesystem-read | `localResourceRoots` holding four differently-spelled paths to the same directory (a trailing slash, a `/./` suffix, and a `Sources` component followed by `..`) | resolving local resource roots returns exactly 1 entry |
| wpo-009 | content-security-policy-floor | Build the Content-Security-Policy string allowing forms, and again disallowing forms | both contain `object-src 'none'`, `base-uri 'none'`, and `frame-ancestors 'none'` |
| wpo-010 | content-security-policy-form-action | Build the Content-Security-Policy string disallowing forms, vs. allowing forms | first contains `form-action 'none'`; second contains no `form-action` directive |
| wpo-011 | content-security-policy-computed | The Content-Security-Policy value of a component constructed from as-declared values with `enableScripts: true, enableForms` absent, `localResourceRoots` absent | contains no `form-action` directive, because the resolved `enableForms` (`true`, following scripts) drove the policy, not the raw absent argument |
| wpo-012 | content-security-policy-directive-order | Build the Content-Security-Policy string disallowing forms | equals exactly the string `object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'` |
| wpo-013 | type-declaration, value-semantics | Two instances of this component built with identical `enableScripts`, `enableForms`, and `declaredLocalResourceRoots` arguments | compare equal; changing any one of the three arguments makes the comparison false |
| wpo-014 | serialization-keys, decode-missing-scripts-as-false, decode-missing-forms-follows-decoded-scripts | Decode this component from an empty object `{}` | resolves `enableScripts` to `false`, `enableForms` to `false`, `declaredLocalResourceRoots` to absent |
| wpo-015 | decode-roots-as-paths | Decode `{"enableScripts": true, "enableForms": true, "localResourceRoots": ["/a/b", "/c/d"]}` | `declaredLocalResourceRoots` equals the two file locations `/a/b` and `/c/d` |
| wpo-016 | encode-roots-as-paths | Encode a value with `declaredLocalResourceRoots` holding the file location `/a/b`, then decode the resulting data back | the encoded `localResourceRoots` array holds the plain string `"/a/b"`, not a nested structure; decoding it back round-trips to an equal value |
| wpo-017 | encode-roots-as-paths | Encode a value with `declaredLocalResourceRoots` absent | the resulting encoded data has no `localResourceRoots` key |
| wpo-018 | resolved-initializer-no-derivation | Construct from already-resolved values with `enableScripts: false, enableForms: true, declaredLocalResourceRoots` absent | `enableForms` resolves to `true` even though `enableScripts` is `false` — no scripts-follow derivation runs |
| wpo-019 | upstream-field-reduction, type-declaration | Inspect this component's fields | exactly `enableScripts`, `enableForms`, `declaredLocalResourceRoots` (`localResourceRoots` on the wire) appear; no field named `retainContextWhenHidden`, `enableFindWidget`, `enableCommandUris`, `portMapping`, or `iconPath` appears anywhere |
| wpo-020 | safe-for-concurrent-access | Resolve local resource roots and read the Content-Security-Policy value concurrently from many independent callers against the same instance | every call completes with the result its own inputs imply; no crash and no data race occurs |
| wpo-021 | resource-roots-filesystem-read | Resolve local resource roots against a scratch directory, then enumerate that directory's contents before and after the call | the directory's entries are unchanged — no file or folder is created, deleted, or modified |
| wpo-022 | roots-declaration-preserved | Construct from as-declared values and inspect the stored `declaredLocalResourceRoots` | passing absent yields a stored value of absent; passing an empty list yields a stored value of an empty list — the two are never coalesced |

## Edge Cases

- **Null input on every option**: constructing this component from as-declared values with every argument absent is the fully-absent case; it resolves to the safest posture — scripts off, forms off, and the default two-root list (extension directory plus every open workspace folder) once local resource roots are resolved. MUST.
- **Empty-list roots versus absent roots**: an empty declared-roots list is not the same input as an absent one — the empty list is honored as "no file access at all," while absent takes the extension-directory-plus-workspace default. Collapsing the two is the exact hazard the source's own documentation names: a panel that deliberately renounced file access must not be handed the whole workspace. MUST.
- **Boundary — extension directory duplicated in workspace roots**: when the default root list's two sources overlap (an open workspace folder that canonicalizes to the same directory as the extension directory), resolving local resource roots keeps only the first occurrence — the extension directory — and drops the duplicate workspace entry, per **resource-roots-deduplication**. MUST.
- **Concurrent access**: this component holds no mutable stored state — every field is fixed once constructed, and its own operations read only their arguments and its own fields. Calling any of them concurrently, from any execution context, against the same or different values requires no synchronization. MUST.
- **Error states**: this component defines no error path of its own beyond decoding's own failure when a present key's data cannot be decoded as its declared type (for example a non-boolean `enableScripts`); that error propagates untouched — nothing in this component catches or discards it. Stated as fact, per the absent-feature rule: the source defines no other error condition. MUST.
- **Offline / disconnected state**: not applicable. This component performs no networking; its only I/O is the local, read-only symlink resolution that resolving local resource roots performs through canonical-directory resolution, which has no connectivity state to lose.
- **Cancellation and timeout**: resolving local resource roots and building the Content-Security-Policy string define no timeout and no cancellation, because both are synchronous calls; a slow or unresponsive mount underneath a declared root blocks the caller for as long as symlink resolution takes, with no escape hatch defined in this component. Stated as fact, per the absent-feature rule — not a marker, since nothing in a synchronous options component's purpose calls for one.
- **A declared root that does not exist on disk**: resolving local resource roots performs no existence check on any declared or default root before canonicalizing it for deduplication; a root naming a directory that has since been deleted or was never created is passed through canonical-directory resolution (whose symlink resolution is a no-op on a path that does not resolve to anything) and returned to the caller unchanged. This is a fact about the collaborator this component delegates canonicalization to, not a gap in this component's own contract.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enableScripts` | a boolean (optional) | absent (resolves to `false`) | The option as the extension wrote it, passed when constructing this component from as-declared values; absent means the option was absent. |
| `enableForms` | a boolean (optional) | absent (resolves to the resolved `enableScripts` value) | The option as the extension wrote it; absent means the option was absent and follows `enableScripts`. |
| `localResourceRoots` | a list of file locations (optional) | absent (resolves to the extension directory plus the workspace roots once local resource roots are resolved) | The option as the extension wrote it; absent means absent, an empty list means an explicit, honored declaration of no file access. |
| `extensionDirectory` | a file location | none (required) | The owning extension's install directory, given when resolving local resource roots; the first element of the default root list when `declaredLocalResourceRoots` is absent. |
| `workspaceRoots` | a list of file locations | none (required; empty when no project is open) | Every open workspace folder, given when resolving local resource roots; appended after the extension directory in the default root list. |
| `allowingForms` | a boolean | none (required) | Given when building the Content-Security-Policy string; in practice always the resolved `enableForms` of the instance asking for a policy. |

There are no environment variables or settings keys involved: every input arrives as a plain argument, or — for the decoding path — as one of the three wire keys read from whatever data the caller (the pane-state persistence layer, via the app's own pane-state store) hands the decoder.

## Deep Linking

Not applicable: this component resolves options and composes an in-memory policy string; it defines no URL scheme, route, or navigable destination.

## Localization

Not applicable: this component produces no user-facing string. Its one string output, the Content-Security-Policy value, is a header value that the panel's resource scheme handler and webview consume as protocol data, never text rendered for a person to read.

## Accessibility Options

Not applicable: this component has no visual or interactive surface for a system accessibility display option to affect.

## Feature Flags

Not applicable: this component defines no feature flag, build configuration check, or remote-config lookup; every operation's output is fixed entirely by the arguments it is called with.

## Analytics

Not applicable: this component emits no analytics event; it returns a list of file locations, a string, or a decoded/encoded value to its caller and performs no telemetry of its own. (An extension's use of the two unbuilt fields this component excludes, `enableCommandUris` and `portMapping`, is recorded by the shared not-implemented ledger — but that recording happens in the webviews bridge adaptor, a different component, before a value of this component is ever constructed.)

## Privacy

- **Data collected**: none in the device- or user-identifying telemetry sense. However, `declaredLocalResourceRoots`, and every location that resolving local resource roots returns, are absolute local file-system paths; when the default (undeclared) root list is used, those paths necessarily embed wherever the extension directory and each workspace folder happen to live on the local machine, which can include the local account's home-directory name.
- **Storage**: none performed by this component itself — it writes to no file and no database. Its serialization support exists so that a caller, specifically the pane-state persistence layer, can persist a value of this component verbatim into the app's own pane-state store as part of restoring a panel after a quit; this component never performs that write itself.
- **Transmission**: none — this component performs no networking of its own.
- **Retention**: for as long as the caller (or, downstream, the pane-state store a persisted value is written into) retains it; this component itself retains nothing once a call returns.

## Logging

Not applicable: this component contains no logging call; there is nothing for it to log, since it defines no error case of its own and every value it produces is returned directly to its caller.

## Platform Notes

- **SwiftUI**: the source (`WebviewPanelOptions.swift`) is plain Foundation (`URL`, `Codable`) with zero dependency on SwiftUI or any view-layer framework. It lives in `AgenticToolkitCore`, the tier every macOS extension-host feature (`WebviewPanelViewController`, `MainThreadWebviews`, `ExtensionHostInstaller`, `ExtensionsCoordinator`, `WebviewPanelState`) reaches down into. A port that keeps this component in Swift needs nothing beyond `Foundation`. `WebviewPanelOptions` is a `public struct` conforming to `Codable`, `Equatable`, and `Sendable`, with exactly the three stored properties named above (`enableScripts: Bool`, `enableForms: Bool`, `declaredLocalResourceRoots: [URL]?`); "constructing this component from as-declared values" above is `init(enableScripts:enableForms:localResourceRoots:)`, and "constructing this component from already-resolved values" is `init(enableScripts:enableForms:declaredLocalResourceRoots:)`, also used by `Decodable`'s own `init(from:)`. "Resolving local resource roots" is `resourceRoots(extensionDirectory:workspaceRoots:)`; its "canonical directory" comparison is `ExtensionResourcePath.canonicalDirectory(_:).path`, applied inside a `deduplicated` helper. "Building the Content-Security-Policy string" is the static `contentSecurityPolicy(allowingForms:)`, and the computed `contentSecurityPolicy` property is what calls it with `self`'s own resolved `enableForms`. The serialization keys above are `CodingKeys` — `enableScripts`, `enableForms`, `localResourceRoots` — decoded/encoded via `decodeIfPresent`/`encodeIfPresent`, with roots decoded as `[String]` and mapped through `URL(fileURLWithPath:)` rather than through `URL`'s own `Codable` conformance. "Safe for concurrent access" above follows from the type's explicit `Sendable` conformance and its having no mutable stored state (every stored property is a `let`). "The shared not-implemented ledger" and "the webviews bridge adaptor" above are `NotImplementedLedger` and `MainThreadWebviews`; "the webview object's `options` property" is `ExtensionWebviewPanel.options` (in `ExtensionWebviewPresenting.swift`), and "the panel view's own handling of an `options` change" is `WebviewPanelViewController.options`'s `didSet`, which re-assigns the scheme handler's `contentSecurityPolicy` and reloads the host document.
- **Compose**: model `WebviewPanelOptions` as a Kotlin `data class` with three `val` properties, giving structural equality and immutability for free in place of the hand-written `Equatable`. Serialize with `kotlinx.serialization`'s `@Serializable`, using a custom `Serializer` (or `@Serializable(with = ...)`) to reproduce the two `decodeIfPresent`-style defaulting rules, since `kotlinx.serialization` treats a missing key as a compile-time-declared default rather than a runtime fallback chained off a sibling field's just-decoded value. Compose the CSP string with a plain `buildString`/`joinToString` in the same fixed directive order.
- **React/Web**: model the type as a plain TypeScript interface (or a small class) mirroring upstream's own `vscode.WebviewOptions` shape, reduced to the same three fields; the defaulting logic (`enableForms` following `enableScripts`, `nil` and `[]` roots meaning different things) has to be hand-written the same way the source hand-writes it, since TypeScript's structural typing gives no default-value mechanism of its own. Compose the CSP string with `Array.prototype.join('; ')` over the same fixed directive order, and, in a browser or Electron host, apply it via a `Content-Security-Policy` response header or `<meta http-equiv="Content-Security-Policy">` tag rather than a native webview configuration object.
- **AppKit / UIKit**: identical to the SwiftUI note — the component depends on neither AppKit nor UIKit, so a macOS host consumes the same `AgenticToolkitCore` type directly with no translation needed. (No iOS target exists for this component today; every current caller is under `packages/apple/AgenticToolkit/macOS/`.)
- **WinUI 3**: there is no single .NET or Windows App SDK type that reproduces this three-field, dual-initializer shape; model it as a C# `record` (`enableScripts`/`enableForms`/`declaredLocalResourceRoots`, the latter an `IReadOnlyList<string>?`) with a static factory reproducing the `enableForms`-follows-`enableScripts` default and the `null`-versus-empty-list distinction for roots, plus `System.Text.Json`'s `JsonConverter<T>` for the same two-key-defaulting decode `WebviewPanelOptions.init(from:)` performs — `System.Text.Json`'s own missing-property handling only supports a compile-time-fixed default, not one derived from a sibling property at decode time. There is no `Microsoft.Web.WebView2.Core` equivalent of a per-navigation, editable Content-Security-Policy the way this source's `WKWebViewConfiguration`-independent CSP string is; `CoreWebView2.WebResourceRequested` (adding a `Content-Security-Policy` response header) or a `CoreWebView2Settings.IsScriptEnabled` toggle at initialization are the closest WebView2 primitives, and unlike this source's re-appliable `options` property, `CoreWebView2Settings.IsScriptEnabled` cannot be changed after the first navigation without a full reload, mirroring this source's own reload-on-change design (see `agentictoolkit://cookbook/workspace/extensions/vscode-api/webviews/webview-panel-view`) rather than avoiding it. Resource-root containment has no WebView2 equivalent either; `SetVirtualHostNameToFolderMapping` maps a single folder to a virtual host and would need to be called once per declared root. `HttpClient`, `Task`/`async`, `ObservableCollection`, and `INotifyPropertyChanged` play no role here: every operation in the source is synchronous, non-networked, and returns a value rather than raising a change notification.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/Extensions/WebviewPanelOptions.swift` |

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/vscode-api/webviews/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
