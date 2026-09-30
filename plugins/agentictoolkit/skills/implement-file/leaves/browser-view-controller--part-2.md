<!-- leaf: implement-file/browser-view-controller--part-2 · source: file-browser-view-controller.md -->

# File Browser View Controller — continued (part 2)

## Accessibility

- The add button carries accessibility identifier `file-browser.add-directory`
  and the remove button carries `file-browser.remove-directory`
  (`NSView.accessibilityID(_:)`, which calls `setAccessibilityIdentifier`).
- Both footer buttons set a `toolTip` (static for add, dynamic for remove —
  see Behavioral Requirements); neither sets an explicit accessibility label
  or title, and both are built with `NSImage(systemSymbolName:
  accessibilityDescription: nil)` — the symbol image is explicitly given no
  accessibility description.
- Neither footer button has an explicit accessibility label or title: both
  have an empty `title`, an image built with `accessibilityDescription:
  nil`, and no `setAccessibilityLabel`/`setAccessibilityTitle` call anywhere
  in source — only `accessibilityID(_:)` is set (see above). VoiceOver
  therefore has no developer-supplied name to announce for either button,
  only whatever generic fallback AppKit's default bezel-button accessibility
  provides.
- Not applicable: the hosted tree's own accessibility (row roles, disclosure
  state announcements, selection announcements) belongs to
  `FileTreeOutlineViewController`, a separate component with its own recipe;
  this recipe covers only what `FileBrowserViewController` itself renders and
  wires (the footer and the container).
- Not applicable: minimum tap target. This is a pointer-driven macOS control,
  not a touch surface, so the template's 44×44pt touch-target guidance does
  not apply; source gives the footer buttons no explicit width/height — their
  size comes from AppKit's intrinsic size for an accessory-bar bezel button
  with an image.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `directories` | `FileBrowserDirectories` | required (no default on the designated initializer) | The primary root plus any additional roots this browser shows. |
| `excludedURL` | `URL` | required | A directory excluded from both the tree and the watcher (e.g. a hosting document's own package). |
| `config` | `FileTreeConfig` | `.default` | Opaque-package extensions/display names and the `UserDefaults` key for custom file-type mappings. |
| `ignorePatterns` | `[String]` | `[]` | Wildcard filename patterns left out of the tree. |
| `selection` | `FileBrowserSelection` | a new, private `FileBrowserSelection()` | The shared selection object; supply one to let a host read or drive it. |
| `restoration` | `FileBrowserRestorationState` | a new, private `FileBrowserRestorationState()` | Persisted expanded/selected state; supply one to restore or persist it. |
| `documentStore` | `TextDocumentStore` | required | App-wide open-document registry, threaded to the tree for its dirty indicator. |
| `gitStatusProvider` | `GitStatusProvider?` | `nil` | A provider to reuse for whichever root it belongs to; `nil` lets each root build its own. |
| `rootURL` (convenience init) | `URL` | n/a | Shorthand that builds `FileBrowserDirectories(primary: rootURL)` with no additional roots. |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none defined in source) | `Add a directory to this project` | Add button tooltip, set as a literal `String` on `NSButton.toolTip`. |
| (none defined in source) | `Add` | `NSOpenPanel.prompt`, a literal `String`. |
| (none defined in source) | `Choose directories to show in this project's file browser.` | `NSOpenPanel.message`, a literal `String`. |
| (none defined in source) | `Remove "<name>" from this project` | Remove button tooltip when enabled; `<name>` is the selected root's last path component, interpolated into a literal `String`. |
| (none defined in source) | `Select an added directory to remove it` | Remove button tooltip when disabled, a literal `String`. |

All five user-facing strings above are assigned directly as `String`
literals to AppKit properties (`NSButton.toolTip`, `NSOpenPanel.prompt`,
`NSOpenPanel.message`) rather than through any localization key or
`NSLocalizedString` call — AppKit does not localize `toolTip`/`prompt`/
`message` the way SwiftUI's `Text` localizes a literal, so these are
genuinely unlocalized; no string-key scheme is defined for this component in
source. (The `preconditionFailure` message naming the primary root's path is
a programmer-error trap surfaced only in a crash log, not user-facing text,
and is excluded from this table.)

## Accessibility Options

- **Reduce Motion**: Not applicable. Source contains no animation —
  `loadView()`, `viewDidLoad()`, and the footer update run entirely through
  Auto Layout constraints and immediate property assignment; there is no
  `NSAnimationContext`, transition, or motion effect to reduce.
- **Increase Contrast**: Not applicable at this component's level. The
  container and footer delegate all color to `ThemedBackgroundView`'s
  semantic theme roles (`.windowBackground`, `.surface`); neither
  `FileBrowserViewController.swift` nor `ThemedViews.swift` branches on
  `NSWorkspace.accessibilityDisplayShouldIncreaseContrast`, so any contrast
  adaptation would live in the theme/palette system, not here.
- **Differentiate Without Color**: Not applicable. This view controller
  itself renders no state that is conveyed by color alone — the only color
  fills are the plain background roles above. Git-status coloring in the
  file tree is rendered by `FileTreeOutlineViewController`, a separate
  component with its own recipe.

## Privacy

- **Data collected**: Directory URLs the user explicitly chooses through the
  system `NSOpenPanel` when adding a root, plus the URL/selection state the
  user creates by clicking in the tree (held in `FileBrowserSelection`).
  Nothing is collected automatically or without a user action.
- **Storage**: This component does not itself write anything to disk or
  `UserDefaults`. Changes flow out through `FileBrowserDirectories.onChange`
  and `FileBrowserRestorationState.onChange` closures, which a host supplies
  and which decide whether and where to persist them; `FileTreeConfig`
  separately names a `UserDefaults` key (`customMappingsDefaultsKey`) that a
  different component (`CustomFileTypeMappings`) owns, not this one.
- **Transmission**: None. `FileBrowserViewController.swift` makes no network
  calls.
- **Retention**: Determined entirely by the host through the `onChange`
  closures above; this component keeps the roots and selection only in
  memory for as long as the controller and its injected objects live.

## Platform Notes

- **SwiftUI**: The source is pure AppKit (`NSViewController`), not SwiftUI.
  A SwiftUI port would replace `loadView()`'s manual `NSStackView`/
  `NSLayoutConstraint` footer with a `VStack` (tree, `Divider()`, footer
  `HStack`), replace the two `NSButton`s with `Button` views driving the same
  `addDirectory()`/`removeSelectedDirectory()` logic, and replace
  `FileBrowserSelection`/`FileBrowserDirectories` (already `Combine`
  `ObservableObject`s) with `@ObservedObject`/`@StateObject` wrappers — they
  need no redesign, only new call sites.
- **Compose**: Start from a `Column` with the tree composable, an
  `HorizontalDivider`, and a `Row` footer holding two `IconButton`s (add/
  remove) bound to the same enablement rule
  (`remove-button-enablement`). `FileBrowserDirectories`/
  `FileBrowserSelection` become a `ViewModel` exposing `StateFlow`s; the
  watch-on-appear/stop-on-disappear lifecycle maps to `DisposableEffect`
  keyed on composition entering/leaving.
- **React/Web**: The tree becomes a virtualized list/tree component; the
  footer becomes a flex row with two icon buttons calling the same add/
  remove handlers, disabling the remove button by the same rule. FSEvents
  watching has no direct web equivalent — `start-watching-on-appear`/
  `stop-watching-on-disappear` would map to subscribing/unsubscribing a
  polling or server-push channel when the component mounts/unmounts
  (`useEffect` cleanup).
- **AppKit / UIKit**: This is the source platform (AppKit/macOS). On iOS,
  `NSViewController` becomes `UIViewController`, `NSOpenPanel` becomes a
  `UIDocumentPickerViewController` configured for directories, `NSButton`
  becomes `UIButton`, and `NSStackView`/`NSBox` become `UIStackView`/a
  hairline `UIView`; the FSEvents-backed watch/stop lifecycle would need to
  move to `viewWillAppear(_:)`/`viewDidDisappear(_:)` on `UIViewController`,
  matching this file's `viewWillAppear()`/`viewDidDisappear()` exactly.
  Internally, the source tracks these per-root managers in a private
  `managersByRoot: [URL: FileTreeManager]` dictionary and gates the
  once-only load and the watch/stop toggle on private `hasLoaded`/
  `isWatching` booleans — implementation detail a conforming reimplementation
  is free to represent differently; the requirements and test vectors above
  describe only the observable load/watch behavior, never these names.
- **WinUI 3**: Model the tree as a `TreeView` (or `NavigationView` with a
  `TreeView` in its pane) hosted in a `Grid` with two `RowDefinition`s: the
  tree's row set to `*`, and a fixed-height footer row below a
  `<MenuFlyoutSeparator>`-style `Border` acting as the divider. The footer is
  a horizontal `StackPanel` with two `Button`s carrying `FontIcon`s — Segoe
  Fluent glyphs written as escaped code points rather than raw glyph
  characters, for example `\uE710` for add/plus and `\uE738` for
  remove/minus — in place of the SF Symbols; each button's
  `AutomationProperties.Name` should carry the same text the source puts in
  `toolTip`, since WinUI has no tooltip-as-accessible-name fallback to rely
  on the way this recipe's Accessibility section flags as unresolved for
  AppKit. Directory selection uses `Windows.Storage.Pickers.FolderPicker` in
  place of `NSOpenPanel`; unlike `NSOpenPanel`'s `allowsMultipleSelection`,
  `FolderPicker` returns exactly one folder per call, so multi-directory
  selection must be emulated with a loop of repeated
  `PickSingleFolderAsync()` calls, each shown to the user in turn, and the
  UI should say so explicitly (e.g. "Add another?") rather than silently
  serializing multiple picks behind what looks like one dialog. The remove button's enabled/disabled pair
  maps to a `VisualStateManager` state pair (`Enabled`/`Disabled`) toggled
  from the same `selection.selectedRoot` rule, with the `IsEnabled` binding
  driving `Button.IsEnabled` and a `ToolTipService.ToolTip` binding driving
  the dynamic message. `FileTreeManager`'s FSEvents watch has no 1:1 WinUI
  primitive; use a `Windows.Storage.Search.StorageFolderQueryResult` with a
  `ContentsChanged` handler started/stopped from the page's
  `Loaded`/`Unloaded` events, mirroring `start-watching-on-appear`/
  `stop-watching-on-disappear`.

