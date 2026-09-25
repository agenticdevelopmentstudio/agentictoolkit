import AppKit
import Combine
import AgenticToolkitCore

/// The Billing Activity window: `BillingModel`'s running timers, recent runs
/// and overview in `BillingActivityViewController`, with every action written
/// back through the model.
///
/// It *is* its window's `SingleWindowController`, not the owner of one, so the
/// window registry, scripting and restore see one object. It is not a
/// `SingletonWindowController`: that protocol builds its instance through a
/// no-argument `makeShared()`, and this window cannot be built without the
/// ``BillingUIContext`` the host app injects. `present(context:)` does what the
/// protocol's `present()` does — including activating the app, which a menu
/// command picked while another app is frontmost needs, or the note field it
/// focuses takes no keystrokes.
@MainActor
public final class BillingActivityWindowController: SingleWindowController {

    public static private(set) var current: BillingActivityWindowController?

    /// Asks a yes-or-no question as a sheet: the question, a detail line, the
    /// action button's title, and the answer.
    public typealias Ask = @MainActor (String, String, String, @escaping (Bool) -> Void) -> Void

    public let viewController: BillingActivityViewController

    /// The write in flight, and the chosen project's repository load in
    /// flight. Tests await them.
    public private(set) var lastWrite: Task<Void, Never>?
    public private(set) var lastRepoLoad: Task<Void, Never>?

    /// A start is being asked about or sent. The running-timer list that
    /// decides whether to ask moves only after the start's write and
    /// refresh, so a second Start in that gap would skip the question and
    /// have the daemon close the first timer a second after it began.
    public private(set) var isStarting = false {
        didSet { viewController.startButton.isEnabled = !isStarting }
    }

    private let model: BillingModel
    private var ask: Ask = { _, _, _, answer in answer(false) }
    private var reportFailure: ComposableSettings.Alerts.Report = { _ in }
    private let now: () -> Date
    private var subscription: AnyCancellable?
    private var lease: BillingWindowLease?

    /// Brings the window forward, building it first if needed, and activates
    /// the app.
    public static func present(context: BillingUIContext) {
        ensureCurrent(context: context).show()
        NSApp.activateUnlessQuiet()
    }

    /// Shows the window and keeps the model polling the lists while it is open.
    public func show() {
        showWindow()
        lease?.shown()
    }

    /// The window closed: stop listening, and let `present()` build a fresh
    /// controller next time rather than keep this one alive and rebuilt on
    /// every poll.
    private func released() {
        subscription = nil
        if Self.current === self { Self.current = nil }
    }

    @discardableResult
    public static func ensureCurrent(context: BillingUIContext) -> BillingActivityWindowController {
        if let current { return current }
        let controller = BillingActivityWindowController(model: context.model)
        current = controller
        return controller
    }

    /// The menus' New Timer…: the window, forward, with the cursor in the note.
    public static func presentNewTimer(context: BillingUIContext) {
        present(context: context)
        current?.focusNewTimer()
    }

    /// Puts the cursor in the new timer's note. The note, not the project
    /// popup: a text field takes focus whatever the keyboard-navigation
    /// setting, while a popup takes it only when full keyboard access is on.
    @discardableResult
    public func focusNewTimer() -> Bool {
        guard let window else { return false }
        let field = viewController.noteField.textField
        field.scrollToVisible(field.bounds)
        return window.makeFirstResponder(field)
    }

    public init(
        model: BillingModel,
        ask: Ask? = nil,
        reportFailure: ComposableSettings.Alerts.Report? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.model = model
        self.now = now
        let viewController = BillingActivityViewController()
        viewController.now = now
        self.viewController = viewController
        super.init(windowID: "billing.activity", contentViewController: viewController)

        windowTitle = "Billing Activity"
        windowStyleMask = [.titled, .closable, .resizable, .miniaturizable]
        windowSpec = WindowSpec(
            defaultSize: NSSize(width: 900, height: 640),
            minSize: NSSize(width: 640, height: 460),
            defaultPosition: .center,
            persistsFrame: true
        )
        self.ask = ask ?? { [weak self] question, detail, actionTitle, answer in
            ComposableSettings.Alerts.confirmDestructive(
                question, detail: detail, actionTitle: actionTitle, on: self?.window, answer)
        }
        self.reportFailure = reportFailure ?? { [weak self] message in
            ComposableSettings.Alerts.report(message, on: self?.window)
        }

        wire()
        reload()
        subscription = model.changes.sink { [weak self] in self?.reload() }
        lease = BillingWindowLease(model: model, windowController: self) { [weak self] in
            self?.released()
        }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("BillingActivityWindowController is code-built, never decoded")
    }

    // MARK: - Content

    private func reload() {
        viewController.show(
            running: model.runningTimers,
            recent: model.recentSegments,
            projects: model.projects,
            clients: model.clients,
            overview: model.overview
        )
    }

    private func wire() {
        viewController.onProjectChosen = { [weak self] projectId in
            guard let self, let projectId else { return }
            self.lastRepoLoad = Task {
                let repos = await self.model.repos(projectId: projectId)
                self.viewController.showRepos(repos, projectId: projectId)
            }
        }
        viewController.onStart = { [weak self] start in self?.requestStart(start) }
        viewController.onStop = { [weak self] segment in self?.stop(segment) }
        viewController.onCreateBillable = { [weak self] segment in
            guard let self else { return }
            self.lastWrite = Task {
                switch await self.model.promote(segmentIDs: [segment.id]) {
                case nil:
                    self.report("The billable couldn't be created. \(self.model.lastError ?? "")")
                case 0?:
                    // The daemon found nothing to roll up: a success that
                    // changed nothing reads as a button that does nothing.
                    self.report(Self.nothingToBill)
                default:
                    break
                }
            }
        }
        viewController.onAssign = { [weak self] segment, projectId in
            guard let self else { return }
            self.lastWrite = Task {
                if await self.model.assignAndRoll(segmentIDs: [segment.id], projectId: projectId) == nil {
                    self.report("The run couldn't be assigned. \(self.model.lastError ?? "")")
                }
            }
        }
        viewController.onDeriveHistory = { [weak self] days in
            guard let self else { return }
            self.lastWrite = Task {
                let since = UTCTimestamp.string(daysAgo: days, from: self.now())
                guard let queued = await self.model.backfill(since: since) else {
                    self.report("History couldn't be derived. \(self.model.lastError ?? "")")
                    return
                }
                self.viewController.showNotice(Self.deriveNotice(sessions: queued, days: days))
            }
        }
    }

    // MARK: - Timers

    /// Starts a timer. The daemon runs one timer at a time and stops the
    /// running one itself, so when one is running the user is asked first.
    /// A request made while another is still being asked about or sent is
    /// dropped: it is the same click twice, not a second timer.
    public func requestStart(_ start: BillingTimerStartDTO) {
        guard !isStarting else { return }
        isStarting = true
        guard let other = model.runningTimers.first(where: { $0.isManual }) else {
            lastWrite = Task { await self.startThenSettle(start) }
            return
        }
        let name = model.projectName(for: other)
        ask("Stop “\(name)” and start a new timer?",
            "Only one timer runs at a time. The time “\(name)” has run so far is kept.",
            "Stop and Start") { [weak self] confirmed in
            guard let self else { return }
            guard confirmed else {
                self.isStarting = false
                return
            }
            self.lastWrite = Task { await self.startThenSettle(start) }
        }
    }

    private func startThenSettle(_ start: BillingTimerStartDTO) async {
        await self.start(start)
        isStarting = false
    }

    /// Stops the running timer, if there is one. Tracked runs are left alone:
    /// they end when their session goes quiet.
    @discardableResult
    public func stopRunningTimer() -> Bool {
        guard let timer = model.runningTimers.first(where: { $0.isManual }) else { return false }
        stop(timer)
        return true
    }

    private func start(_ start: BillingTimerStartDTO) async {
        guard await model.startTimer(start) != nil else {
            report("The timer couldn't be started. \(model.lastError ?? "")")
            return
        }
        viewController.clearNote()
    }

    private func stop(_ segment: BillingSegmentDTO) {
        lastWrite = Task {
            if await self.model.stopTimer(id: segment.id) == nil {
                self.report("The timer couldn't be stopped. \(self.model.lastError ?? "")")
            }
        }
    }

    /// Reports a failure on this window, bringing it forward first. The
    /// menus' Stop Timer and New Timer work through this controller before
    /// its window has ever been shown, and an alert with no window to sit
    /// on is only logged — a timer the user thinks stopped would keep running.
    private func report(_ message: String) {
        if window?.isVisible != true { show() }
        reportFailure(message)
    }

    public static let nothingToBill = "Nothing was billed. The run's project or repository doesn't bill, "
        + "or the run is already on a billable."

    /// What Derive History queued, in a sentence. The daemon's passes do the
    /// work, so this promises runs, not a count of them.
    public static func deriveNotice(sessions: Int, days: Int) -> String {
        switch sessions {
        case 0: "No sessions in the last \(days) days to derive."
        case 1: "Deriving history for 1 session. Its runs appear over the next few minutes."
        default: "Deriving history for \(sessions) sessions. Runs appear over the next few minutes."
        }
    }
}
