import CoreGraphics

public enum AutoApplyResult: Equatable, Sendable {
    case disabled
    case noLayout
    case alreadyCorrect(String)
    case applied(String, ApplyReport)
    /// The layout was applied earlier, macOS placed some displays elsewhere
    /// than requested, and nothing has changed since: the drift is reported
    /// again instead of re-applying, which would loop.
    case drifted(String, [ArrangeDrift])
    case failed(String, LayoutServiceError)
}

/// Applies the auto-apply layout for the current display set, only when
/// something differs, so our own reconfiguration converges instead of looping.
///
/// After an apply it remembers what the hardware actually ended up as. When
/// macOS nudges an origin, the plan never becomes a no-op again; as long as
/// the displays still match that remembered result (and neither the layout,
/// the display set nor the document has changed), it reports the drift
/// instead of applying again.
@MainActor
public final class AutoApplier {
    public let service: LayoutService
    private var lastApplied: AppliedRecord?

    public init(service: LayoutService) { self.service = service }

    public func handle(_ event: DisplayEvent) -> AutoApplyResult {
        guard service.document.preferences.autoApplyEnabled else {
            lastApplied = nil
            return .disabled
        }
        let setID = service.currentDisplaySet().id
        guard let layout = service.layouts.first(where: { $0.autoApply && $0.displaySetID == setID }) else {
            lastApplied = nil
            return .noLayout
        }
        if let record = lastApplied {
            if record.state == observe(layout) {
                return record.drift.isEmpty ? .alreadyCorrect(layout.name) : .drifted(layout.name, record.drift)
            }
            lastApplied = nil
        }
        do {
            if try service.plan(layout).isNoOp { return .alreadyCorrect(layout.name) }
            let report = try service.apply(layout)
            lastApplied = AppliedRecord(state: observe(layout), drift: report.drift)
            return .applied(layout.name, report)
        } catch {
            return .failed(layout.name, LayoutService.serviceError(error))
        }
    }

    private func observe(_ layout: Layout) -> ObservedState {
        let displays = service.system.onlineDisplays()
        return ObservedState(
            layout: layout,
            document: service.document,
            displaySetID: DisplaySet(displays.map(\.identity)).id,
            origins: Dictionary(displays.map { ($0.id, $0.bounds.origin) }, uniquingKeysWith: { first, _ in first }),
            modes: Dictionary(displays.compactMap { display in display.mode.map { (display.id, $0.spec) } },
                              uniquingKeysWith: { first, _ in first })
        )
    }
}

/// Everything whose change must trigger a fresh plan: the layout, the whole
/// document, the display set, and the displays' origins and modes.
private struct ObservedState: Equatable {
    let layout: Layout
    let document: DisplayDocument
    let displaySetID: String
    let origins: [CGDirectDisplayID: CGPoint]
    let modes: [CGDirectDisplayID: ModeSpec]
}

/// The state an apply produced (read back afterwards) and the drift it reported.
private struct AppliedRecord {
    let state: ObservedState
    let drift: [ArrangeDrift]
}
