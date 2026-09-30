<!-- leaf: implement-git-client/projects-project-chooser-window · source: git-client-projects-project-chooser-window.md -->

**Rules** (cite as `implement-git-client/projects-project-chooser-window#<slug>`):

- `coordinator-required-no-default` MUST
- `window-identity-fixed-at-init` MUST
- `content-view-controller-fixed-at-init` MUST
- `coder-init-unavailable` MUST
- `main-actor-isolation` MUST
- `browser-constructed-in-chooser-mode` MUST
- `onchoose-single-invocation` MUST
- `runmodal-return-value` MUST
- `content-onfinish-drives-outcome` MUST
- `open-button-forwards-current-selection` MUST
- `cancel-button-forwards-nil` MUST
- `browser-onchoose-forwarded-unchanged` MUST
- `open-button-enablement-tracks-selection` MUST
- `open-button-initial-disabled-then-synced` MUST
- `window-close-ends-session-as-cancel` MUST
- `window-close-ignored-when-not-active-modal-session` MUST
- `runmodal-orders-out-without-closing` MUST
- `runmodal-activation-respects-quiet-presentation` MUST
- `stock-buttons-fixed-key-equivalents` MUST
- `accessibility-identifiers-fixed` MUST

# ProjectChooserWindow

## Overview

`ProjectChooserWindow` (`ProjectChooserWindow.swift`) is the app-modal
"which project?" dialog: an `NSWindowController` that hosts a private
`ProjectChooserContentViewController`, which in turn hosts a
`ProjectBrowserViewController` in `.chooser` mode behind a Cancel/Open
button pair. It resolves to at most one `GitRepo` drawn from a
`ProjectsCoordinator`'s `repos`, reached through the static entry point
`ProjectChooserWindow.choose(from:onChoose:)` that `ProjectsCoordinator.showProjectChooser()`
calls. Per its own doc comment it is deliberately app-modal rather than a
sheet: "this app has no window guaranteed to be on screen when the question
is asked (it can be asked from the menu bar with nothing open at all), and a
sheet with no parent cannot be dismissed". Both
`ProjectChooserWindow` and its private content view controller are declared
`@MainActor`.

## Behavioral Requirements

- **coordinator-required-no-default**: `init(coordinator:)` and the static
  `choose(from:onChoose:)` MUST both require a `ProjectsCoordinator` argument
  with no default value, and `choose(from:onChoose:)` MUST NOT construct a
  `ProjectChooserWindow` or a coordinator any other way.
- **window-identity-fixed-at-init**: `init(coordinator:)` MUST construct
  exactly one `NSWindow` with `contentRect` 460×480, `styleMask`
  `[.titled, .closable, .resizable]`, `backing: .buffered`, `defer: false`,
  title `"Open Project"`, and `minSize` 360×300, and MUST set that same
  window as both the controller's own `window` and the target of
  `window.delegate`.
- **content-view-controller-fixed-at-init**: `init(coordinator:)` MUST
  construct exactly one `ProjectChooserContentViewController` for the given
  `coordinator` and MUST assign it as `window.contentViewController`.
- **coder-init-unavailable**: `ProjectChooserWindow.init?(coder:)` MUST be
  marked unavailable and MUST call `fatalError` if it is ever invoked, so the
  type MUST NOT be instantiated from a storyboard or nib; the
  same requirement applies to `ProjectChooserContentViewController.init?(coder:)`.
- **main-actor-isolation**: `ProjectChooserWindow` and
  `ProjectChooserContentViewController` MUST both be declared `@MainActor`
  and MUST NOT declare `Sendable` conformance; every stored property
  (`content`, `chosen`, `onFinish`, `browser`, `openButton`) and every method
  of both types is therefore confined to the main actor by that declaration
  alone, not by any lock either type defines itself.
- **browser-constructed-in-chooser-mode**: `ProjectChooserContentViewController.init(coordinator:)`
  MUST construct its `ProjectBrowserViewController` with `mode: .chooser`.
- **onchoose-single-invocation**: `ProjectChooserWindow.choose(from:onChoose:)`
  MUST call `onChoose` exactly once, with the `GitRepo` returned by
  `runModal()`, and only when that result is non-nil; when `runModal()`
  returns `nil` (the user cancelled), `onChoose` MUST NOT be called at all.
- **runmodal-return-value**: `runModal()` MUST return `chosen` after the
  modal session ends; `chosen` is `nil` unless `finish(with:)` was called
  with a non-nil `GitRepo` at some point during that session.
- **content-onfinish-drives-outcome**: The window's eventual outcome MUST be
  determined entirely by invocations of `content.onFinish`, which is wired
  at the end of `init(coordinator:)` to call `finish(with:)` on the window; `finish(with:)` MUST assign its argument to `chosen` and MUST
  call `NSApp.stopModal()`.
- **open-button-forwards-current-selection**: Activating the Open button
  MUST call `onFinish?(browser.selectedRepo)`, forwarding whatever
  `browser.selectedRepo` reports at the moment the button is activated, not
  a value captured earlier.
- **cancel-button-forwards-nil**: Activating the Cancel button MUST call
  `onFinish?(nil)` unconditionally, regardless of the browser's current
  selection.
- **browser-onchoose-forwarded-unchanged**: `browser.onChoose` MUST be wired,
  at construction, to call `onFinish?(repo)` with the exact `GitRepo` the
  browser passes, forwarding it unchanged; the conditions under
  which the browser itself invokes `onChoose` (double-click, Return) are
  `ProjectBrowserViewController`'s own contract, not this file's.
- **open-button-enablement-tracks-selection**: `browser.onSelectionChange`
  MUST be wired, at construction, so that every reported selection change
  sets `openButton.isEnabled` to `true` when the reported `GitRepo?` is
  non-nil and to `false` when it is `nil`.
- **open-button-initial-disabled-then-synced**: `openButton.isEnabled` MUST
  be explicitly set to `false` during `loadView()`, before the browser's
  view is created; accessing `browser.view` for the first time a
  few lines later synchronously loads the browser, which reports
  its own initial selection through `onSelectionChange` — so
  `openButton.isEnabled` MUST end `loadView()` reflecting the browser's
  initial selection, not the `false` value assigned moments before.
- **window-close-ends-session-as-cancel**: `windowWillClose(_:)` MUST call
  `finish(with: nil)` whenever the closing window is the one AppKit
  currently treats as the active modal window (`NSApp.modalWindow === window`),
  which is how dismissal via the title bar close control or ⌘W — both of
  which bypass Cancel and Open — MUST still end the session.
- **window-close-ignored-when-not-active-modal-session**: `windowWillClose(_:)`
  MUST NOT call `finish(with:)` (and therefore MUST NOT call
  `NSApp.stopModal()`) when `NSApp.modalWindow` does not identify this
  window; per the inline comment, this ends "only end a session we are in".
- **runmodal-orders-out-without-closing**: `runModal()` MUST call
  `window.makeKeyAndOrderFront(nil)` before entering the modal loop and
  `window.orderOut(nil)` immediately after `NSApp.runModal(for:)` returns;
  per the inline comment, this `orderOut` call MUST NOT itself produce a
  close notification, so it MUST NOT trigger `windowWillClose(_:)`.
- **runmodal-activation-respects-quiet-presentation**: Before showing the
  window, `runModal()` MUST call `NSApp.activateUnlessQuiet()`,
  which MUST call `NSApplication.activate(ignoringOtherApps: true)` unless
  `QuietWindowPresentation.isEnabled` is `true`, in which case activation
  MUST be skipped entirely (`NSApplication+QuietActivation.swift`).
- **stock-buttons-fixed-key-equivalents**: `loadView()` MUST create Cancel
  and Open as `NSButton` instances with `bezelStyle: .push`, MUST set
  Cancel's `keyEquivalent` to the Escape character (`"\u{1b}"`) and Open's
  `keyEquivalent` to Return (`"\r"`), and MUST route Cancel's action to
  `cancelChoosing(_:)` and Open's action to `openChosen(_:)`.
- **accessibility-identifiers-fixed**: `ProjectChooserWindow` MUST set the
  accessibility identifier `"project-chooser.window"` on its window,
  `"project-chooser.cancel"` on the Cancel button, and
  `"project-chooser.open"` on the Open button.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `coordinator` (parameter to `init` and to `choose(from:onChoose:)`) | `ProjectsCoordinator` | none — required | Supplies the `repos` the hosted `ProjectBrowserViewController` lists; never constructed internally. |
| `onChoose` (parameter to `choose(from:onChoose:)`) | `(GitRepo) -> Void` | none — required | Called exactly once, with the chosen `GitRepo`, when `runModal()` returns non-nil; never called otherwise. |

`ProjectChooserWindow.swift` reads no environment variable and no settings
key directly. `QuietWindowPresentation.isEnabled`, consulted only through
`NSApp.activateUnlessQuiet()`, is `NSApplication+QuietActivation.swift`'s
own concern, reached by this file only as an opaque call
(see **runmodal-activation-respects-quiet-presentation**).

## Localization

`ProjectChooserWindow.swift` produces its user-facing strings as Swift
string literals with no localization key or lookup mechanism:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal) | `Open Project` | Window title, set in `init(coordinator:)`. |
| (none — literal) | `Open` | Open button title. |
| (none — literal) | `Cancel` | Cancel button title. |

