<!-- leaf: implement-general-view-1/dismissible-hint-view--edge-cases · source: dismissible-hint-view.md -->

# DismissibleHintView

**Rules** (cite as `implement-general-view-1/dismissible-hint-view--edge-cases#<slug>`):

- `out-nil-them-initializer-needs-nil-handling` MUST — Null/empty input: text (String), dismissedSetting (UserSetting<Bool>), and buttonTitle (String, defaulted) are all …
- `zero-content-label-per-text-label-source` MUST — Empty text (""): renders an empty wrapping label; the row still lays out with its stack spacing and pinned edges around …
- `stack-given-container-per-text-label-stack` MUST — Very long text: NSTextField(wrappingLabelWithString:) wraps rather than truncates, and no maximum width is configured …
- `main-queue-turn-level-source-traceable-consequence` MUST — Delayed dismissal (asynchronous setting round-trip): tapping dismissButton sets observer.value = true, which writes …
- `current-value-first-per-dismiss-persistence-guard` MUST — Repeated taps on dismissButton: each tap unconditionally sets observer.value = true again, with no read-back of the …

## Edge Cases

- Null/empty input: `text` (`String`), `dismissedSetting`
  (`UserSetting<Bool>`), and `buttonTitle` (`String`, defaulted) are all
  non-optional, typed constructor parameters; Swift's type system rules out
  `nil` for any of them (MUST — the initializer needs no nil-handling path
  because none of its parameters can be `nil`).
- Empty `text` (`""`): renders an empty wrapping label; the row still lays
  out with its stack spacing and pinned edges around a zero-content label
  (MUST, per `text-label` — the source has no guard against an empty
  string).
- Very long `text`: `NSTextField(wrappingLabelWithString:)` wraps rather than
  truncates, and no maximum width is configured by `DismissibleHintView`
  itself; the label's width follows whatever width the pinned stack is given
  by its container (MUST, per `text-label`; the stack's own edge-pinning that
  determines the width it's given is documented under `#platforms/swift`).
- Boundary values: Not applicable — the component's only inputs are strings
  and a `UserSetting<Bool>`; it has no caller-configurable numeric range of
  its own (the 8pt row spacing is a fixed source constant, not a
  caller-supplied boundary).
- Concurrent access: Not applicable — the class is `@MainActor` (see
  `main-actor-confinement`), and `UserSettingObserver`'s `onChange` delivery
  is scheduled on the main dispatch queue, so every read of `observer.value`
  and every write to `isHidden` is serialized on the main actor.
- Error states: Not applicable — every operation in
  `DismissibleHintView.swift` (comparing `isHidden`, wiring target/action,
  reading/writing `observer.value`) is a synchronous, non-throwing call; no
  `try`, `Result`, or error-producing API appears in source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads and writes an in-process
  `UserSetting` through `UserSettingObserver`.
- Delayed dismissal (asynchronous setting round-trip): tapping
  `dismissButton` sets `observer.value = true`, which writes through to
  `dismissedSetting.value`, persists via the underlying settings store, and
  only reaches this view's own `onChange` handler one main-queue turn later
  — through `UserSettingObserver`'s `.dropFirst().receive(on:
  DispatchQueue.main)` subscription (see `UserSetting.swift`) — not
  synchronously within the button-click call frame. A caller that taps and
  immediately inspects `isHidden` in the same call frame still sees the view
  visible; the hide happens on the following main-queue turn. This is a
  MUST-level, source-traceable consequence of the dependency this component
  observes through — the same underlying mechanism the sibling
  `ConditionalView` recipe (`agentictoolkit://recipes/conditional-view`)
  documents for its own observed setting.
- Repeated taps on `dismissButton`: each tap unconditionally sets
  `observer.value = true` again, with no read-back of the setting's current
  value first (MUST, per `dismiss-persistence`); the guard against a
  redundant *visibility* write lives in the `onChange` handler
  (`visibility-write-guard`), not in the tap handler itself, so a repeated or
  already-dismissed tap harmlessly re-assigns the same `true`.
