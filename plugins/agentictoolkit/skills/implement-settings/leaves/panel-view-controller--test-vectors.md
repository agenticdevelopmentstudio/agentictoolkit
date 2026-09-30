<!-- leaf: implement-settings/panel-view-controller--test-vectors · source: settings-panel-view-controller.md -->

# SettingsPanelViewController

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| spvc-001 | class-declaration | Compile-time: inspect the class declaration | `SettingsPanelViewController` is declared as an `open class` inheriting `NSViewController` and conforming to `ComposableSettingsPanel` |
| spvc-002 | main-actor-isolation | Attempt to construct or mutate an instance from off the main actor | Compiler rejects the call at compile time under `@MainActor` isolation checking |
| spvc-003 | descriptor | Compile-time: attempt `instance.descriptor = otherDescriptor` after construction | Fails to compile — `descriptor` is declared `public let`, making it immutable after `init(with:)` |
| spvc-004 | default-descriptor | Construct `SettingsPanelViewController()` (no argument) | `instance.descriptor` is a freshly constructed `SettingsPanelDescriptor` with `title == ""` |
| spvc-005 | descriptor-retention | Construct `SettingsPanelViewController(with: myDescriptor)` | `instance.descriptor === myDescriptor` (the same instance, not a copy) |
| spvc-006 | coder-initialization | Attempt `SettingsPanelViewController(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| spvc-007 | root-view | Trigger `loadView()` | `instance.view === instance.settingsView`, and `instance.settingsView` is a `PanelView` |
| spvc-008 | add-group | Call `instance.addGroup(myGroup)` | `instance.settingsView`'s stack's `arrangedSubviews.last === myGroup` |
| spvc-009 | help-content-default | Read `instance.helpContent` on a plain, non-overriding instance | Returns `nil` |
| spvc-010 | effective-help-content | Read `instance.effectiveHelpContent` on a plain, non-overriding instance whose `helpContent` is `nil` | Returns `nil`; on a subclass instance overriding `helpContent` to a non-nil value, returns that same value |
| spvc-011 | hosts-own-scroll-default | Read `instance.hostsOwnScroll` on a plain, non-overriding instance | Returns `false` |
| spvc-012 | search-keywords-default | Read `instance.searchKeywords` on a plain, non-overriding instance | Returns `[]` |
| spvc-013 | protocol-default-redeclaration | Subclass `SettingsPanelViewController`, override `hostsOwnScroll` to return `true`, then access the instance through an `any ComposableSettingsPanel` existential | The existential's `hostsOwnScroll` reads `true` (the subclass override), not the protocol extension's `false` |
| spvc-014 | hosting-view-helper | Call `SettingsPanelViewController.hostingView(for: Text("Hi"))` | Returns an `NSView` that is an `NSHostingView` wrapping the given SwiftUI content |
| spvc-015 | hosting-view-sizing-options | Call `SettingsPanelViewController.hostingView(for: someView)`, inspect the returned `NSHostingView` | `sizingOptions == [.intrinsicContentSize]` |
| spvc-016 | hosting-view-autoresizing-mask | Call `SettingsPanelViewController.hostingView(for: someView)`, inspect the returned view | `translatesAutoresizingMaskIntoConstraints == false` |
