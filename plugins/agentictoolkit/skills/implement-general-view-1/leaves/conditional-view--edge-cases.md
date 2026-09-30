<!-- leaf: implement-general-view-1/conditional-view--edge-cases · source: conditional-view.md -->

# ConditionalView

## Edge Cases

- Null/empty input: `setting` (`UserSetting<Value>`), `child` (`NSView`),
  and `isVisible` (`@escaping @MainActor (Value) -> Bool`) are all
  non-optional, typed constructor parameters, so Swift's type system rules
  out `nil` for any of the three; the initializer needs no nil-handling path
  because none of its parameters can be `nil`. This is a consequence of the
  type system, not a behavior `ConditionalView` itself implements.
- Boundary values: Not applicable in general — `Value` is a caller-chosen
  `Codable & Sendable` type (a `String`, a `Bool`, an enum, etc.) with no
  minimum/maximum intrinsic to `ConditionalView` itself; whatever boundary a
  particular `Value` type has belongs to the caller's `isVisible` predicate,
  not to this component.
- Concurrent access: Not applicable — the class is declared `@MainActor`
  (see **confines-to-main-actor**), and `UserSettingObserver`'s own
  `onChange` delivery is scheduled on the main dispatch queue, so every
  read of `observer.value` and every write to `isHidden` is serialized on
  the main actor.
- Error states: Not applicable — every operation in
  `ConditionalView.swift` (evaluating `isVisible`, comparing `isHidden`,
  calling `onVisibilityChange`) is a synchronous, non-throwing call; no
  `try`, `Result`, or error-producing API appears in source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads an in-process `UserSetting` value
  through `UserSettingObserver`.
- Asynchronous delivery of external setting changes: see
  **reflects-setting-change-asynchronously**.
- Use outside a `SelfHidingSettingsView`-aware container: `ConditionalView`
  conforms to `SelfHidingSettingsView` specifically so `GroupView`'s
  `addSettingSubview` can subscribe to `onVisibilityChange` and collapse a
  card row's padding and hairline. A `ConditionalView` placed in a container
  that never reads `onVisibilityChange` still hides `child`'s content
  correctly, but any space that container reserves around the row is
  unaffected — closing up that space is the responsibility of the hosting
  container, not of `ConditionalView` itself.
