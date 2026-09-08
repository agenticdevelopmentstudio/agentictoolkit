import AppKit

/// A tab in a project window, as Cocoa Scripting sees it.
///
/// A value: it is made fresh each time `tabs` is read, because everything it
/// carries is a copy of what the window controller already holds and a cached
/// wrapper would be one more thing to invalidate when a tab is renamed.
///
/// One of these per *tab group*, not per edge. A project-level tab is drawn
/// once on every enabled edge under one shared title, so a script that saw two
/// objects both called "Tab 1" would be seeing an implementation detail rather
/// than what is on screen. Which edges it is drawn on is `edges`.
@MainActor
@objc(ScriptableProjectTab)
public final class ScriptableProjectTab: NSObject {

    private let id: UUID
    private let title: String
    private let edges: [String]
    private let project: String

    public init(id: UUID, title: String, edges: [String], project: String) {
        self.id = id
        self.title = title
        self.edges = edges
        self.project = project
        super.init()
    }

    /// The persisted `project_tabs.id`.
    @objc var uniqueID: String { self.id.uuidString }

    @objc var name: String { self.title }

    /// The edges this tab is currently drawn on — plural, because a tab group
    /// spans every enabled edge, and empty is a real answer for a group whose
    /// edges have all been disabled.
    @objc var tabEdges: [String] { self.edges }

    @objc var tabProject: String { self.project }

    public override nonisolated var objectSpecifier: NSScriptObjectSpecifier? {
        final class Box: @unchecked Sendable { var value: NSScriptObjectSpecifier? }
        let box = Box()
        MainActor.assumeIsolated {
            guard let appDescription = NSApp.classDescription as? NSScriptClassDescription else { return }
            box.value = NSUniqueIDSpecifier(
                containerClassDescription: appDescription,
                containerSpecifier: nil,
                key: "projectTabs",
                uniqueID: self.uniqueID)
        }
        return box.value
    }
}
