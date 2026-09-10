import AgenticToolkitCore
import AgenticToolkitCoreUI
import AppKit

/// Settings › Git: which executable runs, how status refreshes behave, and
/// the user's global configuration.
@MainActor
public final class GitSettingsPanelViewController: ComposableSettings.SettingsPanelViewController {
    let executableStatusLabel = ThemedLabel(role: .tertiaryText, textRole: .caption)

    private let client: GitClient
    private let configTable = GitGlobalConfigTableView()
    private var executableObserver: UserSettingObserver<String>?
    private var reloadTask: Task<Void, Never>?

    /// Global-configuration writes queued from the table, in the order they
    /// were fired. Renaming a row in `GitGlobalConfigTableView` fires
    /// `onUnset(oldKey)` immediately followed, synchronously, by
    /// `onSet(newKey, value)` -- see that type's `commitEdit`. Reloading after
    /// each write independently would race: the unset's own reload could read
    /// global config *before* the set's write has landed and redisplay the row
    /// as gone, only to have that stale read clobber the (later-arriving)
    /// correct one. Queuing every write and reloading exactly once, after the
    /// queue drains rather than after each entry, keeps a rename's two halves
    /// atomic from the table's point of view.
    ///
    /// Not `private`: `GitSettingsPanelViewControllerTests` enqueues
    /// instrumented operations directly to test ordering and draining without
    /// going near git (see that file for why -- `GitClient` is a concrete
    /// `actor` with no protocol seam, so the queue itself is what is
    /// testable).
    var pendingWrites: [@Sendable () async throws -> Void] = []
    var isProcessingWrites = false

    public convenience init() {
        self.init(client: .shared)
    }

    public init(client: GitClient) {
        self.client = client
        super.init(with: ComposableSettings.SettingsPanelDescriptor(
            title: "Git",
            icon: NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)
        ))
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { nil }

    deinit {
        reloadTask?.cancel()
    }

    public override var helpContent: ComposableSettings.PanelHelp? {
        ComposableSettings.PanelHelp(topics: [
            .init(
                title: "Executable",
                body: "Every git command the app runs uses the executable configured here. Choose a "
                    + "different binary if the app should not use the one on your PATH."
            ),
            .init(
                title: "Status Refresh",
                body: "Controls how the file browser and tab bar refresh git status: the per-invocation "
                    + "timeout and whether submodules are included."
            ),
            .init(
                title: "Global Configuration",
                body: "Everything below is your ~/.gitconfig. Edits write with git config --global as "
                    + "soon as you commit each cell."
            )
        ])
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        settingsView.addGroup(makeExecutableGroup())
        settingsView.addGroup(makeStatusGroup())
        settingsView.addGroup(makeGlobalConfigGroup())
        reloadGlobalConfig()
    }

    // MARK: Executable

    private func makeExecutableGroup() -> ComposableSettings.GroupView {
        let group = ComposableSettings.GroupView(withTitle: "Executable")
        let pathModel = ComposableSettings.ViewModel<String>(
            title: "Path",
            setting: UserSettings.gitExecutablePath,
            explanation: "Absolute path of the git binary."
        )
        let pathView = ComposableSettings.TextEditView(with: pathModel)
        pathView.textField.accessibilityID("settings.git.executable-field")
        group.addSettingSubview(pathView)

        let choose = ComposableSettings.ButtonViewModel(title: "Choose…") { [weak self] in
            self?.chooseExecutable()
        }
        let chooseView = ComposableSettings.ButtonView(viewModel: choose)
        chooseView.button.accessibilityID("settings.git.choose-executable")
        group.addSettingSubview(chooseView)

        executableStatusLabel.accessibilityID("settings.git.executable-status")
        // A long path clipped with no ellipsis hides exactly the part the
        // user most needs when the status reads "not found" -- the tail.
        executableStatusLabel.lineBreakMode = .byTruncatingMiddle
        group.addSettingSubview(executableStatusLabel, style: .continuation)
        refreshExecutableStatus(path: UserSettings.gitExecutablePath.value)
        executableObserver = UserSettingObserver(UserSettings.gitExecutablePath) { [weak self] newValue in
            self?.refreshExecutableStatus(path: newValue)
        }
        return group
    }

    private func refreshExecutableStatus(path: String) {
        if FileManager.default.isExecutableFile(atPath: path) {
            executableStatusLabel.stringValue = "Found: \(path)"
        } else {
            executableStatusLabel.stringValue = "Executable not found at \(path)"
        }
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: UserSettings.gitExecutablePath.value).deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserSettings.gitExecutablePath.value = url.path
    }

    // MARK: Status refresh

    private func makeStatusGroup() -> ComposableSettings.GroupView {
        let group = ComposableSettings.GroupView(withTitle: "Status Refresh")
        let timeout = ComposableSettings.RangeViewModel<Int>(
            title: "Timeout (seconds)",
            setting: UserSettings.gitStatusTimeoutSeconds,
            minValue: 1,
            maxValue: 60
        )
        let timeoutView = ComposableSettings.IntegerFieldView(viewModel: timeout)
        timeoutView.textField.accessibilityID("settings.git.timeout-field")
        group.addSettingSubview(timeoutView)

        let submodules = ComposableSettings.ViewModel<Bool>(
            title: "Include submodules",
            setting: UserSettings.gitStatusIncludesSubmodules,
            explanation: "When off, status runs with --ignore-submodules."
        )
        let submodulesView = ComposableSettings.CheckboxView(with: submodules)
        submodulesView.toggle.accessibilityID("settings.git.include-submodules")
        group.addSettingSubview(submodulesView)
        return group
    }

    // MARK: Global configuration

    private func makeGlobalConfigGroup() -> ComposableSettings.GroupView {
        let group = ComposableSettings.GroupView(withTitle: "Global Configuration")
        group.addSettingSubview(ComposableSettings.ExplanationView(
            withText: "Edits are written with git config --global as you commit each cell."
        ))
        // The table already refuses to commit a placeholder with an empty key
        // (see `GitGlobalConfigTableView.commitEdit`), but this callback does
        // not trust that alone before handing a key to git: an empty key
        // reaching `unsetGlobalConfig` becomes `git config --global --unset
        // ""` (an error git shows the user), and reaching `setGlobalConfig`
        // becomes a real, permanent write of an empty-named setting to
        // ~/.gitconfig. Both closures capture `self` weakly: if this panel is
        // ever deallocated between a rename's two queued halves, the second
        // one silently no-ops (`self?.client...` short-circuits) rather than
        // erroring, leaving the old key unset and the new key never set.
        // Unreachable today -- every panel is constructed once at launch and
        // held for the process's lifetime by `Features.settingsCoordinator`
        // -- so this is recorded, not fixed: capturing `client` (an actor,
        // not `self`) would close the hole without needing `self` at all, but
        // would also keep this closure alive past a panel nothing else still
        // holds a reference to, trading an unreachable bug for a reachable
        // retain cycle. Revisit if panels ever become lazily created or
        // replaced.
        configTable.onSet = { [weak self] key, value in
            guard !key.isEmpty else { return }
            self?.enqueueWrite { [weak self] in try await self?.client.setGlobalConfig(key: key, value: value) }
        }
        configTable.onUnset = { [weak self] key in
            guard !key.isEmpty else { return }
            self?.enqueueWrite { [weak self] in try await self?.client.unsetGlobalConfig(key: key) }
        }
        group.addSettingSubview(configTable)
        return group
    }

    private func reloadGlobalConfig() {
        // Cancel any in-flight reload before starting another: without a
        // handle, a rapid sequence of writes could leave two reads racing
        // each other into `setEntries`, and nothing ever cancelled the first
        // one when the panel itself is torn down (see `deinit`).
        reloadTask?.cancel()
        let client = self.client
        reloadTask = Task { [weak self] in
            do {
                let entries = try await client.globalConfig()
                guard !Task.isCancelled else { return }
                self?.configTable.setEntries(entries)
                self?.configTable.showError("")
            } catch {
                guard !Task.isCancelled else { return }
                self?.configTable.showError(error.localizedDescription)
            }
        }
    }

    /// Appends one config write to `pendingWrites` and, if nothing is running,
    /// starts draining the queue. See `pendingWrites`' doc comment for why the
    /// queue -- rather than a reload per call -- is what keeps a rename's
    /// `onUnset`/`onSet` pair from racing each other's refresh.
    func enqueueWrite(_ operation: @escaping @Sendable () async throws -> Void) {
        pendingWrites.append(operation)
        processNextWriteIfNeeded()
    }

    func processNextWriteIfNeeded() {
        guard !isProcessingWrites, !pendingWrites.isEmpty else { return }
        isProcessingWrites = true
        let operation = pendingWrites.removeFirst()
        Task { [weak self] in
            do {
                try await operation()
            } catch {
                self?.configTable.showError(error.localizedDescription)
            }
            guard let self else { return }
            self.isProcessingWrites = false
            if self.pendingWrites.isEmpty {
                self.reloadGlobalConfig()
            } else {
                self.processNextWriteIfNeeded()
            }
        }
    }
}
