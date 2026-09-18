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
/// runtime, and where from depends on the kind. A **webview** view is resolved
/// by `registerWebviewViewProvider`, which this host implements — so those
/// panes get the extension's own page as soon as its provider runs, through
/// `resolveWebview`. A **tree** view waits on `registerTreeDataProvider` or
/// `createTreeView`, neither of which exists yet, so those panes stay the
/// labelled empty pane that says so on its face.
@MainActor
public final class ViewsContributionPoint: ContributionPoint {

    /// What one extension contributed, as this point needs to remember it.
    private struct Contributed {
        let containers: [ContributedViewContainer]
        let views: [ContributedView]
    }

    /// The payload-per-extension and notes bookkeeping every point of this
    /// shape needs, kept once in `apple-core` rather than written out again
    /// here — including the withdraw-before-record that makes re-applying
    /// idempotent.
    private var registrations = ContributionRegistrations<Contributed, ContributedViewNote>()

    /// Every compromise made across every applied extension, in application
    /// order. The Extensions UI filters these by identifier at display time,
    /// which is why there is no pre-filtered accessor here.
    public var notes: [ContributedViewNote] { registrations.notes }

    /// Injected, never reached for globally: the registry is deliberately an
    /// instance, because a demo project and a real project need different view
    /// sets in one process (`dependency-injection`).
    private let registry: ComposableTabsViewRegistry

    /// Builds the live webview for a contributed webview view, or `nil` when
    /// nothing can — see `ContributedWebviewResolving`.
    ///
    /// **Settable and late-bound, deliberately.** This point is constructed
    /// with the window's registry, long before any extension host exists;
    /// `ExtensionsCoordinator` assigns this once it has built the installer.
    /// `WebviewPanelSerializer`'s restore closure is the precedent and the
    /// reason — the same ordering, solved the same way, rather than a second
    /// answer to it.
    ///
    /// `nil` until then, and a pane built in that window shows its placeholder.
    /// That is the honest answer for a pane built before the hosts are up, and
    /// it is not a state a user can reach: the panes are registered by `apply`,
    /// which the installer's own pass is what runs.
    public var resolveWebview: ContributedWebviewResolving?

    /// Called when a pane for a contributed view is built, whatever its kind —
    /// the `onView:<id>` activation event's trigger.
    ///
    /// `resolveWebview`'s pair, late-bound for the same reason and separate for
    /// the reason `ExtensionHostInstaller` gives at the two methods it stands
    /// in front of: resolving asks *the one extension that declared the view*
    /// for its page, while this is news any extension may have asked to hear,
    /// including about someone else's view. A tree view has no page to ask for
    /// and still fires this.
    public var onViewWillAppear: ((ContributedView) -> Void)?

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

        // Captured by value below rather than read back off the manifest at
        // factory time: the manifest is the one thing here that is allowed to
        // have gone away by the time a pane is built.
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
            ) { [weak self] _ in
                // Read at pane-build time, not captured: a window may build
                // this pane before or after the hosts come up, and the factory
                // outlives both. `self` weakly for the same reason the closure
                // exists at all — the registry holds it, and this point is
                // owned by a coordinator that can go first.
                //
                // The broadcast goes first, and unconditionally: an extension
                // woken by `onView:` may be the one that then registers the
                // provider the line below looks for, and a tree view — which
                // never reaches that line — is just as much a pane appearing.
                self?.onViewWillAppear?(view)
                guard view.kind == .webview, let resolve = self?.resolveWebview else {
                    return ExtensionViewPlaceholderViewController(
                        view: view, extensionDisplayName: displayName)
                }
                return ExtensionWebviewViewController(
                    view: view, extensionDisplayName: displayName, resolve: resolve)
            }
        }

        registrations.record(
            Contributed(containers: built.containers, views: built.views),
            notes: built.notes,
            for: manifest.identifier)
    }

    /// Withdrawal here is more than forgetting: the panes were handed to a
    /// registry a window reads, so they come back out of it first.
    public func withdraw(extensionIdentifier: String) {
        for view in registrations.payload(for: extensionIdentifier)?.views ?? [] {
            registry.unregister(ComposableTabsViewID(view.registryID))
        }
        registrations.remove(extensionIdentifier)
    }

    public func containers(for extensionIdentifier: String) -> [ContributedViewContainer] {
        registrations.payload(for: extensionIdentifier)?.containers ?? []
    }

    public func views(for extensionIdentifier: String) -> [ContributedView] {
        registrations.payload(for: extensionIdentifier)?.views ?? []
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
/// lie: the extension ships the code that fills a tree, and this host does not
/// run that code yet.
///
/// A **webview** view shows this too, but only until its provider resolves —
/// see `ExtensionWebviewViewController`, which is what swaps it out. The
/// sentence differs between the two because the situations do: one is waiting
/// on this host, the other on the extension.
@MainActor
public final class ExtensionViewPlaceholderViewController: NSViewController {

    /// The widest the explanation is allowed to be: the ceiling its constraint
    /// enforces, and the ceiling on the width it wraps at. One constant because
    /// two literals fifteen lines apart are two numbers that can drift, and
    /// nothing — not the compiler, not a test — would catch the drift.
    private static let explanationWidth: CGFloat = 320

    /// Inset from each side of the pane, matching the stack's own leading and
    /// trailing constraints below.
    private static let explanationInset: CGFloat = 16

    /// Why this pane is empty, in the one sentence a person reads.
    ///
    /// Two sentences because there are two reasons, and telling a user their
    /// extension's webview needs a host feature that in fact exists would send
    /// them looking in the wrong place (`fail-fast`, applied to a person).
    private static func explanation(for kind: ContributedView.Kind) -> String {
        switch kind {
        case .tree:
            return "This view's content is provided by the extension, through a tree data "
                + "provider API the extension host does not implement yet."
        case .webview:
            return "This view's content is drawn by the extension, and it has not drawn any "
                + "yet — its webview view provider has not run."
        }
    }

    private let contributedView: ContributedView
    private let extensionDisplayName: String

    /// Held because its wrap width is not knowable in `loadView` — see
    /// `viewDidLayout`.
    private var explanation: NSTextField?

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
            string: Self.explanation(for: contributedView.kind),
            role: .tertiaryText,
            textRole: .caption)
        // `ThemedLabel` is built as a single-line caption, which is right for
        // every other caller and wrong for a sentence.
        explanation.cell?.wraps = true
        explanation.cell?.usesSingleLineMode = false
        explanation.lineBreakMode = .byWordWrapping
        explanation.maximumNumberOfLines = 0
        explanation.alignment = .center
        self.explanation = explanation
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
                greaterThanOrEqualTo: container.leadingAnchor,
                constant: Self.explanationInset),
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: container.trailingAnchor,
                constant: -Self.explanationInset),
            explanation.widthAnchor.constraint(
                lessThanOrEqualToConstant: Self.explanationWidth)
        ])
        view = container
    }

    /// The width a multi-line `NSTextField` computes its intrinsic *height*
    /// against. Nothing else tells it: the `widthAnchor` above is a ceiling,
    /// not a width, so in a pane narrower than
    /// `explanationWidth + 2 * explanationInset` the label is narrower than the
    /// ceiling and a static value would overestimate — which lays the sentence
    /// out clipped in exactly the narrow panes an auxiliary extension view is
    /// likeliest to be given. So it is measured here rather than guessed, and
    /// re-measured whenever the pane resizes.
    ///
    /// Each of the three operations catches something the others do not.
    /// `bounds.width - 2 * inset` is the width available to the *stack*, which
    /// is an upper bound on the label's width rather than the label's width —
    /// they coincide only because the sentence is the widest thing in the stack
    /// at every size that matters, and would stop coinciding if the stack ever
    /// gained a wider sibling. `min` with the ceiling keeps a wide pane from
    /// claiming more width than the `widthAnchor` will actually grant, which
    /// would under-compute the height and clip the sentence at the *wide* end.
    /// `max(0, …)` is for the collapsed pane: these panes register
    /// `isCollapsible: true`, `ComposableTabs` collapses through
    /// `NSSplitViewItem.isCollapsed`, and zoom collapses every item off the
    /// zoomed path — all of which lay this view out at zero width, where the
    /// subtraction alone yields `-2 * explanationInset`. AppKit documents `0`
    /// as "no maximum" and says nothing whatever about negatives, so the floor
    /// trades an undefined value for a defined one. "No maximum" is itself only
    /// harmless because a collapsed pane draws nothing.
    public override func viewDidLayout() {
        super.viewDidLayout()
        explanation?.preferredMaxLayoutWidth = max(
            0, min(Self.explanationWidth, view.bounds.width - 2 * Self.explanationInset))
    }
}
