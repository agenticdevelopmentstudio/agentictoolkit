import CoreGraphics
import Testing
@testable import AgenticToolkitDisplays

@Suite struct DisplayChangeTests {
    private func geo(
        _ identifier: String,
        _ originX: CGFloat,
        _ width: CGFloat = 100,
        visibleHeight: CGFloat = 90
    ) -> DisplayGeometry {
        DisplayGeometry(
            identityComponent: identifier,
            frame: CGRect(x: originX, y: 0, width: width, height: 100),
            visibleFrame: CGRect(x: originX, y: 0, width: width, height: visibleHeight)
        )
    }

    @Test func nothingChanged() { #expect(DisplayChange.classify(from: [geo("A", 0)], to: [geo("A", 0)]) == nil) }

    @Test func setChanged() {
        #expect(DisplayChange.classify(from: [geo("A", 0)], to: [geo("A", 0), geo("B", 100)])
                == .displaySetChanged(previous: "A", current: "A+B"))
    }

    @Test func resolutionChanged() {
        #expect(DisplayChange.classify(from: [geo("A", 0)], to: [geo("A", 0, 200)]) == .resolutionChanged)
    }

    @Test func dockResizeCountsAsResolutionChange() {
        #expect(DisplayChange.classify(from: [geo("A", 0)], to: [geo("A", 0, visibleHeight: 80)]) == .resolutionChanged)
    }

    @Test func arrangementChanged() {
        #expect(DisplayChange.classify(from: [geo("A", 0), geo("B", 100)], to: [geo("A", 0), geo("B", -100)])
                == .arrangementChanged)
    }

    @Test func swappingTwoIdenticalDisplaysIsNotAChange() {
        #expect(DisplayChange.classify(from: [geo("T", 0), geo("T", 100)], to: [geo("T", 100), geo("T", 0)]) == nil)
    }
}
