import AppKit
import os
import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// Adopted by pane content that holds live resources — child processes, file
/// system watchers — so closing the pane releases them at that moment instead
/// of whenever the last reference happens to go. Optional: content with nothing
/// to tear down simply doesn't adopt it.
@MainActor
public protocol PaneContentTeardown: AnyObject {
    func paneContentWillBeDiscarded()
}

/// Adopted by pane content that would lose something if its pane were closed —
/// a running shell, an edit that is not on disk. The content is the only thing
/// that knows, so it is asked rather than guessed at; returning `nil` means
/// "nothing would be lost", which is why content with nothing at stake simply
/// doesn't adopt this.
@MainActor
public protocol PaneContentRemovalConfirmation: AnyObject {
    /// What the user is about to lose, phrased for an alert body — or `nil` to
    /// remove the pane without asking.
    var removalConfirmationMessage: String? { get }
}

/// What a factory is told about the pane it is filling.
///
/// A struct rather than a parameter list so a new fact can be added without
/// breaking every registered factory in every consumer (`optimize-for-change`).
@MainActor
public struct ComposableTabsViewContext {
    public let viewID: ComposableTabsViewID
    public let descriptor: ComposableTabsViewDescriptor
    public let nodeID: UUID
    public let project: ProjectWorkspace
    /// The directory this pane's content should be rooted in — the tab's
    /// working directory, shared by every pane in the same split tree.
    public let workingDirectory: URL
    /// 1-based, allocated per project, and what the placeholder shows.
    public let paneNumber: Int
    /// The layout node this pane's remembered state belongs to, for a pane
    /// that is not a layout node itself — see `ProjectPaneStateStore.ownerNodeID`.
    /// `nil` for every pane a window lays out directly.
    public let ownerNodeID: UUID?

    /// The store this pane's content should remember things in.
    ///
    /// Content asks for this rather than building a `ProjectPaneStateStore`
    /// itself, so where a nested pane's rows live stays one decision in one
    /// place instead of a key every factory has to spell the same way.
    public func makeStateStore(prefix: String) -> ProjectPaneStateStore {
        let store = ProjectPaneStateStore(project: project, nodeID: nodeID, prefix: prefix)
        store.ownerNodeID = ownerNodeID
        return store
    }
}

/// The per-view facts a split needs before the view has any content to measure,
/// plus the ones a menu needs to offer it.
public struct ComposableTabsViewDescriptor: Sendable {

    /// What the Split menu calls this view — "Terminal", not "whippet.terminal".
    public var displayName: String
    /// Optional SF Symbol for menu items showing this view.
    public var symbolName: String?
    /// The axis this view would rather be added along. A *default direction*,
    /// not a constraint: it decides which way the Split menu proposes first and
    /// does not forbid the user putting the view on the other axis.
    public var preferredAxis: ComposableTabsAxis
    /// Minimum width (or height) of the pane, in points.
    public var minimumThickness: CGFloat
    /// Share of the enclosing split the pane asks for on first layout.
    /// `nil` means "no preference" — the split divides evenly.
    public var preferredThicknessFraction: CGFloat?
    /// Whether AppKit may collapse the pane to nothing.
    public var isCollapsible: Bool
    /// How hard the pane resists a window resize. `nil` derives it: a pane that
    /// named a fraction holds the width it was given, so growth comes out of
    /// its neighbours instead of being shared out.
    public var holdingPriority: NSLayoutConstraint.Priority?

    public init(
        displayName: String,
        symbolName: String? = nil,
        preferredAxis: ComposableTabsAxis = .horizontal,
        minimumThickness: CGFloat = 120,
        preferredThicknessFraction: CGFloat? = nil,
        isCollapsible: Bool = false,
        holdingPriority: NSLayoutConstraint.Priority? = nil
    ) {
        self.displayName = displayName
        self.symbolName = symbolName
        self.preferredAxis = preferredAxis
        self.minimumThickness = minimumThickness
        self.preferredThicknessFraction = preferredThicknessFraction
        self.isCollapsible = isCollapsible
        self.holdingPriority = holdingPriority
    }

    public static let placeholder = ComposableTabsViewDescriptor(displayName: "Placeholder")

    /// What an unregistered identifier resolves to. Same shape as the
    /// placeholder, so a project naming content this app lacks still lays out.
    public static let unknown = ComposableTabsViewDescriptor(displayName: "Unknown")

    /// The priority `ComposableTabsViewController` actually installs.
    public var resolvedHoldingPriority: NSLayoutConstraint.Priority {
        if let holdingPriority { return holdingPriority }
        guard preferredThicknessFraction != nil else { return .defaultLow }
        return NSLayoutConstraint.Priority(
            rawValue: NSLayoutConstraint.Priority.defaultLow.rawValue + 10
        )
    }
}

/// Vends the views a `ComposableTabsViewController` displays.
///
/// An **instance**, not a namespace of statics: the demo project and a real
/// app project need different view sets in the same process, and with global
/// registration the last registrant wins (`dependency-injection`). Each
/// project reaches its own registry through `ComposableTabsLayout`.
@MainActor
public final class ComposableTabsViewRegistry {

    /// Factories vend a view controller, not a bare view:
    /// `ComposableTabsPaneViewController` adopts it as a child, which is what
    /// puts the content in the responder chain, delivers its appearance
    /// callbacks, and keeps it alive. A factory that returned a view would
    /// leave its owner unowned and its `viewWillAppear` silent.
    public typealias Factory = @MainActor (ComposableTabsViewContext) -> NSViewController

    private struct Entry {
        let descriptor: ComposableTabsViewDescriptor
        let factory: Factory
    }

    private var entries: [ComposableTabsViewID: Entry] = [:]

    public init() {
        registerPlaceholder()
    }

    /// Every registry knows the placeholder, because a project is always
    /// allowed to name content this app doesn't have and losing the pane would
    /// lose the layout with it.
    private func registerPlaceholder() {
        register(.placeholder, descriptor: .placeholder) { context in
            PlaceholderPaneViewController(paneNumber: context.paneNumber)
        }
    }

    public func register(
        _ viewID: ComposableTabsViewID,
        descriptor: ComposableTabsViewDescriptor,
        factory: @escaping Factory
    ) {
        entries[viewID] = Entry(descriptor: descriptor, factory: factory)
    }

    /// Removes a registered view, answering whether anything was there.
    ///
    /// `.placeholder` is refused and logged: every registry must always
    /// resolve it, because a project is allowed to name content the running
    /// app does not have and losing the pane would lose the layout with it.
    /// Refused rather than thrown — the callers are teardown paths (an
    /// extension disabled, an extension uninstalled) where there is nothing
    /// useful to do with an error.
    @discardableResult
    public func unregister(_ viewID: ComposableTabsViewID) -> Bool {
        guard viewID != .placeholder else {
            Self.logger.error(
                "Refusing to unregister \(viewID.rawValue, privacy: .public) — every registry resolves it")
            return false
        }
        return entries.removeValue(forKey: viewID) != nil
    }

    public var registeredViewIDs: [ComposableTabsViewID] {
        entries.keys.sorted { $0.rawValue < $1.rawValue }
    }

    public func isRegistered(_ viewID: ComposableTabsViewID) -> Bool {
        entries[viewID] != nil
    }

    /// Falls back to `.unknown` for unregistered identifiers, which are the
    /// same ones `makeContentViewController` answers with a placeholder.
    public func descriptor(for viewID: ComposableTabsViewID) -> ComposableTabsViewDescriptor {
        entries[viewID]?.descriptor ?? .unknown
    }

    /// An unregistered identifier gets the placeholder rather than an error —
    /// a project can legitimately name content the running app doesn't have.
    /// It is logged at `.error` all the same, because the other way to arrive
    /// here is spec/registry drift, and that should be visible rather than
    /// silently rendering "Pane N" (`fail-fast`).
    public func makeContentViewController(
        for viewID: ComposableTabsViewID,
        nodeID: UUID,
        project: ProjectWorkspace,
        workingDirectory: URL,
        paneNumber: Int,
        ownerNodeID: UUID? = nil
    ) -> NSViewController {
        guard let entry = entries[viewID] else {
            Self.logger.error(
                "No view registered for \(viewID.rawValue, privacy: .public) — showing a placeholder")
            return PlaceholderPaneViewController(paneNumber: paneNumber)
        }
        return entry.factory(ComposableTabsViewContext(
            viewID: viewID,
            descriptor: entry.descriptor,
            nodeID: nodeID,
            project: project,
            workingDirectory: workingDirectory,
            paneNumber: paneNumber,
            ownerNodeID: ownerNodeID
        ))
    }
}

extension ComposableTabsViewRegistry: Loggable {
    public static nonisolated let logger = makeLogger()
}

// MARK: - Placeholder

/// The numbered, tinted rectangle a pane shows when its content type is the
/// placeholder — or when the project names content this app doesn't register.
@MainActor
public final class PlaceholderPaneViewController: NSViewController {

    private let paneNumber: Int

    public init(paneNumber: Int) {
        self.paneNumber = paneNumber
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        container.wantsLayer = true
        // The panes are told apart by their tints, so this wants the palette's
        // chart-series colors — the set whose job is to be mutually distinct —
        // rather than a fixed list of system hues no theme reaches.
        let number = paneNumber
        container.observeTheme { view, palette in
            let series = palette.chartSeriesNSColors
            guard !series.isEmpty else { return }
            let tint = series[(number - 1) % series.count]
            view.layer?.backgroundColor = tint.withAlphaComponent(0.15).cgColor
        }

        let title = ThemedLabel(
            string: "Pane \(paneNumber)", role: .primaryText, textRole: .heading)
        title.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(title)
        NSLayoutConstraint.activate([
            title.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        view = container
    }
}
