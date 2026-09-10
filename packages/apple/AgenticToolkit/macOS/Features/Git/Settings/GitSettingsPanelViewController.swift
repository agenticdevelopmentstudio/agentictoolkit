import AgenticToolkitCore
import AgenticToolkitCoreUI
import AppKit

/// Thrown by a rename's queued operation when the new key fails to set
/// *and* restoring the old key/value also fails -- the setting is genuinely
/// gone. Carries both underlying errors, rather than only the restore
/// failure, so `showError`'s message tells the user their setting was lost,
/// not merely that a second, unrelated-looking write failed.
struct GitConfigRestoreFailedError: LocalizedError {
    let setError: Error
    let restoreError: Error

    var errorDescription: String? {
        "Could not rename this setting (\(setError.localizedDescription)), and restoring its previous value "
            + "also failed (\(restoreError.localizedDescription)). This setting has been lost from "
            + "~/.gitconfig."
    }
}

/// Thrown by a rename's queued operation when the new key fails to set but
/// restoring the old key/value succeeds -- nothing was lost, but the rename
/// itself did not happen and the user should know why the row reverted.
struct GitConfigRenameFailedButRestoredError: LocalizedError {
    let setError: Error

    var errorDescription: String? {
        "Could not rename this setting (\(setError.localizedDescription)). Its previous value was restored."
    }
}

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
    /// were fired. A rename in `GitGlobalConfigTableView` fires `onRename`,
    /// which this panel enqueues as a *single* operation that unsets the old
    /// key, sets the new one, and -- if that set fails -- restores the old
    /// key/value before re-throwing (see `performRename`). Reloading after
    /// each write independently would also race: an unset's own reload
    /// could read global config *before* a later write has landed and
    /// redisplay the row as gone, only to have that stale read clobber the
    /// (later-arriving) correct one. Queuing every write and reloading
    /// exactly once, after the queue drains rather than after each entry,
    /// keeps a rename's steps atomic from the table's point of view.
    ///
    /// Not `private`: `GitSettingsPanelViewControllerTests` enqueues
    /// instrumented operations directly to test ordering and draining without
    /// going near git (see that file for why -- `GitClient` is a concrete
    /// `actor` with no protocol seam, so the queue itself is what is
    /// testable).
    var pendingWrites: [@Sendable () async throws -> Void] = []
    var isProcessingWrites = false

    /// Number of times `reloadGlobalConfig` has actually run, incremented
    /// synchronously at the top of that method, before its `await`. Not
    /// `private`: pins the call at the end of `processNextWriteIfNeeded`'s
    /// drain, so a test can assert it happened without racing the reload's
    /// own async body (which does a real, read-only `git config --list`) --
    /// the increment lands on the same synchronous tick the queue empties.
    var reloadCount = 0

    /// The most recent error message `processNextWriteIfNeeded`'s catch
    /// block passed to `configTable.showError`, mirrored here (not `private`)
    /// so a test can assert that call happened without reading the table's
    /// own label. `nil` until the first write fails; never cleared back to
    /// `nil` afterward (only `configTable`'s own label is cleared, by a
    /// successful `reloadGlobalConfig`).
    var lastWriteErrorMessage: String?

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
        // (see `GitGlobalConfigTableView.commitEdit`), but these callbacks do
        // not trust that alone before handing a key to git: an empty key
        // reaching `unsetGlobalConfig` becomes `git config --global --unset
        // ""` (an error git shows the user), and reaching `setGlobalConfig`
        // becomes a real, permanent write of an empty-named setting to
        // ~/.gitconfig. Every closure here captures `self` weakly: if this
        // panel is ever deallocated between a write being enqueued and it
        // actually running, that write silently no-ops (`self?.client...`
        // short-circuits) rather than erroring -- whatever it was supposed to
        // do (unset, set, or, for a rename, restore the old key) silently
        // never happens. Unreachable today -- every panel is constructed once
        // at launch and held for the process's lifetime by
        // `Features.settingsCoordinator` -- so this is recorded, not fixed:
        // capturing `client` (an actor, not `self`) would close the hole
        // without needing `self` at all, but would also keep these closures
        // alive past a panel nothing else still holds a reference to, trading
        // an unreachable bug for a reachable retain cycle. Revisit if panels
        // ever become lazily created or replaced.
        configTable.onSet = { [weak self] key, value in
            guard !key.isEmpty else { return }
            self?.enqueueWrite { [weak self] in try await self?.client.setGlobalConfig(key: key, value: value) }
        }
        configTable.onUnset = { [weak self] key in
            guard !key.isEmpty else { return }
            self?.enqueueWrite { [weak self] in try await self?.client.unsetGlobalConfig(key: key) }
        }
        // A rename delegates to `performRename` rather than inlining its own
        // unset/set/restore sequence here -- see that method's doc comment
        // for why (the same control flow must be what a test drives, not a
        // copy of it).
        configTable.onRename = { [weak self] oldKey, oldValue, newKey, newValue in
            guard !oldKey.isEmpty, !newKey.isEmpty else { return }
            self?.performRename(
                oldKey: oldKey,
                oldValue: oldValue,
                newKey: newKey,
                newValue: newValue,
                unset: { [weak self] key in try await self?.client.unsetGlobalConfig(key: key) },
                set: { [weak self] key, value in try await self?.client.setGlobalConfig(key: key, value: value) }
            )
        }
        group.addSettingSubview(configTable)
        return group
    }

    /// Renames a global-config key as one queued operation: unset `oldKey`,
    /// set `newKey` to `newValue`, and -- if that set fails after the unset
    /// already succeeded -- attempt to restore `oldKey` to `oldValue` before
    /// re-throwing. Both failure outcomes are reported, never swallowed:
    /// `GitConfigRenameFailedButRestoredError` if the restore succeeds,
    /// `GitConfigRestoreFailedError` (carrying both underlying errors) if it
    /// does not -- losing a setting must be loud, never silent.
    ///
    /// `unset`/`set` are the two git writes this performs, taken as
    /// parameters instead of reaching `client` directly. `makeGlobalConfigGroup`
    /// passes `client.unsetGlobalConfig`/`client.setGlobalConfig`; tests pass
    /// throwing stand-ins. Either way this method -- not a hand-rolled copy
    /// of its control flow -- is what runs: a dropped restore, a swapped
    /// argument, or a wrong error type here fails every test that calls it,
    /// the same way it would fail in production.
    ///
    /// All three steps run inside a single `enqueueWrite` call, so a third
    /// edit can never land between the unset and the restore -- a second,
    /// separate `enqueueWrite` for the restore would not guarantee that (see
    /// `pendingWrites`' doc comment).
    func performRename(
        oldKey: String,
        oldValue: String,
        newKey: String,
        newValue: String,
        unset: @escaping @Sendable (_ key: String) async throws -> Void,
        set: @escaping @Sendable (_ key: String, _ value: String) async throws -> Void
    ) {
        enqueueWrite {
            try await unset(oldKey)
            do {
                try await set(newKey, newValue)
            } catch {
                do {
                    try await set(oldKey, oldValue)
                } catch let restoreError {
                    throw GitConfigRestoreFailedError(setError: error, restoreError: restoreError)
                }
                throw GitConfigRenameFailedButRestoredError(setError: error)
            }
        }
    }

    private func reloadGlobalConfig() {
        reloadCount += 1
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
    /// unset/set/restore steps from racing each other's refresh.
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
                self?.lastWriteErrorMessage = error.localizedDescription
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
