---
id: b2cf12e3-71de-4d87-9216-d5e8d604169c
title: Extension Host
domain: agentictoolkit://cookbook/macos/features/extensions/host
type: ingredient
version: 1.0.2
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "Runs one VS Code web extension's JavaScript in its own JSContext, wires\
  \ its per-extension installation and eight vscode namespace adaptors, reconciles\
  \ the running set against the registry by code identity, and records every unimplemented\
  \ API member an extension reaches for."
platforms:
- swift
- macos
tags:
- extensions
- extension-host
- javascriptcore
- mainactor
- not-implemented-ledger
depends-on:
- agentictoolkit://cookbook/core/extensions/activation-event-matcher
- agentictoolkit://cookbook/core/extensions/extension-resource-path
- agentictoolkit://cookbook/core/extensions/extension-manifest
- agentictoolkit://cookbook/core/extensions/extension-registry
related:
- agentictoolkit://cookbook/core/extensions/activation-event-matcher
- agentictoolkit://cookbook/core/extensions/extension-resource-path
- agentictoolkit://cookbook/core/extensions/extension-manifest
- agentictoolkit://cookbook/core/extensions/extension-registry
references: []
approved-by: ''
approved-date: ''
---

# Extension Host

## Overview

`ExtensionHost.swift`, `ExtensionHostInstaller.swift`, and `NotImplementedLedger.swift` (all in `packages/apple/AgenticToolkit/macOS/Features/Extensions/Host/`) form the layer that actually runs a VS Code web extension's JavaScript and keeps the running set of extensions in step with what `ExtensionRegistry` holds. `ExtensionHost` is a `@MainActor` class that owns one extension's `JSContext` inside a single process-wide `JSVirtualMachine`: it resolves and reads the extension's `browser` entry point, compiles it as a CommonJS module wrapper, evaluates it, and calls its exported `activate(context)`, tracking a single `activationState` computed property (`.neverActivated`, `.activating`, `.activated`, `.terminal(.cancelled | .failed)`, `.disposed`) whose evaluation order is explicitly documented as load-bearing — a "ladder of guards" anti-pattern that produced "four rounds of the same defect" before this property replaced it. `ExtensionHostInstaller` is the `@MainActor` class that owns one `ExtensionHost` plus eight per-extension `vscode` namespace adaptors (`MainThreadCommands`, `MainThreadLanguages`, `MainThreadWorkspace`, `MainThreadLanguageModels`, `MainThreadWindow`, `MainThreadWebviews`, `MainThreadTreeViews`, `MainThreadDiagnostics`) inside `ExtensionHostInstallation`, and `ExtensionHostInstaller` itself reconciles the whole running set against `ExtensionRegistry.extensions` by an identity that includes the entry point's on-disk size and modification date, not merely the extension's identifier — so an author's code edit is caught even when the manifest is byte-identical. `NotImplementedLedger` is a small `@MainActor` class, injectable and shareable across hosts, that deduplicates every VS Code API member an extension reached for and this host does not implement, by `(extensionIdentifier, memberPath)`, distinguishing a hard use from a feature-detection probe.

All three files are `@MainActor`; `ExtensionHost` and `JSValue`/`JSContext` are explicitly not `Sendable`, and the doc comments state the isolation is deliberate — every adaptor these types call into is itself main-actor confined, and a host that hopped executors would have to marshal `JSValue`s across them. The one documented exception is `ExtensionHost.compileModule(source:entryPoint:)`, which parses (but never executes) the extension's module off the main actor inside a `Task.detached`, carrying the `JSContext` across that one hop through a private `JSCrossThread<Value>: @unchecked Sendable` box, justified by `JSVirtualMachine`'s own internal lock making cross-thread JavaScriptCore use thread-safe by construction.

## Behavioral Requirements

- **activation-state-precedence**: `ExtensionHost.activationState` MUST evaluate in the fixed order disposed, activated, terminal, activating, neverActivated — never in field-declaration order — so that a cancellation landing after a successful activation is still reported `.activated`, and a failure recorded inside `performActivation`'s `catch` outranks the `activating` state a racing caller might still observe.
- **activate-idempotent-shared-outcome**: `ExtensionHost.activate()` MUST be a no-op that returns immediately when `activationState == .activated`, and two concurrent callers MUST share the single in-flight `activationTask` rather than each evaluating the module.
- **activate-refuses-when-disposed-or-terminal**: `activate()` MUST throw `ExtensionHostError.hostDisposed` on a disposed host, and MUST throw the mapped `activationCancelled`/`activationAlreadyFailed` error (via `terminalRefusal(_:identifier:)`) on a terminal host, without re-evaluating the module.
- **activate-no-timeout**: `activate()` MUST NOT impose an internal timeout on an extension's `activate()` promise; the only two ways to end a suspended activation are cancelling the calling task (`activationCancelled`) and calling `dispose()`.
- **activate-cancellation-shared**: A cancellation from any one caller of `activate()` MUST end the shared activation for every other awaiting caller, via `awaitActivation`'s `withTaskCancellationHandler`.
- **module-evaluated-terminal-boundary**: `moduleEvaluated` MUST be set exactly once, on the line immediately preceding `evaluateModule`'s `runtime.invokeMethod("run", ...)` call, and every route into `.terminal` MUST test this flag rather than infer it from which `do` block it is inside.
- **failure-before-boundary-is-retryable**: A failure that occurs before `moduleEvaluated` is set (entry-point resolution, disk read, compile) MUST leave the host `.neverActivated` and eligible for a later `activate()` call.
- **failure-after-boundary-is-terminal**: Any failure at or after `evaluateModule`'s `run` call (a synchronous throw, a rejected `activate()` promise, a throwing `.then` getter, a top-level throw, or a cancellation landing once the module is running) MUST set `terminationReason` via `markTerminal(_:)` and MUST refuse every later `activate()`/`defineVSCodeMember` call on that host.
- **terminal-reason-keeps-first**: `markTerminal(_:)` MUST keep the first `TerminationReason` recorded and MUST be a no-op on every subsequent call, so a cancellation and a failure racing to the same boundary cannot overwrite each other's diagnostic.
- **dispose-idempotent**: `ExtensionHost.dispose()` MUST be safe to call more than once and safe to call on a host that never activated.
- **dispose-releases-suspended-activation**: `dispose()` MUST resume any suspended `activate()` continuation with `ExtensionHostError.hostDisposed`, since an extension's `activate()` promise may never settle and there is no timeout to fall back on.
- **dispose-cancels-every-timer**: `dispose()` MUST cancel every entry in `timerTasks` and clear the dictionary, so no `setTimeout`/`setInterval` task can reach JavaScript again after teardown.
- **dispose-releases-context**: `dispose()` MUST replace the context's `exceptionHandler` with `recordExceptionOnContext` (never `nil`, since `JSContext.notifyException` calls the handler unconditionally) and MUST release `activationContext`, `runtime`, and `context`.
- **dispose-subscriptions-before-context**: `dispose()` MUST call `disposeSubscriptions()` before releasing the context, so the extension's own disposables are still callable at the moment they run.
- **dispose-subscriptions-idempotent**: `disposeSubscriptions()` MUST run at most once per host (guarded by `subscriptionsDisposed`), so a caller like `ExtensionHostInstallation.dispose()` that calls it ahead of `host.dispose()` produces exactly one pass over `context.subscriptions`.
- **dispose-subscriptions-autoreleased**: `disposeSubscriptions()` MUST wrap its JavaScriptCore calls in `autoreleasepool`, because every `JSValue` it produces holds its `JSContext` strongly and would otherwise keep the context alive past `dispose()`'s promise to release it.
- **isolated-deinit-cancels-timers**: `ExtensionHost`'s `isolated deinit` MUST cancel every timer task as a safety net for a host dropped without an explicit `dispose()` call, but MUST NOT be relied upon as the primary teardown path, since a host with an in-flight `activationTask` (an unstructured `Task` that strongly captures the host) never reaches `deinit` at all.
- **define-vscode-member-refuses-terminal-or-disposed**: `defineVSCodeMember(namespacePath:name:implementation:fileID:line:)` MUST throw `hostDisposed` on a disposed host and the mapped terminal error on a terminal host, never silently queuing a definition nothing will replay and never installing a live implementation into an abandoned runtime.
- **define-vscode-member-replays-on-runtime**: A definition made before a runtime exists MUST be queued in `vscodeMemberDefinitions` and applied immediately once `installRuntime` builds a runtime; a definition made after activation MUST be applied immediately via `applyOrWithdraw`.
- **define-vscode-member-withdraws-on-refusal**: A definition the shim refuses (an unknown namespace) MUST be removed from `vscodeMemberDefinitions` by `applyOrWithdraw` rather than left queued, so the host remains activatable and the same bad definition does not fail every future `activate()`.
- **deferred-value-resolved-at-apply-time**: A `DeferredVSCodeValue` implementation MUST be resolved against a live `JSContext` only inside `apply(_:to:)`, never at `defineVSCodeMember` call time, since every `defineVSCodeMember` caller runs before any context exists.
- **live-value-re-read-per-access**: A `LiveVSCodeValue` implementation MUST be re-read from `JSContext.current()` on every JavaScript access rather than resolved once and cached, so members reporting app state (`vscode.workspace.workspaceFolders`, `vscode.workspace.name`) never freeze to whatever was true at install time.
- **timer-delay-clamped-nan-safe**: `ExtensionHost.clampedTimerDelaySeconds(milliseconds:)` MUST compute `min(max(0, milliseconds), maximumTimerDelayMilliseconds) / 1000`, with `0` as the first argument to `max` (not the second), so that `NaN` collapses to `0` rather than propagating into `Duration.seconds`, which traps on an unrepresentable value.
- **timer-cancel-validates-before-truncating**: `cancelTimer(rawTimerID:)` MUST validate that the raw `Double` id is finite, integral, and within `Int32`'s range before truncating it to an `Int32`, and MUST do nothing (never round onto an unrelated timer) when validation fails.
- **timer-task-count-asserts-not-clamps**: `timerTaskDidFinish()` MUST assert and log a fault rather than clamp to zero when `runningTimerTasks` is not already positive, since a double-decrement indicates a timer task finished twice, a bug this counter exists to surface rather than hide.
- **console-message-always-logged**: Every `console.*` call MUST produce an OSLog line via the mapped `ExtensionConsoleMessage.Level`, and MUST additionally invoke `onConsoleMessage` when one is set, even when no observer is attached.
- **not-implemented-recorded-once-per-member**: A member reached for that this host does not implement MUST be recorded via `NotImplementedLedger.record(memberPath:extensionIdentifier:)`, with only the first access (`access.count == 1`) producing a log line, so a member reached for in a loop does not flood the log.
- **negative-probe-recorded-separately**: A feature-detection probe (`'x' in vscode.commands`, `Object.keys(...)`) that finds nothing MUST be recorded via `recordProbe`/`handleNegativeProbe`, sharing the same ledger row as a hard use of the same member but incrementing `probeCount` rather than `count`.
- **entry-point-requires-browser-not-main**: `resolveEntryPoint()` MUST throw `ExtensionHostError.requiresNodeRuntime` when the manifest declares `main` but not `browser`, and MUST throw `noEntryPoint` when it declares neither, never treating a Node-only extension as a generic load failure.
- **entry-point-must-not-escape-directory**: `resolveEntryPoint()` MUST resolve the declared `browser` path through `ExtensionResourcePath.resolve(_:inside:)` and MUST throw `ExtensionHostError.entryPointEscapesExtensionDirectory` when the resolved path falls outside the extension's own directory, including a sibling directory sharing a name prefix.
- **compile-runs-nothing**: `compileModule(source:entryPoint:)` MUST call `evaluateScript` on a function *expression* that produces a closure and executes none of the extension's top-level statements, which is the property that allows the compile step alone to run off the main actor.
- **entry-point-attributed-in-stack-traces**: `compileModule(source:entryPoint:)` MUST compile the wrapped source with `withSourceURL: entryPoint`, so a syntax error or a thrown exception names the extension author's own file and line.
- **exports-required-non-empty**: `evaluateModule` MUST throw `ExtensionHostError.entryPointThrew` when the module's `run` call yields `undefined`/`null` exports, distinct from a thrown exception.
- **activate-absence-is-not-an-error**: `callActivate` MUST log (not throw) when the module's exports have no `activate` function, since a manifest-only extension that contributes solely through side effects is legal.
- **activate-rejection-getter-throw-reported**: `callActivate` MUST report a thenable whose `.then` property getter throws as an activation failure via `pendingException`, rather than hanging indefinitely because the shim's completion callback (`done`) is never invoked in that case.
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

## Appearance

Not applicable — this is a JavaScript execution runtime, its per-extension installation/adaptor wiring, and an access ledger, not a visual component.

## States

Not applicable — this is a JavaScript execution runtime, its per-extension installation/adaptor wiring, and an access ledger, not a visual component. `ExtensionHost`'s own runtime state machine (`activationState`'s five cases) is covered under Behavioral Requirements above (activation-state-precedence, module-evaluated-terminal-boundary), not as a visual-state table.

## Accessibility

Not applicable — this is a JavaScript execution runtime, its per-extension installation/adaptor wiring, and an access ledger, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| extension-host-001 | entry-point-requires-browser-not-main | A manifest declaring `main` but no `browser` (traced to `ExtensionHostTests.anExtensionWithOnlyAMainEntryPointIsRefusedAsNeedingNode`) | `activate()` throws `.requiresNodeRuntime` naming the declared `main` value |
| extension-host-002 | entry-point-requires-browser-not-main | A manifest declaring neither `main` nor `browser` (traced to `ExtensionHostTests.anExtensionDeclaringNoCodeIsRefusedSeparately`) | `activate()` throws `.noEntryPoint`, distinct from `.requiresNodeRuntime` |
| extension-host-003 | entry-point-must-not-escape-directory | A `browser` entry point resolving outside the extension's own directory (traced to `ExtensionHostTests.aBrowserEntryPointOutsideTheExtensionDirectoryIsRefused`) | `activate()` throws `.entryPointEscapesExtensionDirectory` with both the declared and resolved paths |
| extension-host-004 | entry-point-must-not-escape-directory | A sibling directory sharing a name prefix with the extension's own directory (traced to `ExtensionHostTests.aSiblingDirectoryWithASharedNamePrefixDoesNotCountAsInside`) | The sibling is refused as escaping, not treated as inside |
| extension-host-005 | activate-idempotent-shared-outcome | `activate()` called twice in succession on the same host (traced to `ExtensionHostTests.activatingTwiceRunsTheExtensionOnce`) | The module's top level runs exactly once; the second call returns without re-evaluating |
| extension-host-006 | activate-refuses-when-disposed-or-terminal, failure-after-boundary-is-terminal | An `activate()` that fails after the module evaluated, then a second `activate()` call (traced to `ExtensionHostTests.aFailedActivationIsTerminalAndRefusesTheRetry`) | The second call throws `.activationAlreadyFailed` without re-evaluating the module |
| extension-host-007 | activation-state-precedence | A host walked through every state from fresh to disposed (traced to `ExtensionHostTests.activationStateNamesEveryStepFromFreshToDisposed`) | `activationState` reports `.neverActivated`, `.activating`, `.activated`, and finally `.disposed` at each corresponding point |
| extension-host-008 | activation-state-precedence, terminal-reason-keeps-first | A cancellation landing after activation has already succeeded (traced to `ExtensionHostTests.aCancellationLandingAsActivationSucceedsLeavesTheHostActivated`) | `activationState` reports `.activated`, not `.terminal(.cancelled)`, even though `recordedTerminationReason` shows the cancellation happened |
| extension-host-009 | failure-before-boundary-is-retryable | A malformed entry point that fails to compile, ran nothing (traced to `ExtensionHostTests.aMalformedEntryPointRanNothingSoTheHostStaysRetryable`) | The host stays `.neverActivated`; a corrected file can be activated on a later call |
| extension-host-010 | module-evaluated-terminal-boundary | Verifying the terminal boundary is running the module, not compiling it (traced to `ExtensionHostTests.theTerminalBoundaryIsRunningTheModuleNotCompilingIt`) | A compile failure leaves the host retryable; a run-time failure after `run` is called does not |
| extension-host-011 | dispose-cancels-every-timer | A pending `setTimeout` torn down by `dispose()` (traced to `ExtensionHostTests.teardownCancelsAPendingTimer`) | The timer task is cancelled and its callback never fires |
| extension-host-012 | dispose-cancels-every-timer | A repeating `setInterval` torn down by `dispose()` (traced to `ExtensionHostTests.teardownCancelsARepeatingTimer`) | The repeating timer task is cancelled, not merely declined on its next tick |
| extension-host-013 | dispose-cancels-every-timer | Verifying teardown stops the clock itself rather than only declining to fire (traced to `ExtensionHostTests.teardownStopsTheClockRatherThanOnlyDecliningToFire`) | `runningTimerCount` reaches zero immediately after `dispose()`, not merely on the timer's next scheduled tick |
| extension-host-014 | timer-task-count-asserts-not-clamps | A timer that fires normally and stops being counted (traced to `ExtensionHostTests.aTimerThatFiresNormallyStopsBeingCounted`) | `runningTimerCount` decrements by exactly one per completed timer |
| extension-host-015 | timer-cancel-validates-before-truncating | `clearTimeout` called before a timer fires (traced to `ExtensionHostTests.clearTimeoutStopsATimerBeforeItFires`) | The timer is cancelled and its callback never runs |
| extension-host-016 | timer-cancel-validates-before-truncating | `clearTimeout` given an id it could only reach by truncation (traced to `ExtensionHostTests.clearTimeoutIgnoresAnIdItCouldOnlyReachByTruncation`) | The out-of-range id is ignored; no unrelated live timer is cancelled |
| extension-host-017 | not-implemented-recorded-once-per-member | An unimplemented `vscode` member accessed, naming itself and recorded once (traced to `ExtensionHostTests.anUnimplementedVSCodeMemberThrowsNamesItselfAndIsRecordedOnce`) | The thrown error names the member; `NotImplementedLedger` records exactly one row |
| extension-host-018 | not-implemented-recorded-once-per-member | Repeated access to the same unimplemented member (traced to `ExtensionHostTests.repeatedAccessKeepsTheFirstStampAndCountsTheRest`) | `firstAccess` stays at the first reach; `count` increments on every subsequent reach |
| extension-host-019 | negative-probe-recorded-separately | Probing then using the same unimplemented member (traced to `ExtensionHostTests.probingAndThenUsingTheSameMemberIsOneRow`) | One ledger row carries both a non-zero `probeCount` and a non-zero `count` |
| extension-host-020 | negative-probe-recorded-separately | An honest negative probe, still recorded (traced to `ExtensionHostTests.aNegativeProbeIsAnsweredHonestlyAndStillRecorded`) | The probe returns `false`/absence to the extension without throwing, and is recorded in the ledger |
| extension-host-021 | dispose-subscriptions-idempotent | `context.subscriptions` disposed in insertion order, and not run twice (traced to `ExtensionHostTests.disposeRunsEverySubscriptionInInsertionOrder` and `disposeDoesNotRunASubscriptionTwice`) | Disposables run in the order pushed; a second `disposeSubscriptions()` call is a no-op |
| extension-host-022 | dispose-subscriptions-idempotent | A throwing subscription does not strand the rest (traced to `ExtensionHostTests.aThrowingSubscriptionDoesNotStrandTheRest`) | Every other subscription still disposes; the failure is logged, not thrown |
| extension-host-023 | dispose-idempotent | Disposing a host that never activated, and disposing twice (traced to `ExtensionHostTests.disposingAHostThatNeverActivatedIsSafe` and `disposingTwiceIsSafe`) | Both calls complete without error or duplicate teardown work |
| extension-host-024 | dispose-releases-suspended-activation | Disposing releases an `activate()` that never settles (traced to `ExtensionHostTests.disposingReleasesAnActivateThatNeverSettles`) | The suspended `activate()` call throws `.hostDisposed` rather than hanging forever |
| extension-host-025 | activate-cancellation-shared | Cancelling an activation ends it, and a later settle is harmless (traced to `ExtensionHostTests.cancellingAnActivationEndsItAndALaterSettleIsHarmless`) | The cancelled call throws `.activationCancelled`; the extension's later promise settlement has no observable effect |
| extension-host-026 | failure-after-boundary-is-terminal | A cancellation before the module is evaluated leaves the host retryable (traced to `ExtensionHostTests.aCancellationBeforeTheModuleIsEvaluatedLeavesTheHostRetryable`) | The host stays `.neverActivated`, distinct from a cancellation landing after evaluation |
| extension-host-027 | define-vscode-member-refuses-terminal-or-disposed | Defining a member on a disposed, cancelled, or failed host (traced to `ExtensionHostTests.definingAMemberOnADisposedHostIsRefused`, `definingAMemberOnACancelledHostIsRefused`, `definingAMemberOnAFailedHostIsRefused`) | Each call throws the matching refusal without queuing or installing the definition |
| extension-host-028 | define-vscode-member-withdraws-on-refusal | Defining a member on an unknown namespace (traced to `ExtensionHostTests.definingAMemberOnAnUnknownNamespaceIsRefused` and `aRefusedDefinitionIsWithdrawnSoTheHostStillActivates`) | The call throws `.vscodeMemberNotDefinable`; the host can still activate afterward |
| extension-host-029 | live-value-re-read-per-access | A member defined after activation is live immediately (traced to `ExtensionHostTests.aMemberDefinedAfterActivationIsLiveImmediately`) | The new definition is callable from JavaScript without a second activation |
| extension-host-030 | timer-delay-clamped-nan-safe | An impossible timer delay is clamped rather than trapped (traced to `ExtensionHostTests.anImpossibleTimerDelayIsClampedRatherThanTrapped`) | The extension's `setTimeout` call does not crash the process; the delay is clamped to the documented ceiling |
| extension-host-031 | timer-delay-clamped-nan-safe | `clampedTimerDelaySeconds` boundary sweep: an ordinary delay, zero, the largest `Double`, infinity, `NaN`, a negative value, the ceiling itself, and the `setTimeout` limit (traced to `ExtensionHostTimerClampTests.anOrdinaryDelayIsConverted`, `zeroIsAZeroSleep`, `theLargestDoubleIsClamped`, `infinityIsClamped`, `nanBecomesZero`, `negativeIsImmediate`, `theCeilingItselfIsHonoured`, `theCeilingIsTheSetTimeoutLimit`, `everyAnswerIsRepresentable`) | `NaN` maps to `0`; a negative value maps to an immediate fire; infinity and any value above the ceiling map to the ceiling; every result is representable by `Duration.seconds` |
| extension-host-032 | describe-reentrancy-bounded | A thrown value that throws while being described (traced to `ExtensionHostTests.aThrownValueThatThrowsWhileBeingDescribedIsNotFatal`) | The description falls back to the fixed literal; the process does not crash from unbounded recursion |
| extension-host-033 | activate-refuses-when-disposed-or-terminal | An extension replacing `Function.prototype.call` to fake activation (traced to `ExtensionHostTests.anExtensionThatReplacesFunctionPrototypeCallCannotFakeActivation`) | The host's activation outcome is unaffected by the hostile prototype tampering |
| extension-host-034 | not-implemented-recorded-once-per-member | The activation context's members are recorded stubs, and `subscriptions` is a real array not recorded as a miss (traced to `ExtensionHostTests.theActivationContextIsARecordedStub` and `contextSubscriptionsIsARealArrayAndIsNotRecordedAsAMiss`) | Every context member except `subscriptions` throws-and-records; `subscriptions` behaves as a genuine mutable array |
| extension-host-035 | installer-reconcile-identity-not-identifier | An entry point edited on disk, changing its `FileSignature` while the manifest stays byte-identical, followed by `reconcile()` | The running installation for that identifier is disposed and rebuilt rather than left running the stale code |
| extension-host-036 | installer-reconcile-dispose-before-rebuild | Verifying subscriptions are disposed before the adaptors during teardown (traced to `ExtensionHostInstallerTests.subscriptionsAreDisposedBeforeTheAdaptors`) | `host.disposeSubscriptions()` runs and completes before any of the eight adaptors are disposed |
| extension-host-037 | workspace-scan-race-safe-on-root-return | Workspace roots moving A to B to A while a scan of B is still in flight (traced to `ExtensionHostInstallerTests.workspaceRootsAToBToAGuardNeverFreezesInTheStaleMiddleScan`) | The stale B scan result is discarded; the installer re-enters scanning for the live roots rather than deadlocking |
| extension-host-038 | installer-bring-up-replays-open-documents-live | The `openDocumentLanguageIDs` seam replaying activation for an already-open language (traced to `ExtensionHostInstallerTests.openDocumentLanguageIDsSeamActivatesAnAlreadyOpenLanguage`) | A newly installed extension declaring `onLanguage:` for the already-open language activates immediately |
| extension-host-039 | not-implemented-ledger-dedup-by-key | Two extensions sharing one ledger stay attributed separately (traced to `ExtensionHostTests.oneLedgerKeepsTwoExtensionsApart`) | Each extension's rows carry its own `extensionIdentifier`; no row is merged across extensions |
| extension-host-040 | not-implemented-ledger-dedup-by-key | The ledger's first-stamp and use/probe accounting rules (traced to `NotImplementedLedgerTests.theFirstStampIsKept`, `aProbeObeysTheSameStampRule`, `usesAndProbesShareARowAndNotACounter`, `aProbeOnlyRowHasNoUses`) | The first access timestamp never moves; a probe-only row reports zero hard uses; a mixed row reports both counts on one row |
| extension-host-041 | not-implemented-ledger-accessors-sorted | The ledger's two read accessors agree on order, filtered before sorted (traced to `NotImplementedLedgerTests.theListIsSortedRatherThanChronological`, `oneExtensionsAccessesAreSortedAndFiltered`, `theTwoAccessorsAgree`) | `accesses` and `accesses(for:)` both report rows ordered by extension then member path, and agree on the subset for one extension |

## Edge Cases

- **Null/empty input**: An extension manifest with neither `main` nor `browser` is not an error at all — `noEntryPoint` is thrown only if `activate()` is called; a manifest-only extension that contributes solely through its manifest never calling `activate()` is legal and unremarkable.
- **Boundary values**: `clampedTimerDelaySeconds(milliseconds:)` is exercised across `0`, the largest representable `Double`, `+.infinity`, `.nan`, a negative value, the documented 32-bit `setTimeout` ceiling itself, and one millisecond past it — every one of those inputs must produce a `Duration.seconds`-representable result rather than a trap.
- **Boundary values — timer id truncation**: `cancelTimer(rawTimerID:)` receives the raw `Double` an extension wrote to `clearTimeout`/`clearInterval` rather than an `Int32`, specifically so that an id like `4294967297` (one past `Int32.max`) is rejected outright instead of being silently truncated by JavaScriptCore's `ToInt32` coercion onto an unrelated live timer with id `1`.
- **Concurrent access — shared activation**: Two or more callers invoking `activate()` concurrently on the same host share one `Task`/one outcome; a cancellation from any one of them ends the activation for all of them, per activate-cancellation-shared.
- **Concurrent access — activation racing teardown**: `callActivate` reads `activationState` (rather than an ad-hoc `isDisposed` check) immediately before installing its continuation, because a host observer invoked from inside the extension's own top-level code can call `dispose()` mid-evaluation, and the continuation must not be installed on a host already told to stop.
- **Concurrent access — workspace scan racing a moving workspace**: `startWorkspaceScanIfNeeded()`'s completion re-reads the live workspace roots rather than trusting the roots it started with, specifically to cover an A-then-B-then-back-to-A root change while a scan of B is still running; recording B's result under a workspace now showing A would both misfire `workspaceContains:` activations and leave `completedScan` permanently wrong about which project is open.
- **Concurrent access — double command press during activation**: `dispatchAfterActivation` retires the activation-stub token with `if let` rather than `guard let`, because a user pressing an activation-triggering command twice before the extension finishes activating queues two dispatches, and a `guard`-based admission ticket would silently drop the second press.
- **Error states — hostile JavaScript**: An extension that replaces `Function.prototype.call`/`.apply`, or throws a self-referential `Proxy` from its own top-level code (`aPoisonedFunctionPrototypeApplyCannotSilenceTimerCallbacks`, `aThrownValueThatThrowsWhileBeingDescribedIsNotFatal`), must not be able to fake a successful activation, silence a timer callback, or crash the host process via unbounded native recursion during exception description.
- **Error states — a rejection with no `Error` shape**: `callActivate` reports a rejected `activate()` promise whose rejection reason is not an `Error` instance (`aRejectionThatIsNotAnErrorIsStillReported`) as an `activationThrew` failure rather than crashing or silently succeeding.
- **Error states — a `.then` getter that throws**: A thenable whose `.then` property getter itself throws leaves `callActivate` through the `pendingException` path rather than through the shim's `done` callback, and is reported as a failure rather than left to hang the activation forever (verified in real JavaScriptCore, per the source comment on `callActivate`).
- **Error states — adaptor spells a namespace wrong**: `defineVSCodeMember` called with a namespace the shim's table does not have is the *adaptor's* bug, not the extension's; `applyOrWithdraw` withdraws the bad definition and logs it with the calling adaptor's `fileID:line`, so the member stays a not-implemented stub on every later activation rather than failing every future `activate()` identically.
- **Offline/disconnected**: Not applicable in the networking sense — this component performs no networking of its own; the closest analogue is a workspace that closes mid-scan, covered above under concurrent access.
- **Error states — incomplete workspace scan**: see the open question on workspace-scan-incomplete-signal above.

## Configuration

| Setting | Type | Default | Description |
|---------|------|---------|--------------|
| `ExtensionHost.maximumTimerDelayMilliseconds` | `Double` (`static let`) | `2_147_483_647` | The signed 32-bit `setTimeout` ceiling in milliseconds (about 24.8 days) that every timer delay is clamped against. |
| `ExtensionHostInstaller.scanDepthLimit` | `Int` (`nonisolated static let`) | `6` | How many directory levels deep the `workspaceContains:` scan descends before pruning. |
| `ExtensionHostInstaller.scanEntryLimit` | `Int` (`nonisolated static let`) | `20_000` | The maximum number of file paths the workspace scan collects before stopping. |
| `ExtensionHostInstaller.skippedDirectoryNames` | `Set<String>` (`nonisolated static let`) | `[".build", ".git", ".svn", ".venv", "DerivedData", "Pods", "__pycache__", "build", "dist", "node_modules", "target", "vendor"]` | Directory names the workspace scan never descends into. |
| `ExtensionHostSeams.fileSystemService` | `FileSystemServicing` | `FileSystemService()` | The shared file-system service `vscode.workspace.fs` runs through across every host; defaulted so only a test supplies a double. |
| `NotImplementedLedger.now` | `@MainActor () -> Date` | `{ Date() }` | The injected clock `firstAccess` is stamped from, overridden in tests to make the first-stamp-is-kept rule assertable. |

## Deep Linking

Not applicable: none of `ExtensionHost.swift`, `ExtensionHostInstaller.swift`, or `NotImplementedLedger.swift` defines a URL scheme, route, or navigation target.

## Localization

None of the three files defines a user-facing localized string. Every string surfaced by `ExtensionHostError.errorDescription`, the `ExtensionHostInstallation`/`ExtensionHostInstaller` log lines, and `NotImplementedLedger`'s recorded member paths is either a developer-facing diagnostic (hardcoded English, naming an extension identifier, a namespace path, or a `file:line` origin) or extension-authored text passed through verbatim (a `console.*` message, a thrown exception's own message and stack). None of it is routed through `Bundle.localizedString` or an `.nls.json`-style substitution; that localization pass belongs to `ExtensionManifest`/`ExtensionManifestLocalization` for the extension's own manifest strings, not to this layer.

## Accessibility Options

Not applicable: none of these three files has UI of its own, so none responds to Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: none of the three files declares a feature-flag key or contains conditional feature-gating logic.

## Analytics

Not applicable: none of the three files emits an analytics or event-tracking call; the only instrumentation is the `OSLog`/`Logger` calls documented under Logging below.

## Privacy

- **Data collected**: `ExtensionHost` reads the extension's own bundled JavaScript entry point off disk and runs it; `NotImplementedLedger` records extension-authored identifiers and API member-path strings an extension reached for. None of the three files reads or transmits a credential, token, or other secret value of its own.
- **Extension-authored content is privacy-annotated, not filtered**: Every OSLog interpolation of extension-controlled text — `console.*` output (`handleConsole`), an extension identifier, a thrown exception's message and stack (`describe(_:)`), a `defineVSCodeMember` origin, a member path recorded in the ledger — is marked `privacy: .public` throughout `ExtensionHost.swift` and `ExtensionHostInstaller.swift`. This is a deliberate choice to keep extension diagnostics readable in the system log rather than redacted, not an oversight; it means an extension author's own file contents, console output, and error text are treated as debuggable diagnostic data, not as a secret the host must protect.
- **Storage**: `NotImplementedLedger.entries` and `ExtensionHost`'s runtime state are in-memory only for the life of the process; nothing in these three files persists an entry to disk.
- **Transmission**: Not applicable — none of the three files performs networking.
- **Retention**: A `NotImplementedLedger` entry lives for the life of the ledger instance (typically the app process); `ExtensionHost` and `ExtensionHostInstallation` state is released on `dispose()`.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (falls back to `"nil"` if unset, via the shared `Loggable` protocol) | Category: `ExtensionHost` and `ExtensionHostInstallation`/`ExtensionHostInstaller` respectively.

| Event | Level | Message |
|-------|-------|---------|
| A `console.*` call at any level (`.debug`/`.info`/`.warn`/`.error`/`.log`) | debug / info / warning / error / log (matching the console level) | `[<identifier>] <text>` |
| A `defineVSCodeMember` definition the shim refused, withdrawn from the replay queue | error | `Extension '<identifier>' withdrew the definition of '<name>' on '<namespacePath>', declared at <origin>: the shim refused it, so that member stays a not-implemented stub on every later activation` |
| `disposeSubscriptions()` could not call into the runtime at all | error | `Extension '<identifier>' could not dispose its context.subscriptions.` |
| One subscribed disposable threw while being disposed | error | `Extension '<identifier>' registered a disposable that threw while being disposed: <failure>` |
| `vscode.Uri` could not be installed on a fresh runtime | error | `Extension '<identifier>' could not have 'vscode.Uri' installed (<message>); it stays the shim's not-implemented stub` |
| An eagerly-installed `vscode.*` member (from `installVSCodeMembers`) failed to install | error | `Extension '<identifier>' could not have 'vscode.<memberName>' installed (<message>); it stays the shim's not-implemented stub` |
| The extension's module failed to compile | error | `Extension '<identifier>' would not compile: <message>` |
| The extension threw while its module was loading, or from a fired timer | error | `Extension '<identifier>' threw while loading: <message>` / `Extension '<identifier>' threw from a timer: <message>` |
| The extension threw from `activate()` | error | `Extension '<identifier>' threw from activate(): <message>` |
| An extension exports no `activate()` function | info | `Extension '<identifier>' exports no activate() function` |
| An unimplemented member reached for, first access only | notice | `Extension '<identifier>' reached for '<memberPath>', which is not implemented yet` |
| A negative feature-detection probe, first probe only | notice | `Extension '<identifier>' checked for '<memberPath>' and was told it does not exist` |
| A timer task finished that was never counted as running (an assertion failure in Debug) | fault | `Extension '<identifier>' finished a timer task that was never counted as running` |
| A restored webview panel or contributed view names an extension that is not installed | notice | `The contributed webview view '<viewID>' names extension '<identifier>', which is not installed; its pane keeps its placeholder` (and the tree-view/webview-panel equivalents) |
| More than one installed extension claims a restored webview panel's view type | error | `<count> installed extensions claim webview panel type '<viewType>'; '<identifier>' gets it` |
| An extension's `onCommand:` id is already registered by something else | notice | `Extension '<identifier>' declares 'onCommand:<id>', but '<id>' is already registered: that trigger will not activate it` |
| An extension activated without registering a command its manifest contributes | error | `Extension '<identifier>' activated without registering '<commandID>', a command its manifest contributes` |
| A status bar item's command failed to execute | error | `A status bar item's command '<command>' did not run: <error>` |

## Platform Notes

- **AppKit / UIKit**: This is the source. `ExtensionHost.swift` is part of `AgenticToolkitCore`-adjacent macOS-only code importing `JavaScriptCore` and `OSLog`; `ExtensionHostInstaller.swift` additionally imports `AppKit` for `NSWindow`/`NSAlertMessagePresenter` (the `frontWindow` seam) and `AgenticDeveloperToolkitUI` for the pane/presenter types the eight adaptors are built over. There is no UIKit port target in this repository today.
- **SwiftUI**: Neither file has a SwiftUI dependency. A SwiftUI host wanting to observe `ExtensionHost.onConsoleMessage` or `ExtensionHostInstaller.installations` would wrap them in an `@Observable` adapter, since neither type publishes `@Published`/`@Observable` state directly.
- **Compose**: A Kotlin port has no `JavaScriptCore` equivalent; the nearest analogue is embedding a JS engine such as J2V8 or a WebView-hosted `Duktape`/`QuickJS` binding, with the same one-VM-per-process, one-context-per-extension shape. `@MainActor` confinement maps to a single-threaded `CoroutineDispatcher` (e.g. `Dispatchers.Main`) every call is confined to; the off-main compile step maps to `withContext(Dispatchers.Default)` for the parse, resuming on `Dispatchers.Main` to run the module. `Task`-based timers map to `Handler(Looper.getMainLooper())` or a coroutine `delay`-loop that is explicitly cancellable, mirroring dispose-cancels-every-timer.
- **React/Web**: A TypeScript/Node host has no analogue for running a *second* JavaScript VM inside JavaScript at all; the closest real-world precedent is VS Code's own extension host process, which this component is deliberately modeled after in miniature (one process boundary per extension there, one `JSContext` per extension here). A web-hosted port would instead run each extension inside its own Web Worker or iframe sandbox, with `postMessage` standing in for the `__host` block-table bridge, and would need its own explicit timer-cancellation-on-teardown discipline since a Worker does not enforce it for you.
- **WinUI 3**: A .NET port would host each extension's JavaScript in a `ChakraCore`/`ClearScript` (V8 or JScript) engine instance, mirroring the one-VM-shared, one-context-per-extension shape `JSVirtualMachine`/`JSContext` gives here. `@MainActor` confinement maps to requiring every call to originate on the UI thread (`DispatcherQueue.HasThreadAccess`), with the compile-only off-thread step mapped to `Task.Run` for the parse, resuming on the `DispatcherQueue` to run the module — the same split `compile-runs-nothing` documents. `Task`-based timers map to `DispatcherQueueTimer` or a cancellable `Task.Delay` loop; the NaN-safety concern in `clampedTimerDelaySeconds` has a direct analogue, since `TimeSpan.FromMilliseconds(double.NaN)` throws rather than trapping the process, so the same `Math.Max`/`Math.Min` clamp order is required before constructing the `TimeSpan`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/Host/` |

## Design Decisions

**Decision**: `activationState` is a single computed property with a fixed, documented precedence order (disposed, activated, terminal, activating, neverActivated) rather than a stored enum or a set of independent boolean flags each guard re-derives.
**Rationale**: The source's own comment states four prior rounds of fixes were each a correct answer to the route just demonstrated, and each left the resulting state reachable by another route because the state had no name — only a scatter of booleans each guard re-derived for itself. Naming the precedence once and reading it everywhere ends that cycle; `.terminal` outranking `.activating` specifically matters because `markTerminal(.failed)` runs inside `performActivation`'s `catch` several main-actor jobs before `activate()`'s own `defer` clears `activationTask`, and a second caller arriving in that window must see the same terminal answer as every later caller.
**Approved**: pending

**Decision**: `activate()` has no internal timeout, and the only two ways to end a suspended activation are cancelling the calling task or calling `dispose()`.
**Rationale**: A real extension may legitimately await a network round trip during activation, and a host that gave up at some fixed *n* seconds would report a failure that did not happen. Cancellation is the idiomatic Swift escape a caller already reaches for when it wants a timeout of its own, and `dispose()` is the unconditional teardown escape for every other case.
**Approved**: pending

**Decision**: `moduleEvaluated` — set exactly once, on the line immediately before the shim's `run` call — is the single field that decides whether a failure spends the host permanently or leaves it retryable, rather than inferring that boundary from which `do`/`catch` block a failure surfaced in.
**Rationale**: `compileModule` and `evaluateModule` both throw with zero extension statements executed in some paths (a syntax error, a missing shim) and with the module fully run in others; testing a single boundary field rather than the shape of the `catch` block is what lets `endActivation`'s cancellation path and `performActivation`'s failure path agree on exactly the same rule without duplicating it. The source states a prior version inferred terminality from the `do` block and incorrectly told a host whose extension file "merely would not parse" that its code had already run.
**Approved**: pending

**Decision**: Teardown is three separable phases in a fixed order — the extension's own `context.subscriptions`, then the eight adaptors, then `ExtensionHost.dispose()` — rather than one combined sweep.
**Rationale**: Every subscription entry reaches back through an adaptor (a registered command, an open panel, an owned collection), so subscriptions must be disposed while the adaptors are still standing; the adaptors' own withdrawal sweeps in turn call back into JavaScript (a panel's `onDidDispose`), so they must run before the runtime is released. The source notes an earlier version ran subscriptions last, inside `host.dispose()`, and a `dispose` block that called an already-withdrawn command silently dropped the work because `executeCommand` answers a rejected promise a `dispose` block never awaits.
**Approved**: pending

**Decision**: `clampedTimerDelaySeconds(milliseconds:)` computes `min(max(0, milliseconds), maximumTimerDelayMilliseconds)`, with the clamp floor as the *first* argument to `max`.
**Rationale**: `Duration.seconds(Double)` traps on any value it cannot represent, and the inputs reaching this function are the whole of `Double` including `NaN` and both infinities from one arbitrary `setTimeout` call. Swift's `max(x, y)` returns `x` for any comparison against `NaN` (every comparison against `NaN` is `false`), so `max(0, .nan)` is `0` while `max(.nan, 0)` is `NaN` — the argument order, not the choice of `max` before `min`, is what prevents a single extension's malformed `setTimeout` argument from crashing the whole process. The source notes this was confirmed by a mutation-testing survivor, not merely reasoned from first principles.
**Approved**: pending

**Decision**: `ExtensionHostInstaller.reconcile()` keys "already installed" on `InstalledIdentity` — the manifest plus directory plus the entry point's `FileSignature` (size and modification date) — rather than on the extension's bare identifier.
**Rationale**: `ExtensionRegistry.loadAll()` re-reads every manifest from disk on every rescan, so an extension whose author edited only its *code* (leaving the manifest byte-identical) previously produced a `LoadedExtension` the installer could not distinguish from the one already running, leaving the old code executing while the registry, contribution points, and settings UI all showed the new manifest. A `nil`-equals-`nil` signature (an entry point that cannot be resolved or stat'd) deliberately keeps the currently running host rather than tearing it down for a rebuild that would fail identically.
**Approved**: pending

**Decision**: `startWorkspaceScanIfNeeded()`'s completion handler re-reads the live workspace roots and compares them against the roots the scan was started with, rather than trusting `scanningRoots` alone.
**Rationale**: `scanningRoots` alone cannot distinguish a scan superseded by a *newer* scan (safe to discard) from the workspace moving from A to B and back to A while B's scan is still running — recording B's result at that point would file it as the answer for a workspace now showing A, replay it at every extension, and leave `completedScan` permanently wrong until another `workspaceDidChange()` happens to correct it. Comparing live roots and re-entering the scan when they disagree closes that hole at the cost of one extra idempotent call.
**Approved**: pending

**Decision**: `dispatchAfterActivation(commandID:arguments:)` retires the activation-stub token with `if let token = stubCommands.removeValue(forKey:)` rather than `guard let token = ... else { return }`.
**Rationale**: Activation is asynchronous, so a user pressing the same activation-triggering command twice before the extension finishes activating queues two dispatches, each carrying its own arguments. A `guard`-based admission ticket let only the first dispatch pass and silently dropped the second on the floor; forwarding on its own merits regardless of whether the token is still present ensures every invocation is honored.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |

`separation-of-concerns` passes because `ExtensionHost` delegates entry-point path resolution to `ExtensionResourcePath`, activation-trigger matching to `ActivationEventMatcher`, and manifest structure to `ExtensionManifest`/`LoadedExtension`, keeping its own responsibility limited to running one extension's JavaScript; `ExtensionHostInstaller` in turn delegates code identity to `InstalledIdentity`/`FileSignature`, per-namespace adaptor behavior to the eight `MainThread*` types, and unimplemented-member bookkeeping to the standalone `NotImplementedLedger`, none of which any of these three files re-implements. `unit-test-coverage` passes: `ExtensionHostTests.swift` (75 `@Test` functions), `ExtensionHostInstallerTests.swift` (6), `ExtensionHostTimerClampTests.swift` (9), and `NotImplementedLedgerTests.swift` (14) together exercise entry-point resolution and refusal, the full activation-state precedence and terminal-boundary contract, cancellation-versus-failure semantics, the complete timer lifecycle including every clamp boundary, `defineVSCodeMember` across every host state, hostile-JavaScript defenses, the ledger's dedup/probe/sort contract, and the installer's identity-based reconciliation and workspace-scan race guard — as traced in the Conformance Test Vectors above. `fault-tolerance` passes because a compile or module-load failure that runs no extension code leaves the host retryable rather than spent (failure-before-boundary-is-retryable), a thrown subscription disposable never strands the rest of the teardown list (dispose-subscriptions-idempotent), and an adaptor's misspelled namespace withdraws itself rather than failing every future activation (define-vscode-member-withdraws-on-refusal). `idempotent-operations` passes because `activate()` shares one outcome across concurrent callers and is a no-op once activated (activate-idempotent-shared-outcome), `dispose()` and `disposeSubscriptions()` are both safe to call more than once (dispose-idempotent, dispose-subscriptions-idempotent), and `reconcile()` leaves an extension whose identity has not moved untouched. `explicit-error-handling` is `partial`: every activation-time failure is a typed, `Equatable` `ExtensionHostError` with its own `errorDescription`, but `ExtensionHostInstaller.scan(roots:)` silently swallows a `resourceValues(forKeys:)` failure via `try?` (treating an unreadable directory entry as simply "not a directory" and continuing) with no completeness signal analogous to `ExtensionRegistry`'s own `establishedIdentifiers`/`readEverything` pattern for the same class of failure — see the open question on workspace-scan-incomplete-signal above.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
