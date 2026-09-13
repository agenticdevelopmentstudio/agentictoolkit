import XCTest
@testable import AgenticToolkitHTDV

final class HTDVLayoutEngineTests: XCTestCase {
    private let engine = HTDVLayoutEngine()

    func testCompactAlwaysStacks() {
        XCTAssertEqual(
            engine.layout(availableWidth: 2000, levelCount: 3, hasDetail: true, isCompact: true),
            .stack
        )
    }

    func testAllRailsFitWithoutDetail() {
        let mode = engine.layout(availableWidth: 1000, levelCount: 3, hasDetail: false, isCompact: false)
        XCTAssertEqual(mode, .columns(visibleRails: 0..<3, showsDetail: false))
    }

    func testDetailReservesMinimumWidth() {
        // 1000 - 480 = 520 → two 240pt rails fit.
        let mode = engine.layout(availableWidth: 1000, levelCount: 3, hasDetail: true, isCompact: false)
        XCTAssertEqual(mode, .columns(visibleRails: 1..<3, showsDetail: true))
    }

    func testAtLeastOneRailAlwaysVisible() {
        let mode = engine.layout(availableWidth: 300, levelCount: 4, hasDetail: true, isCompact: false)
        XCTAssertEqual(mode, .columns(visibleRails: 3..<4, showsDetail: true))
    }

    func testZeroLevels() {
        let mode = engine.layout(availableWidth: 800, levelCount: 0, hasDetail: false, isCompact: false)
        XCTAssertEqual(mode, .columns(visibleRails: 0..<0, showsDetail: false))
    }

    func testCustomWidths() {
        let custom = HTDVLayoutEngine(railWidth: 200, minDetailWidth: 300)
        let mode = custom.layout(availableWidth: 900, levelCount: 5, hasDetail: true, isCompact: false)
        // 900 - 300 = 600 → three 200pt rails.
        XCTAssertEqual(mode, .columns(visibleRails: 2..<5, showsDetail: true))
    }

    func testFloorNotRounding() {
        // 900 / 240 = 3.75 → floor gives 3, rounding would give 4.
        let mode = engine.layout(
            availableWidth: 900,
            levelCount: 5,
            hasDetail: false,
            isCompact: false
        )
        XCTAssertEqual(mode, .columns(visibleRails: 2..<5, showsDetail: false))
    }

    /// `railWidth` is a public settable `var` and the only `precondition` guarding it sits in `init`,
    /// so a post-init assignment of 0 divided by zero. The divisor is clamped to 1pt instead, which
    /// is observable: 2pt of available width fits exactly two 1pt rails, not all three. An unclamped
    /// divisor would produce `.infinity` here and show every rail.
    func testZeroRailWidthDividesByOnePointInstead() {
        var mutated = HTDVLayoutEngine()
        mutated.railWidth = 0
        let mode = mutated.layout(availableWidth: 2, levelCount: 3, hasDetail: false, isCompact: false)
        XCTAssertEqual(mode, .columns(visibleRails: 1..<3, showsDetail: false))
    }

    /// A negative `railWidth` is the same bug from the other side: `floor(1000 / -240)` is -5, which
    /// would collapse the layout to a single rail. Clamping the divisor to 1pt keeps 1000pt of width
    /// fitting every level.
    func testNegativeRailWidthClampsDivisorInsteadOfGoingNegative() {
        var mutated = HTDVLayoutEngine()
        mutated.railWidth = -240
        let mode = mutated.layout(availableWidth: 1000, levelCount: 3, hasDetail: false, isCompact: false)
        XCTAssertEqual(mode, .columns(visibleRails: 0..<3, showsDetail: false))
    }

    /// An unbounded sizing pass (`availableWidth: .infinity`) reached `Int(.infinity)`, a trapping
    /// conversion. Clamping the quotient to `levelCount` before converting makes it total: reaching
    /// the assertion at all is the proof, and every rail fits in infinite width.
    func testInfiniteAvailableWidthShowsEveryRailInsteadOfTrapping() {
        let mode = engine.layout(
            availableWidth: .infinity, levelCount: 3, hasDetail: false, isCompact: false
        )
        XCTAssertEqual(mode, .columns(visibleRails: 0..<3, showsDetail: false))
    }

    func testZeroLevelsWithDetail() {
        let mode = engine.layout(
            availableWidth: 800,
            levelCount: 0,
            hasDetail: true,
            isCompact: false
        )
        XCTAssertEqual(mode, .columns(visibleRails: 0..<0, showsDetail: true))
    }
}
