---
id: 1727e605-6f83-42d7-960f-45fbdf714d94
title: File Preview
domain: agentictoolkit://cookbook/workspace/files/file-preview
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A thin wrapper that embeds the platform's native file-preview control in
  the view hierarchy, showing a system-rendered preview for files the editor can't open.
platforms:
- swift
- macos
tags:
- ui
- file-browser
depends-on: []
related:
- agentictoolkit://cookbook/workspace/files/file-editor-view
references: []
approved-by: ''
approved-date: ''
---

# File Preview

## Overview

The component is a thin wrapper that embeds the platform's native file-preview control into the surrounding view hierarchy. Given a single file location, it shows the system's own preview of that file — images, PDFs, movies, audio, archives, presentation decks, and anything else the platform's preview mechanism has a generator for. It exists so that the files a source-code editor cannot render still show something, without this codebase maintaining a per-file-type viewer stack of its own: it reuses the same renderer the user already knows from the platform's own file browser, and a file type that renderer cannot preview draws its own "no preview available" state at no cost to this component. It is used by the file editor view (a sibling component, out of scope for this recipe) to render its system-preview display state.

## Behavioral Requirements

- **wraps-native-preview-control**: The component MUST present the platform's native file-preview control within the surrounding view hierarchy, as a wrapped native view rather than a bespoke re-implementation.
- **requires-preview-url**: The component MUST expose the file location to preview as a required, non-optional, immutable input.
- **constructs-preview-view-with-normal-style**: On creation, the component MUST initialize the native preview control in its full-featured ("normal") presentation style rather than a reduced one.
- **falls-back-to-default-style-when-unavailable**: If the native preview control's full-featured-style initializer is unavailable (yields no instance), the component MUST fall back to constructing the control at its default style instead of crashing or leaving no view.
- **enables-autostart**: The component MUST configure the native preview control to begin generating its preview immediately upon creation, without requiring a separate, explicit start call.
- **sets-initial-preview-item**: On creation, the component MUST configure the native preview control to preview the file at the given location before the control is returned to the view hierarchy.
- **skips-redundant-preview-item-updates**: The component MUST NOT re-trigger preview generation when the incoming file location is unchanged from the file the control is already showing.
- **updates-preview-item-on-url-change**: The component MUST update the native preview control to display the new file when the file location changes to a value different from the file it is currently showing.
- **closes-preview-view-on-dismantle**: The component MUST release the native preview control's underlying preview-generation resources when the component is removed from the view hierarchy.

## Appearance

- **Corner radius**: Not applicable — the component never sets a corner radius; any rounding is the native preview control's own chrome, not code in this file.
- **Padding**: Not set by this component — it has no content of its own to pad. The space around the preview is entirely up to whatever container hosts it (in the file editor view, a fill-the-available-space constraint applied by the caller, which is out of scope for this recipe).
- **Font**: Not applicable — the component renders no text of its own; any text visible inside the preview (e.g., a text-file rendering, or the preview control's own captions) is the native preview control's content.
- **Background**: Not set by this component — the native preview control draws its own background and content; no color or theme lookup appears anywhere in the source.
- **Foreground/Text**: Not applicable — the component sets no foreground color or text of its own.
- **Border**: None; the component never sets a border on the view or its layer.
- **Shadow**: None; the component never sets a shadow on the view or its layer.
- **Min/Max size**: The view is constructed with a zero-size frame; the component sets no width, height, or aspect constraint of its own, so its rendered size is determined entirely by whatever layout the caller applies.

## States

| State | Appearance change |
|-------|------------------|
| Default | Renders the native preview control's live preview of the given file; if the file's type has no preview generator, the control itself draws its native "no preview available" state — this component contains no code for that fallback. |
| Pressed | Not applicable: the component wires no click or press handling of its own; any pointer interaction (zoom, scroll, page navigation) is the native preview control's own behavior. |
| Disabled | Not applicable: the component never reads or sets an enabled/dimmed-appearance property — it has no enabled/disabled concept. |
| Focused | Not applicable: the component never manages keyboard-focus status of its own; it cannot become focused through code in this file. |
| Loading | Not applicable in this component: autostart (see **enables-autostart**) tells the native preview control to begin generating a preview immediately, but any generation-in-progress indicator is the control's own native behavior, not code defined here. |

## Accessibility

- **Role/trait**: Not customized — the component sets no accessibility role, label, or element override anywhere in this file; the native preview control carries the platform's own built-in accessibility behavior for a file preview, unmodified by this wrapper.
- **Label requirements**: Not customized — the component assigns no accessibility label of its own; whatever label the native preview control exposes natively (e.g., derived from the previewed file) is unmodified by this file.
- **Announce state changes**: Not implemented — when the file location changes and the preview target is reassigned (see **updates-preview-item-on-url-change**), no explicit accessibility notification (e.g., a layout-changed or screen-changed post) accompanies that reassignment anywhere in this file; any announcement to a screen reader of the changed preview content is the native preview control's own automatic behavior, not code defined here.
- **Minimum tap target**: Not applicable — the component targets pointer input and wires no click or press handling of its own in this file, so it has no tap target of its own to size; any hit-testing inside the preview is the native preview control's own, pointer-driven behavior.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| quick-look-preview-001 | wraps-native-preview-control | Embed the component, given a file location, in a view hierarchy | It renders as the platform's native file-preview control, wrapped inline in the tree |
| quick-look-preview-002 | requires-preview-url | Attempt to construct the component with no file-location argument | Construction fails; the file location has no default value and is not optional |
| quick-look-preview-003 | constructs-preview-view-with-normal-style | Construct the component in an environment where the native control's full-featured-style construction succeeds | The component returns a native preview control constructed at its full-featured ("normal") style |
| quick-look-preview-004 | falls-back-to-default-style-when-unavailable | Code inspection (not runtime-exercisable: nothing in this codebase lets a test make the full-featured-style construction fail) | Per source, if that construction failed, the component would construct the control at its default style instead, without crashing |
| quick-look-preview-005 | enables-autostart | Inspect the native preview control returned by the component | Its autostart setting is enabled |
| quick-look-preview-006 | sets-initial-preview-item | Construct the component with a given file location | The native preview control's preview target equals that file location immediately after construction |
| quick-look-preview-007 | skips-redundant-preview-item-updates | Update the component with the same file location the control's preview target already holds | The preview target is the same value after the update as before it (its setter is not invoked), verifiable via an identity comparison or a spy on the setter |
| quick-look-preview-008 | updates-preview-item-on-url-change | Update the component with a file location different from the control's current preview target | The preview target is reassigned to the new file location |
| quick-look-preview-009 | closes-preview-view-on-dismantle | The component is removed from the view hierarchy | The native preview control's preview-generation resources are released |

## Edge Cases

- **Null/empty input**: Not applicable — the file location is a required, non-optional input with no failable construction path in this file; the type system prevents constructing the component with a missing or null location (see **requires-preview-url**).
- **Boundary values**: Not applicable — the component takes no numeric, size-constrained, or range-bound input; its only input is a file location.
- **Concurrent access**: Not applicable — the component's lifecycle operations are usable only on the UI thread (see Platform Notes for the mechanism used on Apple platforms), so the surrounding view system never invokes them concurrently with one another.
- **Error states**: The only fallible operation in this file is the preview control's full-featured-style construction; its failure (per the source's comment, "returns nil only when [the preview mechanism] is unavailable") is handled by falling back to the control's default-style construction instead (see **falls-back-to-default-style-when-unavailable**). Beyond that one path, this file defines no error handling. The source's own doc comment states that a file type with no preview generator makes the native preview control draw its own native "no preview available" state; the doc comment makes no equivalent claim for a file that cannot be read or no longer exists, so this recipe does not extend that claim to those cases. This wrapper neither detects nor reports any of these conditions itself — whatever the native preview control does with an unreadable or missing file is its own behavior, unconfirmed by this source file.
- **Offline/disconnected state**: Not applicable — the component performs no networking; the file location identifies a local file and preview rendering happens entirely on-device.
- **File location changes while a preview is still generating**: When the component receives a new file location while the native preview control is still generating the previous preview, the component reassigns the preview target immediately (see **updates-preview-item-on-url-change**) without first canceling or waiting on the prior generation; any cancellation is internal to the native preview control and not implemented in this file.
- **Repeated identical file location across consecutive updates**: The component does not restart generation by reassigning an unchanged preview target (see **skips-redundant-preview-item-updates**); per the source's own comment, reassigning the same item "restarts the generator and flickers."

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `url` | file location | required, set at init | The file to preview; assigned to the native preview control's preview target on creation and reassigned whenever it changes (see **updates-preview-item-on-url-change**). |

## Deep Linking

Not applicable — the component is a content-display wrapper embedded within a caller's view (e.g. the file editor view), not a navigable screen or route of its own; the source defines no URL scheme, route, or deep-link target.

## Localization

Not applicable — the source defines no string literal or text label of its own; it renders no text — all visible content comes from the native preview control's rendering of the previewed file.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the source contains no animation, transition, or motion effect of its own — every lifecycle operation performs a direct property assignment or method call, with no animation-proxy mechanism or explicit animation block anywhere in this file. |
| Increase Contrast | Not applicable: the source sets no color or theme-token value of its own; the native preview control renders its own native chrome, whose Increase Contrast handling, if any, is the system control's responsibility, not this wrapper's. |
| Differentiate Without Color | Not applicable: the source conveys no state or meaning through color — it has exactly one presentation, the native preview control's rendering of whatever the file's own content is. |

## Feature Flags

Not applicable — no feature-flag lookup or conditional gate appears anywhere in this file; the component always constructs and configures its native preview control unconditionally.

## Analytics

Not applicable — no analytics, tracking, or telemetry call appears anywhere in this file, and the component reports no user interaction (it wires no click or press handling of its own — see States).

## Privacy

- **Data collected**: None of its own. The component holds only the file-location input it is given; it neither reads the file's bytes directly (the native preview control does that) nor collects anything else.
- **Storage**: Not applicable — the source performs no read or write of its own beyond handing the file location to the native preview control, which reads and renders the file itself.
- **Transmission**: Not applicable — no networking call appears anywhere in this file; preview rendering is entirely local to the device.
- **Retention**: Not applicable beyond the view's own lifetime — the only retained value is the file-location input, held for as long as the view exists; removal from the view hierarchy releases the preview-generation process (see **closes-preview-view-on-dismantle**) rather than retaining it past the view's lifetime.

## Logging

Not applicable — the source contains no logging call anywhere in this file.

## Platform Notes

- **SwiftUI** (source): `QuickLookPreview.swift` (`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Views/QuickLookPreview.swift`) is the entire source: an `NSViewRepresentable` struct with one stored property, `url: URL`, wrapping AppKit's `QLPreviewView` (from `QuickLookUI`) via `makeNSView`, `updateNSView`, and the static `dismantleNSView` (see **wraps-native-preview-control**). `makeNSView`, `updateNSView`, and `dismantleNSView` are `@MainActor`-isolated by `NSViewRepresentable`'s protocol declaration itself, not by an explicit annotation in this file, so the component is usable only on the main actor and SwiftUI never invokes them concurrently with one another. `makeNSView` constructs the view via the failable `QLPreviewView(frame: .zero, style: .normal)` initializer, falling back to the parameterless `QLPreviewView()` when that returns `nil` (see **constructs-preview-view-with-normal-style**, **falls-back-to-default-style-when-unavailable**); sets `autostarts = true` (see **enables-autostart**); and assigns `url`, cast to `NSURL`, to `previewItem` (see **sets-initial-preview-item**). `updateNSView` reassigns `previewItem` to `url` cast to `NSURL` only when `(view.previewItem as? NSURL) as URL? != url` (see **updates-preview-item-on-url-change**, **skips-redundant-preview-item-updates**). `dismantleNSView` calls `view.close()` (see **closes-preview-view-on-dismantle**). No other SwiftUI-native content — no `Text`, `Image`, shape, or custom drawing — appears in the file; every visible pixel comes from the wrapped `QLPreviewView`.
- **Compose**: There is no first-party Android/Compose equivalent of QuickLook. Reproduce "show it if we can" per file type instead: `AsyncImage`/Coil for images, ExoPlayer's `PlayerView` (wrapped in `AndroidView`) for video/audio, `PdfRenderer` rendered into a `Bitmap` shown in an `Image` for PDFs, and a plain "no preview available" `Column` for everything else — since no single OS-level control does what `QLPreviewView` does here, each format's fallback has to be composed explicitly rather than delegated.
- **React/Web**: Browsers likewise have no single universal preview control. Compose the same per-format fallback: an `<img>` for image MIME types, `<video>`/`<audio>` for media, an `<iframe>` or `pdf.js` for PDFs, and a plain fallback message for anything else, branching on the file's MIME type rather than delegating to one renderer.
- **AppKit / UIKit**: A pure-AppKit host would use `QLPreviewView` directly as a subview, calling `close()` from `deinit`/`viewWillDisappear` in place of `dismantleNSView`. UIKit has no `QLPreviewView` — the iOS analogue is `QLPreviewController`, a full-screen, `UIViewController`-based, one-item-at-a-time browser driven by `QLPreviewControllerDataSource`; porting to iOS means wrapping it as a `UIViewControllerRepresentable` presented modally, rather than embedding it inline the way `QLPreviewView` is embedded here.
- **WinUI 3**: Windows has no OS-level QuickLook equivalent — Explorer's Preview Pane host (`IPreviewHandler`) is a COM interface with no XAML/WinUI wrapper, so no single control can stand in for `QLPreviewView`. Build this as a `Frame` or `ContentControl` that inspects the file's extension/MIME type and swaps in the matching native control: an `Image` bound to a `BitmapImage` for image formats, a `MediaPlayerElement` for audio/video, and a `Microsoft.Web.WebView2` control navigated to the local file (`webView.CoreWebView2.Navigate(fileUri)`) for PDFs — WebView2's Chromium engine renders PDF natively — and any other browser-viewable format. Fall back to a plain "No preview available" `TextBlock` for everything else, mirroring `QLPreviewView`'s own graceful degradation (see Design Decisions), since there is no single control here to delegate that fallback to the way this source does. Swap the active child on `url`/file-type change the same way `updateNSView` swaps `previewItem`, guarding against reassigning an unchanged source the same way **skips-redundant-preview-item-updates** avoids restarting an unchanged `QLPreviewView` generator.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Views/QuickLookPreview.swift` |

## Design Decisions

**Decision**: On Apple platforms, lean on QuickLook (`QLPreviewView`) rather than a stack of per-file-type views.
**Rationale**: Per the source's own doc comment, this "is what keeps 'show it if we can' from becoming a format list this repo has to maintain," and reuses "the same renderer the user already knows from the Finder."
**Approved**: pending

**Decision**: On Apple platforms, an unsupported file format's "no preview available" message is left entirely to `QLPreviewView`, with no fallback view or message coded in this file.
**Rationale**: Per the source's own doc comment, "a type QuickLook has no generator for draws its own 'no preview available' — that is the honest answer, and it costs nothing."
**Approved**: pending

**Decision**: On Apple platforms, `updateNSView` guards reassignment of `previewItem` behind an equality check rather than always reassigning it.
**Rationale**: Per the source's own comment, "reassigning the same item restarts the generator and flickers, so only a genuine change is pushed through."
**Approved**: pending

**Decision**: On Apple platforms, `dismantleNSView` explicitly calls `view.close()` rather than relying on ARC/`deinit` to release the view.
**Rationale**: Per the source's own comment, "QuickLook holds a generator process alive per view; closing releases it rather than waiting for the view to be collected."
**Approved**: pending

**Decision**: On Apple platforms, the failable `QLPreviewView(frame:style:)` initializer is used with a fallback to `QLPreviewView()` rather than force-unwrapping it.
**Rationale**: Per the source's own comment, "the failable initializer is the only one that takes a style; it returns nil only when QuickLook is unavailable, and the plain initializer is the same view at the default style" — a genuine but rare fallback is handled rather than risking a crash.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | Platform Compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | Platform Compliance |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | partial | Reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |

`native-controls-preference` and `platform-design-language` pass because the component delegates all preview rendering to `QLPreviewView`, Finder's own native QuickLook control, rather than a bespoke per-format viewer. `idempotent-operations` passes because `updateNSView` is a no-op when the incoming `url` already matches the view's current `previewItem` (see **skips-redundant-preview-item-updates**). `graceful-degradation` is `partial`: the source's own doc comment confirms `QLPreviewView` draws its own "no preview available" state for a file type with no generator, but makes no equivalent claim for a file that cannot be read or no longer exists, and that case cannot be confirmed from the source alone (see Edge Cases, **Error states**). `separation-of-concerns` passes because this file contains no per-file-type logic of its own — it only bridges SwiftUI to `QLPreviewView` and defers all format-specific rendering to QuickLook.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: platform-neutralized behavioral requirements (moved AppKit specifics to the SwiftUI Platform Notes bullet), fixed RFC 2119 misuse in edge cases, corrected Design Decisions colon placement, reworded test vectors 005 and 008 to be checkable, narrowed the "no preview available" claim and downgraded graceful-degradation to partial pending verification of the unreadable/missing-file case, removed the unsupported WinUI 3 parenthetical, and cleaned up Compliance (title-cased categories, dropped the invalid main-actor-confined/architecture check) |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/files/. |
