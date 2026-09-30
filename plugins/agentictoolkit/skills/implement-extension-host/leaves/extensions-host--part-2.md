<!-- leaf: implement-extension-host/extensions-host--part-2 · source: extension-host-extensions-host.md -->

# Extension Host — continued (part 2)

**Rules** (cite as `implement-extension-host/extensions-host--part-2#<slug>`):

- `activation-state-precedence` MUST
- `activate-idempotent-shared-outcome` MUST
- `activate-refuses-when-disposed-or-terminal` MUST
- `activate-no-timeout` MUST
- `activate-cancellation-shared` MUST
- `module-evaluated-terminal-boundary` MUST
- `failure-before-boundary-is-retryable` MUST
- `failure-after-boundary-is-terminal` MUST
- `terminal-reason-keeps-first` MUST
- `dispose-idempotent` MUST
- `dispose-releases-suspended-activation` MUST
- `dispose-cancels-every-timer` MUST
- `dispose-releases-context` MUST
- `dispose-subscriptions-before-context` MUST
- `dispose-subscriptions-idempotent` MUST
- `dispose-subscriptions-autoreleased` MUST
- `isolated-deinit-cancels-timers` MUST
- `define-vscode-member-refuses-terminal-or-disposed` MUST
- `define-vscode-member-replays-on-runtime` MUST
- `define-vscode-member-withdraws-on-refusal` MUST
- `deferred-value-resolved-at-apply-time` MUST
- `live-value-re-read-per-access` MUST
- `timer-delay-clamped-nan-safe` MUST
- `timer-cancel-validates-before-truncating` MUST
- `timer-task-count-asserts-not-clamps` MUST
- `console-message-always-logged` MUST
- `not-implemented-recorded-once-per-member` MUST
- `negative-probe-recorded-separately` MUST
- `entry-point-requires-browser-not-main` MUST
- `entry-point-must-not-escape-directory` MUST
- `compile-runs-nothing` MUST
- `entry-point-attributed-in-stack-traces` MUST
- `exports-required-non-empty` MUST
- `activate-absence-is-not-an-error` MUST
- `activate-rejection-getter-throw-reported` MUST

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
