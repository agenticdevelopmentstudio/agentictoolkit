import Testing
@testable import AgenticToolkitDisplays

@Suite struct ModeLabelsTests {
    private let uhd = ModeSpec(width: 3840, height: 2160, refreshRate: 60, isHiDPI: false)

    @Test func builtInNames() {
        #expect(ModeLabels().label(for: uhd) == "4K UHD")
        let fullHD = ModeSpec(width: 1920, height: 1080, refreshRate: 60, isHiDPI: true)
        #expect(ModeLabels().label(for: fullHD) == "1080p NTSC")
        #expect(ModeLabels().label(for: ModeSpec(width: 1234, height: 567, refreshRate: 60, isHiDPI: false)) == nil)
    }

    @Test func overrideWithRefreshBeatsOverrideWithout() {
        var labels = ModeLabels()
        labels.set("Desk", width: 3840, height: 2160, refreshRate: nil)
        labels.set("Gaming", width: 3840, height: 2160, refreshRate: 60)
        #expect(labels.label(for: uhd) == "Gaming")
        #expect(labels.label(for: ModeSpec(width: 3840, height: 2160, refreshRate: 30, isHiDPI: false)) == "Desk")
    }

    @Test func emptyOverrideHidesBuiltInAndNilClears() {
        var labels = ModeLabels()
        labels.set("", width: 3840, height: 2160, refreshRate: nil)
        #expect(labels.label(for: uhd) == nil)
        labels.set(nil, width: 3840, height: 2160, refreshRate: nil)
        #expect(labels.label(for: uhd) == "4K UHD")
        #expect(labels.overrides.isEmpty)
    }
}
