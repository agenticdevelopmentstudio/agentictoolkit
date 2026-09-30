<!-- leaf: implement-extension-host-core-1/extensions-extension-registry--part-2 · source: extension-host-core-extensions-extension-registry.md -->

# Extension Registry — continued (part 2)

**Rules** (cite as `implement-extension-host-core-1/extensions-extension-registry--part-2#<slug>`):

- `declared-vscode-version` MUST
- `declared-version-nonisolated` MUST
- `initializer-injected-search-paths` MUST
- `register-before-load-all` MUST
- `load-all-never-throws` MUST
- `load-all-resets-state` MUST
- `scan-existing-search-paths-only` MUST
- `scan-unreadable-search-path-marks-incomplete` MUST
- `scan-unresolvable-entry-type-marks-incomplete` MUST
- `scan-directories-only` MUST
- `scan-sorted-directory-order` MUST
- `scan-search-path-order-preserved` MUST
- `manifest-missing-is-not-a-failure` MUST
- `manifest-unreadable-failure` MUST
- `jsonc-tolerance` MUST
- `manifest-localization-applied-before-decode` MUST
- `manifest-malformed-failure-with-recovered-identifier` MUST
- `engine-range-unparsable-failure` MUST
- `engine-incompatible-failure` MUST
- `duplicate-identifier-first-wins` MUST
- `loaded-extension-logged` MUST
- `contributes-absent-becomes-empty` MUST
- `apply-only-for-enabled-extensions` MUST
- `contribution-point-error-isolated` MUST
- `contribution-failures-cleared-before-reapply` MUST
- `notify-after-load-all` MUST
- `observers-called-in-subscription-order` MUST
- `observer-token-idempotent-removal` MUST
- `reload-off-main-actor-scan` MUST
- `reload-keeps-old-contributions-during-scan` MUST
- `reload-generation-drops-superseded-results` MUST
- `load-all-also-bumps-generation` MUST
- `is-enabled-default-true` MUST
- `is-enabled-case-insensitive` MUST
- `set-enabled-no-op-on-unchanged-state` MUST

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
