<!-- leaf: implement-extension/webview-view-controller · source: extension-webview-view-controller.md -->

**Rules** (cite as `implement-extension/webview-view-controller#<slug>`):

- `placeholder-shown-on-load` MUST
- `resolve-called-once-on-first-display` MUST
- `panel-adopted-when-resolved` MUST
- `no-adoption-without-completion` MUST
- `panel-swap-is-idempotent` MUST
- `remains-on-placeholder-when-unresolved` MUST
- `panel-removal-reverts-to-placeholder` MUST
- `no-revert-once-discarding` MUST
- `teardown-forwarded-to-panel` MUST
- `teardown-sets-discard-flag-first` MUST
- `outgoing-title-callback-cleared` MUST
- `incoming-title-callback-installed` MUST
- `title-change-notified-on-swap` MUST
- `pane-title-delegates-to-content` MUST
- `child-view-fills-container` MUST
- `background-tracks-theme-surface` MUST
- `explicit-construction-only` MUST
- `main-actor-confined` MUST

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

## Accessibility

- **Role/trait**: Not applicable — this component sets no explicit accessibility role of its own; it is a plain container `NSView` with no `setAccessibilityRole` or `accessibilityElement` call anywhere in this file. Whichever child is on screen (`ExtensionViewPlaceholderViewController`'s labeled stack, or the hosted `WebviewPanelViewController`'s web content) carries whatever accessibility role its own view hierarchy provides.
- **Label requirements**: Not applicable for the same reason — no `accessibilityLabel` or `accessibilityIdentifier` is set on the container or in `show(_:)`; labeling belongs entirely to whichever content is being shown.
- **Announce state changes**: Not implemented in source: `show(_:)` swaps the entire visible content — placeholder to webview panel, or back — by adding and removing views, with no accompanying `NSAccessibility` notification (for example `.layoutChanged`) anywhere in this file or in `ExtensionViewPlaceholderViewController`. A VoiceOver user focused on this pane when the extension's page appears, or disappears, gets no announcement that the content changed underneath them.
- **Minimum tap target**: Not applicable — this component places no tappable control of its own. The placeholder it shows has no buttons or links, only three text labels; any interactive element inside a resolved panel's page is the extension's own responsibility, out of this file's scope.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `contributedView` | `ContributedView` | required at init | The manifest's view declaration this pane represents — its name, kind, and owning extension identifier. |
| `extensionDisplayName` | `String` | required at init | The extension's display name, shown by the placeholder while unresolved. |
| `resolve` | `ContributedWebviewResolving` | required at init | Builds the live panel for this view, or returns `nil` when nobody can; called exactly once, from `viewDidLoad()`. |

## Accessibility Options

Document which accessibility display options this component responds to:

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: every content swap in `show(_:)` is an immediate `NSView` add/remove; no `NSAnimationContext`, layer animation, or transition appears anywhere in this file. |
| Increase Contrast | Not observed in this file: the container's fill color is resolved through `SemanticPalette`/theme lookup (`palette.nsColor(.surface)`), so any contrast adaptation belongs to the theme system, out of this ingredient's scope. |
| Differentiate Without Color | Not applicable: this component draws no state that is distinguished by color alone — its only color use is a single background fill, with no second state it must be told apart from by anything else. |

## Privacy

- **Data collected**: None. This component collects no data of its own; it hosts whatever page the extension's provider loads into a `WebviewPanelViewController`, a separate component.
- **Storage**: None of its own; no persistence code appears in this file.
- **Transmission**: None of its own; any network activity happens inside the resolved panel's web content, not in this component.
- **Retention**: Not applicable — this component holds no persistent data of its own.

