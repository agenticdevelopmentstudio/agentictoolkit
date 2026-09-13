import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreUI
import AgenticToolkitCoreMacOS

/// The modal "which project?" dialog — a `ProjectBrowserViewController` in
/// chooser mode with the two buttons a dialog owes the user.
///
/// App-modal rather than a sheet: this app has no window guaranteed to be on
/// screen when the question is asked (it can be asked from the menu bar with
/// nothing open at all), and a sheet with no parent cannot be dismissed.
@MainActor
public final class ProjectChooserWindow: NSWindowController, NSWindowDelegate {

    private let content: ProjectChooserContentViewController
    private var chosen: GitRepo?

    /// Runs the chooser and calls `onChoose` with the picked project, or not at
    /// all if the user cancels.
    public static func choose(
        from coordinator: ProjectsCoordinator,
        onChoose: @escaping (GitRepo) -> Void
    ) {
        let controller = ProjectChooserWindow(coordinator: coordinator)
        if let repo = controller.runModal() {
            onChoose(repo)
        }
    }

    public init(coordinator: ProjectsCoordinator) {
        self.content = ProjectChooserContentViewController(coordinator: coordinator)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Open Project"
        window.minSize = NSSize(width: 360, height: 300)
        super.init(window: window)

        window.contentViewController = content
        window.setContentSize(NSSize(width: 460, height: 480))
        window.center()
        window.accessibilityID("project-chooser.window")
        // The title bar's close button and ⌘W bypass Cancel and Open, so the
        // session has to be ended from the close notification too — see
        // `windowWillClose(_:)`.
        window.delegate = self

        content.onFinish = { [weak self] repo in self?.finish(with: repo) }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @discardableResult
    public func runModal() -> GitRepo? {
        guard let window else { return nil }
        // A menu bar app is often not the active app when this is asked for.
        NSApp.activateUnlessQuiet()
        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)
        window.orderOut(nil)
        return chosen
    }

    /// Closing the window is a cancel, and — more importantly — it is the one
    /// dismissal that does not go through Cancel or Open. Without this the
    /// modal session outlives its window: `NSApp.modalWindow` stays set to an
    /// invisible window, and AppKit spends the rest of the run disabling Quit,
    /// About, Settings… and every status-item command, because those are the
    /// items a modal session is supposed to suppress.
    public func windowWillClose(_ notification: Notification) {
        // `orderOut` after `stopModal` does not notify, but an explicit
        // `close()` from anywhere else would — only end a session we are in.
        guard NSApp.modalWindow === window else { return }
        finish(with: nil)
    }

    private func finish(with repo: GitRepo?) {
        chosen = repo
        NSApp.stopModal()
    }
}

/// The chooser's content: the browser plus Cancel/Open. Split out so the
/// browser has a real parent view controller and gets its appearance callbacks
/// (that is where it takes first responder).
@MainActor
private final class ProjectChooserContentViewController: NSViewController {

    /// Called with the chosen project, or `nil` when the user cancels.
    var onFinish: ((GitRepo?) -> Void)?

    private let browser: ProjectBrowserViewController
    /// Stock push buttons, deliberately. This is the Open dialog of a Mac app:
    /// the pair at the bottom right is a shape people have known for thirty
    /// years, and a hand-drawn substitute is a worse version of it
    /// (`native-controls`).
    private let openButton = NSButton(title: "Open", target: nil, action: nil)

    init(coordinator: ProjectsCoordinator) {
        self.browser = ProjectBrowserViewController(coordinator: coordinator, mode: .chooser)
        super.init(nibName: nil, bundle: nil)
        browser.onChoose = { [weak self] repo in self?.onFinish?(repo) }
        browser.onSelectionChange = { [weak self] repo in self?.openButton.isEnabled = repo != nil }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let container = ThemedBackgroundView(role: .windowBackground)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelChoosing(_:)))
        cancel.bezelStyle = .push
        cancel.keyEquivalent = "\u{1b}"
        cancel.accessibilityID("project-chooser.cancel")

        openButton.bezelStyle = .push
        // Return opens the selection, which also makes this the default button
        // AppKit tints — the one thing that tells the pair apart at a glance.
        openButton.keyEquivalent = "\r"
        openButton.target = self
        openButton.action = #selector(openChosen(_:))
        openButton.isEnabled = false
        openButton.accessibilityID("project-chooser.open")

        let buttons = NSStackView(views: [cancel, openButton])
        buttons.orientation = .horizontal
        buttons.spacing = 12
        buttons.translatesAutoresizingMaskIntoConstraints = false

        addChild(browser)
        let browserView = browser.view
        browserView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(browserView)
        container.addSubview(buttons)

        NSLayoutConstraint.activate([
            browserView.topAnchor.constraint(equalTo: container.topAnchor),
            browserView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            browserView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            browserView.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -16),

            // 20pt margins and a 72pt minimum button: the dialog metrics every
            // other Mac app uses, so this one does not read as homemade.
            buttons.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            buttons.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 20),
            cancel.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
            openButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])

        self.view = container
    }

    @objc private func openChosen(_ sender: Any?) {
        onFinish?(browser.selectedRepo)
    }

    @objc private func cancelChoosing(_ sender: Any?) {
        onFinish?(nil)
    }
}
