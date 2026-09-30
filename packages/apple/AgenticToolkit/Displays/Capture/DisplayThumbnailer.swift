import CoreGraphics
import ScreenCaptureKit

public enum ThumbnailError: Error, Equatable, Sendable {
    /// Screen Recording permission is not granted. Never a blank image.
    case permissionDenied
    case displayNotFound(CGDirectDisplayID)
    case captureFailed(String)
}

/// Live screenshots of displays for menus and editors (ScreenCaptureKit).
public struct DisplayThumbnailer: Sendable {
    private let hasPermission: @Sendable () -> Bool

    public init(hasPermission: @escaping @Sendable () -> Bool = { CGPreflightScreenCaptureAccess() }) {
        self.hasPermission = hasPermission
    }

    public static func thumbnailSize(for display: Display, maxWidth: Int) -> CGSize {
        let width = max(CGFloat(maxWidth), 1)
        let height = max((display.bounds.height * width / max(display.bounds.width, 1)).rounded(), 1)
        return CGSize(width: width, height: height)
    }

    public func capture(_ display: Display, maxWidth: Int) async throws -> CGImage {
        guard hasPermission() else { throw ThumbnailError.permissionDenied }
        let content: SCShareableContent
        do { content = try await SCShareableContent.current } catch {
            throw ThumbnailError.captureFailed(String(describing: error))
        }
        guard let target = content.displays.first(where: { $0.displayID == display.id }) else {
            throw ThumbnailError.displayNotFound(display.id)
        }
        let size = Self.thumbnailSize(for: display, maxWidth: maxWidth)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(size.width)
        configuration.height = Int(size.height)
        configuration.showsCursor = false
        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(display: target, excludingWindows: []),
                configuration: configuration
            )
        } catch {
            throw ThumbnailError.captureFailed(String(describing: error))
        }
    }
}
