import CoreGraphics
import Testing
@testable import AgenticToolkitDisplays

@Suite struct ModeCatalogTests {
    private func mode(
        _ width: Int, _ height: Int, px pixel: Int, hz refresh: Double = 60, usable: Bool = true
    ) -> DisplayMode {
        DisplayMode(pointSize: CGSize(width: width, height: height),
                    pixelSize: CGSize(width: pixel, height: pixel * height / width),
                    refreshRate: refresh, isUsableForDesktopGUI: usable)
    }

    @Test func splitsRetinaAndStandardSortedLargestFirst() {
        let catalog = ModeCatalog(modes: [mode(1920, 1080, px: 1920), mode(1920, 1080, px: 3840),
                                          mode(2560, 1440, px: 5120), mode(3840, 2160, px: 3840)])
        #expect(catalog.retina.map(\.spec.width) == [2560, 1920])
        #expect(catalog.standard.map(\.spec.width) == [3840, 1920])
    }

    @Test func removesExactDuplicatesAndOrdersRefreshDescending() {
        let catalog = ModeCatalog(modes: [mode(1920, 1080, px: 1920, hz: 60), mode(1920, 1080, px: 1920, hz: 60),
                                          mode(1920, 1080, px: 1920, hz: 120)])
        #expect(catalog.standard.map(\.refreshRate) == [120, 60])
    }

    @Test func hidesUnusableModesUnlessAsked() {
        let modes = [mode(640, 480, px: 640, usable: false), mode(1920, 1080, px: 1920)]
        #expect(ModeCatalog(modes: modes).standard.count == 1)
        #expect(ModeCatalog(modes: modes, includeUnusable: true).standard.count == 2)
    }
}
