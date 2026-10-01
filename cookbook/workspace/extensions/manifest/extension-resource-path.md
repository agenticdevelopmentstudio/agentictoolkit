---
id: f6acc431-0443-4b14-8ae4-e1f2dc227c0c
title: Extension Resource Path
domain: agentictoolkit://cookbook/workspace/extensions/manifest/extension-resource-path
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Resolves an extension-declared path against its own directory, refusing any
  escape, and derives where user-installed extensions and plugins live.
platforms:
- swift
- macos
tags:
- extension-host
- path-safety
- containment
- installed-content-location
depends-on: []
related:
- agentictoolkit://cookbook/workspace/extensions/manifest/extension-identity-component
- agentictoolkit://cookbook/workspace/extensions/manifest/extension-manifest
- agentictoolkit://cookbook/ai/plugins/plugin-manager
references:
- packages/apple/AgenticToolkit/Core/Extensions/ExtensionResourcePath.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Extensions/ExtensionResourcePathTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/ThemeContributionPoint.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/Host/ExtensionHost.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/Host/ExtensionHostInstaller.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Theme/VSCodeThemeImporter.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Language/Snippets/SnippetStore.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/AIPluginManager.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/VSIXInstaller.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/WebviewResourceURL.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/WebviewPanelOptions.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Extension Resource Path

## Overview

This component is the single containment check this framework uses for
every path a third-party VS Code-compatible extension declares against a
location inside its own installed directory. Before this component
existed, per its own header comment, the same rule was hand-rolled at four
call sites — a theme contribution's `path`, a theme's own `include`, a
snippet contribution's `path`, and the extension host's `browser` entry
point — and three of the four were missing the escape half of the check,
so the same `../../../.ssh/config` traversal could read arbitrary files
through any of them. A typed escape error is the one failure resolving a
path can raise, carrying both the string the extension declared and the
absolute path it actually resolved to, so a rejection is checkable rather
than a bare boolean. The installed-content-location helper is a second,
narrower concern that happens to live alongside this one: it derives the
two conventions this project's hosts use for user-installed add-ons dropped
beside the app rather than inside it — a per-app Application Support
subdirectory, and a hand-filled home dotfolder — replacing what the plugin
manager's initializer and the app's own extension host had each hand-rolled
and let drift out of step. Every production caller today — a theme-import
loop, a snippet-loading loop, a theme importer's root resolution, the
extension host's entry-point resolution, the extension host installer's
entry-point signature check, and the plugin manager's initializer —
resolves or composes its path through this one component rather than
re-deriving the rule.

## Behavioral Requirements

- **error-case**: a typed escape error MUST be a comparable value type with
  exactly one case: an escape failure carrying the exact string the caller
  declared and the exact resolved destination path.
- **error-message**: the escape error MUST provide a human-readable
  description that names both the exact string the caller declared and the
  exact resolved destination path, in the form "The path (declared, in
  curly quotes) resolves to (resolved), which is outside the extension's
  own directory."
- **single-base-resolve**: resolving a path against a single directory
  MUST resolve `declared` against `directory` and require the result be
  contained within that same `directory`, by delegating to the
  two-directory resolve operation with `directory` supplied as both the
  base and the root.
- **candidate-construction**: the two-directory resolve operation MUST
  build its candidate location by constructing a file path from `declared`
  relative to the canonicalized base directory, then applying symlink
  resolution followed by path standardization, in that order.
- **escape-refusal**: the two-directory resolve operation MUST fail with
  the escape error when the constructed candidate is not contained in the
  canonicalized root directory, and MUST return the candidate unchanged
  when it is.
- **error-payload-fidelity**: the escape error's declared value MUST be
  exactly the string the caller passed in, unmodified by trimming or
  normalization, and its resolved value MUST be the fully canonicalized
  candidate's path string.
- **directory-flag-forcing**: canonicalizing a directory MUST re-derive
  its argument as a location explicitly marked as a directory before
  resolving symlinks and standardizing, so that a location carrying no
  directory marking is still treated as a directory rather than resolved
  against its parent.
- **symmetric-canonicalization**: both the base (or root) side and the
  candidate side of a containment decision MUST be produced by resolving
  symlinks and then standardizing, so that a directory reached through a
  symlink compares equal to the same directory reached directly.
- **child-of-nonexistent-parent**: deriving a not-yet-existing child
  location MUST canonicalize only the parent directory (which is assumed
  to exist), then append the child name and standardize the result; it
  MUST NOT canonicalize the combined, not-yet-existing path as a whole.
- **containment-strictness**: the containment check MUST return true if
  and only if the candidate's path-component count is strictly greater
  than the base's, and the leading path components of the candidate — as
  many as the base has — equal the base's path components exactly, element
  by element; a directory MUST NOT be considered contained in itself.
- **component-wise-comparison**: the containment check MUST compare path
  components, and MUST NOT treat the base's path as a string prefix of the
  candidate's path, so that a sibling directory whose name merely starts
  with the base's name (for example a directory named with the base's name
  plus `-evil` appended) is never mistaken for a descendant.
- **containment-inputs-uncanonicalized**: the containment check MUST NOT
  itself resolve symlinks or standardize either argument; it MUST operate
  only on whichever path components its two location arguments already
  carry, leaving canonicalization to the caller.
- **application-support-composition**: composing the application-support
  location for an app MUST return the user domain's Application Support
  directory with the app's name appended and then the subdirectory name
  appended, in that order, and MUST return absent when the user domain has
  no Application Support directory to report.
- **home-dot-directory-composition**: composing the home dotfolder
  location MUST return the home directory with one additional path
  component consisting of a literal `.` immediately followed by the
  folder's name.
- **home-directory-default**: the home dotfolder composition's
  home-directory parameter MUST default to the process's own home
  directory when the caller supplies no override.
- **stateless-synchronous-operation**: every operation in this component
  and the installed-content-location helper MUST be a synchronous function
  or a computed value operating only on its arguments; neither exposes any
  stored state, and neither can be instantiated, so neither can carry
  state between calls.
- **safe-across-any-concurrency-domain**: none of this component, the
  installed-content-location helper, or the escape error requires
  exclusive access to a particular thread or task. Because every value
  used here (a string, a location, a boolean) is itself safe to share
  across concurrency boundaries, and none of the three holds mutable
  stored state reachable from more than one call, every operation MUST be
  safe to invoke from any concurrency domain, concurrently, without
  additional synchronization.
- **filesystem-side-effects**: resolving a path against a single
  directory, the two-directory resolve operation, and canonicalizing a
  directory MUST consult the file system (through symlink resolution) to
  canonicalize a path, but no operation in this component MUST create,
  delete, or write to any file or directory.
- **application-support-appname-validation**: composing the
  application-support location performs no check that the app's name is
  non-empty before composing the path. This is a stated caller
  precondition — an empty component "collapses the path onto the shared
  Application Support/subdirectory and silently widens the search to
  every app's content of that kind" — and callers are expected to derive
  the name through something that cannot answer an empty string; today the
  only caller always supplies a non-empty display name.

## Appearance

Not applicable — this is a path-resolution and location-derivation utility,
not a visual component.

## States

Not applicable — this is a path-resolution and location-derivation utility,
not a visual component.

## Accessibility

Not applicable — this is a path-resolution and location-derivation utility,
not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| erp-001 | single-base-resolve, candidate-construction | Resolving `"./themes/dark.json"` inside a directory | resolves to the canonical `directory/themes/dark.json` location |
| erp-002 | candidate-construction | Resolving `"snippets/x.code-snippets"` inside a directory (no leading `./`) | resolves to `directory/snippets/x.code-snippets`; a leading `./` is not required |
| erp-003 | directory-flag-forcing | Resolving `"./themes/dark.json"` inside a directory location carrying no directory marking | resolves inside the directory, not beside it |
| erp-004 | escape-refusal, error-payload-fidelity | Resolving `"../outside/secret.json"` inside an extension directory that is a child of a parent directory | fails with the escape error, declared `"../outside/secret.json"`, resolved to the parent directory's `outside/secret.json` canonical path |
| erp-005 | error-message | The description of an escape error with declared `"../x.json"`, resolved `"/tmp/x.json"` | the description contains both `"../x.json"` and `"/tmp/x.json"` |
| erp-006 | single-base-resolve, escape-refusal | Resolving `"../base.json"` relative to a themes directory, contained in a root directory, then resolving `"../../base.json"` the same way | the first resolves to `root/base.json`; the second fails with the escape error |
| erp-007 | component-wise-comparison, containment-inputs-uncanonicalized | The containment check on a candidate whose directory name is the base's name with `-evil` appended | returns false even though the candidate's path string has the base's path as a literal string prefix |
| erp-008 | containment-strictness, containment-inputs-uncanonicalized | The containment check on a base directory checked against itself | returns false |
| erp-009 | containment-strictness, containment-inputs-uncanonicalized | The containment check on a descendant three levels below the base | returns true |
| erp-010 | symmetric-canonicalization | Resolving `"./themes/dark.json"` relative to a symlink pointing at a real directory, contained in that real directory | resolves to `realDirectory/themes/dark.json`, treating the symlinked and real directories as equal |
| erp-011 | escape-refusal, symmetric-canonicalization | Resolving `"./escape/secret.json"` inside a directory whose `escape` entry is a symlink pointing to a sibling directory outside it | fails with the escape error, even though the declared string itself contains no `..` |
| erp-012 | application-support-composition | Composing the application-support location for app name `"Coffee Grinder"`, subdirectory `"Extensions"` | the result's last three path components, in order, are `"Application Support"`, `"Coffee Grinder"`, `"Extensions"` |
| erp-013 | application-support-composition | Composing the application-support location for the same app with subdirectory `"Plugins"` versus `"Extensions"` | both results share the same parent directory |
| erp-014 | home-dot-directory-composition | Composing the home dotfolder location for `"agenticextensions"` and `"agenticplugins"`, given the same fixture home directory | results equal the fixture home directory appended with `.agenticextensions` and `.agenticplugins` respectively |
| erp-015 | home-directory-default | Composing the home dotfolder location for `"agenticextensions"` with an explicit fixture home directory, compared with the same call using the default home directory | the two results differ, and the default result's parent path equals the process's real home directory |
| erp-016 | filesystem-side-effects | Resolving a path inside a scratch directory, enumerating the directory's contents before and after the call | the directory's entries are unchanged; no file or folder is created, deleted, or modified by the call |
| erp-017 | safe-across-any-concurrency-domain, stateless-synchronous-operation | Resolving a path against a single directory, invoked concurrently from many independent callers against the same directory with different declared strings | every call completes with the result its own input implies, with no crash and no shared-state corruption |
| erp-018 | application-support-composition | Composing the application-support location on a host where the user domain reports no Application Support directory | returns absent |

## Edge Cases

- **Null/empty declared path — the directory itself**: a declared value of
  `"."` resolves, before the containment check, to the directory itself;
  the containment check then refuses it because the directory is not
  strictly below itself, so resolving the path fails with the escape error
  rather than handing a caller the directory to open as if it were a file.
  This is the exact case the containment check's own design guards
  against. MUST.
- **Boundary — exactly at the root versus one hop beyond it**: a declared
  path that climbs exactly to `root` (for example `"../base.json"` from a
  `themes/` folder one level below `root`) resolves and succeeds; the same
  path climbing one directory further (`"../../base.json"`) fails with the
  escape error. The boundary is the root directory itself, inclusive on the
  "still inside" side only in the sense that any path strictly below
  `root` succeeds. MUST.
- **Symlink escape with no literal `..` in the declared string**: a
  declared path containing no `..` at all can still escape if a symlink
  planted inside the extension's own directory points outside it; symlink
  resolution on the candidate resolves that symlink to its real target
  before the containment check runs, so the escape is caught even though
  nothing about the declared string itself was suspicious. MUST.
- **Concurrent access**: this component, the escape error, and the
  installed-content-location helper hold no mutable stored state — every
  entry point is a pure function over its arguments — so calling any of
  them concurrently, from any thread or concurrency domain, against the
  same or different directories, requires no synchronization. MUST.
- **Error states**: the only defined failure is the escape error, raised
  once, synchronously, by the resolve operation. Composing the
  application-support location communicates its one "nothing to name" case
  by returning absent, never by failing outright; a caller that ignores an
  absent result (no production caller does today) silently proceeds with
  one fewer search path rather than crashing. Stated as fact, not a
  marker — this component defines no other error condition.
- **Offline / disconnected state**: not applicable. Every operation reads
  only the local file system's symlink structure; there is no networking
  and therefore no connectivity state to lose mid-operation.
- **Cancellation and timeout**: the resolve operation, canonicalizing a
  directory, and deriving a not-yet-existing child location define no
  timeout and no cancellation, because every call is synchronous local
  file-system metadata access with no concurrency-deferred entry point. A
  slow or unresponsive mount underneath the directory being resolved blocks
  the caller for as long as symlink resolution takes, with no escape hatch
  defined in this component. Stated as fact, per the absent-feature rule —
  not a marker, since nothing in the purpose of a synchronous path resolver
  calls for one.
- **Unvalidated caller inputs beyond `appName`**: composing the home
  dotfolder location takes the folder's name at face value; the dotless
  convention exists so that "these are hidden folders" is a property of
  this function rather than of each caller's string literal, but the
  function does not verify the name omits a leading dot or a path
  separator — every caller today already passes a plain identifier such as
  `"agenticplugins"`, so this is a fact about the function's contract
  rather than an observed failure.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `declared` | text | none (required) | The path exactly as an extension manifest, theme file, or contribution point spelled it; passed to resolving a path against a single directory, or the two-directory resolve operation. |
| `directory` | a file-system location | none (required) | The extension's own folder, used as both the resolution base and the containment boundary in the single-directory resolve. |
| `base` | a file-system location | none (required) | The directory `declared` is resolved relative to, in the two-directory resolve; may differ from `root` — a theme's `include` is relative to the including file's own folder, not the extension's. |
| `root` | a file-system location | none (required) | The directory the resolved candidate may not leave, in the two-directory resolve. |
| `component` | text | none (required) | The not-yet-existing child name appended to `parent` when deriving a not-yet-existing child location. |
| `parent` | a file-system location | none (required) | The directory, assumed to already exist, that `component` is appended to when deriving a not-yet-existing child location. |
| `appName` | text | none (required) | The app's display name, passed to composing the application-support location; the function's own contract states it must not be empty, though nothing in the function enforces this (see **application-support-appname-validation** above). |
| `subdirectory` | text | none (required) | The content-kind folder name (for example `"Plugins"` or `"Extensions"`) appended under the app's Application Support directory. |
| `name` | text | none (required) | The dotless folder name passed to composing the home dotfolder location (for example `"agenticplugins"` or `"agenticextensions"`); the leading dot is added by the function. |
| `home` | a file-system location | the process's real home directory | The home directory the home-dotfolder composition resolves against; a caller — typically a test — overrides it so that a test run reads its own fixture rather than a real developer's installed content. |

There are no settings keys or dependency-injection containers involved: every
input arrives as a plain function argument. The one indirect environment
dependency is the process's home directory, consulted only when `home` is
left at its default.

## Deep Linking

Not applicable: this component resolves and composes local file-system paths
in memory; it defines no URL scheme, route, or navigable destination.

## Localization

This component produces exactly one user-facing string: the escape error's
description, a hardcoded English sentence with no localization lookup of
any kind — no locale parameter, no externalized string table entry. A
snippet-loading failure's reason and a theme-import failure's message (at
the component's call sites) both store this same English sentence
verbatim, for direct display to an extension author regardless of the
host's system locale.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — not externalized) | The path "declared value" resolves to "resolved value", which is outside the extension's own directory. | The escape error's description, shown to the extension author when a snippet, theme, theme `include`, or entry-point path escapes its extension's own directory. |

## Accessibility Options

Not applicable: this component has no visual or interactive surface for a
system accessibility display option to affect.

## Feature Flags

Not applicable: this component defines no feature flag, build
configuration check, or remote-config lookup; every function's behavior is
fixed entirely by the arguments it is called with.

## Analytics

Not applicable: this component emits no analytics event; it returns a
location, a failure, or absent to its caller and performs no telemetry of
its own.

## Privacy

- **Data collected**: none in the sense of device- or user-identifying
  telemetry. However, the resolved value carried by a thrown escape error,
  and every location the home-dotfolder and application-support location
  factories derive, is an absolute local file-system path that necessarily
  embeds the local account's home-directory name — because both are
  derived from the process's home directory and the user-domain
  Application Support directory.
- **Storage**: none. Every value this component produces is held only in
  the caller's own variables for as long as the caller keeps it; this
  component writes nothing to disk.
- **Transmission**: none performed directly by this component — it does no
  networking. Downstream, a snippet-loading failure's reason and a
  theme-import failure's message carry a resolved path (and the account
  name it embeds) into structures a settings panel may display to the
  extension author; how far that display surface propagates is outside
  this component.
- **Retention**: for the lifetime of whichever value — a location, a
  thrown error, or a search-path list — the caller holds; this component
  itself retains nothing once a call returns.

## Logging

Not applicable: this component contains no logging call and imports no
logging framework; a failure is communicated to its caller exclusively
through the escape error, never written to a log by this component
itself.

## Platform Notes

- **SwiftUI**: the source (`ExtensionResourcePath.swift`) is plain
  Foundation — `URL` and, transitively through `NSHomeDirectory()` and
  `FileManager.default.urls(for:in:)`, `FileManager` — with zero dependency
  on SwiftUI or any view-layer framework. It sits in `AgenticToolkitCore`,
  the tier reachable from both `Language/` (the snippet store) and
  `macOS/` (the theme, host, and plugin-manager call sites).
  `ExtensionResourcePathError` is declared `public enum` conforming to
  `Error`, `Equatable`, and `LocalizedError`; `ExtensionResourcePath` and
  `InstalledContentLocation` are both case-less enums used purely as
  static-function namespaces, with `resolve(_:inside:)` delegating to
  `resolve(_:relativeTo:containedIn:)`, and neither declares a `Sendable`
  conformance or any actor/`@MainActor` isolation — safe by construction
  rather than by explicit annotation, since every parameter and return
  value (`String`, `URL`, `Bool`) is itself `Sendable` and neither type
  holds mutable stored state. A port that keeps this component in Swift
  needs nothing beyond `Foundation`.
- **Compose**: there is no single JVM/Android API that reproduces this
  file's exact resolve-then-contain guarantee out of the box. Model
  `ExtensionResourcePathError` as a Kotlin `sealed class`/`data class` and
  `ExtensionResourcePath` as a Kotlin `object` namespace (the case-less-enum
  equivalent); build the candidate with `java.nio.file.Path.resolve` against
  a `Path.toRealPath()`-canonicalized base. `java.nio.file.Path.startsWith(Path)`
  is already component-aware, unlike a naive string check, so
  `component-wise-comparison` is largely free on this platform — the
  containment test becomes `candidate.startsWith(root) && candidate != root`.
  Compose the plugin/extension search directories from
  `System.getProperty("user.home")` plus a literal dot-prefixed name, and
  `Context.getExternalFilesDir`/`getFilesDir` in place of the Application
  Support directory.
- **React/Web**: for a Node-hosted extension runtime, use
  `path.resolve`/`path.normalize` for the candidate and `fs.realpathSync`
  (or its promise form) to resolve symlinks on both the base and the
  candidate before comparing. Node's `path` module has no built-in
  "is contained in" predicate, so the same component-wise comparison the
  source hand-rolls — never `String.prototype.startsWith`, which reproduces
  the exact sibling-directory bug `component-wise-comparison` guards
  against — has to be hand-rolled again here, typically via
  `path.relative(root, candidate)` checked for neither being absolute nor
  starting with a parent-directory segment. There is no direct Node
  equivalent of `~/Library/Application Support`; the nearest per-OS
  analogues are the platform's own config-directory environment variables,
  commonly wrapped by a small package that already normalizes across
  operating systems.
- **AppKit / UIKit**: identical to the SwiftUI note — the component depends
  on neither AppKit nor UIKit, so a macOS or iOS host consumes the same
  `AgenticToolkitCore` type directly with no translation needed.
- **WinUI 3**: there is no .NET or Windows App SDK type that performs this
  exact resolve-then-contain check. `Path.GetFullPath` alone does not
  resolve symlinks or junctions the way symlink resolution does in the
  source, so a port needs an explicit link-resolution step chained with
  `Path.GetFullPath` before the containment comparison. Compare with
  `Path.GetRelativePath(root, candidate)` and reject a result that is
  rooted or begins with a parent-directory segment, rather than
  `string.StartsWith`, for the same component-versus-string-prefix reason
  `component-wise-comparison` exists for in the source. `InstalledContentLocation`'s
  two locations map to `Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData)`
  (the Application Support analogue) and, for the hand-filled dotfolder, a
  subfolder of `Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)`
  — Windows has no hidden-by-leading-dot convention, so hiding that folder
  needs an explicit hidden-attribute flag rather than relying on a leading
  dot the way macOS does. `HttpClient`, `System.Text.Json`, `Task`/`async`,
  `ObservableCollection`, and `INotifyPropertyChanged` all have no role
  here: every operation in the source is synchronous, non-networked,
  non-serializing, and returns a value rather than raising a change
  notification.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/Extensions/ExtensionResourcePath.swift` |

## Design Decisions

- **Decision**: a single `resolve` function is shared by all four
  extension-declared-path call sites — snippets, a theme's `path`, a
  theme's `include`, and the host's `browser` entry point — rather than
  each contribution point re-deriving its own containment check.
  **Rationale**: the source's own header comment states that three of the
  four call sites were missing the escape half of the check before this
  type existed, each having re-derived the base URL "in its own words,"
  which let the same `../../../.ssh/config` traversal escape through any of
  them except the one that already checked for it.
  **Approved**: pending
- **Decision**: both sides of a containment comparison are canonicalized
  identically — symlinks resolved, then standardized — rather than
  canonicalizing only the untrusted candidate.
  **Rationale**: the source's comment on `canonicalDirectory` gives both
  failure directions concretely: on macOS the temporary directory alone is
  a symlink (`/var` mapping to `/private/var`), so canonicalizing only one
  side would either refuse every legitimate path under a symlinked root or
  accept an escape through a symlink planted inside the extension,
  depending on which side went uncanonicalized.
  **Approved**: pending
- **Decision**: `canonicalChild(_:of:)` canonicalizes only the parent
  directory and appends the component, rather than building the full child
  path first and canonicalizing that.
  **Rationale**: symlink resolution only drops a leading `/private` when
  the remaining path still names something that exists on disk, so
  canonicalizing a not-yet-created child — as an install-directory guard
  needs to, before the directory it is about to create exists — yields a
  different root than canonicalizing its already-existing parent. The
  source's comment states this literally refused every install into a
  macOS temporary directory, or a home on another volume, by name, before
  `canonicalChild` existed to canonicalize only the part that is actually
  there.
  **Approved**: pending
- **Decision**: `url(_:isContainedIn:)` treats the base directory itself as
  not contained in itself, rather than allowing the candidate to equal the
  base.
  **Rationale**: the source's own comment states the consequence of
  allowing equality directly: a declared path of `"."` resolves to the
  directory itself, and treating that as "contained" would hand a caller
  the directory to open as if it were a file.
  **Approved**: pending
- **Decision**: `InstalledContentLocation` derives locations but never
  validates its own string inputs (`appName`, `subdirectory`, `name`) for
  emptiness or shape, leaving that entirely to callers.
  **Rationale**: per `application-support-appname-validation`, the source's
  own doc comment makes a non-empty `appName` a caller precondition rather
  than a guard in the function, and no
  test in `InstalledContentLocationTests.swift` exercises an empty
  `appName`. Documented here rather than silently left as an assumption,
  per the source's own naming of the risk.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`separation-of-concerns` passes because the file cleanly splits three
responsibilities across three types: `ExtensionResourcePathError` only names
and describes one failure, `ExtensionResourcePath` only resolves and checks
containment, and `InstalledContentLocation` only composes locations — none of
the three reads a manifest, parses JSON, or performs a file read
(`error-case`, `single-base-resolve`, `application-support-composition`).
`input-sanitization` passes because every `declared` string is
extension-author-supplied, untrusted text, and `resolve` never trusts it: it
is resolved, symlink-canonicalized, and checked against a component-wise
containment rule before any caller is handed a `URL` to read
(`candidate-construction`, `escape-refusal`, `symmetric-canonicalization`);
the source's own header comment names the exact vulnerability class this
closes. `explicit-error-handling` passes because the one failure this file
defines is never swallowed — it is a typed, `Equatable`,
`LocalizedError`-conforming case a caller must handle, and every production
caller (`ThemeContributionPoint`, `SnippetStore`, `ExtensionHost`) does
handle it, either recording it for display or re-throwing it as its own
richer error (`escape-refusal`, `error-message`). `unit-test-coverage`
passes: `ExtensionResourcePathTests.swift` exercises both `resolve`
overloads, the flagless-base case, the escape refusal and its message, and
the containment primitive directly (a prefix-sharing sibling, self-
containment, a deep descendant, a symlinked base, and a symlink-planted
escape), and its `InstalledContentLocationTests` suite exercises both
`InstalledContentLocation` factories and the injected-home override.
`no-hardcoded-strings` fails: `errorDescription` returns a fixed English
sentence with no localization lookup of any kind, so the message an
extension author sees when a path escapes is English regardless of the
host's locale (`error-message`, Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/manifest/. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
