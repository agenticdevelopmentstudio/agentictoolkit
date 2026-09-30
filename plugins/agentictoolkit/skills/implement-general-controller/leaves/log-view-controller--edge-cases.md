<!-- leaf: implement-general-controller/log-view-controller--edge-cases · source: log-view-controller.md -->

# Log View Controller

## Edge Cases

- **Null/empty input**: `controller.lastError` being `nil` versus a non-`nil`
  string is the sole discriminator, alongside `isConnected`, for which of
  the three status branches (`connected-indicator` /
  `error-indicator` / `connecting-indicator`) applies; an empty string
  (`""`) for `lastError` is treated as non-`nil` and so is displayed
  verbatim as the error text — the same branch as any other non-`nil`
  value. `leadingToolbarItems()`/`extraTrailingToolbarItems()` returning an
  empty array (the default) is the normal case, not a special-cased branch:
  the corresponding stack view simply arranges zero subviews.
- **Boundary values**: A subclass overriding `minimumContentSize` or
  `toolbarHeight` with a value of zero or negative is not guarded against;
  the resulting `NSLayoutConstraint`s are built from that zero or negative
  constant and passed through to Auto Layout as-is. The resulting layout is
  undefined — this is an unguarded input, not documented behavior, and no
  precondition or assertion rejects it.
- **Concurrent access**: `LogController` is a `@MainActor`-isolated
  protocol, `LogViewController` itself is `@MainActor`, and
  `controller.onStateChange` is typed `(@MainActor () -> Void)?`, so state
  refreshes are always serialized on the main actor; there is no
  cross-thread mutation path to define behavior for.
- **Error states**: `controller.lastError`'s string is displayed verbatim
  with no truncation, retry affordance, or dismiss action wired anywhere;
  clicking Pause or Clear while an error is present still calls
  `togglePause()`/`clear()` unconditionally — neither call is gated on
  connection or error state.
- **Offline/disconnected state**: The Connecting state
  (`isConnected == false`, `lastError == nil`) is this component's sole
  representation of "not yet connected" or "reconnecting"; it renders
  identically whether the transport has never connected or has dropped and
  is retrying, because `LogController` exposes no separate signal for that
  distinction. Actually reconnecting/backoff behavior belongs to the
  injected `LogController` implementation (SSE/HTTP/file-tail), a separate
  component out of this recipe's scope — the component only reads the three
  properties (`isConnected`, `isPaused`, `lastError`) it is given.
