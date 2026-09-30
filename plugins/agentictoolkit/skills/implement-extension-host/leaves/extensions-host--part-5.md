<!-- leaf: implement-extension-host/extensions-host--part-5 · source: extension-host-extensions-host.md -->

# Extension Host — continued (part 5)

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
