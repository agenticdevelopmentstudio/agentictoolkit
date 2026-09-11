import AgenticToolkitCore
import AppKit

/// A tab bar item that describes a session: agent and model, status, name,
/// working directory, branch and summary. Vended by a branch controller,
/// hosted by `MultiTabbedViewController` through `TabItem.viewController`.
@MainActor
public final class TabPaneViewController: NSViewController, TabBarHostedItem {
    public let edge: Edge
    public let tabID: UUID
    public weak var dataSource: TabPaneDataSource?
    public weak var delegate: TabPaneDelegate?

    public var isHighlighted: Bool = false {
        didSet { paneView.isHighlighted = isHighlighted }
    }
    public var onClose: (() -> Void)? {
        didSet { paneView.onClose = onClose }
    }

    private(set) lazy var paneView = TabPaneView(edge: edge, tabID: tabID)

    public init(edge: Edge, tabID: UUID) {
        self.edge = edge
        self.tabID = tabID
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    public override func loadView() {
        view = paneView
        paneView.contextMenuProvider = { [weak self] event in
            guard let self else { return nil }
            return self.delegate?.tabPane(self, contextMenuFor: event)
        }
        paneView.isHighlighted = isHighlighted
        paneView.onClose = onClose
    }

    /// Re-reads the data source and resizes. Call after anything it reports changes.
    public func reload() {
        loadViewIfNeeded()
        guard let dataSource else { return }
        let agent = dataSource.tabPaneAgentName(self)
        let model = dataSource.tabPaneModelName(self)
        paneView.agentLabel.stringValue = model.map { "\(agent) · \($0)" } ?? agent
        paneView.setStatusSymbols(dataSource.tabPaneStatusSymbols(self))
        paneView.sessionLabel.stringValue = dataSource.tabPaneSessionName(self)
        paneView.directoryLabel.stringValue = Self.abbreviate(dataSource.tabPaneWorkingDirectory(self))
        let branch = dataSource.tabPaneBranch(self)
        paneView.branchLabel.stringValue = branch ?? ""
        paneView.branchLabel.isHidden = branch == nil
        let summary = dataSource.tabPaneSummary(self)
        paneView.summaryLabel.stringValue = summary ?? ""
        paneView.summaryLabel.isHidden = summary == nil
        title = paneView.sessionLabel.stringValue
        preferredContentSize = paneView.contentSize
    }

    /// `/Users/me/x` → `~/x`; anything else stays absolute.
    static func abbreviate(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
