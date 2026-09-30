import CoreGraphics
import Testing
@testable import AgenticToolkitDisplays

@MainActor @Suite struct AutoApplierTests {
    let system = FakeDisplaySystem.desk()
    let store = InMemoryDocumentStore()
    let event = DisplayEvent(reasons: [.reconfigured])

    @Test func noLayoutForThisSet() throws {
        let service = try LayoutService(system: system, store: store)
        #expect(AutoApplier(service: service).handle(event) == .noLayout)
    }

    @Test func appliesThenConvergesOnOwnReconfiguration() throws {
        let service = try LayoutService(system: system, store: store)
        _ = try service.captureCurrent(name: "Desk", autoApply: true, withModes: false)
        try system.apply([.origin(2, CGPoint(x: -3840, y: 0))])
        let applier = AutoApplier(service: service)
        guard case .applied("Desk", _) = applier.handle(event) else { Issue.record("expected applied"); return }
        #expect(applier.handle(event) == .alreadyCorrect("Desk"))
    }

    /// macOS nudges the LG 5pt down from where it was asked to go, so the
    /// plan never becomes a no-op. The applier must apply once, then report
    /// the drift rather than loop.
    @Test func nudgedOriginAppliesOnceThenReportsDrift() throws {
        let service = try LayoutService(system: system, store: store)
        _ = try service.captureCurrent(name: "Desk", autoApply: true, withModes: false)
        try system.apply([.origin(2, CGPoint(x: -3840, y: 0))])
        system.originAdjustment = { id, point in id == 2 ? CGPoint(x: point.x, y: point.y + 5) : point }
        let batchesBefore = system.appliedBatches.count
        let applier = AutoApplier(service: service)
        let results = (0..<3).map { _ in applier.handle(event) }
        #expect(system.appliedBatches.count - batchesBefore == 1)
        guard case let .applied("Desk", report) = results[0] else { Issue.record("expected applied"); return }
        let drift = [ArrangeDrift(displayID: 2, requested: CGPoint(x: -3840, y: -615),
                                  actual: CGPoint(x: -3840, y: -610))]
        #expect(report.drift == drift)
        #expect(results[1] == .drifted("Desk", drift))
        #expect(results[2] == .drifted("Desk", drift))
    }

    @Test func externalChangeAfterDriftAppliesAgain() throws {
        let service = try LayoutService(system: system, store: store)
        _ = try service.captureCurrent(name: "Desk", autoApply: true, withModes: false)
        system.originAdjustment = { id, point in id == 2 ? CGPoint(x: point.x, y: point.y + 5) : point }
        try system.apply([.origin(2, CGPoint(x: -3840, y: 0))])
        let applier = AutoApplier(service: service)
        guard case .applied = applier.handle(event) else { Issue.record("expected applied"); return }
        guard case .drifted = applier.handle(event) else { Issue.record("expected drifted"); return }
        try system.apply([.origin(2, CGPoint(x: -3840, y: 100))])
        guard case .applied = applier.handle(event) else { Issue.record("expected a fresh apply"); return }
    }

    @Test func documentChangeClearsTheRecord() throws {
        let service = try LayoutService(system: system, store: store)
        _ = try service.captureCurrent(name: "Desk", autoApply: true, withModes: false)
        try system.apply([.origin(2, CGPoint(x: -3840, y: 0))])
        system.originAdjustment = { id, point in id == 2 ? CGPoint(x: point.x, y: point.y + 5) : point }
        let applier = AutoApplier(service: service)
        guard case .applied = applier.handle(event) else { Issue.record("expected applied"); return }
        try service.setLabel("Wide", width: 7680, height: 2160, refreshRate: nil)
        guard case .applied = applier.handle(event) else { Issue.record("expected a fresh apply"); return }
    }

    @Test func disabledPreferenceWins() throws {
        let service = try LayoutService(system: system, store: store)
        _ = try service.captureCurrent(name: "Desk", autoApply: true, withModes: false)
        try service.setAutoApplyEnabled(false)
        #expect(AutoApplier(service: service).handle(event) == .disabled)
    }

    @Test func nonAutoLayoutsAreIgnored() throws {
        let service = try LayoutService(system: system, store: store)
        _ = try service.captureCurrent(name: "Desk", autoApply: false, withModes: false)
        #expect(AutoApplier(service: service).handle(event) == .noLayout)
    }

    @Test func failureIsReportedNotThrown() throws {
        let service = try LayoutService(system: system, store: store)
        _ = try service.captureCurrent(name: "Desk", autoApply: true, withModes: false)
        try system.apply([.origin(2, CGPoint(x: -3840, y: 0))])
        system.failNextApply = .configurationFailed(step: "complete", code: 1001)
        let expected = LayoutServiceError.display(.configurationFailed(step: "complete", code: 1001))
        #expect(AutoApplier(service: service).handle(event) == .failed("Desk", expected))
    }
}
