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
    private let workingDirectory: String
    private let branch: String

    public init(
        id: UUID,
        title: String,
        edges: [String],
        project: String,
        workingDirectory: String,
        branch: String
    ) {
        self.id = id
        self.title = title
        self.edges = edges
        self.project = project
        self.workingDirectory = workingDirectory
        self.branch = branch
        super.init()
    }

    /// The persisted `project_tabs.group_id` — the group's id, which is what
    /// a project tab *is*. Not `project_tabs.id`: that names one member row,
    /// one per edge the group is drawn on, and a script handed one of those
    /// would be holding an edge rather than the tab it can see.
    @objc var uniqueID: String { self.id.uuidString }

    @objc var name: String { self.title }

    /// The edges this tab is currently drawn on — plural, because a tab group
    /// spans every enabled edge, and empty is a real answer for a group whose
    /// edges have all been disabled.
    @objc var tabEdges: [String] { self.edges }

    @objc var tabProject: String { self.project }

    /// Backs the sdef's `project tab` property `working directory`.
    @objc var tabWorkingDirectory: String { self.workingDirectory }

    /// Backs the sdef's `project tab` property `branch`.
    @objc var tabBranch: String { self.branch }

    public override nonisolated var objectSpecifier: NSScriptObjectSpecifier? {
        applicationElementSpecifier(key: "projectTabs") { self.uniqueID }
    }
}
