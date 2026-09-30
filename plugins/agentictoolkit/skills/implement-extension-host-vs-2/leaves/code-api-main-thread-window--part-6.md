<!-- leaf: implement-extension-host-vs-2/code-api-main-thread-window--part-6 · source: extension-host-vs-code-api-main-thread-window.md -->

# MainThreadWindow — continued (part 6)

## Design Decisions

- **Decision**: `showQuickPick`'s and `showInputBox`'s cancellation-token arguments are accepted and then ignored; nothing in this adaptor wires them to cancel the presenter call or reject the promise.
  **Rationale**: The presenter protocols themselves define no cancellation entry point today, so honoring the token would require a second, currently-nonexistent contract on all four presenters; accepting-and-ignoring keeps extensions that pass a token from crashing on an unrecognized argument while being honest that cancellation has no effect yet.
  **Approved**: pending

- **Decision**: `createStatusBarItem`'s `priority` is forwarded to the presenter unclamped, including `Infinity` and `-Infinity`.
  **Rationale**: VS Code's own priority is an arbitrary-precedence sort key with no documented bound; clamping it here would silently change ordering behavior an extension may depend on, and the presenter — not this adaptor — is the layer responsible for however it chooses to sort or bound priorities for display.
  **Approved**: pending

- **Decision**: Setting `tooltip` to a `MarkdownString`-shaped object or `command` to a `Command`-object-shaped value records one `NotImplementedLedger` access and drops the value rather than raising or rejecting.
  **Rationale**: Both properties are plain (non-promise-returning) setters in the VS Code API, so there is no promise available to reject and no synchronous exception path an extension would expect from a property assignment; recording the access lets the eventual not-implemented report surface the gap to whoever debugs the extension without breaking a setter extensions expect to always succeed.
  **Approved**: pending

- **Decision**: Every status bar item property mutation is applied to the presenter synchronously and immediately, with no debouncing or coalescing of rapid repeated writes.
  **Rationale**: Coalescing would require buffering state this adaptor does not otherwise keep and would change the presenter's view of intermediate states an extension's own logic might depend on (e.g. a progress indicator that sets `text` many times in a loop); the source explicitly notes it has not measured the cost of this choice and does not claim it is free, but treats correctness of intermediate state as the higher priority absent a measured problem.
  **Approved**: pending

- **Decision**: `createStatusBarItem` mints its own internal identifier from the caller's `id` plus a strictly-increasing ordinal, rather than using the caller's `id` directly as the presenter-facing key.
  **Rationale**: VS Code allows an extension to construct multiple status bar items that share the same `id`; using `id` directly as the presenter key would make the second item silently alias or overwrite the first inside this adaptor's own bookkeeping, which upstream VS Code does not do.
  **Approved**: pending

- **Decision**: A `show*Message`, `showQuickPick` or `showInputBox` promise still pending when `MainThreadWindow.dispose()` runs is left permanently unsettled rather than rejected with a teardown error.
  **Rationale**: Rejecting on teardown would require every extension awaiting one of these promises to install a catch handler solely to survive host disposal, which upstream VS Code's own analogous shutdown path does not require; leaving the promise pending matches the observable behavior of the host process disappearing without ever answering, which is what disposal actually represents.
  **Approved**: pending

- **Decision**: `showInputBox`'s and `showQuickPick`'s callback-style options (`validateInput`, and the presenter's own selection-changed callback) are invoked bound to the same `this` convention as each other, rather than each independently choosing a binding the way upstream VS Code's separate extension-host modules do.
  **Rationale**: Keeping one binding convention across both members means an extension author who learns how `this` behaves in one callback does not have to relearn it for the other; upstream VS Code's own two implementations happened to diverge here for historical reasons this adaptor does not need to preserve.
  **Approved**: pending
