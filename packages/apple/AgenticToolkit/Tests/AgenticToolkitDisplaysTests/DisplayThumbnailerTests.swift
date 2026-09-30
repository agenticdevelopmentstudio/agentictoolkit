import CoreGraphics
import Testing
@testable import AgenticToolkitDisplays

@MainActor @Suite struct DisplayThumbnailerTests {
    let display = FakeDisplaySystem.makeDisplay(
        id: 3, uuid: "ODYSSEY", bounds: CGRect(x: 0, y: 0, width: 7680, height: 2160)
    )

    @Test func withoutPermissionThrowsInsteadOfBlankImage() async {
        let thumbnailer = DisplayThumbnailer(hasPermission: { false })
        await #expect(throws: ThumbnailError.permissionDenied) { try await thumbnailer.capture(display, maxWidth: 260) }
    }

    @Test func sizeKeepsAspectRatio() {
        #expect(DisplayThumbnailer.thumbnailSize(for: display, maxWidth: 260) == CGSize(width: 260, height: 73))
    }

    @Test func thumbnailSizeNeverZero() {
        let zeroWidth = DisplayThumbnailer.thumbnailSize(for: display, maxWidth: 0)
        #expect(zeroWidth.width >= 1)
        #expect(zeroWidth.height >= 1)

        let flatDisplay = FakeDisplaySystem.makeDisplay(
            id: 4, uuid: "FLAT", bounds: CGRect(x: 0, y: 0, width: 1, height: 1)
        )
        let flatSize = DisplayThumbnailer.thumbnailSize(for: flatDisplay, maxWidth: 260)
        #expect(flatSize.width >= 1)
        #expect(flatSize.height >= 1)
    }

    @Test func unknownDisplayWithPermission() async throws {
        let thumbnailer = DisplayThumbnailer(hasPermission: { true })
        let ghost = FakeDisplaySystem.makeDisplay(
            id: 999_999, uuid: "GHOST", bounds: CGRect(x: 0, y: 0, width: 10, height: 10)
        )
        do {
            _ = try await thumbnailer.capture(ghost, maxWidth: 100)
            Issue.record("expected an error")
        } catch let error as ThumbnailError {
            // Without Screen Recording permission on the test host, SCShareableContent fails first.
            let isCaptureFailed: Bool = { if case .captureFailed = error { return true } else { return false } }()
            #expect(error == .displayNotFound(999_999) || isCaptureFailed)
        }
    }
}
