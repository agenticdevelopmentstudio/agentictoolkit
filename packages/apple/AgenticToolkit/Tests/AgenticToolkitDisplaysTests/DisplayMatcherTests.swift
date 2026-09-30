import CoreGraphics
import Testing
@testable import AgenticToolkitDisplays

@Suite struct DisplayMatcherTests {
    private func key(_ uuid: String?, _ name: String?, _ width: CGFloat = 100, main: Bool = false) -> DisplayMatchKey {
        DisplayMatchKey(uuid: uuid, name: name, size: CGSize(width: width, height: 100), isMain: main)
    }

    @Test func tiers() {
        let saved = key("U", "Name", 100, main: true)
        let byKey: (DisplayMatchKey) -> DisplayMatchKey = { $0 }
        #expect(DisplayMatcher.bestMatch(for: saved, among: [key("U", "x")], key: byKey)?.quality == .exact)
        let uuidSizeChanged = DisplayMatcher.bestMatch(for: saved, among: [key("U", "x", 200)], key: byKey)
        #expect(uuidSizeChanged?.quality == .uuidSizeChanged)
        #expect(DisplayMatcher.bestMatch(for: saved, among: [key("V", "Name")], key: byKey)?.quality == .nameOnly)
        let positionOnly = DisplayMatcher.bestMatch(for: saved, among: [key("V", "y", main: true)], key: byKey)
        #expect(positionOnly?.quality == .positionOnly)
        #expect(DisplayMatcher.bestMatch(for: saved, among: [key("V", "y")], key: byKey) == nil)
    }

    @Test func bestTierWinsAndFirstWinsTies() {
        let saved = key("U", "Name")
        let candidates = [key("V", "Name"), key("U", "other"), key("U", "third")]
        let match = DisplayMatcher.bestMatch(for: saved, among: Array(candidates.enumerated()), key: { $0.element })
        #expect(match?.candidate.offset == 1)
        #expect(match?.quality == .exact)
    }
}
