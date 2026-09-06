import AppKit

/// Wraps a `() -> Void` closure as an `NSMenuItem` target/selector pair so
/// `MenuManager` can build menu items from `MenuContribution`s without any
/// per-feature `@objc` action plumbing. The host retains one of these per
/// menu item.
@MainActor
public final class ClosureMenuItemTarget: NSObject {

    private let action: () -> Void
    private let isEnabled: () -> Bool

    public init(action: @escaping () -> Void, isEnabled: @escaping () -> Bool = { true }) {
        self.action = action
        self.isEnabled = isEnabled
    }

    @objc(performMenuAction:) public func performMenuAction(_ sender: Any?) {
        action()
    }

    @objc public func validateMenuItem(_ item: NSMenuItem) -> Bool {
        isEnabled()
    }
}

/// Applies per-open updates to the items of one menu: `MenuContribution
/// .isHidden` visibility and, separately, item retitling (`addRetitle(_:
/// title:)`).
///
/// Neither rides along on `validateMenuItem(_:)`: AppKit's automatic
/// validation is about enabling, an item that has already hidden itself is
/// not reliably asked again — which would make hiding a one-way trip — and
/// validation cannot change a title at all. `menuNeedsUpdate(_:)` runs for
/// the whole menu every time it opens, hidden items included, so both rules
/// and retitles are re-asked on every open.
@MainActor
public final class MenuUpdateDelegate: NSObject, NSMenuDelegate {

    private var rules: [(item: NSMenuItem, isHidden: () -> Bool)] = []
    private var retitles: [(item: NSMenuItem, title: () -> String)] = []

    public func add(_ item: NSMenuItem, isHidden: @escaping () -> Bool) {
        rules.append((item, isHidden))
    }

    /// A title AppKit's validation cannot change for you: `validateMenuItem(_:)`
    /// answers only "is this enabled". Re-asked on every menu open, alongside
    /// the visibility rules.
    public func addRetitle(_ item: NSMenuItem, title: @escaping () -> String) {
        retitles.append((item, title))
    }

    public var isEmpty: Bool { rules.isEmpty && retitles.isEmpty }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        for rule in rules {
            rule.item.isHidden = rule.isHidden()
        }
        for retitle in retitles {
            retitle.item.title = retitle.title()
        }
    }
}

/// Prior name, kept because ATK also ships to Stenographer, which is not
/// checked out in this branch and which grep therefore cannot clear — only
/// two call sites exist here, both in `Whippet/Whippet/App/MenuManager.swift`.
public typealias MenuVisibilityDelegate = MenuUpdateDelegate
