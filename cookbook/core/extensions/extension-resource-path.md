---
id: f6acc431-0443-4b14-8ae4-e1f2dc227c0c
title: ExtensionResourcePath
domain: agentictoolkit://cookbook/core/extensions/extension-resource-path
type: ingredient
version: 1.0.2
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
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
- agentictoolkit://cookbook/core/extensions/extension-identity-component
- agentictoolkit://cookbook/core/extensions/extension-manifest
- agentictoolkit://cookbook/ai-plugin-kit/ai-plugin-manager
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

# ExtensionResourcePath

## Overview

`ExtensionResourcePath` is `AgenticToolkitCore`'s single containment check for
every path a third-party VS Code-compatible extension declares against a
location inside its own installed directory. Per its own header comment,
before this type existed the same rule was hand-rolled at four call sites — a
theme contribution's `path`, a theme's own `include`, a snippet contribution's
`path`, and the extension host's `browser` entry point — and three of the
four were missing the escape half of the check, so the same
`../../../.ssh/config` traversal could read arbitrary files through any of
them. `ExtensionResourcePathError` is the one typed failure `resolve` can
raise, carrying both the string the extension declared and the absolute path
it actually resolved to, so a rejection is checkable rather than a bare
boolean. `InstalledContentLocation`, defined in the same file, is a second,
narrower concern that happens to live here: it derives the two conventions
this project's hosts use for user-installed add-ons dropped beside the app
rather than inside it — a per-app Application Support subdirectory, and a
hand-filled home dotfolder — replacing what `AIPluginManager.init(appName:additionalSearchPaths:)`
and the app's own extension host had each hand-rolled and let drift out of
step. Every production caller today — `ThemeContributionPoint`'s theme-import
loop, `SnippetStore`'s snippet-loading loop, `VSCodeThemeImporter.resolvedRoot`,
`ExtensionHost.resolveEntryPoint`, `ExtensionHostInstaller.entryPointSignature`,
and `AIPluginManager.init` — resolves or composes its path through this one
file rather than re-deriving the rule.

## Behavioral Requirements

- **error-case**: `ExtensionResourcePathError` MUST be declared as a `public
  enum` conforming to `Error` and `Equatable`, with exactly one case,
  `escapesExtensionDirectory(declared: String, resolved: String)`.
- **error-message**: `ExtensionResourcePathError` MUST conform to
  `LocalizedError`, and its `errorDescription` MUST return a sentence naming
  both the exact string the caller declared and the exact resolved
  destination path, in the form "The path (declared, in curly quotes)
  resolves to (resolved), which is outside the extension's own directory."
- **single-base-resolve**: `ExtensionResourcePath.resolve(_:inside:)` MUST
  resolve `declared` against `directory` and require the result be contained
  within that same `directory`, by delegating to
  `resolve(_:relativeTo:containedIn:)` with `directory` supplied as both the
  base and the root.
- **candidate-construction**: `resolve(_:relativeTo:containedIn:)` MUST build
  its candidate URL by constructing a file URL from `declared` relative to
  `canonicalDirectory(base)`, then applying symlink resolution followed by
  path standardization, in that order.
- **escape-refusal**: `resolve(_:relativeTo:containedIn:)` MUST throw
  `ExtensionResourcePathError.escapesExtensionDirectory(declared:resolved:)`
  when the constructed candidate is not contained in
  `canonicalDirectory(root)`, and MUST return the candidate unchanged when it
  is.
- **error-payload-fidelity**: the thrown error's `declared` value MUST be
  exactly the string the caller passed in, unmodified by trimming or
  normalization, and its `resolved` value MUST be the fully canonicalized
  candidate's `.path`.
- **directory-flag-forcing**: `canonicalDirectory(_:)` MUST re-derive its
  argument as a file URL with the is-directory flag explicitly set to `true`
  before resolving symlinks and standardizing, so that a `URL` value carrying
  no is-directory flag is still treated as a directory rather than resolved
  against its parent.
- **symmetric-canonicalization**: both the base (or root) side and the
  candidate side of a containment decision MUST be produced by resolving
  symlinks and then standardizing, so that a directory reached through a
  symlink (for example macOS's `/var` mapping to `/private/var`) compares
  equal to the same directory reached directly.
- **child-of-nonexistent-parent**: `canonicalChild(_:of:)` MUST derive its
  result by canonicalizing only `parent` (which is assumed to exist) via
  `canonicalDirectory`, then appending `component` and standardizing the
  result; it MUST NOT canonicalize the combined, not-yet-existing path as a
  whole.
- **containment-strictness**: `url(_:isContainedIn:)` MUST return `true` if
  and only if `candidate`'s path-component count is strictly greater than
  `base`'s, and the leading path components of `candidate` — as many as
  `base` has — equal `base`'s path components exactly, element by element; a
  directory MUST NOT be considered contained in itself.
- **component-wise-comparison**: `url(_:isContainedIn:)` MUST compare path
  components, and MUST NOT treat `base`'s path as a string prefix of
  `candidate`'s path, so that a sibling directory whose name merely starts
  with `base`'s name (for example a directory named with `base`'s name plus
  `-evil` appended) is never mistaken for a descendant.
- **containment-inputs-uncanonicalized**: `url(_:isContainedIn:)` MUST NOT
  itself resolve symlinks or standardize either argument; it MUST operate
  only on whichever path components its two `URL` arguments already carry,
  leaving canonicalization to the caller.
- **application-support-composition**: `InstalledContentLocation.applicationSupport(appName:subdirectory:)`
  MUST return the user domain's Application Support directory with `appName`
  appended and then `subdirectory` appended, in that order, and MUST return
  `nil` when the user domain has no Application Support directory to report.
- **home-dot-directory-composition**: `InstalledContentLocation.homeDotDirectory(named:in:)`
  MUST return `home` with one additional path component consisting of a
  literal `.` immediately followed by `name`.
- **home-directory-default**: `homeDotDirectory(named:in:)`'s `home`
  parameter MUST default to the process's own home directory (via
  `NSHomeDirectory()`, marked as a directory) when the caller supplies no
  override.
- **stateless-synchronous-operation**: every operation on
  `ExtensionResourcePath` and `InstalledContentLocation` MUST be a
  synchronous, non-`async`, `static` function or a computed value operating
  only on its arguments; neither enum declares any case and neither can be
  instantiated, so neither can carry stored instance state between calls.
- **no-actor-isolation**: neither `ExtensionResourcePath`,
  `InstalledContentLocation`, nor `ExtensionResourcePathError` declares a
  `Sendable` conformance or any actor / `@MainActor` isolation in the source.
  Because every parameter and return value used here (`String`, `URL`,
  `Bool`) is itself `Sendable`, and none of the three types holds mutable
  stored state reachable from more than one call, every operation MUST be
  safe to invoke from any isolation domain, concurrently, without additional
  synchronization.
- **filesystem-side-effects**: `resolve(_:inside:)`,
  `resolve(_:relativeTo:containedIn:)`, and `canonicalDirectory(_:)` MUST
  consult the file system (through symlink resolution) to canonicalize a
  path, but no function in this file MUST create, delete, or write to any
  file or directory.
- **application-support-appname-validation**: `applicationSupport(appName:subdirectory:)` performs no check that `appName` is non-empty before composing the path. Its doc comment makes non-empty a caller precondition — an empty component "collapses the path onto the shared Application Support/subdirectory and silently widens the search to every app's content of that kind" — and says callers derive the name through something that cannot answer `""` (`AppStorageLocation.displayName`); today the only caller, `AIPluginManager.init`, always supplies a non-empty display name.

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
| erp-001 | single-base-resolve, candidate-construction | `resolve("./themes/dark.json", inside: directory)` | resolves to the canonical `directory/themes/dark.json` URL (source: `resolvesInsideTheDirectory`) |
| erp-002 | candidate-construction | `resolve("snippets/x.code-snippets", inside: directory)` (no leading `./`) | resolves to `directory/snippets/x.code-snippets`; a leading `./` is not required (source: `resolvesWithoutDotSlash`) |
| erp-003 | directory-flag-forcing | `resolve("./themes/dark.json", inside: directory)` where `directory` is a `URL` carrying no is-directory flag | resolves inside `directory`, not beside it (source: `resolvesAgainstAFlaglessBase`) |
| erp-004 | escape-refusal, error-payload-fidelity | `resolve("../outside/secret.json", inside: extDirectory)` where `extDirectory` is a child of `parent` | throws `escapesExtensionDirectory(declared: "../outside/secret.json", resolved: <parent>/outside/secret.json canonical path)` (source: `refusesAnEscape`) |
| erp-005 | error-message | `errorDescription` of `escapesExtensionDirectory(declared: "../x.json", resolved: "/tmp/x.json")` | the description contains both `"../x.json"` and `"/tmp/x.json"` (source: `refusalIsASentence`) |
| erp-006 | single-base-resolve, escape-refusal | `resolve("../base.json", relativeTo: themesDirectory, containedIn: root)`, then `resolve("../../base.json", relativeTo: themesDirectory, containedIn: root)` | the first resolves to `root/base.json`; the second throws `ExtensionResourcePathError` (source: `resolvesRelativeToOneDirectoryContainedInAnother`) |
| erp-007 | component-wise-comparison, containment-inputs-uncanonicalized | `url(candidate:, isContainedIn: base)` where `candidate`'s directory name is `base`'s name with `-evil` appended | returns `false` even though the candidate's path string has `base`'s path as a literal string prefix (source: `siblingWithSharedNamePrefixIsNotInside`) |
| erp-008 | containment-strictness, containment-inputs-uncanonicalized | `url(base, isContainedIn: base)` | returns `false` (source: `theBaseIsNotInsideItself`) |
| erp-009 | containment-strictness, containment-inputs-uncanonicalized | `url(deepDescendant, isContainedIn: base)` where `deepDescendant` is three levels below `base` | returns `true` (source: `aDeepDescendantIsInside`) |
| erp-010 | symmetric-canonicalization | `resolve("./themes/dark.json", relativeTo: symlinkToRealDirectory, containedIn: realDirectory)` | resolves to `realDirectory/themes/dark.json`, treating the symlinked and real directories as equal (source: `symlinkedBaseCompares`) |
| erp-011 | escape-refusal, symmetric-canonicalization | `resolve("./escape/secret.json", inside: directory)` where `directory/escape` is a symlink pointing to a sibling directory outside `directory` | throws `ExtensionResourcePathError`, even though the declared string itself contains no `..` (source: `aSymlinkOutOfTheDirectoryIsRefused`) |
| erp-012 | application-support-composition | `applicationSupport(appName: "Coffee Grinder", subdirectory: "Extensions")` | the result's last three path components, in order, are `"Application Support"`, `"Coffee Grinder"`, `"Extensions"` (source: `applicationSupportComposesBothComponents`) |
| erp-013 | application-support-composition | `applicationSupport(appName: "Coffee Grinder", subdirectory: "Plugins")` compared with `subdirectory: "Extensions"` | both results share the same parent directory (source: `bothHostsShareTheApplicationSupportShape`) |
| erp-014 | home-dot-directory-composition | `homeDotDirectory(named: "agenticextensions", in: fixtureHome)` and `homeDotDirectory(named: "agenticplugins", in: fixtureHome)` | results equal `fixtureHome` appended with `.agenticextensions` and `.agenticplugins` respectively (source: `homeDotDirectoryAddsTheDot`) |
| erp-015 | home-directory-default | `homeDotDirectory(named: "agenticextensions", in: fixtureHome)` compared with `homeDotDirectory(named: "agenticextensions")` (default `home`) | the two results differ, and the default result's parent path equals the process's real home directory (source: `theInjectedHomeWins`) |
| erp-016 | filesystem-side-effects | call `resolve(_:inside:)` inside a scratch directory, then enumerate the directory's contents before and after the call | the directory's entries are unchanged; no file or folder is created, deleted, or modified by the call (traced to the absence of any create/write call in `ExtensionResourcePath.swift`) |
| erp-017 | no-actor-isolation, stateless-synchronous-operation | invoke `ExtensionResourcePath.resolve(_:inside:)` concurrently from many detached tasks against the same `directory` with different `declared` strings | every call completes with the result its own input implies, with no crash and no shared-state corruption (traced to the absence of any stored property, actor, or `@MainActor` annotation on `ExtensionResourcePath`) |
| erp-018 | application-support-composition | `applicationSupport(appName:subdirectory:)` on a host where the user domain reports no Application Support directory | returns `nil` — not exercised by name in `InstalledContentLocationTests.swift`, but traced directly to the `guard let base = ... else { return nil }` line in the source |

## Edge Cases

- **Null/empty declared path — the directory itself**: a `declared` value of
  `"."` resolves, before the containment check, to the directory itself;
  `containment-strictness` then refuses it because the directory is not
  strictly below itself, so `resolve` throws `escapesExtensionDirectory`
  rather than handing a caller the directory to open as if it were a file.
  This is the exact case the source's own comment on `url(_:isContainedIn:)`
  names. MUST.
- **Boundary — exactly at the root versus one hop beyond it**: a declared
  path that climbs exactly to `root` (for example `"../base.json"` from a
  `themes/` folder one level below `root`) resolves and succeeds; the same
  path climbing one directory further (`"../../base.json"`) throws
  `escapesExtensionDirectory`. The boundary is the root directory itself,
  inclusive on the "still inside" side only in the sense that any path
  strictly below `root` succeeds. MUST.
- **Symlink escape with no literal `..` in the declared string**: a
  declared path containing no `..` at all can still escape if a symlink
  planted inside the extension's own directory points outside it; symlink
  resolution on the candidate resolves that symlink to its real target
  before the containment check runs, so the escape is caught even though
  nothing about the declared string itself was suspicious. MUST.
- **Concurrent access**: `ExtensionResourcePath`, `ExtensionResourcePathError`,
  and `InstalledContentLocation` hold no mutable stored state — every entry
  point is a pure `static` function over its arguments — so calling any of
  them concurrently, from any thread or actor, against the same or
  different directories, requires no synchronization. MUST.
- **Error states**: the only defined failure is
  `ExtensionResourcePathError.escapesExtensionDirectory`, thrown once,
  synchronously, by `resolve`. `applicationSupport` communicates its one
  "nothing to name" case by returning `nil`, never by throwing; a caller
  that ignores a `nil` result (no production caller does today) silently
  proceeds with one fewer search path rather than crashing. Stated as fact,
  not a marker — the source defines no other error condition.
- **Offline / disconnected state**: not applicable. Every operation reads
  only the local file system's symlink structure; there is no networking
  and therefore no connectivity state to lose mid-operation.
- **Cancellation and timeout**: `resolve`, `canonicalDirectory`, and
  `canonicalChild` define no timeout and no cancellation, because every
  call is synchronous local file-system metadata access with no `async`
  entry point. A slow or unresponsive mount underneath the directory being
  resolved blocks the caller for as long as symlink resolution takes, with
  no escape hatch defined in this file. Stated as fact, per the absent-
  feature rule — not a marker, since nothing in the purpose of a
  synchronous path resolver calls for one.
- **Unvalidated caller inputs beyond `appName`**: `homeDotDirectory(named:in:)`
  takes `name` at face value; the source's own doc comment states the
  dotless convention exists so that "these are hidden folders" is a
  property of this function rather than of each caller's string literal,
  but the function does not verify `name` omits a leading dot or a path
  separator — every caller today (`AIPluginManager.init`, and the test
  suite) already passes a plain identifier such as `"agenticplugins"`, so
  this is a fact about the function's contract rather than an observed
  failure.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `declared` | `String` | none (required) | The path exactly as an extension manifest, theme file, or contribution point spelled it; passed to `resolve(_:inside:)` or `resolve(_:relativeTo:containedIn:)`. |
| `directory` | `URL` | none (required) | The extension's own folder, used as both the resolution base and the containment boundary in the single-argument `resolve(_:inside:)` overload. |
| `base` | `URL` | none (required) | The directory `declared` is resolved relative to, in the two-argument overload; may differ from `root` — a theme's `include` is relative to the including file's own folder, not the extension's. |
| `root` | `URL` | none (required) | The directory the resolved candidate may not leave, in the two-argument overload. |
| `component` | `String` | none (required) | The not-yet-existing child name appended to `parent` by `canonicalChild(_:of:)`. |
| `parent` | `URL` | none (required) | The directory, assumed to already exist, that `component` is appended to by `canonicalChild(_:of:)`. |
| `appName` | `String` | none (required) | The app's display name, passed to `InstalledContentLocation.applicationSupport(appName:subdirectory:)`; the function's own doc comment states it must not be empty, though nothing in the function enforces this (see `application-support-appname-validation` above). |
| `subdirectory` | `String` | none (required) | The content-kind folder name (for example `"Plugins"` or `"Extensions"`) appended under the app's Application Support directory. |
| `name` | `String` | none (required) | The dotless folder name passed to `homeDotDirectory(named:in:)` (for example `"agenticplugins"` or `"agenticextensions"`); the leading dot is added by the function. |
| `home` | `URL` | the process's real home directory | The home directory `homeDotDirectory` resolves against; a caller — typically a test — overrides it so that a test run reads its own fixture rather than a real developer's installed content. |

There are no settings keys or dependency-injection containers involved: every
input arrives as a plain function argument. The one indirect environment
dependency is the process's home directory, consulted only when `home` is
left at its default.

## Deep Linking

Not applicable: this component resolves and composes local file-system paths
in memory; it defines no URL scheme, route, or navigable destination.

## Localization

This component produces exactly one user-facing string:
`ExtensionResourcePathError.errorDescription`, a hardcoded English sentence
with no localization lookup of any kind — no locale parameter, no
externalized string table entry. `SnippetFileFailure.reason` and
`ThemeImportFailure.message` (in the file's call sites) both store this same
English sentence verbatim, via `error.localizedDescription`, for direct
display to an extension author regardless of the host's system locale.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — not externalized) | The path "declared value" resolves to "resolved value", which is outside the extension's own directory. | `ExtensionResourcePathError.errorDescription`, shown via `error.localizedDescription` when a snippet, theme, theme `include`, or entry-point path escapes its extension's own directory. |

## Accessibility Options

Not applicable: this component has no visual or interactive surface for a
system accessibility display option to affect.

## Feature Flags

Not applicable: `ExtensionResourcePath.swift` defines no feature flag, build
configuration check, or remote-config lookup; every function's behavior is
fixed entirely by the arguments it is called with.

## Analytics

Not applicable: this component emits no analytics event; it returns a `URL`,
a thrown error, or `nil` to its caller and performs no telemetry of its own.

## Privacy

- **Data collected**: none in the sense of device- or user-identifying
  telemetry. However, the `resolved` value carried by a thrown
  `escapesExtensionDirectory` error, and every `URL` that
  `InstalledContentLocation.homeDotDirectory`/`applicationSupport` derive,
  is an absolute local file-system path that necessarily embeds the local
  account's home-directory name — traced to the use of the process's home
  directory and the user-domain Application Support directory as the base
  of every derived location.
- **Storage**: none. Every value this component produces is held only in
  the caller's own variables for as long as the caller keeps it; this file
  writes nothing to disk.
- **Transmission**: none performed directly by this component — it does no
  networking. Downstream, `SnippetFileFailure.reason` and
  `ThemeImportFailure.message` carry a resolved path (and the account name
  it embeds) into structures a settings panel may display to the extension
  author; how far that display surface propagates is outside this file.
- **Retention**: for the lifetime of whichever value — a `URL`, a thrown
  error, or a search-path array — the caller holds; this component itself
  retains nothing once a call returns.

## Logging

Not applicable: `ExtensionResourcePath.swift` contains no logging call and
imports no logging framework; a failure is communicated to its caller
exclusively through the thrown `ExtensionResourcePathError`, never written
to a log by this component itself.

## Platform Notes

- **SwiftUI**: the source (`ExtensionResourcePath.swift`) is plain
  Foundation — `URL` and, transitively through `NSHomeDirectory()` and
  `FileManager.default.urls(for:in:)`, `FileManager` — with zero dependency
  on SwiftUI or any view-layer framework. It sits in `AgenticToolkitCore`,
  the tier reachable from both `Language/` (the snippet store) and `macOS/`
  (the theme, host, and plugin-manager call sites). A port that keeps this
  component in Swift needs nothing beyond `Foundation`.
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
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
