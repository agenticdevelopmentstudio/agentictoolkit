---
id: 1727e605-6f83-42d7-960f-45fbdf714d94
title: Quick Look Preview
domain: agentictoolkit://cookbook/macos/ui/view-controllers/file-browser/views/quick-look-preview
type: ingredient
version: 1.1.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
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
- agentictoolkit://cookbook/macos/ui/view-controllers/file-browser/views/file-editor-view
references: []
approved-by: ''
approved-date: ''
---

# Quick Look Preview

## Overview

`QuickLookPreview` (`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Views/QuickLookPreview.swift`) is a SwiftUI `NSViewRepresentable` that bridges AppKit's `QLPreviewView` (from `QuickLookUI`) into a SwiftUI view hierarchy. Given a single `url: URL`, it shows Finder's own QuickLook preview of that file — images, PDFs, movies, audio, archives, Keynote decks, and anything else QuickLook has a generator for. Per the source's own doc comment, it exists so that the files a source-code editor cannot render ("the files the source editor can't take") still show something, without this codebase maintaining a per-file-type viewer stack of its own: QuickLook is "the same renderer the user already knows from the Finder," and a file type QuickLook cannot preview draws its own "no preview available" state at no cost to this file. It is used by `FileEditorView` (a sibling component, out of scope for this recipe) to render the `.quickLook(url)` branch of that view's content switch.

## Behavioral Requirements

- **wraps-native-preview-control**: The component MUST present the platform's native file-preview control within the surrounding SwiftUI (or platform-equivalent) view hierarchy, as a wrapped native view rather than a bespoke re-implementation.
- **requires-preview-url**: The component MUST expose `url: URL` as a required, non-optional, immutable (`let`) stored property naming the file to preview.
- **confines-to-main-actor**: The component MUST be usable only on the main actor: `NSViewRepresentable`'s `makeNSView(context:)`, `updateNSView(_:context:)`, and `dismantleNSView(_:coordinator:)` requirements are `@MainActor`-isolated by the protocol declaration itself, not by an explicit annotation in this file.
- **constructs-preview-view-with-normal-style**: On creation, the component MUST initialize the native preview control in its full-featured ("normal") presentation style rather than a reduced one.
- **falls-back-to-default-style-when-unavailable**: If the native preview control's full-featured-style initializer is unavailable (yields no instance), the component MUST fall back to constructing the control at its default style instead of crashing or leaving no view.
- **enables-autostart**: The component MUST configure the native preview control to begin generating its preview immediately upon creation, without requiring a separate, explicit start call.
- **sets-initial-preview-item**: On creation, the component MUST configure the native preview control to preview the file at `url` before the control is returned to the view hierarchy.
- **skips-redundant-preview-item-updates**: The component MUST NOT re-trigger preview generation when the incoming `url` is unchanged from the file the control is already showing.
- **updates-preview-item-on-url-change**: The component MUST update the native preview control to display the new file when `url` changes to a value different from the file it is currently showing.
- **closes-preview-view-on-dismantle**: The component MUST release the native preview control's underlying preview-generation resources when the component is removed from the view hierarchy.

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
- **Announce state changes**: Not implemented — when `url` changes and `updateNSView` reassigns `previewItem` (see **updates-preview-item-on-url-change**), no explicit accessibility notification (e.g., a layout-changed or screen-changed post) accompanies that reassignment anywhere in this file; any announcement to VoiceOver of the changed preview content is `QLPreviewView`'s own automatic behavior, not code defined here.
- **Minimum tap target**: Not applicable — `QuickLookPreview` targets macOS pointer input and wires no target/action, gesture recognizer, or click handling of its own in this file, so it has no tap target of its own to size; any hit-testing inside the preview is `QLPreviewView`'s native, pointer-driven behavior.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| quick-look-preview-001 | wraps-native-preview-control | Embed `QuickLookPreview(url:)` in a SwiftUI view hierarchy | It compiles and renders as an `NSViewRepresentable`-backed `NSView` (a `QLPreviewView`) inside the SwiftUI tree |
| quick-look-preview-002 | requires-preview-url | Attempt to construct `QuickLookPreview()` with no `url` argument | Compilation fails; `url` has no default value and is not optional |
| quick-look-preview-003 | confines-to-main-actor | Call `makeNSView(context:)` from off the main actor | The compiler rejects the call at compile time under Swift's `@MainActor` isolation checking, inherited from `NSViewRepresentable`'s protocol requirements |
| quick-look-preview-004 | constructs-preview-view-with-normal-style | Construct `QuickLookPreview(url:)` in an environment where `QLPreviewView(frame:style:)` succeeds | `makeNSView` returns a `QLPreviewView` constructed with `frame: .zero, style: .normal` |
| quick-look-preview-005 | falls-back-to-default-style-when-unavailable | Code inspection (not runtime-exercisable: nothing in this codebase lets a test make `QLPreviewView(frame:style:)` return `nil`) | Per source, if the initializer returned `nil`, `makeNSView` would construct the view via the parameterless `QLPreviewView()` initializer instead, without crashing |
| quick-look-preview-006 | enables-autostart | Inspect the `QLPreviewView` returned by `makeNSView(context:)` | `view.autostarts == true` |
| quick-look-preview-007 | sets-initial-preview-item | Construct `QuickLookPreview(url: someURL)` | `(view.previewItem as? NSURL) as URL? == someURL` immediately after `makeNSView` returns |
| quick-look-preview-008 | skips-redundant-preview-item-updates | Call `updateNSView(_:context:)` with the `url` the view's `previewItem` already holds | `view.previewItem` is the same object after the call as before it (its setter is not invoked), verifiable via an identity comparison or a spy on the setter |
| quick-look-preview-009 | updates-preview-item-on-url-change | Call `updateNSView(_:context:)` with a `url` different from the view's current `previewItem` | `view.previewItem` is reassigned to the new `url` |
| quick-look-preview-010 | closes-preview-view-on-dismantle | SwiftUI removes `QuickLookPreview` from the view hierarchy, invoking `dismantleNSView(_:coordinator:)` | `close()` is called on the `QLPreviewView` |

## Edge Cases

- **Null/empty input**: Not applicable — `url: URL` is a required, non-optional, `let` stored property with no failable construction path in this file; Swift's type system prevents constructing `QuickLookPreview` with a missing or null `url` (see **requires-preview-url**).
- **Boundary values**: Not applicable — the component takes no numeric, size-constrained, or range-bound input; its only input is a file `URL`.
- **Concurrent access**: Not applicable — `makeNSView`, `updateNSView`, and `dismantleNSView` are `@MainActor`-isolated by `NSViewRepresentable`'s protocol declaration (see **confines-to-main-actor**), so SwiftUI never invokes them concurrently with one another.
- **Error states**: The only fallible operation in this file is the preview control's full-featured initializer, `QLPreviewView(frame: .zero, style: .normal)`; its failure (a `nil` return, per the source's comment "returns nil only when QuickLook is unavailable") is handled by falling back to `QLPreviewView()` instead (see **falls-back-to-default-style-when-unavailable**). Beyond that one path, this file defines no error handling. The source's own doc comment states that a file type with no QuickLook generator makes `QLPreviewView` draw its own native "no preview available" state; the doc comment makes no equivalent claim for a file that cannot be read or no longer exists, so this recipe does not extend that claim to those cases. This wrapper neither detects nor reports any of these conditions itself — whatever `QLPreviewView` does with an unreadable or missing file is its own behavior, unconfirmed by this source file.
- **Offline/disconnected state**: Not applicable — the component performs no networking; `url` identifies a local file and QuickLook rendering happens entirely on-device.
- **`url` changes while a preview is still generating**: When `updateNSView` receives a new `url` while `QLPreviewView` is still generating the previous preview, the component reassigns `previewItem` immediately (see **updates-preview-item-on-url-change**) without first canceling or waiting on the prior generation; any cancellation is internal to `QLPreviewView` and not implemented in this file.
- **Repeated identical `url` across consecutive `updateNSView` calls**: The component does not restart generation by reassigning an unchanged `previewItem` (see **skips-redundant-preview-item-updates**); per the source's own comment, reassigning the same item "restarts the generator and flickers."

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

- **SwiftUI** (source): `QuickLookPreview.swift` (`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Views/QuickLookPreview.swift`) is the entire source: an `NSViewRepresentable` struct with one stored property, `url: URL`, wrapping AppKit's `QLPreviewView` (from `QuickLookUI`) via `makeNSView`, `updateNSView`, and the static `dismantleNSView` (see **wraps-native-preview-control**). `makeNSView` constructs the view via the failable `QLPreviewView(frame: .zero, style: .normal)` initializer, falling back to the parameterless `QLPreviewView()` when that returns `nil` (see **constructs-preview-view-with-normal-style**, **falls-back-to-default-style-when-unavailable**); sets `autostarts = true` (see **enables-autostart**); and assigns `url`, cast to `NSURL`, to `previewItem` (see **sets-initial-preview-item**). `updateNSView` reassigns `previewItem` to `url` cast to `NSURL` only when `(view.previewItem as? NSURL) as URL? != url` (see **updates-preview-item-on-url-change**, **skips-redundant-preview-item-updates**). `dismantleNSView` calls `view.close()` (see **closes-preview-view-on-dismantle**). No other SwiftUI-native content — no `Text`, `Image`, shape, or custom drawing — appears in the file; every visible pixel comes from the wrapped `QLPreviewView`.
- **Compose**: There is no first-party Android/Compose equivalent of QuickLook. Reproduce "show it if we can" per file type instead: `AsyncImage`/Coil for images, ExoPlayer's `PlayerView` (wrapped in `AndroidView`) for video/audio, `PdfRenderer` rendered into a `Bitmap` shown in an `Image` for PDFs, and a plain "no preview available" `Column` for everything else — since no single OS-level control does what `QLPreviewView` does here, each format's fallback has to be composed explicitly rather than delegated.
- **React/Web**: Browsers likewise have no single universal preview control. Compose the same per-format fallback: an `<img>` for image MIME types, `<video>`/`<audio>` for media, an `<iframe>` or `pdf.js` for PDFs, and a plain fallback message for anything else, branching on the file's MIME type rather than delegating to one renderer.
- **AppKit / UIKit**: A pure-AppKit host would use `QLPreviewView` directly as a subview, calling `close()` from `deinit`/`viewWillDisappear` in place of `dismantleNSView`. UIKit has no `QLPreviewView` — the iOS analogue is `QLPreviewController`, a full-screen, `UIViewController`-based, one-item-at-a-time browser driven by `QLPreviewControllerDataSource`; porting to iOS means wrapping it as a `UIViewControllerRepresentable` presented modally, rather than embedding it inline the way `QLPreviewView` is embedded here.
- **WinUI 3**: Windows has no OS-level QuickLook equivalent — Explorer's Preview Pane host (`IPreviewHandler`) is a COM interface with no XAML/WinUI wrapper, so no single control can stand in for `QLPreviewView`. Build this as a `Frame` or `ContentControl` that inspects the file's extension/MIME type and swaps in the matching native control: an `Image` bound to a `BitmapImage` for image formats, a `MediaPlayerElement` for audio/video, and a `Microsoft.Web.WebView2` control navigated to the local file (`webView.CoreWebView2.Navigate(fileUri)`) for PDFs — WebView2's Chromium engine renders PDF natively — and any other browser-viewable format. Fall back to a plain "No preview available" `TextBlock` for everything else, mirroring `QLPreviewView`'s own graceful degradation (see Design Decisions), since there is no single control here to delegate that fallback to the way this source does. Swap the active child on `url`/file-type change the same way `updateNSView` swaps `previewItem`, guarding against reassigning an unchanged source the same way **skips-redundant-preview-item-updates** avoids restarting an unchanged `QLPreviewView` generator.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Views/QuickLookPreview.swift` |

## Design Decisions

**Decision**: Lean on QuickLook (`QLPreviewView`) rather than a stack of per-file-type views.
**Rationale**: Per the source's own doc comment, this "is what keeps 'show it if we can' from becoming a format list this repo has to maintain," and reuses "the same renderer the user already knows from the Finder."
**Approved**: pending

**Decision**: An unsupported file format's "no preview available" message is left entirely to `QLPreviewView`, with no fallback view or message coded in this file.
**Rationale**: Per the source's own doc comment, "a type QuickLook has no generator for draws its own 'no preview available' — that is the honest answer, and it costs nothing."
**Approved**: pending

**Decision**: `updateNSView` guards reassignment of `previewItem` behind an equality check rather than always reassigning it.
**Rationale**: Per the source's own comment, "reassigning the same item restarts the generator and flickers, so only a genuine change is pushed through."
**Approved**: pending

**Decision**: `dismantleNSView` explicitly calls `view.close()` rather than relying on ARC/`deinit` to release the view.
**Rationale**: Per the source's own comment, "QuickLook holds a generator process alive per view; closing releases it rather than waiting for the view to be collected."
**Approved**: pending

**Decision**: The failable `QLPreviewView(frame:style:)` initializer is used with a fallback to `QLPreviewView()` rather than force-unwrapping it.
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
