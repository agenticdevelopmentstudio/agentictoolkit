#if canImport(AppKit)
import AgenticToolkitHubService
import AgenticToolkitHTDV
import AppKit
import Foundation

/// Everything a script can ask about the hub window's content, as one
/// `Encodable` value.
///
/// It lives in HubKit rather than in the app target because the state lives in
/// HubKit's controllers, and only HubKit can read it without making their
/// internals public: `MainWindowController.captureUIState()` assembles this
/// from `composition`, `root`, `signIn` and `hubWindow`, none of which the app
/// target can see.
///
/// One value rather than a command per question, because a script driving the
/// app has to know that the answers it got describe the *same* moment. Two
/// commands asked in sequence can straddle a phase change, and a harness that
/// saw `phase == "signIn"` and then an empty `signIn` section would be looking
/// at a window that had already moved on.
public struct HubUIState: Encodable, Sendable {

    public struct WindowInfo: Encodable, Sendable {
        public var title: String
        public var isVisible: Bool
        public var isKey: Bool
        /// `x`, `y`, `width`, `height` in screen coordinates.
        public var frame: [String: Double]

        public init(title: String, isVisible: Bool, isKey: Bool, frame: [String: Double]) {
            self.title = title
            self.isVisible = isVisible
            self.isKey = isKey
            self.frame = frame
        }
    }

    public struct SignIn: Encodable, Sendable {
        /// `"credentials"` or `"mfa"`.
        public var mode: String
        public var email: String
        public var code: String
        /// The one line the screen shows, error or informational — the same
        /// precedence `SignInViewController.render` uses, so a script reads what
        /// is on screen rather than which of two fields happened to be set.
        public var message: String?
        public var isBusy: Bool
        public var socialProviders: [String]
        /// The MFA method popup's item titles, in order.
        public var methods: [String]
        public var selectedMethod: String?

        public init(
            mode: String,
            email: String,
            code: String,
            message: String?,
            isBusy: Bool,
            socialProviders: [String],
            methods: [String],
            selectedMethod: String?
        ) {
            self.mode = mode
            self.email = email
            self.code = code
            self.message = message
            self.isBusy = isBusy
            self.socialProviders = socialProviders
            self.methods = methods
            self.selectedMethod = selectedMethod
        }
    }

    public struct WorkspaceItem: Encodable, Sendable {
        public var slug: String
        /// What the workspace popup shows — `HubWorkspace.listLabel`.
        public var label: String

        public init(slug: String, label: String) {
            self.slug = slug
            self.label = label
        }
    }

    public struct Item: Encodable, Sendable {
        public var id: String
        public var label: String
        public var sublabel: String?
        /// `"dot:<colour>"` or `"count:<n>"`, so the two badge kinds stay
        /// distinguishable in JSON — a bare `"red"` next to a bare `"3"` makes
        /// the reader guess which field they are looking at.
        public var badge: String?
        /// `"list"` or `"detail"`.
        public var leadsTo: String

        public init(id: String, label: String, sublabel: String?, badge: String?, leadsTo: String) {
            self.id = id
            self.label = label
            self.sublabel = sublabel
            self.badge = badge
            self.leadsTo = leadsTo
        }
    }

    public struct Level: Encodable, Sendable {
        public var index: Int
        public var title: String
        public var items: [Item]
        public var selectedItemID: String?
        public var emptyMessage: String
        public var createActionTitle: String?

        public init(
            index: Int,
            title: String,
            items: [Item],
            selectedItemID: String?,
            emptyMessage: String,
            createActionTitle: String?
        ) {
            self.index = index
            self.title = title
            self.items = items
            self.selectedItemID = selectedItemID
            self.emptyMessage = emptyMessage
            self.createActionTitle = createActionTitle
        }
    }

    public struct HTDV: Encodable, Sendable {
        public var levels: [Level]
        public var selection: [String]
        public var detailID: String?
        public var detailTitle: String?
        public var isLoading: Bool
        public var errorMessage: String?

        public init(
            levels: [Level],
            selection: [String],
            detailID: String?,
            detailTitle: String?,
            isLoading: Bool,
            errorMessage: String?
        ) {
            self.levels = levels
            self.selection = selection
            self.detailID = detailID
            self.detailTitle = detailTitle
            self.isLoading = isLoading
            self.errorMessage = errorMessage
        }
    }

    public var pid: Int32
    public var bundlePath: String
    /// The `AppCoordinator.Phase` case name: `launching`, `loadingWorkspace`,
    /// `signIn`, `ready`, `notMember` or `error`.
    public var phase: String
    /// `.error`'s payload. Carried separately from `notMemberMessage` because
    /// the two phases mean different things and a script diagnosing one must
    /// not have to guess which it is reading.
    public var errorMessage: String?
    /// `.notMember`'s payload — the workspace slug the account is not in.
    public var notMemberMessage: String?
    public var window: WindowInfo?
    public var signIn: SignIn?
    public var workspaces: [WorkspaceItem]
    public var selectedWorkspaceSlug: String?
    public var accountMenu: [String]
    /// The status strip's message, or `nil` when the strip is hidden.
    public var statusStrip: String?
    public var htdv: HTDV?
    /// Whether the permission walkthrough has been retired.
    public var permissionWalkthroughComplete: Bool
    /// `QuietWindowPresentation.isEnabled` — whether this copy keeps its
    /// windows behind the desktop picture. A driving script needs to know
    /// which mode the app it is talking to is in before it concludes anything
    /// from a screenshot or a window level.
    public var quietPresentation: Bool

    public init(
        pid: Int32,
        bundlePath: String,
        phase: String,
        errorMessage: String? = nil,
        notMemberMessage: String? = nil,
        window: WindowInfo? = nil,
        signIn: SignIn? = nil,
        workspaces: [WorkspaceItem] = [],
        selectedWorkspaceSlug: String? = nil,
        accountMenu: [String] = [],
        statusStrip: String? = nil,
        htdv: HTDV? = nil,
        permissionWalkthroughComplete: Bool = false,
        quietPresentation: Bool = false
    ) {
        self.pid = pid
        self.bundlePath = bundlePath
        self.phase = phase
        self.errorMessage = errorMessage
        self.notMemberMessage = notMemberMessage
        self.window = window
        self.signIn = signIn
        self.workspaces = workspaces
        self.selectedWorkspaceSlug = selectedWorkspaceSlug
        self.accountMenu = accountMenu
        self.statusStrip = statusStrip
        self.htdv = htdv
        self.permissionWalkthroughComplete = permissionWalkthroughComplete
        self.quietPresentation = quietPresentation
    }

    /// The snapshot as pretty-printed, key-sorted JSON — the one shape every
    /// `ui state` answer takes.
    ///
    /// Sorted keys so a harness can diff two snapshots textually; pretty so the
    /// person reading one in a terminal can. `"{}"` rather than a thrown error
    /// on failure: an AppleScript command returns a string, and an empty object
    /// is a value every caller's JSON parser already handles.
    public func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? encoder.encode(self),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }
}

// MARK: - Building the HTDV section from the live controller

extension HubUIState.Item {
    /// One rail row. `badge` is flattened to a string here rather than in the
    /// encoder so the JSON shape is visible in one place.
    public init(_ item: HTDVItem) {
        let badge: String?
        switch item.badge {
        case .dot(let color): badge = "dot:\(color)"
        case .count(let count): badge = "count:\(count)"
        case nil: badge = nil
        }
        self.init(
            id: item.id,
            label: item.label,
            sublabel: item.sublabel,
            badge: badge,
            leadsTo: item.leadsTo == .detail ? "detail" : "list"
        )
    }
}

extension HubUIState.HTDV {
    /// Reads the whole visible hierarchy off the controller.
    ///
    /// Everything here is already public API on `HTDVController`, deliberately:
    /// the scripting layer asks the same questions the views ask, so a snapshot
    /// can never describe a tree the views are not drawing.
    @MainActor
    public init(controller: HTDVController) {
        let levels = controller.levels.enumerated().map { index, level in
            HubUIState.Level(
                index: index,
                title: level.title,
                items: level.items.map(HubUIState.Item.init),
                selectedItemID: controller.selectedItem(atLevel: index)?.id,
                emptyMessage: level.emptyMessage,
                createActionTitle: level.createAction?.title
            )
        }
        self.init(
            levels: levels,
            selection: controller.selection,
            detailID: controller.detail?.id,
            detailTitle: controller.detail?.title,
            isLoading: controller.isLoading,
            errorMessage: controller.error?.message
        )
    }
}
#endif
