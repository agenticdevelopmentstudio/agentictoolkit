import AppKit
import Foundation

/// Captures an NSWindow that the current process owns without prompting for
/// Screen Recording permission.
///
/// `CGWindowListCreateImage` is deprecated in macOS 14 (its replacement is
/// `ScreenCaptureKit`), but ScreenCaptureKit is async and requires Screen
/// Recording permission even when capturing your own windows. The legacy
/// CoreGraphics entry point still works for own-window capture without
/// permission. Resolving it via `dlsym` lets us keep using it without
/// triggering the deprecation warning at the call site — the symbol remains
/// exported by CoreGraphics.
///
/// If the runtime symbol ever disappears, `captureOwnWindow` returns `nil`
/// and callers should present an empty result rather than crashing.
public enum WindowScreenshot {

    /// Captures the given window as a CGImage. Returns nil if the legacy
    /// CoreGraphics symbol is unavailable or the capture failed.
    public static func captureOwnWindow(_ windowID: CGWindowID) -> CGImage? {
        guard let captureFn = windowImageFn else { return nil }
        return captureFn(.null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming, .bestResolution])?
            .takeRetainedValue()
    }

    /// Convenience: capture `window` and write a PNG to `url`. Returns true
    /// on success. No-op (returns false) if the window has no `windowNumber`
    /// (e.g. off-screen), the capture failed, or PNG encoding failed.
    @MainActor
    @discardableResult
    public static func writePNG(of window: NSWindow, to url: URL) -> Bool {
        guard window.windowNumber > 0 else { return false }
        guard let cgImage = captureOwnWindow(CGWindowID(window.windowNumber)) else { return false }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - dlsym resolution

private typealias WindowImageFn = @convention(c) (
    CGRect,
    CGWindowListOption,
    CGWindowID,
    CGWindowImageOption
) -> Unmanaged<CGImage>?

private let windowImageFn: WindowImageFn? = {
    guard let handle = dlopen(nil, RTLD_LAZY),
          let sym = dlsym(handle, "CGWindowListCreateImage") else {
        return nil
    }
    return unsafeBitCast(sym, to: WindowImageFn.self)
}()
