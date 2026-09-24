---
id: 1727e605-6f83-42d7-960f-45fbdf714d94
title: Quick Look Preview
domain: agentictoolkit://recipes/quick-look-preview
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A SwiftUI NSViewRepresentable wrapping AppKit's QLPreviewView, showing Finder's
  own QuickLook preview for files the text editor can't open.
platforms:
- swift
- macos
tags:
- ui
- file-browser
- quicklook
- appkit
- macos
depends-on: []
related:
- agentictoolkit://recipes/file-editor-view
references: []
approved-by: ''
approved-date: ''
---

# Quick Look Preview

## Overview

`QuickLookPreview` (`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Views/QuickLookPreview.swift`) is a SwiftUI `NSViewRepresentable` that bridges AppKit's `QLPreviewView` (from `QuickLookUI`) into a SwiftUI view hierarchy. Given a single `url: URL`, it shows Finder's own QuickLook preview of that file — images, PDFs, movies, audio, archives, Keynote decks, and anything else QuickLook has a generator for. Per the source's own doc comment, it exists so that the files a source-code editor cannot render ("the files the source editor can't take") still show something, without this codebase maintaining a per-file-type viewer stack of its own: QuickLook is "the same renderer the user already knows from the Finder," and a file type QuickLook cannot preview draws its own "no preview available" state at no cost to this file. It is used by `FileEditorView` (a sibling component, out of scope for this recipe) to render the `.quickLook(url)` branch of that view's content switch.

## Behavioral Requirements

- **conforms-to-viewrepresentable**: The component MUST conform to `NSViewRepresentable`, presenting a `QLPreviewView` as a SwiftUI view.
- **requires-preview-url**: The component MUST expose `url: URL` as a required, non-optional, immutable (`let`) stored property naming the file to preview.
- **confines-to-main-actor**: The component MUST be usable only on the main actor: `NSViewRepresentable`'s `makeNSView(context:)`, `updateNSView(_:context:)`, and `dismantleNSView(_:coordinator:)` requirements are `@MainActor`-isolated by the protocol declaration itself, not by an explicit annotation in this file.
- **constructs-preview-view-with-normal-style**: On creation, the component MUST construct its `QLPreviewView` via `QLPreviewView(frame: .zero, style: .normal)`.
- **falls-back-to-default-style-when-unavailable**: If `QLPreviewView(frame:style:)` returns `nil`, the component MUST construct the view via the parameterless `QLPreviewView()` initializer instead.
- **enables-autostart**: The component MUST set the created `QLPreviewView`'s `autostarts` property to `true`.
- **sets-initial-preview-item**: The component MUST assign `url`, cast to `NSURL`, to the created view's `previewItem` before returning it from `makeNSView(context:)`.
- **skips-redundant-preview-item-updates**: The component MUST NOT reassign `previewItem` when the view's current `previewItem`, cast back to `URL`, already equals the incoming `url`.
- **updates-preview-item-on-url-change**: The component MUST reassign the view's `previewItem` to the incoming `url`, cast to `NSURL`, when it differs from the view's current `previewItem`.
- **closes-preview-view-on-dismantle**: The component MUST call `close()` on the `QLPreviewView` from `dismantleNSView(_:coordinator:)` when SwiftUI removes it from the hierarchy.

## Appearance

- **Corner radius**: Not applicable — the source never sets a corner radius; any rounding is `QLPreviewView`'s own native chrome, not code in this file.
- **Padding**: Not set by this file — it has no content of its own to pad. The space around the preview is entirely up to whatever container hosts it (in `FileEditorView`, a `.frame(maxWidth: .infinity, maxHeight: .infinity)` applied by the caller, which is out of scope for this recipe).
- **Font**: Not applicable — the source renders no text of its own; any text visible inside the preview (e.g., a text-file rendering, or QuickLook's own captions) is `QLPreviewView`'s native content.
- **Background**: Not set by this file — `QLPreviewView` draws its own background and content; no `NSColor`, `CGColor`, or theme lookup appears anywhere in the source.
- **Foreground/Text**: Not applicable — the source sets no foreground color or text of its own.
- **Border**: None; the source never sets a border on the view or its layer.
- **Shadow**: None; the source never sets a shadow on the view or its layer.
- **Min/Max size**: The view is constructed with `frame: .zero`; the source sets no width, height, or aspect constraint of its own, so its rendered size is determined entirely by whatever Auto Layout or SwiftUI layout the caller applies.

## States

| State | Appearance change |
|-------|------------------|
| Default | Renders `QLPreviewView`'s live preview of `url`; if the file's type has no QuickLook generator, `QLPreviewView` itself draws its native "no preview available" state (per the source's doc comment) — this file contains no code for that fallback. |
| Pressed | Not applicable: the source wires no target/action, gesture recognizer, or click handling of its own; any pointer interaction (zoom, scroll, page navigation) is `QLPreviewView`'s own native behavior. |
| Disabled | Not applicable: the source never reads or sets `isEnabled` or any dimmed-appearance property — `QuickLookPreview` has no enabled/disabled concept. |
| Focused | Not applicable: the source never overrides `acceptsFirstResponder` or manages first-responder status; it cannot become focused through code in this file. |
| Loading | Not applicable in this file: `view.autostarts = true` (see **enables-autostart**) tells `QLPreviewView` to begin generating a preview immediately, but any generation-in-progress indicator is `QLPreviewView`'s own native behavior, not code defined here. |

## Accessibility

- **Role/trait**: Not customized — the source sets no `accessibilityRole`, `accessibilityLabel`, or `isAccessibilityElement` override anywhere in this file; `QLPreviewView` carries AppKit's own built-in accessibility behavior for a QuickLook preview, unmodified by this wrapper.
- **Label requirements**: Not customized — the source assigns no accessibility label of its own; whatever label `QLPreviewView` exposes natively (e.g., derived from the previewed file) is unmodified by this file.
- **Announce state changes**: NEEDS REVIEW: Not implemented in source. Behavior undefined. When `url` changes and `updateNSView` reassigns `previewItem` (see **updates-preview-item-on-url-change**), no explicit accessibility notification (e.g., a layout-changed or screen-changed post) accompanies that change anywhere in this file. Whether a VoiceOver user already focused on this view is told the previewed content changed depends entirely on `QLPreviewView`'s own automatic behavior, which cannot be confirmed from this source file alone. Settling it needs either a VoiceOver test pass across a `url` change, or an explicit accessibility-notification addition to `updateNSView(_:context:)`.
- **Minimum tap target**: Not applicable — `QuickLookPreview` targets macOS pointer input and wires no target/action, gesture recognizer, or click handling of its own in this file, so it has no tap target of its own to size; any hit-testing inside the preview is `QLPreviewView`'s native, pointer-driven behavior.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| quick-look-preview-001 | conforms-to-viewrepresentable | Embed `QuickLookPreview(url:)` in a SwiftUI view hierarchy | It compiles and renders as an `NSViewRepresentable`-backed `NSView` (a `QLPreviewView`) inside the SwiftUI tree |
| quick-look-preview-002 | requires-preview-url | Attempt to construct `QuickLookPreview()` with no `url` argument | Compilation fails; `url` has no default value and is not optional |
| quick-look-preview-003 | confines-to-main-actor | Call `makeNSView(context:)` from off the main actor | The compiler rejects the call at compile time under Swift's `@MainActor` isolation checking, inherited from `NSViewRepresentable`'s protocol requirements |
| quick-look-preview-004 | constructs-preview-view-with-normal-style | Construct `QuickLookPreview(url:)` in an environment where `QLPreviewView(frame:style:)` succeeds | `makeNSView` returns a `QLPreviewView` constructed with `frame: .zero, style: .normal` |
| quick-look-preview-005 | falls-back-to-default-style-when-unavailable | Construct `QuickLookPreview(url:)` in an environment where `QLPreviewView(frame:style:)` returns `nil` | `makeNSView` returns a `QLPreviewView` constructed via the parameterless `QLPreviewView()` initializer, without crashing |
| quick-look-preview-006 | enables-autostart | Inspect the `QLPreviewView` returned by `makeNSView(context:)` | `view.autostarts == true` |
| quick-look-preview-007 | sets-initial-preview-item | Construct `QuickLookPreview(url: someURL)` | `(view.previewItem as? NSURL) as URL? == someURL` immediately after `makeNSView` returns |
| quick-look-preview-008 | skips-redundant-preview-item-updates | Call `updateNSView(_:context:)` with the `url` the view's `previewItem` already holds | `view.previewItem` is not reassigned (no generator restart) |
| quick-look-preview-009 | updates-preview-item-on-url-change | Call `updateNSView(_:context:)` with a `url` different from the view's current `previewItem` | `view.previewItem` is reassigned to the new `url` |
| quick-look-preview-010 | closes-preview-view-on-dismantle | SwiftUI removes `QuickLookPreview` from the view hierarchy, invoking `dismantleNSView(_:coordinator:)` | `close()` is called on the `QLPreviewView` |

## Edge Cases

- **Null/empty input**: Not applicable — `url: URL` is a required, non-optional, `let` stored property with no failable construction path in this file; Swift's type system prevents constructing `QuickLookPreview` with a missing or null `url` (see **requires-preview-url**).
- **Boundary values**: Not applicable — the component takes no numeric, size-constrained, or range-bound input; its only input is a file `URL`.
- **Concurrent access**: Not applicable — `makeNSView`, `updateNSView`, and `dismantleNSView` are `@MainActor`-isolated by `NSViewRepresentable`'s protocol declaration (see **confines-to-main-actor**), so SwiftUI never invokes them concurrently with one another.
- **Error states**: MUST, as observed in source — the only fallible operation in this file is `QLPreviewView(frame: .zero, style: .normal)`; its failure (a `nil` return, per the source's comment "returns nil only when QuickLook is unavailable") is handled by constructing `QLPreviewView()` instead (see **falls-back-to-default-style-when-unavailable**). Beyond that one path, this file defines no error handling: if `url` names a file that cannot be read, no longer exists, or has no QuickLook generator, `QLPreviewView` renders its own native "no preview available" state (per the source's doc comment) — this wrapper neither detects nor reports that condition itself, so it is documented here as `QLPreviewView`'s own behavior, not an error path this file implements.
- **Offline/disconnected state**: Not applicable — the component performs no networking; `url` identifies a local file and QuickLook rendering happens entirely on-device.
- **`url` changes while a preview is still generating**: MUST, as observed in source — when `updateNSView` receives a new `url` while `QLPreviewView` is still generating the previous preview, the component reassigns `previewItem` immediately (see **updates-preview-item-on-url-change**) without first canceling or waiting on the prior generation; any cancellation is internal to `QLPreviewView` and not implemented in this file.
- **Repeated identical `url` across consecutive `updateNSView` calls**: MUST, as observed in source — the component does not restart generation by reassigning an unchanged `previewItem` (see **skips-redundant-preview-item-updates**); per the source's own comment, reassigning the same item "restarts the generator and flickers."

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `url` | `URL` | required, set at init | The file to preview; assigned to `QLPreviewView.previewItem` on creation and reassigned whenever it changes (see **updates-preview-item-on-url-change**). |

## Deep Linking

Not applicable — `QuickLookPreview` is a content-display wrapper embedded within a caller's view (e.g. `FileEditorView`), not a navigable screen or route of its own; the source defines no URL scheme, route, or deep-link target.

## Localization

Not applicable — the source defines no string literal, `Text`, or `Label` of its own; it renders no text — all visible content comes from `QLPreviewView`'s native rendering of the previewed file.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the source contains no animation, transition, or motion effect of its own — `makeNSView`, `updateNSView`, and `dismantleNSView` each perform a direct property assignment or method call, with no animator proxy or animation context anywhere in this file. |
| Increase Contrast | Not applicable: the source sets no `NSColor`, `CGColor`, or theme-token color of its own; `QLPreviewView` renders its own native chrome, whose Increase Contrast handling, if any, is the system control's responsibility, not this wrapper's. |
| Differentiate Without Color | Not applicable: the source conveys no state or meaning through color — it has exactly one presentation, `QLPreviewView`'s rendering of whatever the file's own content is. |

## Feature Flags

Not applicable — no feature-flag lookup or conditional gate appears anywhere in this file; `QuickLookPreview` always constructs and configures its `QLPreviewView` unconditionally.

## Analytics

Not applicable — no analytics, tracking, or telemetry call appears anywhere in this file, and `QuickLookPreview` reports no user interaction (it wires no target/action of its own — see States).

## Privacy

- **Data collected**: None of its own. The component holds only the `url` stored property it is given; it neither reads the file's bytes directly (`QLPreviewView` does that) nor collects anything else.
- **Storage**: Not applicable — the source performs no read or write of its own beyond handing `url` to `QLPreviewView`, which reads and renders the file itself.
- **Transmission**: Not applicable — no networking call appears anywhere in this file; QuickLook rendering is entirely local to the device.
- **Retention**: Not applicable beyond the view's own lifetime — the only retained value is the `url` stored property, held for as long as the SwiftUI view exists; `dismantleNSView` releases the QuickLook generator process (see **closes-preview-view-on-dismantle**) rather than retaining it past the view's lifetime.

## Logging

Not applicable — the source contains no logging call (no `os_log`, `Logger`, or `print`) anywhere in this file.

## Platform Notes

- **SwiftUI** (source): `QuickLookPreview.swift` (`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Views/QuickLookPreview.swift`) is the entire source: an `NSViewRepresentable` struct with one stored property, `url: URL`, wrapping AppKit's `QLPreviewView` (from `QuickLookUI`) via `makeNSView`, `updateNSView`, and the static `dismantleNSView`. No other SwiftUI-native content — no `Text`, `Image`, shape, or custom drawing — appears in the file; every visible pixel comes from the wrapped `QLPreviewView`.
- **Compose**: There is no first-party Android/Compose equivalent of QuickLook. Reproduce "show it if we can" per file type instead: `AsyncImage`/Coil for images, ExoPlayer's `PlayerView` (wrapped in `AndroidView`) for video/audio, `PdfRenderer` rendered into a `Bitmap` shown in an `Image` for PDFs, and a plain "no preview available" `Column` for everything else — since no single OS-level control does what `QLPreviewView` does here, each format's fallback has to be composed explicitly rather than delegated.
- **React/Web**: Browsers likewise have no single universal preview control. Compose the same per-format fallback: an `<img>` for image MIME types, `<video>`/`<audio>` for media, an `<iframe>` or `pdf.js` for PDFs, and a plain fallback message for anything else, branching on the file's MIME type rather than delegating to one renderer.
- **AppKit / UIKit**: A pure-AppKit host would use `QLPreviewView` directly as a subview, calling `close()` from `deinit`/`viewWillDisappear` in place of `dismantleNSView`. UIKit has no `QLPreviewView` — the iOS analogue is `QLPreviewController`, a full-screen, `UIViewController`-based, one-item-at-a-time browser driven by `QLPreviewControllerDataSource`; porting to iOS means wrapping it as a `UIViewControllerRepresentable` presented modally, rather than embedding it inline the way `QLPreviewView` is embedded here.
- **WinUI 3** (the reason this recipe exists): Windows has no OS-level QuickLook equivalent — Explorer's Preview Pane host (`IPreviewHandler`) is a COM interface with no XAML/WinUI wrapper, so no single control can stand in for `QLPreviewView`. Build this as a `Frame` or `ContentControl` that inspects the file's extension/MIME type and swaps in the matching native control: an `Image` bound to a `BitmapImage` for image formats, a `MediaPlayerElement` for audio/video, and a `Microsoft.Web.WebView2` control navigated to the local file (`webView.CoreWebView2.Navigate(fileUri)`) for PDFs — WebView2's Chromium engine renders PDF natively — and any other browser-viewable format. Fall back to a plain "No preview available" `TextBlock` for everything else, mirroring `QLPreviewView`'s own graceful degradation (see Design Decisions), since there is no single control here to delegate that fallback to the way this source does. Swap the active child on `url`/file-type change the same way `updateNSView` swaps `previewItem`, guarding against reassigning an unchanged source the same way **skips-redundant-preview-item-updates** avoids restarting an unchanged `QLPreviewView` generator.

## Design Decisions

**Decision**: Lean on QuickLook (`QLPreviewView`) rather than a stack of per-file-type views.
**Rationale**: Per the source's own doc comment, this "is what keeps 'show it if we can' from becoming a format list this repo has to maintain," and reuses "the same renderer the user already knows from the Finder."
**Approved: pending**

**Decision**: An unsupported file format's "no preview available" message is left entirely to `QLPreviewView`, with no fallback view or message coded in this file.
**Rationale**: Per the source's own doc comment, "a type QuickLook has no generator for draws its own 'no preview available' — that is the honest answer, and it costs nothing."
**Approved: pending**

**Decision**: `updateNSView` guards reassignment of `previewItem` behind an equality check rather than always reassigning it.
**Rationale**: Per the source's own comment, "reassigning the same item restarts the generator and flickers, so only a genuine change is pushed through."
**Approved: pending**

**Decision**: `dismantleNSView` explicitly calls `view.close()` rather than relying on ARC/`deinit` to release the view.
**Rationale**: Per the source's own comment, "QuickLook holds a generator process alive per view; closing releases it rather than waiting for the view to be collected."
**Approved: pending**

**Decision**: The failable `QLPreviewView(frame:style:)` initializer is used with a fallback to `QLPreviewView()` rather than force-unwrapping it.
**Rationale**: Per the source's own comment, "the failable initializer is the only one that takes a style; it returns nil only when QuickLook is unavailable, and the plain initializer is the same view at the default style" — a genuine but rare fallback is handled rather than risking a crash.
**Approved: pending**

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [main-actor-confined](agenticdevelopercookbook://compliance/architecture#main-actor-confined) | passed | architecture |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

`native-controls-preference` and `platform-design-language` pass because the component delegates all preview rendering to `QLPreviewView`, Finder's own native QuickLook control, rather than a bespoke per-format viewer. `main-actor-confined` passes because `NSViewRepresentable`'s `makeNSView`/`updateNSView`/`dismantleNSView` requirements are `@MainActor`-isolated by the protocol itself (see **confines-to-main-actor**). `idempotent-operations` passes because `updateNSView` is a no-op when the incoming `url` already matches the view's current `previewItem` (see **skips-redundant-preview-item-updates**). `graceful-degradation` passes because an unsupported or unreadable file falls back to `QLPreviewView`'s own native "no preview available" rendering rather than crashing or leaving a blank view (see Design Decisions). `separation-of-concerns` passes because this file contains no per-file-type logic of its own — it only bridges SwiftUI to `QLPreviewView` and defers all format-specific rendering to QuickLook.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
