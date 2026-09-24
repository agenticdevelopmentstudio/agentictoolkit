---
id: 7152ec0d-01a9-433d-b1fd-1ac708400f40
title: ExtensionWebviewViewController
domain: agentictoolkit://recipes/extension-webview-view-controller
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: AppKit pane wrapper that shows a contributed extension's webview panel once
  its provider resolves, and an explanatory placeholder before and after.
platforms:
- swift
- macos
tags:
- appkit
- view-controller
- extensions
- webview
- placeholder
depends-on:
- agentictoolkit://recipes/pane-view-controller
- agentictoolkit://recipes/composable-tabs-view-registry
related:
- agentictoolkit://recipes/webview-panel-view-controller
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
approved-by: ''
approved-date: ''
---

# ExtensionWebviewViewController

## Overview

`ExtensionWebviewViewController` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/Webview/ExtensionWebviewViewController.swift`) is the pane a contributed view of kind `.webview` gets. It shows an explanatory placeholder — the view's name, the extension that contributed it, and a sentence saying its webview provider has not run yet — until the extension's `resolveWebviewView` runs and hands back a `WebviewPanelViewController`, at which point it swaps the placeholder for that panel's own view. If the panel is later disposed (the extension is unloaded, reloaded, or disabled), it swaps back to a freshly built placeholder. It never becomes the webview itself; it is the seam between `ViewsContributionPoint`, which knows what the manifest declared, and `ExtensionHostInstaller`, which knows who is installed and awake.

## Behavioral Requirements

- **placeholder-shown-on-load**: The component MUST show a new `ExtensionViewPlaceholderViewController`, built from its `contributedView` and `extensionDisplayName`, as its initial on-screen content, before the `resolve` closure is ever called.
- **resolve-called-once-on-first-display**: The component MUST call the `resolve` closure supplied at `init` exactly once, on first display, passing `contributedView` and a completion closure.
- **panel-adopted-when-resolved**: The component MUST replace the on-screen placeholder with the `WebviewPanelViewController` that `resolve` returned once the completion closure passed to `resolve` has been called, whether that call happens synchronously (before `resolve` returns) or later.
- **no-adoption-without-completion**: The component MUST NOT swap the on-screen placeholder for the panel `resolve` returned until that panel's completion closure has been called; a non-nil panel `resolve` returns never appears on screen if its completion closure is never invoked.
- **panel-swap-is-idempotent**: The component MUST NOT re-show the panel if it is already the on-screen content.
- **remains-on-placeholder-when-unresolved**: The component MUST remain on the placeholder indefinitely when `resolve` returns `nil`, or when its completion closure is never called; it does not retry and does not time out.
- **panel-removal-reverts-to-placeholder**: The component MUST show a newly built placeholder, replacing the current content, when the adopted panel's `onRemovalRequested` fires, provided the component is not being discarded and a `WebviewPanelViewController` is the content currently on screen.
- **no-revert-once-discarding**: The component MUST NOT rebuild a placeholder in response to `onRemovalRequested` once `paneContentWillBeDiscarded()` has run on it.
- **teardown-forwarded-to-panel**: `paneContentWillBeDiscarded()` MUST forward to the held `panel` reference, not to the on-screen `content`, whether or not the panel is currently displayed.
- **teardown-sets-discard-flag-first**: `paneContentWillBeDiscarded()` MUST set its internal discard flag before forwarding to the panel, so that a removal request the panel raises synchronously during its own disposal does not rebuild a placeholder.
- **outgoing-title-callback-cleared**: `show(_:)` MUST clear the outgoing child's `onPaneTitleChange` callback, when the outgoing child conforms to `PaneTitleProviding`, before removing that child from the view hierarchy.
- **incoming-title-callback-installed**: `show(_:)` MUST install a forwarding closure onto the incoming child's `onPaneTitleChange`, when the incoming child conforms to `PaneTitleProviding`, that calls the component's own `onPaneTitleChange`.
- **title-change-notified-on-swap**: `show(_:)` MUST invoke the component's own `onPaneTitleChange` callback once, after installing the incoming child, every time the content is swapped.
- **pane-title-delegates-to-content**: `paneTitle` MUST return the on-screen content's `paneTitle` when that content conforms to `PaneTitleProviding`, and MUST otherwise return `contributedView.name`.
- **child-view-fills-container**: `show(_:)` MUST constrain the incoming child's view to the container's leading, trailing, top, and bottom edges, with no offset.
- **background-tracks-theme-surface**: The container view MUST set its layer's background color from the active theme's `.surface` role immediately on load, and MUST update that color on every subsequent theme change.
- **explicit-construction-only**: The component MUST NOT be constructable without its `contributedView`, `extensionDisplayName`, and `resolve` dependencies explicitly supplied at construction; a serialized-construction path MUST NOT produce a usable instance.
- **main-actor-confined**: The entire class MUST run isolated to the main actor.

## Appearance

- **Corner radius**: Not applicable — the container is a plain `NSView` (`wantsLayer = true`) with no corner radius set anywhere in this file.
- **Padding**: Not applicable — the incoming child's view is pinned edge-to-edge to the container with a constant of 0; there is no inset.
- **Font**: Not applicable — this component draws no text of its own. Text belongs to whichever content is on screen: `ExtensionViewPlaceholderViewController`'s labels, or the hosted `WebviewPanelViewController`'s rendered page.
- **Background**: The container view's layer is filled with `palette.nsColor(.surface)`, resolved through `observeTheme` and reapplied on every theme change.
- **Foreground/Text**: Not applicable — no text or foreground color is set in this file.
- **Border**: Not applicable — no border is set anywhere in this file.
- **Shadow**: Not applicable — no shadow is set anywhere in this file.
- **Min/Max size**: Not applicable — the container carries no width or height constraint of its own. `loadView()` constructs it with an initial frame of `NSRect(x: 0, y: 0, width: 300, height: 200)`, which is discarded the moment the pane host's Auto Layout takes over sizing.

## States

| State | Appearance change |
|-------|------------------|
| Default | — |
| Pressed | Not applicable: this component has no pressed state; it hosts other view controllers rather than drawing an interactive control of its own. |
| Disabled | Not applicable: neither this component nor the placeholder it shows can be disabled in this file; any disabled treatment inside a resolved webview panel's page is the extension's concern. |
| Focused | Not applicable: this component sets no explicit focus or first-responder behavior of its own; whichever child is on screen manages its own focus. |
| Loading | Not applicable: no loading indicator or spinner exists anywhere in this file. The interval between construction and a resolved panel is not visually distinguished from the initial placeholder. |
| Placeholder (unresolved) | Default content: `ExtensionViewPlaceholderViewController`, shown from `loadView()` until the extension's provider resolves. |
| Resolved (webview panel) | Content: the `WebviewPanelViewController` `resolve` returned, adopted once its completion closure has fired. |
| Reverted to placeholder | Content: a freshly built `ExtensionViewPlaceholderViewController`, shown when the previously adopted panel's `onRemovalRequested` fires and the component is not itself being discarded. |

## Accessibility

- **Role/trait**: Not applicable — this component sets no explicit accessibility role of its own; it is a plain container `NSView` with no `setAccessibilityRole` or `accessibilityElement` call anywhere in this file. Whichever child is on screen (`ExtensionViewPlaceholderViewController`'s labeled stack, or the hosted `WebviewPanelViewController`'s web content) carries whatever accessibility role its own view hierarchy provides.
- **Label requirements**: Not applicable for the same reason — no `accessibilityLabel` or `accessibilityIdentifier` is set on the container or in `show(_:)`; labeling belongs entirely to whichever content is being shown.
- **Announce state changes**: NEEDS REVIEW: Not implemented in source. Behavior undefined. `show(_:)` swaps the entire visible content — placeholder to webview panel, or back — by adding and removing views, with no accompanying `NSAccessibility` notification (for example `.layoutChanged`) anywhere in this file or in `ExtensionViewPlaceholderViewController`. A VoiceOver user focused on this pane when the extension's page appears, or disappears, has no announcement that the content changed underneath them. Resolution requires an accessibility audit deciding which notification to post and from where, and sign-off from whoever owns VoiceOver support for this app.
- **Minimum tap target**: Not applicable — this component places no tappable control of its own. The placeholder it shows has no buttons or links, only three text labels; any interactive element inside a resolved panel's page is the extension's own responsibility, out of this file's scope.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ewvc-001 | placeholder-shown-on-load | Construct the component with a `.webview` `ContributedView` and force `loadView()` to run | The view hierarchy shows an `ExtensionViewPlaceholderViewController` displaying the view's `name` and the given `extensionDisplayName`; `resolve` has not been called |
| ewvc-002 | resolve-called-once-on-first-display | Supply a `resolve` closure that records its call count; load the component's view | `resolve` was called exactly once, with the constructor's `contributedView` |
| ewvc-003 | panel-adopted-when-resolved | Supply a `resolve` closure that builds a panel and calls its completion closure before returning | After `viewDidLoad()` returns, the panel's view is the on-screen content, not the placeholder |
| ewvc-004 | panel-swap-is-idempotent | With a panel already adopted, invoke the completion closure a second time | The on-screen content is unchanged — the same view instance, not reparented |
| ewvc-005 | remains-on-placeholder-when-unresolved | Supply a `resolve` closure that returns `nil` and never calls its completion closure | After `viewDidLoad()` returns and after further run-loop turns, the content is still the initial placeholder |
| ewvc-006 | panel-removal-reverts-to-placeholder | With a resolved and adopted panel, invoke that panel's `onRemovalRequested` | The content becomes a new `ExtensionViewPlaceholderViewController` instance, distinct from the original |
| ewvc-007 | no-revert-once-discarding | With a resolved and adopted panel, call `paneContentWillBeDiscarded()`, then invoke the panel's `onRemovalRequested` | No new placeholder is built; the content is unchanged |
| ewvc-008 | teardown-forwarded-to-panel | Supply a panel that is never adopted (its completion closure is never called, so content stays the placeholder); call `paneContentWillBeDiscarded()` | The panel instance's own `paneContentWillBeDiscarded()` was called exactly once, despite never having been on screen |
| ewvc-009 | teardown-sets-discard-flag-first | Supply a panel whose `paneContentWillBeDiscarded()` synchronously invokes its own `onRemovalRequested` before returning | No new placeholder is built during or after that call; the content is unchanged |
| ewvc-010 | outgoing-title-callback-cleared | Adopt a panel conforming to `PaneTitleProviding`, then trigger a swap back to a placeholder via `onRemovalRequested` | The panel's `onPaneTitleChange` is `nil` immediately after the swap |
| ewvc-011 | incoming-title-callback-installed | Adopt a panel conforming to `PaneTitleProviding` | The panel's `onPaneTitleChange` is non-nil, and invoking it calls the component's own `onPaneTitleChange` |
| ewvc-012 | title-change-notified-on-swap | Install an `onPaneTitleChange` callback on the component, then let a panel resolve and be adopted | The component's `onPaneTitleChange` callback fires during the swap |
| ewvc-013 | pane-title-delegates-to-content | Read `paneTitle` before any panel is adopted; then adopt a panel whose `title` is "Extension Page" and read again | First read equals `contributedView.name`; second read equals "Extension Page" |
| ewvc-014 | child-view-fills-container | Load the view; inspect the constraints `show(_:)` installed on the current child's view | Exactly four constraints pin leading, trailing, top, and bottom to the container, each with a constant of 0 |
| ewvc-015 | background-tracks-theme-surface | Load the view under one active theme, read the container layer's background color; then switch the active theme | The color equals the first theme's `.surface` color immediately after load, and equals the second theme's `.surface` color after the switch, with no further action taken |
| ewvc-016 | explicit-construction-only | Call `ExtensionWebviewViewController(coder:)` | The process traps (`fatalError`); no instance is returned |
| ewvc-017 | main-actor-confined | Inspect the class declaration and its stored properties and methods | The class declaration and every one of its stored properties and methods is isolated to `@MainActor`; no member of the class is reachable off the main actor |
| ewvc-018 | no-adoption-without-completion | Supply a `resolve` closure that builds and returns a non-nil panel but never calls its completion closure | After `viewDidLoad()` returns and after further run-loop turns, the panel's view never appears in the hierarchy; the content is still the initial placeholder |

## Edge Cases

- **Null/empty input**: `resolve` returning `nil` — no provider is available at all — the component MUST remain showing the placeholder built in `loadView()` indefinitely (see `remains-on-placeholder-when-unresolved`). Likewise, if `resolve` returns a non-nil panel but its completion closure is never called, the component MUST NOT adopt that panel (see `no-adoption-without-completion`, which defines adoption entirely in terms of that closure firing).
- **Boundary values**: Not applicable. This component takes no numerically- or size-bounded input; its constructor arguments are a `ContributedView` value, a display-name string, and a resolver closure, none of which carry a minimum or maximum in this file.
- **Concurrent access**: Not a hazard, by construction: the whole class, and the `ContributedWebviewResolving` closure type it is handed, are declared `@MainActor` (MUST, see `main-actor-confined`), so `panel`, `isResolved`, `content`, `isBeingDiscarded`, and `onTitleChange` are read and written only on the main actor. The source's own note that the completion runs "synchronously if [the extension] is already awake, and a turn or two later if it had to be activated first" describes timing relative to `resolve` returning, not a different execution context.
- **Error states**: Neither an extension's process crashing nor being force-quit produces a state this file distinguishes — the only signal it reacts to is `onRemovalRequested`, which reverts to the same placeholder shown for a view whose provider never ran (MUST, see `panel-removal-reverts-to-placeholder`); there is no separate "something went wrong" explanation. A panel that disposes itself before `onRemovalRequested` is ever assigned — for example, during `resolve`, before it is returned — replays that disposal synchronously the instant `viewDidLoad()` assigns the callback; because `content` is still the initial placeholder at that point, `panel-removal-reverts-to-placeholder`'s own guard makes this a no-op rather than a double-build.
- **Offline or disconnected state**: Not applicable. This file makes no network request of its own; any network activity a resolved panel's page performs happens inside the extension's own content, outside this file.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `contributedView` | `ContributedView` | required at init | The manifest's view declaration this pane represents — its name, kind, and owning extension identifier. |
| `extensionDisplayName` | `String` | required at init | The extension's display name, shown by the placeholder while unresolved. |
| `resolve` | `ContributedWebviewResolving` | required at init | Builds the live panel for this view, or returns `nil` when nobody can; called exactly once, from `viewDidLoad()`. |

## Deep Linking

Not applicable: this component is built entirely from an in-process `ContributedView`/display-name/resolver triple handed to it by `ViewsContributionPoint`. No URL scheme, universal link, or `NSUserActivity` handling appears anywhere in this file.

## Localization

Not applicable: no `Text`, `Label`, `NSTextField.stringValue`, `title`, or other user-facing string literal appears in `ExtensionWebviewViewController.swift`. The two strings this class touches — `contributedView.name` and `extensionDisplayName` — are values passed in at construction and forwarded unchanged, not literals declared here; the user-facing title, attribution, and explanation text are drawn by `ExtensionViewPlaceholderViewController`, a separate component out of this file's scope.

## Accessibility Options

Document which accessibility display options this component responds to:

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: every content swap in `show(_:)` is an immediate `NSView` add/remove; no `NSAnimationContext`, layer animation, or transition appears anywhere in this file. |
| Increase Contrast | Not observed in this file: the container's fill color is resolved through `SemanticPalette`/theme lookup (`palette.nsColor(.surface)`), so any contrast adaptation belongs to the theme system, out of this ingredient's scope. |
| Differentiate Without Color | Not applicable: this component draws no state that is distinguished by color alone — its only color use is a single background fill, with no second state it must be told apart from by anything else. |

## Feature Flags

Not applicable: no feature-flag or remote-config lookup of any kind appears anywhere in this file.

## Analytics

Not applicable: no analytics event is emitted anywhere in this file.

## Privacy

- **Data collected**: None. This component collects no data of its own; it hosts whatever page the extension's provider loads into a `WebviewPanelViewController`, a separate component.
- **Storage**: None of its own; no persistence code appears in this file.
- **Transmission**: None of its own; any network activity happens inside the resolved panel's web content, not in this component.
- **Retention**: Not applicable — this component holds no persistent data of its own.

## Logging

Not applicable: no `Logger`, `os_log`, or other logging call appears anywhere in this file.

## Platform Notes

- **SwiftUI**: Model the two states as a small `@Observable` view model exposing `panel: WebviewPanelHandle?`, and build a `Group { if let panel { PanelHost(panel) } else { PlaceholderView(view: contributedView, extensionDisplayName: name) } }`. Since the underlying panel content is still AppKit (`WKWebView`-backed), host it via `NSViewControllerRepresentable` rather than reimplementing it; the title-forwarding callback becomes a `Binding<String>` or an `onTitleChange` closure passed down into the wrapped representable, mirroring `PaneTitleProviding`.
- **Compose**: Represent the states as a sealed `PanelState` (`Unresolved`/`Resolved`/`Reverted`) exposed from a `ViewModel`'s `StateFlow`, and switch between a placeholder `@Composable` and an `AndroidView` wrapping the equivalent `WebView` surface based on its value. Forward title changes through a callback lambda the ViewModel holds, mirroring `onPaneTitleChange` rather than an implicit two-way binding.
- **React/Web**: A component holding `panel: Panel | null` state, rendering the placeholder markup until the resolver's callback fires and then rendering the iframe or embedded-webview surface in its place. Forward title changes via a prop callback (`onTitleChange`) the parent wires up, matching this source's callback-not-observable convention; drive the background fill from a CSS custom property bound to the theme's surface token.
- **AppKit/UIKit**: This recipe's own platform and file: `ExtensionWebviewViewController.swift` is macOS/AppKit-only (`import AppKit`; `NSViewController`, `NSView`, `NSLayoutConstraint`), with no iOS counterpart in this feature. It composes `ExtensionViewPlaceholderViewController` and `WebviewPanelViewController` as children via `addChild`/view swapping rather than a `UIViewController`-hosted child, and conforms to this toolkit's `PaneTitleProviding` and `PaneContentTeardown` protocols to participate in the surrounding pane chrome. The lifecycle specifics behind the platform-neutral requirements above are AppKit's: the placeholder is installed as `loadView()`'s content, `resolve` is called exactly once from `viewDidLoad()`, and `init(coder:)` is `@available(*, unavailable)` and fatalErrors, since the only supported construction path takes `contributedView`, `extensionDisplayName`, and `resolve` explicitly.
- **WinUI 3**: Recreate this as a `UserControl` ("ExtensionWebviewControl") wrapping a single-cell `Grid`, driven by a two-state `VisualStateGroup` ("Placeholder"/"Panel") switched from code-behind rather than XAML triggers, since the transition is two-way — placeholder to panel, and back to a freshly built placeholder if the panel is later disposed — and there is no third visual state. Host the placeholder as its own `UserControl` and the resolved page as a `WebView2`-backed `UserControl` (mirroring `WebviewPanelViewController`); when the extension disposes the panel, tear down and `Close()` the `WebView2` before swapping the placeholder `UserControl` back in — `Close()` matters here the same way releasing the WebKit content process matters in the AppKit source, since neither web engine frees its process on garbage collection alone. Bind the container's `Background` to a `{ThemeResource SurfaceBrush}` so it repaints automatically on `ActualThemeChanged`, which is the one simplification available here: WinUI's theme-resource binding replaces the push-based `observeTheme` callback the AppKit source needs. Expose a `PaneTitle` dependency property with a `PaneTitleChanged` routed event in place of `PaneTitleProviding.onPaneTitleChange`, re-raised whenever the hosted panel's own title changes, mirroring `show(_:)`'s callback rewiring on every swap.

## Design Decisions

**Decision**: The completion closure passed to `resolve` sets a flag (`isResolved`) that a separate method (`adoptPanelIfResolved()`) re-checks, rather than swapping content directly from inside the completion closure.
**Rationale**: `resolve` can call the completion synchronously, while `resolve` is still on the call stack and the returned panel has not yet been assigned to the `panel` property; swapping content immediately from inside the closure would read a still-nil `panel`. The flag defers the actual swap until `adoptPanelIfResolved()` runs again at the end of `viewDidLoad()`, after `panel` is assigned.
**Approved**: pending

**Decision**: `paneContentWillBeDiscarded()` sets its discard flag before forwarding to the panel.
**Rationale**: Disposing the panel fires `onRemovalRequested`, which is wired to rebuild a placeholder; without the flag set first, a pane on its way out of the window would have a placeholder rebuilt into it moments before being deallocated.
**Approved**: pending

**Decision**: The resolver this component depends on is a closure typealias (`ContributedWebviewResolving`) rather than a protocol.
**Rationale**: It is one verb with one production implementation, so a protocol would exist for a single conformer; taking it as a closure parameter also lets it be supplied to this component after construction, without needing a stateful lookup type. See `agentictoolkit://recipes/webview-panel-view-controller` for the panel this closure returns.
**Approved**: pending

**Decision**: This component wraps the panel rather than being the webview surface itself.
**Rationale**: An unloaded `WKWebView` is a blank white rectangle. Wrapping it lets the pane show an explanatory placeholder until an extension actually resolves a provider, and go back to that explanation if the panel is later disposed — without which "installed, but nothing registered yet" would be indistinguishable from "broken." (See the open question under **Accessibility** for the one gap this wrapping does not close: the swap between those two readable states carries no assistive-technology announcement.)
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [platform-theming](agenticdevelopercookbook://compliance/platform-compliance#platform-theming) | passed | Platform Compliance |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |

`graceful-degradation` and `platform-theming` are `passed` on the strength of two source-satisfied MUSTs — `remains-on-placeholder-when-unresolved`/`panel-removal-reverts-to-placeholder` for the former, `background-tracks-theme-surface` for the latter; `screen-reader-support` is `partial` because `show(_:)` swaps the entire visible content with no accompanying `NSAccessibility` notification (see the open question under **Accessibility**).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: add no-adoption-without-completion requirement and test vector; trim Design Decisions to this component's own rationale; rename AppKit-lifecycle-tied requirements to platform-neutral names and moved their specifics into the AppKit/UIKit note; fix screen-reader-support status and Compliance table to only cite real catalog checks; fix SwiftUI Binding syntax and WinUI two-way transition note; scope the main-actor-confined test vector to the class; populate related/depends-on and move the misplaced references entry; trim tags to 5; reformat Design Decisions with bold labels; remove dangling Rule 15 citation |
