import AppKit
import Combine
import SwiftUI
import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import AIPluginKit

/// The "LLM Providers" settings panel — a topic/detail split (like "Theme") with
/// one sub-panel per configured provider. The sidebar lists the configurations
/// (titled "Providers" and themed by the framework); selecting one shows its
/// editor in the detail, whose title is the configuration's name. A footer under
/// the list carries add (`+`, opens the provider picker) / remove (`−`).
@MainActor
open class AIPanelViewController: ComposableSettings.SettingsPanelSplitViewController {

    public let pluginManager: AIPluginManager
    private let viewModel: LLMProvidersListViewModel
    private var addRemoveControl: NSSegmentedControl?
    private var selectionObserver: AnyCancellable?
    /// Plugin binaries that failed to load, surfaced as a trailing panel so a bad
    /// signature / ABI mismatch isn't silently invisible until a chat send fails.
    private var loadFailures: [PluginLoadFailure] = []

    public init(pluginManager: AIPluginManager) {
        self.pluginManager = pluginManager
        self.viewModel = LLMProvidersListViewModel(pluginManager: pluginManager)
        super.init(with: ComposableSettings.SettingsPanelDescriptor(
            title: "LLM Providers",
            icon: NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)
        ))
        // The sidebar lists multiple provider configurations, so title it in plural.
        sidebarTitle = "Providers"
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open override var helpContent: ComposableSettings.PanelHelp? {
        ComposableSettings.PanelHelp(topics: [
            .init(
                title: "Providers",
                body: "Each row is one configured way of reaching a model — a plugin "
                    + "(Claude, OpenAI, Google, or any OpenAI-compatible endpoint) plus "
                    + "the account details it needs. Add one with +, remove the selected "
                    + "one with −. Other panels that use a model choose from this list, "
                    + "so a provider configured once here is available everywhere."
            ),
            .init(
                title: "Keys and Secrets",
                body: "An API key you enter is stored in your login Keychain, never in a "
                    + "settings file or a database. Removing a provider removes its key "
                    + "along with it."
            ),
            .init(
                title: "Trying It Out",
                body: "The chat below a provider's settings talks to it directly, so you "
                    + "can confirm the key and the endpoint work — and pick a model — "
                    + "before anything else depends on them. A provider whose plugin "
                    + "failed to load says so instead, and can't be used until that is "
                    + "resolved."
            )
        ])
    }

    /// The provider editors are SwiftUI, so their controls cannot be read off
    /// the view tree; this names what the whole panel is about.
    open override var searchKeywords: [String] {
        ["llm", "provider", "api key", "model", "claude", "openai", "google", "endpoint"]
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        listViewController.setFooterView(makeFooter())

        // Load the plugin binaries so dlopen failures (bad signature, ABI mismatch)
        // become visible here instead of only surfacing as a generic error when a
        // chat/summary send later fails.
        loadFailures = pluginManager.loadAllPlugins().failures

        viewModel.onRequestAddProvider = { [weak self] in
            guard let self, let window = self.view.window else { return }
            ProviderPicker.present(over: window, rows: self.viewModel.pickerRows) { [weak self] available in
                guard let self else { return }
                self.viewModel.add(available)            // sets selectedId to the new config
                self.rebuildPanels(selecting: self.viewModel.selectedId)
            }
        }

        viewModel.onRequestChat = { [weak self] config in
            guard let self else { return }
            LLMChatWindowController.present(pluginManager: self.pluginManager, configuration: config)
        }

        rebuildPanels(selecting: viewModel.selectedId ?? viewModel.configurations.first?.id)

        // Enable the remove(−) segment only when a configuration is selected.
        selectionObserver = viewModel.$selectedId.sink { [weak self] id in
            self?.addRemoveControl?.setEnabled(id != nil, forSegment: 1)
        }
    }

    /// Rebuilds the detail panels to match the configurations list and selects
    /// `selectID`. Called on load and after any structural change (add / remove).
    ///
    /// Existing panels are REUSED by configuration id — only genuinely new
    /// configurations get a fresh panel, so an add/remove doesn't discard the
    /// in-progress edits of configurations it never touched.
    private func rebuildPanels(selecting selectID: UUID?) {
        let configs = viewModel.configurations
        let existing = Dictionary(
            panels.compactMap { ($0 as? ProviderConfigPanelViewController).map { ($0.config.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        var rebuilt: [any ComposableSettingsPanel] = configs.map { config in
            existing[config.id] ?? ProviderConfigPanelViewController(
                config: config,
                viewModel: viewModel,
                onRenamed: { [weak self] in self?.refreshRows() }
            )
        }
        if !loadFailures.isEmpty {
            rebuilt.append(PluginLoadFailuresPanel(failures: loadFailures))
        }
        setPanels(rebuilt)
        if let index = configs.firstIndex(where: { $0.id == selectID }) {
            selectPanel(at: index)
        } else if !rebuilt.isEmpty {
            selectPanel(at: 0)
        }
    }

    // MARK: - Scripted / testable selection

    /// The names of the configured providers, in sidebar order (excludes the
    /// trailing plugin-load-failures panel, which isn't a provider configuration).
    public var configurationNames: [String] {
        panels.compactMap { ($0 as? ProviderConfigPanelViewController)?.descriptor.title }
    }

    /// Selects the provider configuration with the given name (its sidebar title),
    /// driving both the list highlight and the detail editor. Enables scripted /
    /// UI-test navigation of the inner Providers list, which — being a custom
    /// themed table — doesn't reliably respond to synthetic clicks. Returns false
    /// when no configuration has that name.
    @discardableResult
    public func selectConfiguration(named name: String) -> Bool {
        guard let index = panels.firstIndex(where: { $0.descriptor.title == name }) else { return false }
        selectPanel(at: index)
        return true
    }

    /// Opens the LLM Chat window on the selected configuration and hands back its
    /// view model, so automation can drive a chat whose text field doesn't take
    /// synthetic input. Returns nil when no configuration is selected.
    ///
    /// The chat left this panel (see `LLMProviderEditorView`), so the scripted
    /// "test chat" verbs now reach it through its own window — the surface a user
    /// would drive by hand.
    @discardableResult
    public func presentChat() -> AIChatViewModel? {
        guard let id = viewModel.selectedId,
              let config = viewModel.configuration(for: id) else { return nil }
        LLMChatWindowController.present(pluginManager: pluginManager, configuration: config)
        return LLMChatWindowController.current?.chatViewModel
    }

    /// Sends a message through the selected configuration's chat. Returns false
    /// when no configuration is selected.
    @discardableResult
    public func sendTestMessage(_ text: String) -> Bool {
        guard let viewModel = presentChat() else { return false }
        viewModel.sendMessage(text)
        return true
    }

    /// The chat already open on the selected configuration, or `nil` when there is
    /// no chat window, nothing is selected, or the open window is pointed at a
    /// different provider. Never opens or switches one — this is the read side.
    private func openChatViewModel() -> AIChatViewModel? {
        guard let id = viewModel.selectedId,
              let controller = LLMChatWindowController.current,
              controller.window?.isVisible == true,
              controller.selection?.configuration.id == id else { return nil }
        return controller.chatViewModel
    }

    /// The selected configuration's chat transcript as newline-separated
    /// `role: text` lines. Empty when no chat is open on that configuration.
    ///
    /// Reads the open window rather than presenting one. Presenting is what
    /// `sendTestMessage` does, and it rebuilds the transcript whenever the window
    /// was showing a different provider — so a *getter* that presented could
    /// destroy the very conversation it was asked to report, and always answered
    /// "" when it did.
    public func testChatTranscript() -> String {
        guard let viewModel = openChatViewModel() else { return "" }
        return viewModel.messages.map { "\($0.role.scriptingLabel): \($0.text)" }.joined(separator: "\n")
    }

    /// Re-reads the sidebar row titles from the existing panels after an in-place
    /// rename, without recreating them, then keeps the selected row highlighted.
    private func refreshRows() {
        listViewController.setPanels(panels)
        if let index = viewModel.configurations.firstIndex(where: { $0.id == viewModel.selectedId }) {
            listViewController.selectPanel(at: index)
        }
    }

    // MARK: - Footer

    private func makeFooter() -> NSView {
        let addRemove = NSSegmentedControl()
        addRemove.segmentCount = 2
        let plus = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add provider")
        let minus = NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove provider")
        addRemove.setImage(plus, forSegment: 0)
        addRemove.setImage(minus, forSegment: 1)
        addRemove.setWidth(28, forSegment: 0)
        addRemove.setWidth(28, forSegment: 1)
        addRemove.trackingMode = .momentary
        addRemove.segmentStyle = .smallSquare
        addRemove.target = self
        addRemove.action = #selector(addRemoveClicked(_:))
        addRemove.setToolTip("Add a provider", forSegment: 0)
        addRemove.setToolTip("Remove the selected provider", forSegment: 1)
        addRemove.setEnabled(viewModel.selectedId != nil, forSegment: 1)
        addRemoveControl = addRemove

        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        bar.spacing = 6
        bar.addView(addRemove, in: .leading)
        bar.translatesAutoresizingMaskIntoConstraints = false

        let separator = ThemedSeparatorView(role: .border)
        let footer = NSStackView(views: [separator, bar])
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 0
        footer.translatesAutoresizingMaskIntoConstraints = false
        for sub in [separator, bar] {
            sub.widthAnchor.constraint(equalTo: footer.widthAnchor).isActive = true
        }
        return footer
    }

    @objc private func addRemoveClicked(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: viewModel.onRequestAddProvider?()
        case 1: removeSelected()
        default: break
        }
    }

    private func removeSelected() {
        guard let id = viewModel.selectedId,
              let config = viewModel.configurations.first(where: { $0.id == id }) else {
            RefusalFeedback.announce()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Delete “\(config.name)”?"
        alert.informativeText = "This removes the configuration and its stored settings, including any API key."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true

        let confirmDelete: () -> Void = { [weak self] in
            guard let self else { return }
            // Land on the previous row (or the first) after the delete.
            let ids = self.viewModel.configurations.map(\.id)
            let previous = ids.firstIndex(of: id).flatMap { $0 > 0 ? ids[$0 - 1] : nil }
            self.viewModel.remove(id)
            self.rebuildPanels(selecting: previous ?? self.viewModel.configurations.first?.id)
        }

        if let window = view.window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn { confirmDelete() }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            confirmDelete()
        }
    }
}

/// One configuration's detail panel: its title (the config name) is the sidebar
/// row label + detail-pane title; its body is the SwiftUI editor.
@MainActor
private final class ProviderConfigPanelViewController: ComposableSettings.SettingsPanelViewController {

    let config: AIProviderConfiguration
    private let viewModel: LLMProvidersListViewModel
    private let onRenamed: () -> Void
    private var nameObserver: AnyCancellable?

    init(config: AIProviderConfiguration, viewModel: LLMProvidersListViewModel, onRenamed: @escaping () -> Void) {
        self.config = config
        self.viewModel = viewModel
        self.onRenamed = onRenamed
        super.init(with: ComposableSettings.SettingsPanelDescriptor(
            title: config.name,
            icon: NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)
        ))
        // Keep the sidebar row title + detail title in sync when this config is
        // renamed in the editor.
        nameObserver = viewModel.$configurations
            .compactMap { configs in configs.first(where: { $0.id == config.id })?.name }
            .removeDuplicates()
            .sink { [weak self] name in
                guard let self, self.descriptor.title != name else { return }
                self.descriptor.title = name
                self.onRenamed()
            }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var searchKeywords: [String] {
        ["provider", "api key", "endpoint", "model", config.name]
    }

    override func loadView() {
        let editor = LLMProviderEditorView(configuration: config, viewModel: viewModel)
        self.view = Self.hostingView(for: editor.themedRoot())
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // Selecting this row shows this panel — record it as the active selection
        // (drives the footer's remove target).
        viewModel.selectedId = config.id
    }
}
