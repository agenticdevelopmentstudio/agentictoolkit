<!-- leaf: implement-extension-host-core-1/extensions-extension-resource-path · source: extension-host-core-extensions-extension-resource-path.md -->

**Rules** (cite as `implement-extension-host-core-1/extensions-extension-resource-path#<slug>`):

- `error-case` MUST
- `error-message` MUST
- `single-base-resolve` MUST
- `candidate-construction` MUST
- `escape-refusal` MUST
- `error-payload-fidelity` MUST
- `directory-flag-forcing` MUST
- `symmetric-canonicalization` MUST
- `child-of-nonexistent-parent` MUST
- `containment-strictness` MUST
- `component-wise-comparison` MUST
- `containment-inputs-uncanonicalized` MUST
- `application-support-composition` MUST
- `home-dot-directory-composition` MUST
- `home-directory-default` MUST
- `stateless-synchronous-operation` MUST
- `no-actor-isolation` MUST
- `filesystem-side-effects` MUST

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

