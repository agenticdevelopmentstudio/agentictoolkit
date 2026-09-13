import Foundation
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
/// The platform's base view controller type. Detail factories and create
/// actions vend/receive this.
public typealias PlatformViewController = NSViewController
#elseif canImport(UIKit)
import UIKit
/// The platform's base view controller type. Detail factories and create
/// actions vend/receive this.
public typealias PlatformViewController = UIViewController
#endif

/// What selecting an item reveals to its right: another rail of items, or a
/// detail pane.
public enum HTDVLeadsTo: Sendable, Hashable {
    case list
    case detail
}

/// Semantic badge colours; each platform view maps these to system colours.
public enum HTDVBadgeColor: Sendable, Hashable {
    case red, orange, yellow, green, blue, gray
}

/// Trailing badge on a rail row.
public enum HTDVBadge: Sendable, Hashable {
    case dot(HTDVBadgeColor)
    case count(Int)
}

/// The "+" affordance on a rail. `perform` receives the hosting view
/// controller so it can present UI.
public struct HTDVCreateAction: Sendable {
    public let title: String
    public let perform: @MainActor @Sendable (PlatformViewController) async -> Void

    public init(
        title: String,
        perform: @escaping @MainActor @Sendable (PlatformViewController) async -> Void
    ) {
        self.title = title
        self.perform = perform
    }
}

/// One row in a rail.
public struct HTDVItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let sublabel: String?
    public let systemImage: String?
    public let dividerAfter: Bool
    public let leadsTo: HTDVLeadsTo
    public let badge: HTDVBadge?

    public init(
        id: String,
        label: String,
        sublabel: String? = nil,
        systemImage: String? = nil,
        dividerAfter: Bool = false,
        leadsTo: HTDVLeadsTo = .list,
        badge: HTDVBadge? = nil
    ) {
        self.id = id
        self.label = label
        self.sublabel = sublabel
        self.systemImage = systemImage
        self.dividerAfter = dividerAfter
        self.leadsTo = leadsTo
        self.badge = badge
    }
}

/// One rail: a titled list of items plus what to show when it is empty and
/// how to add to it.
public struct HTDVLevel: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let items: [HTDVItem]
    public let emptyMessage: String
    public let createAction: HTDVCreateAction?

    public init(
        id: String,
        title: String,
        items: [HTDVItem],
        emptyMessage: String = "Nothing here yet",
        createAction: HTDVCreateAction? = nil
    ) {
        self.id = id
        self.title = title
        self.items = items
        self.emptyMessage = emptyMessage
        self.createAction = createAction
    }
}

/// A detail pane factory. `make` runs on the main actor when the pane is
/// first shown.
public struct HTDVDetail: Sendable {
    public let id: String
    public let title: String
    public let make: @MainActor @Sendable () -> PlatformViewController

    public init(
        id: String,
        title: String,
        make: @escaping @MainActor @Sendable () -> PlatformViewController
    ) {
        self.id = id
        self.title = title
        self.make = make
    }
}

/// What lies beneath a selected path.
public enum HTDVChild: Sendable {
    case level(HTDVLevel)
    case detail(HTDVDetail)
    case empty
}

/// Vends the tree. Implementations are typically actors or `@unchecked
/// Sendable` classes wrapping a client.
public protocol HTDVDataSource: AnyObject, Sendable {
    func rootLevel() async throws -> HTDVLevel
    func child(for path: [HTDVItem]) async throws -> HTDVChild
}
