//
//  LanguageServersPanelViewController.swift
//  AgenticToolkit
//

import AppKit
import Combine
import Foundation
import SwiftUI

import AgenticToolkitCore
import AgenticToolkitCoreUI
import AgenticToolkitCoreMacOS
import AgenticToolkitLanguage

/// Settings panel for the language servers the editor talks LSP to.
///
/// Structurally a sibling of `MCPServersPanelViewController`: a split view
/// controller holding one sub-panel that hosts the SwiftUI editor, reading and
/// writing through the supplied `SettingsStore` — non-secret rows to the regular
/// provider, secret environment values to the secure one.
///
/// **It takes a publisher of open projects, not a window manager.** A language
/// server is per project, so the status half of this panel has to follow
/// projects opening and closing; taking `ProjectWindowManager` would put a
/// window manager in the dependencies of a settings panel and make the whole
/// thing untestable without a window. The host wires the publisher
/// (`dependency-injection`).
@MainActor
public final class LanguageServersPanelViewController: ComposableSettings.SettingsPanelSplitViewController {

    private let store: SettingsStore
    private let statusModel: LanguageServerStatusModel

    /// - Parameter openProjectCount: how many project windows are open, which
    ///   is not the same as `projects.count` — a window whose language services
    ///   could not be built contributes no project here, and the empty state
    ///   must still say "not running", not "no project open".
    public init(
        store: SettingsStore,
        projects: some Publisher<[LanguageServerStatusModel.Project], Never>,
        openProjectCount: some Publisher<Int, Never>
    ) {
        self.store = store
        self.statusModel = LanguageServerStatusModel(projects: projects, openProjectCount: openProjectCount)
        super.init(with: ComposableSettings.SettingsPanelDescriptor(
            title: "Language Servers",
            icon: NSImage(systemSymbolName: "curlybraces", accessibilityDescription: nil)
        ))
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var helpContent: ComposableSettings.PanelHelp? {
        Self.serversHelp
    }

    /// Shared with the sub-panel, because the split shows whichever topic is
    /// selected and there is only one sub-panel — so the two would otherwise
    /// say the same thing twice (`dry`).
    ///
    /// **The Status topic describes only what the panel can back.** Its
    /// neighbour in the MCP panel promises a live indicator its view model does
    /// not implement, which is a defect this one is written not to repeat: every
    /// sentence below names something `LanguageServerStatusModel` actually
    /// reports — the five states, one line per open project, and the failure's
    /// own stderr.
    static let serversHelp = ComposableSettings.PanelHelp(topics: [
        .init(
            title: "Language Servers",
            body: "A language server speaks the Language Server Protocol and is what "
                + "gives the editor completion, diagnostics, hover documentation and "
                + "jump-to-definition for a language. Each row is one server the app "
                + "knows how to start, and the languages it claims decide which files "
                + "it is asked about."
        ),
        .init(
            title: "Command and Environment",
            body: "A server is described the way a shell would launch it: an absolute "
                + "path to the executable, its arguments, and environment variables. An "
                + "absolute path rather than a bare name, because the app is launched "
                + "from Finder and does not inherit your shell's PATH. Values marked "
                + "secret are kept in your login Keychain rather than in the settings "
                + "file, so a token a server needs never lands in plain text."
        ),
        .init(
            title: "Root Markers",
            body: "A server is rooted at a workspace directory, and root markers are how "
                + "that directory is found: starting at the project directory, the app "
                + "walks upwards looking for the first of these names — Package.swift, "
                + ".git, whatever the language uses — and roots the server at the "
                + "directory holding it. If nothing matches, the project directory is "
                + "used."
        ),
        .init(
            title: "Status",
            body: "Language servers run per project, so the status beneath each row is "
                + "one line per open project — and with no project window open there is "
                + "nothing to run and nothing to report. A line reads idle before the "
                + "server has been asked to start, starting during its handshake, "
                + "running once the handshake finished and the editor can use it, "
                + "stopped after it has been shut down, and failed if it died or never "
                + "started. A failed line carries the reason and, when the server wrote "
                + "anything before dying, what it wrote on its error output — which is "
                + "usually where a wrong command path or a missing dependency says so. "
                + "A server whose row is switched off, or which no project has started, "
                + "reads as not running."
        )
    ])

    public override func viewDidLoad() {
        super.viewDidLoad()
        addPanel(LanguageServersListPanelViewController(store: store, statusModel: statusModel))
    }
}

/// Single sub-panel hosting the SwiftUI editor.
@MainActor
private final class LanguageServersListPanelViewController: ComposableSettings.SettingsPanelViewController {

    private let viewModel: LanguageServersListViewModel

    init(store: SettingsStore, statusModel: LanguageServerStatusModel) {
        self.viewModel = LanguageServersListViewModel(store: store, statusModel: statusModel)
        super.init(with: ComposableSettings.SettingsPanelDescriptor(
            title: "Servers",
            icon: NSImage(systemSymbolName: "list.bullet", accessibilityDescription: nil)
        ))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var helpContent: ComposableSettings.PanelHelp? {
        LanguageServersPanelViewController.serversHelp
    }

    /// The sidebar's search cannot read a SwiftUI panel's controls, so this
    /// panel names what it is about — including the features a user would think
    /// to search for rather than the machinery that provides them.
    override var searchKeywords: [String] {
        ["language server", "lsp", "sourcekit", "completion", "diagnostics", "hover", "definition"]
    }

    override func loadView() {
        self.view = Self.hostingView(
            for: LanguageServersListView(viewModel: viewModel).themedRoot())
    }
}

// MARK: - View model

/// The list half of the panel: the configurations, and the status rows keyed so
/// a row can find its own.
///
/// The status half is not re-derived here — it is `LanguageServerStatusModel`'s,
/// and this only republishes it grouped by configuration so a row does not scan
/// the whole list on every redraw.
@MainActor
final class LanguageServersListViewModel: ObservableObject {

    @Published var configurations: [LanguageServerConfiguration] = []
    @Published var statusesByConfiguration: [UUID: [LanguageServerStatusRow]] = [:]
    @Published var hasOpenProject = false

    private let store: SettingsStore
    private var cancellables: Set<AnyCancellable> = []

    init(store: SettingsStore, statusModel: LanguageServerStatusModel) {
        self.store = store

        store.publisher(for: UserSettings.languageServerConfigurations)
            .sink { [weak self] in self?.configurations = $0 }
            .store(in: &cancellables)

        // Grouped from the value the publisher *delivered*. Reading
        // `statusModel.rows` back inside the sink would read the previous
        // array, because `@Published` fires from `willSet`.
        statusModel.$rows
            .map { rows in Dictionary(grouping: rows, by: \.configurationID) }
            .sink { [weak self] in self?.statusesByConfiguration = $0 }
            .store(in: &cancellables)

        statusModel.$hasOpenProject
            .sink { [weak self] in self?.hasOpenProject = $0 }
            .store(in: &cancellables)
    }

    func setEnabled(_ id: UUID, enabled: Bool) {
        var current = configurations
        guard let index = current.firstIndex(where: { $0.id == id }) else { return }
        current[index].isEnabled = enabled
        store.set(current, for: UserSettings.languageServerConfigurations)
    }

    /// Removes the configuration **and** the secrets stored under its id.
    ///
    /// Both halves, exactly as `MCPServersListViewModel.remove` does: the
    /// secrets live in the Keychain under the configuration's id, and dropping
    /// only the configuration would leave a token behind that nothing can ever
    /// name again.
    func remove(_ id: UUID) {
        let next = configurations.filter { $0.id != id }
        store.set(next, for: UserSettings.languageServerConfigurations)

        var secrets = store.get(UserSettings.languageServerSecrets)
        if secrets.removeValue(forKey: id.uuidString) != nil {
            store.set(secrets, for: UserSettings.languageServerSecrets)
        }
    }

    func add(_ configuration: LanguageServerConfiguration) {
        var current = configurations
        current.append(configuration)
        store.set(current, for: UserSettings.languageServerConfigurations)
    }
}

// MARK: - SwiftUI views

private struct LanguageServersListView: View {

    @ObservedObject var viewModel: LanguageServersListViewModel
    @State private var showingAdd = false

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Configured Servers")
                    .font(theme.font(.heading))
                Spacer()
                Button("Add Server…") { showingAdd = true }
                    .accessibilityIdentifier("language-servers.add")
            }

            if viewModel.configurations.isEmpty {
                Text("No language servers configured.")
                    .foregroundStyle(theme.secondaryText)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.configurations.enumerated()), id: \.element.id) { index, config in
                        LanguageServerRow(
                            configuration: config,
                            statuses: viewModel.statusesByConfiguration[config.id] ?? [],
                            hasOpenProject: viewModel.hasOpenProject,
                            onToggle: { viewModel.setEnabled(config.id, enabled: $0) },
                            onRemove: { viewModel.remove(config.id) }
                        )
                        if index < viewModel.configurations.count - 1 {
                            Divider()
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        // Fills the pane and top-anchors in it — a *minimum* here would be the
        // panel telling the window how big to be.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showingAdd) {
            LanguageServerAddSheet(
                onCommit: { configuration in
                    viewModel.add(configuration)
                    showingAdd = false
                },
                onCancel: { showingAdd = false }
            )
        }
    }
}

private struct LanguageServerRow: View {

    let configuration: LanguageServerConfiguration
    let statuses: [LanguageServerStatusRow]
    let hasOpenProject: Bool
    let onToggle: (Bool) -> Void
    let onRemove: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(configuration.name)
                        .font(theme.font(.body))
                    Text(configuration.languageIds.joined(separator: ", "))
                        .font(theme.font(.caption))
                        .foregroundStyle(theme.secondaryText)
                    Text(commandSummary)
                        .font(theme.font(.caption))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { configuration.isEnabled },
                    set: { onToggle($0) }
                ))
                .labelsHidden()
                .help("Enabled")
                .accessibilityIdentifier("language-servers.enabled.\(configuration.id.uuidString.lowercased())")

                Button(action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove server")
                .accessibilityIdentifier("language-servers.remove.\(configuration.id.uuidString.lowercased())")
            }

            statusArea
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var statusArea: some View {
        if !hasOpenProject {
            // Not an error and not "off": a language server only exists inside
            // a project, so with no window open there is nothing to report.
            Text("No project open — language servers run per project.")
                .font(theme.font(.caption))
                .foregroundStyle(theme.secondaryText)
        } else if statuses.isEmpty {
            Text("Not running")
                .font(theme.font(.caption))
                .foregroundStyle(theme.secondaryText)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(statuses) { status in
                    LanguageServerStatusLine(status: status)
                }
            }
        }
    }

    private var commandSummary: String {
        let arguments = configuration.arguments.joined(separator: " ")
        return "\(configuration.command) \(arguments)".trimmingCharacters(in: .whitespaces)
    }
}

private struct LanguageServerStatusLine: View {

    let status: LanguageServerStatusRow

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(colour)
                    .frame(width: 8, height: 8)
                Text("\(status.projectName) — \(label)")
                    .font(theme.font(.caption))
                    .foregroundStyle(theme.secondaryText)
            }
            if !status.failureReason.isEmpty {
                Text(status.failureReason)
                    .font(theme.font(.caption))
                    .foregroundStyle(theme.danger)
                    .lineLimit(2)
            }
            if !status.standardErrorText.isEmpty {
                Text(status.standardErrorText)
                    .font(theme.font(.caption))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
        }
    }

    /// Three roles rather than five colours: running is good, failed is bad, and
    /// the three transient states are neither — colouring them apart would make
    /// a handshake look like an event.
    private var colour: Color {
        switch status.kind {
        case .running: return theme.success
        case .failed: return theme.danger
        case .idle, .starting, .stopped: return theme.secondaryText
        }
    }

    private var label: String {
        switch status.kind {
        case .idle: return "Idle"
        case .starting: return "Starting…"
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .failed: return "Failed"
        }
    }
}

private struct LanguageServerAddSheet: View {

    var onCommit: (LanguageServerConfiguration) -> Void
    var onCancel: () -> Void

    @Environment(\.theme) private var theme
    @State private var name: String = ""
    @State private var languageIdsText: String = ""
    @State private var command: String = ""
    @State private var argumentsText: String = ""
    @State private var rootMarkersText: String = ".git"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Language Server")
                .font(theme.font(.heading))

            Form {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("language-servers.add.name")
                TextField("Language IDs", text: $languageIdsText)
                    .help("Comma-separated LSP language ids, e.g. swift, objective-c")
                    .accessibilityIdentifier("language-servers.add.language-ids")
                TextField("Command", text: $command)
                    .help("Absolute path to the server executable, e.g. /usr/bin/sourcekit-lsp")
                    .accessibilityIdentifier("language-servers.add.command")
                TextField("Arguments", text: $argumentsText)
                    .help("Space-separated arguments")
                    .accessibilityIdentifier("language-servers.add.arguments")
                TextField("Root Markers", text: $rootMarkersText)
                    .help(LanguageServerRegistry.rootMarkersHelpText)
                    .accessibilityIdentifier("language-servers.add.root-markers")
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("language-servers.add.cancel")
                Button("Add") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
                    .accessibilityIdentifier("language-servers.add.commit")
            }
        }
        .padding(20)
        .frame(minWidth: 440)
    }

    private var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard !command.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return !Self.list(from: languageIdsText).isEmpty
    }

    private func commit() {
        onCommit(LanguageServerConfiguration(
            name: name.trimmingCharacters(in: .whitespaces),
            languageIds: Self.list(from: languageIdsText),
            command: command.trimmingCharacters(in: .whitespaces),
            arguments: argumentsText.split(whereSeparator: \.isWhitespace).map(String.init),
            rootMarkers: Self.list(from: rootMarkersText)
        ))
    }

    /// Splits a comma-separated field, dropping empties so a trailing comma or
    /// a stray double comma does not become a language id nobody can see.
    private static func list(from text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
