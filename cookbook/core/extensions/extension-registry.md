---
id: 4b6f3e1a-9c2d-4e7a-8b3f-1d5a6c9e2f70
title: Extension Registry
domain: agentictoolkit://cookbook/core/extensions/extension-registry
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "Discovers VS Code extension manifests from disk, gates them by declared engine\
  \ compatibility, and drives their contributions through registered ContributionPoints."
platforms:
- swift
- macos
tags:
- extensions
- extension-registry
- registry
- mainactor
- contribution-point
depends-on:
- agentictoolkit://cookbook/core/extensions/contribution-point
- agentictoolkit://cookbook/core/extensions/extension-manifest
related:
- agentictoolkit://cookbook/core/extensions/contribution-point
- agentictoolkit://cookbook/core/extensions/extension-manifest
- agentictoolkit://cookbook/core/extensions/contributed-views
- agentictoolkit://cookbook/core/extensions/contributed-settings
- agentictoolkit://cookbook/core/extensions/activation-event-matcher
- agentictoolkit://cookbook/ai-plugin-kit/ai-plugin-manager
references: []
approved-by: ''
approved-date: ''
---

# Extension Registry

## Overview

`ExtensionRegistry.swift` (`packages/apple/AgenticToolkit/Core/Extensions/ExtensionRegistry.swift`) defines `ExtensionRegistry`, the `@MainActor` class that discovers VS Code extensions from disk, gates each one by its declared `engines.vscode` compatibility against the host's `declaredVSCodeVersion`, and drives their `contributes.*` blocks through whatever `ContributionPoint`s the host has registered. Discovery reads only each extension's `package.json` manifest; it never opens the extension's `main`/`browser` JavaScript entry point and never `dlopen`s anything, because a VS Code extension's JavaScript is not something this host runs — a bad or malicious manifest can therefore only ever produce a load failure, never code execution. The file is modeled on `AIPluginManager` (`AIPluginKit/AIPluginManager.swift`), and search paths are injected by the caller rather than derived internally, exactly as `AIPluginManager`'s test-only initializer takes them. `ExtensionRegistry` also owns enablement (`isEnabled`/`setEnabled`, backed by `UserSettings.disabledExtensionIdentifiers`) and uninstall (`uninstall(_:)`), and it publishes `establishedIdentifiers`, a tri-state answer — the set of every identifier this scan can vouch for, or `nil` when the scan is not whole — that a caller uses to decide whether it is safe to prune orphaned, persisted state (for example, deleted themes) for extensions no longer found on disk.

## Behavioral Requirements

- **declared-vscode-version**: `ExtensionRegistry.declaredVSCodeVersion` MUST be the constant `SemanticVersion(major: 1, minor: 138, patch: 0)`, the last VS Code API surface version the host's `VSCodeAPI` adaptors were written against.
- **declared-version-nonisolated**: `declaredVSCodeVersion` MUST be `nonisolated static let` even though the enclosing class is `@MainActor`, because it is a constant, not mutable state, and a caller reading it MUST NOT be required to hop to the main actor.
- **initializer-injected-search-paths**: `init(searchPaths:hostVersion:)` MUST accept `searchPaths: [URL]` and `hostVersion: SemanticVersion` as caller-supplied values, deriving neither internally.
- **register-before-load-all**: `register(_:)` MUST append the given `ContributionPoint` to the registry's list of registered points; a point registered after `loadAll()` has already run MUST NOT have `apply` replayed against it for extensions loaded before its registration.
- **load-all-never-throws**: `loadAll()` MUST NOT throw; every per-extension failure MUST be recorded in `failures` rather than propagated, so one bad extension does not prevent any other extension in the same scan from loading.
- **load-all-resets-state**: `loadAll()` MUST withdraw every currently loaded extension's contributions from every registered `ContributionPoint` before rebuilding `extensions` and `failures`, so a second call does not leave a contribution installed twice while the registry's own bookkeeping reports it once.
- **scan-existing-search-paths-only**: A `searchPaths` entry that does not exist on disk MUST be skipped with no failure recorded and `readEverything` left `true` for that entry, per `Scan.scan(searchPaths:hostVersion:)`'s check that `fileManager.fileExists(atPath:)` is false before treating a directory-listing failure as incomplete.
- **scan-unreadable-search-path-marks-incomplete**: A `searchPaths` entry that exists on disk but whose contents cannot be listed (for example, a permissions failure) MUST set `Scan.readEverything` to `false` for that scan.
- **scan-unresolvable-entry-type-marks-incomplete**: A directory entry whose `isDirectoryKey` resource value cannot be read MUST set `Scan.readEverything` to `false`, and MUST NOT be treated as either a manifest candidate or an ordinary file.
- **scan-directories-only**: A directory entry whose type resolves and is not a directory MUST be skipped with no effect on `readEverything`.
- **scan-sorted-directory-order**: Within one search path, candidate directories MUST be visited in ascending order of `lastPathComponent` (`String` `<`), never in the order `FileManager.contentsOfDirectory` returns.
- **scan-search-path-order-preserved**: Directories from an earlier entry in `searchPaths` MUST be scanned, and MUST claim a contested identifier, before any directory from a later entry.
- **manifest-missing-is-not-a-failure**: A candidate directory with no `package.json` MUST produce no entry in `Scan.directories` at all — neither a loaded extension nor a failure.
- **manifest-unreadable-failure**: A `package.json` that exists but cannot be read as `Data` MUST produce a `Scan.Outcome.failed(.manifestUnreadable(_), identifier: nil)` entry.
- **jsonc-tolerance**: `package.json` bytes MUST be passed through `JSONCPreprocessor.jsonData(from:)` before decoding, so line comments, block comments, a trailing comma, and a leading BOM in the file all decode successfully.
- **manifest-localization-applied-before-decode**: `package.json` bytes MUST be passed through `ExtensionManifestLocalization.localize(_:forManifestIn:)` before the JSONC preprocessor and the `ExtensionManifest` decode, so an `%nlsKey%`-style placeholder resolves against `package.nls.json` in the same directory before any string reaches `ExtensionManifest`.
- **manifest-malformed-failure-with-recovered-identifier**: A `package.json` that decodes as JSONC but fails `JSONDecoder().decode(ExtensionManifest.self, from:)` MUST produce `Scan.Outcome.failed(.manifestMalformed(_), identifier:)`, where `identifier` is `ExtensionRegistry.identifier(inRawManifest:)`'s best-effort recovery of `publisher.name` (or bare `name` when no `publisher` key is present) read directly out of the raw bytes via `JSONSerialization`, lower-cased, or `nil` when even `name` cannot be read.
- **engine-range-unparsable-failure**: A manifest that decodes successfully but whose `engines.vscode` string does not parse as a `VSCodeEngineRange` MUST produce `Scan.Outcome.failed(.engineRangeUnparsable(manifest.engines.vscode), identifier: manifest.identifier)`.
- **engine-incompatible-failure**: A manifest whose `VSCodeEngineRange.accepts(hostVersion)` returns `false` MUST produce `Scan.Outcome.failed(.engineIncompatible(required: manifest.engines.vscode, host: hostVersion.description), identifier: manifest.identifier)`.
- **duplicate-identifier-first-wins**: When two directories in one `loadAll()`/`apply(_:)` pass decode manifests with the same `ExtensionManifest.identifier`, the directory visited first (per scan-sorted-directory-order and scan-search-path-order-preserved) MUST be loaded into `extensions`, and every subsequent directory claiming the same identifier MUST instead produce `.duplicateIdentifier(existing: <winner's path>)` recorded against the losing directory.
- **loaded-extension-logged**: Every directory whose manifest decodes, passes the engine gate, and claims a not-yet-claimed identifier MUST be appended to `extensions` as a `LoadedExtension`, and an info-level log line naming the identifier and the directory path MUST be emitted.
- **contributes-absent-becomes-empty**: A manifest whose `contributes` key is absent MUST still be applied to every registered `ContributionPoint`, passing `ExtensionManifest.Contributions.empty` rather than skipping the call, so "declares nothing" and "no `contributes` key" are indistinguishable to a contribution point.
- **apply-only-for-enabled-extensions**: `apply(_ scan:)` MUST call `applyContributions` for a loaded extension's identifier only when `isEnabled(loaded.identifier)` is `true` at the time of the call.
- **contribution-point-error-isolated**: When one registered `ContributionPoint`'s `apply(_:from:at:)` throws while applying one extension's contributions, `applyContributions(_:from:at:)` MUST catch the error, log it at error level naming the point's `contributionKey` and the extension's identifier, record an `ExtensionLoadFailure` with `reason: .contributionPointFailed(key:message:)` (using `String(describing: error)`, not `localizedDescription`) and `identifier: manifest.identifier`, and MUST continue calling `apply` on every remaining registered point for the same extension; the extension MUST remain in `extensions`.
- **contribution-failures-cleared-before-reapply**: `applyContributions(_:from:at:)` MUST remove every existing `contributionPointFailed` failure entry for the extension's directory (via `removeContributionFailures(at:)`) before calling `apply` on any registered point, so a re-enable through `setEnabled` does not accumulate duplicate failure entries for the same refusal.
- **notify-after-load-all**: `loadAll()` MUST call every registered contributions-observer handler exactly once, after `apply(_:)` has finished rebuilding `extensions`, `failures`, and every contribution point's state — never before, and never once per extension.
- **observers-called-in-subscription-order**: `notifyContributionsDidChange()` MUST call every registered observer's handler in the order `addContributionsObserver(_:)` added it, iterating over a copy of the observer list so a handler that adds or removes an observer from within itself affects only the next notification.
- **observer-token-idempotent-removal**: `removeContributionsObserver(_:)` MUST be safe to call with a token that was never registered, or one already removed, with no error and no effect on the remaining observers.
- **reload-off-main-actor-scan**: `reload()` (no arguments) MUST perform the directory-enumeration-and-decode work of `Scan.scan(searchPaths:hostVersion:)` off the main actor, via `BlockingWork.run(qos: .userInitiated)`, while every state mutation of the registry itself (withdrawing and reapplying contributions, and firing observers) MUST run on the main actor.
- **reload-keeps-old-contributions-during-scan**: During `reload()`'s in-flight scan, the previously applied contributions MUST remain installed and MUST NOT be withdrawn until `apply(_:)` runs after the scan returns.
- **reload-generation-drops-superseded-results**: `reload(performing:)` MUST increment `reloadGeneration` before starting its scan and capture that value; when the scan returns, if `reloadGeneration` no longer equals the captured value (a later `reload` call started and is still in flight or has already applied), the returned scan result MUST be discarded (logged at debug level) and MUST NOT be passed to `apply(_:)`.
- **load-all-also-bumps-generation**: `loadAll()` MUST increment `reloadGeneration` before scanning synchronously, so a `reload()` already in flight when `loadAll()` runs has its eventual result dropped as superseded.
- **is-enabled-default-true**: `isEnabled(_:)` MUST return `true` for any identifier not present (case-insensitively) in `UserSettings.disabledExtensionIdentifiers.value`; disabled state, not enabled state, is what is persisted.
- **is-enabled-case-insensitive**: `isEnabled(_:)` MUST fold both the argument and every persisted entry in `UserSettings.disabledExtensionIdentifiers.value` to lower case before comparing, so a persisted entry written in a different case than the argument still matches.
- **set-enabled-no-op-on-unchanged-state**: `setEnabled(_:for:)` MUST do nothing at all — no write to `UserSettings.disabledExtensionIdentifiers`, no call to any `ContributionPoint`, no observer notification — when the requested `enabled` value equals `isEnabled(identifier)`'s current answer.
- **set-enabled-migrates-persisted-casing**: When `setEnabled(_:for:)` does change state, it MUST remove every case-insensitive match of `identifier` from `UserSettings.disabledExtensionIdentifiers.value` and, if disabling, insert exactly the lower-cased form, so the persisted set converges toward one canonical casing per identifier over successive toggles.
- **set-enabled-drives-contribution-points**: When `setEnabled(_:for:)` changes an already-loaded extension's enabled state, enabling MUST call `applyContributions` for it (passing `.empty` if its manifest has no `contributes`), and disabling MUST call `withdraw(extensionIdentifier:)` on every registered point and then `removeContributionFailures(at:)` for its directory.
- **set-enabled-unloaded-identifier-persists-only**: `setEnabled(_:for:)` for an identifier not present in `extensions` MUST still update `UserSettings.disabledExtensionIdentifiers`, but MUST NOT call any `ContributionPoint` and MUST NOT fire the contributions-observer notification.
- **set-enabled-notifies-only-on-change**: `setEnabled(_:for:)` MUST call `notifyContributionsDidChange()` only after it has actually changed the enabled state of an extension that is currently loaded; the no-op case and the unloaded-identifier case MUST NOT notify.
- **uninstall-deletes-then-updates-memory**: `uninstall(_:)` MUST call `FileManager.default.removeItem(at:)` on the extension's directory before removing it from `extensions`, withdrawing its contributions from every registered point, clearing its `contributionPointFailed` entries, and removing it from `UserSettings.disabledExtensionIdentifiers`; if the delete throws, `uninstall(_:)` MUST propagate that error and MUST leave `extensions`, `failures`, every contribution point's state, and the disabled-identifiers set completely unchanged.
- **uninstall-unknown-identifier-is-a-no-op**: `uninstall(_:)` for an identifier not present (case-folded) in `extensions` MUST return without throwing, without touching the file system, and without any other side effect.
- **uninstall-notifies-once**: A successful `uninstall(_:)` MUST call `notifyContributionsDidChange()` exactly once, after every other state change it performs.
- **established-identifiers-nil-when-incomplete**: `establishedIdentifiers` MUST be `nil` whenever `scanReadEverything` is `false`, regardless of the contents of `extensions` or `failures`.
- **established-identifiers-nil-on-unnameable-failure**: `establishedIdentifiers` MUST be `nil` whenever any entry in `failures` has `identifier == nil`, even if `scanReadEverything` is `true`.
- **established-identifiers-union**: When neither condition above applies, `establishedIdentifiers` MUST return the union of every loaded extension's identifier and every failure's non-nil identifier, as a `Set<String>`.
- **established-identifiers-initial-state**: A newly constructed `ExtensionRegistry` on which `loadAll()`/`reload()` has never been called MUST report `establishedIdentifiers == nil`, because `scanReadEverything` starts `false`.
- **contribution-registrations-not-part-of-registry-state**: `ExtensionRegistry` itself MUST hold no `ContributionRegistrations` value; per-point bookkeeping of what was applied belongs to each `ContributionPoint` conformer (see the `extension-host-core-extensions-contribution-point` recipe), not to the registry.

## Appearance

Not applicable — this is the extension host's discovery-and-contribution registry, not a visual component.

## States

Not applicable — this is the extension host's discovery-and-contribution registry, not a visual component. Its runtime state machine (never-scanned, scanning, loaded, superseded-reload-in-flight) is covered under Behavioral Requirements above (established-identifiers-initial-state, reload-generation-drops-superseded-results), not as a visual-state table.

## Accessibility

Not applicable — this is the extension host's discovery-and-contribution registry, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| extension-registry-001 | loaded-extension-logged, load-all-never-throws | One search path containing one directory with a valid manifest (`publisher: "acme"`, `name: "good"`, `engines.vscode: "^1.74.0"`), `hostVersion: 1.95.0` (traced to `ExtensionRegistryTests.goodExtensionLoads`) | `registry.extensions.count == 1`; `registry.extensions.first?.identifier == "acme.good"`; `registry.failures.isEmpty` |
| extension-registry-002 | manifest-missing-is-not-a-failure | One search path containing one empty directory with no `package.json` (traced to `ExtensionRegistryTests.missingManifestIsSkippedSilently`) | `registry.extensions.isEmpty`; `registry.failures.isEmpty` |
| extension-registry-003 | manifest-malformed-failure-with-recovered-identifier, contribution-point-error-isolated | Two directories: one with `{ not valid json`, one with a valid `acme.good` manifest (traced to `ExtensionRegistryTests.malformedJSONIsIsolated`) | `registry.extensions.count == 1` (`acme.good` loaded); `registry.failures.count == 1` with `reason` matching `.manifestMalformed` |
| extension-registry-004 | engine-incompatible-failure | A manifest with `engines.vscode: "^2.0.0"`, `hostVersion: 1.95.0` (traced to `ExtensionRegistryTests.incompatibleEngineFails`) | `registry.extensions.isEmpty`; one failure with `.engineIncompatible(required: "^2.0.0", host: "1.95.0")` |
| extension-registry-005 | engine-range-unparsable-failure | A manifest with `engines.vscode: "~1.74.0"` (a range shape VS Code's own grammar never implemented) (traced to `ExtensionRegistryTests.unparsableEngineRangeFails`) | `registry.extensions.isEmpty`; one failure with `.engineRangeUnparsable("~1.74.0")` |
| extension-registry-006 | duplicate-identifier-first-wins, scan-search-path-order-preserved | Two search paths `[firstRoot, secondRoot]`, each containing a directory named `dup-ext` whose manifest is `acme.dup` (traced to `ExtensionRegistryTests.duplicateIdentifierAcrossSearchPathsLoadsOnce`) | `registry.extensions.count == 1`, loaded from `firstRoot/dup-ext`; one failure recorded against `secondRoot/dup-ext` with `.duplicateIdentifier(existing: firstRoot/dup-ext's path)` |
| extension-registry-007 | scan-sorted-directory-order, duplicate-identifier-first-wins | One search path with two directories claiming the same identifier, named `acme.tool-1.0.0` and `acme.tool-1.1.0` (traced to `ExtensionRegistryTests.duplicateResolutionIsDeterministic`) | The lexicographically first directory (`acme.tool-1.0.0`) wins and is loaded; `acme.tool-1.1.0` is recorded as the duplicate failure |
| extension-registry-008 | contribution-registrations-not-part-of-registry-state, contributes-absent-becomes-empty, apply-only-for-enabled-extensions | A registered `RecordingContributionPoint`, and an enabled extension whose manifest declares `contributes.commands` (traced to `ExtensionRegistryTests.contributionPointRespectsEnablement`) | The point's `apply` is called for the enabled extension; a disabled extension in the same scan never has `apply` called on it |
| extension-registry-009 | contribution-point-error-isolated | A registered `ThrowingContributionPoint` that always throws, and one loadable extension `acme.good` (traced to `ExtensionRegistryTests.aRefusedContributionKeepsTheScanComplete`) | `registry.extensions.count == 1` (still loaded); one failure with `identifier == "acme.good"` and `reason: .contributionPointFailed`; `registry.establishedIdentifiers == ["acme.good"]` |
| extension-registry-010 | set-enabled-no-op-on-unchanged-state, set-enabled-drives-contribution-points | An enabled, loaded extension with a registered `RecordingContributionPoint`; call `setEnabled(false, for:)` then `setEnabled(true, for:)` then `setEnabled(true, for:)` again (traced to `ExtensionRegistryTests.setEnabledDrivesContributionPoint` and `redundantSetEnabledIsANoOp`) | First call withdraws; second call re-applies; third (redundant) call produces no additional `apply`/`withdraw` call and no observer notification |
| extension-registry-011 | load-all-resets-state | `loadAll()` called twice in succession on the same search paths with a registered `RecordingContributionPoint` (traced to `ExtensionRegistryTests.loadAllTwiceAppliesContributionsOnce`) | The point's `appliedIdentifiers` contains each extension's identifier exactly once after the second call, never twice |
| extension-registry-012 | uninstall-deletes-then-updates-memory, uninstall-notifies-once | A loaded, enabled extension with a registered contribution point; call `uninstall(_:)` (traced to `ExtensionRegistryTests.uninstallWithdrawsAndRemoves`) | The extension's directory no longer exists on disk; `registry.extensions` no longer contains it; the point's `withdraw` was called for it; the observer fires exactly once |
| extension-registry-013 | uninstall-unknown-identifier-is-a-no-op | `uninstall("not-installed.anything")` on a registry that never loaded that identifier | Returns without throwing; `registry.extensions` and `registry.failures` are unchanged; no file-system call occurs |
| extension-registry-014 | established-identifiers-nil-on-unnameable-failure | Two directories: one with `{ not valid json` (no recoverable `name`), one with a valid `acme.good` manifest (traced to `ExtensionRegistryTests.aMalformedManifestMakesTheWholeScanUnnameable`) | `registry.failures.first?.identifier == nil`; `registry.establishedIdentifiers == nil` |
| extension-registry-015 | manifest-malformed-failure-with-recovered-identifier, established-identifiers-union | A manifest whose `version` field is the wrong JSON type (fails strict decode) but whose `name` and `publisher` are present and valid, alongside a second, fully valid `acme.good` manifest (traced to `ExtensionRegistryTests.malformedManifestStillNamesItsExtension`) | One failure with `identifier == "acme.broken"`; `registry.establishedIdentifiers == ["acme.broken", "acme.good"]` |
| extension-registry-016 | scan-unreadable-search-path-marks-incomplete, established-identifiers-nil-when-incomplete | A search path directory that exists, contains a valid extension, but has its POSIX permissions set to `0o000` before `loadAll()` (traced to `ExtensionRegistryTests.anUnreadableSearchPathMakesTheWholeScanUnnameable`) | `registry.extensions.isEmpty`; `registry.failures.isEmpty`; `registry.establishedIdentifiers == nil` |
| extension-registry-017 | scan-existing-search-paths-only | A `searchPaths` entry pointing at a path that does not exist on disk, alone and alongside a real search path with one valid extension (traced to `ExtensionRegistryTests.anAbsentSearchPathLeavesTheScanComplete`) | `establishedIdentifiers == []` for the absent-only case; `establishedIdentifiers == ["acme.good"]` when paired with the real path |
| extension-registry-018 | established-identifiers-initial-state | A freshly constructed `ExtensionRegistry` before `loadAll()`/`reload()` is ever called, with one valid extension already sitting on disk at its search path (traced to `ExtensionRegistryTests.anUnscannedRegistryAnswersUnknown`) | `registry.establishedIdentifiers == nil`; after `loadAll()`, `registry.establishedIdentifiers == ["acme.good"]` |
| extension-registry-019 | jsonc-tolerance | A `package.json` beginning with a UTF-8 BOM, containing `//` line comments, a `/* block comment */`, and a trailing comma in the `commands` array (traced to `ExtensionRegistryTests.jsoncManifestLoads`) | `registry.failures.isEmpty`; the extension loads with `identifier == "acme.jsonc"` and one decoded command |
| extension-registry-020 | scan-sorted-directory-order | Twenty extension directories named `e00-ext` through `e19-ext`, written in an order the file system does not guarantee to preserve (traced to `ExtensionRegistryTests.directoriesAreEnumeratedInSortedOrder`) | `registry.extensions.map(\.identifier)` equals `["acme.e00", "acme.e01", …, "acme.e19"]`, in that exact order |
| extension-registry-021 | is-enabled-case-insensitive, set-enabled-migrates-persisted-casing | Two directories decoding to the same folded identifier via different literal casing (`MS-vscode.Foo` and `ms-vscode.foo`); then `setEnabled(false, for: "ms-vscode.foo")` (traced to `ExtensionRegistryTests.caseVariantsAreOneExtension`) | Only one extension loads, `identifier == "ms-vscode.foo"`; the second directory is recorded as a duplicate; after `setEnabled(false, for:)`, `isEnabled("MS-vscode.Foo") == false` |
| extension-registry-022 | is-enabled-case-insensitive | `UserSettings.disabledExtensionIdentifiers.value = ["MS-vscode.Foo"]` set before `loadAll()`, then a manifest for `ms-vscode.foo` loaded (traced to `ExtensionRegistryTests.persistedDisabledIdentifierMigratesCase`) | `registry.isEnabled("ms-vscode.foo") == false`; the registered contribution point's `apply` is never called for it |
| extension-registry-023 | reload-generation-drops-superseded-results | Two overlapping calls to `reload(performing:)` with an injected scan closure, where the first call's scan resolves after the second call's scan has already resolved and applied (traced to `ExtensionRegistryTests`'s reload-generation test coverage under the `reload(performing:)` seam) | The first (superseded) call's scan result is discarded and never reaches `apply(_:)`; a debug log line is emitted naming the dropped generation |

## Edge Cases

- **Null and empty input**: An empty `searchPaths` array MUST leave `extensions` and `failures` both empty after `loadAll()`, with `establishedIdentifiers == []` (scan-existing-search-paths-only, no directories to skip). A `package.json` decoding to a manifest with no `contributes` key at all MUST be treated identically to one whose `contributes` is present but names nothing (contributes-absent-becomes-empty).
- **Boundary values**: An `engines.vscode` value of exactly `^1.138.0` (the host's own `declaredVSCodeVersion`) MUST be accepted, since `VSCodeEngineRange.accepts(_:)` treats the host version as satisfying its own floor. A `SemanticVersion` component above `Int32.max` fails to parse in `SemanticVersion.init?(_:)`, so an `engines.vscode` string containing such a component surfaces as `.engineRangeUnparsable`, never a crash, per `SemanticVersion`'s own documented plausibility bound.
- **Concurrent access**: `ExtensionRegistry` is `@MainActor`-isolated; every mutating method (main-actor-confinement analog: main-actor-isolation on `ContributionPoint`) can only be reached from the main actor, so two calls into the same instance are always serialized, never truly concurrent. `Scan.scan(searchPaths:hostVersion:)` is `nonisolated static` and `Sendable`-safe specifically so `reload()` can run it off the main actor (reload-off-main-actor-scan) without racing the registry's own state, which is mutated only by `apply(_:)` back on the main actor.
- **Error states — a search path that cannot be listed**: `Scan.readEverything` becomes `false` and `establishedIdentifiers` becomes `nil` for the whole scan (scan-unreadable-search-path-marks-incomplete, established-identifiers-nil-when-incomplete); nothing is logged for this specific case in `ExtensionRegistry.swift` itself — see the marker below.
- **Error states — a manifest that cannot be identified**: A `manifestMalformed` or `manifestUnreadable` failure whose `identifier` cannot be recovered MUST set `establishedIdentifiers` to `nil` for the entire scan (established-identifiers-nil-on-unnameable-failure), even though every other extension in the same scan loaded or failed with a known identifier.
- **Error states — `uninstall` failing mid-operation**: The file-system delete is attempted first and, if it throws, no in-memory state changes at all (uninstall-deletes-then-updates-memory); a caller sees the extension still fully intact rather than partially removed.
- **Offline or disconnected state**: Not applicable — `ExtensionRegistry.swift` performs only local file-system I/O (`FileManager`, `Data(contentsOf:)`); it makes no network request of its own, so connectivity has no effect on discovery, loading, enablement, or uninstall.
- **A superseded `reload()` finishing after a later one**: the earlier call's scan result is dropped rather than applied, per reload-generation-drops-superseded-results; this is the specific race the `reloadGeneration` counter exists to resolve, and it is resolved by *start* order, not *finish* order.
- **Two overlapping calls where `loadAll()` runs synchronously while an async `reload()` is in flight**: `loadAll()` also bumps `reloadGeneration` (load-all-also-bumps-generation), so the in-flight `reload()`'s eventual result is dropped as superseded once `loadAll()` finishes first.
- **A directory caught mid-install or mid-update, with no `package.json` yet**: treated identically to an ordinary non-extension directory (manifest-missing-is-not-a-failure) — silently absent from both `extensions` and `failures`. The source's own doc comment on `read(from:hostVersion:)` states this is a deliberate, accepted risk: if such a directory is later pruned by a caller relying on `establishedIdentifiers`, that extension's contributed data (for example, its themes) can be lost even though the scan reported itself complete, and — per that same comment — a user's actively selected theme from that extension does not automatically come back, only the theme *entries* do, on the next successful load.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `searchPaths` (`init(searchPaths:hostVersion:)`) | `[URL]` | none — required | Directories to scan for extension folders; caller-resolved, since `ExtensionRegistry` cannot import the tier that would derive them (see Design Decisions). |
| `hostVersion` (`init(searchPaths:hostVersion:)`) | `SemanticVersion` | none — required | The running host's own version, compared only by `ActivationEventMatcher` and callers outside this file; not the value the engine gate checks against. |
| `ExtensionRegistry.declaredVSCodeVersion` | `SemanticVersion` (`nonisolated static let`) | `1.138.0` | The VS Code API surface version every extension's `engines.vscode` is gated against during `loadAll()`/`reload()`. |
| `UserSettings.disabledExtensionIdentifiers` | `UserSetting<Set<String>>` (`"extensions.disabledIdentifiers"`) | `[]` | Persisted, case-insensitively-compared set of identifiers the user has switched off; absence from this set means enabled. |
| Registered `ContributionPoint`s (`register(_:)`) | `[any ContributionPoint]` | `[]` | Points that receive `apply`/`withdraw` calls for each enabled extension's `contributes.*` blocks; caller-supplied, order-preserving. |
| Contributions observers (`addContributionsObserver(_:)`) | `[(token: UUID, handler: () -> Void)]` | `[]` | Handlers called once after every load, reload, enable/disable, or uninstall that changed live contribution state. |

## Deep Linking

Not applicable: `ExtensionRegistry.swift` defines no URL scheme, route, or navigation target.

## Localization

`ExtensionRegistry.swift` defines no user-facing string of its own; every string it carries into its `ExtensionLoadError` cases and log lines is either a manifest-derived identifier/path or a developer-facing diagnostic. It does, however, drive manifest localization for the extension's own declared strings: every `package.json` decode is routed through `ExtensionManifestLocalization.localize(_:forManifestIn:)` (manifest-localization-applied-before-decode) before the JSONC preprocessor and the `ExtensionManifest` decode, so an extension's own `%configuration.title%`-style placeholder resolves against its `package.nls.json` before any downstream caller ever sees the manifest's strings.

## Accessibility Options

Not applicable: this file has no UI of its own, so it responds to no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: `ExtensionRegistry.swift` declares no feature-flag key and contains no conditional feature-gating logic.

## Analytics

Not applicable: `ExtensionRegistry.swift` emits no analytics or event-tracking call; its only instrumentation is the `OSLog`/`Logger` calls documented under Logging.

## Privacy

- **Data collected**: `ExtensionRegistry` reads only extension manifest metadata from disk — identifiers, versions, engine ranges, and `contributes.*` declarations — and the user's own set of disabled extension identifiers. It reads no credential, token, or other secret value; a manifest's own contents are third-party-authored text, not user-entered secrets.
- **Storage**: The only persisted state this file writes is `UserSettings.disabledExtensionIdentifiers` (a set of extension identifier strings) via `setEnabled`/`uninstall`. `extensions`, `failures`, and `contributionPoints` are in-memory only and are rebuilt from disk by every `loadAll()`/`reload()`.
- **Transmission**: Not applicable — this file performs no networking.
- **Retention**: `extensions` and `failures` live only as long as the `ExtensionRegistry` instance and are wholly replaced by each `apply(_:)`; `UserSettings.disabledExtensionIdentifiers` persists across launches until `uninstall(_:)` clears an identifier's tombstone or a user explicitly re-enables it.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (falls back to `"nil"` if unset, via the shared `Loggable` protocol) | Category: `ExtensionRegistry`

| Event | Level | Message |
|-------|-------|---------|
| A directory's manifest decodes, passes the engine gate, and claims a fresh identifier | info | `Loaded extension '<identifier>' from <directory path>` |
| Any recorded `ExtensionLoadError` (`manifestUnreadable`, `manifestMalformed`, `engineRangeUnparsable`, `engineIncompatible`, `contributionPointFailed`) | warning | `Failed to load extension at <directory path>: <reason>` |
| A second directory claims an identifier an earlier directory already loaded | warning | `Skipping duplicate extension '<identifier>' at <directory path>; already loaded from <existing path>` |
| A registered `ContributionPoint`'s `apply` throws for a loaded extension | error | `Contribution point '<contributionKey>' failed to apply '<identifier>': <error description>` |
| A `reload(performing:)` call's scan result is discarded because a later `reload` began and finished first | debug | `Dropping the result of reload <generation>: superseded by <current generation> while it was scanning.` |

## Platform Notes

- **AppKit / UIKit**: This is the source. The file is `packages/apple/AgenticToolkit/Core/Extensions/ExtensionRegistry.swift`, part of the `AgenticToolkitCore` framework target, which builds for macOS. It has no AppKit or UIKit import; the only Apple-framework dependencies are `Foundation` and `OSLog`. Its sibling `ContributionPoint.swift` (same directory) defines the protocol this file drives, and every conformer today lives under `macOS/Features/Extensions/`.
- **SwiftUI**: No SwiftUI dependency exists in this file. A SwiftUI host would typically wrap `ExtensionRegistry` in an `@Observable`/`ObservableObject` adapter that calls `loadAll()` once at startup and re-publishes `extensions`/`failures` from inside a contributions-observer handler (`addContributionsObserver`), since the registry itself exposes no `@Published`/`@Observable` state directly.
- **Compose**: A Kotlin port would model the `@MainActor` confinement as a single-threaded `CoroutineDispatcher` (e.g. `Dispatchers.Main`) every call is confined to, mirroring main-actor-confinement. `Scan.scan` maps to a plain synchronous function over `java.io.File.listFiles()` (sorted explicitly, per scan-sorted-directory-order); the off-thread `reload()` path (reload-off-main-actor-scan) maps to `withContext(Dispatchers.IO) { scan(...) }` followed by resuming on `Dispatchers.Main` to apply. `JSONCPreprocessor` and `ExtensionManifestLocalization` have no framework-provided Kotlin equivalent and would need a direct port (a JSONC comment/BOM/trailing-comma stripper, and an `.nls.json`-keyed string substitution pass) ahead of `kotlinx.serialization` decoding.
- **React/Web**: A TypeScript port has no actor isolation to enforce, so main-actor-confinement has no direct analogue; a port would instead document that every mutating call into a shared registry instance must run on the same JS event-loop turn, with any asynchronous rescan (the `reload()` analogue) queued rather than interleaved. Directory enumeration maps to Node's `fs.readdir`/`fs.promises.readdir` (sorted explicitly), JSONC parsing to a library implementing the same comment/trailing-comma/BOM tolerance, and `VSCodeEngineRange`/`SemanticVersion` need a direct port since neither is `semver`-compatible by design (see the `extension-host-core-extensions-extension-manifest` recipe for the shared manifest-decoding contract).
- **WinUI 3**: There is no `dlopen`/`NSPrincipalClass` analogue needed here at all — unlike `AIPluginManager`, this registry never loads the extension's executable code, only its manifest, so a .NET port has no assembly-loading counterpart to design around. `Scan.scan` maps to `System.IO.Directory.EnumerateDirectories`/`EnumerateFiles` (materialized and sorted with `OrderBy(x => x, StringComparer.Ordinal)` to match scan-sorted-directory-order exactly), `System.IO.File.Exists`/`ReadAllBytesAsync` for the manifest read, and `System.Text.Json` for the decode — preceded by a hand-written JSONC-tolerant preprocessing pass (comments, trailing commas, BOM) and an `.nls.json` string-substitution pass, since neither ships in `System.Text.Json` and both are load-bearing per jsonc-tolerance and manifest-localization-applied-before-decode. `VSCodeEngineRange`/`SemanticVersion` need a direct, from-scratch port (a `record struct` for each), since .NET's own `Version`/`NuGetVersion` types implement npm-style semver precedence, not VS Code's caret-with-must-equal-flags grammar. `@MainActor` confinement maps to requiring every call to originate on the UI thread (`DispatcherQueue.HasThreadAccess`), and the off-UI-thread scan in `reload()` maps to `Task.Run` for the synchronous file I/O, resuming on the `DispatcherQueue` to mutate state and raise a `ContributionsChanged` event — the direct analogue of `addContributionsObserver`'s callback list, though a WinUI 3 port might reasonably expose it as a C# `event Action` instead of a manually-managed token/handler list, since .NET events already support multi-subscriber add/remove.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/Extensions/ExtensionRegistry.swift` |

## Design Decisions

**Decision**: `searchPaths` is a caller-injected `[URL]` rather than a value `ExtensionRegistry` derives itself from a well-known location.
**Rationale**: The real search paths live behind `AppStorageLocation`, which sits in `apple-database`, a tier `ExtensionRegistry` cannot import without creating an upward dependency from a lower tier. The caller resolves the real paths and passes them in, the same pattern `AIPluginManager`'s test-only initializer already uses — see the `ai-plugin-runtime-ai-plugin-kit-ai-plugin-manager` recipe.
**Approved**: pending

**Decision**: `contributionsObservers` is a list of `(token, handler)` pairs rather than the single callback slot it replaced.
**Rationale**: More than one caller needs to react to a contribution change — the document layout has to widen before a contributed view can be placed, and an extension host has to reconcile separately — and a single slot meant whichever subscriber registered second silently un-wired the first. A prior workaround, where each subscriber read the slot and chained through it, was correct only as long as every subscriber remembered to chain, and failed silently the first time one did not.
**Approved**: pending

**Decision**: `loadAll()` withdraws every currently loaded extension's contributions from every registered point before rebuilding state, even for an extension that will be reapplied unchanged in the same pass.
**Rationale**: Clearing only the `extensions`/`failures` arrays without withdrawing first would leave every contribution point holding a duplicate application while the registry's own bookkeeping reported it once, and a single later `withdraw` call would then leave one copy behind. Withdraw-before-rebuild keeps the registry and every contribution point's state from ever disagreeing about how many times something was applied.
**Approved**: pending

**Decision**: `establishedIdentifiers` is computed on every access from `extensions`, `failures`, and `scanReadEverything`, rather than stored as a separately maintained third property.
**Rationale**: Deriving it guarantees it cannot drift out of step with the two arrays it is built from. `scanReadEverything` captures the one fact the arrays alone cannot express — a directory or search path the scan never got far enough to name leaves no trace in either array — so "every failure is nameable" is not by itself evidence the scan was whole.
**Approved**: pending

**Decision**: A directory caught mid-install or mid-update, with no `package.json` on disk yet, is treated identically to an ordinary non-extension directory: silently absent from both `extensions` and `failures`, with the scan still reporting itself complete.
**Rationale**: The alternative — treating any manifest-less directory as unnameable — makes the scan permanently incomplete on any search path holding one stray non-extension folder (a `.DS_Store` sibling, a README), which disables orphan pruning for every user, always. A rare, transient, largely self-healing loss (the extension's themes return on the next successful load) is accepted as the better trade against a certain, permanent one.
**Approved**: pending

**Decision**: `SemanticVersion` parses only `major[.minor[.patch]]` with no pre-release or build-metadata grammar, and `VSCodeEngineRange` is a direct port of VS Code's own `extensionValidator.ts` rather than an npm-semver-range reading of `engines.vscode`.
**Rationale**: `engines.vscode` looks like an npm semver range and is not one; an npm reading rejects roughly a quarter of real-world extensions VS Code itself runs, per the source's own cited Open VSX survey. A caret range on this grammar clears must-equal flags rather than computing a ceiling, and a sub-1.0.0 requirement is treated as compatible with 1.x except at an exact match — both intentionally surprising relative to npm semantics, and both load-bearing for extension compatibility.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |

`separation-of-concerns` passes because `ExtensionRegistry.swift` delegates manifest decoding to `ExtensionManifest`, engine-range parsing to `VSCodeEngineRange`, JSONC tolerance to `JSONCPreprocessor`, and NLS resolution to `ExtensionManifestLocalization`, keeping this file's own responsibility limited to directory enumeration, gating, ordering, and driving registered contribution points. `unit-test-coverage` passes: `ExtensionRegistryTests.swift` exercises discovery, every `ExtensionLoadError` case, duplicate resolution, enablement (including case-migration), uninstall (including the failed-delete path), the `establishedIdentifiers` tri-state contract across every branch that sets it `nil`, JSONC tolerance, ordering, and the observer-notification contract, including the reload-generation race via the `reload(performing:)` test seam. `fault-tolerance` passes because `loadAll()` never throws, isolates each directory's and each contribution point's failure independently (contribution-point-error-isolated, manifest-malformed-failure-with-recovered-identifier), and a bad extension or a refusing contribution point never prevents another extension from loading. `explicit-error-handling` is `partial`: every load-time failure is a typed `ExtensionLoadError` recorded in `failures`, but the two skip branches inside `Scan.scan` that set `readEverything = false` (an unreadable search path, an unresolvable directory-entry type) emit no log line at all, unlike every other skip branch in the file — see the open question under Edge Cases.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
