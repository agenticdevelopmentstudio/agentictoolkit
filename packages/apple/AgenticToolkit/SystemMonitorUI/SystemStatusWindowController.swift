import AppKit
import AgenticToolkitMacOS
import AgenticToolkitSystemMonitor

/// Shows an engine's readings while it is on screen. It follows the engine
/// only while visible, so a closed window costs nothing; the engine keeps
/// sampling for whoever else is watching it.
@MainActor
public final class SystemStatusViewController: WindowContentViewController<SystemStatusView> {

    public let engine: SystemMonitorEngine
    private var observation: SystemMonitorEngine.Observation?

    public init(engine: SystemMonitorEngine) {
        self.engine = engine
        super.init(contentView: SystemStatusView())
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    public override func viewWillAppear() {
        super.viewWillAppear()
        observation = engine.observe { [weak self] readings in
            guard let self else { return }
            contentView.show(readings, refreshedAt: engine.lastRefreshed)
        }
    }

    public override func viewDidDisappear() {
        super.viewDidDisappear()
        observation?.cancel()
        observation = nil
    }
}

/// The System Status window: one card per monitor, themed, updated live.
@MainActor
public final class SystemStatusWindowController: WindowController<SystemStatusViewController> {

    public static let windowID = "system-status"

    public init(engine: SystemMonitorEngine) {
        super.init(windowID: Self.windowID, contentViewController: SystemStatusViewController(engine: engine))
        windowSpec = WindowSpec(
            defaultSize: NSSize(width: 420, height: 560),
            minSize: NSSize(width: 340, height: 280),
            defaultPosition: .topRight,
            behavior: .persistsFrame
        )
        windowTitle = "System Status"
        windowStyleMask = [.titled, .closable, .miniaturizable, .resizable]
        minSize = windowSpec?.minSize
    }
}
