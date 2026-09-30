import CoreGraphics
import Testing
@testable import AgenticToolkitDisplays

@MainActor @Suite struct FakeDisplaySystemTests {
    @Test func applyMovesOriginsAndNotifiesObservers() throws {
        let system = FakeDisplaySystem.desk()
        var notified = 0
        let observation = system.addReconfigurationObserver { notified += 1 }
        try system.apply([.origin(2, CGPoint(x: -3840, y: -1080))])
        #expect(system.onlineDisplays().first { $0.id == 2 }?.bounds.origin == CGPoint(x: -3840, y: -1080))
        #expect(notified == 1)
        observation.cancel()
        try system.apply([.origin(2, CGPoint(x: -3840, y: 0))])
        #expect(notified == 1)
    }

    @Test func droppingAnObservationWithoutCancelRemovesItsObserver() throws {
        let system = FakeDisplaySystem.desk()
        var notified = 0
        do {
            let observation = system.addReconfigurationObserver { notified += 1 }
            #expect(system.observerCount == 1)
            _ = observation
        }
        #expect(system.observerCount == 0)
        try system.apply([.origin(2, CGPoint(x: -3840, y: 0))])
        #expect(notified == 0)
    }

    @Test func applyModeResizesBoundsKeepingOrigin() throws {
        let system = FakeDisplaySystem.desk()
        let target = try #require(system.modes(for: 2).first { $0.pointSize == CGSize(width: 2560, height: 1440) })
        try system.apply([.mode(2, target)])
        let display = try #require(system.onlineDisplays().first { $0.id == 2 })
        #expect(display.bounds.size == CGSize(width: 2560, height: 1440))
        #expect(display.mode?.spec == target.spec)
    }

    @Test func unknownDisplayThrows() {
        let system = FakeDisplaySystem.desk()
        #expect(throws: DisplayError.displayNotFound(99)) { try system.apply([.origin(99, .zero)]) }
    }

    @Test func scriptedFailureThrowsAndChangesNothing() {
        let system = FakeDisplaySystem.desk()
        system.failNextApply = .configurationFailed(step: "complete", code: 1001)
        #expect(throws: DisplayError.configurationFailed(step: "complete", code: 1001)) {
            try system.apply([.origin(2, .zero)])
        }
        #expect(system.onlineDisplays().first { $0.id == 2 }?.bounds.origin == CGPoint(x: -3840, y: -615))
    }
}
