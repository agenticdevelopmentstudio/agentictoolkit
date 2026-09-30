<!-- leaf: implement-general-view-1/dismissible-hint-view--part-2 · source: dismissible-hint-view.md -->

# DismissibleHintView — continued (part 2)

## Platform Notes

- **SwiftUI**: Bind `dismissedSetting`'s `@Published` value into `@State` (or
  observe it via a Combine publisher) and use structural conditional
  inclusion, `if !dismissed { VStack(alignment: .leading) { Text(text).font(.caption).foregroundStyle(.secondary); Button(buttonTitle) { dismissed = true } } }`,
  rather than `.hidden()` — SwiftUI removes the branch not taken from the
  view hierarchy the same way a hidden `NSView` drops out of an
  `NSStackView`, which is what `initial-visibility` and `visibility-update`
  ultimately exist to drive for a hosting container. Persist the tap through
  the same setting-backed store before flipping local state, mirroring
  `dismiss-persistence`. Because the `if` branch removes the view from the
  hierarchy structurally, the hosting container's own body re-evaluates and
  lays out around the gap automatically on the next diff — no
  `onVisibilityChange`-equivalent callback is needed for a SwiftUI-hosted
  container the way a fixed-layout `NSStackView`/`GroupView` needs the
  AppKit source's explicit notification.
- **Compose**: Collect the setting as `State<Boolean>` via `collectAsState()`
  and wrap the `Column { Text(...); Button(...) }` composition in `if
  (!dismissed) { ... }`. Persist the dismissal through the same
  `DataStore`/`SharedPreferences`-backed setting the composable observes,
  mirroring the durable, restart-surviving nature of `dismiss-persistence`;
  Compose's own recomposition already skips redundant redraws for an
  unchanged `State` value, so no extra guard is needed to mirror
  `visibility-write-guard`. Because `if (!dismissed)` removes the composable
  from composition, the hosting container recomposes and reflows around the
  gap on its own — Compose's declarative recomposition is itself the
  container-collapse signal, so no explicit `onVisibilityChange` analog is
  required the way the AppKit source's fixed-layout hosting `GroupView`
  needs one.
- **React/Web**: Subscribe to the setting's store with a hook (e.g.
  `useSyncExternalStore`) and render conditionally,
  `{!dismissed && <div className="hint"><p>{text}</p><button onClick={() => setDismissed(true)}>{buttonTitle}</button></div>}`.
  Route the click handler through the same persisted store the subscription
  reads, so a page reload still respects a prior dismissal, mirroring
  `dismiss-persistence` and the durability documented under Privacy. Because
  `{!dismissed && …}` removes the element from the rendered tree, React's own
  re-render lays out the surrounding flow around the gap automatically — the
  DOM's normal flow layout is the container-collapse signal, so no explicit
  `onVisibilityChange`-equivalent callback is required the way the AppKit
  source's fixed-layout hosting `GroupView` needs one.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/DismissibleHintView.swift`,
  with layout constants from `ViewLayout.swift`, the `SelfHidingSettingsView`
  contract from `GroupView.swift`/`SettingsViewProtocol.swift`, the
  persisted-setting plumbing from `UserSetting.swift`, and the theme
  synchronization from `ThemeBinding.swift`'s `observeTheme`. A macOS-only
  (`import AppKit`) `NSView` subclass, `@MainActor`, inside the
  `ComposableSettings` namespace. Beyond the cross-platform behavior in
  Behavioral Requirements, the AppKit implementation: exposes `textLabel` and
  `dismissButton` as public, read-only properties (`NSTextField`/`NSButton`)
  so a caller can inspect the exact instances the view displays; disables
  `translatesAutoresizingMaskIntoConstraints` on itself and on the internal
  stack; pins the stack's top/leading/trailing/bottom anchors to its own
  corresponding edges with no additional constant (`pinToEdges`); and traps
  with a fatal error on both `init(coder:)` and the frame-only
  `init(frame:)`, since the only supported construction path is the
  designated `init(text:dismissedSetting:buttonTitle:)`. There is no UIKit
  code path in source; a UIKit port would replace
  `NSTextField`/`NSButton`/`NSStackView` with `UILabel`/`UIButton`/
  `UIStackView`, use `UIView.isHidden` (the same removal-from-layout
  semantics apply within a `UIStackView`), would still need its own
  `translatesAutoresizingMaskIntoConstraints`/pinning equivalent, and would
  have no `NSCoder`-vs-frame initializer split to fatal-error on the way this
  source's designated-initializer-only construction does.
- **WinUI 3** (the reason this recipe exists): Prefer an inline `InfoBar`
  (`IsOpen` bound one-way to the observed setting via a converter,
  `IsClosable="False"`, `Severity="Informational"`) or a `StackPanel` whose
  `Visibility` is bound the same way, over `TeachingTip` — a `TeachingTip` is
  a light-dismiss popup that floats outside the layout flow and can't
  collapse a card row's own padding and hairline the way
  `self-hiding-conformance`/`onVisibilityChange` needs to, and its own
  light-dismiss/close paths would fall out of sync with a one-way
  `IsOpen`/`Visibility` binding driven solely by the setting. Bind
  `IsOpen`/`Visibility` one-way, via `x:Bind`, to a value converter over the
  observed setting (`IsOpen="{x:Bind Setting.Value, Converter={StaticResource
  IsDismissedToIsOpenConverter}, Mode=OneWay}"`), guarding the converter so it
  only flips the bound value when the resolved value actually differs from
  the current one — the WinUI analog of
  `visibility-write-guard`/`visibility-change-notification`. Set the
  `InfoBar`'s `Message` (or the `StackPanel`'s child `TextBlock.Text`) to the
  hint text (mirroring `text-label-theming`'s theme-styled caption text), and
  bind the dismiss control's content/title to `buttonTitle` — never hardcode
  `"Got It"` — with its click handler writing the observed setting's
  persisted value to `true` — the same write-through-the-store-first pattern
  `dismiss-persistence` uses, rather than setting `IsOpen`/`Visibility` to
  closed/collapsed directly in the click handler — so a restart still
  respects a prior dismissal (see Privacy) and the async round trip
  documented in Edge Cases has a direct analog.

## Design Decisions

- **Decision**: Copy the observed setting's current value directly into
  `isHidden` at the end of `init` (`self.isHidden = self.observer.value`),
  rather than routing the initial state through the same `onChange`
  guard/notify path used for later changes.
  **Rationale**: A synchronous initial assignment prevents the view from
  rendering visible-by-default until the observer's first,
  asynchronously-delivered change notification arrives, and avoids firing
  `onVisibilityChange` for a hosting `GroupView` before that view has even
  finished adding this row — the same reasoning the sibling `ConditionalView`
  recipe (`agentictoolkit://recipes/conditional-view`) documents for its own
  initial-visibility evaluation.
  **Approved**: pending
- **Decision**: Guard the `onChange` handler with `dismissed != self.isHidden`
  before writing `isHidden` or invoking `onVisibilityChange`.
  **Rationale**: Without the guard, any redelivery of the observed setting's
  value would re-trigger a hosting `GroupView`'s separator/padding recompute
  even when this view's own visibility hasn't actually changed.
  **Approved**: pending
- **Decision**: `dismissTapped` unconditionally sets `observer.value = true`,
  with no check of the setting's current value first.
  **Rationale**: The visible-to-dismissed transition only runs one way —
  there is no "undismiss" affordance on the view — so an unconditional write
  costs nothing extra even if tapped on an already-dismissed hint; the
  visibility guard lives in the `onChange` handler, not in the tap handler.
  **Approved**: pending
- **Decision**: Route dismissal through the persisted `dismissedSetting` and
  its `UserSettingObserver`'s asynchronous `onChange` delivery, rather than
  setting `isHidden = true` directly inside `dismissTapped`.
  **Rationale**: This makes "dismissed" a durable, app-restart-surviving fact
  (see Privacy: Storage) instead of transient view state, at the cost of the
  one-main-queue-turn delay between the tap and the view actually hiding
  documented under Edge Cases.
  **Approved**: pending
- **Decision**: Default `buttonTitle` to the English literal `"Got It"`
  rather than requiring every call site to supply a title.
  **Rationale**: Keeps single-hint call sites terse for the common case; see
  Localization for the unlocalized-default consequence this creates for call
  sites that never override it.
  **Approved**: pending
