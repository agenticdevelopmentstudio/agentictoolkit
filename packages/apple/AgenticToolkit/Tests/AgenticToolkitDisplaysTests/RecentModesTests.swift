import Testing
@testable import AgenticToolkitDisplays

@Suite struct RecentModesTests {
    private func spec(_ width: Int) -> ModeSpec {
        ModeSpec(width: width, height: 1000, refreshRate: 60, isHiDPI: false)
    }

    @Test func newestFirstDistinctLimitedToThree() {
        var list: [ModeSpec] = []
        for width in [1, 2, 3, 2, 4] { list = RecentModes.recording(spec(width), in: list) }
        #expect(list.map(\.width) == [4, 2, 3])
    }

    @Test func refreshWithinHalfHertzIsTheSameMode() {
        let list = RecentModes.recording(ModeSpec(width: 1, height: 1000, refreshRate: 59.94, isHiDPI: false),
                                         in: [spec(1)])
        #expect(list.count == 1)
    }
}
