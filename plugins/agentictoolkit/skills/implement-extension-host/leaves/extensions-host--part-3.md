<!-- leaf: implement-extension-host/extensions-host--part-3 · source: extension-host-extensions-host.md -->

# Extension Host — continued (part 3)

**Rules** (cite as `implement-extension-host/extensions-host--part-3#<slug>`):

- `finish-activation-resumes-exactly-once` MUST
- `describe-reentrancy-bounded` MUST
- `vscode-uri-and-vocabulary-installed-eagerly` MUST
- `install-vscode-members-sorted` MUST
- `host-globals-removed-after-shim-setup` MUST
- `installation-adaptor-teardown-order` MUST
- `installation-dispose-idempotent` MUST
- `activation-command-double-press-forwards-both` MUST
- `activation-stub-leaves-owned-commands-alone` MUST
- `installer-reconcile-identity-not-identifier` MUST
- `installer-reconcile-dispose-before-rebuild` MUST
- `installer-reconcile-disables-removed-extensions` MUST
- `installer-bring-up-replays-completed-scan-only-if-current` MUST
- `installer-bring-up-replays-open-documents-live` MUST
- `workspace-scan-reused-per-workspace` MUST
- `workspace-scan-race-safe-on-root-return` MUST
- `workspace-scan-depth-and-entry-capped` MUST
- `workspace-scan-skips-generated-directories` MUST
- `workspace-scan-includes-dotfiles` MUST
- `webview-panel-claim-order-deterministic` MUST
- `contributed-view-resolved-by-manifest-ownership` MUST
- `contributed-view-will-appear-is-a-broadcast` MUST
- `not-implemented-ledger-dedup-by-key` MUST
- `not-implemented-ledger-accessors-sorted` MUST

- **finish-activation-resumes-exactly-once**: `finishActivation(_:)` MUST resume the stored `activationContinuation` at most once and MUST be a safe no-op when no continuation is pending, since up to four routes (the shim's completion block, the thenable-getter-throw path, `dispose()`, and a cancelling caller) can race to end the same activation.
- **describe-reentrancy-bounded**: `describe(_:)` MUST return a fixed literal string rather than recursing when called while already describing another exception (guarded by `describingException`), so a hostile self-referential `Proxy` that throws while being described cannot overflow the native stack.
- **vscode-uri-and-vocabulary-installed-eagerly**: `installRuntime(runtimeSource:into:)` MUST install the command-dispatch trampoline, `vscode.Uri`, the language-model message vocabulary, the text-geometry classes, and the diagnostic value types on every activation, before any adaptor-registered member and before the extension's own module code runs, and MUST NOT route any of these five through `defineVSCodeMember`/`vscodeMemberDefinitions`, since they are host ceremony reinstalled identically every time rather than adaptor state to be replayed.
- **install-vscode-members-sorted**: `installVSCodeMembers(_:onto:)` MUST iterate a members dictionary's keys in sorted order, never in raw dictionary-iteration order, so the install order (and therefore any log line describing a failed install) is stable across runs.
- **host-globals-removed-after-shim-setup**: `installRuntime` MUST evaluate `delete globalThis.__extensionRuntime; delete globalThis.__host;` after wiring the runtime, so extension code has no direct line to the host's timer/console/ledger bridge once setup is complete.
- **installation-adaptor-teardown-order**: `ExtensionHostInstallation.dispose()` MUST run, in this exact order: `host.disposeSubscriptions()`; unregister every remaining entry in `stubCommands`; dispose all eight adaptors (`commands`, `languages`, `workspace`, `languageModels`, `window`, `webviews`, `treeViews`, `diagnostics`); then `host.dispose()` last — because the adaptor withdrawals call back into JavaScript (a panel's `onDidDispose`, a tree view's teardown) and require a live runtime.
- **installation-dispose-idempotent**: `ExtensionHostInstallation.dispose()` MUST be a no-op on a second call (guarded by `isDisposed`).
- **activation-command-double-press-forwards-both**: `ExtensionHostInstallation.dispatchAfterActivation(commandID:arguments:)` MUST retire the stub token with `if let` (never `guard let`) before forwarding, so that a second command press queued while activation is still in flight is forwarded on its own merits rather than dropped because the token was already taken by the first press.
- **activation-stub-leaves-owned-commands-alone**: `registerActivationCommands(_:)` MUST NOT register a stub over a command id already present in `commandRegistry`, and MUST log that the extension's `onCommand:` trigger for that id will never fire.
- **installer-reconcile-identity-not-identifier**: `ExtensionHostInstaller.reconcile()` MUST key "already installed" on `InstalledIdentity` (manifest plus directory plus entry-point `FileSignature`), never on the bare extension identifier, so an author's on-disk code edit is detected and the host is rebuilt even when the manifest is unchanged.
- **installer-reconcile-dispose-before-rebuild**: `reconcile()` MUST dispose an outgoing installation before constructing its replacement for the same identifier, never leaving both live at once, since both would otherwise record against the same `extensionIdentifier` in five adaptors simultaneously.
- **installer-reconcile-disables-removed-extensions**: `reconcile()` MUST dispose and remove every installation whose identifier is no longer in the enabled set.
- **installer-bring-up-replays-completed-scan-only-if-current**: `bringUp(_:identity:)` MUST replay `.workspaceScanned` against a newly installed extension only when `completedScan.roots` still equals the live `workspaceRootURLs`, never a stale scan from a since-closed project.
- **installer-bring-up-replays-open-documents-live**: `bringUp(_:identity:)` MUST replay `.documentOpened` triggers by reading `seams.openDocumentLanguageIDs()` live at call time, never from a remembered set, so a document since closed cannot activate an extension.
- **workspace-scan-reused-per-workspace**: `startWorkspaceScanIfNeeded()` MUST reuse `completedScan` when its roots already equal the live workspace roots, and MUST NOT start a second scan while one with the same roots is already `scanningRoots`.
- **workspace-scan-race-safe-on-root-return**: `startWorkspaceScanIfNeeded()`'s completion handler MUST re-read the live workspace roots and discard a scan's result (retrying rather than recording it) when the live roots no longer match the roots the scan was started against — covering an A-to-B-and-back-to-A root change during an in-flight scan of B.
- **workspace-scan-depth-and-entry-capped**: `ExtensionHostInstaller.scan(roots:)` MUST stop descending into a directory once `enumerator.level >= scanDepthLimit` (6) and MUST stop collecting once `found.count >= scanEntryLimit` (20,000).
- **workspace-scan-skips-generated-directories**: `scan(roots:)` MUST skip descending into any directory named in `skippedDirectoryNames` (`.build`, `.git`, `.svn`, `.venv`, `DerivedData`, `Pods`, `__pycache__`, `build`, `dist`, `node_modules`, `target`, `vendor`).
- **workspace-scan-includes-dotfiles**: `scan(roots:)` MUST NOT pass `.skipsHiddenFiles` to its `FileManager` enumerator, so dotfile-based `workspaceContains:` patterns (`.vscode/launch.json`, `.eslintrc*`) remain matchable.
- **workspace-scan-incomplete-signal**: NEEDS REVIEW: Not implemented in source. `ExtensionHostInstaller.scan(roots:)` resolves each directory entry's `isDirectoryKey` with `try? url.resourceValues(forKeys: [.isDirectoryKey])`, defaulting to `false` on any failure and continuing the walk with no signal that the walk is now incomplete. `CompletedScan` carries no incompleteness flag comparable to `ExtensionRegistry.establishedIdentifiers`'s `nil`-on-incomplete-scan contract, so a `workspaceContains:` extension can be told a pattern does not match a workspace the scan never actually finished reading, with nothing anywhere recording that the answer might be wrong.
- **webview-panel-claim-order-deterministic**: `restoreWebviewPanel(state:makePanel:)` MUST resolve a webview view-type contested by more than one installed extension by sorting claimants by `identifier` and choosing the first, and MUST log when more than one claimant exists.
- **contributed-view-resolved-by-manifest-ownership**: `resolveWebviewView(view:makePanel:didResolve:)` and `resolveTreeView(view:didResolve:)` MUST resolve strictly to the single extension named by `ContributedView.extensionIdentifier`, never by a claims-based contest, since a contributed view's ownership was already declared in the manifest.
- **contributed-view-will-appear-is-a-broadcast**: `contributedViewWillAppear(viewID:)` MUST notify every installed extension's `activateIfTriggered(by: .viewShown(viewID:))`, unlike the owner-only resolution methods, because `onView:` may be declared by any extension against any view id, including one it does not own.
- **not-implemented-ledger-dedup-by-key**: `NotImplementedLedger` MUST deduplicate by `(extensionIdentifier, memberPath)`, keeping the first `firstAccess` timestamp and incrementing `count` (for `record`) or `probeCount` (for `recordProbe`) on every subsequent call for the same key.
- **not-implemented-ledger-accessors-sorted**: `NotImplementedLedger.accesses` and `accesses(for:)` MUST both return rows ordered by `extensionIdentifier` then `memberPath` via the shared `reportOrder`, never in insertion order.
## Configuration

| Setting | Type | Default | Description |
|---------|------|---------|--------------|
| `ExtensionHost.maximumTimerDelayMilliseconds` | `Double` (`static let`) | `2_147_483_647` | The signed 32-bit `setTimeout` ceiling in milliseconds (about 24.8 days) that every timer delay is clamped against. |
| `ExtensionHostInstaller.scanDepthLimit` | `Int` (`nonisolated static let`) | `6` | How many directory levels deep the `workspaceContains:` scan descends before pruning. |
| `ExtensionHostInstaller.scanEntryLimit` | `Int` (`nonisolated static let`) | `20_000` | The maximum number of file paths the workspace scan collects before stopping. |
| `ExtensionHostInstaller.skippedDirectoryNames` | `Set<String>` (`nonisolated static let`) | `[".build", ".git", ".svn", ".venv", "DerivedData", "Pods", "__pycache__", "build", "dist", "node_modules", "target", "vendor"]` | Directory names the workspace scan never descends into. |
| `ExtensionHostSeams.fileSystemService` | `FileSystemServicing` | `FileSystemService()` | The shared file-system service `vscode.workspace.fs` runs through across every host; defaulted so only a test supplies a double. |
| `NotImplementedLedger.now` | `@MainActor () -> Date` | `{ Date() }` | The injected clock `firstAccess` is stamped from, overridden in tests to make the first-stamp-is-kept rule assertable. |

## Localization

None of the three files defines a user-facing localized string. Every string surfaced by `ExtensionHostError.errorDescription`, the `ExtensionHostInstallation`/`ExtensionHostInstaller` log lines, and `NotImplementedLedger`'s recorded member paths is either a developer-facing diagnostic (hardcoded English, naming an extension identifier, a namespace path, or a `file:line` origin) or extension-authored text passed through verbatim (a `console.*` message, a thrown exception's own message and stack). None of it is routed through `Bundle.localizedString` or an `.nls.json`-style substitution; that localization pass belongs to `ExtensionManifest`/`ExtensionManifestLocalization` for the extension's own manifest strings, not to this layer.

