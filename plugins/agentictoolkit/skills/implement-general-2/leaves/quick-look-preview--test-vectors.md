<!-- leaf: implement-general-2/quick-look-preview--test-vectors · source: quick-look-preview.md -->

# Quick Look Preview

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
