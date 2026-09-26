---
id: 35dd47a6-23f3-4306-9c81-e3823b79a7a3
title: VSIXInstaller
domain: agentictoolkit://cookbook/core/extensions/vsix-installer
type: ingredient
version: 1.0.2
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "Puts a downloaded or user-supplied .vsix on disk as a directory
  ExtensionRegistry can load, verifying it against the registry's published
  digest and signature and removing every other directory that claims the
  same identifier in the same step."
platforms:
- swift
- macos
tags:
- extension-host
- vsix
- installer
- filesystem
depends-on: []
related:
- agentictoolkit://cookbook/core/extensions/extension-identity-component
- agentictoolkit://cookbook/core/extensions/extension-resource-path
- agentictoolkit://cookbook/core/extensions/extension-manifest
- agentictoolkit://cookbook/core/extensions/extension-manifest-localization
- agentictoolkit://cookbook/core/extensions/vs-code-engine-range
- agentictoolkit://cookbook/core/extensions/vsix-archive
- agentictoolkit://cookbook/core/extensions/open-vsx-catalog
- agentictoolkit://cookbook/core/extensions/open-vsx-client
- agentictoolkit://cookbook/core/extensions/extension-registry
references:
- packages/apple/AgenticToolkit/Core/Extensions/VSIXInstaller.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/VSIXArchive.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/ExtensionIdentityComponent.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/ExtensionResourcePath.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/ExtensionManifest.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/ExtensionManifestLocalization.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/VSCodeEngineRange.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/OpenVSXCatalog.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/OpenVSXClient.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/ExtensionRegistry.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Concurrency/BlockingWork.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Extensions/VSIXInstallerTests.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Extensions/VSIXInstallerFileSystemFailureTests.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Extensions/VSIXRegistryInstallTests.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

# VSIXInstaller

## Overview

`VSIXInstaller` is a `Sendable` `struct` that puts a `.vsix` on disk as a
directory `ExtensionRegistry` can load, and takes the previous install of the
same extension away in the same step. Its whole design is organized around
two states a half-done install would leave behind, both worse than an outright
failure: a partly written directory (`ExtensionRegistry.load(from:)` silently
skips a folder whose `package.json` has not landed yet, calls the scan
complete anyway, and then prunes that extension's themes as orphans — the
user's selected theme does not come back), and two directories claiming one
identifier (the registry resolves that by sorted directory name, which is not
version order, so `…-1.10.0` sorting before `…-1.9.0` can leave an *old*
version winning after an update that only added a folder).

It has two public entry points that converge on one code path. `install(_:
using:)` is the registry half: it decides installability and verification
completeness from `OpenVSXExtensionDetail` metadata alone, downloads the
archive and whichever verification artifacts the registry named, then hops
off the cooperative thread pool to hash and check the archive and write it to
disk. `install(archive:verification:expectedIdentifier:source:)` is the local
half — what a user dropping a `.vsix` on the app reaches directly, and what
the registry half calls once it already has proved bytes in hand. Every
identity and containment check downstream of the manifest applies on both
paths alike, because the manifest is a document neither a registry response
nor a user's file selection can be trusted to agree with.

All line references below are to
`packages/apple/AgenticToolkit/Core/Extensions/VSIXInstaller.swift` unless
another file is named.

## Behavioral Requirements

- **injected-install-directory**: `VSIXInstaller` MUST store `installDirectory`
  as an injected `URL` rather than deriving it internally, because the tier
  this type lives in cannot import `AppStorageLocation`, and because a test
  that installs into a real user's extensions directory would not be a test.
- **default-host-version**: `init`'s `hostVersion` parameter MUST default to
  `ExtensionRegistry.declaredVSCodeVersion`, which equals `SemanticVersion(major:
  1, minor: 138, patch: 0)` (66–68; `ExtensionRegistry.swift`).
- **injected-file-manager**: `init`'s `fileManager` parameter MUST be a
  `@Sendable () -> FileManager` closure defaulting to `{ .default }`, never a
  stored `FileManager` instance, because `FileManager` is not `Sendable` and
  this type is; every file operation MUST read the file manager through this
  closure.
- **sendable-value-type**: `VSIXInstaller` MUST be declared as a `Sendable`
  `struct`, usable concurrently from any thread or actor without additional
  synchronization for its own construction and property access, because its
  only stored properties are an immutable `URL`, an immutable
  `SemanticVersion`, and an immutable `@Sendable` closure.
- **registry-install-order**: `install(_:using:)` MUST decide installability
  from the record's metadata, then decide verification-artifact completeness
  from the record's metadata, before downloading anything; only after both
  checks pass MUST it download the archive and whichever verification
  artifacts the record named.
- **registry-installability-gate**: `install(_:using:)` MUST throw
  `VSIXInstallError.registryVersionUnusable(installability)` when
  `detail.installability(forHostVersion: hostVersion)` is not `.installable`,
  without making any request.
- **registry-requires-universal-build**: `install(_:using:)` MUST throw
  `VSIXInstallError.registryVersionUnusable(.noUniversalBuild)` when
  `detail.universalDownloadURL` is `nil`, without making any request.
- **signature-pair-completeness**: `install(_:using:)` MUST throw
  `VSIXInstallError.verificationIncomplete(published:missing:)`, before
  downloading the archive, when the record names exactly one of
  `signatureURL`/`publicKeyURL` and not the other — `verificationIncomplete(
  published: "signature", missing: "publicKey")` for a signature with no key,
  `verificationIncomplete(published: "publicKey", missing: "signature")` for a
  key with no signature.
- **artifact-fetched-only-if-named**: `install(_:using:)` MUST fetch
  `sha256URL`, and MUST fetch both `signatureURL` and `publicKeyURL` together,
  only when the record names each one; an artifact the record names but
  `client` cannot serve MUST propagate as `client`'s own thrown error, carrying
  the URL that failed.
- **blocking-verification-hop**: `install(_:using:)` MUST run archive
  verification (`VSIXArchive.verify`) and the local install
  (`install(archive:verification:expectedIdentifier:source:)`) inside
  `BlockingWork.run`, on a GCD global queue, rather than directly on the
  calling `async` context or inside `Task.detached` — because both steps are
  synchronous and blocking (a SHA-256 over up to 512 MB, then a write and a
  `ditto` invocation that can hold a thread for up to 124 seconds), and a
  detached task still occupies a cooperative-pool thread for the whole of that
  (`BlockingWork.swift`).
- **local-install-entry-point**: `install(archive:verification:
  expectedIdentifier:source:)` MUST be usable both as the tail of the registry
  flow above and as the sole entry point for archive bytes with no registry
  provenance (a user-supplied `.vsix`), with `expectedIdentifier` defaulting to
  `nil` for the latter case.
- **scratch-directory-lifecycle**: `install(archive:...)` MUST create a
  uniquely named scratch directory under `fileManager.temporaryDirectory`
  (`vsix-install-<UUID>`), and MUST remove it via `defer` on every exit path,
  successful or not.
- **archive-expansion**: `install(archive:...)` MUST write `archive` to
  `extension.vsix` inside the scratch directory and expand it with
  `VSIXArchive.expand` into an `expanded` subdirectory before reading anything
  from it.
- **payload-directory-required**: `install(archive:...)` MUST throw
  `VSIXInstallError.noPayloadDirectory` when `VSIXArchive.payloadDirectory(in:
  expanded)` does not exist — a zip that is not a `.vsix`.
- **manifest-read-and-localized**: `readManifest(in:)` MUST read
  `<payload>/package.json`, run its bytes through
  `ExtensionManifestLocalization.localize(_:forManifestIn:)` to resolve
  `%key%` placeholders against the payload's own nls tables, then through
  `JSONCPreprocessor.jsonData(from:)`, before decoding it as `ExtensionManifest`
  with a plain `JSONDecoder`.
- **manifest-unreadable**: `readManifest(in:)` MUST throw
  `VSIXInstallError.manifestUnreadable` when `package.json` cannot be read as
  `Data`.
- **manifest-malformed**: `readManifest(in:)` MUST throw
  `VSIXInstallError.manifestMalformed(String)`, carrying the decoder's
  `localizedDescription`, when the (localized, preprocessed) bytes do not
  decode as `ExtensionManifest`.
- **identity-claim-checked**: `install(archive:...)` MUST throw
  `VSIXInstallError.identityMismatch(claimed:found:)` when `expectedIdentifier`
  is non-`nil` and differs from the decoded `manifest.identifier`, before any
  further check runs — a registry claim the archive's own manifest does not
  bear out.
- **engine-range-checked**: `install(archive:...)` MUST throw
  `VSIXInstallError.engineRangeUnreadable(manifest.engines.vscode)` when
  `VSCodeEngineRange(manifest.engines.vscode)` fails to parse, and MUST throw
  `VSIXInstallError.engineIncompatible(manifest.engines.vscode, host:
  hostVersion.description)` when the parsed range does not accept
  `hostVersion` — both before the destination directory is computed or created.
- **identity-fields-validated**: `install(archive:...)` MUST call
  `requireSafeComponent` on both `manifest.identifier` and `manifest.version`,
  throwing `VSIXInstallError.unsafeIdentity(field:value:)` when either fails
  `ExtensionIdentityComponent.isSafe`, before either value becomes a directory
  name component, on every install path — `expectedIdentifier` above guards
  only one field on only the registry path, and `version` is compared with
  nothing else on any path (343–347;
  `ExtensionIdentityComponent.swift`).
- **directory-naming-convention**: `VSIXInstaller.directoryName(identifier:
  version:)` MUST return `"\(identifier)-\(version)"` — the layout the
  Marketplace installer writes — as pure string interpolation with no escaping
  and no validation of its own; the constraint that makes the result safe
  lives entirely in the caller's prior call to `requireSafeComponent`, not in
  this function.
- **destination-containment-double-checked**: `install(archive:...)` MUST
  independently verify, after building `destination`, that
  `ExtensionResourcePath.canonicalChild(directoryName, of: installDirectory)`
  is contained in `ExtensionResourcePath.canonicalDirectory(installDirectory)`,
  throwing `VSIXInstallError.unsafeIdentity(field: "identifier", value:
  destination.lastPathComponent)` when it is not — a check over the actual
  resolved path, distinct in kind from the string-level
  `identity-fields-validated` check above it, because a future change to
  `directoryName` that joined its parts differently would slip past the first
  and be caught here.
- **install-directory-created**: `install(archive:...)` MUST create
  `installDirectory`, with intermediate directories, before scanning it or
  writing into it — a first install into a fresh home MUST succeed, not be
  treated as an edge case (test `createsTheInstallDirectory`).
- **recovery-runs-before-scan**: `install(archive:...)` MUST call
  `recoverInterruptedInstalls()` before computing superseded directories or
  moving anything into place, so an aside a previous crash left behind is
  visible to the supersede sweep rather than invisible and unreclaimed.
- **reinstall-idempotent**: `install(archive:...)` MUST succeed, not throw a
  conflict, when the archive being installed is the same identifier and
  version already present at `destination` — the existing directory MUST be
  replaced rather than left alone, because its bytes are unproved and it may
  be a half-written tree an earlier attempt died inside, while the incoming
  bytes have already passed verification (test
  `reinstallIsIdempotent`).
- **supersede-by-manifest-identity**: `otherInstallDirectories(claiming:
  besides:)` MUST list every directory in `installDirectory` other than
  `destination`, skipping hidden entries, and MUST match a candidate by
  decoding its own `package.json` and comparing `manifest.identifier` — never
  by matching the candidate's folder name against any naming convention — so a
  hand-installed extension or a dev checkout named however its author named
  it is still recognized as superseded (test
  `supersedesAHandNamedDirectory`).
- **supersede-non-fatal-removal**: `install(archive:...)` MUST still return a
  successful `VSIXInstallation` when a superseded directory cannot be removed,
  logging the failure rather than throwing, because the new version is already
  in place and loadable by that point and reporting the install as failed
  would be false (test
  `anUnremovableSupersededCopyStillInstalls`).
- **move-into-place-atomicity**: `moveIntoPlace(_:to:)` MUST move an existing
  `destination` aside before moving the new payload in, never delete it
  first, so that a failure of the second move can restore the first; when
  `destination` did not previously exist, a failed move MUST throw
  `VSIXInstallError.couldNotInstall(reason)` directly with no aside step at
  all.
- **move-into-place-rollback**: `moveIntoPlace(_:to:)` MUST attempt to move
  the aside back to `destination` when the payload move fails and a previous
  copy existed; on a successful rollback it MUST throw
  `VSIXInstallError.couldNotInstall(reason)` naming only the original failure;
  on a failed rollback it MUST log the rollback failure at `error` level and
  throw `VSIXInstallError.couldNotInstall` naming both the original failure
  and that the previous version could not be put back, together with the
  aside's last path component.
- **aside-cleanup-on-success**: `moveIntoPlace(_:to:)` MUST attempt to remove
  the aside with `try?` once the new payload is successfully in place,
  swallowing any removal failure rather than surfacing it as part of a
  successful install.
- **aside-naming**: the aside a replaced directory is moved to MUST be named
  `.<destination.lastPathComponent>.replacing-<UUID>` — a leading dot so that
  `otherInstallDirectories` and `ExtensionRegistry.scan`, both of which pass
  `.skipsHiddenFiles`, do not see the second copy of the identifier that
  exists for the moment between the two renames.
- **recovery-sweep-scope**: `recoverInterruptedInstalls()` MUST list
  `installDirectory`'s contents with no hidden-file filtering (the opposite of
  every other listing in this file), and for every entry whose name
  `Self.replacedName(ofAside:)` recognizes, MUST either remove the aside (when
  its replaced destination already exists) or move the aside back to that
  destination (when it does not).
- **recovery-non-aside-entries-untouched**: `Self.replacedName(ofAside:)` MUST
  return `nil`, leaving the entry alone, for any hidden name that does not
  carry both the leading-dot prefix and the `.replacing-<nonce>` marker with a
  non-empty replaced name — an ordinary dotfile such as `.DS_Store` MUST NOT be
  touched by a recovery sweep (test
  `anUnrelatedHiddenEntryIsLeftAlone`).
- **recovery-failure-logged**: `recoverInterruptedInstalls()` MUST log, at
  `error` level, a failure to remove or restore a recognized aside, and MUST
  leave that aside exactly where it is rather than deleting it — it may be the
  only surviving copy of the extension.
- **recovery-idempotent**: `recoverInterruptedInstalls()` MUST be safe to call
  when no install is in progress and MUST be safe to call repeatedly, because
  it acts only on entries matching the aside naming convention and a live
  `moveIntoPlace` holds its aside for both of its renames on one synchronous,
  actor-free call path.
- **installation-record-shape**: On success, `install(archive:...)` MUST
  return a `VSIXInstallation` carrying `identifier`, `version`, `displayName`,
  `directory` (the final `destination`), `verification`, `source`,
  `supersededDirectories` (every directory this call removed or failed to
  remove), and `runnableHere`, all taken from the decoded manifest and the
  call's own inputs.
- **runnable-here-computed**: `VSIXInstallation.runnableHere` MUST equal
  `manifest.browser != nil || manifest.main == nil` — `true` for a web
  extension with a `browser` entry point or for a declarative-only extension
  with no entry point at all, `false` only for an extension that declares
  `main` and no `browser`; a `false` value MUST NOT be treated as a failed
  install, since the extension's declarative contributions still work (574–584; test `runnableHereFollowsTheEntryPoint`).
- **install-source-shape**: `VSIXInstallation.Source` MUST be either
  `.registry(String, version: String)` (the `<namespace>/<name>` and version
  asked for) or `.localFile(URL)` (a `.vsix` the caller supplied), and
  `install(_:using:)` MUST always construct the former from `detail.namespace
  + "/" + detail.name` and `detail.version`.
- **directory-name-not-independently-safe**: `directoryName(identifier:
  version:)` and the historical doc comment on it MUST be understood as pure
  joining that guarantees nothing on its own — a prior version of this
  function's documentation claimed npm-level constraints on `name` and
  `publisher` that do not exist, since nothing in this path runs npm and
  `publisher` is not an npm field; the actual constraint is
  `identity-fields-validated` and `destination-containment-double-checked`
  above, in the caller.
- **request-safe-component-error**: `requireSafeComponent(_:field:)` MUST
  throw `VSIXInstallError.unsafeIdentity(field:value:)` naming the actual
  field and the actual (unsafe) value, rather than a generic failure, because
  the person reading the message is the one who needs to see what the archive
  claimed.
- **logging-conformance**: `VSIXInstaller` MUST conform to `Loggable`,
  declaring `public static nonisolated let logger = makeLogger()`, giving it
  category `"VSIXInstaller"` under whatever subsystem `Bundle.main.
  bundleIdentifier` resolves to (`"nil"` when there is none) (`Loggable.swift`).
- **case-folded-manifest-identifier**: `manifest.identifier`, which
  `directory-naming-convention` and every identity check above consume, MUST
  already be the case-folded `publisher.name` (or bare `name` with no
  publisher) that `ExtensionManifest.identifier` computes — `VSIXInstaller`
  itself performs no case-folding of its own
  (`ExtensionManifest.swift`).
- **concurrent-install-ordering**: NEEDS REVIEW: Not implemented in source. No lock or actor serializes concurrent calls to `install(archive:...)` (or the `install(_:using:)` path that calls it) sharing one `installDirectory` value; each call independently runs `recoverInterruptedInstalls`, the supersede scan, `moveIntoPlace`, and superseded-directory cleanup against the same directory tree, and the source defines no ordering, mutual exclusion, or detection of that overlap.

## Appearance

Not applicable — this is a file-system installer, not a visual component.

## States

Not applicable — this is a file-system installer, not a visual component.

## Accessibility

Not applicable — this is a file-system installer, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| vsix-installer-001 | directory-naming-convention, installation-record-shape | `install(archive:verification:expectedIdentifier: "acme.widget", source: .registry("acme/widget", version: "1.0.0"))` for a manifest naming `acme.widget` 1.0.0 with an extra `theme.json` | `installation.directory.lastPathComponent == "acme.widget-1.0.0"`; `supersededDirectories.isEmpty`; `theme.json` exists in the installed directory (test `installsUnderTheConventionalName`) |
| vsix-installer-002 | directory-naming-convention | `VSIXInstaller.directoryName(identifier: "acme.widget", version: "1.2.3")` | Returns `"acme.widget-1.2.3"` (test `directoryNameIsConventional`) |
| vsix-installer-003 | install-directory-created | `install(archive:...)` where `installDirectory` does not yet exist on disk | Succeeds; the directory tree is created and the extension lands under `acme.widget-1.0.0` (test `createsTheInstallDirectory`) |
| vsix-installer-004 | runnable-here-computed | Install three manifests: one declaring `browser`, one declaring neither `browser` nor `main`, one declaring only `main` | `runnableHere == true, true, false` respectively; all three directories exist on disk regardless (test `runnableHereFollowsTheEntryPoint`) |
| vsix-installer-005 | identity-claim-checked | `install(archive:...)` with `expectedIdentifier: "acme.something-else"` against an archive whose manifest names `acme.widget` | Throws `VSIXInstallError.identityMismatch(claimed: "acme.something-else", found: "acme.widget")`; nothing is written to `installDirectory` (test `identityMismatchIsRefused`) |
| vsix-installer-006 | engine-range-checked | `install(archive:...)` against a manifest with `engines.vscode == "^1.200.0"`, host `1.138.0` | Throws `VSIXInstallError.engineIncompatible("^1.200.0", host: "1.138.0")`; nothing written (test `engineIncompatibleIsRefused`) |
| vsix-installer-007 | engine-range-checked | `install(archive:...)` against a manifest with `engines.vscode == ">= 1.74.0"` | Throws `VSIXInstallError.engineRangeUnreadable(">= 1.74.0")` (test `engineRangeUnreadableIsRefused`) |
| vsix-installer-008 | payload-directory-required | `install(archive:...)` against a plain zip with no `extension/` directory | Throws `VSIXInstallError.noPayloadDirectory` (test `noPayloadDirectory`) |
| vsix-installer-009 | manifest-unreadable | `install(archive:...)` against a `.vsix` whose `extension/` directory has no `package.json` | Throws `VSIXInstallError.manifestUnreadable` (test `manifestUnreadable`) |
| vsix-installer-010 | manifest-malformed | `install(archive:...)` against a manifest of `"{ not json at all"` | Throws `VSIXInstallError.manifestMalformed(reason)` with a non-empty `reason` (test `manifestMalformed`) |
| vsix-installer-011 | reinstall-idempotent | `install(archive:...)` the same archive twice in a row | Both succeed; the two returned directories are the same standardized URL; the second call's `supersededDirectories.isEmpty`; exactly one directory remains (test `reinstallIsIdempotent`) |
| vsix-installer-012 | supersede-by-manifest-identity | Install `acme.widget` 1.9.0, then install `acme.widget` 1.10.0 | The update's `supersededDirectories` names `acme.widget-1.9.0`; only `acme.widget-1.10.0` remains — despite `…-1.10.0` sorting before `…-1.9.0` by name (test `supersedesTheOlderVersion`) |
| vsix-installer-013 | supersede-by-manifest-identity | A hand-named directory `my-widget-checkout` whose `package.json` claims `acme.widget`, plus an unrelated `other.thing-1.0.0`, both present before installing `acme.widget` 2.0.0 | `supersededDirectories` names only `my-widget-checkout`; the final listing is `["acme.widget-2.0.0", "other.thing-1.0.0"]` (test `supersedesAHandNamedDirectory`) |
| vsix-installer-014 | move-into-place-rollback | Install `acme.widget` 1.0.0, then attempt to install a 2.0.0 whose engine range the host rejects | The refused install throws; `acme.widget-1.0.0` and its `theme.json` remain exactly as before (test `afailedInstallLeavesTheOldOneAlone`) |
| vsix-installer-015 | identity-fields-validated, destination-containment-double-checked | `install(archive:...)` against a manifest with `version: "../../escaped"` | Throws `VSIXInstallError.unsafeIdentity(field: "version", value: "../../escaped")`; nothing is written even two levels above `installDirectory` (test `hostileVersionIsRefused`) |
| vsix-installer-016 | identity-fields-validated | `install(archive:...)` against a manifest with `name: "../../escaped"` | Throws `VSIXInstallError.unsafeIdentity(field: "identifier", value: "acme.../../escaped")`; nothing written (test `hostileNameIsRefused`) |
| vsix-installer-017 | identity-fields-validated | `install(archive:...)` against a manifest with `publisher: ".hidden"` | Throws; nothing written — a leading-dot identity is refused because it would be invisible to every scan that skips hidden files (test `hiddenDirectoryIdentityIsRefused`) |
| vsix-installer-018 | identity-fields-validated | `install(archive:...)` against a manifest with `version: "1.0.0-beta.1+build.7"` | Succeeds; installed directory is `acme.widget-1.0.0-beta.1+build.7` — an unusual but safe version is not refused (test `prereleaseVersionStillInstalls`) |
| vsix-installer-019 | destination-containment-double-checked | `install(archive:...)` where `installDirectory` is reached through a `/private`-rooted path (e.g. `/private/var/folders/...`) | Succeeds; installed directory is `acme.widget-1.0.0` — the belt-and-braces containment check does not misfire on an existing, real `/private` root (test `aPrivateRootedInstallDirectoryStillInstalls`) |
| vsix-installer-020 | destination-containment-double-checked | Same `/private`-rooted `installDirectory`, but `name: "escape"`, `publisher: ".."` | Throws; nothing written — the containment check still refuses a climbing name from a `/private` root (test `aClimbingNameIsStillRefusedFromAPrivateRoot`) |
| vsix-installer-021 | move-into-place-atomicity, move-into-place-rollback | A move into an existing `acme.widget-1.0.0` fails (injected `FileManager` refuses the move) | Throws `VSIXInstallError.couldNotInstall`; no `.`-prefixed entry remains; `acme.widget-1.0.0` is restored whole, including `theme.json` (test `aFailedMoveRestoresThePreviousVersion`) |
| vsix-installer-022 | move-into-place-atomicity | A first install (no prior version) fails to move into place | Throws `VSIXInstallError.couldNotInstall`; `installDirectory` is completely empty afterward, including no hidden entries (test `aFailedFirstInstallLeavesNothing`) |
| vsix-installer-023 | supersede-non-fatal-removal | A superseded `acme.widget-1.0.0` cannot be removed (injected `FileManager` refuses the removal) while installing `acme.widget` 2.0.0 | Succeeds; `installation.version == "2.0.0"`; `supersededDirectories` names `acme.widget-1.0.0`, which is still present on disk alongside `acme.widget-2.0.0` (test `anUnremovableSupersededCopyStillInstalls`) |
| vsix-installer-024 | recovery-sweep-scope | `recoverInterruptedInstalls()` where `.acme.widget-1.0.0.replacing-<uuid>` exists and `acme.widget-1.0.0` does not | Restores the aside to `acme.widget-1.0.0`, whole; the aside no longer exists (test `anInterruptedReplacementIsPutBack`) |
| vsix-installer-025 | recovery-sweep-scope | `recoverInterruptedInstalls()` where both `.acme.widget-1.0.0.replacing-<uuid>` and a live `acme.widget-1.0.0` (marked with `marker.txt`) exist | Discards the aside; the live directory (with `marker.txt`) is untouched (test `aSupersededAsideIsDiscarded`) |
| vsix-installer-026 | recovery-non-aside-entries-untouched | `recoverInterruptedInstalls()` where a `.DS_Store` file exists in `installDirectory` | Returns an empty recovered list; `.DS_Store` remains exactly as it was (test `anUnrelatedHiddenEntryIsLeftAlone`) |
| vsix-installer-027 | recovery-runs-before-scan | `install(archive:...)` for `acme.widget` 2.0.0 where `.acme.widget-1.0.0.replacing-<uuid>` exists as a crash-orphaned aside | Succeeds; exactly one directory, `acme.widget-2.0.0`, remains — the stranded 1.0.0 is recovered and then superseded, not left as a second, hidden copy (test `installingRunsTheRecoverySweep`) |
| vsix-installer-028 | move-into-place-rollback | A move into an existing `acme.widget-1.0.0` fails, and the rollback move (from the aside) also fails | Throws `VSIXInstallError.couldNotInstall` whose reason contains `"could not be put back"` and the aside's `.acme.widget-1.0.0.replacing-` name; exactly one hidden aside entry remains on disk (test `aFailedRollbackSaysWhereTheCopyIs`) |
| vsix-installer-029 | signature-pair-completeness | `install(_:using:)` against a registry record naming a `signature` and no `publicKey` | Throws `VSIXInstallError.verificationIncomplete(published: "signature", missing: "publicKey")`; nothing installed (test `signatureWithoutAKeyIsRefused`) |
| vsix-installer-030 | signature-pair-completeness | `install(_:using:)` against a registry record naming a `publicKey` and no `signature` | Throws `VSIXInstallError.verificationIncomplete(published: "publicKey", missing: "signature")`; nothing installed (test `keyWithoutASignatureIsRefused`) |
| vsix-installer-031 | registry-install-order, signature-pair-completeness | `install(_:using:)` against a registry record naming only a `signature` (no key) | The `.vsix` artifact URL is never requested — the refusal is decided from metadata before any download (test `incompleteRecordIsRefusedBeforeTheDownload`) |
| vsix-installer-032 | blocking-verification-hop, installation-record-shape | `install(_:using:)` against a record naming a matching digest, a valid signature, and the registry's own key | Succeeds; `installation.verification.signature == .registryAttested`; `installation.verification.digest == .matched` — not `.verified`, since only registry attestation, not publisher identity, was proved (test `signedInstallRecordsRegistryAttestation`) |
| vsix-installer-033 | artifact-fetched-only-if-named | `install(_:using:)` against a record naming neither `sha256`, `signature`, nor `publicKey` | Succeeds; `installation.verification.signature == .notPublished`; `installation.verification.digest == .notPublished` (test `unsignedInstallSaysSo`) |
| vsix-installer-034 | artifact-fetched-only-if-named | `install(_:using:)` against a record naming only `sha256`, matching the archive | Succeeds; `installation.verification.digest == .matched`; `installation.verification.signature == .notPublished` — distinguishable from a version with no digest at all (test `aMatchedDigestIsNotTheSameAsNoDigest`) |

## Edge Cases

- **Null and empty input**: An empty, absent, or unreadable `package.json`
  MUST be refused as `manifestUnreadable` or `manifestMalformed` before any
  identity check runs (`manifest-unreadable`, `manifest-malformed`). An empty
  `manifest.identifier` or `manifest.version` MUST be refused by
  `identity-fields-validated`'s `ExtensionIdentityComponent.isSafe` empty-value
  rule, never reaching `directoryName`.
- **Boundary values**: A directory-name component that is safe but unusual —
  a pre-release version such as `1.0.0-beta.1+build.7` — MUST still install,
  distinguishing the identity guard's actual target (path-unsafe shapes) from
  merely unfamiliar ones (`identity-fields-validated`; test
  `prereleaseVersionStillInstalls`). An `installDirectory` reached through a
  `/private`-rooted path, where the directory exists but its intended child
  does not yet, MUST still install and MUST still refuse a climbing name from
  that same root (`destination-containment-double-checked`; tests
  `aPrivateRootedInstallDirectoryStillInstalls`,
  `aClimbingNameIsStillRefusedFromAPrivateRoot`).
- **Concurrent access**: The open question on `concurrent-install-ordering` —
  two `install(archive:...)` calls sharing one `installDirectory`, overlapping
  in time, have no documented ordering, mutual exclusion, or detection of the
  overlap; each independently runs its own recovery sweep, supersede scan, and
  `moveIntoPlace`, against the same directory tree.
- **Malformed input (hostile manifest fields)**: `identifier` or `version`
  values that climb out of `installDirectory` with `../` sequences, that name
  an absolute path, or that begin with a `.` (hiding the resulting directory
  from every scan that skips hidden files) MUST be refused by
  `identity-fields-validated` before any path is built, and the resulting
  destination's actual resolved location MUST also be refused by
  `destination-containment-double-checked` even if it somehow slipped past the
  first check — because `moveIntoPlace` finishes with a rename that resolves
  `..` in the kernel, past anything Foundation-level string checking would see
  (tests `hostileVersionIsRefused`, `hostileNameIsRefused`,
  `absolutePathIdentityIsRefused`, `hiddenDirectoryIdentityIsRefused`).
- **Error states (file system refuses partway through)**: A move into an
  existing destination that fails MUST attempt a rollback and MUST report,
  distinctly, whether that rollback itself succeeded or failed
  (`move-into-place-rollback`). A move into a destination with no existing
  copy that fails MUST leave nothing behind, hidden or otherwise
  (`move-into-place-atomicity`; test `aFailedFirstInstallLeavesNothing`). A
  superseded directory that cannot be removed MUST NOT fail an otherwise
  successful install (`supersede-non-fatal-removal`).
- **Error states (dependency unavailable)**: On the registry path, a
  network-level failure fetching the archive, the digest, the signature, or
  the public key MUST propagate as `OpenVSXClient`'s own thrown error type,
  before any verification or file-system step in this component begins. This component defines no retry, timeout, or cancellation of its
  own around that download; the effective behavior is whatever `client`
  provides (absence of any retry, timeout, or `Task` cancellation handling
  anywhere in `install(_:using:)`).
- **Crash / power-loss recovery**: A power interruption between the two
  renames of `moveIntoPlace` MUST be recoverable by the next call to
  `recoverInterruptedInstalls()` (which every `install(archive:...)` call runs
  first): the surviving aside is restored to its own name if the destination
  is empty, or discarded if the destination is already occupied
  (`recovery-sweep-scope`; tests `anInterruptedReplacementIsPutBack`,
  `aSupersededAsideIsDiscarded`, `installingRunsTheRecoverySweep`). An
  ordinary hidden entry that merely begins with a dot but does not match the
  aside naming convention MUST be left untouched by that same sweep
  (`recovery-non-aside-entries-untouched`; test
  `anUnrelatedHiddenEntryIsLeftAlone`).
- **Offline / disconnected state**: For `install(archive:...)`, there is no
  network dependency at all — the archive bytes are already in the caller's
  hand — so connectivity loss cannot occur mid-operation on that path. For
  `install(_:using:)`, connectivity lost during the archive, digest,
  signature, or key download surfaces as whatever error
  `OpenVSXClient`'s underlying `URLSession` produces, before this component
  writes anything to disk (same citation as the dependency-unavailable case
  above).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `installDirectory` | `URL` | none (required) | Where installs land and are scanned for superseded copies; injected rather than derived. |
| `hostVersion` | `SemanticVersion` | `ExtensionRegistry.declaredVSCodeVersion` (`1.138.0`) | The VS Code engine version an archive's `engines.vscode` range is checked against. |
| `fileManager` | `@Sendable () -> FileManager` | `{ .default }` | File-system seam; a test substitutes a `FileManager` subclass that refuses a named move or removal. |
| `detail` (`install(_:using:)` parameter) | `OpenVSXExtensionDetail` | none (required) | The registry record naming the version, its download URL, and its verification artifacts. |
| `client` (`install(_:using:)` parameter) | `OpenVSXClient` | none (required) | How the archive and verification artifacts are fetched from the registry. |
| `archive` (`install(archive:...)` parameter) | `Data` | none (required) | The `.vsix` bytes already in hand. |
| `verification` (`install(archive:...)` parameter) | `VSIXVerification` | none (required) | What the bytes were already proved to be, computed by `VSIXArchive.verify` before this call. |
| `expectedIdentifier` (`install(archive:...)` parameter) | `String?` | `nil` | The identity a registry source claimed for the archive; `nil` when there is no claim to check (a user-supplied file). |
| `source` (`install(archive:...)` parameter) | `VSIXInstallation.Source` | none (required) | Whether this installation's provenance is recorded as `.registry` or `.localFile`. |

## Deep Linking

Not applicable: `VSIXInstaller.swift` defines no URL scheme, route, or
navigable destination of any kind — it installs files onto disk and returns a
`VSIXInstallation` value, and declares no navigation surface (traced to the
full source, which contains no route or scheme type).

## Localization

Not applicable: the source declares no user-facing string literal of its own.
`VSIXInstallError`'s cases carry structured data — field names, claimed and
found values, and an underlying error's `localizedDescription` — rather than
authored display text, and the two log messages in the source are
developer-facing diagnostics, not strings a person using the app would read. Separately, `readManifest(in:)`
does call `ExtensionManifestLocalization.localize(_:forManifestIn:)` to
resolve `%key%` placeholders in the *extension being installed*'s own
manifest before decoding it — but that localizes the archive's content, not
any string this component itself displays.

## Accessibility Options

Not applicable: this is a non-visual file-system installer with no rendered
UI to respond to Reduce Motion, Increase Contrast, or Differentiate Without
Color (traced to the full source, which contains no UI code of any kind).

## Feature Flags

Not applicable: the source declares no feature-flag or configuration-flag
lookup — every call to `install(_:using:)`, `install(archive:...)`, or
`recoverInterruptedInstalls()` runs the same fixed logic unconditionally
(traced to the absence of any flag check anywhere in the source).

## Analytics

Not applicable: the source contains no event-emission or telemetry call of
any kind — a successful install returns a `VSIXInstallation` value and a
failure throws a `VSIXInstallError`, with no recorded event either way
(traced to the full body of the source file).

## Privacy

- **Data collected**: `VSIXInstaller` collects nothing beyond what the caller
  already supplies as arguments — the archive bytes, the registry's metadata
  fields it is given (`detail`), and whatever `expectedIdentifier`/`source` the
  caller passes. It reads no field from the archive's manifest that it did
  not already need for the checks above (identifier, version, `engines.vscode`,
  `displayName`, `browser`, `main`).
- **Storage**: The extension's expanded payload is written, unencrypted, as
  ordinary files under `installDirectory` — a persistent, caller-chosen
  location, typically `~/Library/Application Support/<App>/Extensions` in the
  shipping app (doc comment). A superseded copy and, briefly, a
  crash-orphaned aside are also written there under a hidden name before being
  removed.
- **Transmission**: `VSIXInstaller` itself makes no network request; on the
  registry path, `install(_:using:)` calls into `OpenVSXClient` to fetch the
  archive and its verification artifacts, so whatever `OpenVSXClient`'s own
  Privacy section states about that transmission applies here as well.
- **Retention**: The installed directory persists until a later install
  supersedes it (`supersede-by-manifest-identity`) or a caller elsewhere in the
  app removes it; `VSIXInstaller` sets no expiry or retention policy of its
  own on anything it writes.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default) |
Category: `VSIXInstaller`

| Event | Level | Message |
|-------|-------|---------|
| A superseded directory was left on disk because it could not be removed after an otherwise successful install | warning | `Installed <identifier> but could not remove the superseded copy at <path>: <reason>` |
| `moveIntoPlace`'s rollback (moving the aside back to `destination`) failed after the payload move into `destination` had also failed | error | `Could not put the previous <destination.lastPathComponent> back from <aside.lastPathComponent>: <reason>` |
| `recoverInterruptedInstalls()` failed to restore or discard a crash-orphaned aside | error | `Could not finish the interrupted replacement of <replaced>: <reason>` |

## Platform Notes

- **SwiftUI**: Source:
  `packages/apple/AgenticToolkit/Core/Extensions/VSIXInstaller.swift`, its
  verification and expansion in `Core/Extensions/VSIXArchive.swift`, its
  identity and containment guards in `Core/Extensions/
  ExtensionIdentityComponent.swift` and `Core/Extensions/
  ExtensionResourcePath.swift`, its manifest decode in `Core/Extensions/
  ExtensionManifest.swift`, and its blocking-work hop in `Core/Concurrency/
  BlockingWork.swift`. The type is plain `Foundation`/`OSLog` with no SwiftUI
  dependency; a SwiftUI-hosted extensions panel calls either `install`
  overload with `async`/`await` from a `Task` and renders the returned
  `VSIXInstallation` or caught `VSIXInstallError` into its own `@State`/
  `@Observable` view state — `VSIXInstaller` itself holds none.
- **Compose**: On Kotlin/Android, port to a class exposing
  `suspend fun install(detail: OpenVsxExtensionDetail, using: OpenVsxClient):
  VsixInstallation` and a synchronous
  `fun install(archive: ByteArray, verification: VsixVerification,
  expectedIdentifier: String?, source: VsixInstallation.Source):
  VsixInstallation`. Run the synchronous half — hashing, unzip, and the
  move-and-rollback sequence — with `withContext(Dispatchers.IO)` rather than
  the default coroutine dispatcher, mirroring why `BlockingWork` exists: IO
  threads are the pool that is allowed to block. Reuse the ported
  `ExtensionIdentityComponent.isSafe` and a `File`-based containment check
  (`canonicalFile` compared by path-segment prefix, not string prefix) before
  either becomes a path. `File.renameTo` is the closest analogue to `rename(2)`
  for the atomic swap, but is documented as platform- and filesystem-dependent
  on Android, so a port should verify it behaves atomically within the target
  storage volume or fall back to copy-then-delete-old with the same aside
  convention if not.
- **React/Web**: There is no local file system to install into in a browser
  context, so a literal port has no destination; where this runs inside an
  Electron-style host with Node's `fs` module available, port to an `async
  function install(archiveBytes: Uint8Array, verification: VsixVerification,
  expectedIdentifier: string | null, source: VsixInstallationSource):
  Promise<VsixInstallation>`. Use `fs.promises.rename` for the atomic swap
  (POSIX `rename(2)` semantics on the same volume), a zip library with
  path-traversal and symlink protection equivalent to `ditto`'s (many
  JavaScript zip libraries do not refuse a traversing or symlink-escaping
  entry by default and would need an explicit per-entry path check), and
  reuse the ported `isSafe` and a `path`-segment containment check before any
  extracted or joined path is used.
- **AppKit / UIKit**: No divergence from the SwiftUI bullet above — the
  source is framework-agnostic `Foundation` code, callable identically from an
  AppKit-hosted (macOS) or UIKit-hosted (iOS) caller. `AgenticToolkitCore`, the
  framework target that builds this file, is configured `platform: macOS` in
  `packages/apple/AgenticToolkit/project.yml` today, so an iOS caller would
  first need the type made available to an iOS target; `VSIXInstaller` itself
  needs no AppKit/UIKit-specific change to run there.
- **WinUI 3**: Port to a class exposing `async Task<VsixInstallation>
  InstallAsync(OpenVsxExtensionDetail detail, OpenVsxClient client)` and a
  synchronous `VsixInstallation Install(byte[] archive, VsixVerification
  verification, string? expectedIdentifier, VsixInstallationSource source)`.
  Offload the synchronous half onto `Task.Run`, which is a reasonable
  counterpart to `BlockingWork` here even though .NET's thread pool grows to
  accommodate blocking work rather than being a fixed cooperative pool — the
  concern is milder, not absent, since a large enough number of concurrently
  blocking `Task.Run` calls still exhausts the pool before it can grow. Hash
  with `System.Security.Cryptography.SHA256`; .NET has no built-in Ed25519
  verifier as of this writing, so the signature check ported from
  `VSIXArchive.verify` needs a third-party library (for example `NSec.
  Cryptography` or a `libsodium` binding) rather than a framework type.
  Extract the archive with `System.IO.Compression.ZipFile.ExtractToDirectory`
  or an equivalent, but note it does **not** refuse a `../`-escaping or
  symlink-escaping zip entry the way `ditto -x -k` does — a port needs an
  explicit per-entry destination-containment check before extraction, not
  merely a check on the final tree. Decode the manifest with `System.Text.
  Json`'s `JsonSerializer.Deserialize` against a matching record type. Port
  `ExtensionIdentityComponent.IsSafe` and call it on both the identifier and
  the version before either reaches `Path.Combine` — which, like
  `appendingPathComponent`, performs no escaping of its own. Use
  `System.IO.Directory.Move` for the aside-then-swap sequence; it is a rename
  within one NTFS volume and shares `rename(2)`'s all-or-nothing character
  there, but throws `IOException` across volumes rather than completing, so a
  port should confirm both directories live under one volume the way this
  source implicitly relies on `installDirectory` and its parent doing. No
  `ObservableCollection` or `INotifyPropertyChanged` belongs on this type
  itself, since it has no UI-observable state of its own — those apply only to
  whatever ViewModel wraps calls into it.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/Extensions/VSIXInstaller.swift` |

## Design Decisions

**Decision**: Move an existing `destination` directory aside before moving the
new payload in, rather than deleting the old copy first.
**Rationale**: A failure during the second move can then restore the first;
deleting the old copy first would leave the user with neither version if the
second move then failed — the one outcome that would make an update button
unsafe to press (doc comment; `moveIntoPlace`).
**Approved**: pending

**Decision**: Check destination containment twice — once as a predicate over
the identifier and version strings (`ExtensionIdentityComponent.isSafe`), once
as a fact about the actual resolved destination path
(`ExtensionResourcePath.canonicalChild`/`url(isContainedIn:)`).
**Rationale**: The two checks fail for different reasons. A future change to
`directoryName(identifier:version:)` that joined its parts differently would
slip straight past the string-level predicate and still be caught by the
path-level check, which is closer to what `moveIntoPlace`'s underlying
`rename(2)` actually resolves.
**Approved**: pending

**Decision**: Canonicalize the install directory's *parent*, which exists,
and append the new component to that — rather than canonicalizing the full,
not-yet-existing destination path.
**Rationale**: `resolvingSymlinksInPath()` drops a leading `/private` only
when what remains still names something real. The version of this guard that
canonicalized the whole destination refused every ordinary install into an
extensions folder reached through `/private` (a macOS temporary directory, or
a home on another volume) with `unsafeIdentity`, naming a perfectly ordinary
`<publisher>.<name>-<version>` (`ExtensionResourcePath.swift`; test `aPrivateRootedInstallDirectoryStillInstalls`).
**Approved**: pending

**Decision**: Match superseded directories by decoding each candidate's own
`package.json` and comparing its `identifier`, never by matching the
candidate's folder name against a naming convention.
**Rationale**: A hand-installed extension or a dev checkout is named however
its author named it, and those are exactly the copies whose survival would
shadow the extension just installed if the sweep trusted names instead of
content (doc comment; test `supersedesAHandNamedDirectory`).
**Approved**: pending

**Decision**: Report the failure of a rollback (moving the aside back after
the new payload's move also failed) as a distinct outcome from the original
move failure, rather than the same `try?`-discarded error both used to share.
**Rationale**: The thrown error used to carry only the original failure's
reason, so the one outcome this whole aside-and-swap dance exists to
prevent — the user left with no version of the extension at all — was
reported in exactly the same words as the safe outcome where the previous
version simply went back. The aside's own name is included because a person
can move it back by hand and nothing else on disk says where it went.
**Approved**: pending

**Decision**: Let a superseded copy that cannot be removed, and a
crash-recovery aside that cannot be restored or discarded, fail quietly (a
logged warning or error) rather than fail the calling operation.
**Rationale**: In both cases the alternative on-disk state is already
correct, or already the best available outcome, by the time the failure
happens — the new version is installed and loadable, or the aside is still
the only surviving copy and deleting it would turn a recoverable state into
an unrecoverable one. Throwing would report an install that succeeded (or a
recovery that did the safe thing) as having failed.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | Reliability |

`separation-of-concerns` passes because `VSIXInstaller` delegates every
concern it does not own: byte verification and archive expansion to
`VSIXArchive`, identity-component safety to `ExtensionIdentityComponent`,
destination containment to `ExtensionResourcePath`, engine-range parsing to
`VSCodeEngineRange`, manifest decoding and localization to `ExtensionManifest`
and `ExtensionManifestLocalization`, and the blocking-thread hop to
`BlockingWork` — keeping its own code to ordering those calls and to the
move-and-rollback sequence that is genuinely its own (`registry-install-order`,
Overview). `unit-test-coverage` passes: roughly 40 test functions across
`VSIXInstallerTests.swift`, `VSIXInstallerFileSystemFailureTests.swift`, and
`VSIXRegistryInstallTests.swift` exercise the happy path, every
`VSIXInstallError` case, every hostile-identity shape, both halves of a
move-and-rollback failure, the crash-recovery sweep in both directions, and
every registry signature-completeness combination. `explicit-error-handling`
is partial: every checked failure raises a specific `VSIXInstallError` case
rather than returning `nil` or failing silently — with the documented
exceptions that `otherInstallDirectories` silently skips (via `try?`) any
candidate directory whose manifest cannot be read or decoded, treating it as
simply not a match rather than as a reportable problem, and that a superseded
directory's removal failure and a crash-recovery aside's restore failure are
communicated only through a log line, never through the returned or thrown
value (`supersede-by-manifest-identity`, `supersede-non-fatal-removal`,
`recovery-failure-logged`). `input-sanitization` passes: `identity-fields-
validated` and `destination-containment-double-checked` refuse a manifest's
`identifier` or `version` before either becomes a path component, on every
install path, using two independently-failing checks. `fault-tolerance`
passes: a failed move restores the previous version whenever one existed, a
failed rollback is reported as its own distinct outcome rather than masked, a
crash between the two renames of a replace is recoverable on the next call,
and an unremovable superseded copy does not turn a successful install into a
reported failure (`move-into-place-rollback`, `recovery-sweep-scope`,
`supersede-non-fatal-removal`). `idempotent-operations` passes: reinstalling
the same identifier and version succeeds and leaves exactly one directory
rather than erroring or duplicating, and `recoverInterruptedInstalls()` is
safe to call whether or not a crash actually happened (`reinstall-idempotent`,
`recovery-idempotent`). `data-integrity` passes: on the registry path, the
archive's digest and signature are checked against what the registry itself
published before any byte is written, the archive's own `engines.vscode` is
checked against the host even when the registry's separate metadata already
implied compatibility, and a registry's identity claim is checked against the
archive's own manifest rather than trusted (`signature-pair-completeness`,
`engine-range-checked`, `identity-claim-checked`).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
