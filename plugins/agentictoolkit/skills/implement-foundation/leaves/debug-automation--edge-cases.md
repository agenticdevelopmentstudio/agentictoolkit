<!-- leaf: implement-foundation/debug-automation--edge-cases · source: foundation-debug-automation.md -->

# Foundation Debug Automation

**Rules** (cite as `implement-foundation/debug-automation--edge-cases#<slug>`):

- `null-and-empty-input` MUST — DebugLaunchSwitch.init(_:) takes a non-optional String and performs no validation; an empty string "" is accepted and …
- `boundary-values` MUST — The only boundary in this component is the compile-time DEBUG/Release split itself, exercised by the two branches of …
- `concurrent-access` MUST — DebugLaunchSwitch is an immutable, Sendable value type, so concurrent reads of isOn/isOn(defaults:) from multiple …
- `error-states` MUST — None of the four files exposes a throws or failable API. UserDefaults.bool(forKey:) never throws — it returns false for …
- `colliding-switch-keys` MUST — DebugLaunchSwitch has no built-in namespacing or collision guard; two DebugLaunchSwitch values constructed with the …
- `xctest-framework-linkage-outside-an-actual-test-run` MUST — isRunningInTests reports true whenever the XCTestCase class is resolvable in the current process, per its own stated …
- `live-mutation-of-the-launch-argument-or-default-mid-process` MUST — neither isOn(defaults:) nor isEnabled caches its result; each re-evaluates its UserDefaults/NSClassFromString read on …
- `repeated-calls-with-no-intervening-state-change` MUST — calling sinkBehindDesktop(), orderFrontQuietly(), makeKeyAndOrderFrontQuietly(), or activateUnlessQuiet() more than …

## Edge Cases

- **Null and empty input**: `DebugLaunchSwitch.init(_:)` takes a
  non-optional `String` and performs no validation; an empty string `""` is
  accepted and stored as `key`, and `UserDefaults.bool(forKey: "")` is a
  legal (if useless) lookup that never crashes (MUST, see
  **switch-key-identity**).
- **Boundary values**: The only boundary in this component is the
  compile-time `DEBUG`/Release split itself, exercised by the two branches
  of `isOn(defaults:)`'s `#if DEBUG` (MUST, see
  **debug-build-reads-argument-domain** and **release-build-always-off**);
  there is no numeric range or size to bound.
- **Concurrent access**: `DebugLaunchSwitch` is an immutable, `Sendable`
  value type, so concurrent reads of `isOn`/`isOn(defaults:)` from multiple
  threads or actors require no synchronization of their own (MUST, see
  **switch-sendable-hashable-value-type**). `QuietWindowPresentation` and
  the two `@MainActor` `NSWindow` methods are confined to the main actor by
  declaration, so the compiler serializes all access to `isEnabled`,
  `resolve(isTestHost:defaults:)`, `orderFrontQuietly()`, and
  `makeKeyAndOrderFrontQuietly()` (MUST, see
  **quiet-presentation-main-actor-isolation**,
  **quiet-methods-main-actor-isolation**). `sinkBehindDesktop()` and
  `isRunningInTests` carry no actor annotation in this source file; nothing
  in `NSWindow+TestHostVisibility.swift` itself enforces that either is
  called on the main thread, though every call site in this recipe's own
  files reaches them only from an already-`@MainActor` caller (MUST, see
  **quiet-methods-main-actor-isolation**).
- **Error states**: None of the four files exposes a `throws` or failable
  API. `UserDefaults.bool(forKey:)` never throws — it returns `false` for a
  missing or non-Boolean key by Foundation's own contract — and
  `NSClassFromString` never throws. This component has no network, database,
  or file-system dependency whose unavailability it needs to report (MUST —
  there is no error path to define, not an omitted one).
- **Offline or disconnected state**: Not applicable — none of the four
  `DebugAutomation` files makes a network call or models a connectivity
  state.
- **Colliding switch keys**: `DebugLaunchSwitch` has no built-in namespacing
  or collision guard; two `DebugLaunchSwitch` values constructed with the
  same key string observe the same `UserDefaults`/launch-argument slot,
  since `Hashable`/`Equatable` conformance is exactly string equality on
  `key`. This is the documented contract — "the `UserDefaults` key, which is
  also the launch-argument name" (`DebugLaunchSwitch.swift`) — not an
  omitted guard (MUST, see **switch-key-identity**).
- **XCTest-framework linkage outside an actual test run**: `isRunningInTests`
  reports `true` whenever the `XCTestCase` class is resolvable in the
  current process, per its own stated assumption that "XCTest links its own
  framework into the runner, so the class exists in a test run and nowhere
  else" (`NSWindow+TestHostVisibility.swift`). A host process that
  happens to link `XCTest.framework` for some other reason would also report
  `true`; this is the documented assumption the check relies on, not a
  validation this file performs (MUST, see **test-host-detection**).
- **Live mutation of the launch argument or default mid-process**: neither
  `isOn(defaults:)` nor `isEnabled` caches its result; each re-evaluates its
  `UserDefaults`/`NSClassFromString` read on every call, so a value changed
  in the supplied `UserDefaults` between two calls MUST be reflected on the
  very next read (MUST, see **is-enabled-live-read**,
  **injectable-defaults-parameter**).
- **Repeated calls with no intervening state change**: calling
  `sinkBehindDesktop()`, `orderFrontQuietly()`,
  `makeKeyAndOrderFrontQuietly()`, or `activateUnlessQuiet()` more than once
  in a row, with `QuietWindowPresentation.isEnabled` unchanged between calls,
  MUST leave the window or app in the same observable state a single call
  would have produced — each is a single property assignment or a single
  AppKit ordering/activation call, not an accumulating counter (MUST, see
  **sink-level-only**, **quiet-order-front**,
  **quiet-make-key-and-order-front**, **loud-activation-behavior**).
