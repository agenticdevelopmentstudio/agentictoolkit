<!-- leaf: implement-general-2/quick-look-preview · source: quick-look-preview.md -->

**Rules** (cite as `implement-general-2/quick-look-preview#<slug>`):

- `wraps-native-preview-control` MUST
- `requires-preview-url` MUST
- `confines-to-main-actor` MUST
- `constructs-preview-view-with-normal-style` MUST
- `falls-back-to-default-style-when-unavailable` MUST
- `enables-autostart` MUST
- `sets-initial-preview-item` MUST
- `skips-redundant-preview-item-updates` MUST
- `updates-preview-item-on-url-change` MUST
- `closes-preview-view-on-dismantle` MUST

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

## Accessibility

- **Role/trait**: Not customized — the source sets no `accessibilityRole`, `accessibilityLabel`, or `isAccessibilityElement` override anywhere in this file; `QLPreviewView` carries AppKit's own built-in accessibility behavior for a QuickLook preview, unmodified by this wrapper.
- **Label requirements**: Not customized — the source assigns no accessibility label of its own; whatever label `QLPreviewView` exposes natively (e.g., derived from the previewed file) is unmodified by this file.
- **Announce state changes**: Not implemented — when `url` changes and `updateNSView` reassigns `previewItem` (see **updates-preview-item-on-url-change**), no explicit accessibility notification (e.g., a layout-changed or screen-changed post) accompanies that reassignment anywhere in this file; any announcement to VoiceOver of the changed preview content is `QLPreviewView`'s own automatic behavior, not code defined here.
- **Minimum tap target**: Not applicable — `QuickLookPreview` targets macOS pointer input and wires no target/action, gesture recognizer, or click handling of its own in this file, so it has no tap target of its own to size; any hit-testing inside the preview is `QLPreviewView`'s native, pointer-driven behavior.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `url` | `URL` | required, set at init | The file to preview; assigned to `QLPreviewView.previewItem` on creation and reassigned whenever it changes (see **updates-preview-item-on-url-change**). |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the source contains no animation, transition, or motion effect of its own — `makeNSView`, `updateNSView`, and `dismantleNSView` each perform a direct property assignment or method call, with no animator proxy or animation context anywhere in this file. |
| Increase Contrast | Not applicable: the source sets no `NSColor`, `CGColor`, or theme-token color of its own; `QLPreviewView` renders its own native chrome, whose Increase Contrast handling, if any, is the system control's responsibility, not this wrapper's. |
| Differentiate Without Color | Not applicable: the source conveys no state or meaning through color — it has exactly one presentation, `QLPreviewView`'s rendering of whatever the file's own content is. |

## Privacy

- **Data collected**: None of its own. The component holds only the `url` stored property it is given; it neither reads the file's bytes directly (`QLPreviewView` does that) nor collects anything else.
- **Storage**: Not applicable — the source performs no read or write of its own beyond handing `url` to `QLPreviewView`, which reads and renders the file itself.
- **Transmission**: Not applicable — no networking call appears anywhere in this file; QuickLook rendering is entirely local to the device.
- **Retention**: Not applicable beyond the view's own lifetime — the only retained value is the `url` stored property, held for as long as the SwiftUI view exists; `dismantleNSView` releases the QuickLook generator process (see **closes-preview-view-on-dismantle**) rather than retaining it past the view's lifetime.

