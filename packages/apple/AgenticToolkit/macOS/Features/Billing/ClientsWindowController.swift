import AppKit
import Combine
import AgenticToolkitCore

/// The Clients window: `BillingModel.clients` shown in the toolkit's
/// record-detail window, with each edit saved back through the model. The
/// model and settings arrive in a ``BillingUIContext``, so any app can host it.
@MainActor
public final class ClientsWindowController {

    public static private(set) var current: ClientsWindowController?

    public static let newClientName = "New Client"

    public let windowController: ComposableSettings.RecordDetailWindowController<BillingClientDTO>

    /// The save or delete in flight. Tests await it; nothing else reads it.
    public private(set) var lastWrite: Task<Void, Never>?

    private let model: BillingModel
    private let settings: BillingUserSettings
    private var subscription: AnyCancellable?
    private var lease: BillingWindowLease?

    private var confirm: ComposableSettings.Alerts.Confirm { windowController.confirm }
    private var reportFailure: ComposableSettings.Alerts.Report { windowController.reportFailure }

    /// Brings the window forward, building it first if needed, and activates
    /// the app: a menu command picked while another app is frontmost would
    /// otherwise open it behind that app.
    public static func present(context: BillingUIContext) {
        ensureCurrent(context: context).show()
        NSApp.activateUnlessQuiet()
    }

    /// Shows the window and keeps the model polling the lists while it is open.
    public func show() {
        windowController.showWindow()
        lease?.shown()
    }

    /// The window closed: stop listening, and let `present(context:)` build a
    /// fresh controller next time rather than keep this one alive and rebuilt
    /// on every poll.
    private func released() {
        subscription = nil
        if Self.current === self { Self.current = nil }
    }

    @discardableResult
    public static func ensureCurrent(context: BillingUIContext) -> ClientsWindowController {
        if let current { return current }
        let controller = ClientsWindowController(context: context)
        current = controller
        return controller
    }

    /// - Parameters:
    ///   - confirm, reportFailure: sheets on this window unless given, so
    ///     tests can answer without one.
    public init(
        context: BillingUIContext,
        confirm: ComposableSettings.Alerts.Confirm? = nil,
        reportFailure: ComposableSettings.Alerts.Report? = nil
    ) {
        self.model = context.model
        self.settings = context.settings
        let windowController = ComposableSettings.RecordDetailWindowController<BillingClientDTO>(
            windowID: "billing.clients",
            title: "Clients",
            accessibilityPrefix: "billing.clients",
            makeDetailPanel: { ClientDetailPanel(client: $0) },
            updateDetailPanel: { panel, client in (panel as? ClientDetailPanel)?.apply(client) }
        )
        self.windowController = windowController
        if let confirm { windowController.confirm = confirm }
        if let reportFailure { windowController.reportFailure = reportFailure }

        windowController.windowStyleMask = [.titled, .closable, .resizable, .miniaturizable]
        windowController.windowSpec = WindowSpec(
            defaultSize: NSSize(width: 760, height: 560),
            minSize: NSSize(width: 560, height: 400),
            defaultPosition: .center,
            persistsFrame: true
        )
        windowController.emptyMessage = "No clients yet."
        windowController.onAddRecord = { [weak self] in
            guard let self else { return }
            self.lastWrite = Task { await self.addClient() }
        }
        windowController.onRemoveRecord = { [weak self] client in
            guard let self else { return }
            self.lastWrite = Task { await self.remove(client) }
        }
        // The factory runs before `self` exists; wire each pane as it is listed.
        windowController.onConfigurePanel = { [weak self] panel, _ in
            (panel as? ClientDetailPanel)?.onSave = { [weak self] edited in self?.save(edited) }
        }

        reload()
        subscription = model.changes.sink { [weak self] in self?.reload() }
        lease = BillingWindowLease(model: model, windowController: windowController) { [weak self] in
            self?.released()
        }
    }

    // MARK: - Content

    public func panel(for id: String) -> ClientDetailPanel? {
        windowController.panel(forRecordID: id) as? ClientDetailPanel
    }

    /// Clients by name, archived last. The owner sorts, not the window:
    /// Task 14's sidebar keeps the order it is given.
    private func reload() {
        let sorted = model.clients.sorted { lhs, rhs in
            if lhs.archived != rhs.archived { return !lhs.archived }
            return lhs.recordTitle.localizedStandardCompare(rhs.recordTitle) == .orderedAscending
        }
        windowController.setRecords(sorted)
    }

    // MARK: - Writes

    /// Creates a client with a name nobody has used yet, selects it, and puts
    /// the cursor in its name field.
    @discardableResult
    public func addClient() async -> BillingClientDTO? {
        let name = UniqueName.next(base: Self.newClientName, taken: model.clients.map(\.name))
        let draft = BillingClientDTO(
            id: "", name: name, currency: settings.currency.value)
        guard let saved = await model.saveClient(draft) else {
            reportFailure("The new client couldn't be saved. \(model.lastError ?? "")")
            return nil
        }
        windowController.selectRecord(id: saved.id)
        panel(for: saved.id)?.focusName()
        return saved
    }

    private func save(_ client: BillingClientDTO) {
        lastWrite = Task { [weak self] in
            guard let self else { return }
            if await self.model.saveClient(client) == nil {
                // The refresh that follows the write has re-applied the stored
                // client, but a refresh leaves alone a field still being
                // edited, and the refused text is in exactly that field. Force
                // it back, so ending the edit can't send it again.
                if let stored = self.model.client(id: client.id) {
                    self.panel(for: client.id)?.revert(attempted: client, stored: stored)
                }
                self.reportFailure("“\(client.recordTitle)” couldn't be saved. \(self.model.lastError ?? "")")
            }
        }
    }

    private func remove(_ client: BillingClientDTO) async {
        guard await ComposableSettings.Alerts.ask(
            confirm, "Delete “\(client.recordTitle)”?",
            detail: "Its projects and tracked time are kept; the projects become your own work.")
        else { return }
        if !(await model.deleteClient(id: client.id)) {
            reportFailure("“\(client.recordTitle)” couldn't be deleted. \(model.lastError ?? "")")
        }
    }
}
