<!-- leaf: implement-general-2/quick-look-preview--part-2 · source: quick-look-preview.md -->

# Quick Look Preview — continued (part 2)

## Platform Notes

- **SwiftUI** (source): `QuickLookPreview.swift` (`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Views/QuickLookPreview.swift`) is the entire source: an `NSViewRepresentable` struct with one stored property, `url: URL`, wrapping AppKit's `QLPreviewView` (from `QuickLookUI`) via `makeNSView`, `updateNSView`, and the static `dismantleNSView` (see **wraps-native-preview-control**). `makeNSView` constructs the view via the failable `QLPreviewView(frame: .zero, style: .normal)` initializer, falling back to the parameterless `QLPreviewView()` when that returns `nil` (see **constructs-preview-view-with-normal-style**, **falls-back-to-default-style-when-unavailable**); sets `autostarts = true` (see **enables-autostart**); and assigns `url`, cast to `NSURL`, to `previewItem` (see **sets-initial-preview-item**). `updateNSView` reassigns `previewItem` to `url` cast to `NSURL` only when `(view.previewItem as? NSURL) as URL? != url` (see **updates-preview-item-on-url-change**, **skips-redundant-preview-item-updates**). `dismantleNSView` calls `view.close()` (see **closes-preview-view-on-dismantle**). No other SwiftUI-native content — no `Text`, `Image`, shape, or custom drawing — appears in the file; every visible pixel comes from the wrapped `QLPreviewView`.
- **Compose**: There is no first-party Android/Compose equivalent of QuickLook. Reproduce "show it if we can" per file type instead: `AsyncImage`/Coil for images, ExoPlayer's `PlayerView` (wrapped in `AndroidView`) for video/audio, `PdfRenderer` rendered into a `Bitmap` shown in an `Image` for PDFs, and a plain "no preview available" `Column` for everything else — since no single OS-level control does what `QLPreviewView` does here, each format's fallback has to be composed explicitly rather than delegated.
- **React/Web**: Browsers likewise have no single universal preview control. Compose the same per-format fallback: an `<img>` for image MIME types, `<video>`/`<audio>` for media, an `<iframe>` or `pdf.js` for PDFs, and a plain fallback message for anything else, branching on the file's MIME type rather than delegating to one renderer.
- **AppKit / UIKit**: A pure-AppKit host would use `QLPreviewView` directly as a subview, calling `close()` from `deinit`/`viewWillDisappear` in place of `dismantleNSView`. UIKit has no `QLPreviewView` — the iOS analogue is `QLPreviewController`, a full-screen, `UIViewController`-based, one-item-at-a-time browser driven by `QLPreviewControllerDataSource`; porting to iOS means wrapping it as a `UIViewControllerRepresentable` presented modally, rather than embedding it inline the way `QLPreviewView` is embedded here.
- **WinUI 3**: Windows has no OS-level QuickLook equivalent — Explorer's Preview Pane host (`IPreviewHandler`) is a COM interface with no XAML/WinUI wrapper, so no single control can stand in for `QLPreviewView`. Build this as a `Frame` or `ContentControl` that inspects the file's extension/MIME type and swaps in the matching native control: an `Image` bound to a `BitmapImage` for image formats, a `MediaPlayerElement` for audio/video, and a `Microsoft.Web.WebView2` control navigated to the local file (`webView.CoreWebView2.Navigate(fileUri)`) for PDFs — WebView2's Chromium engine renders PDF natively — and any other browser-viewable format. Fall back to a plain "No preview available" `TextBlock` for everything else, mirroring `QLPreviewView`'s own graceful degradation (see Design Decisions), since there is no single control here to delegate that fallback to the way this source does. Swap the active child on `url`/file-type change the same way `updateNSView` swaps `previewItem`, guarding against reassigning an unchanged source the same way **skips-redundant-preview-item-updates** avoids restarting an unchanged `QLPreviewView` generator.

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
