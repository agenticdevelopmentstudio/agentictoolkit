import CoreGraphics
import Testing
@testable import AgenticToolkitDisplays

@MainActor @Suite struct DisplayConfiguratorTests {
    @Test func setModeResolvesSpecAndApplies() throws {
        let system = FakeDisplaySystem.desk()
        let spec = ModeSpec(width: 2560, height: 1440, refreshRate: 60, isHiDPI: true)
        let mode = try DisplayConfigurator(system: system).setMode(spec, for: 2)
        #expect(mode.spec == spec)
        #expect(system.appliedBatches == [[.mode(2, mode)]])
    }

    @Test func setModeUnknownSpecThrows() {
        let spec = ModeSpec(width: 1, height: 1, refreshRate: 60, isHiDPI: false)
        #expect(throws: DisplayError.modeNotAvailable(spec)) {
            try DisplayConfigurator(system: FakeDisplaySystem.desk()).setMode(spec, for: 2)
        }
    }

    @Test func arrangeAppliesOneTransactionAndReportsNoDrift() throws {
        let system = FakeDisplaySystem.desk()
        let drift = try DisplayConfigurator(system: system).arrange(origins: [3: .zero, 2: CGPoint(x: -3840, y: -1080)])
        #expect(drift.isEmpty)
        #expect(system.appliedBatches.count == 1)
    }

    @Test func arrangeReportsDriftWhenMacOSNudges() throws {
        let system = FakeDisplaySystem.desk()
        system.originAdjustment = { id, point in id == 2 ? CGPoint(x: point.x, y: point.y + 10) : point }
        let drift = try DisplayConfigurator(system: system).arrange(origins: [3: .zero, 2: CGPoint(x: -3840, y: -1080)])
        let expected = ArrangeDrift(
            displayID: 2, requested: CGPoint(x: -3840, y: -1080), actual: CGPoint(x: -3840, y: -1070)
        )
        #expect(drift == [expected])
    }

    @Test func arrangeWithoutAnOriginAtZeroThrows() {
        #expect(throws: DisplayError.noMainOrigin) {
            try DisplayConfigurator(system: FakeDisplaySystem.desk()).arrange(origins: [2: CGPoint(x: 5, y: 5)])
        }
    }

    @Test func arrangeWithTwoOriginsAtZeroThrows() {
        let system = FakeDisplaySystem.desk()
        #expect(throws: DisplayError.noMainOrigin) {
            try DisplayConfigurator(system: system).arrange(origins: [3: .zero, 2: .zero])
        }
        #expect(system.appliedBatches.isEmpty)
    }

    @Test func arrangeUnknownDisplayThrows() {
        #expect(throws: DisplayError.displayNotFound(42)) {
            try DisplayConfigurator(system: FakeDisplaySystem.desk())
                .arrange(origins: [3: .zero, 42: CGPoint(x: 7680, y: 0)])
        }
    }
}
