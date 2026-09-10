//
//  ViewsContributionPoint.swift
//  AgenticToolkit
//

import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import Foundation

/// Registers what each extension's `contributes.views` and
/// `contributes.viewsContainers` declare, as panes the tabs registry can vend.
///
/// What a declaration *means* — the namespaced id, the axis, the icon, every
/// note — is `ContributedViewsBuilder`'s, in `apple-core`, where it can be
/// tested without a window. This class is the AppKit half only: it puts the
/// result into a registry and hands back a placeholder pane.
///
/// A view entry is an id, a name and a placement; the content arrives at
/// runtime from `registerTreeDataProvider` or `createTreeView`. So what is
/// registered here is honestly a labelled empty pane, and it says so on its
/// face. That registry is the seam an extension host fills in later.
@MainActor
public final class ViewsContributionPoint: ContributionPoint {

    private struct Registration {
        let identifier: String
        /// `displayName ?? name`, kept for the placeholder's second line.
        /// Reading it back off the manifest at factory time would mean holding
        /// the manifest, and the manifest is the one thing here that is
        /// allowed to have gone away.
        let displayName: String
        let containers: [ContributedViewContainer]
        let views: [ContributedView]
    }

    /// An array, not a dictionary: application order is the only order these
    /// have, and a dictionary has none to report.
    private var registrations: [Registration] = []

    /// Every compromise made across every applied extension, in application
    /// order. The Extensions UI filters these by identifier at display time,
    /// which is why there is no pre-filtered accessor here.
    public private(set) var notes: [ContributedViewNote] = []

    /// Injected, never reached for globally: the registry is deliberately an
    /// instance, because a demo project and a real project need different view
    /// sets in one process (`dependency-injection`).
    private let registry: ComposableTabsViewRegistry

    public init(registry: ComposableTabsViewRegistry) {
        self.registry = registry
    }

    public var contributionKey: String { "views" }

    /// - Parameter directory: unused, and named `_` for that reason. Every
    ///   manifest key here that names a file — a view's or a container's
    ///   `icon` — is turned into a note rather than read, so this point opens
    ///   nothing.
    ///
    ///   Should that ever change, resolve a manifest-relative path as
    ///   `URL(fileURLWithPath: directory.path, isDirectory: true)` first:
    ///   `URL(fileURLWithPath:relativeTo:)` resolves against the base's
    ///   *parent* unless the base is known to be a directory, and Task 4.5a
    ///   shipped that bug once already.
    public func apply(
        _ contributions: ExtensionManifest.Contributions,
        from manifest: ExtensionManifest,
        at _: URL
    ) throws {
        // Withdraw first, as every contribution point here does: applying the
        // same extension twice — a reload, a disable/enable — must leave one
        // registration per view and one copy of each note (`idempotency`).
        withdraw(extensionIdentifier: manifest.identifier)

        let built = ContributedViewsBuilder.build(from: contributions, manifest: manifest)
        guard !built.containers.isEmpty || !built.views.isEmpty || !built.notes.isEmpty else {
            return
        }

        let displayName = manifest.displayName ?? manifest.name
        for view in built.views {
            registry.register(
                ComposableTabsViewID(view.registryID),
                descriptor: ComposableTabsViewDescriptor(
                    displayName: view.name,
                    symbolName: view.symbolName,
                    preferredAxis: view.preferredAxisIsVertical ? .vertical : .horizontal,
                    // Extension panes are auxiliary content. The registry's own
                    // non-collapsible built-ins are the ones a window cannot
                    // function without, and none of these is that.
                    isCollapsible: true
                )
            ) { _ in
                ExtensionViewPlaceholderViewController(
                    view: view, extensionDisplayName: displayName)
            }
        }

        registrations.append(Registration(
            identifier: manifest.identifier,
            displayName: displayName,
            containers: built.containers,
            views: built.views
        ))
        notes.append(contentsOf: built.notes)
    }

    public func withdraw(extensionIdentifier: String) {
        for registration in registrations where registration.identifier == extensionIdentifier {
            for view in registration.views {
                registry.unregister(ComposableTabsViewID(view.registryID))
            }
        }
        registrations.removeAll { $0.identifier == extensionIdentifier }
        notes.removeAll { $0.extensionIdentifier == extensionIdentifier }
    }

    public func containers(for extensionIdentifier: String) -> [ContributedViewContainer] {
        registrations.first { $0.identifier == extensionIdentifier }?.containers ?? []
    }

    public func views(for extensionIdentifier: String) -> [ContributedView] {
        registrations.first { $0.identifier == extensionIdentifier }?.views ?? []
    }
}

// MARK: - The pane

/// What a contributed view actually shows: its name, who contributed it, and
/// one sentence saying where the missing content would come from.
///
/// In this file rather than one of its own because it exists only as this
/// contribution point's factory output and has no other consumer — a separate
/// public file would be a shared component nobody assembles from
/// (`design-for-deletion`).
///
/// No spinner, no empty outline, no fake tree. An empty outline would be a
/// lie: the extension ships the code that fills it, and this host does not run
/// that code yet.
@MainActor
public final class ExtensionViewPlaceholderViewController: NSViewController {

    private let contributedView: ContributedView
    private let extensionDisplayName: String

    public init(view: ContributedView, extensionDisplayName: String) {
        self.contributedView = view
        self.extensionDisplayName = extensionDisplayName
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        container.wantsLayer = true
        container.observeTheme { view, palette in
            view.layer?.backgroundColor = palette.nsColor(.surface).cgColor
        }

        let title = ThemedLabel(
            string: contributedView.name, role: .primaryText, textRole: .heading)
        let attribution = ThemedLabel(
            string: extensionDisplayName, role: .secondaryText, textRole: .body)
        let explanation = ThemedLabel(
            string: "This view's content is provided by the extension, "
                + "which needs an extension host this app does not run yet.",
            role: .tertiaryText,
            textRole: .caption)
        // `ThemedLabel` is built as a single-line caption, which is right for
        // every other caller and wrong for a sentence.
        explanation.cell?.wraps = true
        explanation.cell?.usesSingleLineMode = false
        explanation.lineBreakMode = .byWordWrapping
        explanation.maximumNumberOfLines = 0
        explanation.alignment = .center
        title.alignment = .center
        attribution.alignment = .center

        let stack = NSStackView(views: [title, attribution, explanation])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(
                greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: container.trailingAnchor, constant: -16),
            explanation.widthAnchor.constraint(lessThanOrEqualToConstant: 320)
        ])
        view = container
    }
}
